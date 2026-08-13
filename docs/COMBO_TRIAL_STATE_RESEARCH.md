# 连段训练场景状态调研

## 目标

连段文件目前主要描述“玩家输入了什么、何时输入、是否命中”。要做到录制与训练接近 1:1，还必须保存“录制开始时游戏处于什么状态”。

典型问题是不知火舞录制时有 3 个忍焰库存，而训练开始时游戏菜单只设置了 1 个。输入时间线虽然正确，后续强化必杀仍会因为资源不足而失败。

本调研基于：

- `autorun/TrainingComboTrials_v1.0.lua`
- `autorun/Training_ScriptManager.lua`
- `data/TrainingComboTrials_data/CustomCombos/*.json`
- `exam/SF6-Training-Mode-Plus`
- `exam/SF6-training-mod/.../SF6 Training Mode Plus`
- 上游 `Wael3rd/SF6_Tools` 的 `SF6_RecordingSlotManager.lua`
- 当前游戏可执行文件中可见的训练模式类型和方法名

## 结论摘要

1. 不知火舞忍焰可以稳定记录和恢复。字段是训练设置 `ParameterSetting.UniqueData.stock_0_028`，取值 0-5。
2. 斗气虚损可以稳定记录和恢复。必须同时保存精确斗气值和 `Is_DG_Break`，不能只把虚损表示成负数。
3. 游戏原生有 8 个录制槽，不是 10 个。每个槽可保存完整逐帧输入、帧数、启用状态和随机权重。
4. 倒地反攻、格挡反攻、受击反攻各有 10 个配置项。它们可引用普通技、必杀技、SA，也可通过 `Type=4 + SkillIndex=0..7` 引用上述 8 个录制槽。
5. 角色专属库存和安装技计时器适合写进可移植 JSON。飞行道具、分身、毒、炸弹附着、浮空和连段补正等战斗中间态不适合逐字段长期维护，应优先使用游戏原生 Save State。
6. 当前连段系统只保存斗气/SA“消耗量”，没有保存并恢复录制开始时的精确斗气、SA 和角色专属资源。这正是不知火舞案例失败的根因。

## 当前连段 JSON 已保存的数据

### 文件级

- `_xt_meta`：角色、标题、作者、备注、标签、版本、更新时间
- `combo_stats.damage`：总伤害
- `combo_stats.drive_used`：攻击方斗气最低值相对起始值的消耗
- `combo_stats.super_used`：攻击方 SA 最低值相对起始值的消耗
- `combo_stats.hit_type`：存在代码支持，但当前样本未必都有
- `timeline`：逐帧方向和按键输入
- `raw_input_file`：旧格式外部输入文件兼容字段

### 起始场景

- `recorded_by`：录制方 P1/P2
- `start_pos_p1`、`start_pos_p2`：位置换算值
- `start_pos_p1_raw`、`start_pos_p2_raw`：原始定点数 X 坐标
- `facing_left`：每一步朝向
- `counter_type`：0 普通、1 Counter、2 Punish Counter
- `has_piyo`、`piyo_frame`：是否在录制过程中出现晕厥及发生帧

### 每一步

- `id`：Action ID
- `motion`、`motion_aliases`：显示指令和兼容指令
- `delay_from_prev`：与前一步间隔
- `hold_frames`、`charge_min`、`charge_max`
- `is_holdable`、`dual_threshold`、`hold_partial_check`
- `expected_combo`、`actual_combo`
- `expected_hp`、`damage_at_step`
- `has_hit`、`is_projectile_hit`
- `group_id`、`next_auto_id`

`actual_combo` 和部分 `has_hit` 是运行时字段，加载后会被重置，不属于真正的初始场景。

## 当前缺失但可稳定加入 JSON 的数据

以下数据来自训练模式持久设置，适合跨重置、跨会话和跨机器分享。建议保存在首步的 `scene_state` 中。

### 1. 双方身份与操作方式

- P1/P2 角色 ID
- 经典/现代操作类型
- 录制方、受击方
- 初始左右关系和朝向
- 起始位置类型：中央、左角、右角、自定义
- P1/P2 精确 X 坐标
- 建议附带舞台 ID，但只把它用于边界兼容检查，不强制切换舞台

角色和操作类型不匹配时应拒绝开始，而不是静默播放。

### 2. 体力与可回复体力

训练设置可恢复：

- `Vital_Type`
- `Vital_Point`
- `Is_Vital_Infinity`
- `Is_Vital_No_Recovery`
- `Is_Vital_Recovery_Timer`
- `Is_KO`
- `Is_Point_Lock`

运行时还可读取：

- `vital_new`：当前有效体力
- `vital_old`
- `heal_new`：包含灰血的可回复上限
- `vital_max`

为了复现灰血场景，不能只保存 `Vital_Point` 百分比，还应保存 `vital_new` 与 `heal_new`。运行时由场景状态模块统一设置训练体力、关闭自动回血并触发一次刷新；刷新后只允许一次有界的精确值校正，随后释放体力写入权。不得逐帧与游戏争抢体力，否则会造成黄血与满血闪烁。

### 3. 斗气与虚损

已确认可修改：

- `DG_Type`
- `DG_Stock`
- `DG_Point`
- `Is_DG_Point_Lock`
- `Is_DG_Break`

游戏还暴露了与恢复相关的字段/方法：

- `Is_DG_Recovery_Timer`
- `DG_Timer`
- `SetDGRecoveryTime`
- `SetDGTimeRecovery`

最低可用方案：

```json
{
  "drive": {
    "point": 12500,
    "stock": 1,
    "burnout": true
  }
}
```

`burnout=true` 才表示虚损。低斗气但非虚损与虚损中剩余恢复量是两个不同状态。若要严格复现“还需多久恢复”，还要增加恢复计时器探测；仅记录 `Is_DG_Break` 已足以复现晕连成立条件。

### 4. SA 槽

- `SA_Type`
- `SA_Stock`
- `SA_Point`
- `Is_SA_Point_Lock`
- `Is_SA_No_Recovery`
- `Is_SA_Recovery_Timer`
- `SA_Timer`

当前连段文件只有 `super_used`，这不能替代起始 `SA_Point`。

### 5. 角色专属资源

参考库通过 `ParameterSetting.UniqueData` 修改这些资源。

| 角色 | 字段 | 可记录内容 |
|---|---|---|
| 隆 | `timer_0_001` | 电刃蓄力：标准/发动/无限 |
| 杰米 | `stock_0_021` | 醉酒等级 0-4 |
| 杰米 | `timer_0_021` | 魔身安装状态及剩余时间 |
| 金伯莉 | `stock_0_003` | 手里剑炸弹库存 |
| 莉莉 | `stock_0_012` | 风缠库存 0-3 |
| 蛛俐 | `stock_0_016` | 风破库存 0-3 |
| 蛛俐 | `timer_0_016` | 风水引擎及剩余时间 |
| 本田 | `stock_0_020` | 相扑魂 |
| 布兰卡 | `stock_0_015` | 小布兰卡炸弹库存 |
| 布兰卡 | `timer_0_015` | 雷兽及剩余时间 |
| 古烈 | `timer_0_018` | Solid Puncher 及剩余时间 |
| 不知火舞 | `stock_0_028` | 忍焰/火焰库存 0-5 |
| C.毒蛇 | `timer_0_030` | 限制解除及剩余时间 |
| 英格丽德 | `stock_0_032` | 太阳纹章 0-4 |
| 玛侬 | `stock_0_005` | 奖牌内部值 0-4，对应显示 1-5 |

库存值 `7` 在参考库中表示“无限”。分享连段时应保存录制时的实际有限值，不建议默认写 7。

安装技需要保存两层：

- `UniqueData.timer_*`：关闭、发动、无限
- 角色运行时 `style_timer`：发动后的剩余帧数

其他未列出的角色不代表绝对没有运行时资源，只表示当前训练设置和参考库没有提供稳定、通用的可写入口。

### 6. 防守与命中环境

已由当前项目实际写入：

- `GuardSetting.DummyData.GuardType`
- `CounterSetting.DummyData.NC_TYPE`
- `CounterSetting.DummyData.PC_TYPE`

建议保存：

- 防御类型：不防、第一击后防御、全防、随机防御等
- 普通命中/打康/确反康
- 受身/起身类型
- 假人姿态：站立、蹲下、跳跃等

连段训练通常应继续强制“第一击后防御”，但 JSON 应记录原始命中要求，并把训练系统强制值与录制场景值分开。

### 7. 游戏速度和恢复规则

参考库已确认可以修改：

- `OtherSetting.Is_Speed_Setting`
- `OtherSetting.OS_Game_Speed`
- `tf_OtherSetting.ApplyGameSpeed()`

游戏速度会直接改变人工复现的体感和基于真实帧计数的脚本逻辑，建议记录并在训练开始时校验。若连段系统始终只支持 100%，则应明确拒绝其他速度录制。

受身/起身规则、假人站立/蹲下/跳跃状态来自 `tf_DummyStatus`、`ERecoveryType`、`TM_DS_DUMMYTYPE`、`TM_DS_JUMPTYPE`。这些属于可移植训练设置，但精确字段仍应通过运行时反射固定后再加入 schema。

显示设置、帧数表、伤害信息显示和快捷键不会改变战斗结果，不应塞进连段场景 JSON。

## 录制槽和三类反攻

### 普通录制槽

上游 `SF6_RecordingSlotManager.lua` 已验证访问路径：

`TrainingManager.get_RecordFunc()._tData.RecordSetting.FighterDataList[角色ID].RecordSlots`

游戏当前有 8 个槽。每槽可稳定导出：

- `id`：1-8
- `name`：MOD 自定义名称
- `timeline`：逐帧方向和按键
- `Frame`：总帧数
- `Weight`：随机播放权重
- `IsValid`
- `IsActive`
- `InputData.Num`
- `InputData.buff[]`：每帧的 16 位输入掩码

这意味着连段 JSON 可以附带一组录制槽快照，训练开始时自动导入。它们既可用于普通随机播放，也可被反攻设置引用。

### 倒地、格挡、受击反攻

游戏原生存在：

- `tf_ReversalSetting`
- `DownReversalDatas`
- `GuardReversalDatas`
- `DamageReversalDatas`
- `UpdateDownReversal`
- `UpdateGuardReversal`
- `UpdateDamageReversal`
- `SetReversalData`
- `SetReversalActive`
- `SetAllReversalActive`
- `SetReversalDelayFrame`
- `SetReversalCount`
- `SetReversalMeatyFrame`

每一类有 10 个反攻项目。项目可以是：

- 普通技
- 指令普通技
- 必杀技
- SA
- 录制动作

上游代码确认当反攻项目 `Type == 4` 时，`SkillIndex` 为 0-7，对应 8 个普通录制槽。

因此答案是：三类反攻都可以记录进连段场景 JSON。完整快照至少需要：

```json
{
  "reversal": {
    "type": "down",
    "items": [
      {
        "index": 0,
        "type": 4,
        "skill_index": 2,
        "active": true,
        "delay_frame": 0,
        "count": 1,
        "meaty_frame": 0
      }
    ]
  }
}
```

精确字段布局仍应以运行时反射结果为准，但能力和数据入口已经确认。

## 可记录但不建议直接逐字段恢复的运行时状态

这些数据能从 `gBattle.Player`、`gBattle.Team` 或动作引擎读取，但直接写入容易导致不同游戏版本、不同角色或不同动作资源之间不一致。

- 当前 Action ID、Action Frame、动作状态标志
- 站立、蹲下、空中、倒地、起身、受击、格挡状态
- X/Y/Z 坐标、速度、加速度、跳跃轨迹
- 朝向、转身中状态
- hit stop、block stun、hit stun
- combo count、连段补正、伤害补正
- 浮空次数、追击限制、受身状态
- 晕厥值、晕厥恢复进度、Piyo 状态
- 精确虚损恢复计时器
- 蓄力计时、指令缓存、负边输入
- 场上飞行道具、布兰卡玩偶、JP 门、拉希德旋风等实体
- A.K.I. 毒、拜森炸弹等附着状态
- 角色安装技内部子状态和视觉/音效状态
- 世界停止、SA 演出、镜头和屏幕边界状态

若连段必须从这些状态中间开始，推荐保存游戏原生 Save State，而不是维护一张不断变化的字段表。

## 原生 Save State 的定位

项目已经 hook：

- `TrainingManager.requestSaveState`
- `TrainingManager.SaveKeyData`
- `TrainingManager.requestLoadState`

参考库还指出加载入口：

- `app.training.tf_OtherSettings.Load_SnapShot(LocalSnapShot)`

原生 Save State 最接近真正的 1:1，因为它可以覆盖角色动作、场上对象、补正、浮空和计时器等运行时状态。

限制：

- 当前项目只同步了 MOD 自己的连段步骤，没有把游戏快照序列化进连段 JSON。
- `LocalSnapShot` 很可能含托管对象和版本相关结构，不能直接假设可跨版本、跨角色、跨机器。
- 应先实现“当前会话绑定的快照”，再研究可移植二进制或逐字段导出。

## 建议 JSON 结构

保持现有步骤数组兼容，在第一步增加：

```json
{
  "scene_state": {
    "schema": "xt.combo_trial.scene.v1",
    "capture_mode": "portable",
    "players": {
      "p1": {
        "fighter_id": 28,
        "control_type": 0,
        "health": {
          "vital": 10000,
          "recoverable": 10000
        },
        "drive": {
          "point": 60000,
          "stock": 6,
          "burnout": false
        },
        "super": {
          "point": 0,
          "stock": 0
        },
        "unique": {
          "stock_0_028": 3
        }
      },
      "p2": {}
    },
    "position": {
      "p1_x_raw": -45547520,
      "p2_x_raw": -50135040,
      "facing_left": true
    },
    "dummy": {
      "guard_type": 2,
      "counter_type": 0,
      "recovery_type": 0
    },
    "recording_slots": [],
    "reversal": {
      "down": [],
      "guard": [],
      "damage": []
    }
  }
}
```

不要把角色资源放在 `combo_stats`。`combo_stats` 是结果统计，`scene_state` 才是开始前必须恢复的条件。

## 应用顺序

1. 校验角色、操作类型和 JSON schema。
2. 备份玩家当前训练设置。
3. 写入体力、斗气、虚损、SA、角色专属资源。
4. 写入防御、Counter、受身、录制槽和反攻配置。
5. 设置训练菜单位置并请求一次 Refresh。
6. 等待 `stage_timer == 1` 或 `_IsReqRefresh == false`。
7. 注入精确位置、灰血、安装技剩余计时器等运行时值。
8. 清空输入缓存，等待若干中立帧。
9. 才开始连段验证或自动演示。
10. 退出连段训练时恢复步骤 2 的备份。

若顺序反过来，Refresh 会覆盖已经注入的角色库存和运行时数值。

## 实施优先级

### P0：解决当前真实失败

- `scene_state.players.*.drive`
- `scene_state.players.*.super`
- `scene_state.players.*.unique`
- 不知火舞 `stock_0_028`
- 双方精确体力和位置
- 开始训练与每次重置时重新应用

### P1：完整训练环境

- 虚损状态
- 灰血
- 防御、Counter、受身、假人姿态
- 8 个录制槽导入/导出
- 三类反攻配置

### P2：严格 1:1

- 安装技剩余时间
- 虚损恢复计时器
- 晕厥值与恢复进度
- 原生 Save State 绑定
- 场上对象和连段中间态

## 不能做出的保证

- 仅凭逐帧输入无法复现所有场景；资源和战斗状态是独立输入条件。
- 直接写 Action ID/Action Frame 不能替代 Save State。
- 角色专属字段可能随游戏更新变化，必须带 schema 和游戏版本校验。
- 原生 Save State 是否可安全跨会话导出，目前没有证据，应视为待验证。

## 证据索引

- 当前连段录制与恢复：`autorun/TrainingComboTrials_v1.0.lua`
- 当前守防、Counter 与位置控制：`autorun/TrainingComboTrials_v1.0.lua`、`autorun/Training_ScriptManager.lua`
- 角色专属库存和计时器：`exam/SF6-training-mod/.../UniqueCharacterParametersData.lua`
- 体力、斗气、虚损、SA、位置写入：`exam/SF6-training-mod/.../TrainingSettingsAndRandomizer.lua`
- 灰血、精确斗气、SA、安装技计时器读取：`exam/SF6-training-mod/.../CharacterInfoDisplay.lua`
- Save State 入口注释：`exam/SF6-Training-Mode-Plus/.../SaveStateRandomizer.lua`
- 8 个录制槽及 JSON 导入/导出：上游 [SF6_RecordingSlotManager.lua](https://github.com/Wael3rd/SF6_Tools/blob/8efc7dd7376834b065b2a1e331af60d7be003928/reframework/autorun/SF6_RecordingSlotManager.lua)
- 上游调研版本：`8efc7dd7376834b065b2a1e331af60d7be003928`，2026-06-14
- 三类反攻数组和录制槽引用：同一上游文件的 `_rsm_detect_overlays`
- 游戏类型/方法名：当前 `StreetFighter6.exe` 中的 `tf_RecordSetting`、`tf_ReversalSetting`、`Update*Reversal`、`SetReversal*`
