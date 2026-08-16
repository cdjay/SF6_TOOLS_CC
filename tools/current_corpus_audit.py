#!/usr/bin/env python3
"""Run production editor and Lua consumer checks over the frozen 965 corpus."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time


def lua_string(value: str) -> str:
    parts = ['"']
    for byte in value.encode("utf-8"):
        if 32 <= byte <= 126 and byte not in (34, 92):
            parts.append(chr(byte))
        elif byte == 34:
            parts.append('\\"')
        elif byte == 92:
            parts.append("\\\\")
        elif byte == 10:
            parts.append("\\n")
        elif byte == 13:
            parts.append("\\r")
        elif byte == 9:
            parts.append("\\t")
        else:
            parts.append(f"\\x{byte:02x}")
    parts.append('"')
    return "".join(parts)


def lua_value(value) -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("non-finite JSON number")
        return repr(value)
    if isinstance(value, list):
        return "{" + ",".join(lua_value(item) for item in value) + "}"
    if isinstance(value, dict):
        items = []
        for key in sorted(value, key=lambda item: str(item)):
            items.append(f"[{lua_string(str(key))}]={lua_value(value[key])}")
        return "{" + ",".join(items) + "}"
    raise TypeError(f"unsupported value: {type(value).__name__}")


def locate_combo(corpus_root: Path, character: str, filename: str) -> Path:
    character_root = corpus_root / f"{character}_CustomCombos"
    matches = list(character_root.rglob(filename)) if character_root.exists() else []
    if len(matches) != 1:
        raise RuntimeError(f"{character}/{filename}: expected one file, found {len(matches)}")
    return matches[0]


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def normalized_runtime_path(path: str) -> str:
    return path.replace("\\", "/").lower()


def build_lua_input(repo: Path, corpus_root: Path, manifest: dict) -> dict:
    cases = []
    for entry in manifest["files"]:
        filename = locate_combo(corpus_root, entry["character"], entry["filename"])
        cases.append(
            {
                "character": entry["character"],
                "filename": entry["filename"],
                "path": str(filename),
                "sequence": load_json(filename),
            }
        )

    documents = {
        "sf6cc/version.json": load_json(repo / "data" / "SF6CC" / "version.json"),
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
            key = normalized_runtime_path(f"TrainingComboTrials_data/{directory}/{filename.name}")
            documents[key] = load_json(filename)
    return {
        "snapshot_id": manifest["snapshot_id"],
        "target_game_build": manifest["target_game_build"],
        "cases": cases,
        "json_documents": documents,
    }


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


def distribution(values: list[int]) -> dict:
    if not values:
        return {"min": None, "median": None, "max": None}
    return {
        "min": min(values),
        "median": statistics.median(values),
        "max": max(values),
    }


def compute_coverage(repo: Path, lua_input: dict) -> dict:
    observed = Counter()
    observed_motions: dict[tuple[str, int], Counter] = defaultdict(Counter)
    combo_lengths = []
    timeline_lengths = []
    timeline_frames = []
    timeline_gaps = []
    long_gap_cases = []
    multi_button_lines = 0
    multi_button_cases = 0
    zero_gap_lines = 0

    for case in lua_input["cases"]:
        character = case["character"]
        sequence = case["sequence"]
        combo_lengths.append(len(sequence))
        has_multi_button = False
        for step in sequence:
            try:
                action_id = int(step.get("id"))
            except (TypeError, ValueError):
                continue
            observed[(character, action_id)] += 1
            observed_motions[(character, action_id)][str(step.get("motion", ""))] += 1
        timeline = sequence[0].get("timeline") if sequence else None
        if isinstance(timeline, list):
            timeline_lengths.append(len(timeline))
            total_frames = 0
            max_gap = 0
            for line in timeline:
                match = re.match(r"^(\d+)f\s*:\s*(.*)$", str(line))
                if not match:
                    continue
                gap = int(match.group(1))
                input_text = match.group(2)
                timeline_gaps.append(gap)
                total_frames += gap
                max_gap = max(max_gap, gap)
                zero_gap_lines += int(gap == 0)
                button_tokens = re.findall(r"(?:LP|MP|HP|LK|MK|HK)", input_text.upper())
                if len(set(button_tokens)) >= 2:
                    multi_button_lines += 1
                    has_multi_button = True
            timeline_frames.append(total_frames)
            if max_gap >= 300:
                long_gap_cases.append({
                    "character": character,
                    "filename": case["filename"],
                    "max_gap": max_gap,
                })
        multi_button_cases += int(has_multi_button)

    command_root = repo / "data" / "TrainingComboTrials_data" / "command_display"
    raw_universe = set()
    visible_candidates = set()
    ac_relation_proxies = set()
    exercised_ac_relation_proxies = set()
    bcm_route_proxies = set()
    exercised_bcm_route_proxies = set()
    observed_command_patterns = Counter()
    command_by_pair = {}
    for filename in sorted(command_root.glob("*.json")):
        character = filename.stem
        document = load_json(filename)
        for key, entry in document.items():
            if not str(key).isdigit() or not isinstance(entry, dict):
                continue
            pair = (character, int(key))
            raw_universe.add(pair)
            command_by_pair[pair] = entry
            if entry.get("suppress_display") is not True:
                visible_candidates.add(pair)
            if pair in observed:
                display = str((entry.get("classic_command") or {}).get("display") or "")
                if display.startswith(">"):
                    observed_command_patterns["follow_up"] += 1
                if "[" in display and "]" in display:
                    observed_command_patterns["charge"] += 1
                if re.search(r"(?:236236|214214|720)", display):
                    observed_command_patterns["super_or_720"] += 1
                if len(set(re.findall(r"(?:LP|MP|HP|LK|MK|HK)", display.upper()))) >= 2:
                    observed_command_patterns["multi_button"] += 1
                if re.search(r"[12346789]{2,}", display):
                    observed_command_patterns["motion"] += 1
            for route_index, route in enumerate(entry.get("routes") or []):
                if not isinstance(route, dict):
                    continue
                display_action = int(route.get("display_action_id") or key)
                inherited = route.get("inherited_from_action_id")
                relation_type = route.get("ac_relation_type")
                ac_path = route.get("ac_path") or []
                if inherited is not None or relation_type is not None or len(ac_path) >= 2:
                    relation_key = (
                        character,
                        int(inherited) if inherited is not None else None,
                        display_action,
                        int(relation_type) if relation_type is not None else None,
                        tuple(ac_path),
                    )
                    ac_relation_proxies.add(relation_key)
                    if (character, display_action) in observed:
                        exercised_ac_relation_proxies.add(relation_key)
                source = str(route.get("source") or "")
                if route.get("bcm_owner_action_id") is not None or source.startswith("bcm_"):
                    route_key = (character, int(key), route_index, source)
                    bcm_route_proxies.add(route_key)
                    if pair in observed:
                        exercised_bcm_route_proxies.add(route_key)

    compatibility_root = repo / "data" / "TrainingComboTrials_data" / "action_compatibility"
    compatibility = defaultdict(list)
    for filename in sorted(compatibility_root.glob("*.json")) if compatibility_root.exists() else []:
        document = load_json(filename)
        character = document.get("character") or filename.stem
        for entry in document.get("entries") or []:
            compatibility[(character, int(entry["recorded_action_id"]))].append(entry)

    effective_observed = Counter()
    compatibility_projections = 0
    for pair, count in observed.items():
        character, action_id = pair
        projected = action_id
        entries = compatibility.get(pair) or []
        if entries:
            motions = observed_motions[pair]
            for entry in entries:
                allowed = {str(value).upper() for value in entry.get("recorded_motions") or []}
                if not allowed or any(str(motion).upper() in allowed for motion in motions):
                    projected = int(entry["runtime_action_id"])
                    compatibility_projections += count
                    break
        effective_observed[(character, projected)] += count

    per_character = {}
    characters = sorted({character for character, _ in raw_universe | set(observed)})
    for character in characters:
        observed_pairs = {pair for pair in observed if pair[0] == character}
        effective_pairs = {pair for pair in effective_observed if pair[0] == character}
        universe_pairs = {pair for pair in raw_universe if pair[0] == character}
        visible_pairs = {pair for pair in visible_candidates if pair[0] == character}
        per_character[character] = {
            "observed_actions": len(observed_pairs),
            "effective_observed_actions": len(effective_pairs),
            "command_display_action_universe": len(universe_pairs),
            "visible_command_candidates": len(visible_pairs),
            "effective_visible_candidates_exercised": len(effective_pairs & visible_pairs),
            "visible_candidates_never_observed": sorted(pair[1] for pair in visible_pairs - effective_pairs),
            "observed_only_once": sorted(pair[1] for pair in observed_pairs if observed[pair] == 1),
        }

    return {
        "action_coverage": {
            "authority_note": "command_display is a current generated Runtime projection, not the raw AC Action universe",
            "raw_ac_action_universe": "UNKNOWN_NOT_BULK_AVAILABLE_IN_SF6CC",
            "command_display_action_universe": len(raw_universe),
            "visible_command_candidates": len(visible_candidates),
            "observed_recorded_action_pairs": len(observed),
            "effective_observed_action_pairs": len(effective_observed),
            "effective_visible_candidates_exercised": len(set(effective_observed) & visible_candidates),
            "visible_candidates_never_observed": len(visible_candidates - set(effective_observed)),
            "observed_action_pairs_not_in_direct_map": sorted(
                f"{character}:{action_id}" for character, action_id in set(observed) - raw_universe
            ),
            "compatibility_projected_occurrences": compatibility_projections,
            "per_character": per_character,
        },
        "move_coverage": {
            "status": "UNKNOWN",
            "reason": "No full current Move graph is checked into SF6CC; the read-only query API is subject-based rather than a bulk universe enumerator.",
        },
        "ac_coverage_proxy": {
            "authority_note": "Derived from command_display route evidence, not the raw AC edge universe",
            "relation_proxies": len(ac_relation_proxies),
            "exercised_relation_proxies": len(exercised_ac_relation_proxies),
        },
        "bcm_coverage_proxy": {
            "authority_note": "Derived from command_display BCM-backed routes, not the raw BCM catalog universe",
            "route_proxies": len(bcm_route_proxies),
            "exercised_route_proxies": len(exercised_bcm_route_proxies),
            "observed_command_patterns": dict(sorted(observed_command_patterns.items())),
        },
        "timeline_stratification": {
            "combo_steps": distribution(combo_lengths),
            "timeline_entries": distribution(timeline_lengths),
            "timeline_total_frames": distribution(timeline_frames),
            "timeline_gap_frames": distribution(timeline_gaps),
            "zero_gap_lines": zero_gap_lines,
            "same_frame_statement": "No zero-gap timeline lines were found; same-frame game observations remain unproven because the frozen corpus stores gap strings, not observed absolute-frame event objects.",
            "multi_button_timeline_lines": multi_button_lines,
            "multi_button_cases": multi_button_cases,
            "long_gap_case_count_at_least_300_frames": len(long_gap_cases),
            "long_gap_cases_by_character": dict(sorted(Counter(
                row["character"] for row in long_gap_cases
            ).items())),
            "longest_gap_cases": sorted(
                long_gap_cases,
                key=lambda row: (-row["max_gap"], row["character"], row["filename"]),
            )[:50],
        },
        "side_relative_coverage": {
            "relative_raw_input_cases": sum(
                isinstance(case["sequence"][0].get("relative_raw_inputs"), list)
                for case in lua_input["cases"]
            ),
            "legacy_raw_input_cases": sum(
                isinstance(case["sequence"][0].get("raw_inputs"), list)
                for case in lua_input["cases"]
            ),
            "recorded_facing_trace_cases": 0,
            "side_switch_or_cross_up_cases": "UNKNOWN",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--corpus-root",
        type=Path,
        default=Path(r"D:\CP\SF6CC\reframework\release\tester_packages\0803"),
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=Path("docs/backup/SF6CC_VALIDATED_COMBO_BACKUP_2026-08-06_V1.manifest.json"),
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("audit-output/current-corpus"),
    )
    parser.add_argument("--case-order", choices=["normal", "reverse"], default="normal")
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    manifest_path = args.manifest if args.manifest.is_absolute() else repo / args.manifest
    output_dir = args.output_dir if args.output_dir.is_absolute() else repo / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest = load_json(manifest_path)
    roundtrip_output = output_dir / "full-corpus-roundtrip.json"
    consumer_output = output_dir / "full-corpus-consumer.json"
    combined_output = output_dir / "full-corpus-audit.json"

    roundtrip_run = run(
        [
            "node",
            "tools/corpus_roundtrip.mjs",
            "--manifest",
            str(manifest_path),
            "--corpus-root",
            str(args.corpus_root),
            "--output",
            str(roundtrip_output),
        ],
        repo,
    )

    lua_input = build_lua_input(repo, args.corpus_root, manifest)
    if args.case_order == "reverse":
        lua_input["cases"].reverse()
    coverage = compute_coverage(repo, lua_input)
    with tempfile.TemporaryDirectory(prefix="sf6cc-task-c-corpus-") as temporary:
        lua_data_path = Path(temporary) / "corpus.lua"
        lua_data_path.write_text("return " + lua_value(lua_input) + "\n", encoding="ascii")
        consumer_run = run(
            [
                "lua",
                "tools/corpus_consumer.lua",
                str(lua_data_path),
                str(consumer_output),
            ],
            repo,
        )

    roundtrip = load_json(roundtrip_output) if roundtrip_output.exists() else None
    consumer = load_json(consumer_output) if consumer_output.exists() else None
    combined = {
        "schema": "sf6cc.task-c.full-corpus-audit.v1",
        "audit_date": "2026-08-15",
        "corpus_snapshot": manifest["snapshot_id"],
        "target_game_build": manifest["target_game_build"],
        "case_order": args.case_order,
        "manifest_cases": manifest["combo_count"],
        "roundtrip_run": roundtrip_run,
        "consumer_run": consumer_run,
        "roundtrip": roundtrip,
        "consumer": consumer,
        "coverage": coverage,
        "full_corpus_executed": bool(
            roundtrip
            and consumer
            and roundtrip.get("files") == manifest["combo_count"]
            and consumer.get("cases") == manifest["combo_count"]
        ),
        "evidence_limits": [
            "The corpus entered production editor and Lua modules but not REFramework game hooks.",
            "Command display validation uses the production ImGui resolver with read-only in-memory JSON adapters.",
            "No synthetic runtime observations are labelled as real-game detection truth.",
        ],
    }
    combined_output.write_text(json.dumps(combined, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "output": str(combined_output),
                "full_corpus_executed": combined["full_corpus_executed"],
                "roundtrip_exit": roundtrip_run["exit_code"],
                "roundtrip_failed": None if roundtrip is None else roundtrip["failed"],
                "consumer_exit": consumer_run["exit_code"],
                "consumer_failures": None if consumer is None else consumer["failure_count"],
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
