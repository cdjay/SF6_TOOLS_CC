#!/usr/bin/env python3
"""Build the repository test, fixture, and corpus inventory.

This tool is intentionally read-only with respect to production files. It runs
the checked-in tests, inspects test sources, and inventories loose/archived
combo JSON without extracting or rewriting any corpus.
"""

from __future__ import annotations

import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import zipfile


TEST_EXTENSIONS = {".lua", ".js", ".mjs", ".py"}
DOMAIN_ORDER = [
    "Raw Input",
    "Recording",
    "Action observation",
    "Timeline",
    "Side-relative direction",
    "Hitstop",
    "Normalization",
    "Move resolution",
    "AC relation",
    "BCM input facts",
    "Display",
    "Detection",
    "Demo",
    "Playback",
    "Fast-forward",
    "Legacy compatibility",
    "Serialization",
    "Metadata",
    "Generated artifact loading",
    "Unknown handling",
    "Character policies",
]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def run(command: list[str], cwd: Path) -> dict:
    started = time.perf_counter()
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return {
        "command": command,
        "exit_code": completed.returncode,
        "duration_ms": round((time.perf_counter() - started) * 1000),
        "output": completed.stdout.strip(),
    }


def discover_tests(root: Path) -> list[Path]:
    tests = [
        path
        for path in (root / "tools").rglob("test_*.*")
        if path.is_file() and path.suffix.lower() in TEST_EXTENSIONS
    ]
    release_test = root / "tools" / "test_release_version.ps1"
    if release_test.exists():
        tests.append(release_test)
    return sorted(set(tests), key=lambda path: rel(path, root).lower())


def infer_domains(name: str, content: str) -> list[str]:
    haystack = f"{name}\n{content}".lower()
    domains: set[str] = set()
    rules = {
        "Raw Input": ["raw_input", "raw input", "relative_raw_inputs"],
        "Recording": ["action_event_compiler", "record", "transcription"],
        "Action observation": ["observe", "action_restart", "action event"],
        "Timeline": ["timeline"],
        "Side-relative direction": ["facing_relative", "side-relative", "mirror"],
        "Hitstop": ["hitstop", "hit_stop"],
        "Normalization": ["normaliz", "sequence_grouping"],
        "Move resolution": ["command_resolution", "move_graph", "move resolver"],
        "AC relation": ["action_relations", "ac relation", "ac_"] ,
        "BCM input facts": ["bcm", "command_display", "command resolver"],
        "Display": ["display", "ui", "imgui", "preview", "web_character"],
        "Detection": ["validator", "matcher", "detect", "runtime_auditor"],
        "Demo": ["demo"],
        "Playback": ["playback", "replay"],
        "Fast-forward": ["fast_forward", "fast-forward", "skip_frame"],
        "Legacy compatibility": ["compatib", "legacy", "migration", "archive"],
        "Serialization": ["json", "scene_state", "checkpoint", "recoverable"],
        "Metadata": ["meta", "version", "catalog", "file_name", "editor"],
        "Generated artifact loading": ["generated", "move_graph", "artifact", "manifest"],
        "Unknown handling": ["unknown", "unsupported", "missing"],
        "Character policies": ["character", "dummy", "environment", "hp_vital"],
    }
    for domain, tokens in rules.items():
        if any(token in haystack for token in tokens):
            domains.add(domain)
    return [domain for domain in DOMAIN_ORDER if domain in domains]


def infer_test_type(path: Path, content: str) -> str:
    name = path.name.lower()
    if name == "character_exception_baseline.mjs":
        return "ORACLE"
    if "runtime" in name or "scenario" in name:
        return "SIMULATION"
    if "current_move_graph" in name or "generated_" in name:
        return "MODULE"
    if "editor_ui_contract" in name or "entry" in name or "main_local_limit" in name:
        return "MODULE"
    if "fixture" in content.lower() or "data/training" in content.lower():
        return "MODULE"
    return "UNIT"


def quoted_paths(content: str) -> list[str]:
    candidates = re.findall(
        r"[\"']([^\"']*(?:autorun|data|tests/fixtures|tools/fixtures)[^\"']*)[\"']",
        content.replace("\\", "/"),
        flags=re.IGNORECASE,
    )
    return sorted(set(candidate for candidate in candidates if len(candidate) < 300))


def module_references(content: str) -> list[str]:
    normalized = content.replace("\\", "/")
    references = set()
    patterns = [
        r"require\s*\(\s*[\"']([^\"']+)[\"']\s*\)",
        r"dofile\s*\(\s*[\"']([^\"']+)[\"']\s*\)",
        r"loadfile\s*\(\s*[\"']([^\"']+)[\"']\s*\)",
        r"from\s+[\"']([^\"']+)[\"']",
    ]
    for pattern in patterns:
        references.update(re.findall(pattern, normalized, flags=re.IGNORECASE | re.DOTALL))
    references.update(
        path for path in quoted_paths(content) if path.lower().startswith("autorun/")
    )
    return sorted(references)


def assertion_profile(content: str, extension: str) -> dict:
    if extension == ".lua":
        total = len(re.findall(r"\bassert\s*\(", content))
    elif extension in {".js", ".mjs"}:
        total = len(re.findall(r"\bassert(?:\.[A-Za-z]+)?\s*\(", content))
    elif extension == ".py":
        total = len(re.findall(r"\bself\.assert[A-Za-z]+\s*\(", content))
    else:
        total = len(re.findall(r"\b(?:Assert|throw)\b", content, flags=re.IGNORECASE))
    weak = len(
        re.findall(
            r"(?:~=\s*nil|!=\s*null|not\s+none|assert\.ok|doesnotthrow|test-path)",
            content,
            flags=re.IGNORECASE,
        )
    )
    source_text = len(
        re.findall(
            r"(?:source:find|\.includes\(|\.match\(|-match\s+)",
            content,
            flags=re.IGNORECASE,
        )
    )
    if total == 0:
        strength = "UNKNOWN"
    elif weak > total / 2:
        strength = "WEAK"
    elif source_text > total / 2:
        strength = "STATIC_CONTRACT"
    else:
        strength = "SEMANTIC_ASSERTIONS_PRESENT"
    return {
        "assertion_tokens": total,
        "weak_assertion_tokens": weak,
        "source_text_assertion_tokens": source_text,
        "strength": strength,
    }


def infer_consumers(content: str) -> list[str]:
    lowered = content.lower()
    tokens = {
        "recording": ["record", "actioneventcompiler", "observe_capture"],
        "detection": ["detect", "validator", "matcher", "match_expected"],
        "display": ["display", "commandresolver", "imgui"],
        "demo": ["demo"],
        "playback": ["playback", "replay"],
        "audit": ["audit", "runtimeauditor"],
    }
    return [name for name, values in tokens.items() if any(value in lowered for value in values)]


def test_inventory(root: Path) -> list[dict]:
    inventory = []
    for path in discover_tests(root):
        content = path.read_text(encoding="utf-8", errors="replace")
        location = rel(path, root)
        fixtures = quoted_paths(content)
        modules = module_references(content)
        source_contract = any(token in content for token in ["source:find", "readFileSync", "Get-Content"])
        expected_source = "hand-authored assertions over inline/synthetic fixtures"
        if any("tests/fixtures" in fixture.lower() for fixture in fixtures):
            expected_source = "checked-in fixture plus hand-authored assertions"
        elif any("tools/fixtures" in fixture.lower() for fixture in fixtures):
            expected_source = "checked-in generated fixture plus hand-authored assertions"
        elif source_contract:
            expected_source = "source-text contract assertions"
        independence = "MEDIUM"
        if source_contract:
            independence = "LOW"
        inventory.append(
            {
                "name": path.stem,
                "location": location,
                "language": path.suffix.lower().lstrip("."),
                "type": infer_test_type(path, content),
                "domains": infer_domains(location, content),
                "input_source": "checked-in fixture" if fixtures else "inline/synthetic fixture",
                "fixture_references": fixtures,
                "expected_source": expected_source,
                "consumers_exercised": infer_consumers(content),
                "production_modules_exercised": modules,
                "assertions": assertion_profile(content, path.suffix.lower()),
                "independence_level": independence,
                "inventory_method": "static inventory; classifications require manual governance review",
            }
        )

    oracle_path = root / "tools" / "character_exception_baseline.mjs"
    if oracle_path.exists():
        content = oracle_path.read_text(encoding="utf-8", errors="replace")
        inventory.append(
            {
                "name": "character_exception_sealed_oracle",
                "location": rel(oracle_path, root),
                "language": "mjs",
                "type": "ORACLE",
                "domains": ["Move resolution", "Display", "Detection", "Legacy compatibility", "Character policies"],
                "input_source": "current production exception/override/compatibility/generated data",
                "fixture_references": [
                    "tests/fixtures/character_exception_baseline.json",
                    "tests/fixtures/character_exception_legacy_oracle.json",
                ],
                "expected_source": "sealed snapshot originally generated by this same tool from production data",
                "consumers_exercised": [],
                "production_modules_exercised": [],
                "assertions": assertion_profile(content, ".mjs"),
                "independence_level": "LOW",
                "inventory_method": "manual classification: asset integrity and source-drift gate; not an independent runtime oracle",
            }
        )
    return sorted(inventory, key=lambda item: item["location"].lower())


def execute_baseline(root: Path, inventory: list[dict]) -> dict:
    tracked_lua = subprocess.run(
        ["git", "ls-files", "*.lua"],
        cwd=root,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        check=True,
    ).stdout.splitlines()
    parse_results = [run(["luac", "-p", "--", path], root) for path in tracked_lua]
    test_results = []
    for item in inventory:
        location = item["location"]
        if item["type"] == "ORACLE":
            continue
        extension = Path(location).suffix.lower()
        if extension == ".lua":
            command = ["lua", location]
        elif extension in {".js", ".mjs"}:
            command = ["node", location]
        elif extension == ".py":
            command = ["python", location]
        elif extension == ".ps1":
            command = ["pwsh", "-NoProfile", "-File", location]
        else:
            continue
        result = run(command, root)
        result["location"] = location
        test_results.append(result)
    oracle_results = [
        run(["node", "tools/character_exception_baseline.mjs", "--check"], root),
        run(["node", "tools/character_exception_baseline.mjs", "--verify-source"], root),
    ]
    return {
        "lua_parse": {
            "total": len(parse_results),
            "passed": sum(result["exit_code"] == 0 for result in parse_results),
            "failed": sum(result["exit_code"] != 0 for result in parse_results),
            "failures": [result for result in parse_results if result["exit_code"] != 0],
        },
        "tests": {
            "total_files": len(test_results),
            "passed_files": sum(result["exit_code"] == 0 for result in test_results),
            "failed_files": sum(result["exit_code"] != 0 for result in test_results),
            "results": test_results,
        },
        "sealed_oracle": {
            "integrity_check": oracle_results[0],
            "current_source_check": oracle_results[1],
        },
    }


def combo_document(raw: bytes, source: str) -> dict | None:
    try:
        document = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(document, list) or not document or not isinstance(document[0], dict):
        return None
    first = document[0]
    combo_keys = {
        "_xt_meta",
        "expected_combo",
        "timeline",
        "raw_inputs",
        "relative_raw_inputs",
        "combo_stats",
    }
    if not combo_keys.intersection(first):
        return None
    metadata = first.get("_xt_meta") if isinstance(first.get("_xt_meta"), dict) else {}
    character = metadata.get("character")
    if not character:
        match = re.search(r"(?:customcombos[/\\]|^)([A-Za-z0-9]+)(?:_CustomCombos)?[/\\]", source)
        character = match.group(1) if match else "Unknown"
    schema = metadata.get("schema", "unknown")
    if schema == 2:
        generation = "current_v2"
    elif schema == "unknown":
        generation = "legacy_or_unknown"
    else:
        generation = f"schema_{schema}"
    flags = {
        "relative_raw_inputs": False,
        "raw_inputs": False,
        "timeline": False,
        "structured_timeline": False,
        "string_gap_timeline": False,
        "same_frame_timeline_observed": False,
    }
    action_count = 0
    timeline_event_count = 0
    for step in document:
        if not isinstance(step, dict):
            continue
        action_count += int(step.get("expected_combo") is not None or step.get("action_id") is not None)
        flags["relative_raw_inputs"] |= isinstance(step.get("relative_raw_inputs"), list)
        flags["raw_inputs"] |= isinstance(step.get("raw_inputs"), list)
        timeline = step.get("timeline")
        if isinstance(timeline, list):
            flags["timeline"] = True
            timeline_event_count += len(timeline)
            flags["structured_timeline"] |= any(isinstance(event, dict) for event in timeline)
            flags["string_gap_timeline"] |= any(isinstance(event, str) for event in timeline)
            frames = []
            for event in timeline:
                if isinstance(event, dict):
                    frame = event.get("frame")
                    if isinstance(frame, (int, float)):
                        frames.append(frame)
            flags["same_frame_timeline_observed"] |= len(frames) != len(set(frames))
    canonical = json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "character": str(character),
        "schema": str(schema),
        "generation": generation,
        "step_count": len(document),
        "action_count": action_count,
        "timeline_event_count": timeline_event_count,
        "flags": flags,
        "exact_hash": sha256(raw),
        "canonical_json_hash": sha256(canonical),
    }


class CorpusAccumulator:
    def __init__(self) -> None:
        self.total_json = 0
        self.combo_json = 0
        self.non_combo_json = 0
        self.parse_or_shape_failures = 0
        self.exact_hashes: set[str] = set()
        self.canonical_hashes: set[str] = set()
        self.logical_keys: set[str] = set()
        self.characters: dict[str, int] = {}
        self.schemas: dict[str, int] = {}
        self.generations: dict[str, int] = {}
        self.properties = {
            "relative_raw_inputs": 0,
            "raw_inputs": 0,
            "timeline": 0,
            "structured_timeline": 0,
            "string_gap_timeline": 0,
            "same_frame_timeline_observed": 0,
        }
        self.step_count = 0
        self.action_count = 0
        self.timeline_event_count = 0

    def add(self, source: str, raw: bytes) -> None:
        self.total_json += 1
        combo = combo_document(raw, source)
        if combo is None:
            self.non_combo_json += 1
            self.parse_or_shape_failures += 1
            return
        self.combo_json += 1
        self.exact_hashes.add(combo["exact_hash"])
        self.canonical_hashes.add(combo["canonical_json_hash"])
        basename = Path(source.replace("\\", "/")).name.lower()
        self.logical_keys.add(f"{combo['character'].lower()}::{basename}")
        self.characters[combo["character"]] = self.characters.get(combo["character"], 0) + 1
        self.schemas[combo["schema"]] = self.schemas.get(combo["schema"], 0) + 1
        self.generations[combo["generation"]] = self.generations.get(combo["generation"], 0) + 1
        for key, value in combo["flags"].items():
            self.properties[key] += int(value)
        self.step_count += combo["step_count"]
        self.action_count += combo["action_count"]
        self.timeline_event_count += combo["timeline_event_count"]

    def summary(self) -> dict:
        return {
            "json_files_seen": self.total_json,
            "combo_json_files": self.combo_json,
            "non_combo_or_unparseable_json": self.non_combo_json,
            "unique_exact_bytes": len(self.exact_hashes),
            "unique_canonical_json": len(self.canonical_hashes),
            "logical_character_filename_keys": len(self.logical_keys),
            "characters": dict(sorted(self.characters.items())),
            "schemas": dict(sorted(self.schemas.items())),
            "generation_classification": dict(sorted(self.generations.items())),
            "properties": self.properties,
            "total_steps": self.step_count,
            "observed_action_fields": self.action_count,
            "timeline_events": self.timeline_event_count,
            "dedup_note": "Exact/canonical JSON identity only; semantic duplicate classification is not claimed in phase one.",
        }


def scan_loose(root: Path) -> tuple[dict, CorpusAccumulator]:
    accumulator = CorpusAccumulator()
    if not root.exists():
        return {"status": "MISSING", "directory_count": 0, **accumulator.summary()}, accumulator
    directory_count = sum(path.is_dir() for path in root.rglob("*"))
    files = sorted(root.rglob("*.json"))
    for path in files:
        accumulator.add(str(path), path.read_bytes())
    return {
        "status": "AVAILABLE",
        "root": str(root),
        "directory_count": directory_count,
        **accumulator.summary(),
    }, accumulator


def scan_archives(root: Path) -> dict:
    combined = CorpusAccumulator()
    archive_rows = []
    if not root.exists():
        return {"status": "MISSING", "archives": [], "combined": combined.summary()}
    for archive in sorted(root.rglob("*.zip")):
        accumulator = CorpusAccumulator()
        error = None
        try:
            with zipfile.ZipFile(archive) as bundle:
                for info in bundle.infolist():
                    if info.is_dir() or not info.filename.lower().endswith(".json"):
                        continue
                    accumulator.add(f"{archive}!/{info.filename}", bundle.read(info))
        except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
            error = f"{type(exc).__name__}: {exc}"
        summary = accumulator.summary()
        archive_rows.append(
            {
                "archive": str(archive),
                "size_bytes": archive.stat().st_size,
                "error": error,
                **summary,
            }
        )
        combined.total_json += accumulator.total_json
        combined.combo_json += accumulator.combo_json
        combined.non_combo_json += accumulator.non_combo_json
        combined.parse_or_shape_failures += accumulator.parse_or_shape_failures
        combined.exact_hashes.update(accumulator.exact_hashes)
        combined.canonical_hashes.update(accumulator.canonical_hashes)
        combined.logical_keys.update(accumulator.logical_keys)
        for mapping_name in ["characters", "schemas", "generations", "properties"]:
            target = getattr(combined, mapping_name)
            source = getattr(accumulator, mapping_name)
            for key, value in source.items():
                target[key] = target.get(key, 0) + value
        combined.step_count += accumulator.step_count
        combined.action_count += accumulator.action_count
        combined.timeline_event_count += accumulator.timeline_event_count
    return {
        "status": "AVAILABLE",
        "archive_count": len(archive_rows),
        "archive_errors": sum(row["error"] is not None for row in archive_rows),
        "archives": archive_rows,
        "combined": combined.summary(),
    }


def validate_frozen_manifest(repo: Path, frozen_root: Path, archive_root: Path | None = None) -> dict:
    manifest_path = repo / "docs" / "backup" / "SF6CC_VALIDATED_COMBO_BACKUP_2026-08-06_V1.manifest.json"
    if not manifest_path.exists():
        return {"status": "MANIFEST_MISSING"}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    failures = []
    verified = 0
    for entry in manifest.get("files", []):
        character = entry["character"]
        character_root = frozen_root / f"{character}_CustomCombos"
        matches = list(character_root.rglob(entry["filename"])) if character_root.exists() else []
        if not matches:
            failures.append({"path": str(character_root / entry["filename"]), "reason": "missing"})
            continue
        if len(matches) > 1:
            failures.append({
                "path": str(character_root),
                "reason": "ambiguous_duplicate_filename",
                "matches": [str(match) for match in matches],
            })
            continue
        candidate = matches[0]
        raw = candidate.read_bytes()
        if len(raw) != entry["size"]:
            failures.append({"path": str(candidate), "reason": "size_mismatch"})
            continue
        if sha256(raw) != entry["sha256"]:
            failures.append({"path": str(candidate), "reason": "sha256_mismatch"})
            continue
        verified += 1
    loose_source_status = "PASS" if not failures and verified == manifest.get("combo_count") else "FAIL"
    archive_declaration = manifest.get("archive", {})
    archive_search_root = archive_root if archive_root is not None else frozen_root.parent
    archive_matches = list(archive_search_root.rglob(
        archive_declaration.get("filename", "__missing__")
    )) if archive_search_root.exists() else []
    archive_status = "UNAVAILABLE"
    archive_verification = None
    if archive_matches:
        archive_path = archive_matches[0]
        archive_raw = archive_path.read_bytes()
        archive_verification = {
            "path": str(archive_path),
            "size_matches": len(archive_raw) == archive_declaration.get("size_bytes"),
            "sha256_matches": sha256(archive_raw) == archive_declaration.get("sha256"),
        }
        archive_status = "PASS" if all(archive_verification.values()) else "FAIL"
    if loose_source_status == "PASS" and archive_status == "UNAVAILABLE":
        overall_status = "LOOSE_SOURCE_PASS_ARCHIVE_UNAVAILABLE"
    elif loose_source_status == "PASS" and archive_status == "PASS":
        overall_status = "PASS"
    else:
        overall_status = "FAIL"
    return {
        "status": overall_status,
        "loose_source_status": loose_source_status,
        "archive_status": archive_status,
        "archive_verification": archive_verification,
        "manifest": str(manifest_path),
        "snapshot_id": manifest.get("snapshot_id"),
        "target_game_build": manifest.get("target_game_build"),
        "declared_combo_count": manifest.get("combo_count"),
        "verified_files": verified,
        "failures": failures,
        "character_distribution": manifest.get("characters", {}),
        "root_hash": manifest.get("root_hash"),
        "archive": archive_declaration,
    }


def git_metadata(root: Path) -> dict:
    def git(*args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=root,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            check=True,
        ).stdout.strip()

    return {
        "repo_root": str(root),
        "branch": git("branch", "--show-current"),
        "head": git("rev-parse", "HEAD"),
        "status_before_report": git("status", "--short"),
        "worktrees": git("worktree", "list", "--porcelain"),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--backup-root",
        type=Path,
        default=Path(r"D:\CP\SF6CC\reframework\release\tester_packages"),
    )
    parser.add_argument(
        "--game-combo-root",
        type=Path,
        default=Path(
            r"D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\data\TrainingComboTrials_data\CustomCombos"
        ),
    )
    parser.add_argument("--archive-root", type=Path)
    parser.add_argument("--audit-date", default=date.today().isoformat())
    parser.add_argument("--run-tests", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    root = args.repo_root.resolve()
    inventory = test_inventory(root)
    frozen_root = args.backup_root / "0803"
    repository_corpus, _ = scan_loose(root / "data" / "TrainingComboTrials_data" / "CustomCombos")
    game_corpus, _ = scan_loose(args.game_combo_root)
    frozen_corpus, _ = scan_loose(frozen_root)
    backup_loose, _ = scan_loose(args.backup_root)
    archive_corpus = scan_archives(args.backup_root)

    payload = {
        "schema": "sf6cc.repository.test-audit.v1",
        "audit_date": args.audit_date,
        "scope": ["Baseline", "Test Inventory", "Corpus Inventory", "Evidence Matrix inputs"],
        "git": git_metadata(root),
        "environment": {
            "python": os.sys.version,
            "platform": os.name,
            "backup_root": str(args.backup_root),
            "game_combo_root": str(args.game_combo_root),
            "archive_root": None if args.archive_root is None else str(args.archive_root),
        },
        "test_inventory": {
            "count": len(inventory),
            "items": inventory,
        },
        "baseline_execution": execute_baseline(root, inventory) if args.run_tests else None,
        "corpus_inventory": {
            "repository_custom_combos": repository_corpus,
            "game_runtime_custom_combos": game_corpus,
            "frozen_0803_loose": frozen_corpus,
            "all_tester_packages_loose": backup_loose,
            "all_tester_packages_archives": archive_corpus,
            "frozen_manifest_validation": validate_frozen_manifest(
                root, frozen_root, args.archive_root
            ),
        },
        "limitations": [
            "Phase one inventories corpus identity and structural properties but does not execute production consumers over the corpus.",
            "Canonical JSON deduplication is not semantic deduplication.",
            "Static test classification is an audit starting point, not proof of assertion independence.",
            "No real-game smoke evidence is produced by this tool.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.output),
        "test_inventory": len(inventory),
        "test_failures": None if payload["baseline_execution"] is None else payload["baseline_execution"]["tests"]["failed_files"],
        "frozen_combo_count": frozen_corpus["combo_json_files"],
        "manifest_status": payload["corpus_inventory"]["frozen_manifest_validation"]["status"],
        "backup_loose_combo_count": backup_loose["combo_json_files"],
        "archive_combo_count": archive_corpus["combined"]["combo_json_files"],
    }, indent=2))


if __name__ == "__main__":
    main()
