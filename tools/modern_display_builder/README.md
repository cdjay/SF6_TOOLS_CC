# Modern Display Builder

This directory contains offline-friendly tooling for generating modern control display mapping candidates from Capcom official frame data.

The generated files are candidates for review. They must not automatically overwrite the runtime mapping under:

```text
data/TrainingComboTrials_data/modern_display/<Character>.json
```

## Scope

`extract_modern_display.py` supports single-character candidate generation.

`batch_build_modern_display.py` reads `characters.json`, generates official candidates, merges them into runtime mapping JSON files, and writes markdown reports. It does not modify Lua, validators, timeline data, recorder logic, website code, or raw official dumps.

## Usage

Fetch from the official URL and write a candidate JSON:

```powershell
python tools/modern_display_builder/extract_modern_display.py `
  --character Akuma `
  --url https://www.streetfighter.com/6/zh-hant/character/gouki_akuma/frame `
  --output tools/modern_display_builder/out/Akuma.official.generated.json
```

Generate a diff report against the current runtime mapping:

```powershell
python tools/modern_display_builder/extract_modern_display.py `
  --character Akuma `
  --url https://www.streetfighter.com/6/zh-hant/character/gouki_akuma/frame `
  --output tools/modern_display_builder/out/Akuma.official.generated.json `
  --current data/TrainingComboTrials_data/modern_display/Akuma.json `
  --diff-output docs/modern_display_akuma_official_diff.md
```

Use a local input when the network is unavailable:

```powershell
python tools/modern_display_builder/extract_modern_display.py `
  --character Akuma `
  --html path/to/gouki_akuma_frame.html `
  --output tools/modern_display_builder/out/Akuma.official.generated.json
```

`--html` accepts either:

- a saved Capcom frame HTML page, if its referenced Next.js frame chunk can also be found locally or fetched through `--url`
- the frame page JavaScript chunk itself

Use a paired official Classic/Modern table dump (for example the `INGRID.json`
files stored beside a dated AC+BCM dump):

```powershell
python tools/modern_display_builder/extract_modern_display.py `
  --character Ingrid `
  --official-dump "D:\CP\SF6CR-evidence\AC+BCM+OFF\2026.5.28\INGRID.json" `
  --output tools/modern_display_builder/out/Ingrid.official.generated.json
```

The dated HTML compiler automatically performs this conversion when a known
OFF filename is present in the selected dump directory. It archives both the
raw capture and normalized semantics under
`tools/action_runtime_compiler/html/off/<version>/`; this standalone command is
mainly for reviewing or updating the checked-in semantic input.

Do not commit large raw HTML or JavaScript dumps. Small generated candidate JSON files and markdown diff reports are acceptable when they are useful for review.

Batch build and merge every manifest character:

```powershell
python tools/modern_display_builder/batch_build_modern_display.py
```

Rebuild one manifest character:

```powershell
python tools/modern_display_builder/batch_build_modern_display.py --character Ryu
```

Batch outputs:

- `tools/modern_display_builder/out/<Character>.official.generated.json`
- `data/TrainingComboTrials_data/modern_display/<Character>.json`
- `docs/modern_display_<Character>_official_diff.md`
- `docs/modern_display_all_characters_batch_report.md`

If a page is reachable but no official action IDs are found, the batch report marks that character as failed/skipped and does not create an empty formal mapping.

## Output Shape

Output follows `xt.modern_display.v1`:

```json
{
  "_meta": {
    "schema": "xt.modern_display.v1",
    "character": "Akuma",
    "generated_from": "capcom_official",
    "source_url": "https://www.streetfighter.com/6/zh-hant/character/gouki_akuma/frame",
    "updated_at": "YYYY-MM-DD",
    "description": "Official Akuma modern display candidate generated from Capcom frame data."
  },
  "617": {
    "classic_display": "HK",
    "modern_display": "AUTO + 強",
    "control_support": "classic_modern",
    "source": "capcom_official",
    "move_name": "立ち強K（首撥ね）",
    "category": "NORMAL",
    "note": "Generated from Capcom official frame data."
  }
}
```

If Capcom provides a classic command but no modern command, the generated entry uses:

```json
{
  "modern_display": null,
  "control_support": "classic_only",
  "note": "No modern command found in official data."
}
```

## Normalization Rules

The tool intentionally keeps normalization small:

- full-width plus and follow-up symbols become `+` and `>`
- extra whitespace is collapsed
- modern buttons are preserved as `弱`, `中`, `強`, `SP`, `AUTO`
- `攻撃` is preserved and marked for review
- air context is lightly normalized to `空中`
- uncertain text remains in the generated display and is marked in `note`

Generated output is a review candidate, not a direct source of truth.
