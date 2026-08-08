# Unified Command Display Schema v1

`xt.command_display.v1` 是 SF6CC 的统一角色指令表。它是当前游戏版本的 Runtime 投影，不是跨版本 Move 身份定义。

- Action ID 是当前游戏 build 内的动作技术标识，**不是跨版本稳定身份**。跨版本稳定实体是 Move（见 [文档权威](DOCUMENTATION_AUTHORITY.md) 与 [AC+BCM 语义核心](AC_BCM_SEMANTIC_CORE.zh-CN.md)）。
- AC 提供当前版本的动作关系与派生图。
- BCM 的 `norm/easy/sprt/supr` 只负责提供不同控制方式的输入投影。
- 本 Schema 定义的 `xt.command_display.v1` 是 current-build projection，不定义 move_uid。

正式数据暂时保存在兼容目录：

```text
data/TrainingComboTrials_data/command_display/<Character>.json
```

AC/BCM 批量导出还会从同一指令结果与同版本 OFF 快照生成网页角色资料，格式见
`docs/web_character_schema.md`。

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
- 官网已确认的派生输入动作若通过唯一、完整匹配的 AC `Type 37 + Attr 64` 分支进入
  实际执行阶段，执行阶段 Action ID 可继承指令投影；录像中的真实 Action ID 不得改写。
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

少量已由 raw input 与运行时 Action ID 共同验证、但尚未进入生成图的动作，可暂存于
`command_display_overrides/<Character>.json`。这是角色产品数据，不读取连段 JSON 中保存的
motion 作为证据。每条覆盖必须提供非空 `classic`、`evidence`；若支持现代模式，还必须同时
提供 `commands.simple` 与 `commands.motion`。覆盖默认只能补齐缺失 Action，不能替换已生成
条目；加载后统一标记为 `runtime_verified_override`，继续经过与正式指令表相同的严格审计门。

同一文档可选的 `contextual_internal_phases` 只用于声明指令表的上下文内部阶段。
每个 child Action 必须提供非空 `owner_ids` 与 `evidence`；仅当它紧邻其中一个已验证
owner Action 时，绘制与指令完整性审计才能隐藏该 child。单独出现、前驱错误、
配置畸形或明确标记为玩家输入的派生仍必须显示或审计失败。该字段不得写入
`absorb_ids`，不得参与 ActionEventCompiler 折叠或训练匹配；使用该字段时，V2 必须
保留 owner 与 child 两个真实 Action step，以便 raw input 二次回放继续核对数量、
ID、顺序、时序与结果。
