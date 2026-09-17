#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
DEPS = ROOT / "libexec" / "rtide" / "deps"
LOADER = importlib.machinery.SourceFileLoader("rtide_deps", str(DEPS))
SPEC = importlib.util.spec_from_loader("rtide_deps", LOADER)
DEPS_MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DEPS_MOD)


class DependencyMatrixTests(unittest.TestCase):
    def run_deps(self, *args):
        return subprocess.run([sys.executable, str(DEPS), *map(str, args)],
                              text=True, capture_output=True)

    def test_every_requirement_is_classified_once(self):
        names = [r["name"] for r in DEPS_MOD.REQUIREMENTS]
        self.assertEqual(len(names), len(set(names)), "duplicate requirement name")
        for requirement in DEPS_MOD.REQUIREMENTS:
            self.assertIn(requirement["level"], {"required", "build", "optional"})
            self.assertTrue(requirement["category"])
            # Every requirement must offer actionable guidance. Some (such as
            # the agent harness) are intentionally installed by the user, so a
            # remedy is required even when nothing can be provisioned.
            self.assertTrue(requirement.get("remedy"), requirement["name"])

    def test_required_and_optional_levels_are_distinct(self):
        required = {r["name"] for r in DEPS_MOD.REQUIREMENTS if r["level"] == "required"}
        optional = {r["name"] for r in DEPS_MOD.REQUIREMENTS if r["level"] == "optional"}
        self.assertTrue(required.isdisjoint(optional))

    def test_check_json_reports_level_and_remedy(self):
        payload = json.loads(self.run_deps("check", "--json").stdout)
        by_name = {row["name"]: row for row in payload}
        self.assertEqual(by_name["git"]["level"], "required")
        self.assertEqual(by_name["speech-engine"]["level"], "optional")
        # A missing optional capability carries a non-blocking remedy.
        if not by_name["speech-engine"]["present"]:
            self.assertIn("without-voice", by_name["speech-engine"]["remedy"])

    def test_missing_packages_are_per_manager_and_present_only(self):
        for manager in ("apt-get", "dnf", "brew", "pacman", "zypper"):
            packages = self.run_deps("missing-packages", manager).stdout.split()
            # No package name may repeat across the selected set.
            self.assertEqual(len(packages), len(set(packages)), manager)
        # A present requirement contributes no packages.
        with mock.patch.object(DEPS_MOD, "report",
                               return_value=[{"name": "git", "level": "required",
                                              "category": "core", "present": True,
                                              "detail": "", "remedy": "", "provisioned": ""}]):
            self.assertEqual(DEPS_MOD.missing_packages("apt-get"), [])

    def test_install_scope_excludes_present_and_optional(self):
        rows = [
            {"name": "git", "level": "required", "category": "core", "present": True,
             "detail": "", "remedy": "", "provisioned": ""},
            {"name": "tmux", "level": "required", "category": "core", "present": False,
             "detail": "", "remedy": "x", "provisioned": ""},
            {"name": "speech-engine", "level": "optional", "category": "voice",
             "present": False, "detail": "", "remedy": "x", "provisioned": "install-voice"},
        ]
        with mock.patch.object(DEPS_MOD, "report", return_value=rows):
            self.assertEqual(DEPS_MOD.missing_for_install(), ["tmux"])

    def test_doctor_separates_blockers_from_optional(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env.update(HOME=tmp, RTIDE_CONFIG_DIR=tmp)
            result = subprocess.run([str(ROOT / "bin" / "rtide"), "doctor"],
                                    text=True, capture_output=True, env=env)
            output = result.stdout + result.stderr
            # The optional speech engine must never be reported as a blocker.
            self.assertNotIn("MISSING: speech-engine", output)
            # Build tools are only relevant to a missing tweb.
            if subprocess.run(["bash", "-c", "command -v tweb"], capture_output=True).returncode == 0:
                self.assertIn("only needed to build tweb from source", output)


if __name__ == "__main__":
    unittest.main()
