# AC+BCM 统一动作语义核心

Status: CURRENT Architecture Contract / 已批准设计目标

本文档定义 SF6CC 中角色动作数据的唯一解释方式。它不是某个角色的修复记录，也不是临时兼容方案。

## 1. 三项基础工作

后续工作分为三条并行但有依赖关系的主线：

1. **主入口解耦**：`autorun/TrainingComboTrials_v1.0.lua` 只保留组合、生命周期、Hook 和模块间编排。录制、检测、显示、审计的新业务逻辑不得继续堆入入口文件。
2. **统一 AC+BCM 语义**：AC+BCM 生成一个角色动作图，录制、检测、显示、审计都只能从这个动作图查询语义，不得各自重新解释 Action ID 或指令。
3. **架构文档和 AI 约束**：架构原则、数据契约、迁移策略和禁止事项必须进入版本控制，并成为所有 AI 修改代码前后的检查依据。

这三项不能通过继续增加角色例外表来解决。

## 2. 数据源优先级

### 2.1 唯一权威

当前游戏版本的 AC+BCM 是动作关系和指令关系的唯一权威：

- AC 提供 Action 全集、BranchKey 关系、状态/阶段关系和动作之间的结构证据。
- BCM 提供实际输入入口、Classic/Simple/Motion profile、触发条件和资源条件。
- AC 与 BCM 必须按 fighter ID 和版本成对处理。

官网 OFF、人工出招表和历史运行时补丁不能决定 Action 绑定。它们最多提供名称、文本或人工核对信息。

两个直接 BCM Action 只有在生成目录同时证明经典指令定义一致、AC 核心结构一致、存在
精确且已审计的 AC 阶段边，并且运行时条件差异被严格限定时，才能属于同一运行时指令
阶段族。录制、检测、展示和审计共同消费该生成声明；显示文本相同本身永远不是身份依据。

### 2.2 Action ID 的地位

Action ID 是当前游戏版本内的技术标识，不是跨版本的招式主键，也不是最终语义主键。

稳定的业务实体是 `Move`。推荐的数据关系是：

```text
Move
├── BCM routes
├── input conditions
├── current Action bindings
├── AC owner / variant / internal phase roles
└── display projections
```

跨版本迁移必须离线比较新旧 AC+BCM，依据指令、BCM 条件和 AC 结构证据把旧 Combo JSON 改写为当前版本；运行时不保留永久的新旧 Action 映射表。

## 3. 统一生成物

生成器最终应输出一个角色动作图，暂定契约名：

```text
xt.character_move_graph.v1
```

它至少包含：

- 当前版本和 fighter ID；
- `moves`：稳定的 Move 实体；
- BCM route、输入形式、profile 和触发条件；
- Action binding 及其 `owner`、`variant`、`internal_phase` 角色；
- AC BranchKey 关系和证据；
- 可供 UI 使用的 Classic/Simple/Motion 显示投影；
- 生成诊断、未解析项和覆盖率统计。

生成器必须保留所有 BCM 路由。不能因为当前尚未能触发就提前丢弃；运行时 resolver 根据实际 Action、输入模式、按键和条件选择有效路线。

AC 派生的强度目标只有在 Classic/Modern 分支目标唯一、强度参数成对一致，且源 Action
存在唯一直接 BCM 输入路线时，才能继承该路线的方向与续招上下文。派生目标必须保留自己的
Action ID，不得与源 Action 建立等价组；生成物必须同时记录关系、路线和审计计数，运行时
消费者对任一字段缺失或不一致都必须拒绝加载该派生命令。

## 4. 运行时唯一入口

Lua 侧需要一个唯一的语义服务，暂定为 `MoveResolver`。四个消费者只能调用它：

```text
resolve_action(character, action_id, context)
resolve_input(character, input, context)
canonical_owner(character, action_id, context)
is_internal_phase(character, action_id, context)
matches(expected_move, observed_action, context)
get_command(move, mode, context)
```

### 4.1 录制

录制器负责采集原始 Action、输入和时间，不负责独立发明角色语义。动作合并、内部阶段和 Move 归属由 `MoveResolver` 提供。

### 4.2 检测

检测器比较 Move/route 语义和当前运行状态。它不能直接把 Action ID 当作跨版本招式身份，也不能绕过 resolver 使用角色专属 ID 分支。

### 4.3 显示

显示器只把 resolver 返回的 Move/route 投影成 Classic、Simple 或 Motion 文本。显示补丁不能改变录制和检测语义。

### 4.4 审计

审计器验证同一动作图下的录制、播放、输入、时间线、接触和完成结果。审计可以报告诊断级别差异，但不能用自己的动作分类覆盖 resolver。

## 5. 例外规则边界

例外只有在 AC+BCM 无法表达、且有明确运行时证据时才允许存在。

允许的例外示例：

- 引擎实际吸收了一个不会独立显示的内部阶段；
- 输入窗口、蓄力窗口或引擎过渡存在运行时事实差异；
- 同一 BCM route 在运行时需要上下文才能判定。

禁止的例外示例：

- 为弥补生成器漏识别而给 Action 填显示文本；
- 用角色专属 Lua `if action_id == ...` 代替 AC/BCM 关系；
- 用显示 override 修复检测失败；
- 用旧版本 Action 映射表永久支持旧 Combo JSON；
- 把官网 Action ID 当成游戏 Action ID。

例外记录必须是结构化、可审计、带证据的 curation 数据。不得直接修改原始 AC/BCM dump，也不得直接手写生成结果作为长期来源。

## 6. 主入口解耦规则

`TrainingComboTrials_v1.0.lua` 是 composition root，不是所有业务的容器。

允许保留在主入口的内容：

- `require` 和依赖装配；
- REFramework Hook 注册；
- 全局生命周期和场景回调；
- 将运行时上下文传递给模块；
- 少量兼容适配和启动/停止编排。

必须移出的内容：

- 角色动作语义；
- 录制事件编译；
- 连段动作匹配；
- 显示文本解析；
- 审计判定；
- 角色专属例外选择；
- 与动作语义无关的训练环境读写。

拆分采用渐进迁移：先搬运现有行为并建立 characterization tests，再替换数据来源，最后删除旧路径。不得在没有测试基线的情况下进行大规模重写。

## 7. 迁移顺序

```text
冻结当前行为基线
        ↓
生成 AC+BCM Move Graph
        ↓
实现 Lua MoveResolver
        ↓
录制器 shadow mode 对比
        ↓
检测器切换
        ↓
显示器切换
        ↓
审计器切换
        ↓
回流真实例外并删除补丁层
        ↓
拆分主入口剩余流程
```

在四个消费者都通过同一套基线后，才能删除 `CommandDisplayOverrides`、运行时 `ActionCompatibility` 以及不再需要的角色 Action ID 分支。

## 7.1 当前 Resolver 推进状态（2026-08-15）

`MoveResolver` 已作为 `CurrentMoveGraph` 已验证数据访问层之上的影子语义入口实现。
解析时优先使用已经审定的 `stable_move_uid`；在人审尚未完成时，只能把 build-local
`current_move_uid` 明确标记为 provisional identity。多值 membership、未解析 membership、
缺失 Action 与 artifact readiness 必须保持为不同结果，不得折叠成一次匹配。

`UnifiedActionConsumer` 已暴露 resolver 加载与结构化 shadow compare 入口，但比较结果始终
声明 `production_result = legacy`。当前没有任何 Runtime consumer 完成 authority switch；
`review_complete=false` 或 `integration_candidate=false` 的 artifact 只能用于诊断、corpus
比较与后续 shadow observation，不能成为 production authority。

Phase 2 将角色条件化的蓄力/长按行为收敛到 `ChargeRuntimePolicy`，主入口只负责调用。
Akuma Action 1231 等名称到指令序列的展开归 `MotionPresentation` 所有；该模块只能返回
显示文本，不能修改录制、检测、兼容或 MoveResolver identity。Presentation override 已由
Resolver 隔离测试证明不会改变语义解析结果。

## 7.2 连段起始前导规范化

Presentation、Detector 和 Auditor 必须从冻结 V2 序列生成同一份训练投影。只允许移除连段开头连续出现的以下步骤：单一基础方向 `1` 到 `9`、基础位移 `44`/`66`、Drive Parry。第一个不属于该集合的 Action 是首个可见、可检测检查点。

该投影不得改写冻结 V2 Action ID list、timeline 或 raw input；自动演示继续忠实消费原始回放载荷。首个真实语义动作之后的方向、`44`/`66` 和 Drive Parry 恢复严格语义。若序列全部由前导组成，加载和审计必须 fail closed，不得伪造完成。

## 8. 完成标准

架构迁移完成必须同时满足：

- 录制、检测、显示、审计使用同一 `MoveResolver`；
- 角色动作和指令主要来自 `xt.character_move_graph.v1`；
- 例外占比可统计，并且每条例外都有证据；
- 当前版本 Combo 可录制、播放、显示、审计一致；
- 旧版本迁移是离线数据升级，不是运行时永久兼容；
- 主入口只承担编排，不再增长动作业务逻辑；
- 生成器和运行时测试覆盖所有已审计角色；
- 删除补丁后，现有角色录制和播放行为不发生未解释回归。

