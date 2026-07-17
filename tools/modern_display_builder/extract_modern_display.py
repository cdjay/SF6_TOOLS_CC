#!/usr/bin/env python3
"""Generate modern display mapping candidates from Capcom SF6 frame data."""

from __future__ import annotations

import argparse
import ast
import datetime as _dt
import html.parser
import json
import re
import sys
from pathlib import Path
from typing import Any
from urllib.error import URLError, HTTPError
from urllib.parse import urljoin
from urllib.request import Request, urlopen


DEFAULT_URL = "https://www.streetfighter.com/6/zh-hant/character/gouki_akuma/frame"
SCHEMA = "xt.modern_display.v1"


class NextScriptParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.script_srcs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "script":
            return
        attr = dict(attrs)
        src = attr.get("src")
        if src:
            self.script_srcs.append(src)


def fetch_text(url: str, referer: str | None = None) -> str:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-TW,zh;q=0.9,en;q=0.8",
    }
    if referer:
        headers["Referer"] = referer
    req = Request(url, headers=headers)
    with urlopen(req, timeout=40) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def character_to_slug(character: str) -> str:
    normalized = character.strip().lower().replace("-", "_").replace(" ", "_")
    aliases = {
        "aki": "aki",
        "akuma": "gouki_akuma",
        "alex": "alex",
        "blanka": "blanka",
        "cammy": "cammy",
        "chunli": "chunli",
        "chun_li": "chunli",
        "cviper": "cviper",
        "c_viper": "cviper",
        "dee_jay": "deejay",
        "deejay": "deejay",
        "dhalsim": "dhalsim",
        "ed": "ed",
        "ehonda": "ehonda",
        "e_honda": "ehonda",
        "elena": "elena",
        "gouki": "gouki_akuma",
        "gouki_akuma": "gouki_akuma",
        "guile": "guile",
        "ingrid": "ingrid",
        "jamie": "jamie",
        "jp": "jp",
        "juri": "juri",
        "ken": "ken",
        "kimberly": "kimberly",
        "lily": "lily",
        "luke": "luke",
        "mai": "mai",
        "manon": "manon",
        "marisa": "marisa",
        "mbison": "vega_mbison",
        "m_bison": "vega_mbison",
        "rashid": "rashid",
        "ryu": "ryu",
        "sagat": "sagat",
        "terry": "terry",
        "vega_mbison": "vega_mbison",
        "zangief": "zangief",
    }
    return aliases.get(normalized, normalized)


def character_display_name(character: str) -> str:
    slug = character_to_slug(character)
    display_names = {
        "aki": "AKI",
        "gouki_akuma": "Akuma",
        "chunli": "ChunLi",
        "cviper": "CViper",
        "deejay": "DeeJay",
        "ehonda": "EHonda",
        "vega_mbison": "MBison",
        "jp": "JP",
    }
    return display_names.get(slug, character.strip())


def read_local_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def find_local_chunk(html_path: Path, script_src: str) -> Path | None:
    basename = Path(script_src).name
    candidates = [
        html_path.parent / basename,
        html_path.parent / script_src.lstrip("/").replace("/", "_"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    for candidate in html_path.parent.rglob(basename):
        if candidate.is_file():
            return candidate
    return None


def discover_frame_chunk_src(html_text: str) -> str | None:
    parser = NextScriptParser()
    parser.feed(html_text)
    for src in parser.script_srcs:
        if "/chunks/pages/character/" in src and "/frame-" in src and src.endswith(".js"):
            return src
    return None


def load_source_text(url: str | None, html_path: Path | None) -> tuple[str, str]:
    if html_path:
        text = read_local_text(html_path)
        if "command_modern" in text and "JSON.parse" in text:
            return text, f"local:{html_path}"

        chunk_src = discover_frame_chunk_src(text)
        if not chunk_src:
            raise RuntimeError("Local HTML does not reference a frame chunk and is not a frame chunk itself.")

        local_chunk = find_local_chunk(html_path, chunk_src)
        if local_chunk:
            return read_local_text(local_chunk), f"local:{local_chunk}"

        if not url:
            raise RuntimeError(
                "Local HTML references a frame chunk, but the chunk was not found locally. "
                "Pass --url as a fallback or provide the JS chunk via --html."
            )
        chunk_url = urljoin(url, chunk_src)
        return fetch_text(chunk_url, referer=url), chunk_url

    if not url:
        raise RuntimeError("Either --url or --html is required.")
    html_text = fetch_text(url)
    chunk_src = discover_frame_chunk_src(html_text)
    if not chunk_src:
        raise RuntimeError("Official page did not expose a frame chunk script.")
    chunk_url = urljoin(url, chunk_src)
    return fetch_text(chunk_url, referer=url), chunk_url


def parse_json_modules(chunk_text: str) -> dict[str, Any]:
    modules: dict[str, Any] = {}
    pattern = re.compile(r"([A-Za-z_$][\w$]*)=JSON\.parse\('((?:\\.|[^\\'])*)'\)")
    for match in pattern.finditer(chunk_text):
        var_name = match.group(1)
        raw = match.group(2)
        decoded = ast.literal_eval("'" + raw + "'")
        try:
            modules[var_name] = json.loads(decoded)
        except json.JSONDecodeError:
            continue
    return modules


def parse_character_var_map(chunk_text: str) -> dict[str, str]:
    marker = "gouki_akuma"
    pos = chunk_text.find(marker)
    while pos != -1:
        left = chunk_text.rfind("({", 0, pos)
        right = chunk_text.find("})[t]", pos)
        if left != -1 and right != -1:
            body = chunk_text[left + 2 : right]
            pairs = dict(re.findall(r"([A-Za-z0-9_]+):([A-Za-z_$][\w$]*)", body))
            if marker in pairs:
                return pairs
        pos = chunk_text.find(marker, pos + 1)
    return {}


def normalize_command(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None

    replacements = {
        "＋": "+",
        "＞": ">",
        "／": "/",
        "　": " ",
        "\r": " ",
        "\n": " ",
        "（前ジャンプ中に）": "空中 ",
        "（垂直ジャンプ中に）": "空中 ",
        "（後ろジャンプ中に）": "空中 ",
        "（ジャンプ中に）": "空中 ",
        "(前ジャンプ中に)": "空中 ",
        "(垂直ジャンプ中に)": "空中 ",
        "(後ろジャンプ中に)": "空中 ",
        "(ジャンプ中に)": "空中 ",
        "(During a jump)": "空中 ",
        "(during a jump)": "空中 ",
        "(跳跃期间)": "空中 ",
    }
    for src, dst in replacements.items():
        text = text.replace(src, dst)

    text = re.sub(r"\s+", " ", text)
    text = re.sub(r"\s*([+>])\s*", r" \1 ", text)
    text = re.sub(r"\s*/\s*", "/", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def normalize_modern_command(value: Any) -> str | None:
    text = normalize_command(value)
    if not text:
        return None
    text = re.sub(r"\bL\b", "弱", text)
    text = re.sub(r"\bM\b", "中", text)
    text = re.sub(r"\bH\b", "强", text)
    return normalize_command(text)


def split_official_move_cell(value: Any) -> tuple[str | None, str | None]:
    lines = [line.strip() for line in str(value or "").splitlines() if line.strip()]
    if len(lines) < 2:
        return None, None
    return lines[0], " ".join(lines[1:])


def build_candidate_from_official_dump(character: str, source_path: Path, payload: Any) -> dict[str, Any]:
    """Build semantics from paired official Classic/Modern table captures.

    The captures contain no Action IDs. The compiler later binds each row to
    the unique current BCM classic-command identity; row numbers are never used
    as game Action IDs.
    """
    if not isinstance(payload, list):
        raise RuntimeError("Official dump root must be an array of captures.")
    captures = [item for item in payload if isinstance(item, dict)]
    language = "en" if any(item.get("language") == "en" for item in captures) else "zh"
    classic = next((item for item in captures
                    if item.get("language") == language and item.get("control_type") == "classic"), None)
    modern = next((item for item in captures
                   if item.get("language") == language and item.get("control_type") == "modern"), None)
    if not classic or not modern:
        raise RuntimeError(f"Official dump does not contain paired {language} Classic/Modern captures.")

    classic_rows: dict[str, dict[str, Any]] = {}
    for section in classic.get("sections") or []:
        if not isinstance(section, dict):
            continue
        for row in section.get("rows") or []:
            if not isinstance(row, list) or not row:
                continue
            move_name, command = split_official_move_cell(row[0])
            if move_name and command:
                classic_rows[move_name] = {"command": normalize_command(command)}

    semantic_rows: list[dict[str, Any]] = []
    for section_index, section in enumerate(modern.get("sections") or []):
        if not isinstance(section, dict):
            continue
        for row_index, row in enumerate(section.get("rows") or []):
            if not isinstance(row, list) or not row:
                continue
            move_name, modern_command = split_official_move_cell(row[0])
            pair = classic_rows.get(move_name or "")
            if not move_name or not modern_command or not pair or not pair.get("command"):
                continue
            classic_display = pair["command"]
            modern_display = normalize_modern_command(modern_command)
            if not modern_display:
                continue
            category = "AIR" if str(classic_display).startswith("空中 ") else "NORMAL"
            semantic_rows.append({
                "row_id": f"{language}:{section_index}:{row_index}",
                "classic_display": classic_display,
                "modern_display": modern_display,
                "control_support": "classic_modern",
                "source": "capcom_official_dump",
                "move_name": move_name,
                "category": category,
                "official_web_id": None,
                "note": "Generated from paired Capcom official Classic/Modern table captures without Action IDs.",
            })

    display_name = character_display_name(character)
    return {
        "_meta": {
            "schema": SCHEMA,
            "character": display_name,
            "generated_from": "capcom_official",
            "source_url": str(modern.get("source_url") or ""),
            "source_chunk": f"local:{source_path}",
            "source_format": "paired_official_table_dump",
            "updated_at": _dt.date.today().isoformat(),
            "description": f"Official {display_name} modern semantics generated from paired Capcom tables.",
        },
        "_semantic_rows": semantic_rows,
    }


def command_needs_review(command: str | None) -> bool:
    if not command:
        return False
    review_markers = ["攻撃", "|", "（", "）", "(", ")"]
    return any(marker in command for marker in review_markers)


def row_score(row: dict[str, Any]) -> tuple[int, int, int]:
    return (
        1 if row.get("command_modern") else 0,
        1 if row.get("skill") else 0,
        1 if row.get("webId") not in (None, "", -1, "-1", "　") else 0,
    )


def select_rows(frame_rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    selected: dict[str, dict[str, Any]] = {}
    for row in frame_rows:
        action_id = row.get("actionId")
        if action_id is None:
            continue
        action_id_text = str(action_id).strip()
        if not action_id_text or not action_id_text.isdigit():
            continue
        current = selected.get(action_id_text)
        if current is None or row_score(row) > row_score(current):
            selected[action_id_text] = row
    return selected


def build_candidate(character: str, source_url: str | None, source_chunk: str, frame_rows: list[dict[str, Any]]) -> dict[str, Any]:
    display_name = character_display_name(character)
    selected = select_rows(frame_rows)
    output: dict[str, Any] = {
        "_meta": {
            "schema": SCHEMA,
            "character": display_name,
            "generated_from": "capcom_official",
            "source_url": source_url or "",
            "source_chunk": source_chunk,
            "updated_at": _dt.date.today().isoformat(),
            "description": f"Official {display_name} modern display candidate generated from Capcom frame data.",
        }
    }

    for action_id in sorted(selected, key=lambda value: int(value)):
        row = selected[action_id]
        classic_display = normalize_command(row.get("command"))
        modern_display = normalize_command(row.get("command_modern"))
        note_parts = []
        if modern_display:
            note_parts.append("Generated from Capcom official frame data.")
            if command_needs_review(modern_display):
                note_parts.append("Needs review: command contains generalized or contextual notation.")
            control_support = "classic_modern"
        else:
            note_parts.append("No modern command found in official data.")
            control_support = "classic_only"

        output[action_id] = {
            "classic_display": classic_display,
            "modern_display": modern_display,
            "control_support": control_support,
            "source": "capcom_official",
            "move_name": row.get("skill"),
            "category": row.get("type"),
            "official_web_id": row.get("webId"),
            "note": " ".join(note_parts),
        }
    return output


def load_current_mapping(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def action_keys(mapping: dict[str, Any]) -> set[str]:
    return {key for key in mapping.keys() if key != "_meta" and key.isdigit()}


def markdown_list(values: list[str]) -> str:
    if not values:
        return "- None\n"
    return "".join(f"- `{value}`\n" for value in values)


def format_markdown_cell(value: Any) -> str:
    if value is None:
        return "null"
    return str(value).replace("|", "\\|")


def write_diff_report(candidate: dict[str, Any], current: dict[str, Any], output_path: Path) -> dict[str, Any]:
    candidate_ids = action_keys(candidate)
    current_ids = action_keys(current)

    official_new = sorted(candidate_ids - current_ids, key=int)
    current_missing = sorted(current_ids - candidate_ids, key=int)
    classic_only = sorted(
        [key for key in candidate_ids if candidate[key].get("modern_display") is None],
        key=int,
    )
    mismatches = []
    needs_review = []
    for key in sorted(candidate_ids & current_ids, key=int):
        candidate_display = candidate[key].get("modern_display")
        current_display = current[key].get("modern_display")
        if candidate_display != current_display:
            mismatches.append((key, current_display, candidate_display))
        note = str(candidate[key].get("note") or "")
        if "Needs review" in note:
            needs_review.append(key)

    sample_not_covered = sorted(
        [key for key in current_ids if key not in candidate_ids or candidate.get(key, {}).get("modern_display") is None],
        key=int,
    )
    manual_review = sorted(set(needs_review + classic_only), key=int)

    lines = [
        "# Akuma Official Modern Display Diff\n",
        "\n",
        "This report compares the Capcom official generated candidate with the current runtime mapping.\n",
        "\n",
        "## Summary\n",
        "\n",
        f"- Official candidate action_id count: {len(candidate_ids)}\n",
        f"- Current Akuma.json action_id count: {len(current_ids)}\n",
        f"- Official-only action_id count: {len(official_new)}\n",
        f"- Current-only action_id count: {len(current_missing)}\n",
        f"- modern_display mismatch count: {len(mismatches)}\n",
        f"- classic_only action_id count: {len(classic_only)}\n",
        f"- needs-review action_id count: {len(manual_review)}\n",
        "\n",
        "## Official Candidate Adds\n",
        "\n",
        markdown_list(official_new),
        "\n",
        "## Current Mapping Not Found In Official Candidate\n",
        "\n",
        markdown_list(current_missing),
        "\n",
        "## Modern Display Mismatches\n",
        "\n",
    ]
    if mismatches:
        lines.extend(["| action_id | current | official candidate |\n", "| --- | --- | --- |\n"])
        for key, current_display, candidate_display in mismatches:
            lines.append(
                f"| `{key}` | `{format_markdown_cell(current_display)}` | "
                f"`{format_markdown_cell(candidate_display)}` |\n"
            )
    else:
        lines.append("- None\n")

    lines.extend([
        "\n",
        "## Classic Only In Official Candidate\n",
        "\n",
        markdown_list(classic_only),
        "\n",
        "## Needs Manual Review\n",
        "\n",
        markdown_list(manual_review),
        "\n",
        "## Current Sample Supplements Not Covered By Official Modern Command\n",
        "\n",
        markdown_list(sample_not_covered),
        "\n",
        "Notes:\n",
        "\n",
        "- This report does not modify `data/TrainingComboTrials_data/modern_display/Akuma.json`.\n",
        "- `攻撃` is preserved in official candidates and marked for review instead of being forced to `強`.\n",
        "- Current-only IDs may be contextual, sample-derived, or absent from the public official table.\n",
    ])
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("".join(lines), encoding="utf-8")

    return {
        "candidate_count": len(candidate_ids),
        "current_count": len(current_ids),
        "official_new": official_new,
        "current_missing": current_missing,
        "mismatches": mismatches,
        "classic_only": classic_only,
        "needs_review": manual_review,
        "sample_not_covered": sample_not_covered,
    }


def run(args: argparse.Namespace) -> int:
    if args.official_dump:
        dump_path = Path(args.official_dump)
        payload = json.loads(dump_path.read_text(encoding="utf-8"))
        candidate = build_candidate_from_official_dump(args.character, dump_path, payload)
        output_path = Path(args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"generated={output_path}")
        print(f"source_chunk=local:{dump_path}")
        print(f"semantic_row_count={len(candidate.get('_semantic_rows') or [])}")
        return 0

    source_url = args.url
    html_path = Path(args.html) if args.html else None
    chunk_text, source_chunk = load_source_text(source_url, html_path)
    modules = parse_json_modules(chunk_text)
    char_map = parse_character_var_map(chunk_text)
    slug = character_to_slug(args.character)
    var_name = char_map.get(slug)
    if not var_name:
        raise RuntimeError(f"Could not resolve character variable for {args.character} ({slug}).")
    data = modules.get(var_name)
    if not isinstance(data, dict) or not isinstance(data.get("frame"), list):
        raise RuntimeError(f"Frame data for {args.character} was not found in parsed modules.")

    candidate = build_candidate(args.character, source_url, source_chunk, data["frame"])
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(candidate, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    ids = action_keys(candidate)
    print(f"generated={output_path}")
    print(f"source_chunk={source_chunk}")
    print(f"action_id_count={len(ids)}")

    if args.current and args.diff_output:
        current = load_current_mapping(Path(args.current))
        summary = write_diff_report(candidate, current, Path(args.diff_output))
        print(f"diff_report={args.diff_output}")
        print(f"current_count={summary['current_count']}")
        print(f"mismatch_count={len(summary['mismatches'])}")
        print(f"classic_only_count={len(summary['classic_only'])}")
        print(f"needs_review_count={len(summary['needs_review'])}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Extract modern display candidates from Capcom SF6 frame data.")
    parser.add_argument("--character", required=True, help="Character display name, e.g. Akuma")
    parser.add_argument("--url", help="Official Capcom frame URL")
    parser.add_argument("--html", help="Local saved HTML page or frame JS chunk")
    parser.add_argument("--official-dump", help="Local paired official Classic/Modern table dump JSON")
    parser.add_argument("--output", required=True, help="Output candidate JSON path")
    parser.add_argument("--current", help="Current runtime modern_display JSON for diff reporting")
    parser.add_argument("--diff-output", help="Markdown diff report path")
    args = parser.parse_args(argv)

    try:
        return run(args)
    except (RuntimeError, OSError, HTTPError, URLError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        print("hint: pass --html with a saved frame page or frame JS chunk to run offline.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
