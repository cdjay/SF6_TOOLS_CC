# BCM 简表生成器

这个工具把 SF6CR 导出的完整 BCM 对象图转换成适合审查和 MOD 读取的版本化简表。

## 使用方式

直接打开 `index.html`，把 `*-bcm-full-*.json` 拖入页面。转换完全在浏览器本地完成，不上传文件。页面可以筛选 Action ID、比较 `norm/easy/sprt/supr`，并导出两种结果：

- 审查简表：保留四套 profile、触发条件、指令变体和转换诊断。
- MOD 基础表：仅保留运行时需要的 `Action ID → 经典指令`，由 exceptions 继续覆盖行为与显示例外。

命令行等价用法：

```powershell
node tools\bcm_catalog_builder\build_catalog.js <完整BCM.json> <BCM简表.json> [角色规范名]
```

把 AC Action 全集、BCM 审查简表和例外表合并成最终运行时表：

```powershell
node tools\bcm_catalog_builder\build_action_catalog.js <完整AC.json> <BCM审查简表.json> <运行时表.json> [例外表.json]
```

请把临时输出写到仓库外。只有经过验证、供 MOD 使用的角色简表才应放入 `data/TrainingComboTrials_data/bcm_catalog/` 并纳入版本控制。

## 输出边界

- `classic_display` 使用与当前 MOD 相同的 `norm → sprt` 选择顺序。
- 四套 profile 和所有指令变体都会保留。
- 工具不会仅凭导出文件的 `control_mode_label` 猜测现代模式映射。完整 classic/modern 对象图可能完全相同；现代 profile 选择策略需要单独验证。
- BCM 提供基础指令，现有 exceptions 继续负责吸收动作、蓄力窗口、前置动作忽略、强制匹配等行为例外。
- DRC 与 RAW DR 不依赖角色 Action ID：生成器以 BCM 的系统类别、功能号与 Focus 消耗组合识别它们，即使基础输入同为 `66` 也会输出正确名称。
- BCM 在提供经典指令的触发器上以 `turn_around=2` 标记 TC 后续技；生成器据此添加 `>`。该规则已用本田与英格丽德交叉验证，包括英格丽德空中 `HK > HK`。
- 页面使用无损整数预处理；BCM 的 64 位条件 flags 会以十进制字符串保留，避免浏览器把它们四舍五入。
- 重复方向之间的 BCM 中立帧会规范成玩家指令写法，例如 `5,2,5,2 → 22`；只有蓄力位或蓄力输入类型才会生成 `[8]2` 一类写法。
- 两种输出都会记录原始完整 BCM 文件的 SHA-256，用于确认基础表来源和发现过期转换结果。
- 证据集把角色写成 `Fab` 时，生成器会用 `fighter_id` 转换成 MOD 使用的规范角色名（例如 20 → `EHonda`）；可选命令行参数仍可显式覆盖。
- 最终运行时表只使用游戏 dump：AC 提供实际 Action ID 全集和派生关系，BCM 提供实际指令入口；exceptions 的直接显示名及 `absorb_ids` 建立人工确认的别名。
- 官网 OFF 出招表不是游戏 Action ID 的证据，不能输入本工具或回填运行时表；它仅可作为人工核对指令文本的参考。
- AC 会继续查找高置信的状态替换别名：必须由 `BranchKey Type=29/35` 直接指向，且与 BCM 基础动作的关键结构同构；结果计入 `coverage.ac_derived_alias_count`。
- 对于引擎标成自动过渡的架势普通技，MOD 仅在最终运行时表已有明确入口且检测到实体攻击键时视为主动输入；没有入口的后续动画仍会被过滤。

## 测试

```powershell
node tools\bcm_catalog_builder\test_bcm_catalog.js
```
