# Web Character Schema v1

`xt.character.web.v1` 是 AC/BCM 批量导出器生成的网页角色资料文件。它把同版本的统一指令表与
Capcom OFF 帧数快照组合在一个文件中，但保持两个独立索引：

- `actions` 按当前游戏 Action ID 查询，用于连段起手和连段步骤的指令显示；
- `moves` 按稳定的网页招式记录 ID 查询，用于角色资料页、帧数表和招式列表。

生成位置：

```text
tools/action_runtime_compiler/acbcm/<版本>/lastjson_web/<Character>.json
```

## 顶层结构

```json
{
  "_meta": {
    "schema": "xt.character.web.v1",
    "token_schema": "xt.command_tokens.v1",
    "character": "Ryu",
    "fighter_id": 1,
    "action_count": 87,
    "move_count": 82
  },
  "_icons": {},
  "actions": {},
  "moves": {},
  "move_order": [],
  "_audit": {}
}
```

## actions

```json
{
  "904": {
    "move_id": "web:302:1",
    "control_support": "classic_modern",
    "relation": null,
    "classic": {
      "display": "236+HP",
      "tokens": [],
      "mirrored_tokens": []
    },
    "modern": {
      "suppressed": false,
      "simple": {},
      "motion": {},
      "all": {}
    }
  }
}
```

连段数据应保存 `starter_action_id`。网站通过 `actions[String(starter_action_id)]` 读取经典、现代简化
或现代搓招，不应再次解析 `display` 字符串。

## moves

```json
{
  "web:302:1": {
    "official_web_id": "302",
    "name": "強 波動拳",
    "category": "SPECIAL",
    "attribute": "上・弾",
    "command": {
      "source": "action",
      "action_id": 904,
      "fallback": null
    },
    "action_ids": [904],
    "frames": {
      "startup": { "raw": "12", "value": 12 },
      "active": { "raw": null, "value": null },
      "recovery": { "raw": null, "value": null },
      "total": { "raw": "47", "value": 47 },
      "on_block": { "raw": "-9", "value": -9 },
      "on_hit": { "raw": "-2", "value": -2 }
    },
    "damage": { "raw": "700", "value": 700 }
  }
}
```

`command.source = "action"` 时，使用 `actions[String(command.action_id)]`。未能安全绑定当前 Action ID
的官网招式使用 `official_fallback`，其 `fallback` 直接包含可渲染的经典和现代 token。

同一内部招式、同一官网 Action 提示、至少两个等级且备注明确要求按住按钮时，网页生成器将其识别为
等级蓄力组。此类 move 的 Classic 指令使用已验证 AC+BCM Action 投影，Modern 指令使用官网独立
招式语义，并写入 `official_fallback`；Action 索引本身仍保留连段步骤或 assist-combo 语义。

`raw` 永远保留官网原文。只有纯数字字段才写入 `value`；`4-6`、`※1100` 等条件或范围文本的
`value` 为 `null`，网站展示不得丢弃 `raw`。

## move_order

角色资料页必须按 `move_order` 遍历。`official_web_id` 在少数角色中重复，因此不能直接作为 JSON
主键；生成器使用 `web:<id>:<occurrence>`。没有公开 `webId` 的官网内部辅助/快捷输入行不会进入
角色资料页，但仍可参与 AC/BCM 指令编译。

## 数据边界

- AC/BCM：当前游戏 Action ID、动作关系、Classic/Modern 指令投影；
- OFF：招式名、分类、帧数、伤害、取消属性、量表变化和备注；
- AC 的结构帧不能替代官网 `startup_frame/active_frame/recovery_frame`；
- 官网 Action ID 只作提示，只有已验证的当前 Action ↔ 官网语义绑定才能写入 `move_id`。
