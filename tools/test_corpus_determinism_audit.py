"""Regression checks for tied reports and shared-process Lua test fixtures."""

from copy import deepcopy
from pathlib import Path
import subprocess
import unittest

import corpus_determinism_audit as audit


ROOT = Path(__file__).resolve().parents[1]


class DeterminismAuditTests(unittest.TestCase):
    def test_tied_failures_have_order_independent_identity(self):
        normal = {"failures": [
            {"case_id": "first", "check": "display", "detail": "missing action"},
            {"case_id": "second", "check": "display", "detail": "missing action"},
        ], "checks": {"failed": 2}}
        reverse = deepcopy(normal)
        reverse["failures"].reverse()
        self.assertEqual(audit.stable_consumer(normal), audit.stable_consumer(reverse))

    def test_normalization_preserves_real_differences(self):
        before = {"failures": [{"case_id": "first", "detail": "old"}]}
        after = {"failures": [{"case_id": "first", "detail": "new"}]}
        self.assertNotEqual(audit.stable_consumer(before), audit.stable_consumer(after))

    def run_lua(self, code):
        result = subprocess.run(["lua", "-e", code], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_game_probe_rebinds_its_own_game_state_fixture(self):
        output = self.run_lua(
            "package.path=package.path..';./autorun/?.lua'; "
            "package.loaded['func/GameState']={p1={},p2={}}; "
            "local original=require('func/ComboTrials/GameProbe'); "
            "dofile('tools/test_combo_game_probe.lua'); "
            "assert(package.loaded['func/ComboTrials/GameProbe']==original)"
        )
        self.assertIn("combo game probe tests passed", output)

    def test_seed_fixture_restores_current_session_module(self):
        output = self.run_lua(
            "dofile('tools/test_training_library_native_seed.lua'); "
            "dofile('tools/test_native_recording_runtime.lua')"
        )
        self.assertIn("old recording session immediately", output)


if __name__ == "__main__":
    unittest.main()
