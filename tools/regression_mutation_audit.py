#!/usr/bin/env python3
"""Run controlled in-memory mutation probes against focused Lua tests."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path


PROBES = [
    {
        "id": "MUT-C001",
        "domain": "Detection",
        "module": "func/ComboTrials/UnifiedActionConsumer",
        "field": "match_expected_action",
        "replacement": "function() return { matched = true, reason = 'regression_mutation' } end",
        "test": "tools/test_unified_action_consumer.lua",
        "defect": "Every observed Action is accepted, including wrong IDs.",
    },
    {
        "id": "MUT-C002",
        "domain": "Side-relative direction",
        "module": "func/ComboTrials/RawInputCodec",
        "field": "relative_to_native",
        "replacement": "function() return 0 end",
        "test": "tools/test_combo_raw_input_codec.lua",
        "defect": "Playback direction projection drops every input mask.",
    },
    {
        "id": "MUT-C003",
        "domain": "Timeline",
        "module": "func/ComboTrials/TimelineSequenceNormalizer",
        "field": "build_press_events",
        "replacement": "function() return {} end",
        "test": "tools/test_combo_timeline_normalizer.lua",
        "defect": "Timeline normalization drops every press event.",
    },
    {
        "id": "MUT-C004",
        "domain": "Detection combo count",
        "module": "func/ComboTrials/Validator",
        "field": "check_combo",
        "replacement": "function() return true end",
        "test": "tools/test_combo_validator.lua",
        "defect": "Every combo-count observation is accepted.",
    },
]


def lua_wrapper(probe: dict) -> str:
    return f'''package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local target = require("{probe['module']}")
target["{probe['field']}"] = {probe['replacement']}
local ok, err = pcall(dofile, "{probe['test']}")
if ok then
    io.stderr:write("TASK_C_MUTATION_SURVIVED\\n")
    os.exit(2)
end
io.write("TASK_C_MUTATION_KILLED\\t", tostring(err), "\\n")
'''


def run_probe(repo: Path, lua: str, probe: dict, temporary: Path) -> dict:
    wrapper = temporary / f"{probe['id'].lower()}.lua"
    wrapper.write_text(lua_wrapper(probe), encoding="utf-8")
    completed = subprocess.run(
        [lua, str(wrapper)],
        cwd=repo,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output = completed.stdout.strip()
    killed = completed.returncode == 0 and "TASK_C_MUTATION_KILLED" in output
    return {
        "id": probe["id"],
        "domain": probe["domain"],
        "production_module": probe["module"],
        "mutated_function": probe["field"],
        "focused_test": probe["test"],
        "deliberate_defect": probe["defect"],
        "process_isolation": "fresh Lua process; in-memory monkeypatch only",
        "exit_code": completed.returncode,
        "mutation_killed": killed,
        "output_tail": "\n".join(output.splitlines()[-8:]),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument("--lua", default="lua")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("audit-output/regression-mutation.json"),
    )
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    output = args.output if args.output.is_absolute() else repo / args.output
    with tempfile.TemporaryDirectory(prefix="sf6cc-task-c-mutation-") as name:
        temporary = Path(name)
        results = [run_probe(repo, args.lua, probe, temporary) for probe in PROBES]
    payload = {
        "schema": "sf6cc.task-c.mutation-audit.v1",
        "audit_date": "2026-08-15",
        "scope": "controlled regression sensitivity; not a mutation score",
        "production_files_modified": False,
        "probes": results,
        "summary": {
            "total": len(results),
            "killed": sum(row["mutation_killed"] for row in results),
            "survived": sum(not row["mutation_killed"] for row in results),
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload["summary"], indent=2))
    if payload["summary"]["survived"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
