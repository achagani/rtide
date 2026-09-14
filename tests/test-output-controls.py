import importlib.machinery
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('output_controls', str(ROOT / 'libexec/rtide/output-controls'))
spec = importlib.util.spec_from_loader(loader.name, loader)
controls = importlib.util.module_from_spec(spec)
loader.exec_module(controls)


class OutputControlsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.state = self.workspace / '.rtide/output-zoom.json'
        self.calls = []
        self.answer = {'preference': 1.5, 'updated': 123}

    def fake_run(self, *args):
        self.calls.append(args)
        output = ''
        if args[-1] == '#{pane_height}':
            output = '40'
        if args[:2] == ('tweb', 'eval'):
            output = json.dumps(self.answer)
        return subprocess.CompletedProcess(args, 0, output, '')

    def test_workspace_preference_roundtrip(self):
        with patch.object(controls, 'run', self.fake_run):
            controls.update('%2', self.workspace)
            self.assertEqual(json.loads(self.state.read_text()), self.answer)
            controls.update('%2', self.workspace)
        script = [call[-1] for call in self.calls if call[0] == 'tweb'][-1]
        options = json.loads(script.split(';', 1)[0].split('=', 1)[1])
        self.assertEqual(options['workspace'], self.workspace.as_uri())
        self.assertEqual(options['preference'], 1.5)
        self.assertEqual(options['rows'], 40)

    def test_invalid_page_state_is_not_persisted(self):
        self.answer = {'preference': '../../../../etc/passwd'}
        with patch.object(controls, 'run', self.fake_run):
            controls.update('%2', self.workspace)
        self.assertFalse(self.state.exists())

    def test_corrupt_preference_recovers(self):
        self.state.parent.mkdir()
        self.state.write_text('invalid json')
        with patch.object(controls, 'run', self.fake_run):
            controls.update('%2', self.workspace)
        self.assertEqual(json.loads(self.state.read_text()), self.answer)

    def test_export_suppresses_injection(self):
        with patch.object(controls, 'run', return_value=subprocess.CompletedProcess([], 0, '1\n', '')) as run:
            controls.update('%2', self.workspace)
        self.assertEqual(run.call_count, 1)
        self.assertFalse(self.state.exists())

    def test_preference_bounds(self):
        for value in ('auto', 0.5, 3, 1.25):
            self.assertTrue(controls.valid(value))
        for value in (None, True, 0.49, 3.1, '1.5', float('nan')):
            self.assertFalse(controls.valid(value))


if __name__ == '__main__':
    unittest.main()
