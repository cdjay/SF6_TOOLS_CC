#!/usr/bin/env python3
"""Execute every exact-unique combo-shaped tester package artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile
import zipfile

import task_c_full_corpus_audit as core


COMBO_KEYS = {
    "_xt_meta",
    "expected_combo",
    "timeline",
    "raw_inputs",
    "relative_raw_inputs",
    "combo_stats",
}


def combo_document(raw: bytes):
    try:
        document = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(document, list) or not document or not isinstance(document[0], dict):
        return None
    if not COMBO_KEYS.intersection(document[0]):
        return None
    return document


def infer_character(document: list, source: str) -> str:
    metadata = document[0].get("_xt_meta")
    if isinstance(metadata, dict) and metadata.get("character"):
        return str(metadata["character"])
    normalized = source.replace("\\", "/")
    patterns = [
        r"/CustomCombos/([^/]+)/",
        r"/([^/]+)_CustomCombos/",
        r"^([^/]+)_CustomCombos/",
    ]
    for pattern in patterns:
        match = re.search(pattern, normalized, flags=re.IGNORECASE)
        if match:
            return match.group(1)
    return "Unknown"


def collect_cases(backup_root: Path, stage: Path) -> tuple[list[dict], dict]:
    seen = set()
    cases = []
    counts = {
        "loose_json_seen": 0,
        "archive_json_seen": 0,
        "combo_shaped_occurrences": 0,
        "exact_duplicate_occurrences": 0,
        "archive_count": 0,
        "archive_errors": [],
    }

    def add(raw: bytes, source: str, filename: str, source_kind: str) -> None:
        document = combo_document(raw)
        if document is None:
            return
        counts["combo_shaped_occurrences"] += 1
        digest = hashlib.sha256(raw).hexdigest()
        if digest in seen:
            counts["exact_duplicate_occurrences"] += 1
            return
        seen.add(digest)
        character = infer_character(document, source)
        staged = stage / f"{len(cases) + 1:05d}_{digest[:16]}.json"
        staged.write_bytes(raw)
        cases.append({
            "character": character,
            "filename": filename,
            "path": str(staged),
            "source": source,
            "source_kind": source_kind,
            "exact_sha256": digest,
            "sequence": document,
        })

    for filename in sorted(backup_root.rglob("*.json")):
        counts["loose_json_seen"] += 1
        add(filename.read_bytes(), str(filename), filename.name, "loose")

    for archive in sorted(backup_root.rglob("*.zip")):
        counts["archive_count"] += 1
        try:
            with zipfile.ZipFile(archive) as bundle:
                for entry in bundle.infolist():
                    if entry.is_dir() or not entry.filename.lower().endswith(".json"):
                        continue
                    counts["archive_json_seen"] += 1
                    add(
                        bundle.read(entry),
                        f"{archive}!/{entry.filename}",
                        Path(entry.filename).name,
                        "zip",
                    )
        except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
            counts["archive_errors"].append({
                "archive": str(archive),
                "error": f"{type(exc).__name__}: {exc}",
            })
    counts["exact_unique_combo_cases"] = len(cases)
    return cases, counts


def runtime_documents(repo: Path) -> dict:
    documents = {
        "sf6cc/version.json": core.load_json(repo / "data" / "SF6CC" / "version.json"),
    }
    data_root = repo / "data" / "TrainingComboTrials_data"
    for directory in [
        "command_display",
        "command_display_overrides",
        "action_compatibility",
        "exceptions",
        "generated_semantics",
    ]:
        source = data_root / directory
        for filename in source.glob("*.json") if source.exists() else []:
            key = core.normalized_runtime_path(
                f"TrainingComboTrials_data/{directory}/{filename.name}"
            )
            documents[key] = core.load_json(filename)
    return documents


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--backup-root",
        type=Path,
        default=Path(r"D:\CP\SF6CC\reframework\release\tester_packages"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("docs/audits/task-c"),
    )
    parser.add_argument("--case-order", choices=["normal", "reverse"], default="normal")
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    output_dir = args.output_dir if args.output_dir.is_absolute() else repo / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    roundtrip_output = output_dir / "all-accessible-corpus-roundtrip.json"
    consumer_output = output_dir / "all-accessible-corpus-consumer.json"
    combined_output = output_dir / "all-accessible-corpus-audit.json"

    with tempfile.TemporaryDirectory(prefix="sf6cc-task-c-all-corpus-") as temporary:
        temporary_root = Path(temporary)
        stage = temporary_root / "cases"
        stage.mkdir()
        cases, inventory = collect_cases(args.backup_root, stage)
        if args.case_order == "reverse":
            cases.reverse()
        snapshot_id = "ALL-ACCESSIBLE-TESTER-PACKAGES-EXACT-UNIQUE-2026-08-15"
        case_index = {
            "snapshot_id": snapshot_id,
            "target_game_build": "mixed_or_unknown",
            "cases": [
                {
                    "character": case["character"],
                    "filename": case["filename"],
                    "path": case["path"],
                }
                for case in cases
            ],
        }
        case_index_path = temporary_root / "case-index.json"
        case_index_path.write_text(
            json.dumps(case_index, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        roundtrip_run = core.run(
            [
                "node",
                "tools/task_c_corpus_roundtrip.mjs",
                "--case-index",
                str(case_index_path),
                "--output",
                str(roundtrip_output),
            ],
            repo,
        )

        lua_input = {
            "snapshot_id": snapshot_id,
            "target_game_build": "mixed_or_unknown",
            "cases": cases,
            "json_documents": runtime_documents(repo),
        }
        coverage = core.compute_coverage(repo, lua_input)
        lua_data_path = temporary_root / "corpus.lua"
        lua_data_path.write_text("return " + core.lua_value(lua_input) + "\n", encoding="ascii")
        consumer_run = core.run(
            [
                "lua",
                "tools/task_c_full_corpus_consumer.lua",
                str(lua_data_path),
                str(consumer_output),
            ],
            repo,
        )

    roundtrip = core.load_json(roundtrip_output) if roundtrip_output.exists() else None
    consumer = core.load_json(consumer_output) if consumer_output.exists() else None
    combined = {
        "schema": "sf6cc.task-c.all-accessible-corpus-audit.v1",
        "audit_date": "2026-08-15",
        "corpus_snapshot": "ALL-ACCESSIBLE-TESTER-PACKAGES-EXACT-UNIQUE-2026-08-15",
        "case_order": args.case_order,
        "inventory": inventory,
        "roundtrip_run": roundtrip_run,
        "consumer_run": consumer_run,
        "roundtrip": roundtrip,
        "consumer": consumer,
        "coverage": coverage,
        "all_accessible_exact_unique_corpus_executed": bool(
            roundtrip
            and consumer
            and roundtrip.get("files") == inventory["exact_unique_combo_cases"]
            and consumer.get("cases") == inventory["exact_unique_combo_cases"]
        ),
        "classification_note": "Historical revisions and mixed-build artifacts are evidence inputs, not current truth. Current-map failures require compatibility/build classification before escalation.",
    }
    combined_output.write_text(
        json.dumps(combined, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "output": str(combined_output),
        "unique_cases": inventory["exact_unique_combo_cases"],
        "executed": combined["all_accessible_exact_unique_corpus_executed"],
        "roundtrip_failed": None if roundtrip is None else roundtrip["failed"],
        "consumer_failures": None if consumer is None else consumer["failure_count"],
    }, indent=2))


if __name__ == "__main__":
    main()
