import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin" / "rtide-forks"


class ForkManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self.temp.name)
        self.repo = base / "project"
        self.fork = base / ".rtide-worktrees" / "feature-one"
        self.repo.mkdir()
        subprocess.run(["git", "-C", self.repo, "init", "-q"], check=True)
        (self.repo / ".gitignore").write_text(".rtide/*\n!.rtide/memory/\n")
        (self.repo / "app.txt").write_text("base\n")
        subprocess.run(["git", "-C", self.repo, "add", ".gitignore", "app.txt"], check=True)
        subprocess.run([
            "git", "-C", self.repo, "-c", "user.name=test",
            "-c", "user.email=test@example.invalid", "commit", "-qm", "base"
        ], check=True)
        subprocess.run(["git", "-C", self.repo, "branch", "-M", "main"], check=True)
        subprocess.run([
            "git", "-C", self.repo, "worktree", "add", "-q", "-b",
            "feature/one", self.fork, "main"
        ], check=True)
        (self.fork / ".rtide").mkdir()
        (self.fork / ".rtide" / "fork-origin").write_text(
            f"source={self.repo}\nbranch=feature/one\ncreated=2026-09-01T12:00:00-04:00\n"
        )
        (self.fork / ".rtide" / "output-history.json").write_text(json.dumps([
            {"request": "Build feature one", "title": "Feature output"}
        ]))

    def tearDown(self):
        subprocess.run(["git", "-C", self.repo, "worktree", "remove", "--force", self.fork], check=False)
        self.temp.cleanup()

    def run_helper(self, *args):
        return subprocess.run(
            ["python3", SCRIPT, "--root", self.repo, *args],
            capture_output=True, text=True
        )

    def test_list_discovers_persistent_fork_metadata(self):
        result = self.run_helper("list", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        items = json.loads(result.stdout)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["name"], "feature-one")
        self.assertEqual(items[0]["request"], "Build feature one")
        self.assertFalse(items[0]["dirty"])
        self.assertEqual(items[0]["pending_memories"], 0)

    def test_list_reports_pending_fork_memories(self):
        index = self.fork / ".rtide" / "memory" / ".index-v2"
        index.mkdir(parents=True)
        (index / "index.json").write_text(json.dumps({"entries": [
            {"review": "pending"}, {"review": "reviewed"}, {"review": "pending"}
        ]}))
        result = self.run_helper("list", "--json")
        self.assertEqual(json.loads(result.stdout)[0]["pending_memories"], 2)

    def test_status_accepts_name_branch_and_path(self):
        for selector in ("feature-one", "feature/one", str(self.fork)):
            result = self.run_helper("status", selector, "--json")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)["branch"], "feature/one")

    def test_finish_refuses_dirty_or_unmerged_fork(self):
        (self.fork / "app.txt").write_text("changed\n")
        subprocess.run(["git", "-C", self.fork, "add", "app.txt"], check=True)
        subprocess.run([
            "git", "-C", self.fork, "-c", "user.name=test",
            "-c", "user.email=test@example.invalid", "commit", "-qm", "feature"
        ], check=True)
        (self.fork / "untracked.txt").write_text("dirty\n")
        result = self.run_helper("check-finish", "feature-one")
        self.assertEqual(result.returncode, 2)
        self.assertIn("modified or untracked", result.stderr)
        self.assertIn("not merged", result.stderr)

    def test_finish_allows_clean_merged_fork(self):
        result = self.run_helper("check-finish", "feature-one")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
