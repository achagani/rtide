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

    def test_custom_artifact_uses_its_authored_title(self):
        with tempfile.TemporaryDirectory() as tmp:
            page = os.path.join(tmp, "field-guide.html")
            with open(page, "w") as f:
                f.write("<html><head><title>Big Meadows — Deep Trip Briefing</title>"
                        "</head><body></body></html>")
            self.assertEqual(
                AGENT.artifact_title("file://" + page),
                "Big Meadows — Deep Trip Briefing",
            )
            entries = [{"kind": "custom artifact", "title": "old request",
                        "url": "file://" + page}]
            AGENT.refresh_artifact_titles(entries)
            self.assertEqual(entries[0]["title"], "Big Meadows — Deep Trip Briefing")

    def test_fallback_is_a_standalone_designed_result(self):
        page = AGENT.build_result_html(
            "Compare the options", "# Recommendation\n\n- Fast\n- Clear", "demo", 4.2
        )
        self.assertIn("RTIDE · designed result", page)
        self.assertIn("Browse output history", page)
        self.assertIn("<h1>Recommendation</h1>", page)
        self.assertIn("<ul>", page)
        self.assertNotIn('class="msg', page)
        self.assertNotIn("scrollTo", page)

    def test_prose_opening_is_not_promoted_to_hero_title(self):
        opening = "This opening sentence explains the answer and belongs in the body."
        page = AGENT.build_result_html(
            "Explain the behavior", opening + "\n\nMore detail follows.", "demo", 2
        )
        self.assertIn("<h1>Explain the behavior</h1>", page)
        self.assertNotIn(f"<h1>{opening}</h1>", page)
        self.assertEqual(page.count(opening), 1)
        self.assertIn("<summary>Request context</summary>", page)

    def test_fallback_renders_images_and_contextual_links(self):
        body = AGENT.md_to_html(
            "![Route map](https://example.com/map.png)\n\n"
            "[Open the source](https://example.com/report)"
        )
        self.assertIn('<img src="https://example.com/map.png"', body)
        self.assertIn('alt="Route map"', body)
        self.assertIn('<a href="https://example.com/report">Open the source</a>', body)

    def test_fallback_rejects_unsafe_visual_urls(self):
        body = AGENT.md_to_html(
            "![Unsafe](javascript:evil) [Bad link](javascript:evil)"
        )
        self.assertNotIn("javascript:", body)
        self.assertNotIn("<img", body)

    def test_history_links_to_individual_results(self):
        entries = [{
            "request": "Compare the options", "title": "Recommendation",
            "url": "file:///workspace/.tweb/results/result-1.html",
            "elapsed": 4.2, "created": "Aug 27, 2026 · 22:30",
            "kind": "designed result",
        }]
        page = AGENT.build_history_html(entries, "demo")
        self.assertIn("Output history", page)
        self.assertIn("result-1.html", page)
        self.assertIn("Compare the options", page)

    def test_history_distinguishes_custom_artifacts_compactly(self):
        entries = [{
            "request": "Build a trip guide", "title": "Big Meadows — Field Guide",
            "url": "file:///workspace/.tweb/field-guide.html", "elapsed": 8,
            "created": "Aug 27 · 23:22", "kind": "custom artifact",
        }]
        page = AGENT.build_history_html(entries, "demo")
        self.assertIn('class="card artifact"', page)
        self.assertIn("1 outputs · 1 artifacts", page)
        self.assertIn("Big Meadows — Field Guide", page)


if __name__ == "__main__":
    unittest.main()
