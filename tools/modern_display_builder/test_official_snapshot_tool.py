#!/usr/bin/env python3

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import official_snapshot_tool as tool


class OfficialSnapshotToolTest(unittest.TestCase):
    def test_version_normalization_and_default(self) -> None:
        self.assertEqual(tool.normalize_version("2026.5.28"), "2026-05-28")
        self.assertEqual(tool.normalize_version("2026-05-28"), "2026-05-28")
        with tempfile.TemporaryDirectory() as root:
            Path(root, "2026.5.28").mkdir()
            Path(root, "2026-07-01").mkdir()
            self.assertEqual(tool.default_version(Path(root)), "2026-07-01")

    def test_semantic_rows_do_not_trust_official_action_id(self) -> None:
        rows = tool.semantic_rows([{
            "actionId": 625,
            "webId": 7,
            "skill": "Test Move",
            "type": "NORMAL",
            "command": "2 + LK",
            "command_modern": "AUTO + L",
        }])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["classic_display"], "2 + LK")
        self.assertEqual(rows[0]["modern_display"], "AUTO + 弱")
        self.assertNotIn("action_id", rows[0])

    def test_diff_reports_changed_field(self) -> None:
        entry = {"fighter_id": 1, "url": "https://example.invalid"}
        before = tool.build_snapshot("Ryu", entry, [{
            "actionId": 600, "skill": "LP", "command": "LP", "command_modern": "L"
        }], "chunk", "a", "2026-05-28")
        after = json.loads(json.dumps(before))
        after["_official_frame"][0]["command_modern"] = "AUTO + L"
        after["_official_semantic_rows"] = tool.semantic_rows(after["_official_frame"])
        difference = tool.diff_snapshot(before, after)
        self.assertFalse(difference["baseline"])
        self.assertEqual(difference["changed_actions"][0]["action_id"], "600")
        self.assertTrue(any(item["path"].endswith("command_modern")
                            for item in difference["changed_actions"][0]["fields"]))
        self.assertEqual(difference["semantic_rows_changed"], 1)


    def test_release_day_fighter_without_official_page(self) -> None:
        manifest = {
            "Ryu": {"fighter_id": 1, "official_name": "ryu", "url": "https://example.invalid/ryu"},
            "Arjun": {"fighter_id": 34, "official_name": "arjun", "url": "https://example.invalid/arjun"},
        }
        modules = {"ryuVar": {"frame": [{"actionId": 600, "skill": "LP", "command": "LP"}]}}
        var_map = {"ryu": "ryuVar"}
        with self.assertRaisesRegex(RuntimeError, "Arjun"):
            tool.snapshots_from_modules(manifest, modules, var_map, "chunk", "sha", "2026-10-13")
        snapshots, missing = tool.snapshots_from_modules(
            manifest, modules, var_map, "chunk", "sha", "2026-10-13", allow_missing=True)
        self.assertEqual(list(snapshots), ["Ryu"])
        self.assertEqual(missing, ["Arjun"])

    def test_roster_is_the_default_manifest(self) -> None:
        manifest = tool.load_manifest(tool.DEFAULT_MANIFEST)
        self.assertEqual(manifest["Akuma"]["official_name"], "gouki_akuma")
        self.assertEqual(manifest["MBison"]["url"],
                         "https://www.streetfighter.com/6/zh-hant/character/vega_mbison/frame")
        self.assertEqual(len({entry["fighter_id"] for entry in manifest.values()}), len(manifest))


if __name__ == "__main__":
    unittest.main()
