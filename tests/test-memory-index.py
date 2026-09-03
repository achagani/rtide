import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "libexec" / "rtide" / "memory-index"


class MemoryIndexTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.memory = pathlib.Path(self.temp.name) / "memory"
        self.memory.mkdir()
        (self.memory / "MEMORY.md").write_text("# Memory index\n")
        (self.memory / "one.md").write_text(
            "---\nname: one\ncreated: 2026-09-01\nupdated: 2026-09-01\n---\n\nKeep output concise.\n"
        )

    def tearDown(self):
        self.temp.cleanup()

    def run_index(self, scope="fork"):
        return subprocess.run(
            ["python3", SCRIPT, self.memory, "--scope", scope, "--json"],
            capture_output=True, text=True
        )

    def test_migration_preserves_markdown_and_creates_deterministic_id(self):
        source = (self.memory / "one.md").read_bytes()
        first = self.run_index()
        self.assertEqual(first.returncode, 0, first.stderr)
        first_data = json.loads(first.stdout)
        second = self.run_index()
        second_data = json.loads(second.stdout)
        self.assertEqual(first_data["entries"][0]["id"], second_data["entries"][0]["id"])
        self.assertEqual((self.memory / "one.md").read_bytes(), source)
        self.assertEqual(first_data["entries"][0]["review"], "pending")

    def test_scope_is_never_promoted_by_migration(self):
        data = json.loads(self.run_index("project").stdout)
        self.assertEqual(data["entries"][0]["scope"], "project")
        self.assertIsNone(data["entries"][0]["promoted_to"])

    def test_exact_duplicates_are_indexed_without_deletion(self):
        (self.memory / "two.md").write_text("Keep output concise.\n")
        data = json.loads(self.run_index().stdout)
        self.assertEqual(len(data["entries"]), 2)
        self.assertEqual(len(data["exact_duplicates"]), 1)
        self.assertTrue((self.memory / "two.md").is_file())


if __name__ == "__main__":
    unittest.main()
