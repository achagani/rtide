import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "rtide-progress"


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.workspace = pathlib.Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def run_progress(self, *args):
        return subprocess.run(["python3", SCRIPT, "--workspace", self.workspace, "--no-render", *args], capture_output=True, text=True)

    def test_dashboard_tracks_substeps_and_completion(self):
        result = self.run_progress("init", "Menu feature", "--objective", "Build it", "--steps", "Audit", "Implement", "Test")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.run_progress("event", "Menu feature", "Audit", "Read current code", "--status", "active").returncode, 0)
        self.assertEqual(self.run_progress("event", "Menu feature", "Audit", "Architecture mapped", "--status", "complete").returncode, 0)
        self.assertEqual(self.run_progress("finish", "Menu feature", "--summary", "Implemented", "--metric", "tests=12", "--metric", "version=0.2.1").returncode, 0)
        state = json.loads((self.workspace / ".rtide/progress/menu-feature.json").read_text())
        page = (self.workspace / ".tweb/implementation-menu-feature.html").read_text()
        self.assertEqual(state["status"], "complete")
        self.assertIn('content="implementation-dashboard"', page)
        self.assertIn("Implementation complete", page)
        self.assertIn("Architecture mapped", page)
        self.assertIn("12", page)

    def test_blocked_finish_preserves_blocked_state(self):
        self.run_progress("init", "Blocked task", "--steps", "Build")
        self.run_progress("event", "Blocked task", "Build", "Need permission", "--status", "blocked")
        self.run_progress("finish", "Blocked task", "--summary", "Waiting", "--blocked")
        state = json.loads((self.workspace / ".rtide/progress/blocked-task.json").read_text())
        self.assertEqual(state["status"], "blocked")
        self.assertEqual(state["steps"][0]["status"], "blocked")

    def test_separate_titles_create_separate_execution_runs(self):
        self.run_progress("init", "Fork menu fix", "--steps", "Build")
        self.run_progress("init", "Window naming fix", "--steps", "Build")
        self.assertTrue((self.workspace / ".rtide/progress/fork-menu-fix.json").exists())
        self.assertTrue((self.workspace / ".rtide/progress/window-naming-fix.json").exists())
        self.assertTrue((self.workspace / ".tweb/implementation-fork-menu-fix.html").exists())
        self.assertTrue((self.workspace / ".tweb/implementation-window-naming-fix.html").exists())

    def test_active_workflow_starts_updates_and_completes_current_run(self):
        started = self.run_progress("start", "Active feature", "--steps", "Audit", "Build")
        self.assertEqual(started.returncode, 0, started.stderr)
        pointer = self.workspace / ".rtide/progress/active"
        self.assertEqual(pointer.read_text().strip(), "active-feature")
        updated = self.run_progress("checkpoint", "Audit", "Mapped behavior", "--status", "complete")
        self.assertEqual(updated.returncode, 0, updated.stderr)
        finished = self.run_progress("complete", "--summary", "Shipped", "--metric", "tests=3")
        self.assertEqual(finished.returncode, 0, finished.stderr)
        self.assertFalse(pointer.exists())
        state = json.loads((self.workspace / ".rtide/progress/active-feature.json").read_text())
        self.assertEqual(state["status"], "complete")
        self.assertIn("Mapped behavior", state["steps"][0]["events"][0]["message"])

    def test_checkpoint_adopts_one_legacy_active_dashboard(self):
        self.run_progress("init", "Legacy active", "--steps", "Build")
        (self.workspace / ".rtide/progress/active").unlink()
        result = self.run_progress("checkpoint", "Build", "Adopted", "--status", "complete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.workspace / ".rtide/progress/active").read_text().strip(),
                         "legacy-active")


if __name__ == "__main__":
    unittest.main()
