#!/usr/bin/env python3
import importlib.util
import io
import json
import os
import pty
import select
import stat
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest
from unittest import mock


ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
PATH = os.path.join(ROOT, "libexec", "rtide", "composer.py")
SPEC = importlib.util.spec_from_file_location("rtide_composer", PATH)
COMPOSER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = COMPOSER
SPEC.loader.exec_module(COMPOSER)
PNG = b"\x89PNG\r\n\x1a\n" + b"fixture"


class ComposerTests(unittest.TestCase):
    def test_buffer_edits_multiline_at_cursor(self):
        value = COMPOSER.Buffer("alpha\ngamma")
        value.cursor = 6
        value.insert("beta\n")
        self.assertEqual(value.text, "alpha\nbeta\ngamma")
        value.move_vertical(1)
        self.assertGreaterEqual(value.cursor, 11)
        value.backspace()
        self.assertNotEqual(value.text, "alpha\nbeta\ngamma")
        value = COMPOSER.Buffer("alpha beta gamma")
        value.move_word(-1)
        self.assertEqual(value.cursor, 11)
        value.move_word(-1)
        self.assertEqual(value.cursor, 6)
        value.move_word(1)
        self.assertEqual(value.cursor, 11)

    def test_render_is_bounded_to_terminal_height(self):
        composer = COMPOSER.Composer.__new__(COMPOSER.Composer)
        composer.attachments = []
        composer.message = ""
        composer._drawn = 0
        composer.stdout = io.StringIO()
        with mock.patch.object(COMPOSER.shutil, "get_terminal_size",
                               return_value=os.terminal_size((20, 3))):
            composer._render(COMPOSER.Buffer("one\ntwo\nthree\nfour"), "ready")
        self.assertEqual(composer.stdout.getvalue().count("\x1b[2K"), 3)

    def test_path_staging_snapshots_bytes_and_permissions(self):
        with tempfile.TemporaryDirectory() as workspace:
            source = os.path.join(workspace, "source image.png")
            with open(source, "wb") as handle:
                handle.write(PNG)
            store = COMPOSER.AttachmentStore(workspace)
            attachment = store.stage_path(source)
            with open(source, "wb") as handle:
                handle.write(PNG + b"changed")
            with open(attachment.path, "rb") as handle:
                self.assertEqual(handle.read(), PNG)
            self.assertEqual(stat.S_IMODE(os.stat(attachment.path).st_mode), 0o600)
            store.cleanup()
            self.assertFalse(os.path.exists(attachment.path))
            self.assertTrue(os.path.exists(source))

    def test_invalid_and_oversized_files_fail_before_staging(self):
        with tempfile.TemporaryDirectory() as workspace:
            store = COMPOSER.AttachmentStore(workspace, max_bytes=8)
            invalid = os.path.join(workspace, "bad.bin")
            with open(invalid, "wb") as handle:
                handle.write(b"unknown")
            with self.assertRaisesRegex(COMPOSER.ComposerError, "unsupported"):
                store.stage_path(invalid)
            image = os.path.join(workspace, "large.png")
            with open(image, "wb") as handle:
                handle.write(PNG)
            with self.assertRaisesRegex(COMPOSER.ComposerError, "exceeds"):
                store.stage_path(image)

    def test_wayland_clipboard_discovers_and_reads_explicit_mime(self):
        listing = mock.Mock(returncode=0, stdout=b"text/plain\nimage/png\n")
        image = mock.Mock(returncode=0, stdout=PNG)
        runner = mock.Mock(side_effect=[listing, image])
        with tempfile.TemporaryDirectory() as workspace, \
                mock.patch.object(COMPOSER.shutil, "which", return_value="/usr/bin/wl-paste"):
            store = COMPOSER.AttachmentStore(workspace)
            item = store.stage_clipboard({"WAYLAND_DISPLAY": "wayland-1"}, runner)
            self.assertEqual(item.mime, "image/png")
            self.assertEqual(runner.call_args_list[1].args[0],
                             ["wl-paste", "--no-newline", "--type", "image/png"])

    def test_clipboard_text_only_and_unavailable_are_clear(self):
        listing = mock.Mock(returncode=0, stdout=b"text/plain\n")
        with tempfile.TemporaryDirectory() as workspace, \
                mock.patch.object(COMPOSER.shutil, "which", return_value="/usr/bin/wl-paste"):
            store = COMPOSER.AttachmentStore(workspace)
            with self.assertRaisesRegex(COMPOSER.ComposerError, "contains text"):
                store.stage_clipboard({"WAYLAND_DISPLAY": "wayland-1"}, mock.Mock(return_value=listing))
        with tempfile.TemporaryDirectory() as workspace, \
                mock.patch.object(COMPOSER.shutil, "which", return_value=None):
            store = COMPOSER.AttachmentStore(workspace)
            with self.assertRaisesRegex(COMPOSER.ComposerError, "unavailable"):
                store.stage_clipboard({}, mock.Mock())

    def test_external_editor_round_trip_and_cancel(self):
        def edit(command):
            with open(command[-1], "w") as handle:
                handle.write("edited\ntext")
            return mock.Mock(returncode=0)
        with tempfile.TemporaryDirectory() as workspace:
            result = COMPOSER.external_edit("draft", workspace,
                                            {"EDITOR": "fake-editor"}, edit)
            self.assertEqual(result, "edited\ntext")
            cancelled = COMPOSER.external_edit(
                "draft", workspace, {"EDITOR": "fake-editor"},
                lambda _command: mock.Mock(returncode=1))
            self.assertEqual(cancelled, "draft")

    def test_pty_ctrl_j_and_enter_submit_exact_multiline_text(self):
        master, slave = pty.openpty()
        program = textwrap.dedent(f"""
            import importlib.util, json, sys, tempfile
            spec = importlib.util.spec_from_file_location('composer_child', {PATH!r})
            module = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = module
            spec.loader.exec_module(module)
            with tempfile.TemporaryDirectory() as workspace:
                result = module.Composer(workspace).read_submission('ready')
                print('RESULT=' + json.dumps(result.text))
        """)
        proc = subprocess.Popen([sys.executable, "-c", program], stdin=slave,
                                stdout=slave, stderr=slave, close_fds=True)
        os.close(slave)
        time.sleep(0.1)
        os.write(master, b"first\x0asecond\r")
        output = bytearray()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and proc.poll() is None:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    output.extend(os.read(master, 4096))
                except OSError:
                    break
        proc.wait(timeout=2)
        while select.select([master], [], [], 0)[0]:
            try:
                output.extend(os.read(master, 4096))
            except OSError:
                break
        os.close(master)
        self.assertEqual(proc.returncode, 0, output.decode(errors="replace"))
        marker = output.decode(errors="replace").split("RESULT=", 1)[1]
        self.assertEqual(json.loads(marker.strip()), "first\nsecond")

    def test_pty_bracketed_paste_and_modified_enter_do_not_submit_early(self):
        master, slave = pty.openpty()
        program = textwrap.dedent(f"""
            import importlib.util, json, sys, tempfile
            spec = importlib.util.spec_from_file_location('composer_paste_child', {PATH!r})
            module = importlib.util.module_from_spec(spec)
            sys.modules[spec.name] = module
            spec.loader.exec_module(module)
            with tempfile.TemporaryDirectory() as workspace:
                result = module.Composer(workspace).read_submission('ready')
                print('RESULT=' + json.dumps(result.text))
        """)
        proc = subprocess.Popen([sys.executable, "-c", program], stdin=slave,
                                stdout=slave, stderr=slave, close_fds=True)
        os.close(slave)
        time.sleep(0.1)
        os.write(master, b"\x1b[200~paste one\npaste two\x1b[201~\x1b[13;2utail\r")
        output = bytearray()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline and proc.poll() is None:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    output.extend(os.read(master, 4096))
                except OSError:
                    break
        proc.wait(timeout=2)
        os.close(master)
        text = output.decode(errors="replace")
        self.assertEqual(proc.returncode, 0, text)
        self.assertEqual(json.loads(text.split("RESULT=", 1)[1].strip()),
                         "paste one\npaste two\ntail")


if __name__ == "__main__":
    unittest.main()
