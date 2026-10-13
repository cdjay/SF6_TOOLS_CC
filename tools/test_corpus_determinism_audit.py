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

    def test_roster_json_fixture_does_not_use_another_safe_loader(self):
        output = self.run_lua(
            "local old=function() return nil end; safe_load_json=old; "
            "dofile('tools/test_fighter_roster.lua'); assert(safe_load_json==old)"
        )
        self.assertIn("fighter roster tests passed", output)

    def test_native_menu_fixture_rebinds_and_restores_context(self):
        output = self.run_lua(
            "package.path='autorun/?.lua;'..package.path; "
            "local old={is_training_allowed=function() return false end,"
            "pause_open=function() return false end}; "
            "package.loaded['SF6CCTrainingLibrary/Context']=old; "
            "dofile('tools/test_native_library_menu.lua'); "
            "assert(package.loaded['SF6CCTrainingLibrary/Context']==old)"
        )
        self.assertIn("native menu presentation checks passed", output)

    def test_root_tab_fixture_does_not_leave_a_ticker_double(self):
        output = self.run_lua(
            "dofile('tools/test_native_library_tab.lua'); "
            "dofile('tools/test_native_library_ticker.lua')"
        )
        self.assertIn("PASS native ticker:", output)

    def test_root_tab_fixture_restores_the_library_module(self):
        output = self.run_lua(
            "local old={new=function() end,shared=function() end}; "
            "package.loaded['SF6CCTrainingLibrary/Library']=old; "
            "dofile('tools/test_native_library_tab.lua'); "
            "assert(package.loaded['SF6CCTrainingLibrary/Library']==old)"
        )
        self.assertIn("native root-tab contract checks", output)

    def test_deployment_fixture_restores_search_paths(self):
        output = self.run_lua(
            "local old_path,old_cpath=package.path,package.cpath; "
            "arg={'.'}; "
            "dofile('tools/test_training_deployment.lua'); "
            "assert(package.path==old_path and package.cpath==old_cpath); "
            "require('tools/training_record_bank/core')"
        )
        self.assertIn("isolated training deployment dependency gate", output)

    def test_standalone_fixture_really_excludes_legacy_globals(self):
        output = self.run_lua(
            "arg={'.'}; GameState={}; SF6CC_NativeNotes={}; SF6CC_RuntimeSafety={}; "
            "dofile('tools/test_training_standalone.lua')"
        )
        self.assertIn("standalone native eight-slot entry", output)


if __name__ == "__main__":
    unittest.main()
