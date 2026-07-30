# 连段 Action 转录架构

## 事实边界

连段数据分成三层，优先级不可颠倒：

1. `raw_inputs` 或 `timeline`：玩家实际输入，是可重放的事实。
2. 游戏运行时 Action 事件：重放输入后，由游戏实际产生的 Action ID、命中、连击数和伤害。
3. V2 steps：为 SF6CC、WTT 和指令表 UI 生成的兼容产物。

指令表、角色例外和旧 V2 steps 只能用于显示或兼容读取，不能决定录制时“发生了哪个
Action”。V2 格式保持冻结，不增加 WTT 无法识别的新顶层结构。

## 新录制

`ActionEventCompiler.lua` 按帧观察：

- 物理输入的按键边沿、方向变化和双击方向；
- 游戏实际暴露的 Action ID 与 ActionFrame；
- 实际 HP、combo count 和格挡接触。

只有输入锚点与随后发生的运行时 Action 绑定后，才生成一个 V2 step。保存时继续输出
`id`、`motion`、`expected_combo`、`expected_hp`、`delay_from_prev` 和命中字段，因此
WTT 不需要修改。`motion` 优先由当前 Action 指令目录生成；目录缺项时退回输入记号。
无论哪种显示路径，都不能改写已经观察到的 Action ID。

每次 Action ID 变化或同 ID 的 ActionFrame 回卷也会原样进入转录报告的
`action_trace.observed_actions`，用于核对“游戏实际发生了什么”；没有对应新输入的内部
过渡只进入审计轨迹，不会伪造成玩家需要执行的 V2 step。

Action ID 对应的经典指令必须由已审计的角色指令表解析。解析器报错或 Action ID 没有
可靠指令时，批量转录会标记失败，不再静默接受根据单帧输入猜出的 motion。按键松开触发
的内部 Action 阶段会合并回原输入；快速出现的 Drive Parry 前置阶段会提升为实际
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
2. 每个文件先按 `raw_inputs`（优先）或 `timeline` 回放一次；
3. 旧 timeline 回放期间逐帧捕获实际注入游戏的输入，统一写成内嵌
   `raw_inputs`；已有 raw input 的文件原样保留该输入事实；
4. 输入结束后保留最多 360 帧结算窗口，等待末尾命中和 combo count 归零；
5. 用新编译器重新生成完整 V2 steps；
6. 原文件的 Action steps、伤害和最大连击只用于生成差异提示；它们是旧录制器的派生
   结果，不再阻止按输入事实重建候选。差异写入 `source_advisories`，不会被静默丢弃。
   未解析输入、未解析 motion、超时、资源消耗和必要格挡接触仍会中止本次候选；
7. 加载源文件后进入完整训练启动流程，应用该连段记录的位置、血量、斗气、SA、角色
   资源和防御设置；位置/资源重注入以及训练场刷新完成后，才开始稳定预滚倒计时；
8. 候选生成后再次恢复训练环境，并只使用刚生成的 `raw_inputs` 重放一遍；
9. 第二遍逐项核对实际 Action ID、动作数量、相邻动作时序、每一步连击数和累计伤害，
   同时再次核对整条连段的伤害、最大连击、格挡接触、斗气和 SA 消耗；
10. 两遍都通过才写候选文件，并在候选元数据及报告中写入
   `raw_replay_verified: true`；任一遍失败都只写报告。

V2 `scene_state` 是新文件的场景权威。只有旧 WTT 文件缺少对应 V2 值时，播放器才从
`snapshot_gauges` 补足生命、虚损、斗气和枯竭状态。候选文件若同时保留两种字段，会把
已有旧字段同步为 `scene_state` 的值，并在保留虚损差值的同时记录同步数量，避免 SF6CC
与 WTT 对同一 JSON 应用不同初始状态。

新版直接录制和转录候选都以内嵌 `raw_inputs` 作为首选回放事实。为兼容旧 WTTmod，
timeline 可以继续保留，但不会覆盖或反向推导 Action ID。

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

## 运行目录批量审计

录制菜单中的“审计当前角色全部连段”用于检查已经安装到运行目录的最终 JSON，不再生成
候选，也不会覆盖任何连段文件。

每个文件都会经过完整训练启动、场景恢复、稳定预滚和 `raw_inputs` 自动演示。输入结束
后，审计器使用同一个 Action 编译器核对实际 Action ID、动作数量、相邻动作时序、每步
连击数与累计伤害，以及整条连段的伤害、最大连击、格挡接触、斗气和 SA 消耗。每条结束
前还必须确认训练 UI 已推进到序列末尾且没有失败状态。随后先清理训练环境，再加载下一
条，因此也能暴露首轮启动、指令表完成判定和跨文件状态污染。

报告写入：

```text
TrainingComboTrials_data/RuntimeAuditReports/<Character>_<timestamp>.json
```

报告只接受内嵌 `raw_inputs`。如果安装目录仍混有只有 timeline 的旧文件，会明确记录
`runtime_audit_raw_inputs_missing`，而不是临时转录或猜测 Action。

## 失败分类

报告的 `reasons` 是直接观测到的失败，例如：

- `missing_input_stream`
- `transcribed_raw_inputs_missing`
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
