import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TmuxInstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = {**os.environ, "HOME": str(self.home), "XDG_CONFIG_HOME": str(self.home / "xdg")}

    def install(self, check=True):
        return subprocess.run(["python3", str(ROOT / "scripts/install-tmux")],
                              env=self.env, capture_output=True, text=True, check=check)

    def test_fresh_install_and_reinstall(self):
        self.install()
        config = self.home / ".tmux.conf"
        original = config.read_bytes()
        self.install()
        self.assertEqual(config.read_bytes(), original)
        self.assertIn(b"set-option -g allow-passthrough all", original)

    def test_preserves_xdg_config_symlink_and_backup(self):
        config = self.home / "xdg/tmux/tmux.conf"
        config.parent.mkdir(parents=True)
        target = self.home / "dotfiles-tmux"
        original = b"# personal\nset -g mouse on\nset -g allow-passthrough off"
        target.write_bytes(original)
        config.symlink_to(target)
        self.install()
        self.assertTrue(config.is_symlink())
        self.assertTrue(target.read_bytes().startswith(original + b"\n"))
        self.assertEqual(config.with_name("tmux.conf.rtide-backup").read_bytes(), original)
        self.assertFalse((self.home / ".tmux.conf").exists())
        self.install()
        self.assertEqual(target.read_text().count("# >>> RTIDE"), 1)

    def test_malformed_block_fails_without_edit(self):
        config = self.home / ".tmux.conf"
        original = "# >>> RTIDE terminal graphics >>>\n# personal\n"
        config.write_text(original)
        self.assertNotEqual(self.install(check=False).returncode, 0)
        self.assertEqual(config.read_text(), original)

    def test_home_config_takes_precedence(self):
        config = self.home / ".tmux.conf"
        config.write_text("# home\n")
        xdg = self.home / "xdg/tmux/tmux.conf"
        xdg.parent.mkdir(parents=True)
        xdg.write_text("# xdg\n")
        self.install()
        self.assertIn("allow-passthrough all", config.read_text())
        self.assertEqual(xdg.read_text(), "# xdg\n")

    def test_installed_config_enables_real_tmux(self):
        self.install()
        socket = str(self.home / "test.sock")
        command = ["tmux", "-S", socket, "-f", str(self.home / ".tmux.conf")]
        try:
            subprocess.run(command + ["new-session", "-d", "-s", "check"], check=True, capture_output=True)
            result = subprocess.check_output(command + ["show-options", "-gv", "allow-passthrough"], text=True)
            self.assertEqual(result.strip(), "all")
        finally:
            subprocess.run(command + ["kill-server"], capture_output=True)


if __name__ == "__main__":
    unittest.main()
