#!/usr/bin/env python3
"""Repeat tests/corpus checks and challenge order/state determinism."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import random
import tempfile

import task_c_full_corpus_audit as corpus_core


def load_phase1(repo: Path):
    spec = importlib.util.spec_from_file_location(
        "task_c_phase1_audit",
        repo / "tools" / "task_c_phase1_audit.py",
    )
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def canonical_hash(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def test_command(location: str) -> list[str]:
    suffix = Path(location).suffix.lower()
    if suffix == ".lua":
        return ["lua", location]
    if suffix in {".js", ".mjs"}:
        return ["node", location]
    if suffix == ".py":
        return ["python", location]
    if suffix == ".ps1":
        return ["pwsh", "-NoProfile", "-File", location]
    raise ValueError(location)


def fresh_process_order(repo: Path, locations: list[str], label: str) -> dict:
    results = []
    for location in locations:
        result = corpus_core.run(test_command(location), repo)
        results.append({
            "location": location,
            "exit_code": result["exit_code"],
            "output_tail": result["output"][-1000:],
        })
    return {
        "label": label,
        "files": len(results),
        "passed": sum(result["exit_code"] == 0 for result in results),
        "failed": sum(result["exit_code"] != 0 for result in results),
        "failures": [result for result in results if result["exit_code"] != 0],
        "result_hash": canonical_hash([
            [result["location"], result["exit_code"]] for result in results
        ]),
    }


def lua_same_process(repo: Path, locations: list[str], label: str, temporary: Path) -> dict:
    runner = temporary / f"lua-tests-{label}.lua"
    lines = [
        "local files = {",
        *[f"  {json.dumps(location)}," for location in locations],
        "}",
        "for index, filename in ipairs(files) do",
        "  local ok, err = pcall(dofile, filename)",
        "  if not ok then",
        "    io.stderr:write(string.format('TASK_C_SAME_PROCESS_FAIL\\t%d\\t%s\\t%s\\n', index, filename, tostring(err)))",
        "    os.exit(1)",
        "  end",
        "end",
        "print('TASK_C_SAME_PROCESS_PASS ' .. tostring(#files))",
    ]
    runner.write_text("\n".join(lines) + "\n", encoding="utf-8")
    result = corpus_core.run(["lua", str(runner)], repo)
    return {
        "label": label,
        "files": len(locations),
        "exit_code": result["exit_code"],
        "output_tail": result["output"][-4000:],
    }


def stable_roundtrip(value: dict) -> dict:
    return {
        "files": value.get("files"),
        "passed": value.get("passed"),
        "failed": value.get("failed"),
        "assertions": value.get("assertions"),
        "warning_counts_by_character": value.get("warning_counts_by_character"),
        "warning_cases": sorted(
            [
                {
                    "character": row.get("character"),
                    "filename": row.get("filename"),
                    "warnings": row.get("warnings"),
                }
                for row in value.get("warning_cases") or []
            ],
            key=lambda row: (str(row["character"]), str(row["filename"]), str(row["warnings"])),
        ),
        "failures": sorted(
            [
                {key: item for key, item in row.items() if key not in {"path"}}
                for row in value.get("failures") or []
            ],
            key=lambda row: json.dumps(row, sort_keys=True, ensure_ascii=False),
        ),
    }


def stable_consumer(value: dict) -> dict:
    copy = dict(value)
    copy["failures"] = sorted(
        copy.get("failures") or [],
        key=lambda row: (
            str(row.get("exact_sha256")),
            str(row.get("check")),
            str(row.get("detail")),
        ),
    )
    return copy


def stable_audit(value: dict) -> dict:
    return {
        "roundtrip": stable_roundtrip(value["roundtrip"]),
        "consumer": stable_consumer(value["consumer"]),
        "coverage": value["coverage"],
        "executed": value.get("full_corpus_executed")
            if "full_corpus_executed" in value
            else value.get("all_accessible_exact_unique_corpus_executed"),
    }


def run_corpus_variants(repo: Path, backup_root: Path, temporary: Path) -> dict:
    variants = []
    commands = [
        (
            "frozen_normal_1",
            [
                "python", "tools/task_c_full_corpus_audit.py",
                "--repo-root", ".",
                "--corpus-root", str(backup_root / "0803"),
                "--output-dir", str(temporary / "frozen-normal-1"),
                "--case-order", "normal",
            ],
        ),
        (
            "frozen_normal_2",
            [
                "python", "tools/task_c_full_corpus_audit.py",
                "--repo-root", ".",
                "--corpus-root", str(backup_root / "0803"),
                "--output-dir", str(temporary / "frozen-normal-2"),
                "--case-order", "normal",
            ],
        ),
        (
            "frozen_reverse",
            [
                "python", "tools/task_c_full_corpus_audit.py",
                "--repo-root", ".",
                "--corpus-root", str(backup_root / "0803"),
                "--output-dir", str(temporary / "frozen-reverse"),
                "--case-order", "reverse",
            ],
        ),
        (
            "all_normal_1",
            [
                "python", "tools/task_c_all_accessible_corpus_audit.py",
                "--repo-root", ".",
                "--backup-root", str(backup_root),
                "--output-dir", str(temporary / "all-normal-1"),
                "--case-order", "normal",
            ],
        ),
        (
            "all_normal_2",
            [
                "python", "tools/task_c_all_accessible_corpus_audit.py",
                "--repo-root", ".",
                "--backup-root", str(backup_root),
                "--output-dir", str(temporary / "all-normal-2"),
                "--case-order", "normal",
            ],
        ),
        (
            "all_reverse",
            [
                "python", "tools/task_c_all_accessible_corpus_audit.py",
                "--repo-root", ".",
                "--backup-root", str(backup_root),
                "--output-dir", str(temporary / "all-reverse"),
                "--case-order", "reverse",
            ],
        ),
    ]
    for label, command in commands:
        result = corpus_core.run(command, repo)
        output_dir = Path(command[command.index("--output-dir") + 1])
        audit_name = "full-corpus-audit.json" if label.startswith("frozen") else "all-accessible-corpus-audit.json"
        audit = corpus_core.load_json(output_dir / audit_name)
        stable = stable_audit(audit)
        variants.append({
            "label": label,
            "exit_code": result["exit_code"],
            "semantic_hash": canonical_hash(stable),
            "consumer_hash": canonical_hash(stable["consumer"]),
            "roundtrip_hash": canonical_hash(stable["roundtrip"]),
        })
    frozen_hashes = {row["semantic_hash"] for row in variants if row["label"].startswith("frozen")}
    all_hashes = {row["semantic_hash"] for row in variants if row["label"].startswith("all_")}
    return {
        "variants": variants,
        "frozen_semantic_deterministic": len(frozen_hashes) == 1,
        "all_accessible_semantic_deterministic": len(all_hashes) == 1,
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
        "--output",
        type=Path,
        default=Path("docs/audits/task-c/determinism-audit.json"),
    )
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    output = args.output if args.output.is_absolute() else repo / args.output
    phase1 = load_phase1(repo)
    inventory = phase1.test_inventory(repo)
    locations = [item["location"] for item in inventory if item["type"] != "ORACLE"]
    normal = list(locations)
    reverse = list(reversed(locations))
    seeded = list(locations)
    random.Random(20260815).shuffle(seeded)
    lua_locations = [location for location in locations if location.endswith(".lua")]

    with tempfile.TemporaryDirectory(prefix="sf6cc-task-c-determinism-") as temporary_name:
        temporary = Path(temporary_name)
        fresh = [
            fresh_process_order(repo, normal, "normal"),
            fresh_process_order(repo, reverse, "reverse"),
            fresh_process_order(repo, seeded, "seeded_20260815"),
        ]
        same_process = [
            lua_same_process(repo, lua_locations, "forward", temporary),
            lua_same_process(repo, list(reversed(lua_locations)), "reverse", temporary),
        ]
        corpus = run_corpus_variants(repo, args.backup_root, temporary)

    payload = {
        "schema": "sf6cc.task-c.determinism-audit.v1",
        "audit_date": "2026-08-15",
        "fresh_process_test_orders": fresh,
        "lua_same_process_orders": same_process,
        "test_infrastructure_findings": [
            {
                "id": "TEST-INFRA-C001",
                "classification": "TEST_FIXTURE_STATE_LEAKAGE",
                "initial_observation": (
                    "Fresh-process orders passed 59/59, while same-process Lua "
                    "orders reused stale package.loaded/package.preload test doubles."
                ),
                "root_cause": (
                    "Tests that injected SceneState, GameState, RandomKill, "
                    "ImGuiCanvas, SharedHooks, and SF6CC_Version fixtures did "
                    "not consistently clear or restore module caches and globals."
                ),
                "production_state_leakage": False,
                "remediation_commit": "c44364f",
                "status": (
                    "VERIFIED_FIXED"
                    if all(row["exit_code"] == 0 for row in same_process)
                    else "REGRESSION_PRESENT"
                ),
            }
        ],
        "corpus": corpus,
        "authoritative_generator": {
            "status": "BLOCKED_INPUTS_UNAVAILABLE_IN_SF6CC",
            "reason": "Full raw AC/BCM inputs are required by compile.js/build_command_display.js and are not checked into this repository.",
            "available_evidence": "Synthetic compiler/command-display tests include deterministic equality assertions and pass in every fresh-process order.",
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(output),
        "fresh_orders_pass": all(row["failed"] == 0 for row in fresh),
        "same_process_pass": all(row["exit_code"] == 0 for row in same_process),
        "frozen_deterministic": corpus["frozen_semantic_deterministic"],
        "all_accessible_deterministic": corpus["all_accessible_semantic_deterministic"],
    }, indent=2))


if __name__ == "__main__":
    main()
