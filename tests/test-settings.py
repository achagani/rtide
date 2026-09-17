#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "libexec" / "rtide" / "settings"
AGENT = ROOT / "libexec" / "rtide" / "agent"


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.workspace = self.root / "workspace"
        self.config = self.home / ".rtide" / "config"
        self.config.parent.mkdir(parents=True)
        (self.workspace / ".rtide").mkdir(parents=True)
        self.config.write_text(
            "# user config\nprovider=openai\nharness=codex\nmodel=global-model\n"
            "permission_policy=workspace\nagent_lines=3\ntweb_pct=60\nshell=bash\n"
            "auto_float=false\ndefault_dir=\nworktree_root=\nfuture_key=preserve-me\n",
            encoding="utf-8",
        )

    def tearDown(self):
        self.temp.cleanup()

    def run_settings(self, *args, check=True):
        return subprocess.run(
            [str(SETTINGS), "--config", str(self.config), *map(str, args)],
            text=True, capture_output=True, check=check,
        )

    def test_schema_and_capability_matrix(self):
        schema = json.loads(self.run_settings("schema", "--json").stdout)
        self.assertEqual(set(schema["settings"]), {
            "provider", "harness", "model", "permission_policy", "agent_lines",
            "tweb_pct", "shell", "auto_float", "default_dir", "worktree_root",
        })
        self.assertEqual(schema["permission_capabilities"]["codex"],
                         ["workspace", "observe", "native", "unrestricted"])
        for harness in ("claude", "hermes", "opencode"):
            self.assertEqual(schema["permission_capabilities"][harness], ["native"])
            rejected = self.run_settings("capability", harness, "workspace", check=False)
            self.assertNotEqual(rejected.returncode, 0)

    def test_precedence_status_and_effective_state(self):
        self.run_settings("set", "--scope", "workspace", self.workspace,
                          "model=workspace-model", "permission_policy=observe")
        self.run_settings("publish", self.workspace, "provider=openai", "harness=codex",
                          "model=global-model", "permission_policy=workspace", "--pid", "41")
        status = json.loads(self.run_settings("status", self.workspace, "--json").stdout)
        rows = {row["key"]: row for row in status["settings"]}
        self.assertEqual(rows["model"]["desired"], "workspace-model")
        self.assertEqual(rows["model"]["effective"], "global-model")
        self.assertEqual(rows["model"]["state"], "pending")
        self.assertEqual(rows["shell"]["state"], "restart-required")

    def test_atomic_write_preserves_unknown_data_and_never_executes(self):
        marker = self.root / "executed"
        self.config.write_text(
            self.config.read_text(encoding="utf-8")
            + f"malicious=$(touch {marker})\nmodel=$(touch {marker})\n",
            encoding="utf-8",
        )
        self.run_settings("set", "--scope", "global", self.workspace,
                          "agent_lines=5", "auto_float=true")
        text = self.config.read_text(encoding="utf-8")
        self.assertIn("future_key=preserve-me", text)
        self.assertIn(f"malicious=$(touch {marker})", text)
        self.assertFalse(marker.exists())
        bad = self.run_settings("set", "--scope", "global", self.workspace,
                                "tweb_pct=100", check=False)
        self.assertNotEqual(bad.returncode, 0)
        self.assertIn("tweb_pct=60", self.config.read_text(encoding="utf-8"))

    def test_reserved_setting_is_reported_as_explicit_only(self):
        status = json.loads(self.run_settings("status", self.workspace, "--json").stdout)
        rows = {row["key"]: row for row in status["settings"]}
        self.assertEqual(rows["auto_float"]["state"], "explicit-only")
        self.assertIn("never floats output during an agent turn",
                      rows["auto_float"]["note"])

    def test_agent_process_publishes_exact_effective_arguments(self):
        env = os.environ.copy()
        env.update({"HOME": str(self.home), "RTIDE_ROOT": str(ROOT)})
        result = subprocess.run(
            [str(AGENT), "codex", "openai", "test-model", str(self.workspace), "unrestricted"],
            input="", text=True, capture_output=True, env=env, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        active = json.loads((self.workspace / ".rtide" / "effective-settings.json").read_text())
        self.assertEqual(active["permission_policy"], "unrestricted")
        self.assertEqual(active["harness"], "codex")
        self.assertIsInstance(active["agent_pid"], int)


if __name__ == "__main__":
    unittest.main()
