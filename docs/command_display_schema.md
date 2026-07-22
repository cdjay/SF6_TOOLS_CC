# Unified Command Display Schema v1

`xt.command_display.v1` 是 SF6CC 的统一角色指令表。它以 Action ID 为稳定身份，
AC 提供动作及派生关系，BCM 的 `norm/easy/sprt/supr` 只负责提供不同控制方式的输入投影。

正式数据暂时保存在兼容目录：

```text
data/TrainingComboTrials_data/command_display/<Character>.json
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
- `control_support`：`classic_modern`、`classic_only` 或 `unknown`。现代投影缺少经典文本时
  必须标记为 `unknown`，因为这表示编译器尚未补齐经典投影，不代表 Action 仅现代可用。

经典指令是独立全集，现代指令是其子集。生成器禁止读取 `simple_command` 或 `motion_command`
的文本来反推经典指令；现代槽只用于执行“所有现代 Action 必须已包含在经典全集中”的完整性检查。

经典投影依次使用已编译运行时语义、稳定公共 Action、BCM `classic_display`，并允许经过严格
验证的等价 Action、结构同源 Action 和 command-entry rebind 继承同一经典指令。经验证的
Type20 保持续段和动作阶段可继承父节点经典投影；其余现代内部阶段只允许通过 AC 完整结构、
BCM 条件距离和 Assist Combo 强度取得可审计的经典投影。每条推导都会写入
`classic_projection_relations`；正式生成要求 `classic_projection_pending_count` 为零，否则整批拒绝发布。

三个指令槽是每条 Action 记录的强制字段。某种控制方式确实没有可执行输入时，该槽写为
`null`；不得为了消除空值而伪造指令。显示层选择简化或搓招时，允许回退到另一个已验证的现代槽。
修复动作关系、投影规则或未识别 Action ID 后，必须重新生成整张角色表，使三个槽在同一次生成中更新。

## 运行时边界

角色指令表只负责动作身份、关系和显示投影，不参与连段成功判定。蓄力窗口、输入保持、
吸收 ID、忽略帧等行为规则仍由 CharacterRules 和 exception 数据负责。加载器完成完整审计后，
只缓存 Action ID 与三个指令槽，避免长期保留大型 JSON。

经典、现代简化和现代搓招显示均以统一角色表为唯一权威。exception 文件禁止保存显示文本，
只保留蓄力、吸收、强制识别、忽略帧等检测行为。
