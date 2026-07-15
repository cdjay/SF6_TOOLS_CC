# BCM 运行时基础表

这里存放由 `tools/bcm_catalog_builder/` 从完整 BCM 对象图编译出的精简产品数据。完整研究转储不得放进本目录。

运行时解析顺序：

1. 角色 BCM 基础表提供稳定的经典模式 Action ID → 指令。
2. 没有角色基础表或没有对应 Action 时，回退到游戏内实时 BCM。
3. 角色及 Common exceptions 最后覆盖显示名和匹配行为。

`sf6cc.bcm-runtime.v1` 字段：

- `character` / `fighter_id`：角色身份。
- `source_schema` / `source_sha256`：完整 BCM 来源与校验值。
- `policy`：生成时采用的 profile 和例外表策略。
- `actions`：字符串 Action ID 到经典指令的映射。

现代模式不应直接复用 `control_mode_label` 推断。完整 BCM 的 classic/modern 导出可能相同；在 profile 选择规则验证完成前，现代显示继续使用现有 `modern_display` 产品数据。
