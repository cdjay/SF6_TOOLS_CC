# AC+BCM 角色简表编译器

该工具直接读取 SF6CR 导出的完整 AC 与 BCM 对象图，生成版本化角色简表和独立诊断报告。

运行时 Action ID 只来自游戏 dump。官网 OFF 出招表不能作为输入，也不能参与 Action ID 映射。

## 可视化批量构建（推荐）

双击：

```text
tools\action_runtime_compiler\start_html_builder.bat
```

工具会启动仅监听 `127.0.0.1` 的本地服务并打开浏览器。界面中填写 dump 绝对目录和本次版本，扫描后可选择角色批量编译。同一版本可以分多次追加角色；再次选择版本中已有的角色时，会覆盖该角色的 AC+BCM、简表、报告和差异记录，未选择的角色保持不变。

本地输出位于 `tools\action_runtime_compiler\html`：

- `acbcm\<版本>\`：原始完整 AC+BCM、哈希和归档清单；
- `char\<版本>\`：角色简表、编译报告、逐角色差异及汇总差异；
- `latest\`：最新 v2 运行时表，保留给编译器内部审查；
- `latest_exceptions\`：由 AC+BCM 自动生成并通过旧表兼容审计、且状态为 `valid` 的现有角色例外表格式，可全选复制到游戏的 `data\TrainingComboTrials_data\exceptions`；
- `latest-manifest.json`：记录 latest 中每个角色来自哪个归档版本，放在 latest 外以免同步时混入。

以上归档和生成目录都被工具目录内的 `.gitignore` 排除，不会把大型研究 dump 或本机构建物带入提交。

上传新版本时，工具默认与最近一次包含该角色的归档比较，也可以在界面中指定基准版本。同版本覆盖已有角色时，默认与覆盖前内容比较。差异覆盖：

- AC Action ID 增删；
- 指令显示新增、删除与变化；
- AC 派生/人工别名变化；
- TC 与 DRC/RAW DR 语义变化；
- 验证规则变化；
- 编译诊断代码变化及 AC/BCM 源哈希。

## 使用

```powershell
node tools\action_runtime_compiler\compile.js `
  --ac <完整AC.json> `
  --bcm <完整BCM.json> `
  --output <角色简表.json> `
  --report <编译报告.json> `
  [--exceptions <可选人工例外表.json>] `
  [--character <规范角色名>]
```

不传 `--exceptions` 等价于空例外表。人工例外只作为最后一层字段覆盖；编译报告会标记已不在当前 AC 中的过期 ID。

AC 或 BCM 若标记为截断、hard gate 失败或角色动作全集为空，报告状态为 `invalid`，命令返回非零退出码。输出目录不存在时会自动创建；省略 `--report` 时默认写入与简表同目录的 `<简表名>.report.json`。

## 输出

- `sf6cc.action-runtime.v2`：保留兼容字段 `actions`、`aliases`，新增 `validation` 与 `evidence`。
- `sf6cc.action-runtime-compile-report.v1`：记录覆盖率、未分类 AC 动作清单、AC 范围外 BCM 动作、TC 父动作上下文缺口、BCM 多显示候选和过期例外。未分类 AC 动作包含大量系统状态，本身不表示“缺失指令”。

当前已自动解码：

- BCM 经典指令；
- DRC 与 RAW DR 系统动作；
- `turn_around=2` 的 TC 后续段；
- AC `BranchKey Type=29` 的条件/资源等级动作变体，以及结构同构的 Type 35 动作变体；长按等级图中的 Type 29 目标会物化为独立阶段，不再错误吸收到父动作；
- AC Type 20 的空中方向攻击、Type 63 `Param02=1` 的八方向空中攻击与方向投；方向 mask 和终端 `force` 由分支图自动解码；
- 由 Type 29 与 Type 20 至少两个共享等级目标的状态图识别已确认长按动作；精确 `charge_min/max` 没有可靠的角色无关公式时继续留给兼容层，不从 BCM 时间窗猜测；
- BCM 蓄力释放序列的显示正规化，例如 `6646` 自动显示为 `[4]646`；
- AC Type 13 的无输入/落地分支关系；同一语义名称的兄弟目标会同步已确认的 `force=true` 检测规则，例如豪鬼普通/OD 百鬼袭的无操作滑步 `996/1004`；
- 同 BCM gate 的架势后续段（例如本田 `970 → 972`）；
- TC 父动作关系；前后动作显示相同时会写入 `optional_parent_ids`，例如英格丽德 `655 → 656`；
- 可选人工例外覆盖及其验证字段。

每个版本的 `char` 目录同时保存 `<角色>.exceptions.json`。生成表只写现有运行时真正消费的字段；`force=false`、`ignore=false`、`ignore_prev_frames=5` 等默认值不会重复写入。

批量生成时会强制把每个角色与当前 `data/TrainingComboTrials_data/exceptions` 检测表比较，并保存 `<角色>.compatibility.json`。比较会按运行时真实默认值和等价指令写法规格化（例如缺省 `hold_partial_check=true`、`2HP/2+HP`、`drc/DRC`），避免把纯格式差异误算成人工缺口。纯 AC+BCM 已覆盖的旧规则不会重复保留；尚未覆盖但 Action ID 仍存在的规则会自动缩减成兼容兜底层。若最终输出仍遗漏旧表语义，该角色标记为 `invalid`，不会更新 `latest_exceptions`。

编译器不会修改用户录制的连段 JSON。

## 测试

```powershell
node tools\action_runtime_compiler\test_compiler.js
node tools\action_runtime_compiler\test_archive_builder.js

node tools\action_runtime_compiler\verify_known_samples.js `
  --evidence-dir "D:\CP\SF6CR-evidence\AC+BCM+OFF"
```

最后一条命令使用外部研究 dump 回归本田、迪·杰与英格丽德已确认的普通技、派生动作、DRC/RAW DR 和 TC。它只读 dump，不把研究数据或生成物写入仓库。
