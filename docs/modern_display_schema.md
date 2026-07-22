# Modern Display Mapping Schema v1（历史文档）

> 当前生成器已经升级为统一的 `xt.command_display.v1`。经典和现代指令共享同一份
> AC ActionGraph，正式规范见 [command_display_schema.md](command_display_schema.md)。本文仅保留用于解释旧 v1 文件。

本文档定义 SF6CC 现代控制模式显示映射的数据结构。该结构只服务于连段列表和步骤显示，不参与验证、自动演示、录制主流程或 timeline 解释。

## 目标

现代控制样本与经典控制样本可以共享 combo JSON 的基础结构，但显示层需要根据控制模式选择不同的出招显示。

目标是：

- 旧 combo JSON 默认继续按 classic 显示。
- modern combo JSON 可以通过 `action_id` 查找现代控制显示文本。
- Lua 显示层只依赖 `modern_display` 字段。
- `classic_display`、`source`、`control_support`、`note`、`todo` 只用于审核、工具链和社区数据整理。
- 官网数据作为基础映射来源，社区样本和人工实机验证用于补全派生、上下文动作和缺失动作。

## Combo JSON 模式识别

combo JSON 的模式识别字段仍然放在 sequence 第一项的 `_xt_meta` 中，不迁移到根级。这样可以保持现有读取逻辑兼容。

示例：

```json
[
  {
    "_xt_meta": {
      "control_type": "modern",
      "timeline_input_profile": "modern",
      "control_support": "classic_modern"
    },
    "id": 617,
    "motion": "HK"
  }
]
```

识别规则：

- `_xt_meta.control_type == "modern"` 时视为 modern 样本。
- `_xt_meta.timeline_input_profile == "modern"` 时也视为 modern 样本。
- 没有 `control_type` 的旧 JSON 永远默认为 classic。
- classic JSON 不读取 modern display 映射，保持旧显示逻辑。

## Mapping 文件位置

每个角色一个文件：

```text
data/TrainingComboTrials_data/modern_display/<Character>.json
```

例如：

```text
data/TrainingComboTrials_data/modern_display/Akuma.json
```

## 文件结构

mapping 文件允许根级 `_meta`，同时保留根级 `action_id -> object` 的结构。

示例：

```json
{
  "_meta": {
    "schema": "xt.modern_display.v1",
    "character": "Akuma",
    "updated_at": "2026-07-04",
    "description": "Modern control display mapping for Akuma"
  },
  "617": {
    "classic_display": "HK",
    "modern_display": "AUTO + 強",
    "control_support": "classic_modern",
    "source": "community_sample",
    "note": "Verified by modern control sample."
  }
}
```

Lua 当前按具体 `action_id` 字符串读取：

```lua
entry = modern_map[tostring(step.id or "")]
```

因此根级 `_meta` 不会参与显示查询。

## 字段含义

### `_meta.schema`

固定为：

```text
xt.modern_display.v1
```

### `_meta.character`

角色名，必须与文件名和游戏内 combo 目录使用的角色名保持一致。

### `_meta.updated_at`

映射文件最后维护日期，使用 `YYYY-MM-DD`。

### `_meta.description`

给维护者看的简短说明。

### `classic_display`

经典控制显示文本。用于官网数据对照、审核和后台工具，不参与 Lua 现代显示逻辑。

### `modern_display`

现代控制显示文本。Lua 显示层当前只依赖此字段。

支持的现代 token 包括：

- `弱`
- `中`
- `強`
- `SP`
- `AUTO`
- `+`
- `>`
- `1` 到 `9`
- `空中`

### `control_support`

表示该 action 的控制模式支持情况。

推荐取值：

- `classic_modern`: classic 和 modern 都可显示或复现。
- `classic_only`: 仅 classic 可用或目前只确认 classic。
- `modern_only`: 仅 modern 可用。
- `unknown`: 尚未确认，不要强行猜。

该字段不用于验证。

### `source`

表示当前条目的来源。

推荐取值：

- `capcom_official`: 从 Capcom 官网 command/frame 数据逐条确认。
- `community_sample`: 来自社区 modern JSON 样本并通过实机验证。
- `manual_verified`: 维护者手动确认。
- `inferred`: 由样本、上下文或已有动作关系推断，尚需复核。
- `todo`: 已发现但未完成映射。

不要在未逐条确认官网数据时使用 `capcom_official`。

### `note`

维护说明。可记录上下文、派生关系、实机验证情况或需要官网确认的原因。

### `todo`

可选字段，用于标记待处理项。建议使用结构化值，例如：

```json
"todo": "needs_official_confirmation"
```

不要依赖自然语言 note 来做自动化统计。

## 官网数据与社区样本

Capcom 官网 command/frame 数据适合作为基础映射来源，但不能完全覆盖社区使用场景。

原因：

- 派生动作可能依赖上下文。
- modern 自动派生可能与 classic command 的显示粒度不同。
- 部分 `action_id` 在样本中出现时，需要结合前后动作理解。
- 官网文本中的泛化按钮如 `攻撃` 可能需要人工确认最终显示。

推荐流程：

1. 从官网生成基础 `classic_display` 和 `modern_display`。
2. 社区上传 modern JSON 后统计 action_id。
3. 对照 mapping 文件列出 unknown action_id。
4. 审核员根据样本和实机验证补充 mapping。
5. 稳定后再扩展到其它角色。

## 兼容性要求

- 旧 combo JSON 无 `control_type` 时必须永远默认 classic。
- mapping 文件新增 `_meta` 不应影响 Lua 显示层。
- Lua 显示层只依赖 `entry.modern_display`。
- `classic_display`、`control_support`、`source`、`note`、`todo` 不应用于运行时验证。
- 不允许因为缺少 modern mapping 而报错；缺失时 fallback 到原 classic display。
