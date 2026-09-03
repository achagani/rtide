#!/usr/bin/env python3
"""Exercise typed fork creation through a real fzf popup and tmux client."""

import os
import pty
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ForkMenuE2ETest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="rtide-fork-menu-e2e-"))
        self.home = self.tmp / "home"
        self.project = self.tmp / "project"
        self.fake_bin = self.tmp / "bin"
        self.socket = str(self.tmp / "tmux.sock")
        (self.home / ".rtide").mkdir(parents=True)
        self.fake_bin.mkdir()
        fake_tweb = self.fake_bin / "tweb"
        fake_tweb.write_text(
            "#!/usr/bin/env bash\n"
            "case \"${1:-}\" in\n"
            "  status) printf '{\"tabs\":{\"tabs\":[{\"active\":true,\"url\":\"%s\"}]}}\\n' \"${FAKE_TWEB_STATUS_URL:-}\" ;;\n"
            "  open) exec sleep 300 ;;\n"
            "esac\n",
            encoding="utf-8",
        )
        fake_tweb.chmod(0o755)
        (self.project / ".rtide").mkdir(parents=True)
        (self.home / ".rtide/config").write_text(
            "provider=openai\nharness=codex\nmodel=test-model\n"
            "agent_lines=3\ntweb_pct=60\nshell=bash\n",
            encoding="utf-8",
        )
        (self.project / ".gitignore").write_text(".rtide/\n", encoding="utf-8")
        (self.project / "app.txt").write_text("baseline\n", encoding="utf-8")
        self.run_command("git", "-C", str(self.project), "init", "-q")
        self.run_command("git", "-C", str(self.project), "add", ".gitignore", "app.txt")
        self.run_command(
            "git", "-C", str(self.project), "-c", "user.name=test",
            "-c", "user.email=test@example.invalid", "commit", "-qm", "baseline",
        )
        self.run_command("git", "-C", str(self.project), "branch", "-M", "main")
        self.env = os.environ.copy()
        self.env.update(
            HOME=str(self.home),
            PATH=f"{self.fake_bin}:{self.env['PATH']}",
            RTIDE_FORK_NO_LAUNCH="1",
            RTIDE_ROOT=str(ROOT),
            TERM="xterm-256color",
        )
        self.client_pid = None
        self.master_fd = None

    def tearDown(self):
        self.tmux("kill-server", check=False)
        if self.client_pid:
            try:
                os.kill(self.client_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        if self.master_fd is not None:
            os.close(self.master_fd)
        shutil.rmtree(self.tmp, ignore_errors=True)

    def run_command(self, *args, check=True):
        return subprocess.run(
            args, check=check, text=True, capture_output=True, env=getattr(self, "env", None)
        )

    def tmux(self, *args, check=True):
        return self.run_command("tmux", "-S", self.socket, *args, check=check)

    def attach_client(self):
        master_fd, slave_fd = pty.openpty()
        pid = os.fork()
        if pid == 0:
            os.close(master_fd)
            os.setsid()
            os.dup2(slave_fd, 0)
            os.dup2(slave_fd, 1)
            os.dup2(slave_fd, 2)
            os.execvpe(
                "tmux", ["tmux", "-S", self.socket, "attach-session", "-t", "ui"], self.env
            )
        os.close(slave_fd)
        os.set_blocking(master_fd, False)
        self.client_pid = pid
        self.master_fd = master_fd

    def configure_session(self):
        self.tmux("new-session", "-d", "-s", "ui", "-n", "work", "-c", str(self.project))
        pane = self.tmux("display-message", "-p", "-t", "ui:work", "#{pane_id}").stdout.strip()
        self.tmux("set-option", "-p", "-t", pane, "@rtide-role", "nvim")
        for key in ("HOME", "PATH", "RTIDE_FORK_NO_LAUNCH", "RTIDE_ROOT"):
            self.tmux("set-environment", "-g", key, self.env[key])
        self.attach_client()
        time.sleep(0.5)
        return pane

    def open_manager(self, pane):
        return subprocess.Popen(
            [
                "tmux", "-S", self.socket, "display-popup", "-E", "-t", pane,
                "-w", "70%", "-h", "70%", "-d", str(self.project),
                str(ROOT / "bin/rtide"), "fork-menu", pane,
            ], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )

    def type_enter(self, value):
        os.write(self.master_fd, value.encode())
        time.sleep(0.2)
        os.write(self.master_fd, b"\r")

    @unittest.skipUnless(shutil.which("tmux") and shutil.which("fzf"), "tmux and fzf required")
    def test_unmatched_query_creates_exact_fork(self):
        name = "manager-popup-e2e"
        self.tmux("new-session", "-d", "-s", "ui", "-n", "work", "-c", str(self.project))
        pane = self.tmux("display-message", "-p", "-t", "ui:work", "#{pane_id}").stdout.strip()
        self.tmux("set-option", "-p", "-t", pane, "@rtide-role", "nvim")
        for key in ("HOME", "PATH", "RTIDE_FORK_NO_LAUNCH", "RTIDE_ROOT"):
            self.tmux("set-environment", "-g", key, self.env[key])
        self.attach_client()
        time.sleep(0.5)
        popup = subprocess.Popen(
            [
                "tmux", "-S", self.socket, "display-popup", "-E", "-t", pane,
                "-w", "70%", "-h", "70%", "-d", str(self.project),
                str(ROOT / "bin/rtide"), "fork-menu", pane,
            ],
            env=self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.addCleanup(lambda: popup.poll() is None and popup.kill())
        time.sleep(0.8)
        os.write(self.master_fd, name.encode())
        time.sleep(0.2)
        os.write(self.master_fd, b"\r")

        fork = self.tmp / ".rtide-worktrees" / name
        deadline = time.time() + 8
        while time.time() < deadline and not fork.is_dir():
            time.sleep(0.1)
        self.assertTrue(fork.is_dir(), "Fork Manager did not create the typed unmatched name")
        self.assertEqual(
            self.run_command("git", "-C", str(fork), "branch", "--show-current").stdout.strip(),
            "rtide/fork-1",
        )

    @unittest.skipUnless(shutil.which("tmux") and shutil.which("fzf"), "tmux and fzf required")
    def test_resume_switches_the_invoking_client(self):
        name = "manager-popup-resume"
        fork = self.tmp / ".rtide-worktrees" / name
        self.run_command(
            "git", "-C", str(self.project), "worktree", "add", "-q", "-b",
            "rtide/fork-1", str(fork), "HEAD",
        )
        (fork / ".rtide").mkdir()
        (fork / ".rtide/fork-origin").write_text(
            f"source={self.project}\nbranch=rtide/fork-1\ncreated=now\n", encoding="utf-8"
        )
        (fork / ".tweb").mkdir()
        (fork / ".tweb/welcome.html").write_text(
            "<!doctype html><title>Fork ready</title><h1>Fork ready</h1>\n",
            encoding="utf-8",
        )
        self.env["FAKE_TWEB_STATUS_URL"] = (fork / ".tweb/welcome.html").resolve().as_uri()
        self.tmux("new-session", "-d", "-s", "ui", "-n", "work", "-c", str(self.project))
        pane = self.tmux("display-message", "-p", "-t", "ui:work", "#{pane_id}").stdout.strip()
        self.tmux("set-option", "-p", "-t", pane, "@rtide-role", "nvim")
        for key in ("HOME", "PATH", "RTIDE_FORK_NO_LAUNCH", "RTIDE_ROOT", "FAKE_TWEB_STATUS_URL"):
            self.tmux("set-environment", "-g", key, self.env[key])
        self.attach_client()
        time.sleep(0.5)
        client = self.tmux("display-message", "-p", "-t", pane, "#{client_name}").stdout.strip()
        popup = subprocess.Popen(
            [
                "tmux", "-S", self.socket, "display-popup", "-E", "-t", pane,
                "-w", "70%", "-h", "70%", "-d", str(self.project),
                str(ROOT / "bin/rtide"), "fork-menu", pane,
            ], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.addCleanup(lambda: popup.poll() is None and popup.kill())
        time.sleep(0.8)
        os.write(self.master_fd, name.encode())
        time.sleep(0.2)
        os.write(self.master_fd, b"\r")
        time.sleep(0.5)
        os.write(self.master_fd, b"Resume or switch")
        time.sleep(0.2)
        os.write(self.master_fd, b"\r")

        deadline = time.time() + 8
        current = ""
        while time.time() < deadline:
            current = self.tmux("display-message", "-p", "-c", client, "#{@rtide-workspace}").stdout.strip()
            if current == str(fork):
                break
            time.sleep(0.1)
        diagnostics = []
        for path in sorted((fork / ".rtide").glob("fork-launch*")):
            try:
                diagnostics.append(f"{path.name}:\n{path.read_text(encoding='utf-8')}")
            except (OSError, UnicodeDecodeError):
                pass
        self.assertEqual(
            current, str(fork),
            "Resume did not switch the invoking tmux client\n" + "\n".join(diagnostics),
        )

    @unittest.skipUnless(shutil.which("tmux") and shutil.which("fzf"), "tmux and fzf required")
    def test_finish_and_remove_disappears_from_inventory(self):
        name = "manager-popup-remove"
        fork = self.tmp / ".rtide-worktrees" / name
        self.run_command(
            "git", "-C", str(self.project), "worktree", "add", "-q", "-b",
            "rtide/fork-1", str(fork), "HEAD",
        )
        (fork / ".rtide").mkdir()
        (fork / ".rtide/fork-origin").write_text(
            f"source={self.project}\nbranch=rtide/fork-1\ncreated=now\n", encoding="utf-8"
        )
        pane = self.configure_session()
        popup = self.open_manager(pane)
        self.addCleanup(lambda: popup.poll() is None and popup.kill())
        time.sleep(0.8)
        self.type_enter(name)
        time.sleep(1.5)
        self.type_enter("Finish and remove")
        time.sleep(1.0)
        os.write(self.master_fd, b"Yes")
        time.sleep(0.2)
        os.write(self.master_fd, b"\r")

        deadline = time.time() + 8
        while time.time() < deadline and fork.exists():
            time.sleep(0.1)
        self.assertFalse(fork.exists(), "confirmed Finish and remove left the worktree behind")
        inventory = self.run_command(
            str(ROOT / "libexec/rtide/forks"), "--root", str(self.project), "list", "--json"
        ).stdout
        self.assertNotIn(name, inventory, "removed fork remained in Fork Manager inventory")


if __name__ == "__main__":
    unittest.main()
