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
AGENT_PATH = os.path.join(ROOT, "libexec", "rtide", "agent")
LOADER = importlib.machinery.SourceFileLoader("rtide_agent", AGENT_PATH)
SPEC = importlib.util.spec_from_loader("rtide_agent", LOADER)
AGENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AGENT)
ANSI = re.compile(r"\x1b(?:\[[0-9;]*[A-Za-z]|[78])")


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

    def test_agent_readiness_uses_atomic_workspace_marker(self):
        with tempfile.TemporaryDirectory() as workspace:
            AGENT.mark_agent_ready(workspace)
            marker = os.path.join(workspace, ".rtide", "agent-ready")
            self.assertTrue(os.path.isfile(marker))
            with open(marker) as marker_file:
                self.assertEqual(int(marker_file.read()), os.getpid())

    def test_lifecycle_publisher_emits_events_and_bounded_heartbeat(self):
        completed = mock.Mock(returncode=0)
        with mock.patch.object(AGENT.subprocess, "run", return_value=completed) as run:
            publisher = AGENT.LifecyclePublisher("%9", heartbeat_interval=0.01)
            self.assertTrue(publisher.publish("input-needed", "question"))
            publisher.start()
            publisher.stop_event.wait(0.03)
            publisher.stop()
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn([AGENT.WORKSPACE_STATUS, "publish", "input-needed",
                       "--reason", "question", "--pane", "%9"], commands)
        self.assertTrue(any(command[1:3] == ["heartbeat", "--pane"] for command in commands))

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

    def test_working_status_shows_queue_count(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            AGENT.working_status("@note researching", 9, 3)
        plain = ANSI.sub("", out.getvalue())
        self.assertIn("working 9s", plain)
        self.assertIn("q3", plain)

    def test_working_state_keeps_visible_prompt(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            AGENT.working_status("@note researching", 2, 0, reset_prompt=True)
        plain = ANSI.sub("", out.getvalue())
        self.assertIn("working 2s", plain)
        self.assertIn("\n╰─❯ ", plain)
        self.assertIn("🎙 voice", plain)

    def test_agent_uses_bounded_composer(self):
        self.assertTrue(callable(AGENT.Composer.read_submission))
        self.assertTrue(AGENT.Submission("one line").attachments == ())

    def test_development_identity_is_environment_controlled(self):
        with open(AGENT_PATH) as source_file:
            source = source_file.read()
        self.assertIn('os.environ.get("RTIDE_DEV_MODE") == "1"', source)
        self.assertIn("DEV_BADGE", source)

    def test_development_result_shows_absolute_worktree(self):
        with mock.patch.object(AGENT, "DEV_WORKTREE", "/workspace/rtide-feature"):
            page = AGENT.build_result_html("Request", "Answer", "feature", 1)
        self.assertIn("DEVELOPMENT WORKTREE", page)
        self.assertIn("/workspace/rtide-feature", page)

    def test_release_result_has_no_development_worktree_banner(self):
        with mock.patch.object(AGENT, "DEV_WORKTREE", ""):
            page = AGENT.build_result_html("Request", "Answer", "feature", 1)
        self.assertNotIn("DEVELOPMENT WORKTREE", page)

    def test_window_activity_animates_and_restores_base_name(self):
        location = mock.Mock(returncode=0, stdout="@7\tfeature-one\n")
        stored = mock.Mock(returncode=0, stdout="feature-one\n")
        calls = [location, stored]
        def fake_run(*args, **kwargs):
            return calls.pop(0) if calls else mock.Mock(returncode=0, stdout="")
        with mock.patch.dict(os.environ, {"TMUX_PANE": "%9"}), \
                mock.patch.object(AGENT.subprocess, "run",
                                  side_effect=fake_run) as run:
            activity = AGENT.WindowActivity(interval=0.01)
            self.assertTrue(activity.start())
            activity.stop_event.wait(0.03)
            activity.stop()
        commands = [call.args[0] for call in run.call_args_list]
        self.assertTrue(any(cmd[:2] == ["tmux", "rename-window"] and
                            cmd[-1].endswith(" feature-one") for cmd in commands))
        self.assertEqual(commands[-1], ["tmux", "rename-window", "-t", "@7",
                                        "feature-one"])

    def test_request_context_is_expanded_by_default(self):
        page = AGENT.build_result_html("Original request", "Answer", "demo", 1)
        self.assertIn('<details class="request" open>', page)

    def test_question_output_has_choice_and_freeform_ui(self):
        response = "Which direction should I take?\n\n1. Fast route\n2. Scenic route"
        page = AGENT.build_result_html(
            "Plan it", response, "demo", 1, "http://127.0.0.1:123/reply/token"
        )
        self.assertIn("Input requested", page)
        self.assertIn('value="Fast route"', page)
        self.assertIn('textarea name="answer"', page)
        self.assertIn("Send response", page)

    def test_live_input_controls(self):
        action, submission = AGENT.classify_live_input("follow up")
        self.assertEqual((action, submission.text), ("queue", "follow up"))
        action, submission = AGENT.classify_live_input("/steer focus on maps")
        self.assertEqual((action, submission.text), ("steer", "focus on maps"))
        self.assertEqual(AGENT.classify_live_input("/interrupt"),
                         ("interrupt", ""))
        last = AGENT.Submission("last request")
        self.assertEqual(AGENT.classify_live_input("/resend", last),
                         ("queue", last))

    def test_structured_attachment_metadata_reaches_provider(self):
        item = AGENT.Attachment("id", "/tmp/image.png", "image.png",
                                "image/png", 12)
        request = AGENT.Submission("describe", (item,))
        completed = mock.Mock(returncode=0, stdout="command\n", stderr="")
        with mock.patch.object(AGENT.subprocess, "run", return_value=completed) as run:
            command = AGENT.get_run_cmd("codex", "openai", "model", request, None)
        self.assertEqual(command, "command")
        self.assertEqual(run.call_args.args[0][-4:],
                         ["--attachment", "/tmp/image.png", "image/png", "image.png"])

    def test_fork_context_seeds_only_the_first_turn(self):
        with tempfile.TemporaryDirectory() as tmp:
            context = os.path.join(tmp, "fork-context.md")
            with open(context, "w") as f:
                f.write("Inherited conversation")
            request = AGENT.Submission("Continue here")
            seeded = AGENT.request_with_fork_context(request, None, context)
            self.assertIn("Inherited conversation", seeded.text)
            self.assertTrue(seeded.text.endswith("Continue here"))
            self.assertEqual(
                AGENT.request_with_fork_context(AGENT.Submission("Next turn"), "session-1", context),
                AGENT.Submission("Next turn"),
            )

    def test_fork_command_targets_current_window_with_literal_prompt(self):
        location = mock.Mock(returncode=0, stdout="rtide-demo\t@7\n")
        launched = mock.Mock(returncode=0, stdout="fork: demo-fork-1\n", stderr="")
        with mock.patch.dict(os.environ, {"TMUX_PANE": "%9"}):
            with mock.patch.object(AGENT.subprocess, "run",
                                   side_effect=[location, launched]) as run:
                ok, _ = AGENT.fork_command("don't expand $HOME or `pwd`")
        self.assertTrue(ok)
        self.assertEqual(
            run.call_args_list[1].args[0],
            [AGENT.RTIDE_BIN, "fork", "rtide-demo", "@7", "",
             "don't expand $HOME or `pwd`"],
        )

    def test_fork_lifecycle_command_targets_rtide_directly(self):
        location = mock.Mock(returncode=0, stdout="rtide-demo\t@7\n")
        launched = mock.Mock(returncode=0, stdout="fork status\n", stderr="")
        with mock.patch.dict(os.environ, {"TMUX_PANE": "%9"}):
            with mock.patch.object(AGENT.subprocess, "run", side_effect=[location, launched]) as run:
                ok, _ = AGENT.fork_command("status running-icon")
        self.assertTrue(ok)
        self.assertEqual(
            run.call_args_list[1].args[0],
            [AGENT.RTIDE_BIN, "fork", "status", "running-icon", "%9"],
        )

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

    def test_controller_fulfills_workspace_render_request(self):
        with tempfile.TemporaryDirectory() as tmp:
            request = os.path.join(tmp, "render-request")
            before = AGENT.marker_version(request)
            with open(request, "w") as f:
                f.write("0\nfile:///workspace/.tweb/research.html\n")
            with mock.patch.object(AGENT, "show_and_verify", return_value=True) as show, \
                    mock.patch.object(AGENT, "managed_tweb_pane", return_value="%9"), \
                    mock.patch.object(AGENT.subprocess, "run") as run:
                after = AGENT.fulfill_render_request(request, before)
            show.assert_called_once_with("file:///workspace/.tweb/research.html")
            run.assert_called_once_with(
                ["tweb", "pin", "--pane", "%9"],
                stdout=AGENT.subprocess.DEVNULL, stderr=AGENT.subprocess.DEVNULL,
            )
            self.assertEqual(after, AGENT.marker_version(request))

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

    def test_implementation_dashboard_has_native_output_kind(self):
        with tempfile.TemporaryDirectory() as tmp:
            page = os.path.join(tmp, "progress.html")
            with open(page, "w") as handle:
                handle.write('<meta name="rtide-output-kind" content="implementation-dashboard"><title>Build progress</title>')
            self.assertEqual(AGENT.artifact_kind("file://" + page), "implementation dashboard")
            entries = [{"kind": "implementation dashboard", "title": "Build progress", "request": "Implement", "url": "file://" + page, "elapsed": 2, "created": "now"}]
            history = AGENT.build_history_html(entries, "demo", "implementation")
            viewer = AGENT.build_viewer_html(entries)
            self.assertIn('data-kind="implementation"', history)
            self.assertIn("history-implementations.html", history)
            self.assertIn('"kind": "implementation"', viewer)

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
        self.assertNotIn("<h1>", page)
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
        self.assertIn("viewer.html?src=", page)
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
        self.assertIn('href="history-artifacts.html"', page)
        self.assertIn('data-kind="artifact"', page)
        self.assertIn("1 shown · 1 total", page)
        self.assertIn("Big Meadows — Field Guide", page)

    def test_history_filters_are_script_free_pages(self):
        entries = [
            {"request": "A", "title": "Artifact", "url": "file:///w/.tweb/a.html",
             "elapsed": 1, "created": "now", "kind": "custom artifact"},
            {"request": "R", "title": "Response", "url": "file:///w/.tweb/r.html",
             "elapsed": 1, "created": "now", "kind": "designed result"},
        ]
        page = AGENT.build_history_html(entries, "demo", "artifact")
        self.assertIn("Artifact", page)
        self.assertNotIn(">Response</h2>", page)
        self.assertNotIn("<script>", page)

    def test_viewer_keeps_navigation_outside_artifact(self):
        viewer = AGENT.build_viewer_html([
            {"url": "file:///one.html", "title": "One"},
            {"url": "file:///two.html", "title": "Two"},
        ], "http://127.0.0.1:123/pdf/token")
        self.assertIn('<a class="outputs" href="history.html">Outputs</a>', viewer)
        self.assertIn('<iframe id="artifact"', viewer)
        self.assertNotIn("Open ↗", viewer)
        self.assertIn('class="pdf-action"', viewer)
        self.assertNotIn("contentWindow.print", viewer)
        self.assertIn("ArrowLeft", viewer)
        self.assertIn('className=\'dot\'', viewer)
        self.assertIn('file:///two.html', viewer)
        self.assertIn('data-mode="artifact"', viewer)


if __name__ == "__main__":
    unittest.main()
