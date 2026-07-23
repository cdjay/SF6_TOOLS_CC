# Wael → cdjay 交接文件技术审计与主线收敛说明

> 本文以尊重、合作和长期维护为前提，对 Wael 提交的
> [`HANDOVER_cdjay.md`](https://github.com/Wael3rd/SF6_Tools/blob/c8a87efc2acd25786fa50d0bae16290765c46680/HANDOVER_cdjay.md)
> 进行技术核验，并说明为什么 `Wael3rd/SF6_Tools` 与
> `cdjay/SF6_TOOLS_CC` 当前尚不能通过一次普通 Pull Request 或 Git merge
> 直接恢复为同一条开发主线。

## 1. 文档信息

| 项目 | 内容 |
|---|---|
| 文档性质 | GitHub 仓库、Git 历史、代码结构与交接声明的只读技术审计 |
| 审计日期 | 2026-07-23（Asia/Shanghai） |
| Wael 审计基线 | [`Wael3rd/SF6_Tools@c8a87ef`](https://github.com/Wael3rd/SF6_Tools/commit/c8a87efc2acd25786fa50d0bae16290765c46680) |
| SF6CC 审计基线 | [`cdjay/SF6_TOOLS_CC@9b851c5`](https://github.com/cdjay/SF6_TOOLS_CC/commit/9b851c5596e87388f179c789e09379fb722750cf) |
| 交接文件 blob | `18ceb7f11af94bff8398b381486ce5e0aa77a3b8` |
| 本地未推送内容 | 不纳入本次 GitHub 端结论 |

本文讨论的是“当前是否具备直接合并条件”，不是对任何贡献者、实现质量或社区方向的否定。

## 2. 致谢与基本立场

首先，感谢 Wael 对 SF6CC 工作成果所给予的认可，也感谢他投入大量时间完成跨仓库阅读、人工移植、双语适配、实机测试和交接记录。

从提交历史和代码内容可以确认，Wael 并非只做了表面复制。他对多项能力进行了实际接入和适配，包括：

- `CTTimelineSequenceNormalizer`；
- Trial 防御设置保存与恢复；
- 假人蹲姿与防御类型推断；
- Raw Input 与旧 Timeline DEMO 的兼容路径；
- Modern Display 数据与未解析动作审计；
- DynamicRecords Lua 主体；
- 在线对战安全 gate；
- SharedHooks、HitConfirm、SheldonsBoxes 等修复；
- 中文字体、中文顶栏和运行时 i18n；
- 30 个角色的 BCM Catalog 生成结果。

Wael 在交接文件中也主动说明了没有采用的实现、保留的技术取舍和仍需共同决定的问题。这种透明度对后续协作很有价值。

因此，本文的核心结论不是“Wael 的整合没有价值”，而是：

> Wael 已完成大量有效的功能移植，但“功能移植”尚未等同于“Git 主线收敛”；当前仓库状态也还不足以证明 Wael 分支已经成为 SF6CC 在代码、工具、数据、发布和治理意义上的 100% 超集。

## 3. 执行摘要

当前两个仓库不能直接回到同一主线，主要有五类原因：

1. **Git 历史已经断裂。** GitHub 仍显示 fork 关系，但两个默认分支没有共同祖先。
2. **仓库边界不同。** Wael 仓库代表游戏根目录安装包；SF6CC 仓库代表 `reframework` 目录内容及其生成、审计和打包源文件。
3. **核心实现仍然分叉。** 路径归一化后仍有 76 个同路径文件内容不同，核心 Lua 文件存在上万行级别的累计改动。
4. **交接属于人工移植，不是可持续同步。** 多数能力以重新实现、复制生成物或适配方式进入 Wael 主线，没有形成共享源码权威和可重放的提交关系。
5. **产品、数据和治理规则没有统一。** Catalog/Exceptions、RSM/DynamicRecords、Modern resolver、发布版本、CI 和最终维护权仍未确定。

语言和 UI 差异并不是主要障碍。真正的障碍位于 Git 拓扑、代码所有权、数据来源和产品边界。

## 4. 审计范围与方法

本次审计采用以下方法：

- 读取 Wael 交接文件及其对应提交；
- 核对两个 GitHub 仓库的默认分支、HEAD、fork 关系、release、PR 和 Actions；
- 获取两个公开 HEAD，执行 `git merge-base`、`git rev-list` 和 tree/blob 对比；
- 将 Wael 的 `reframework/` 前缀移除后进行规范化路径比较；
- 对交接文件点名的关键 Lua 模块、JSON 数据、生成工具和编辑器进行逐项核验；
- 区分“功能存在”“实现等价”“仓库完整”“可持续维护”四种不同结论。

本次审计不包含：

- 本地尚未推送到 GitHub 的提交；
- 未公开的测试记录或私有仓库；
- 对游戏不同版本、不同 REFramework 版本的完整实机矩阵复测；
- 对参与者主观意图的判断。

## 5. 对 `HANDOVER_cdjay.md` 的总体理解

Wael 在交接文件中表达了三个核心目标：

1. 尽可能吸收 SF6CC 的共享运行时能力；
2. 保留部分不同实现，并解释为什么选择另一条技术路径；
3. 形成“一个核心、两个按语言区分的前端”，再将后续主动权交还给 cdjay。

这些目标是积极的，但文档同时使用了“100% superset”“same result”“one core”等较强表述。要使这些表述成为可验证的工程结论，需要同时满足：

- Git 历史可以追踪；
- 核心模块只有一个权威来源；
- 行为等价有自动或可重复的测试证据；
- 生成器与生成物一起进入主线；
- 产品专属层与共享层有明确边界；
- 双方对发布、维护和后续同步机制达成一致。

目前这些条件尚未全部满足。

## 6. 对交接文件“已整合项目”的逐项核验

### 6.1 CTTimelineSequenceNormalizer

**核验结论：已移植，基础判断成立。**

Wael 分支中可以找到对应 normalizer，并且已经接入组合序列加载流程。这是实际的代码整合，不是文档声明。

需要注意的是，Normalizer 解决的是录制时间轴到验证 step 的归一化问题。它不能自动证明所有运行时 action 匹配分支都与 SF6CC 等价，尤其不能独立替代后文讨论的零连击 pressure skip。

### 6.2 Trial 防御设置保存与恢复

**核验结论：已移植，并且 Wael 后续修复了首次移植时遗漏的字段。**

提交历史显示该功能先进入主线，随后又通过补充 `CT_TRIAL_DEFENSE_FIELDS` 修正实际运行问题。这说明 Wael 确实进行了实机回归和后续修复。

同时也说明，人工移植不能仅以“代码已进入仓库”作为完成标准；还需要回归用例覆盖所有退出路径、录制路径和异常路径。

### 6.3 假人蹲姿与防御类型推断

**核验结论：已移植。**

相关环境、`scene_state`、`_xt_meta` 和 combo 文本读取逻辑已经出现在 Wael 版本中。两边仍保留各自的 jump 与 trial 启动流程，因此应将其描述为“功能已接入 Wael 架构”，而不是“两个实现完全相同”。

### 6.4 Modern 未解析动作审计

**核验结论：已移植，但接入的是 Wael 的 `ModernDisplay.lua` 路径。**

审计层存在，能够记录无法解析的 `act_id`。不过 SF6CC 的 D2D resolver 与 Wael 的轻量 resolver 仍是两套实现，审计数据也不能自动证明两套 resolver 对所有动作产生相同输出。

### 6.5 新版 Combo Schema 警告

**核验结论：警告机制已移植，但完整加载流程并不相同。**

两边都可以识别高于当前支持版本的 `_xt_meta.schema` 并给出提示。SF6CC 的文件加载路径还包含 `pcall`、准备阶段和失败后保持状态等附加保护；Wael 交接提交明确说明只移植了其中一部分。

因此更准确的表述应是：

> 新版 schema 警告能力已移植；完整的文件清理、延迟刷新和失败隔离策略没有完全共用。

### 6.6 BCM Action Catalog

**核验结论：30 角色生成结果已进入 Wael，生成工具链没有完整进入。**

Wael 主线包含 30 个 v2 Catalog 结果，并且在 `CharacterRules` 中接通了 catalog 参数。这是有价值的运行时增强。

但 Wael 仓库没有包含 SF6CC 的完整生成与审计源：

- [`tools/action_runtime_compiler`](https://github.com/cdjay/SF6_TOOLS_CC/tree/9b851c5596e87388f179c789e09379fb722750cf/tools/action_runtime_compiler)；
- `tools/bcm_catalog_builder`；
- `tools/modern_display_builder`；
- 生成规则测试；
- OFF/AC/BCM 版本归档与来源校验；
- 角色批量差异报告。

这意味着 Wael 仓库拥有当前生成物，但不能仅依靠自身仓库完整重现这些生成物。游戏数据更新后，维护工作仍依赖 SF6CC 工具链或人工复制。

从“可运行”角度可以认为已整合；从“可维护、可重现的仓库超集”角度仍不完整。

### 6.7 Modern Display v9 数据

**核验结论：30 个角色的数据文件在审计基线中内容一致。**

这是双方已经成功共享的资产之一。但显示引擎仍不同：

- SF6CC 继续在 `ComboTrials_D2D.lua` 内维护更完整的解析与上下文处理；
- Wael 使用较小的 `ModernDisplay.lua` 做 `act_id → notation` 映射。

“同一批映射数据”不等于“所有显示行为等价”。以下场景仍需要 golden tests：

- 单 step 与多 step combo；
- 录制中实时显示；
- Modern AUTO、SP、AUTO+SP；
- charge、hold、install 和状态派生动作；
- DRC、RAW DR 与动作 alias；
- Classic/Modern 不同控制模式下的 fallback。

### 6.8 DynamicRecords

**核验结论：Lua 主体已移植并双语化，但完整产品工作流缺少编辑器文件。**

Wael 的 `DynamicRecords.lua` 仍声明：

```lua
M.EDITOR_PATH = M.DATA_DIR .. "/editor/SF6CC_TrainingConfigEditor.html"
```

SF6CC 仓库实际包含：

- [`data/SF6CC_TrainingConfigs/editor/SF6CC_TrainingConfigEditor.html`](https://github.com/cdjay/SF6_TOOLS_CC/blob/9b851c5596e87388f179c789e09379fb722750cf/data/SF6CC_TrainingConfigs/editor/SF6CC_TrainingConfigEditor.html)

Wael 审计基线中没有对应文件。因此：

- 训练配置导入、导出和备份 Lua 能力已经存在；
- 本地 Editor 路径会指向一个未随仓库发布的文件；
- “完整 DynamicRecords 产品能力已移植”尚不能成立。

这并不否定 Lua 移植本身，只说明交接清单需要把“核心运行时”和“配套编辑器”分开标注。

### 6.9 “11 项上游修复”

**核验结论：交接文件点名的主要修复大多可以在 Wael 代码中找到，但缺少一份稳定的 11 项来源映射和自动验收结果。**

当前提交历史中存在多个 `sync:`、`feat: port` 和 `port(cdjay #N)` 提交，它们记录了移植意图，但没有形成统一表格来说明：

- SF6CC 原始 commit SHA；
- Wael 对应 commit SHA；
- 是否逐字复制或适配重写；
- 哪些文件和调用路径发生变化；
- 对应的自动测试或实机测试编号。

后续如果继续双向同步，建议把这种映射作为正式 port manifest，而不是只依赖提交标题和网页看板。

## 7. 对交接文件“技术取舍”的详细分析

### 7.1 HP 精确恢复

Wael 认为两边都按具体 HP 点数恢复，而不是按百分比恢复。静态代码层面支持这一结论。

该项不是阻止收敛的主要问题。仍建议共同建立以下测试：

- 普通伤害；
- 灰血；
- Burnout；
- 不同初始血量；
- DEMO、重试和切换 combo 后恢复；
- 中途退出 trial。

### 7.2 Raw Input DEMO 与 CTStunDemoRuntime

Wael 选择以 Raw Input 作为新 combo 的主路径，并保留 CTStunDemoRuntime 作为旧 combo fallback。这个设计有合理依据：在同一个引擎 input hook 上录制和回放，可以减少脚本帧与输入采样之间的漂移。

但交接文件中的“drift is impossible”属于比静态代码能够证明的更强结论。它仍依赖：

- 对应 hook 在当前游戏版本的真实触发行为；
- hitstop、DI、DRC、stun 和场景切换期间的 engine tick 行为；
- 录制与回放时角色状态、控制模式和场景状态一致；
- REFramework 与游戏更新后 hook 语义不变。

此外，保留两套回放引擎会形成兼容矩阵：

| Combo 类型 | 回放路径 |
|---|---|
| 新版且含 `raw_inputs` | Raw Input |
| 旧版且无 `raw_inputs` | Timeline / CTStunDemoRuntime |
| 控制模式不匹配 | Timeline 或拒绝/提示，取决于实现 |
| 更高 schema | best-effort 加载 |

因此该项更适合描述为“Wael 选择了一套主路径，并保留兼容 fallback”，而不是两个仓库已经共享同一个 DEMO 核心。

### 7.3 Same-action continuation

这是交接文件中最需要谨慎修正的一项。

Wael 将以下两个 SF6CC 函数归纳为“重复同一动作，例如 `cr.LK × 3`”：

- `is_same_action_continuation_step`；
- `ct_try_skip_unreported_same_action_pressure_step`。

并认为 `current_combo >= expected_combo` 加 `CTTimelineSequenceNormalizer` 可以取得相同结果。

这一判断对“命中后 combo count 正常递增”的重复动作可能成立，但第二个函数还明确处理零连击 pressure：

```lua
expected_combo == 0
hit_result == "block"
motion contains "WHIFF"
has_hit ~= true and damage_at_step == 0
```

相关代码见：

- [`TrainingComboTrials_v1.0.lua` same-action/pressure 分支](https://github.com/cdjay/SF6_TOOLS_CC/blob/9b851c5596e87388f179c789e09379fb722750cf/autorun/TrainingComboTrials_v1.0.lua#L5244-L5360)

在格挡或空挥场景中，combo count 不会递增，因此不能单独承担 step 区分。SF6CC 的 pressure skip 还会在引擎没有上报中间重复 action 时：

1. 确认当前期望 step 属于零连击 pressure；
2. 检查当前 action 是否能够匹配下一个 step；
3. 为被跳过 step 计算虚拟 timing；
4. 更新 `last_played_frame`、`current_step` 和 UI；
5. 将当前 action 交给下一个 step 继续验证。

Normalizer 可以减少部分重复录制 step，但不能自动替代上述运行时状态迁移，尤其不能覆盖手工编写的 JSON 或无法被 normalizer 合并的 pressure 序列。

因此，更准确的结论是：

> 命中型重复动作可能已经由 combo count 与 normalizer 覆盖；零连击的 block/whiff pressure continuation 尚未证明等价，仍是合并前需要补充回归测试或移植的功能差异。

### 7.4 Modern resolver

Wael 保留轻量 `ModernDisplay.lua`，而没有整体移植 SF6CC 在 D2D 中的约 1300 行解析逻辑。这是一项合理的维护性取舍，但意味着双方选择了不同的 source of truth：

- 一方倾向将语义预编译进映射文件，再以轻量 resolver 消费；
- 一方保留更丰富的运行时上下文、provenance 和显示规则。

如果要回到一个主线，必须明确：

- generator 是否拥有最终语义权威；
- runtime 是否只消费已编译结果；
- 哪些 fallback 允许存在；
- 运行时是否可以根据角色和 action 名称再次推导；
- 所有 30 角色的 expected output 如何自动验证。

在作出这个决定之前，两种实现都可以合理存在，但不能称为“已经是同一个核心”。

## 8. “一个核心、两个语言前端”为何尚未真正实现

交接文件提出英文保持 Wael 布局、中文复刻 SF6CC 顶栏，并通过 i18n 在运行时切换。这一 UI 工作已经取得明显进展。

但从代码结构看，目前实际形态更接近：

```text
Wael 产品运行时
├── Wael 的训练模式与默认配置
├── Wael 的 English UI
├── SF6CC 风格的 Chinese UI
├── Wael 选择的 Modern/DEMO 实现
└── 人工移植的部分 SF6CC 功能
```

而不是：

```text
Shared WTT Core
├── Wael Front-end
└── SF6CC Front-end
```

原因是：

- 两边仍分别维护 `TrainingComboTrials_v1.0.lua`；
- 两边仍分别维护 D2D、UI、Script Manager 和默认配置；
- 共享逻辑没有被提取为唯一版本的 core；
- SF6CC 的生成、发布和 SF6CM JSON 接口没有进入 Wael 产品层；
- Wael 的额外训练模式也没有成为 SF6CC 必须接受的 core 组成部分。

语言切换已经实现，但产品层和核心层还没有完成物理拆分。

## 9. Git 历史为何无法直接合并

### 9.1 GitHub 的 fork 关系与 Git 提交关系不一致

GitHub 页面仍显示：

- [`cdjay/SF6_TOOLS_CC` forked from `Wael3rd/SF6_Tools`](https://github.com/cdjay/SF6_TOOLS_CC)

但两个默认分支的根提交分别是：

- Wael：[`17b20f2` First Release](https://github.com/Wael3rd/SF6_Tools/commit/17b20f29ecf0588537777b5533f07de6ba455696)；
- SF6CC：[`ac3a001` 初始化](https://github.com/cdjay/SF6_TOOLS_CC/commit/ac3a0016bd31ce74456d0a9af81d683566737539)。

实际执行 `git merge-base origin/master upstream/main` 没有返回共同祖先。GitHub Compare API 也返回：

```text
No common ancestor between main and cdjay:master.
```

这通常意味着 fork 的默认分支后来被孤立初始化、历史重写或强制替换。GitHub 保留了仓库网络关系，但 Git 已无法把 SF6CC 的 190 个提交理解为 Wael 255 个提交之上的一组增量。

Git 官方文档说明，默认情况下 merge 会拒绝没有共同祖先的历史；`--allow-unrelated-histories` 只是特殊覆盖选项，不会自动判断两个独立历史中同名文件的真实来源和正确版本：

- [Git `--allow-unrelated-histories` 文档](https://git-scm.com/docs/git-merge#Documentation/git-merge.txt---allow-unrelated-histories)

### 9.2 当前不能形成正常的跨 fork PR

普通 PR 依赖共同祖先来计算：

- base 之后新增了哪些提交；
- 哪些文件由哪一方修改；
- 哪些提交已进入 base；
- 哪些改动可以自动合并；
- review 应聚焦哪些增量。

在没有 merge base 的情况下，GitHub 只能把两个仓库近似视为两个独立项目，无法生成具有工程意义的增量 PR。

Wael 通过人工读取 SF6CC HEAD，再把选定逻辑重新提交到自己主线，绕过了这一平台限制。但这些提交是新的 Wael 提交，不会让原 SF6CC commits 成为 Wael `main` 的祖先，因此不能恢复后续自动同步。

## 10. 仓库边界为何不同

Wael 仓库代表可直接解压到游戏根目录的发行结构：

```text
dinput8.dll
reframework/
README.md
LICENSE
```

Wael 仓库根目录还跟踪了约 22.5 MB 的 `dinput8.dll`，并把 `reframework/` 作为安装子目录。

SF6CC 仓库依据自身架构约定，代表游戏 `reframework` 目录的内容：

```text
autorun/
data/
fonts/
images/
plugins/
tools/
sf6cm_manifest.json
```

发行时再由版本化打包程序组装：

- 标准包；
- runtime 包；
- manifest；
- 对应版本目录；
- 从本地游戏根目录读取 `dinput8.dll` 和运行时配置。

因此，同一个文件在两个仓库中的路径不同：

```text
Wael:  reframework/autorun/TrainingComboTrials_v1.0.lua
SF6CC: autorun/TrainingComboTrials_v1.0.lua
```

未经路径归一化的直接 diff 为：

```text
573 files changed
414341 insertions(+)
412713 deletions(-)
```

该统计因整体目录层级变化和二进制资源而被显著放大，不能当作真实开发量，但它说明普通 PR 会近似显示为“删除一套仓库，再增加另一套仓库”，无法有效 review。

## 11. 路径归一化后的真实差异

将 Wael 路径中的 `reframework/` 前缀移除后，对两个公开 HEAD 的 blob 进行比较：

| 指标 | 数量 |
|---|---:|
| SF6CC 文件数 | 310 |
| Wael `reframework/` 内文件数 | 258 |
| 同路径文件 | 170 |
| 同路径且内容完全一致 | 94 |
| 同路径但内容不同 | 76 |
| 仅 SF6CC 存在 | 140 |
| 仅 Wael 存在 | 88 |

积极的一面是，94 个完全一致文件表明双方已经共享了相当数量的字体、图标、Modern 数据和部分核心模块。

但 76 个同路径不同内容的文件中包含核心运行时。19 个共同 Lua 文件累计约 17,250 行 diff churn，其中：

| 文件 | 约合 diff churn |
|---|---:|
| `autorun/TrainingComboTrials_v1.0.lua` | 7,813 行 |
| `autorun/func/ComboTrials_D2D.lua` | 2,197 行 |
| `autorun/func/ComboTrials_UI.lua` | 1,709 行 |
| `autorun/Training_ScriptManager.lua` | 1,009 行 |
| `autorun/SF6_DistanceViewer.lua` | 971 行 |
| `autorun/SheldonsBoxes.lua` | 676 行 |

这不是简单的翻译差异，而是两套架构长期独立演化后的结果。

## 12. 双方各自独有的产品内容

### 12.1 SF6CC 侧独有或未完整进入 Wael 的内容

主要包括：

- `sf6cm_manifest.json`；
- 版本化 release packaging；
- AC/BCM/OFF/Modern 生成、归档、审计和测试工具；
- `SF6CC_ActionIdProbe.lua`；
- DynamicRecords 本地编辑器；
- `script_whitelist.dll`；
- SF6CC 的架构、愿景、路线图、贡献规范；
- Modern 数据差异报告与回归基线；
- SF6CM 仅通过 JSON 交互的产品接口。

这些内容中有些不应进入 WTT Core，但它们必须被正式定义为“SF6CC 产品层”，不能因为 Wael 已移植共享运行时功能就被视为已经覆盖。

### 12.2 Wael 侧独有或未进入 SF6CC 的内容

主要包括：

- `TrainingReactions_v1.0.lua`；
- `TrainingPostGuard_v0.1.lua`；
- `TrainingMoveExecution.lua`；
- `SF6_Teleport.lua`；
- `SF6_RecordingSlotManager.lua` 及角色基础数据；
- Wael 的额外训练模式、Dashboard 和 Guide；
- Wael 的 game-root release 布局。

这些能力有实际用户价值，但是否应全部属于共享 Core，需要双方共同决定。不能仅因为中文顶栏暂时隐藏部分入口，就默认 SF6CC 已经接受其作为产品默认功能。

## 13. 数据与架构权威仍未统一

交接文件已经诚实地指出若干未决问题，这些问题本身也是无法立即回主线的原因。

### 13.1 DRC / RAW DR 的 `500/501` 语义

当前存在至少两种来源：

- 原始 BCM/生成数据的动作语义；
- `exceptions/Common.json` 中沿用的 MOD 约定。

如果两者冲突，需要确定最终权威，而不是根据加载顺序偶然得到结果。

### 13.2 install 动作与 exceptions

部分 install 状态动作不能仅由 BCM 入口推出，需要 AC universe、状态派生或人工 exceptions。双方需要共同定义：

- 哪些内容由生成器确定；
- 哪些内容允许 manual exception；
- exception 是否只做兼容 fallback；
- generated output 是否可以吸收并消除 exception；
- provenance 如何进入 JSON。

### 13.3 Catalog 与 Exceptions 的开关策略

Wael 将 Catalog 和 Exceptions 设计为两个独立开关；SF6CC 当前更倾向于生成器语义与 manual exception 分层组合。

这会直接影响：

- 动作显示；
- alias；
- absorb；
- force/ignore；
- strict 模式行为；
- 用户配置迁移。

在规则统一前，两边会对同一个 combo JSON 得出不同解释。

### 13.4 DynamicRecords 与 Recording Slot Manager

Wael 选择同时保留两套系统。这是一种安全的短期兼容策略，但长期会产生：

- 重复的数据模型；
- 不同的导入/导出入口；
- 相同录像槽的并行管理；
- 不同的备份和社区分享格式；
- 用户不知道哪个系统是官方推荐路径。

该问题需要产品级决策，而不是简单删除其中一个实现。

## 14. 测试、发布和治理差异

### 14.1 当前缺少代码 CI

GitHub 端检查显示：

- SF6CC 没有公开 GitHub Actions 工作流；
- Wael 当前主要是 GitHub Pages build/deploy；
- 交接提交上的绿色检查不是 Lua、JSON、Catalog 或游戏运行时测试。

Wael 在交接文件中记录了语法检查、声明顺序检查、引号扫描和实机测试，这些工作值得肯定。但如果要建立共同主线，还需要可重复的自动验收，例如：

- Lua load/syntax；
- 200 local 限制；
- JSON schema；
- 30 角色 Catalog/Modern golden output；
- same-action hit/block/whiff；
- Raw Input 与 Timeline fallback；
- online safety；
- trial 所有退出路径的设置恢复。

### 14.2 交接不是正式融合 PR

`HANDOVER_cdjay.md` 是直接进入 Wael `main` 的文档提交，不是跨仓库的融合 PR。它没有提供：

- 双方可共同 review 的完整增量 diff；
- 明确的 acceptance criteria；
- 双方对每项取舍的确认记录；
- 合并后谁维护共享 core 的治理规则；
- 下一次双向同步的流程。

“将主动权交还给 cdjay”体现了尊重和合作意愿，但从工程治理角度，它也把剩余收敛责任转移给了一个无法正常向 upstream 发 PR 的孤立历史分支。

### 14.3 默认分支缺少保护

审计时两个默认分支均未发现 branch protection 或 ruleset。该情况不是当前无法 merge 的直接原因，但会使未来共同主线继续面临：

- force push 再次断开历史；
- 未经 review 的直接提交；
- 没有强制测试；
- 生成物与生成器不一致；
- release 从未经验证的 HEAD 构建。

### 14.4 发布版本体系不同

公开 release 仍分别使用：

- Wael：`v2.x`；
- SF6CC：`v0.x`。

两个审计 HEAD 都晚于各自最新正式 release。交接后的 Wael `main` 尚不能等同于已发布、已被用户验证的统一版本。

共同主线需要确定：

- 版本命名；
- 配置迁移；
- Combo JSON 兼容范围；
- 哪一套 release layout 是权威；
- 如何标记 WTT Core 版本与 SF6CC 产品版本。

### 14.5 License 与贡献归属需要补齐

Wael 仓库包含 MIT LICENSE。SF6CC README 在审计基线中引用 `LICENSE` 和 `LICENSE_NOTES.md`，但这两个文件没有出现在公开 tree 中，GitHub 也没有识别出许可证。

这不是本文的法律判断，也不否定已有 MIT 来源代码的历史授权；但在重新整理主线、迁移贡献和发布统一版本之前，应明确：

- 上游 MIT 文本；
- SF6CC 新增贡献的许可；
- Wael、cdjay、Jaxen、fattypiggy 等贡献者的作者身份；
- 人工移植提交与原始 commit 的映射；
- 生成数据和二进制资产的来源说明。

## 15. 为什么当前“回不到一个主线”

综合以上证据，原因可以归纳为以下层次。

### P0：Git 拓扑阻断

- GitHub fork 关系仍在；
- Git commit graph 已完全断开；
- 无 merge base；
- 190 与 255 个提交无法表示为正常的上游/下游增量；
- 普通跨 fork PR 无法工作。

### P0：仓库边界冲突

- Wael 根目录是游戏根发行包；
- SF6CC 根目录是 `reframework` 源内容；
- 同一文件路径整体相差一层；
- 二进制、工具、文档和生成物的跟踪规则不同。

### P1：共享 Core 没有唯一权威

- 核心同名 Lua 文件继续双线演化；
- 只有部分模块完全相同；
- 没有公共 core package 或 subtree；
- 后续改动仍需人工 port。

### P1：功能等价尚有缺口

- same-action 零连击 pressure 没有证明等价；
- DynamicRecords editor 没有进入 Wael tree；
- schema 加载保护只移植一部分；
- Modern resolver 仍是两套实现；
- 双回放引擎形成额外兼容矩阵。

### P1：生成与数据规则没有统一

- Wael 拥有生成结果，但缺少完整生成器；
- `500/501`、install、exceptions、catalog 权威仍未定；
- 新游戏版本出现后可能再次分叉。

### P2：产品与治理没有统一

- WTT、Wael Edition、SF6CC、SF6CM 的责任边界仍需正式确认；
- 没有共同 release/version 策略；
- 没有代码 CI 和 branch protection；
- handover 不是双方验收的 PR 或 ADR；
- License 和作者映射需要补齐。

## 16. 不建议采用的合并方式

不建议直接在现有默认分支执行：

```bash
git merge --allow-unrelated-histories
```

原因是它只能在提交图上创建一个双父 merge commit，却不会解决：

- 整体路径移动；
- 573 个文件级差异；
- 同名核心文件该保留哪一版；
- 生成器与生成物的权威；
- 产品默认值；
- 数据兼容；
- 发布方式；
- 未来如何继续同步。

结果很可能是一次无法 review、无法解释、也无法作为未来基线的巨型合并。

## 17. 推荐的主线恢复方案

### 17.1 推荐目标：一个真实共享的 WTT Core，两套独立产品层

更符合双方现状和 SF6CC 长期架构的形式是：

```text
WTT Core（唯一权威）
├── Wael 产品层 / English 默认体验
└── SF6CC 产品层 / 中文、本地化、生成工具与 SF6CM JSON 接口
```

其中：

- Combo 核心验证、SharedHooks、RuntimeSafety、通用数据 schema 属于 Core；
- Wael 的额外训练模式可以作为 Wael 产品功能或经共同同意进入 Core；
- SF6CC 的本地化、打包、生成审计和 SF6CM manifest 保留在 SF6CC 产品层；
- SF6CM 继续只通过 JSON 与 Lua 项目通信，不形成直接依赖。

### 17.2 建议步骤

1. 冻结并标记当前两个公开 HEAD，保留完整历史证据。
2. 为当前 SF6CC `master` 建立永久 `legacy` tag/branch，不直接删除现有历史。
3. 从 Wael `main` 提取 `reframework/` 子树，建立路径一致的 Core 基线。
4. 从该 Core 基线创建新的 SF6CC 开发分支，使未来真正拥有共同祖先。
5. 将 SF6CC 独有内容按子系统重新引入，而不是整体合并旧 tree。
6. 为所有人工 port 建立 source commit → target commit 映射，保留作者与来源。
7. 对未决架构建立 ADR：
   - Raw Input / Timeline；
   - Same-action continuation；
   - Modern resolver；
   - Catalog / Exceptions；
   - RSM / DynamicRecords；
   - release layout。
8. 建立自动回归和实机测试矩阵。
9. 通过一个可 review 的 integration PR 完成新基线验收。
10. 为默认分支开启禁止 force push、必须 review 和必须通过检查。

### 17.3 合并验收条件

在宣布“回到一个主线”之前，至少应满足：

- [ ] 两个产品分支拥有真实共同祖先；
- [ ] GitHub 可以正常计算 ahead/behind；
- [ ] 可以创建常规跨 fork PR；
- [ ] Core 文件只有一个权威来源；
- [ ] same-action hit/block/whiff 全部回归通过；
- [ ] Raw Input 与旧 Timeline combo 均可回放；
- [ ] 30 角色 Modern/Catalog golden tests 通过；
- [ ] DynamicRecords Lua、编辑器和格式文档完整；
- [ ] generator 能从已记录来源重建全部生成物；
- [ ] SF6CC manifest 与发布打包不直接依赖 SF6CM；
- [ ] License、Credits 和 commit 来源映射完整；
- [ ] 共同版本和发布说明已经确定；
- [ ] 双方对关键 ADR 和维护责任完成确认。

## 18. 最终结论

Wael 的交接工作值得感谢，也已经显著减少双方在共享运行时功能上的差距。他完成的移植、实机测试、双语化和技术取舍说明，为后续真正收敛提供了良好基础。

但当前状态仍应准确描述为：

> Wael 主线已经吸收了大量 SF6CC 功能，并形成了一个具有较高兼容度的 Wael 实现；SF6CC 则继续保留更完整的生成、审计、产品和发布体系。双方尚未恢复共同 Git 历史，也尚未形成唯一共享 Core。

因此，当前不能通过一次普通 merge 或 PR 直接回到同一主线。根本原因不是合作意愿不足，也不是中英文 UI 无法统一，而是：

- 历史已经断裂；
- 仓库边界不同；
- 核心仍有实质差异；
- 部分功能只完成了运行时移植；
- 生成、数据、发布和治理权威尚未统一。

这并不意味着未来无法收敛。只要保留双方现有成果，重新建立有共同祖先的 Core 基线，并通过可重复测试和正式 PR 逐项验收，就可以从“人工双向移植”转变为长期可维护的上游/下游协作关系。

再次感谢 Wael 对 SF6CC 工作成果的尊重、署名和整合投入。本文希望为双方提供一份客观、可执行的技术基础，使后续讨论聚焦于如何共同维护，而不是否定任何一方已经完成的工作。

## 附录 A：主要证据链接

- [Wael 交接文件（固定提交）](https://github.com/Wael3rd/SF6_Tools/blob/c8a87efc2acd25786fa50d0bae16290765c46680/HANDOVER_cdjay.md)
- [Wael 审计 HEAD](https://github.com/Wael3rd/SF6_Tools/commit/c8a87efc2acd25786fa50d0bae16290765c46680)
- [SF6CC 审计 HEAD](https://github.com/cdjay/SF6_TOOLS_CC/commit/9b851c5596e87388f179c789e09379fb722750cf)
- [Wael 仓库](https://github.com/Wael3rd/SF6_Tools)
- [SF6CC 仓库及 GitHub fork 标记](https://github.com/cdjay/SF6_TOOLS_CC)
- [GitHub Compare API](https://api.github.com/repos/Wael3rd/SF6_Tools/compare/main...cdjay:master)
- [GitHub 跨 fork 比较说明](https://docs.github.com/en/pull-requests/how-tos/commit-changes/comparing-commits)
- [Git 无共同祖先合并说明](https://git-scm.com/docs/git-merge#Documentation/git-merge.txt---allow-unrelated-histories)
- [SF6CC same-action/pressure 实现](https://github.com/cdjay/SF6_TOOLS_CC/blob/9b851c5596e87388f179c789e09379fb722750cf/autorun/TrainingComboTrials_v1.0.lua#L5244-L5360)
- [SF6CC Action Runtime Compiler](https://github.com/cdjay/SF6_TOOLS_CC/tree/9b851c5596e87388f179c789e09379fb722750cf/tools/action_runtime_compiler)
- [SF6CC DynamicRecords Editor](https://github.com/cdjay/SF6_TOOLS_CC/blob/9b851c5596e87388f179c789e09379fb722750cf/data/SF6CC_TrainingConfigs/editor/SF6CC_TrainingConfigEditor.html)

## 附录 B：术语说明

| 术语 | 本文含义 |
|---|---|
| WTT Core | 双方均可复用的通用训练运行时、schema 和基础模块 |
| Wael 产品层 | Wael Edition 的训练模式、默认 UI、Dashboard、Guide 与发布结构 |
| SF6CC 产品层 | 中文体验、数据生成审计、发布工具、社区规范与 SF6CM JSON 接口 |
| 功能移植 | 在另一套架构中重新接入相同或相近能力 |
| 行为等价 | 在明确输入和运行环境下产生相同可观察结果 |
| 主线收敛 | 拥有共同 Git 历史、唯一 Core 权威、可持续 PR 与发布流程 |
