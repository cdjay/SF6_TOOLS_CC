# Unified Command Display Schema v1

`xt.command_display.v1` 是 SF6CC 的统一角色指令表。它以 Action ID 为稳定身份，
AC 提供动作及派生关系，BCM 的 `norm/easy/sprt/supr` 只负责提供不同控制方式的输入投影。

正式数据暂时保存在兼容目录：

```text
data/TrainingComboTrials_data/modern_display/<Character>.json
```

## 条目

```json
{
  "1234": {
    "classic_command": {
      "display": "236+LP",
      "inputs": ["236+LP"]
    },
    "simple_command": {
      "display": "SP",
      "inputs": ["SP"]
    },
    "motion_command": {
      "display": "236 + 弱",
      "inputs": ["236 + 弱"]
    },
    "relation": {
      "type": "followup",
      "source_action_id": 1200,
      "evidence": "capcom_official_followup_context_matches_source_move"
    },
    "control_support": "classic_modern"
  }
}
```

- `classic_command`：经典指令投影，顺序为 `norm → sprt`。
- `simple_command`：现代简化指令投影，主要来自 `easy/supr`。
- `motion_command`：现代搓招投影，主要来自 `sprt`。
- `relation`：共享 ActionGraph 中已验证的派生关系。
- `modern_display`：旧读取器使用的兼容摘要，不是权威字段。
- `control_support`：`classic_modern`、`classic_only` 或 `unknown`。现代投影缺少经典文本时
  必须标记为 `unknown`，因为这表示编译器尚未补齐经典投影，不代表 Action 仅现代可用。

经典投影依次使用已编译运行时语义、稳定公共 Action、BCM `classic_display`，并允许经过严格
验证的等价 Action、结构同源 Action 和 command-entry rebind 继承同一经典指令。无法证明的
Assist Combo 内部阶段和保持转换不会猜测，计入 `classic_projection_pending_count`。

## 运行时边界

角色指令表只负责动作身份、关系和显示投影，不参与连段成功判定。蓄力窗口、输入保持、
吸收 ID、忽略帧等行为规则仍由 CharacterRules 和 exception 数据负责。加载器完成完整审计后，
只缓存 Action ID 与三个指令槽，避免长期保留大型 JSON。

迁移期间经典显示仍以已有 exception 显示覆盖为最高优先级，再回退到 `classic_command`；
完成 30 角色回归后才能删除 exception 中纯显示字段，行为字段不得随之删除。
