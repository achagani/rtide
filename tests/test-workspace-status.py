#!/usr/bin/env python3
import datetime as dt
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "libexec" / "rtide" / "workspace-status"
LOADER = importlib.machinery.SourceFileLoader("workspace_status", str(HELPER))
SPEC = importlib.util.spec_from_loader("workspace_status", LOADER)
STATUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATUS)


class WorkspaceStatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = mock.patch.dict(os.environ, {"RTIDE_STATUS_DIR": self.temp.name, "TMUX": "/tmp/test,1,0"})
        self.env.start()
        self.addCleanup(self.env.stop)

    def location(self):
        return {"session": "rtide-demo", "session_id": "$1", "window_id": "@7",
                "label": "work", "workspace": self.temp.name}

    def test_atomic_state_machine_and_sticky_acknowledgement(self):
        with mock.patch.object(STATUS, "pane_location", return_value=self.location()), \
                mock.patch.object(STATUS, "run_tmux"):
            working = STATUS.publish("%1", "working")
            self.assertEqual(working["lifecycle"], "working")
            waiting = STATUS.publish("%1", "input-needed", "question")
            self.assertFalse(waiting["attention"]["acknowledged"])
            self.assertEqual(STATUS.acknowledge("@7", "focus")["lifecycle"], "input-needed")
            self.assertEqual(STATUS.acknowledge("@7", "answer")["lifecycle"], "ready")
            done = STATUS.publish("%1", "done", "done-unseen")
            self.assertEqual(done["attention"]["reason"], "done-unseen")
            self.assertEqual(STATUS.acknowledge("@7", "focus")["lifecycle"], "ready")
        files = list(Path(self.temp.name).glob("*.json"))
        self.assertEqual(len(files), 1)
        self.assertEqual(json.loads(files[0].read_text())["schema"], 1)
        self.assertFalse(list(Path(self.temp.name).glob("*.tmp")))

    def test_stale_is_derived_only_from_heartbeat_policy(self):
        old = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=STATUS.STALE_AFTER + 1)).isoformat()
        path = STATUS.status_path(STATUS.tmux_server_id(), "@7")
        STATUS.atomic_json(path, {"server": STATUS.tmux_server_id(), "window_id": "@7",
                                  "lifecycle": "working", "heartbeat": old})
        record = STATUS.load_records()[((STATUS.tmux_server_id(), "@7"))]
        self.assertEqual(record["display_state"], "stale")
        self.assertEqual(record["lifecycle"], "working")

    def test_inventory_preserves_duplicate_basenames_and_groups_forks(self):
        first = Path(self.temp.name) / "one" / "app"
        second = Path(self.temp.name) / "two" / "app"
        fork = Path(self.temp.name) / "fork"
        for path in (first, second, fork):
            (path / ".rtide").mkdir(parents=True)
        (fork / ".rtide" / "fork-origin").write_text(f"source={first}\nbranch=rtide/fork-1\n")
        rows = "\n".join((
            f"rtide-app\t$1\t@1\twork\t{first}\t1\t1",
            f"rtide-app-2\t$2\t@2\twork\t{second}\t0\t1",
            f"rtide-app\t$1\t@3\tfork-1\t{fork}\t0\t1",
        )) + "\n"
        response = mock.Mock(returncode=0, stdout=rows)
        with mock.patch.object(STATUS, "run_tmux", return_value=response):
            items = STATUS.inventory()
        self.assertEqual(len(items), 3)
        self.assertEqual(len({item["identity"] for item in items}), 3)
        self.assertEqual(items[1]["fork_source"], str(first))

    def test_switch_targets_only_invoking_client_and_acknowledges_window(self):
        success = mock.Mock(returncode=0, stdout="", stderr="")
        with mock.patch.object(STATUS, "run_tmux", return_value=success) as tmux, \
                mock.patch.object(STATUS, "acknowledge") as acknowledge:
            STATUS.switch("/dev/pts/9", "rtide-demo:@7")
        tmux.assert_called_once_with("switch-client", "-c", "/dev/pts/9", "-t", "rtide-demo:@7")
        acknowledge.assert_called_once_with("@7", "focus")

    def test_geometry_snapshots(self):
        self.assertEqual(STATUS.rail_geometry(60, 30),
                         {"mode": "compact", "width": 56, "height": 24, "x": "C", "y": "C"})
        self.assertEqual(STATUS.rail_geometry(120, 40),
                         {"mode": "rail", "width": 32, "height": 40, "x": "R", "y": 0})
        self.assertEqual(STATUS.rail_geometry(200, 50),
                         {"mode": "rail", "width": 42, "height": 50, "x": "R", "y": 0})

    def test_inventory_is_one_tmux_call_and_linear_for_burst(self):
        root = Path(self.temp.name)
        rows = []
        for index in range(200):
            workspace = root / f"workspace-{index}"
            workspace.mkdir()
            rows.append(f"rtide-{index}\t${index}\t@{index}\twork\t{workspace}\t0\t0")
        response = mock.Mock(returncode=0, stdout="\n".join(rows) + "\n")
        started = time.monotonic()
        with mock.patch.object(STATUS, "run_tmux", return_value=response) as tmux:
            items = STATUS.inventory()
        self.assertEqual(len(items), 200)
        self.assertEqual(tmux.call_count, 1)
        self.assertLess(time.monotonic() - started, 1.0)


if __name__ == "__main__":
    unittest.main()
