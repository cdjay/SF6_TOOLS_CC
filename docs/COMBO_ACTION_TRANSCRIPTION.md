# 连段 Action 转录架构

## 事实边界

连段数据分成三层，优先级不可颠倒：

1. `relative_raw_inputs`、旧版 `raw_inputs` 或 `timeline`：玩家实际输入，是可重放的事实。
2. 游戏运行时 Action 事件：重放输入后，由游戏实际产生的 Action ID、命中、连击数和伤害。
3. V2 steps：为 SF6CC、WTT 和指令表 UI 生成的兼容产物。

指令表、角色例外和旧 V2 steps 只能用于显示或兼容读取，不能决定录制时“发生了哪个
Action”。V2 格式保持冻结，不增加 WTT 无法识别的新顶层结构。

## 新录制

`ActionEventCompiler.lua` 按帧观察：

- 物理输入的按键边沿、方向变化和双击方向；
- 游戏实际暴露的 Action ID 与 ActionFrame；
- 实际 HP、combo count 和格挡接触。

HP 下降只参与伤害累计，不能单独证明一次新命中。接触事实必须来自 combo count 增长，
或来自一次尚未消费的受击类型 / hit stop 新周期，并超过已支持的持续伤害单次范围；
格挡使用独立且同样只消费一次的周期。
因此持续毒伤仍保留在原始 HP 损失遥测中，但不会制造 Action 命中、刷新尾部结算时间，
也不会把最后一次真实接触之后的无限 DOT 写进连段总伤害。
只有在真实 combo reset 到重新命中的时间窗口内，同时观察到多次、小额、无接触信号
的持续伤害，而且各段 combo 峰值能够精确重构源文件总数（例如 `1 + 27 = 28`），
系统才允许修正旧录制器被 DOT 掩盖的计数；普通掉连后再次命中仍按失败处理。
旧录制器还可能把后续派生招式的多段命中提前记到前一个 Action。此时只允许源计数在
同一运行时连段分段内暂时领先：每段首尾必须与运行时累计值完全相等、运行时计数不得
回退、源计数途中不得落后，且非接触 Action 不能承接新增计数；Action 序列与最终重构
总数仍须完全一致。源文件明确写为未接触的末尾设置动作，只有在运行时已于前一 Action
达到全部正数连击、末行既不接触也不增加伤害时，才不会因延迟写入的累计值被误判为
“必须命中的最后一招”。

只有输入锚点与随后发生的运行时 Action 绑定后，才生成一个 V2 step。保存时继续输出
`id`、`motion`、`expected_combo`、`expected_hp`、`delay_from_prev` 和命中字段，因此
WTT 不需要修改。`motion` 优先由当前 Action 指令目录生成；目录缺项时退回输入记号。
普通玩家指令保留实际 Action ID；只有经过 ActionGraph 证实的帧零 command-owner 分支才会
在 V2 step 中规范化为可执行指令的 owner。规范化不能改写下面的原始观察轨迹。

每次 Action ID 变化或同 ID 的 ActionFrame 回卷也会原样进入转录报告的
`action_trace.observed_actions`，用于核对“游戏实际发生了什么”；没有对应新输入的内部
过渡只进入审计轨迹，不会伪造成玩家需要执行的 V2 step。

旧 V2 若按例外数据库的 `record_absorb_as_parent` 把帧零派生或内部命中 Action 记在父
Action 名下，编译器只在角色规则明确声明且相邻 Action 关系匹配时规范化为同一个可见
command owner。`action_event_projection` 中仍由 `absorb_ids` 定义该 owner 的阶段成员；
`canonical_owner_ids` 只是允许 owner 缺席时独立规范化的子集，其余成员只能紧邻已出现的
owner 折叠，canonical 的时间窗口与同锚要求也必须由该产品数据明确声明。第二次 raw replay
必须用同一输入重现相同的规范化指令序列、时序和结果；
状态选择允许同一 command owner 在两次回放中经过不同的已验证内部分支。捕获与验证报告
各自用 `observed_actions` 保留实际子 Action ID，`projected_events` 同时记录
`normalized_from_action_id`，供人工比较真实分支。这不是宽泛 Action 别名，关系不匹配时
仍然严格失败。

所有角色 Action ID 关系必须保存在 `exceptions/<Character>.json`，通用 Lua 不得按角色名
或角色 Action ID 分支。`action_event_projection` 描述 command owner 与内部阶段；
`action_event_rules.transient_precursor_ids` 描述同一物理输入短暂产生的前驱 Action；
`action_event_rules.suppress_after` 描述只在指定前驱、锚点类型、时间窗口和接触条件下抑制的
尾部 Action；`action_event_rules.preserve_quick_successor` 描述一个应保留的取消 Action
与同一输入随后启动的真实 Action，并用 `max_delay_frames` 限制锚点续传窗口。
`CharacterRules` 只把这些产品数据编译成纯运行时关系表，
`ActionEventCompiler` 与实时验证器消费同一张表。

多键指令还有一条不依赖角色或 Action ID 的输入事实规则：若游戏在完整 `PP`/`KK`、
`PPP`/`KKK` 或显式多键指令下短暂暴露一个无接触的单拳/单脚 Action，且和弦在统一
完成窗口内形成，
编译器与实时验证器都把该 Action 视为 `partial_chord_precursor`，等待随后出现的完整
指令 Action。已经发生接触、超过窗口或没有完整和弦证据的单键 Action 仍是独立动作；
完整按键在 20 帧内形成后只允许最多 2 帧的 Action 可见延迟，press/release 绑定都按物理
按下帧计算。后继 Action 若不是冻结步骤的精确/兼容 ID，只能由严格 AC+BCM 生成目录中的
共享状态来源组确认；显示文本和 display override 不参与。该规则不推断 Move 归属，也不
修改 V2 timeline、raw input 或 Action ID。

父 Action 的吸收关系不得遮蔽当前冻结步骤：在 input-truth 检测中，如果被吸收的后继
Action 本身就是当前步骤的精确 ID、显式兼容变体或严格生成的同源变体，实时消费者必须
保留该后继并交给统一 matcher。其他内部 phase 仍按既有吸收语义附着到父 Action；该规则
不改变 Recorder 的折叠结果，也不把 absorb 关系升级为跨版本 Action 等价。

Runtime 入口统一通过 `UnifiedActionConsumer.lua` 消费这套既有合同。该模块只转发
`ActionEventCompiler`、`ActionMatcher` 与 `CommandResolver` 的现有决定，不定义新的
Action 范围、过滤条件、命中规则或 V2 字段语义。录制、训练检测与运行审计不得绕过该入口
另建一套 Action 判定；Presentation 仍只负责显示投影。

实时检测中的角色条件同样必须数据化：Action 条目的 `runtime_force_after_ids` 只在声明的
前驱 Action 后启用强制识别；角色根级 `_character.allow_pending_absorb` 控制该角色能否在
连击数尚未到达时暂存内部命中阶段；`preserve_short_action` 控制短 Action 是否绕过通用幽灵
过滤。Lua 只执行这些布尔策略，不识别角色名或角色 Action ID。

展示分组和旧文件环境修复也遵守相同边界：
`_character.sequence_grouping.structural_followup_chains` 与
`break_followup_after_ids` 保存 Action 间的分组关系；
`command_display_overrides` 的 `presentation_contexts` 保存本地化的状态上下文标签，
并可声明该上下文指令必须独立成行。它只改变显示，不修改 V2 `motion`、Action ID、检测或回放；
`_character.transcription_rules.initial_unique_requirements` 保存“哪些 Action 证明起始角色资源
必需”的映射。`SequenceGrouping` 和 `Transcriber` 只实现通用关系解析与事实推导。

被抑制或折叠的 Action 默认只向 command owner 合并命中、格挡、连击数和累计伤害等结果
事实。它的按钮边沿、松键掩码、蓄力帧和 `is_holdable` 分类不属于 owner，不得传播；只有
通用机制明确把一个输入前驱提升为真实 command owner 时，才允许迁移输入锚点事实。

Action ID 对应的经典指令优先由已审计的角色指令表解析。解析器报错仍会使批量转录失败。
如果目录缺少某个 Action，但它绑定了明确按键并在运行时真实命中、格挡或形成明确的
非接触设置动作，转录阶段可以保留该 ID，并从完整输入方向序列生成待验证 motion，同时
在报告中写入 `input_derived_contact_motion` 或 `input_derived_noncontact_motion` 提示。
这只用于保留诊断证据，不代表最终通过：运行目录审计仍会按实际连段表判定，任何
“指令未识别”都必须先补齐 command owner、折叠内部阶段或提供严格指令映射。按键松开
触发的内部 Action 阶段会合并回原输入；快速出现的 Drive Parry 前置阶段会提升为实际
`RAW DR` Action，而有明确停留时间的 `PARRY > RAW DR` 仍保留为两个指令。

部分招式会先暴露没有指令表语义的内部 Action，几十帧后才进入可持久显示的真实
Action。编译器允许同一个输入锚点沿运行时 Action 轨迹向后提升最多 60 帧，但绝不跨越
下一个物理输入事件。每次提升都会写入 `action_trace.promoted_events` 的原 ID、目标 ID
与帧号；这是一条统一的时序规则，不是角色或连段例外。

当同一录制前段已实际造成伤害，而末尾真实 Action 不增加伤害与连击数时，系统会自动
将最后一步标记为 V2 已有的 `validation_role: "pressure_tail"`。训练时仍必须在正确
时机做出该 Action ID，但它命中、被挡或空挥都可以完成；不会再进入普通招式的命中或
15 帧格挡确认逻辑。这个语义在候选生成、直接录制保存和 JSON 加载时都会自动归一化，
因此不要求普通录制者手工标注，管理员标注仅作为兼容覆写。

## 批量转录

游戏内菜单的“转录当前角色全部连段”会：

1. 扫描当前 P1 角色的全部连段 JSON；
2. 每个文件先选择真实输入来源：已有 `relative_raw_inputs` 时直接使用；旧文件同时有
   native `raw_inputs` 与可用 `timeline` 时优先重放 timeline，以重建不受换边影响的输入；
   只有 native raw 而没有可用 timeline 时才原样使用 native raw；
3. timeline 回放期间逐帧捕获实际注入游戏的输入，并按当帧角色朝向转换为内嵌
   `relative_raw_inputs`；已有相对输入继续保持相对语义，raw-only 文件则保留其原生输入
   事实；
4. 输入结束后保留最多 360 帧结算窗口，等待末尾命中和 combo count 归零；
5. 用新编译器重新生成完整 V2 steps；
6. 原文件的 Action steps、伤害和最大连击只用于生成差异提示；它们是旧录制器的派生
   结果，不再阻止按输入事实重建候选。差异写入 `source_advisories`，不会被静默丢弃。
   未解析输入、未解析 motion、超时、资源消耗和必要格挡接触仍会中止本次候选；
7. 加载源文件后进入完整训练启动流程，应用该连段记录的位置、血量、斗气、SA、角色
   资源和防御设置；位置/资源重注入以及训练场刷新完成后，才开始稳定预滚倒计时；
8. 候选生成后再次恢复训练环境，并只使用刚生成或保留的内嵌输入流重放一遍；
9. 第二遍逐项核对实际 Action ID、动作数量、相邻动作时序、每一步连击数和累计伤害，
   同时再次核对整条连段的伤害、最大连击、格挡接触、斗气和 SA 消耗；
10. 两遍都通过才写候选文件，并在候选元数据及报告中写入
   `raw_replay_verified: true`；任一遍失败都只写报告。

V2 `scene_state` 是新文件的场景权威。只有旧 WTT 文件缺少对应 V2 值时，播放器才从
`snapshot_gauges` 补足生命、虚损、斗气和枯竭状态。候选文件若同时保留两种字段，会把
已有旧字段同步为 `scene_state` 的值，并在保留虚损差值的同时记录同步数量，避免 SF6CC
与 WTT 对同一 JSON 应用不同初始状态。

新版直接录制和 timeline 转录候选以内嵌 `relative_raw_inputs` 作为首选回放事实。它和
native `raw_inputs` 使用同一 uint16 mask；只有左右方向位会在录制时按当帧朝向归一化，
播放时再按实时朝向投影，因此换边前后的“前/后”语义保持不变。`_xt_meta.input_stream`
记录 `{ field: "relative_raw_inputs", encoding: "facing_relative_v1" }`。

为兼容尚未识别该扩展的旧 WTTmod，相对输入候选保留 timeline 且不并存已知错误的 native
`raw_inputs`：旧 WTT 会忽略未知字段并自然回退 timeline。只有 raw input、没有可用
timeline 的旧文件仍保留 native `raw_inputs`，不会被猜测转换。V2 schema 继续保持 2。

训练检测也遵守同一边界：含有效 `relative_raw_inputs` 或 `raw_inputs` 的文件使用输入事实
严格模式，只有 JSON 中记录的 Action ID（或明确声明的版本变体 ID）才能完成对应 step。
没有新输入锚点的游戏内部 Action 只进入观察日志，不会触发“错误动作”；旧 `absorb_ids`
也不能代替已转录的 Action step。按键松开只在紧邻窗口内保留负缘触发语义，陈旧松键
不能绑定几十帧后的低编号移动/系统 Action；否则蓄力技输入过程中的跳跃启动会被错误
绘制成独立的“上”。只有 timeline-only 的旧 WTT 文件继续走历史兼容规则。

源文件永远不会被覆盖。每次运行使用独立目录：

```text
TrainingComboTrials_data/TranscribedCandidates/<Character>/<timestamp>/
TrainingComboTrials_data/TranscriptionReports/<Character>_<timestamp>.json
```

两个目录都是运行时产物，已加入 `.gitignore`。人工验证通过后，再由维护者选择哪些候选
进入产品数据。菜单中的“载入最近转录报告”可以直接逐个加载隔离候选并开始训练，无需
复制或覆盖源文件。

转录被取消或游戏脚本重载后，先载入最近报告，菜单会显示“继续转录（剩余 N）”。继续
时按报告内的 `source_file` 去重：新流程明确写入 `raw_replay_verified: false` 的失败
项目和带 `raw_replay_verified: true` 的通过项不会重复播放；旧报告中缺少该字段的成功
与失败都会自动重新排队，因为它们可能受旧版环境启动时序影响。新结果继续写入原候选
目录与原报告。“重新转录全部”才会显式创建新的批次。

失败项同时记录 `validation_revision`。当资源或结果验收口径升级时，旧 revision 的失败
会自动重新排队；已经完成 raw 二次验证的成功候选不会因此整批重跑。

如果失败原因需要维护者在游戏内手工调整外部环境，例如把 2P 换成大体型角色，载入最近
转录报告后可使用“仅重试转录失败项（N）”。它会创建独立候选目录和报告，只重放当前
报告中的失败源文件，并通过 `source_transcription_report` 保留来源；不会重跑或覆盖
已经通过的候选。

## 运行目录批量审计

录制菜单中的“审计当前角色全部连段”用于检查已经安装到运行目录的最终 JSON，不再生成
候选，也不会覆盖任何连段文件。

每个文件都会经过完整训练启动、场景恢复、稳定预滚，并按
`relative_raw_inputs` > `raw_inputs` > `timeline` 的顺序选择可重放输入自动演示。timeline-only
旧文件会直接走既有 timeline 播放器，不生成 raw 候选，也不修改源 JSON。输入结束后，审计器使用
同一个 Action 编译器核对实际 Action ID、动作数量、相邻动作时序、每步连击数与累计
伤害，以及整条连段的伤害、最大连击、格挡接触、斗气和 SA 消耗。raw/relative raw 使用
严格逐步核对；旧 timeline 的 Action 分组和逐步累计字段不是新编译器 schema，因此逐步
轨迹差异记录为 `advisories`，通过仍以玩家实际使用的训练 UI 完成、最终结果和指令显示为
边界。每条结束前还必须确认
训练 UI 已推进到序列末尾且没有失败状态。随后先清理训练环境，再加载下一条，因此也能
暴露首轮启动、指令表完成判定和跨文件状态污染。

运行审计还会调用与连段表绘制完全相同的逐步指令解析器。只要任一步在实际连段表中会
显示“指令未识别”（包括有真实 Action ID、且 raw input 能完整复演的步骤），该文件仍必须
审计失败；运行时 Action 与结果正确不能替代面向玩家的指令完整性。失败报告会保存
`command_display_validation.unresolved` 中的步骤序号、Action ID、原始 motion 与解析状态，
以便补齐严格指令表或有复演证据的角色 override 后重新审计。

运行审计 revision 37 还会核对整份指令验证载荷的结构不变量：角色与本轮角色一致、模式
有效、指令表状态为 `loaded`、声明与实际未解析数都为 0、步骤分类计数完整且与本次序列
长度一致。载入历史审计报告时不会再信任报告中持久化的成功/失败汇总，而会按当前规则
重算“有效通过 / 失败 / 待复审”；revision 32 或更早、或缺少完整验证上下文的旧成功项只进入
待复审队列，不会被“仅转录审计失败项”误选。

timeline 旧文件还可能同时记录“首段命中结果”和“连击归零后的压起身开放命中分支”。当
运行时明确观察到首段命中、真实连击重置，以及 `命中后防御` 环境下的后续格挡接触，并且
训练 UI、末段接触和指令显示均完成时，审计器会把该分段场景的累计伤害/最大连击差异记为
`advisories`。没有这组运行证据的连续连段仍严格核对最终伤害；斗气、SA、末段接触与训练
UI 完成状态始终严格。仅最大连击数变化、而伤害与接触结果完全一致的 timeline 旧文件也
只记录诊断，不要求为了计数器口径变化重新转录。

revision 36 相对 revision 35 只单调放宽上述两类 timeline 误报；revision 37 进一步把
旧录制中各步骤一致的 `expected_hp` 作为攻击方 HP 证据补入加载后的内存场景，不修改源
JSON。两次升级都没有撤销既有通过证据，因此载入 revision 35 或 36 报告时会保留原通过
项，并让“仅审计失败项”继续只选择原失败队列；revision 34 或更早的报告仍按过期处理。

报告写入：

```text
TrainingComboTrials_data/RuntimeAuditReports/<Character>_<timestamp>.json
```

报告会记录实际选择的 `input_source`，并使用通用 `replay_verified` 表示本次重放是否通过。
raw/relative raw 另保留 `raw_replay_verified`，timeline 则记录 `timeline_replay_verified`。
只有三种输入都不可用时才记录 `runtime_audit_input_stream_missing`。

## 失败分类

报告的 `reasons` 是直接观测到的失败，例如：

- `missing_input_stream`
- `transcribed_relative_raw_inputs_missing`
- `transcribed_raw_inputs_missing`
- `runtime_audit_input_stream_missing`
- `runtime_command_display_validation_missing`
- `runtime_command_display_validation_invalid:*`
- `runtime_command_display_unresolved:count=N`
- `no_action_steps`
- `unresolved_input_actions`
- `unresolved_action_motion`
- `motion_resolver_error`
- `damage_mismatch`
- `combo_count_mismatch`
- `block_contact_missing`
- `drive_consumption_mismatch`
- `super_consumption_mismatch`
- `replay_tail_timeout`
- `raw_replay_damage_mismatch`
- `raw_replay_combo_count_mismatch`
- `raw_replay_action_count_mismatch:*`
- `raw_replay_action_id_mismatch:*`
- `raw_replay_action_timing_mismatch:*`
- `raw_replay_step_combo_mismatch:*`
- `raw_replay_step_damage_mismatch:*`

`suspected_causes` 是从源 JSON 元数据推断出的环境线索，不会被当作 Action 事实：

- `first_hit_punish_counter`
- `actor_character_resource_required`
- `actor_low_health`
- `defender_burnout`
- `defender_virtual_damage`
- `defender_guard_state_change`

这样可以区分“底层没有观察到输入对应的 Action”和“输入本身依赖尚未完整恢复的训练
环境”，避免继续把个别文件的症状写成互相影响的角色兼容代码。
