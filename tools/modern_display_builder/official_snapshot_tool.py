#!/usr/bin/env python3
"""Fetch, version, and diff Capcom's official SF6 frame data.

This tool deliberately does not merge or write SF6CC runtime tables.  It only
creates reproducible official-data snapshots under action_runtime_compiler/off.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any

import extract_modern_display as extractor


TOOL_ROOT = Path(__file__).resolve().parents[1] / "action_runtime_compiler"
DEFAULT_MANIFEST = Path(__file__).resolve().with_name("characters.json")
DEFAULT_ACBCM_ROOT = TOOL_ROOT / "acbcm"
DEFAULT_OFF_ROOT = TOOL_ROOT / "off"
SNAPSHOT_SCHEMA = "xt.modern_display.v1"
MANIFEST_SCHEMA = "sf6cc.capcom-official-snapshot-manifest.v1"
DIFF_SCHEMA = "sf6cc.capcom-official-snapshot-diff.v1"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256_json(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def normalize_version(value: str) -> str:
    match = re.fullmatch(r"(\d{4})[.-](\d{1,2})[.-](\d{1,2})", str(value or "").strip())
    if not match:
        raise RuntimeError("版本必须是 YYYY-MM-DD 或 YYYY.M.D 日期格式。")
    year, month, day = (int(part) for part in match.groups())
    return dt.date(year, month, day).isoformat()


def version_date(name: str) -> dt.date | None:
    try:
        return dt.date.fromisoformat(normalize_version(name))
    except (RuntimeError, ValueError):
        return None


def default_version(acbcm_root: Path) -> str:
    versions = []
    if acbcm_root.is_dir():
        for child in acbcm_root.iterdir():
            parsed = version_date(child.name) if child.is_dir() else None
            if parsed:
                versions.append((parsed, child.name))
    if versions:
        return max(versions)[0].isoformat()
    return dt.date.today().isoformat()


def semantic_rows(frame_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    occurrences: dict[str, int] = {}
    for row in frame_rows:
        classic = extractor.normalize_command(row.get("command"))
        modern = extractor.normalize_modern_command(row.get("command_modern"))
        if not classic or not modern:
            continue
        stable = str(row.get("webId") or row.get("actionId") or row.get("skill") or "row")
        occurrences[stable] = occurrences.get(stable, 0) + 1
        row_id = f"{stable}:{occurrences[stable]}"
        rows.append({
            "row_id": row_id,
            "classic_display": classic,
            "modern_display": modern,
            "control_support": "classic_modern",
            "source": "capcom_official_live",
            "move_name": row.get("skill"),
            "category": row.get("type"),
            "official_web_id": row.get("webId"),
            "note": "Fetched from the current Capcom frame-data module; Action IDs are hints only.",
        })
    return rows


def build_snapshot(character: str, entry: dict[str, Any], frame_rows: list[dict[str, Any]],
                   source_chunk: str, source_chunk_sha256: str, version: str) -> dict[str, Any]:
    # Keep Capcom action IDs as hints, exactly like the reviewed extractor.
    # The Modern compiler still requires the current BCM Classic identity and
    # never assigns a route from the hint alone.  Dropping the hint entirely is
    # also unsafe when several current actions share one Classic identity.
    snapshot = extractor.build_candidate(character, entry["url"], source_chunk, frame_rows)
    snapshot["_meta"].update({
        "schema": SNAPSHOT_SCHEMA,
        "character": character,
        "fighter_id": int(entry["fighter_id"]),
        "generated_from": "capcom_official",
        "source_chunk_sha256": source_chunk_sha256,
        "source_format": "capcom_frame_module_snapshot",
        "updated_at": version,
        "description": f"Versioned Capcom official frame snapshot for {character}.",
    })
    snapshot["_official_semantic_rows"] = semantic_rows(frame_rows)
    snapshot["_official_frame"] = frame_rows
    return snapshot


def indexed_frame(snapshot: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    result: dict[str, list[dict[str, Any]]] = {}
    for row in snapshot.get("_official_frame") or []:
        action_id = str(row.get("actionId") if row.get("actionId") is not None else "no-action-id")
        result.setdefault(action_id, []).append(row)
    return result


def changed_fields(before: Any, after: Any, prefix: str = "") -> list[dict[str, Any]]:
    if type(before) is not type(after):
        return [{"path": prefix or "$", "before": before, "after": after}]
    if isinstance(before, dict):
        changes: list[dict[str, Any]] = []
        for key in sorted(set(before) | set(after)):
            child = f"{prefix}.{key}" if prefix else str(key)
            if key not in before:
                changes.append({"path": child, "before": None, "after": after[key]})
            elif key not in after:
                changes.append({"path": child, "before": before[key], "after": None})
            else:
                changes.extend(changed_fields(before[key], after[key], child))
        return changes
    if isinstance(before, list):
        if before == after:
            return []
        if len(before) != len(after):
            return [{"path": prefix or "$", "before": before, "after": after}]
        changes: list[dict[str, Any]] = []
        for index, (left, right) in enumerate(zip(before, after)):
            changes.extend(changed_fields(left, right, f"{prefix}[{index}]"))
        return changes
    return [] if before == after else [{"path": prefix or "$", "before": before, "after": after}]


def diff_snapshot(before: dict[str, Any] | None, after: dict[str, Any]) -> dict[str, Any]:
    if before is None:
        ids = sorted(indexed_frame(after), key=lambda value: (not value.isdigit(), int(value) if value.isdigit() else value))
        return {"baseline": True, "source_resource_changed": False,
                "added_action_ids": ids, "removed_action_ids": [],
                "changed_actions": [],
                "semantic_rows_changed": len(after.get("_official_semantic_rows") or [])}
    before_index, after_index = indexed_frame(before), indexed_frame(after)
    before_ids, after_ids = set(before_index), set(after_index)
    common = sorted(before_ids & after_ids,
                    key=lambda value: (not value.isdigit(), int(value) if value.isdigit() else value))
    changed = []
    for action_id in common:
        fields = changed_fields(before_index[action_id], after_index[action_id])
        if fields:
            changed.append({"action_id": action_id, "fields": fields})
    before_semantics = before.get("_official_semantic_rows") or []
    after_semantics = after.get("_official_semantic_rows") or []
    return {
        "baseline": False,
        "source_resource_changed": (before.get("_meta") or {}).get("source_chunk_sha256")
            != (after.get("_meta") or {}).get("source_chunk_sha256"),
        "added_action_ids": sorted(after_ids - before_ids),
        "removed_action_ids": sorted(before_ids - after_ids),
        "changed_actions": changed,
        "semantic_rows_changed": 0 if before_semantics == after_semantics else 1,
    }


def find_previous(off_root: Path, current_version: str, current_existing: Path) -> tuple[str | None, Path | None]:
    if current_existing.is_dir() and (current_existing / "manifest.json").exists():
        return current_version, current_existing
    target_date = dt.date.fromisoformat(current_version)
    candidates = []
    if off_root.is_dir():
        for child in off_root.iterdir():
            parsed = version_date(child.name) if child.is_dir() else None
            if parsed and parsed < target_date and (child / "manifest.json").exists():
                candidates.append((parsed, child))
    if not candidates:
        return None, None
    parsed, directory = max(candidates, key=lambda item: item[0])
    return parsed.isoformat(), directory


def load_previous_snapshots(directory: Path | None, characters: list[str]) -> dict[str, dict[str, Any]]:
    if directory is None:
        return {}
    result = {}
    for character in characters:
        filename = directory / f"{character}.official.generated.json"
        if filename.exists():
            result[character] = read_json(filename)
    return result


def markdown_report(bundle: dict[str, Any]) -> str:
    lines = [
        "# Capcom 官网数据版本差异\n\n",
        f"- 当前版本：`{bundle['version']}`\n",
        f"- 对比版本：`{bundle['compare_version'] or '无（首次基线）'}`\n",
        f"- 有变化角色：{bundle['summary']['changed_characters']}\n",
        f"- 无变化角色：{bundle['summary']['unchanged_characters']}\n",
        f"- 新增 Action ID：{bundle['summary']['added_action_ids']}\n",
        f"- 删除 Action ID：{bundle['summary']['removed_action_ids']}\n",
        f"- 内容变化 Action ID：{bundle['summary']['changed_action_ids']}\n\n",
        f"- 官网数据资源文件变化：{'是' if bundle['summary']['source_resource_changed'] else '否'}\n\n",
        "| 角色 | Fighter ID | 状态 | 新增ID | 删除ID | 变化ID | 官网语义变化 | 资源变化 |\n",
        "| --- | ---: | --- | ---: | ---: | ---: | --- | --- |\n",
    ]
    for item in bundle["characters"]:
        lines.append(
            f"| {item['character']} | {item['fighter_id']} | {item['status']} | "
            f"{len(item['added_action_ids'])} | {len(item['removed_action_ids'])} | "
            f"{len(item['changed_actions'])} | {'是' if item['semantic_rows_changed'] else '否'} | "
            f"{'是' if item['source_resource_changed'] else '否'} |\n"
        )
    for item in bundle["characters"]:
        if item["status"] == "unchanged":
            continue
        lines.extend([f"\n## {item['character']}（Fighter {item['fighter_id']}）\n\n"])
        if item["added_action_ids"]:
            lines.append("- 新增 Action ID：" + ", ".join(map(str, item["added_action_ids"])) + "\n")
        if item["removed_action_ids"]:
            lines.append("- 删除 Action ID：" + ", ".join(map(str, item["removed_action_ids"])) + "\n")
        for action in item["changed_actions"]:
            paths = ", ".join(field["path"] for field in action["fields"][:12])
            suffix = " …" if len(action["fields"]) > 12 else ""
            lines.append(f"- Action `{action['action_id']}`：{paths}{suffix}\n")
        if item["semantic_rows_changed"]:
            lines.append("- Classic/Modern 官网指令语义有变化。\n")
    return "".join(lines)


def fetch_all(manifest: dict[str, dict[str, Any]], version: str) -> tuple[dict[str, dict[str, Any]], str]:
    first = min(manifest.items(), key=lambda item: int(item[1]["fighter_id"]))[1]
    chunk_text, source_chunk = extractor.load_source_text(first["url"], None)
    modules = extractor.parse_json_modules(chunk_text)
    var_map = extractor.parse_character_var_map(chunk_text)
    chunk_sha = hashlib.sha256(chunk_text.encode("utf-8")).hexdigest()
    snapshots = {}
    for character, entry in sorted(manifest.items(), key=lambda item: int(item[1]["fighter_id"])):
        var_name = var_map.get(entry["official_name"])
        payload = modules.get(var_name) if var_name else None
        frame_rows = payload.get("frame") if isinstance(payload, dict) else None
        if not isinstance(frame_rows, list) or not frame_rows:
            raise RuntimeError(f"官网 frame 数据缺失: {character} ({entry['official_name']})")
        snapshots[character] = build_snapshot(
            character, entry, frame_rows, source_chunk, chunk_sha, version)
    return snapshots, source_chunk


def run(args: argparse.Namespace) -> int:
    manifest_path = Path(args.manifest).resolve()
    acbcm_root = Path(args.acbcm_root).resolve()
    off_root = Path(args.off_root).resolve()
    version = normalize_version(args.version) if args.version else default_version(acbcm_root)
    manifest = read_json(manifest_path)
    if not manifest:
        raise RuntimeError("角色清单不能为空。")
    ids = [int(entry["fighter_id"]) for entry in manifest.values()]
    if len(set(ids)) != len(manifest):
        raise RuntimeError("角色清单 fighter_id 存在重复。")

    target = off_root / version
    previous_version, previous_dir = find_previous(off_root, version, target)
    previous = load_previous_snapshots(previous_dir, list(manifest))
    snapshots, source_chunk = fetch_all(manifest, version)

    characters = []
    for character, entry in sorted(manifest.items(), key=lambda item: int(item[1]["fighter_id"])):
        difference = diff_snapshot(previous.get(character), snapshots[character])
        changed = difference["baseline"] or bool(difference["source_resource_changed"]
            or difference["added_action_ids"]
            or difference["removed_action_ids"] or difference["changed_actions"]
            or difference["semantic_rows_changed"])
        characters.append({
            "character": character,
            "fighter_id": int(entry["fighter_id"]),
            "status": "baseline" if difference["baseline"] else ("changed" if changed else "unchanged"),
            "snapshot_file": f"{character}.official.generated.json",
            "snapshot_sha256": sha256_json(snapshots[character]),
            **difference,
        })

    summary = {
        "changed_characters": sum(item["status"] != "unchanged" for item in characters),
        "unchanged_characters": sum(item["status"] == "unchanged" for item in characters),
        "added_action_ids": sum(len(item["added_action_ids"]) for item in characters),
        "removed_action_ids": sum(len(item["removed_action_ids"]) for item in characters),
        "changed_action_ids": sum(len(item["changed_actions"]) for item in characters),
        "source_resource_changed": any(item["source_resource_changed"] for item in characters),
    }
    bundle = {
        "schema": DIFF_SCHEMA,
        "version": version,
        "fetched_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "compare_version": previous_version,
        "comparison_mode": "same-version-before-refresh" if previous_version == version
            else ("previous-version" if previous_version else "baseline"),
        "summary": summary,
        "characters": characters,
    }
    snapshot_manifest = {
        "schema": MANIFEST_SCHEMA,
        "version": version,
        "fetched_at": bundle["fetched_at"],
        "character_count": len(characters),
        "source_chunk": source_chunk,
        "characters": [{key: value for key, value in item.items()
                        if key in {"character", "fighter_id", "snapshot_file", "snapshot_sha256"}}
                       for item in characters],
    }

    off_root.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=f".{version}-", dir=off_root))
    try:
        for character, snapshot in snapshots.items():
            write_json(stage / f"{character}.official.generated.json", snapshot)
        write_json(stage / "manifest.json", snapshot_manifest)
        write_json(stage / "differences.json", bundle)
        (stage / "differences.md").write_text(markdown_report(bundle), encoding="utf-8")
        target.mkdir(parents=True, exist_ok=True)
        for source in stage.iterdir():
            destination = target / source.name
            temporary = target / f".{source.name}.tmp"
            shutil.copy2(source, temporary)
            temporary.replace(destination)
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    print(f"官网数据版本: {version}")
    print(f"保存目录: {target}")
    print(f"对比版本: {previous_version or '无（首次基线）'}")
    print(f"变化角色: {summary['changed_characters']}，无变化角色: {summary['unchanged_characters']}")
    print(f"新增/删除/变化 Action ID: {summary['added_action_ids']}/"
          f"{summary['removed_action_ids']}/{summary['changed_action_ids']}")
    print(f"详细报告: {target / 'differences.md'}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="抓取并对比角色清单中的 Capcom 官网数据。")
    parser.add_argument("--version", help="版本日期；默认取 acbcm 中最新日期，否则取今天")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--acbcm-root", default=str(DEFAULT_ACBCM_ROOT))
    parser.add_argument("--off-root", default=str(DEFAULT_OFF_ROOT))
    args = parser.parse_args(argv)
    try:
        return run(args)
    except Exception as exc:  # keep BAT output readable for network/parser failures
        print(f"错误: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
