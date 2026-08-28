#!/usr/bin/env python3
import contextlib
import importlib.util
import importlib.machinery
import io
import json
import os
import re
import tempfile
import unittest
from unittest import mock


ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
AGENT_PATH = os.path.join(ROOT, "bin", "rtide-agent")
LOADER = importlib.machinery.SourceFileLoader("rtide_agent", AGENT_PATH)
SPEC = importlib.util.spec_from_loader("rtide_agent", LOADER)
AGENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AGENT)
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


class AgentStatusTests(unittest.TestCase):
    def test_clear_erases_visible_screen_and_scrollback(self):
        out = io.StringIO()
        with mock.patch.object(AGENT.subprocess, "run") as run:
            with mock.patch.dict(os.environ, {"TMUX_PANE": "%9"}):
                with contextlib.redirect_stdout(out):
                    AGENT.clear()
        run.assert_called_once()
        self.assertIn("clear-history", run.call_args.args[0])
        self.assertEqual(out.getvalue(), "\033[3J\033[2J\033[H")

    def test_agent_narration_is_not_relabelled(self):
        text, color = AGENT.activity("@note Checking the pane layout…")
        self.assertEqual(text, "Checking the pane layout…")
        self.assertEqual(color, AGENT.CYAN)

    def test_timer_and_activity_stay_on_one_line(self):
        out = io.StringIO()
        size = os.terminal_size((36, 24))
        with mock.patch.object(AGENT.shutil, "get_terminal_size", return_value=size):
            with contextlib.redirect_stdout(out):
                AGENT.working_status("Edit /a/very/long/path/to/file.py", 12.9)
        plain = ANSI.sub("", out.getvalue()).lstrip("\r")
        self.assertIn("working 12s", plain)
        self.assertIn("Edit", plain)
        self.assertNotIn("\n", plain)
        self.assertLessEqual(len(plain), size.columns)

    def test_codex_command_event_uses_agent_payload(self):
        event = {
            "type": "item.started",
            "item": {"type": "command_execution", "command": "pytest -q"},
        }
        text, session, activity = AGENT.parse_line("codex", json.dumps(event))
        self.assertIsNone(text)
        self.assertIsNone(session)
        self.assertEqual(activity, "command pytest -q")

    def test_successful_artifact_render_disables_conversation_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = os.path.join(tmp, "last-render")
            before = AGENT.marker_version(marker)
            with open(marker, "w") as f:
                f.write("file:///workspace/.tweb/research.html\n")
            self.assertTrue(AGENT.artifact_rendered(marker, before))


if __name__ == "__main__":
    unittest.main()
