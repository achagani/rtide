#!/usr/bin/env python3
"""Bounded terminal composer and private attachment staging for RTIDE."""

from __future__ import annotations

from dataclasses import dataclass
import mimetypes
import os
from pathlib import Path
import select
import shlex
import shutil
import subprocess
import tempfile
import termios
import tty
import uuid


DEFAULT_MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
DEFAULT_MAX_DRAFT_BYTES = 1024 * 1024
MAX_ATTACHMENTS = 8
PASTE_START = b"\x1b[200~"
PASTE_END = b"\x1b[201~"


class ComposerError(RuntimeError):
    pass


@dataclass(frozen=True)
class Attachment:
    id: str
    path: str
    name: str
    mime: str
    size: int

    @property
    def is_image(self):
        return self.mime in {"image/png", "image/jpeg"}


@dataclass(frozen=True)
class Submission:
    text: str
    attachments: tuple[Attachment, ...] = ()

    @property
    def empty(self):
        return not self.text and not self.attachments


def _mime_from_bytes(data, name=""):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", ".png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", ".jpg"
    guessed = mimetypes.guess_type(name)[0]
    if guessed and (guessed.startswith("text/") or guessed in {
            "application/json", "application/pdf", "application/xml"}):
        return guessed, Path(name).suffix.lower()
    raise ComposerError("unsupported attachment type; use PNG, JPEG, text, JSON, XML, or PDF")


class AttachmentStore:
    """Snapshots user input below ignored workspace runtime state."""

    def __init__(self, workspace, max_bytes=None):
        self.workspace = os.path.realpath(workspace)
        self.max_bytes = max_bytes or int(os.environ.get(
            "RTIDE_ATTACHMENT_MAX_BYTES", DEFAULT_MAX_ATTACHMENT_BYTES))
        attachment_root = os.path.join(self.workspace, ".rtide", "attachments")
        os.makedirs(attachment_root, mode=0o700, exist_ok=True)
        self._prune(attachment_root)
        self.root = os.path.join(
            attachment_root,
            f"{os.getpid()}-{uuid.uuid4().hex[:8]}",
        )
        os.makedirs(self.root, mode=0o700, exist_ok=True)
        os.chmod(self.root, 0o700)

    @staticmethod
    def _prune(root):
        for entry in os.scandir(root):
            if not entry.is_dir(follow_symlinks=False):
                continue
            try:
                pid = int(entry.name.partition("-")[0])
                os.kill(pid, 0)
            except ProcessLookupError:
                shutil.rmtree(entry.path, ignore_errors=True)
            except (ValueError, PermissionError, OSError):
                continue

    def _stage(self, data, name):
        if not data:
            raise ComposerError("attachment is empty")
        if len(data) > self.max_bytes:
            raise ComposerError(
                f"attachment exceeds {self.max_bytes // (1024 * 1024)} MiB limit")
        mime, suffix = _mime_from_bytes(data, name)
        identifier = uuid.uuid4().hex[:10]
        target = os.path.join(self.root, identifier + suffix)
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
        except Exception:
            try:
                os.unlink(target)
            except OSError:
                pass
            raise
        return Attachment(identifier, target, os.path.basename(name) or identifier,
                          mime, len(data))

    def stage_path(self, source):
        source = os.path.realpath(os.path.expanduser(source))
        try:
            info = os.stat(source, follow_symlinks=True)
        except OSError as exc:
            raise ComposerError(f"attachment is not readable: {source}") from exc
        if not os.path.isfile(source):
            raise ComposerError("attachment must be a regular file")
        if info.st_size > self.max_bytes:
            raise ComposerError(
                f"attachment exceeds {self.max_bytes // (1024 * 1024)} MiB limit")
        try:
            with open(source, "rb") as handle:
                data = handle.read(self.max_bytes + 1)
        except OSError as exc:
            raise ComposerError(f"attachment is not readable: {source}") from exc
        return self._stage(data, os.path.basename(source))

    def stage_clipboard(self, env=None, runner=subprocess.run):
        env = os.environ if env is None else env
        if env.get("WAYLAND_DISPLAY") and shutil.which("wl-paste"):
            listing = runner(["wl-paste", "--list-types"], capture_output=True,
                             timeout=2)
            if listing.returncode:
                raise ComposerError("could not inspect the Wayland clipboard")
            types = listing.stdout.decode(errors="replace").splitlines()
            mime = next((kind for kind in ("image/png", "image/jpeg")
                         if kind in types), None)
            if not mime:
                raise ComposerError("clipboard contains text, not a supported image")
            result = runner(["wl-paste", "--no-newline", "--type", mime],
                            capture_output=True, timeout=3)
        elif env.get("DISPLAY") and shutil.which("xclip"):
            listing = runner(["xclip", "-selection", "clipboard", "-t", "TARGETS", "-o"],
                             capture_output=True, timeout=2)
            types = listing.stdout.decode(errors="replace").splitlines()
            mime = next((kind for kind in ("image/png", "image/jpeg")
                         if kind in types), None)
            if not mime:
                raise ComposerError("clipboard contains text, not a supported image")
            result = runner(["xclip", "-selection", "clipboard", "-t", mime, "-o"],
                            capture_output=True, timeout=3)
        else:
            raise ComposerError("image clipboard unavailable; use /attach PATH")
        if result.returncode:
            raise ComposerError("clipboard image read failed")
        return self._stage(result.stdout, "clipboard.png" if mime == "image/png" else "clipboard.jpg")

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)
        parent = os.path.dirname(self.root)
        try:
            os.rmdir(parent)
        except OSError:
            pass


class Buffer:
    def __init__(self, text=""):
        self.text = text.replace("\r\n", "\n").replace("\r", "\n")
        self.cursor = len(self.text)

    def insert(self, value):
        value = value.replace("\r\n", "\n").replace("\r", "\n")
        self.text = self.text[:self.cursor] + value + self.text[self.cursor:]
        self.cursor += len(value)

    def backspace(self):
        if self.cursor:
            self.text = self.text[:self.cursor - 1] + self.text[self.cursor:]
            self.cursor -= 1

    def delete(self):
        if self.cursor < len(self.text):
            self.text = self.text[:self.cursor] + self.text[self.cursor + 1:]

    def move_vertical(self, delta):
        before = self.text[:self.cursor]
        line_start = before.rfind("\n") + 1
        column = self.cursor - line_start
        lines = self.text.split("\n")
        row = before.count("\n")
        target = max(0, min(len(lines) - 1, row + delta))
        self.cursor = sum(len(line) + 1 for line in lines[:target]) + min(column, len(lines[target]))

    def move_word(self, delta):
        if delta < 0:
            while self.cursor and self.text[self.cursor - 1].isspace():
                self.cursor -= 1
            while self.cursor and not self.text[self.cursor - 1].isspace():
                self.cursor -= 1
        else:
            while self.cursor < len(self.text) and not self.text[self.cursor].isspace():
                self.cursor += 1
            while self.cursor < len(self.text) and self.text[self.cursor].isspace():
                self.cursor += 1


def external_edit(text, workspace, env=None, runner=subprocess.run):
    env = os.environ if env is None else env
    editor = env.get("VISUAL") or env.get("EDITOR")
    if not editor:
        raise ComposerError("set $VISUAL or $EDITOR to use the external editor")
    draft_dir = os.path.join(workspace, ".rtide", "drafts")
    os.makedirs(draft_dir, mode=0o700, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix="draft-", suffix=".md", dir=draft_dir, text=True)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        result = runner(shlex.split(editor) + [path])
        if result.returncode:
            return text
        with open(path, encoding="utf-8") as handle:
            return handle.read().replace("\r\n", "\n").replace("\r", "\n")
    finally:
        try:
            os.unlink(path)
            os.rmdir(draft_dir)
        except OSError:
            pass


class Composer:
    """Small raw-terminal editor with a bounded scrolling viewport."""

    def __init__(self, workspace, store=None, history=None, stdin=None, stdout=None):
        self.workspace = os.path.realpath(workspace)
        self.store = store or AttachmentStore(workspace)
        self.history = history if history is not None else []
        self.stdin = stdin or os.fdopen(os.dup(0), "rb", buffering=0)
        self.stdout = stdout or os.fdopen(os.dup(1), "w", buffering=1)
        self.attachments = []
        self.message = ""
        self._drawn = 0
        # Bytes already read from the terminal but not yet consumed as keys.
        # A large read can carry a paste terminator plus the keystrokes that
        # follow it; those trailing bytes must be replayed, not discarded.
        self._pending = bytearray()

    def _read_byte(self):
        if self._pending:
            byte = bytes(self._pending[:1])
            del self._pending[:1]
            return byte
        return os.read(self.stdin.fileno(), 1)

    def _read_escape(self, first=b"\x1b"):
        value = bytearray(first)
        while (self._pending or select.select([self.stdin], [], [], 0.015)[0]) \
                and len(value) < 32:
            value.extend(self._read_byte())
            if bytes(value).endswith((b"~", b"u")) or bytes(value) in {
                    b"\x1b[A", b"\x1b[B", b"\x1b[C", b"\x1b[D", b"\x1b[H", b"\x1b[F"}:
                break
        return bytes(value)

    def _read_paste(self):
        limit = int(os.environ.get("RTIDE_COMPOSER_MAX_BYTES", DEFAULT_MAX_DRAFT_BYTES))
        data = bytearray()
        pending = bytearray(self._pending)
        self._pending = bytearray()
        while True:
            marker = pending.find(PASTE_END)
            if marker >= 0:
                data.extend(pending[:marker][:max(0, limit - len(data))])
                # Preserve input that arrived in the same read as the terminator.
                self._pending = bytearray(pending[marker + len(PASTE_END):])
                break
            # Hold back a partial terminator before flushing the safe prefix.
            safe = max(0, len(pending) - len(PASTE_END) + 1)
            data.extend(pending[:safe][:max(0, limit - len(data))])
            del pending[:safe]
            chunk = os.read(self.stdin.fileno(), 4096)
            if not chunk:
                break
            pending.extend(chunk)
        if len(data) >= limit:
            self.message = f"paste truncated at {limit} bytes"
        return bytes(data).decode("utf-8", errors="replace")

    def _display_lines(self, buffer):
        width = max(12, shutil.get_terminal_size((80, 3)).columns)
        logical = buffer.text.split("\n")
        rows = []
        cursor_row = cursor_col = 0
        offset = 0
        for line_no, line in enumerate(logical):
            chunks = [line[i:i + width - 5] for i in range(0, len(line), width - 5)] or [""]
            for chunk_no, chunk in enumerate(chunks):
                rows.append(("╰─❯ " if not rows else "    ") + chunk)
                line_pos = min(buffer.cursor - offset, len(line))
                if offset <= buffer.cursor <= offset + len(line) and chunk_no == line_pos // (width - 5):
                    cursor_row = len(rows) - 1
                    cursor_col = 5 + line_pos % (width - 5)
            offset += len(line) + 1
        return rows, cursor_row, cursor_col

    def _render(self, buffer, status):
        rows, cursor_row, cursor_col = self._display_lines(buffer)
        terminal_rows = shutil.get_terminal_size((80, 3)).lines
        viewport = max(1, min(8, terminal_rows - 1 - bool(self.attachments)))
        start = max(0, min(cursor_row, len(rows) - viewport))
        visible = rows[start:start + viewport]
        attachment_line = ""
        if self.attachments:
            tokens = [f"[{index + 1}:{item.name} {item.size / 1024:.1f}KiB]"
                      for index, item in enumerate(self.attachments)]
            attachment_line = "attachments " + " ".join(tokens)
        header = self.message or status
        lines = [header]
        if attachment_line:
            lines.append(attachment_line)
        lines.extend(visible)
        if self._drawn:
            self.stdout.write(f"\x1b[{self._drawn - 1}A\r")
        self.stdout.write("\x1b[?25l")
        for index, line in enumerate(lines):
            # ESC[2K erases the line but does not reset the column, and raw-mode
            # \n feeds without a carriage return. Without the \r each row starts
            # at the previous row's end column, indenting the prompt.
            self.stdout.write("\r\x1b[2K" + line)
            if index != len(lines) - 1:
                self.stdout.write("\n")
        if self._drawn > len(lines):
            for _ in range(self._drawn - len(lines)):
                self.stdout.write("\n\x1b[2K")
            self.stdout.write(f"\x1b[{self._drawn - len(lines)}A")
        target_row = 1 + bool(attachment_line) + cursor_row - start
        up = len(lines) - 1 - target_row
        self.stdout.write("\r" + (f"\x1b[{up}A" if up else "") + f"\x1b[{cursor_col}C\x1b[?25h")
        self.stdout.flush()
        self._drawn = len(lines)

    def _attachment_command(self, text):
        if text.startswith("/attach "):
            if len(self.attachments) >= MAX_ATTACHMENTS:
                raise ComposerError(f"at most {MAX_ATTACHMENTS} attachments are allowed")
            self.attachments.append(self.store.stage_path(text[8:].strip()))
            return True
        if text in {"/paste-image", "/clipboard"}:
            if len(self.attachments) >= MAX_ATTACHMENTS:
                raise ComposerError(f"at most {MAX_ATTACHMENTS} attachments are allowed")
            self.attachments.append(self.store.stage_clipboard())
            return True
        if text == "/attachments":
            self.message = ("attachments: " + ", ".join(
                f"{i + 1}={item.name} ({item.mime}, {item.size} bytes)"
                for i, item in enumerate(self.attachments))) if self.attachments else "attachments: none"
            return True
        if text.startswith("/remove"):
            words = text.split()
            if len(words) != 2 or not words[1].isdigit():
                raise ComposerError("usage: /remove NUMBER")
            index = int(words[1]) - 1
            if not 0 <= index < len(self.attachments):
                raise ComposerError("attachment number is out of range")
            item = self.attachments.pop(index)
            try:
                os.unlink(item.path)
            except OSError:
                pass
            return True
        return False

    def read_submission(self, status="RTIDE  ● ready · Enter send · Ctrl+J newline · Ctrl+G editor"):
        if not self.stdin.isatty():
            line = self.stdin.readline().decode("utf-8", errors="replace")
            if not line:
                raise EOFError
            return Submission(line.rstrip("\n"))
        buffer = Buffer()
        history_index = len(self.history)
        original = termios.tcgetattr(self.stdin.fileno())
        tty.setraw(self.stdin.fileno())
        self.stdout.write("\x1b[?2004h")
        try:
            while True:
                self._render(buffer, status)
                key = self._read_byte()
                self.message = ""
                if not key or key == b"\x04":
                    raise EOFError
                if key == b"\x03":
                    raise KeyboardInterrupt
                if key == b"\r":
                    try:
                        if self._attachment_command(buffer.text):
                            buffer = Buffer()
                            continue
                    except ComposerError as exc:
                        self.message = f"error: {exc}"
                        buffer = Buffer()
                        continue
                    submission = Submission(buffer.text, tuple(self.attachments))
                    if submission.empty:
                        continue
                    if buffer.text:
                        self.history.append(buffer.text)
                        del self.history[:-100]
                    self.attachments = []
                    self.stdout.write("\n")
                    return submission
                if key == b"\n":
                    buffer.insert("\n")
                elif key in {b"\x7f", b"\x08"}:
                    buffer.backspace()
                elif key == b"\x07":
                    try:
                        termios.tcsetattr(self.stdin.fileno(), termios.TCSADRAIN, original)
                        self.stdout.write("\n")
                        self.stdout.flush()
                        buffer = Buffer(external_edit(buffer.text, self.workspace))
                        self._drawn = 0
                    except ComposerError as exc:
                        self.message = f"error: {exc}"
                    finally:
                        tty.setraw(self.stdin.fileno())
                elif key == b"\x01":
                    buffer.cursor = buffer.text.rfind("\n", 0, buffer.cursor) + 1
                elif key == b"\x05":
                    end = buffer.text.find("\n", buffer.cursor)
                    buffer.cursor = len(buffer.text) if end < 0 else end
                elif key == b"\x0b":
                    end = buffer.text.find("\n", buffer.cursor)
                    end = len(buffer.text) if end < 0 else end
                    buffer.text = buffer.text[:buffer.cursor] + buffer.text[end:]
                elif key == b"\x1b":
                    sequence = self._read_escape(key)
                    if sequence == PASTE_START:
                        buffer.insert(self._read_paste())
                    elif sequence in {b"\x1b[13;2u", b"\x1b[27;2;13~"}:
                        buffer.insert("\n")
                    elif sequence == b"\x1b[D":
                        buffer.cursor = max(0, buffer.cursor - 1)
                    elif sequence == b"\x1b[C":
                        buffer.cursor = min(len(buffer.text), buffer.cursor + 1)
                    elif sequence == b"\x1b[1;5D":
                        buffer.move_word(-1)
                    elif sequence == b"\x1b[1;5C":
                        buffer.move_word(1)
                    elif sequence == b"\x1b[A":
                        if "\n" in buffer.text:
                            buffer.move_vertical(-1)
                        elif self.history and history_index:
                            history_index -= 1
                            buffer = Buffer(self.history[history_index])
                    elif sequence == b"\x1b[B":
                        if "\n" in buffer.text:
                            buffer.move_vertical(1)
                        elif history_index < len(self.history) - 1:
                            history_index += 1
                            buffer = Buffer(self.history[history_index])
                        elif history_index == len(self.history) - 1:
                            history_index = len(self.history)
                            buffer = Buffer()
                    elif sequence in {b"\x1b[H", b"\x1b[1~"}:
                        buffer.cursor = 0
                    elif sequence in {b"\x1b[F", b"\x1b[4~"}:
                        buffer.cursor = len(buffer.text)
                    elif sequence == b"\x1b[3~":
                        buffer.delete()
                    elif sequence in {b"\x1bv", b"\x1bV"}:
                        try:
                            if len(self.attachments) >= MAX_ATTACHMENTS:
                                raise ComposerError(f"at most {MAX_ATTACHMENTS} attachments are allowed")
                            self.attachments.append(self.store.stage_clipboard())
                        except ComposerError as exc:
                            self.message = f"error: {exc}"
                    elif sequence == b"\x1b":
                        buffer = Buffer()
                        for item in self.attachments:
                            try:
                                os.unlink(item.path)
                            except OSError:
                                pass
                        self.attachments = []
                        self.message = "draft cancelled"
                else:
                    if key[0] >= 0xC0:
                        length = 2 if key[0] < 0xE0 else (3 if key[0] < 0xF0 else 4)
                        for _ in range(length - 1):
                            key += self._read_byte()
                    buffer.insert(key.decode("utf-8", errors="replace"))
        finally:
            termios.tcsetattr(self.stdin.fileno(), termios.TCSADRAIN, original)
            self.stdout.write("\x1b[?2004l\x1b[?25h")
            self.stdout.flush()
