// Generated from rule_config.lua; run build_rule_editor.mjs.
globalThis.CFN_RULE_CATALOG = {
  "build": 20004000,
  "builtins": [
    [
      "guard_damage",
      "防住了，但仍然掉血"
    ],
    [
      "parry_caught",
      "蓝防后受伤（类型待确认）"
    ],
    [
      "attack_caught",
      "出招后受伤（类型待确认）"
    ],
    [
      "caught",
      "受伤类型待确认"
    ],
    [
      "wakeup_hit",
      "起身时被压中"
    ],
    [
      "wakeup_button_counter",
      "起身后抢招被打断"
    ],
    [
      "whiff_punish_candidate",
      "出招落空后被惩罚"
    ],
    [
      "attack_punished",
      "出招过程中被确反康"
    ],
    [
      "air_attack_counter",
      "空中出招被打断"
    ],
    [
      "air_ground_counter",
      "空中出招时被地面对手打中"
    ],
    [
      "guard_button_counter",
      "防御后抢招被打断"
    ],
    [
      "attack_counter",
      "出招被对手抢先打断"
    ],
    [
      "guard_reaction_followup",
      "防御后陷入受击状态，被继续追击"
    ],
    [
      "reaction_followup",
      "受击过程中继续掉血"
    ],
    [
      "side_change_air_hit",
      "换边时没有挡住空中进攻"
    ],
    [
      "guard_not_held",
      "防御后没有继续维持后方向"
    ],
    [
      "crouch_guard_air_hit",
      "蹲防没有挡住后续空中进攻"
    ],
    [
      "guard_broken",
      "防御转入受击"
    ],
    [
      "dash_intercepted",
      "冲刺途中被截停"
    ],
    [
      "forward_walk_hit",
      "前走时被打中"
    ],
    [
      "movement_hit",
      "移动时被打中"
    ],
    [
      "air_hit",
      "空中被打中"
    ],
    [
      "unresolved",
      "掉血来源或原因未确定"
    ]
  ],
  "capture_schema": "sf6cc.cfn-state-capture.experimental.v1",
  "columns": [
    "round",
    "replay_frame",
    "battle_round",
    "stage_frame",
    "render_tick",
    "thread_id",
    "update_result",
    "fight_st",
    "play_timer",
    "play_timer_ms",
    "display_prev_frame",
    "display_stun_frame",
    "display_attack_side",
    "meter_frame",
    "meter_start_frame",
    "meter_stop_frame",
    "meter_active",
    "p1.vital_new",
    "p1.vital_old",
    "p1.vital_max",
    "p1.heal_new",
    "p1.focus_new",
    "p1.focus_max",
    "p1.mSuperGauge",
    "p1.mSuperGaugeMax",
    "p1.mSingleDamage",
    "p1.mComboDamage",
    "p1.mComboCount",
    "p1.action_id",
    "p1.action_frame_raw",
    "p1.x_raw",
    "p1.y_raw",
    "p1.z_raw",
    "p1.facing_right",
    "p1.act_st",
    "p1.hit_st",
    "p1.hit_st_old",
    "p1.hit_stop",
    "p1.damage_type",
    "p1.damage_source",
    "p1.combo_cnt",
    "p1.pl_input_new",
    "p1.pl_sw_new",
    "p1.display_current_frame",
    "p1.display_prev_action_frame",
    "p1.display_atk_margin",
    "p1.display_hit_id",
    "p1.guard_time",
    "p1.damage_time",
    "p1.pose_st",
    "p1.free_to_move",
    "p1.engine_action_id",
    "p1.engine_action_frame_raw",
    "p1.engine_frame_num_raw",
    "p1.engine_margin_start_raw",
    "p1.engine_speed_raw",
    "p1.engine_state_flags",
    "p1.engine_battle_version",
    "p1.engine_loop_count",
    "p1.engine_style_index",
    "p1.display_meter_size",
    "p1.display_meter_index",
    "p1.display_meter_type",
    "p1.display_meter_empty",
    "p1.display_meter_changed",
    "p1.display_meter_end",
    "p1.display_meter_not_add",
    "p1.display_meter_not_whole",
    "p2.vital_new",
    "p2.vital_old",
    "p2.vital_max",
    "p2.heal_new",
    "p2.focus_new",
    "p2.focus_max",
    "p2.mSuperGauge",
    "p2.mSuperGaugeMax",
    "p2.mSingleDamage",
    "p2.mComboDamage",
    "p2.mComboCount",
    "p2.action_id",
    "p2.action_frame_raw",
    "p2.x_raw",
    "p2.y_raw",
    "p2.z_raw",
    "p2.facing_right",
    "p2.act_st",
    "p2.hit_st",
    "p2.hit_st_old",
    "p2.hit_stop",
    "p2.damage_type",
    "p2.damage_source",
    "p2.combo_cnt",
    "p2.pl_input_new",
    "p2.pl_sw_new",
    "p2.display_current_frame",
    "p2.display_prev_action_frame",
    "p2.display_atk_margin",
    "p2.display_hit_id",
    "p2.guard_time",
    "p2.damage_time",
    "p2.pose_st",
    "p2.free_to_move",
    "p2.engine_action_id",
    "p2.engine_action_frame_raw",
    "p2.engine_frame_num_raw",
    "p2.engine_margin_start_raw",
    "p2.engine_speed_raw",
    "p2.engine_state_flags",
    "p2.engine_battle_version",
    "p2.engine_loop_count",
    "p2.engine_style_index",
    "p2.display_meter_size",
    "p2.display_meter_index",
    "p2.display_meter_type",
    "p2.display_meter_empty",
    "p2.display_meter_changed",
    "p2.display_meter_end",
    "p2.display_meter_not_add",
    "p2.display_meter_not_whole"
  ],
  "defaults": {
    "build": 20004000,
    "include_system": true,
    "name": "我的录像规则",
    "rules": [],
    "schema": "sf6cc.replay-rules.v1",
    "settings": {
      "advantage_min": 4,
      "guard_frames": 15,
      "response_frames": 30,
      "wakeup_frames": 8
    }
  },
  "fields": [
    {
      "group": "事件",
      "key": "base_rule",
      "label": "系统原分类",
      "options": [
        [
          "guard_damage",
          "防住了，但仍然掉血"
        ],
        [
          "parry_caught",
          "蓝防后受伤（类型待确认）"
        ],
        [
          "attack_caught",
          "出招后受伤（类型待确认）"
        ],
        [
          "caught",
          "受伤类型待确认"
        ],
        [
          "wakeup_hit",
          "起身时被压中"
        ],
        [
          "wakeup_button_counter",
          "起身后抢招被打断"
        ],
        [
          "whiff_punish_candidate",
          "出招落空后被惩罚"
        ],
        [
          "attack_punished",
          "出招过程中被确反康"
        ],
        [
          "air_attack_counter",
          "空中出招被打断"
        ],
        [
          "air_ground_counter",
          "空中出招时被地面对手打中"
        ],
        [
          "guard_button_counter",
          "防御后抢招被打断"
        ],
        [
          "attack_counter",
          "出招被对手抢先打断"
        ],
        [
          "guard_reaction_followup",
          "防御后陷入受击状态，被继续追击"
        ],
        [
          "reaction_followup",
          "受击过程中继续掉血"
        ],
        [
          "side_change_air_hit",
          "换边时没有挡住空中进攻"
        ],
        [
          "guard_not_held",
          "防御后没有继续维持后方向"
        ],
        [
          "crouch_guard_air_hit",
          "蹲防没有挡住后续空中进攻"
        ],
        [
          "guard_broken",
          "防御转入受击"
        ],
        [
          "dash_intercepted",
          "冲刺途中被截停"
        ],
        [
          "forward_walk_hit",
          "前走时被打中"
        ],
        [
          "movement_hit",
          "移动时被打中"
        ],
        [
          "air_hit",
          "空中被打中"
        ],
        [
          "unresolved",
          "掉血来源或原因未确定"
        ]
      ],
      "type": "enum"
    },
    {
      "group": "事件",
      "key": "kind",
      "label": "记录类型",
      "options": [
        [
          "damage",
          "受伤段"
        ],
        [
          "guard",
          "防御段"
        ]
      ],
      "type": "enum"
    },
    {
      "group": "事件",
      "key": "frame",
      "label": "发生帧",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "round",
      "label": "第几局（从1开始）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "side",
      "label": "分析对象（1P或2P）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "damage",
      "label": "本段实际掉血",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "duration",
      "label": "本段长度（帧）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "guard_elapsed",
      "label": "距离防御结束（帧）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "wakeup_elapsed",
      "label": "距离最近起身（帧）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "response_delay",
      "label": "防御结束到出招间隔（帧）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "native_advantage",
      "label": "已关联硬直差（正负归属未确认）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "native_abs",
      "label": "已关联硬直差绝对值",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "window_frames",
      "label": "计测表收招窗口（帧）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "distance",
      "label": "双方横向间距（游戏单位）",
      "type": "number"
    },
    {
      "group": "事件",
      "key": "counter",
      "label": "新出现普通康",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "punish",
      "label": "新出现确反康",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "guard_flag",
      "label": "新出现防御标记",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "facing_changed",
      "label": "本帧换边",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "previous_attack",
      "label": "掉血前正在出招",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "previous_guard",
      "label": "掉血前正在防御",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "attack_start_observed",
      "label": "看到了本次出招起点",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "active_seen",
      "label": "看到了攻击判定",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "contact_seen",
      "label": "观察到本次出招接触对手",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "reaction_preceded_by_guard",
      "label": "受击状态之前是防御",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "guard_complete",
      "label": "防御段起止完整",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "response_observed",
      "label": "观察到防御后出招",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "window_complete",
      "label": "收招窗口完整结束",
      "type": "boolean"
    },
    {
      "group": "事件",
      "key": "source_opponent",
      "label": "伤害来源确认为对手",
      "type": "boolean"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.vital_new",
      "label": "血量",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.vital_old",
      "label": "上次血量",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.vital_max",
      "label": "血量上限",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.heal_new",
      "label": "可恢复血量原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.focus_new",
      "label": "斗气原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.focus_max",
      "label": "斗气上限",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.mSuperGauge",
      "label": "能量原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.mSuperGaugeMax",
      "label": "能量上限",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.mSingleDamage",
      "label": "游戏单次伤害",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.mComboDamage",
      "label": "游戏连段伤害",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.mComboCount",
      "label": "游戏连击计数",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.action_id",
      "label": "动作编号",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.action_frame_raw",
      "label": "动作进度原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.x_raw",
      "label": "横向位置原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.y_raw",
      "label": "高度原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.z_raw",
      "label": "纵向位置原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.facing_right",
      "label": "朝向原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.act_st",
      "label": "行动状态编号",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.hit_st",
      "label": "受击标记原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.hit_st_old",
      "label": "上次受击标记",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.hit_stop",
      "label": "停顿剩余",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.damage_type",
      "label": "伤害类型原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.damage_source",
      "label": "伤害来源玩家",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.combo_cnt",
      "label": "另一连击计数",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.pl_input_new",
      "label": "方向与按键原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.pl_sw_new",
      "label": "新按键原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_current_frame",
      "label": "显示当前帧",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_prev_action_frame",
      "label": "显示动作帧",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_atk_margin",
      "label": "显示动作余量",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_hit_id",
      "label": "显示命中编号",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.guard_time",
      "label": "防御剩余",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.damage_time",
      "label": "受击剩余",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.pose_st",
      "label": "姿态编号",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.free_to_move",
      "label": "行动许可原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_action_id",
      "label": "引擎动作编号",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_action_frame_raw",
      "label": "引擎动作进度原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_frame_num_raw",
      "label": "引擎动作长度原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_margin_start_raw",
      "label": "引擎余量起点原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_speed_raw",
      "label": "引擎速度原值",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_state_flags",
      "label": "引擎状态标记",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_battle_version",
      "label": "战斗版本",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_loop_count",
      "label": "动作循环次数",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.engine_style_index",
      "label": "动作形态编号",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_size",
      "label": "计测表大小",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_index",
      "label": "计测表位置",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_type",
      "label": "计测格类型",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_empty",
      "label": "计测格为空",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_changed",
      "label": "计测格变化",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_end",
      "label": "计测格结束",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_not_add",
      "label": "计测格未新增",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.display_meter_not_whole",
      "label": "计测格不完整",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.health_pct",
      "label": "血量百分比",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.drive_pct",
      "label": "斗气百分比",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.super_pct",
      "label": "能量百分比",
      "type": "number"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.back",
      "label": "输入后方向",
      "type": "boolean"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.forward",
      "label": "输入前方向",
      "type": "boolean"
    },
    {
      "group": "分析对象·发生帧",
      "key": "self.current.down",
      "label": "输入下方向",
      "type": "boolean"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.vital_new",
      "label": "血量",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.vital_old",
      "label": "上次血量",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.vital_max",
      "label": "血量上限",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.heal_new",
      "label": "可恢复血量原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.focus_new",
      "label": "斗气原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.focus_max",
      "label": "斗气上限",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.mSuperGauge",
      "label": "能量原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.mSuperGaugeMax",
      "label": "能量上限",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.mSingleDamage",
      "label": "游戏单次伤害",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.mComboDamage",
      "label": "游戏连段伤害",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.mComboCount",
      "label": "游戏连击计数",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.action_id",
      "label": "动作编号",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.action_frame_raw",
      "label": "动作进度原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.x_raw",
      "label": "横向位置原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.y_raw",
      "label": "高度原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.z_raw",
      "label": "纵向位置原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.facing_right",
      "label": "朝向原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.act_st",
      "label": "行动状态编号",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.hit_st",
      "label": "受击标记原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.hit_st_old",
      "label": "上次受击标记",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.hit_stop",
      "label": "停顿剩余",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.damage_type",
      "label": "伤害类型原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.damage_source",
      "label": "伤害来源玩家",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.combo_cnt",
      "label": "另一连击计数",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.pl_input_new",
      "label": "方向与按键原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.pl_sw_new",
      "label": "新按键原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_current_frame",
      "label": "显示当前帧",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_prev_action_frame",
      "label": "显示动作帧",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_atk_margin",
      "label": "显示动作余量",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_hit_id",
      "label": "显示命中编号",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.guard_time",
      "label": "防御剩余",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.damage_time",
      "label": "受击剩余",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.pose_st",
      "label": "姿态编号",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.free_to_move",
      "label": "行动许可原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_action_id",
      "label": "引擎动作编号",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_action_frame_raw",
      "label": "引擎动作进度原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_frame_num_raw",
      "label": "引擎动作长度原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_margin_start_raw",
      "label": "引擎余量起点原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_speed_raw",
      "label": "引擎速度原值",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_state_flags",
      "label": "引擎状态标记",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_battle_version",
      "label": "战斗版本",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_loop_count",
      "label": "动作循环次数",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.engine_style_index",
      "label": "动作形态编号",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_size",
      "label": "计测表大小",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_index",
      "label": "计测表位置",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_type",
      "label": "计测格类型",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_empty",
      "label": "计测格为空",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_changed",
      "label": "计测格变化",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_end",
      "label": "计测格结束",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_not_add",
      "label": "计测格未新增",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.display_meter_not_whole",
      "label": "计测格不完整",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.health_pct",
      "label": "血量百分比",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.drive_pct",
      "label": "斗气百分比",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.super_pct",
      "label": "能量百分比",
      "type": "number"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.back",
      "label": "输入后方向",
      "type": "boolean"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.forward",
      "label": "输入前方向",
      "type": "boolean"
    },
    {
      "group": "分析对象·前一帧",
      "key": "self.previous.down",
      "label": "输入下方向",
      "type": "boolean"
    },
    {
      "group": "玩家",
      "key": "self.fighter_id",
      "label": "分析对象角色编号（当前版本）",
      "type": "number"
    },
    {
      "group": "玩家",
      "key": "self.control_mode",
      "label": "分析对象操作模式",
      "options": [
        [
          0,
          "经典"
        ],
        [
          1,
          "现代"
        ]
      ],
      "type": "enum"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.vital_new",
      "label": "血量",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.vital_old",
      "label": "上次血量",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.vital_max",
      "label": "血量上限",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.heal_new",
      "label": "可恢复血量原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.focus_new",
      "label": "斗气原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.focus_max",
      "label": "斗气上限",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.mSuperGauge",
      "label": "能量原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.mSuperGaugeMax",
      "label": "能量上限",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.mSingleDamage",
      "label": "游戏单次伤害",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.mComboDamage",
      "label": "游戏连段伤害",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.mComboCount",
      "label": "游戏连击计数",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.action_id",
      "label": "动作编号",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.action_frame_raw",
      "label": "动作进度原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.x_raw",
      "label": "横向位置原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.y_raw",
      "label": "高度原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.z_raw",
      "label": "纵向位置原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.facing_right",
      "label": "朝向原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.act_st",
      "label": "行动状态编号",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.hit_st",
      "label": "受击标记原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.hit_st_old",
      "label": "上次受击标记",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.hit_stop",
      "label": "停顿剩余",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.damage_type",
      "label": "伤害类型原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.damage_source",
      "label": "伤害来源玩家",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.combo_cnt",
      "label": "另一连击计数",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.pl_input_new",
      "label": "方向与按键原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.pl_sw_new",
      "label": "新按键原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_current_frame",
      "label": "显示当前帧",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_prev_action_frame",
      "label": "显示动作帧",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_atk_margin",
      "label": "显示动作余量",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_hit_id",
      "label": "显示命中编号",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.guard_time",
      "label": "防御剩余",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.damage_time",
      "label": "受击剩余",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.pose_st",
      "label": "姿态编号",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.free_to_move",
      "label": "行动许可原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_action_id",
      "label": "引擎动作编号",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_action_frame_raw",
      "label": "引擎动作进度原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_frame_num_raw",
      "label": "引擎动作长度原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_margin_start_raw",
      "label": "引擎余量起点原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_speed_raw",
      "label": "引擎速度原值",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_state_flags",
      "label": "引擎状态标记",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_battle_version",
      "label": "战斗版本",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_loop_count",
      "label": "动作循环次数",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.engine_style_index",
      "label": "动作形态编号",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_size",
      "label": "计测表大小",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_index",
      "label": "计测表位置",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_type",
      "label": "计测格类型",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_empty",
      "label": "计测格为空",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_changed",
      "label": "计测格变化",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_end",
      "label": "计测格结束",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_not_add",
      "label": "计测格未新增",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.display_meter_not_whole",
      "label": "计测格不完整",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.health_pct",
      "label": "血量百分比",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.drive_pct",
      "label": "斗气百分比",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.super_pct",
      "label": "能量百分比",
      "type": "number"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.back",
      "label": "输入后方向",
      "type": "boolean"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.forward",
      "label": "输入前方向",
      "type": "boolean"
    },
    {
      "group": "对手·发生帧",
      "key": "other.current.down",
      "label": "输入下方向",
      "type": "boolean"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.vital_new",
      "label": "血量",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.vital_old",
      "label": "上次血量",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.vital_max",
      "label": "血量上限",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.heal_new",
      "label": "可恢复血量原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.focus_new",
      "label": "斗气原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.focus_max",
      "label": "斗气上限",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.mSuperGauge",
      "label": "能量原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.mSuperGaugeMax",
      "label": "能量上限",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.mSingleDamage",
      "label": "游戏单次伤害",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.mComboDamage",
      "label": "游戏连段伤害",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.mComboCount",
      "label": "游戏连击计数",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.action_id",
      "label": "动作编号",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.action_frame_raw",
      "label": "动作进度原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.x_raw",
      "label": "横向位置原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.y_raw",
      "label": "高度原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.z_raw",
      "label": "纵向位置原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.facing_right",
      "label": "朝向原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.act_st",
      "label": "行动状态编号",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.hit_st",
      "label": "受击标记原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.hit_st_old",
      "label": "上次受击标记",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.hit_stop",
      "label": "停顿剩余",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.damage_type",
      "label": "伤害类型原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.damage_source",
      "label": "伤害来源玩家",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.combo_cnt",
      "label": "另一连击计数",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.pl_input_new",
      "label": "方向与按键原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.pl_sw_new",
      "label": "新按键原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_current_frame",
      "label": "显示当前帧",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_prev_action_frame",
      "label": "显示动作帧",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_atk_margin",
      "label": "显示动作余量",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_hit_id",
      "label": "显示命中编号",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.guard_time",
      "label": "防御剩余",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.damage_time",
      "label": "受击剩余",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.pose_st",
      "label": "姿态编号",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.free_to_move",
      "label": "行动许可原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_action_id",
      "label": "引擎动作编号",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_action_frame_raw",
      "label": "引擎动作进度原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_frame_num_raw",
      "label": "引擎动作长度原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_margin_start_raw",
      "label": "引擎余量起点原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_speed_raw",
      "label": "引擎速度原值",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_state_flags",
      "label": "引擎状态标记",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_battle_version",
      "label": "战斗版本",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_loop_count",
      "label": "动作循环次数",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.engine_style_index",
      "label": "动作形态编号",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_size",
      "label": "计测表大小",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_index",
      "label": "计测表位置",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_type",
      "label": "计测格类型",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_empty",
      "label": "计测格为空",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_changed",
      "label": "计测格变化",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_end",
      "label": "计测格结束",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_not_add",
      "label": "计测格未新增",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.display_meter_not_whole",
      "label": "计测格不完整",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.health_pct",
      "label": "血量百分比",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.drive_pct",
      "label": "斗气百分比",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.super_pct",
      "label": "能量百分比",
      "type": "number"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.back",
      "label": "输入后方向",
      "type": "boolean"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.forward",
      "label": "输入前方向",
      "type": "boolean"
    },
    {
      "group": "对手·前一帧",
      "key": "other.previous.down",
      "label": "输入下方向",
      "type": "boolean"
    },
    {
      "group": "玩家",
      "key": "other.fighter_id",
      "label": "对手角色编号（当前版本）",
      "type": "number"
    },
    {
      "group": "玩家",
      "key": "other.control_mode",
      "label": "对手操作模式",
      "options": [
        [
          0,
          "经典"
        ],
        [
          1,
          "现代"
        ]
      ],
      "type": "enum"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.round",
      "label": "局数原值",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.replay_frame",
      "label": "录像帧",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.battle_round",
      "label": "战斗局数原值",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.stage_frame",
      "label": "战斗帧",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.render_tick",
      "label": "渲染计数",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.thread_id",
      "label": "采样线程编号",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.update_result",
      "label": "更新结果原值",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.fight_st",
      "label": "比赛阶段编号",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.play_timer",
      "label": "倒计时秒",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.play_timer_ms",
      "label": "倒计时子帧",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.display_prev_frame",
      "label": "显示同步帧",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.display_stun_frame",
      "label": "硬直差原始读数",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.display_attack_side",
      "label": "显示攻击方原值",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.meter_frame",
      "label": "计测表帧",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.meter_start_frame",
      "label": "计测表起点",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.meter_stop_frame",
      "label": "计测表停止帧",
      "type": "number"
    },
    {
      "group": "全局·发生帧",
      "key": "clock.current.meter_active",
      "label": "计测表活动状态",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.round",
      "label": "局数原值",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.replay_frame",
      "label": "录像帧",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.battle_round",
      "label": "战斗局数原值",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.stage_frame",
      "label": "战斗帧",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.render_tick",
      "label": "渲染计数",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.thread_id",
      "label": "采样线程编号",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.update_result",
      "label": "更新结果原值",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.fight_st",
      "label": "比赛阶段编号",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.play_timer",
      "label": "倒计时秒",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.play_timer_ms",
      "label": "倒计时子帧",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.display_prev_frame",
      "label": "显示同步帧",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.display_stun_frame",
      "label": "硬直差原始读数",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.display_attack_side",
      "label": "显示攻击方原值",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.meter_frame",
      "label": "计测表帧",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.meter_start_frame",
      "label": "计测表起点",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.meter_stop_frame",
      "label": "计测表停止帧",
      "type": "number"
    },
    {
      "group": "全局·前一帧",
      "key": "clock.previous.meter_active",
      "label": "计测表活动状态",
      "type": "number"
    }
  ],
  "schema": "sf6cc.replay-rules.v1",
  "settings": [
    {
      "key": "wakeup_frames",
      "label": "起身后抢招范围（帧）",
      "max": 30,
      "min": 1,
      "value": 8
    },
    {
      "key": "guard_frames",
      "label": "防御后抢招范围（帧）",
      "max": 30,
      "min": 1,
      "value": 15
    },
    {
      "key": "response_frames",
      "label": "防御后行动观察范围（帧，不含终点）",
      "max": 120,
      "min": 1,
      "value": 30
    },
    {
      "key": "advantage_min",
      "label": "防御机会：硬直差绝对值下限",
      "max": 120,
      "min": 1,
      "value": 4
    }
  ],
  "icon": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAYAAABw4pVUAAAACXBIWXMAAAsTAAALEwEAmpwYAAAEI0lEQVR4nO2dO2jVUBiA05f4aq1aRF1VLCjFLo5SN4tLS63QKoJFxM1RRwc3J1dxEGcnu4kOipM4iIJU8IFvbQVfKEJtPwmc4u3tOclNbpLz5+b/4E5NzvnP+ZL/JOckaRCUHOAo8BX4AYz7jqfyAJ/4zwff8VQe6vAdT+VBhcgCFSILVIgsUCGyoNWE1DdI8YsKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKEYYKaY43wBjQbX4jwEwzBaqQ5mRssjw0stH8LRUqJD1jEU/yjKctVIWkpztCSE9ZhWSegwviBdAVIWRDGYXkkoML4GYYYwMvEZVOSC45OEf+AueBthgZm4G3ZRSSSw7OifAtrSFHrAMmRfWYMyO1DJ9CHgOdEUI6gPvI4B6w3RJjJ3AJWMyyMh9CrgProk77mgZfMKnCB2FHX7YN3sAW4HYelRYp5DdwKkgIMAS8o1icb/QCB8KXS/OqOCgwRfU7Gjho8m8vcBBot2zTB0wXFOsjYKclhjbgHDCfZ+WBrxQFrDYpoZ47jpwddshpc6blGetaS93hAXODAgh8pChgtzkSXcwChx377gGeZBzrH+Cso759wHMKIi8hT4G9jgYeB34mGFRXWcpY4zi70vAa2O+I9QTwiwIJBKSoOB4CuxwddsR8ViMt07a7bhPrFTwQZDwXNejouH4zsKflO3DMUfYO4EHC8ubNAL3irjsc0GPSqVgh1rmoJlJUI1wD1lvqWJXgJu1jxF33KPANjwR5zEXV5PmrZM+ziDPxEPA5Yt+7wLai7rqLFhI1F9XZZIpq6KrIkXK2Arfqtl80Hb5iuia8xDbTIyLIS0jq9YAUg3Kfpf52c5PZa2IZiJgFqP28U6mFjOSxHpCC92Hnu2JxxNdmptJ9zZPlImTGccnY1HpAShaAi1EzyHULYOEik0iyuOwdN1MLmawHNEk4Zd8RIaPLLL+Kxfeaeh50CxjbUtOKQkaEjG2paEUhM4LGtsS0ohCJYxtVF1JaVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwVIgwgrJDqzWo7KBCZIEKkQMwZUnDU77jqiTASfPUO5aXc874jq9S4JahUgTKWEKlCJKxhErJeQBfYDk2ObZtdKAv4MxYDI9+ixDntr7b0RIQ08H1NhrZR0kJDXSsTUij+yoJoMEOdQlJUoYSAwk6MkpI0rIUCyTsQOBVzXYvsyhTib+0nYrYZ9h8JDP8DWdZdqUp4ihGzxR5HYVKkddBqBR5HYNKWQ4w6XuQxT3QTwZVwnyv6otPGTFS5uL+LUUrCpnzLSNCymylhNR8AXTONH5CQDwTNfGM+grkH0Ni59Ie2VqVAAAAAElFTkSuQmCC",
  "input_icons": {
    "1": "data:image/png;base64,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",
    "2": "data:image/png;base64,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",
    "3": "data:image/png;base64,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",
    "4": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAMAAAC5zwKfAAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAAoJQTFRFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQ0NDIiIiAAAAAAAAAAAAAAAAAAAAZWVl7+/vAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAioqKAAAAAAAAAwMDBAQEk5OT8vLy5+fnDAwMBAQEAAAAAAAAAAAAoqKiAAAAAAAAvb298/PzAAAAAAAAAAAAAAAABAQEAAAA19fXAAAAAQEBAAAAAAAAAAAAAAAAAAAABAQEAAAAAAAAAAAAAAAAAAAAAAAAAAAA5ubmDg4OAAAAAAAAAAAAAAAAAAAAAAAAAAAAT09PTk5OPj4+AAAAAAAAAAAAAAAAAAAA8fHxvb29AAAAAAAAAAAAAAAAoKCgra2tAAAAAAAAAAAAAAAAu7u7CgoKAAAAAAAAISEhAAAAAAAAMzMz5eXlAAAAAAAA7u7uAAAATExMAAAAWlpaAAAAAAAAAAAAAAAAAQEBY2Nj8vLyAAAAAAAAgYGBJiYmo6OjOTk5AAAAAAAAAAAAAAAAAAAAzc3NAAAAtLS0AAAAj4+P9/f3AAAAZGRkAAAAAAAAQ0ND7+/vqqqqAAAAAAAA5eXlxsbGAAAAIiIi7+/vyMjIxcXFjo6OAAAAAAAAAAAAIiIizc3NAAAAsbGxBAQEAAAAAAAAAAAAAAAAAAAAo6OjBAQEAAAAAAAA8/PzAAAAAAAAAAAAAAAAAAAAaGhoAgICWlpaAAAAAAAARUVFAAAAIyMjAAAAMTEx4uLiz8/PAAAA1tbWrKysAAAAAAAAAAAAAAAAAAAAAAAASU4joQAAANZ0Uk5TAAIQJENTMwMRNHS1yalmGQqE1Pb87DaO2v///8NMCEKU//9O10kFGFKo6vr/Z7Lm///////HRgS7+wbu+/sod8r+fcv/StIMivsVPNloYlg7HZfb///f08ChXyCr////4H4fHlz//y4nbrj///GaLQf//zB2/2/W//8J9/89/5b3FFa93v39/jWc/v/+/7f4JXXG/+v/uf//I/+T1fv7+zLQ/vt5/v7///tzwfL7+4f/77ysnhJZ/89qIf8PTZ0+j////w04/77/K/7//8L//xugo3GGR5bzuiYAAAOmSURBVHic7dhvaBNnHAfw7/fuYlK1klLwlRZn2WYrguI/yBRRJkEaygjZqqD4ppsgKlGUSpVIh2JRsQqrttuayZRZt5XiqlYlMgY1olCNCuI/KgpCRK2KpE2aJvUuVryL0txyzwtf9IGDu4ffffK7f8/z/EIIbhwFR8FPH2RmS4sEJRIctCUEgQ5SA8lXYkBnwpEB4wWvzKY4IigpRZn80jL5SAAoTWac6lUn0rI9aR0kJ1OJqR76IRfwrlXQPkV7Hr3FfciAjyzfQ7n87fPVUh20kZctgnL5uH6iQMtLBOi6XD5OjmE8Y2JAl0Imx7wYTwgBSxBdwHiPVNY7HKKCzhAwlDcYXaDEeiS7812IRdD975K0HKEDejCyNDeVeh3+GOhWUmkZ1x3Qg5MGwyNji7Qw8kn4A1CSKhmGo0jXNZVdWGhiINbEvxNZgaoX1j5fp65v6sXc2HCe0vNzBtD1vKcqVHZb/dwMYIG5mYLn3WRQH+kqY/zBGDztgwGcrW4XTIBfd7gTE5p14PxZZDvgvWTi5I81V5uPPPge9Mcz3vL/8vSywbfeiqG8vSzQL7OvHSuv9ebtGUH3NDt/x2qey98zgLWxk1VKcLVyxoKnB2vlo1UK5FNWOB1YG3m2LK7A9o817z1YN7w6+EsQyN1MNq6zpSAKLKnmoU1MQhjo3MRDmwcgDpzfvYfYZzcOCFZAHCBTe6StDcJANpDSLtT+JgxEQ2DC1l3Y3iIIBL6Y21G/Y8gWIH4WA4JNW4YcCgIUBaqzk+yoaUTgF2GgOt+tndiIuiZhINy3t/P1eR/xBMaX/FuYe+nX/4l5Uf0kJQU37m2Dj8JATTzQCp/tcX7gxj+yQVVUUq1YmXpsADbTVEH4dOKRa2uK/MbYkugxsqWaL3/SdaqLJRQhd7uJ+OI5O7J+nNJxBoHvd2aBC02Arf1H7wTvZoOQjkc7gTU/GsA67apPjOwtTwa/mlGRvQpSD6WO+52IBLfpwXp+AxzOkeHLzz3qKvfD+23vOLKi5gWK+5rVgxqIqAJCZGUhihuEgQjJ9BSidUAYiNDAWE/hCcaFgeiiN2lH241udf+qkFqvi7/+4EV7izAQXbZ7pV6cVIdcQaCa44NS77TqL5tFgXB/tqTUA5z29aP+2EPLFX1GvBjYAJzxpAWBQCSw6rS2qD271CkGhFyxc/9izJR8d0x6uUB/Z1PFlVvTk9+ZTTB3zeXvvN9dafZPGzPg/22j4Cj4KYBvAN5FTWCb+jGXAAAAAElFTkSuQmCC",
    "5": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAE7mlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wMVQwMjoxNjozNSswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDFUMDI6MTc6MjkrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDFUMDI6MTc6MjkrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjljM2E1NGI1LWI2ZDYtZjU0Ni1iNWYzLTY4NmYzNGUyNGViMyIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "6": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAMAAAC5zwKfAAAAAXNSR0IB2cksfwAAAAlwSFlzAAALEwAACxMBAJqcGAAAArtQTFRFAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQEBBAQEVVVVAwMDAAAAAAAAAAAAAAAA29vbv7+/AAAAAAAAAAAAr6+v8/PzpqamAQEBAAAAAwMDAQEBAAAAAAAAAAAAAAAApaWl8vLyz8/PIiIiAAAAAAAAAAAAAAAAAAAAzc3NAAAA7+/vQ0NDAAAAAAAAAAAAAAAAAAAAAAAAUFBQAAAA8/PzY2NjAAAAAAAAAAAAAAAAcnJyAAAAAAAAAAAAAAAAAAAAAAAAAAAAkJCQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAkZGRAgICAAAAAAAAAAAAAAAAnJycpKSkAAAAAAAAAAAAAAAANjY2Tk5OSkpKwcHBwsLCpaWlEBAQAAAAAAAAAAAAlJSU1tbWKioqAAAAAAAAAAAAAAAA6+vrMTExAAAAAAAAOTk5AAAAWlpaAAAAAAAAAAAA8vLyYmJiAAAAAAAAAAAAcXFxkJCQAAAAAAAAAAAAAAAAo6OjAAAAAAAAwcHBDw8PAAAA0NDQQ0NDAAAAAAAAY2NjZWVlAAAAAAAAAAAA6enpAAAAAAAAAQEBAAAAAAAAAQEBoKCgAAAAlZWV9/f3j4+PAAAAAAAAra2taGhoAAAAfHx8zs7OxcXFxMTE4+PjX19f7+/vZWVlAAAAAAAAAAAAAAAAQ0NDAAAAAAAAAAAAAAAAAAAAAAAA5eXlIiIiAAAAAAAA1dXVIiIiAAAAzc3NAAAArKyso6OjAAAAmZmZAAAAAAAA8fHxioqKAAAAAAAAAAAAAAAAAAAAZmZmAAAAAAAAAAAAVFRU3t7eTk5OAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAhR24ywAAAOl0Uk5TABADM1JmUTISlMfGkyMCLOr6+Om2Fzy7///mslQkOPv+aDCa/Pv/7wbe/yiW8P//////7st2JgT/Nv//1oYICyrx+kP/+9kFDBX7/FMcOlZigPzsqVgdIF6fvdP+/LRqP/v//gcbfNz7/////vv72HSS////uXMx4P//2gn/mPuOJ9/+/v7dUP7+VRphJf73eP7+O/73Wg73/w3VhP/vz8x667z/w////7io//9C////////+/v2QYXz+4MPnquszv77NKr+/nX79Pv/ZP9ZK///5KddmUv/jT0u///70sB954ETQGyITxjddH8kAAAD2UlEQVR4nO3Yb0gbZxwH8O8vmkTPVGlnHWSrq/ZF1W5CURBfLCub0xX6h1aLaenY9mKlXXHtQKkylTldYb4YDLaVWbsyqJP+wRc6nS3WktqWia3TQam0QtWIjJYyNajJxUv2XFy2S9TkcnnKGPiQF3eX333yPE9+99zvjsC50Rq4Bv7fQBbs5QfqvDpiTQxDqgfjFvUEBhpplg+YxCgG0mySK5SoHkwh5nkhj9vOBUx1EYzkhE4SFkOI6sF0moOJjRhJ08Jiwkj0YFKy4U8Twe3cIE0LgrSaGAG4Sc4adgaxv1ve6ucEIk5c1I9kxXq4gQLIMZnF+nmTGwh6gCwaT7NFBe6wpz4jf/iGIcD8Yu8Kl6FGMJnuIXdqJdEXUUTh3BtA4jolCMOv+e6pzf0vBKcPiygysLkZBiZDm7v6XlOCSHQhjp34e5DIIkr/nuww7ekfcg4qDrzqS8o2RzBoSReNuBcelFvuoGIn+RURsRK1lTYHgh/61jgVmtyh20oQGTOxkOhBdnNA1LbsRNGksoeYDwCRoXMgke4oRQYW9lBBr0owuL1F1+Qcafw3fWTQ2KUZFN6gn3PMbtI38AJZJydhjhnK9ovRg3h7Amb9oF8k1Hl1VzSDciuWbzbOeFs3NxB66aLVGd9t4wbC0AKr00QV3EA8vgvrV5XUbuMB+tCEBQhTL13v4AayC0bCVOoJDzcQ60kc20rH+IHYuDCWdvUXTiBL8Peq4HJ/c4QbyG6tX9Inc7zmUCAHyug4q0b5gGU/OE6SJHs8QAEe0SlV0cdl8vrAA/TMw1VFY62++x8HMG4e5dST3rVUPEUPljeiPOZaehf84LYD7o7KRo3aKdBpu/f7w+888Rd30YJ0GhNNh+Kz/ikWl8CaLzSC1Z/DWn+hRFEzEUoz3R2fqalF5MKjNvBA/aew/lSn9BhIsXojylVwFxW1jbwYbAddOdCSUvh1d8CPIu9u537DdhVgZUUQaGiF+P6uzoLAUbCPTtehDzNk+WtyVShBC52H5eVgb6ngJJMYpnc9wK3X55Tgm3QWlowdwZ6Wol1uDcni+aOjw61FzcFhGsGmM0DBcOvM8udSbeDZ74BLtn0z4ASe+yAHl/r2ziAq8LcS9hTwI9v46My7uEBUf9mzUpgGsP9bjA6Q7djKYZGDxlKMDlLvKl4E4MOdPjChmHnt61bzIgDzH5nRNpLZgBqxsPrIqmHqwT13zKjMa0AtWUJ4Ec1h727koDbm2UAILwLQvmXTubSWgzE774cMi+BV1TjL673tTfZll69GkK33w0MD1aG5//p13xq4Bj4n8C8nVmZgAW7sRgAAAABJRU5ErkJggg==",
    "7": "data:image/png;base64,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",
    "8": "data:image/png;base64,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",
    "9": "data:image/png;base64,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",
    "lp": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAFu2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wMVQwMjowMTo0NCswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDFUMDI6MDg6MTUrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDFUMDI6MDg6MTUrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjExMzNhYTA1LTg0NGUtYmE0Zi05MzI1LTk5MGUwZDU3Mjc5NSIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "mp": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAFu2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wMVQwMjowMjowOCswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDFUMDI6MDc6MjgrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDFUMDI6MDc6MjgrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjIwYWFiMzQ3LTYyYTQtMjk0OC04OWQyLTljYjRjOWIzNDE3MCIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "hp": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAFu2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wMVQwMjowMjoxNCswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDFUMDI6MDc6NDQrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDFUMDI6MDc6NDQrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjE5YzNlNWQ5LThjNTYtMTQ0YS1hYzhjLTE5N2UzNDZhZTMxNCIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "lk": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAFu2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wMVQwMjowMjowMSswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDFUMDI6MDc6NDErMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDFUMDI6MDc6NDErMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmM0NTU4MzNiLWRmN2ItNTU0NC1iZmI0LWQ4OTM4YjkzODNjMiIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "mk": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAFu2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wMVQwMjowMjoxMCswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDFUMDI6MDc6MzErMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDFUMDI6MDc6MzErMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjQ3Y2Q2OGFjLTIzZDMtYjM0MC1iNGU1LTUwOGZjZDcxZmNmYyIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "hk": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAFu2lUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wMVQwMjowMjoxNiswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDFUMDI6MDc6MzYrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDFUMDI6MDc6MzYrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjliYTVjN2JhLTM3OTEtMTI0Ni1hNjhiLTE2YzM0ZmU3NzY4NCIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "modern_l": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABPCAYAAAB8kULjAAAACXBIWXMAAAsTAAALEwEAmpwYAAAE7mlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wNFQwMDozODozMSswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDRUMDA6NDE6MDUrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDRUMDA6NDE6MDUrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjQzM2JkM2U1LWZkNWEtMTA0Yi04NWE4LTM4ZGI0YjI3OTdkMyIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo0MzNiZDNlNS1mZDVhLTEwNGItODVhOC0zOGRiNGIyNzk3ZDMiIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDo0MzNiZDNlNS1mZDVhLTEwNGItODVhOC0zOGRiNGIyNzk3ZDMiPiA8eG1wTU06SGlzdG9yeT4gPHJkZjpTZXE+IDxyZGY6bGkgc3RFdnQ6YWN0aW9uPSJjcmVhdGVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOjQzM2JkM2U1LWZkNWEtMTA0Yi04NWE4LTM4ZGI0YjI3OTdkMyIgc3RFdnQ6d2hlbj0iMjAyNi0wNy0wNFQwMDozODozMSswODowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIi8+IDwvcmRmOlNlcT4gPC94bXBNTTpIaXN0b3J5PiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/Pqt5mpEAABBoSURBVHic5Z15jGTHXcc/Ve/o7ulr7mu9x+xheze+yo6V2HLsxEksJBIUAYkUIhACFIkjRAIRIUWKEEokAgIlXH8EggBBEApIKCGIyMQkEbLjOHY5trPetXfX3mt2Z6ane6a7p4/X71Xxx+tu9/TO7OGd3ZnZ+Wq10/V7v6733nfqrl99R1hr2QwopTxgGrgNUMDtwBQw2f6ZBby2+zLQAOrABeBY++dx4DXgotZ6+WY+fwfiZhKolEoCjwF3Ae8H3gUMX2e2TWISfwg8A3xPa33iOvO8atwUApVSR4BfBj4A3AvIG3i7AvAd4BvAN7XWlRt4rxtHYLuKfhD4HeARIHFDbnR5nAT+HvgHrfXZG3GDDSdQKeUSE/d54P71/KTr4SVSpPIjpHLDZEamSGWH8FIZ/IEsnp9EOg7WQthqYqIQ02pSLxepV5ZoVIrUlhZoVJZo1ipErQBrovVuVwK+BPyd1vrcRr7vhhKolHoP8DniqnoJHM8nmc4zuGs/mdEpBidnyAxPIBAIAQJB+9+asO3/bPwJay3NepVKYZby/FlK50+xUponqK1ba2eBL2qt//y6XrQHG0KgUsoHvgD8Lmu8fyKTJz++m5G9hxnefYhUJo8jYjeBACyhMTQjQ2QNxhoATPvZZNtXCokjJI4QeFLiOBIbvwQGCMMWpQtvsnj6GMXzJ6kWZtd75KeBT2mtX7jed79uApVS7wD+Bnio/1oinWN8/92M7X8Hg9P7cYXAcxwiY7AWamGLUqNOEIY0Wi2qYUgQhUTGgLVE7WdzhAAhcKXEd1w8KUk6LulEgozvk/Y9PMfBERJrDE1jaFRKFN48ysXXX6Q8t2bz1wI+o7X+0vW8/3URqJT6ReCvgUyv3fESTB66j4nb72NwaqZbYoy1rAQtFusrlOp1amGLWivEtNsuIdarvKthsVgLjpQkXJek45DxfcbSWQaTCXzXI4giImOol4ssvnmU80d/yEppfq3s/hX4Ta314tvh4G0TqJT6PPDZfvvg9AwzD7yf/PQMruPiCYkBSo0aF8plCvUVwsgQWYsgJkFw9eT1wrZLqWnn5UpJNplkMpNlIp0h4bqExhAZQ3XxIuePPsu5V55ZK6uXgY9rrX9yrc/wtghUSn0V+JV++557H2HPvY+SSOfwpENkDcuNJrOVZRZrKzSjCCHAEbLbrm0UesmUQpBPJhlJpbktn8d3HEJriVoBhTPHOfH0t6iXi/1ZzAIfvtZ28ZoIVEo5wNeAj/XaE+kchx7+EGMzR3DcuD0q1+ucXl6iUFshNAYh4k5gY2lbG6an/RxMJtmXH2Isk4ntxrBSmufE09+icOZ4/1fngY9ordcspmvhWgn8K+A3em2ZkSkOP/az5CZ24wiBsZb52gqnikUarQBHShDiphDXDwsYY3CkZCKdYd/QMEnXIzIRYavJyWe/zblXfoBt9/ptnAE+prV+9mrucdUEKqX+lHhW0UV+ci+H3/dRMoOjOI5DK4o4WVzkfDme13tSsjlLFathrCWIIgaTSe4YHWckNUDLRBhrOfnDb3NGf7/bkbVxGnhUa33mSnlfFYFKqV8n7m27yE/s4a4nPkEqO4gvHcpBk9cXF1hYWcGVG9/GbQSaUUjS9bh9eJRd+TyRMbSM4Y3nnuT0C9/tJ/E54Amt9dLl8rzipF4p9Tjw5V5bdnSaO9/7c6SygyQch1Kjzktzs8xXq/hblDyAhOMSRBGvFuY5XSrFowAh2P/gB9mrHut3fxD44pXyvCyBSqk9wFd4a12OZHaII49/lOzwBL7jsFir8fL8BSqNJgnXhS1KXge+lETWcnRhjhPFRdz2AH3fgx9k6s4H+t0/qZT69OXyu1IJ/CPgQCfheAnufPQjZEam8B2X5UadV+bnqAZBTN42gCUmUQg4WVrkzPIyjpRIKTn40E8zODXT/5XPKaUOr5ffugQqpT4BfLzXtv/BDzCy5w48KWmEIccWF6gGTZLO9iCvAwskHA8HweulRWbLZXwp8ZMD3P7Ih0nlR3rdh4E/Wy+vNQlUSuWBz/Taxvbfxa4j70IgaBnDiWKBYq1OcpuUvH5YLJ7jYKKI44V5CrUanpRkR6eZuf99/e4/pZT6pbXyWa8Efgq4p5NI5YaZeeBxHM/HdSTnKmXOV+Lf2naGBVzHoRmGnCgWaIQRrpSMH7yXyUOq3/2zSqnJfuMlDCil7gB+7y2LYOrOB8iOTuM7Dkv1OmeWSm97/roV4bku5UaDM8slQOB6Prfd8zCp3FCv2+3E2xKrsFYR+nkg10nkJ/cwcUjhSEnLGE6WijRbLdxtXvp60VnUmK2UWWrU8aQkN76byTse6C8kv6WUWrUJtooFpdQg8MluxlIyffhB0rlhHCE4V16m1KjhbdN273KQIm7bTy+VCNvTv8mD95Eenuh120Vfx9pfjD4B7OkksqPTDO06gCsltbDFhUo5rro36i02Ga4QLNZrLNSqeEKSGhxlbN8RhFhF06/1JvoJ/NXOByEdRvcdJpUdQkjJxWqFWhAgb+iO5OZCtBdDZstVgijCE5LxQ/eRSGd73e5WSv1MJ9FlQyn1fqA7YExm8kwcUnhSUgsCFqpVLHarTzSuGxIo1mss1FZwHUlmaJyhXQfoqXcOcT/R9e/gQ0Cykxic3k8qN4wUkuVGg2oQIMWtW/o6cKQkMhFzK1WCyOBKycTBe3D9Vdva71RKjcNqArvjPjeRYnTvnbhCEGEoNetExtyybV8/pJQs1+tUm02kkOTGdpPMrhrSHAbeCW0ClVL3Avd1rrqeT3ZkClfKeBNopQbcOuO+K8ERgtAYloMGYPEHMuQmdtPXfT4Eb5XAu+kJ8smO3cZAfhgDVIMmQRRu2SWqGwEpBJE1LNXjmieFID+xB+k4vW7vVkolOwTe1bEKKcmMTnW77uVGg6i9UbOTIIj3rWtRiABy47vxkgO9LvcD07K9UfSOjlVKh/TQWDywjCKqzSbGmh1HoBSSZtiiHgQApAdHSWYGe12GgWEJjBLP8wBw/CSZwXj0vRIENKMw3vG/WU++ReAIQSMMqQYBIJDSwU9l+t0OSOJ573TH4g9kSeXi5jCIQlomQu6swhejvQ1bD0NCE4EQ/euEAAclcShtl1rXSyA9H4DQGiJj2ZxNya2ByBiMjdvENQjcJ4FVAxw3kejOd8PIELXZ34kQQGgMnZ1LP5nud8lJ4oDuLhIDOWjPCVtRxK27dHB1aIYtImviGMZLV6FSknhu14Vs729YILJcNuBxJ0B2oyosjuv3X05LYFVcQ+9Ge4e4ndYDrwcvkeo3DUv6lrR6p2sd4nZyCexFq1nvNxUlsCqewUQh0F7mjqNvd3QJNLYTkS2IwqD/8ookPvHTRbNWhvbUzXMcdjZ9kHC99kTCYsOw/3JdEh8B6CJsNrF0tvwkjnRgk46DbTYscdRrp1kLGiv9LmUJVIBqxxK2mphWXFRdIXGk6B4r2GmwWKSUSBGTWV++JIz6TQmUicNbAQhqlW74axwR72B2IH/WWiSCrOfjtmvhGgSekMRny17rWKKgQXVpDoC075Nw3PZAcmfBEFffhOMCFmMignq13+2k1FpHQDc63ZiIldICxsaxI5lEAilk99DLTkFkDEnPJZOII/tWlgo0qku9LkXawxiAVzpWawzVwoVu3HA+mezGPu8kWCxpz2fA87FAef4srUat1+UFYLZD4MvEjAJQWThHbbmIBDJ+At9xdxSBxlpc4ZBPprp7xctzZzDRqiHzD7TWDQmgtf4x8GLnStgKqCxeIDSGtO8xko6XsjfrdPvNRmQtrpTk/SQCQVCrto+LrXr/Z2D1NO6lzoewWadw+hihtThIhhIpnC0ScX8zYIwhn0qRSSQw1lBeOEujsmq4/CrwI1hN4H8S6xIAsDR7inq5iLGGfDJJxve7pyhvZUTG4EiHiXQG35GExjB34iXCoNnr9iOt9Tz0EKi1/g4xswA0qsvMvaZpGcOA7zOWySAQt/ykxADDqQHGBtKEkaFamqd0/iQ91TcC/q2T6I/V+GrngzURhdOvUq8uYY1hMpNlwPcx3Lql0LbXAKZzGXzHoWUN86+/SHNl1QHul7XW3+gk+gn8GvEpHQAqhVlK504QGsOA6zGVzXXnybciQmsZSQ0wNpChZQ31pQILbx7tPwr2t72JVQRqrUu9DtYYZl99jpVykchabsvlGUoO0Lp0VWLbw1iLJyV7B4dwpSQyhosnXmSlONfrdh74l17DWuFWXyeeHwOwfPEMc69rImPwpOTA0DAJzyM0t05VtsSdx3Q2x2AyRcsYyvNnuXj8+f6h219qrVedk72EQK31ceBPerO/cOx5KoXZ+MBeKsWewaG4Kt8iPUorDMklk+zJDwGWsBVw7qWnqZdXDV1eI5ZQWYX1Av7+gp5xYb1c5I3nnyJqBYSR4bZsjl3ZHME2L4Xx1m1EwnU5ODxK0nUIjWH+xI+5+Lrud/+C1vpiv3FNAts6VH/ca1s49Qrnjz4bH1CRkoPDowwPpGhs0/ZQEMf+SMfhjtFxRgcGaBlDpTDLGy/8b7/7f2ut/3GtfNYNOdVa/zN9Deap5/6HxTPHaRlD0nW5c2SMjJ+gEW0vEgXQjFpEWA4NjTCdi2tT0Kzx2v99s3/dr0jfOeleXClm9/eJ5ZMAiFpNjn3/P6guXiCIQvLJFHeNT5DxfZrbpCQKIGjLrhwYGmFP+9ywMYaTT/8XSxfe6P/KH2qtX10jK+AKBLZPbH+SWGMFEDQqJY4+9XUqxTmCKGJkYIC7x6fIJhMxiVu8XwmMwRGCI2MTHBweIbSx6M+bzz3J7LEf9bt/RWv95bXy6eCKUeNa66eA345TMTuVwizHvvvv1CtLNKOIoWSKeyamGc9kaJqQaIvOmZtRiO84HB4dZ+/QUDv6wnLquSc5rb/X7/48cQ28LDZcM+F0aZEz5TLGmPa26OZjUzUTlFJCa23bny+r2iGFwBWCC9UqJ0uxaocUYtOC0y0WY+zWUO2Aa9CNkZJ62OKNUomLlUq8KSVET6DOjUVHN8aRkPOT7N0qujEdrK9c9B723PueWLnIcbDWUmo0OLtcYrFeJ7yJykVZP8F0NsdkNou3VZSLenEl7azB6f04rosnBEEUsdxsMletUKhV39LOEgKnXSo3UjtrKpNldCCN326Dw62mndXBeuptrp9g4vb7mTh4T1e9zW/L3vWqt1VaTZqh2Xj1NscjtIYwiqhtVfW2DpRSdxHrB767/1oinWP8wN2MzVyqH2gsVIIGlSC4on4gxGRdi35gvVJicavrB3ZwJQXLZCZPfmqG8Zkj5Cb3MZDJx22gEIi2ruflFCwhjhSN287LKViGlAvnKZz6CYWzr20PBcteKKUeA/4AeO9a191EkkQqS356hqGpGbJju0gPjW+ohmptuUCzuq4m99bUUO3F1ar4Op6Pm0iRyg6Tyq+t4iukg5ASE7aIwhYmDKiVi9SXC9SXi9SWCzQqpVtHxbcX7Wr9BPBp4HFurPj2eth+OtJrQSn1MPALxB2N4sYrmf+AeJ/7n7TWl0RFbiQ2Q0v/EeBR4vO2Crjk+M814tbX0l8LV/nXHFzAJ/4rDlVisi4QR5OdJiZuU/+aw/8DUbcOoQnjq98AAAAASUVORK5CYII=",
    "modern_m": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAE7mlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wNFQwMDozODoyOSswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDRUMDA6NDE6MDArMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDRUMDA6NDE6MDArMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmVmZWRjZDQzLWJlMmQtNDg0MC04Mjc4LWFlNDMwMzE2ZWEzMyIgeG1wTU06RG9jdW1lbnRJRD0i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",
    "modern_h": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABRCAYAAABFTSEIAAAACXBIWXMAAAsTAAALEwEAmpwYAAAE7mlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wNFQwMDozODoyNiswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDRUMDA6NDE6MDMrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDRUMDA6NDE6MDMrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjgwZmU5YjZjLTQ0NGYtMjg0OS1hOTNjLWQ5NzcyZDFhMTFhMyIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo4MGZlOWI2Yy00NDRmLTI4NDktYTkzYy1kOTc3MmQxYTExYTMiIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDo4MGZlOWI2Yy00NDRmLTI4NDktYTkzYy1kOTc3MmQxYTExYTMiPiA8eG1wTU06SGlzdG9yeT4gPHJkZjpTZXE+IDxyZGY6bGkgc3RFdnQ6YWN0aW9uPSJjcmVhdGVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOjgwZmU5YjZjLTQ0NGYtMjg0OS1hOTNjLWQ5NzcyZDFhMTFhMyIgc3RFdnQ6d2hlbj0iMjAyNi0wNy0wNFQwMDozODoyNiswODowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIi8+IDwvcmRmOlNlcT4gPC94bXBNTTpIaXN0b3J5PiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PuARxvUAABDgSURBVHic7Z15jCRXfcc/79XR13T3zHTvzM7svbYXs4Zkyw6OOJQEZNl/YIn8Qy6IFIiQEgIEkgiFQ/wVgiKFQIAkf0TCITG5kKJEiiWwo5BIECuWcdkBL/jY+5hje44+po+qeu/lj6oeV3fPrPeYXTwzfLVadf3qdVW97/xevev3+7YwxvDjhOd5JWAWmACqwH5gBigAKilmAWvAHHARqAErwGXf9xu3+5nTELebQM/zysB9wD3ACeB1wM8Ameu8VA94GngBeBZ4Hvie7/v1rXrWa8FtI9DzvF8GHgR+mpjAW4HvAc8Bj/u+/0+36B4DuKUEep53B/CrwLuIvex24mng34B/8H3/1K26yS0hMCHufcBHgOJm5aQQWEJQtF3KrkvetinZGcquS05aA2U7WlEPAhpRj3YUUQ8CmlGAMgZ99To0gS8Bj9wKIreUQM/zJoCPERNX3qhM1rIZsx0OFYrM5grM5gvMZgtUMzkQAuJ/6UcEDOtPaQBjqPU6XO6ucbm9xuXOGufWmrSikK6KNnu8OjGRX/B9f+Xma5s83VYR6Hnee4nJu3f4nBSCCTfDHWNlTkxU2Zcfo5rNI0RClRCIhDZjNEYbjNEJdSD654VASBmXw0Dy7MYYat02l9otnl2pcapVZyXobeaZzxCT+OhW1PumCfQ8bwb4I+D9G50/WChyYmIPbyxPMpsfQ0oL+iRogw67qCBARSFGhajeK5/jQgZh2UhpIyyJlckgLAfLdrBcF+lkETL5Q2iN1orL7Rbfry/z7MoVzq81N3v0rwKf9n1/7mbqf1MEep73IPBl4Njwuf35Me6vTHNiYg+VTBZhWUhpYZQmiroEjTpBs0EUdFC9HjoKMSrqO9VAMzbrBoNAxITaDlYmg+3mcIsl3FIZ284iLInWCqMilno9nl25wlNLC1xstzaqwovAh33ff/xGObhhAj3P+23gL4ftRcfl/so0b6nOsDeXR0iJtGy0iujWl+mtLBGsNVBhgI7i95UQMnn/vUKbSH0eeUYTN19jNADStrEcF7dQIjNRIVueRDouOgwxWjHfafM/tTmeWlqgGQYbVeeDvu//1Y3wcEMEep73x8Anhu13Fcd5577D3DFWwrJshGVhooigscJabZFufQmtVOJF1vr77GZhtMYohcEgLZvs+ATZ0iSZiSqW62KUQinFqVadxy6d5aXm6kaX+Zzv+5+83ntfN4Ge530R+N20zRKSB/bu5xem91NyMkjHAa3ori6ztjhHr7WKjqL191/au7YSxpj4PWg0AkO2XKEwNUumPIGwLHQY0Qh7/NfCRf5j/iIq8eAU/tz3/Y9ezz2vi0DP8x4BfiNtKzouv3TgTn5qsootJJbrEq6t0Vw4T7dWi3tVQEo50ERvKfrN24CQkkx5nNLsEZyxMVQQEBnN/y3X+OcLL2/UpP/G9/33XeutrplAz/O+AHw0batmcvza4WO8rjSBkBYIQWdpgebFs0RBF2nZt4+0zWAMWkXYbpbi/sPkKtMxwVrxQmOFvz/7IrVeZ/hbX/R9/2PXcvlrItDzvN8BvpK2TWfzvPfI6zg6VkZaNsZomnMXaF4+D9ogHftaq3hboMMIpKA4e5DizAGEkGgVcbpV59EzL7DQbQ9/5UO+7//Fq133VQn0PO8XgW8A64xMZXO8/+hxDhSKSNtBRwH1sy/TXlqEZLgCWz9FvDkItFagFPnKFOXDdyJtFx2FXFhr8tXTJ1nsDnhiBLzb9/1/vepVr0ag53kHge8AB/q2kuPygTvu4WhxHOnYqKBH/exLdJYWEbazZT3rrYLRGhOF5CpTlA/fheVm0GHE6eYqf33qeRqD78QLwNt83z+/2fU2ra3neQ7wCCnyspbNuw/exdFiGWnbqF6P1bMv0l5aQDjua548iDsV4bi0lxZYPfsiqtdD2jZHi2XeffAustbAq+cA8EjCxYa4Wo3/EHhH2vDgzAHunazGQwIV0jj3Mp2lK0jHjQfD2wRCSKTj0lm6QuPcy2gVIiyLeyerPDhzYLj4O4i52BAb1trzvHuAz6RtJyaqvH16X0yUgfq5U7SXF5F2n7zX2jvvajAxibZLe3mR+rlT8ZBHSN4+vY8TE9XhL3wm4WQEm7nNJ0h1GrO5Ag/vO4IrHZCS1sIl2rV5hGVvi2a7GYSUCMumXZuntXAJpMSVDg/vO8JsrpAuarPBzAs2INDzvDcD70nbHth7gJlsHstxCNtNWnPnU0tL28nzhmHiOghBa+48YbuJ5TjMZPM8sHekKb8n4WYAG7nPp9IHx8uT3DM+ibBstI5oXj6PjsJ4kLxDIC0bHYVx3XSEsGzuGZ/keHlyuOinRr6bPvA87+eBd/aPHSl5a3UvY5aLsCSdK/N06ytIe+eQ14e0bbr1FTpX5hGWZMxyeWt1L87gK+qdnucNdKzDHvib6YPj5fivIGybqNOmOX8JYQTDi+47AwJhBM35y0TtNaRtrdd/CH+QPlgn0PO81xPvngHgSos3VabJOC4CQ3vxMlGvA9ZOJC+GsARRp8Xa4mWEkGRshzdXZ4bHhm9LuAIGPfC9QKl/cLBQ5O7iONKyibpdOiu1eHl9R3pfH3Hr6taXCbsdpOPw+tI4hwoDG4tFYq6AhEDP87LAQ32jLSQnJqrkHBdjoLNSI+x14xWXHQ5hWbHDLF/BGLClzRvHK9iDE4WHEs7WPfBnSe2mFR2HN4xX4t4p7NFdWoy9bxuP+a4VQkqM0XSXFtFBPM17w3iFojMwm7sXeBO8QuCbSfUMR8ZKyT4tBK0GYdBBWjufvD6kJQmDDkGrAQKq2TyHCqV0EUESaSGTifL9/TO2kPEaXzJl6zVW430MufOGLptBSButFL3GKph4X/vIWAlrcHH45zzPcyRxSNl63ErGsjiQL4IURL02Qbuxo7uNzSCAoN0g6rVBCA4XSsO98X1AVRLH4q3PW8qOy75cHhDxhncYbquVlq2CEBIVhqggAAT7cnnKjpsucgCYkcDxtHXSzZJzXIQQhJ01om53PZJgV0FKom6XsLOGEIKc4zLhZodL3S2JAxzXsTeXB8CoCNXtEEcD7D4kkTqobgeTBCwNrdAA3CeBI2nLVDaHQGCURgcBEvHj31n7cUAIJAIdBBilEQhm8yMEHpTA4bSl4sZhZtoodNjb1otVNwsD6LCHNgqEoGSPrOxPS6CStpSSAaPRGhWpXel8fQgBKlIYHUcwFEcJ3CNJzX8Bsv2lKkMc5bSLXdAkHPSbYc4ZIbA0QmBGWklQaLz9tyt7kD4EMQdGg0i4GURpZHwysNqym9tvH+mQuw28SQIDMQ2BVq8c7Ob220eKgwFuYrQlsJy29PpB2kIibGd77xndLAwxB8lMrDcawL4sidOo1qGNSSK7QUprV7dikXDQj3bfIGjdksBi2lIP4+BuISWWbe3qVmwMWPYrkbR9blJYlMDZtGUp6IAxSGEhncxu74SRTgYpLDAm5mYQZyVwJm1Z7HYwGIQlkW4myWvZfW5oTJzcI90MwpIYzHD4G8AZSZztuI75TjsJjbWwc7k4nnkXEogxCCFiDqQFJuFmEC9I4GTashx06URxW7ecDHJ0+rJrIG0Hy4mzcDtRyHLQHS5yUhInMV/oW+phwKXOGgaDWxjDzufXl3N2E4yKsPN53MIYBsOlzhr10eDLOUmc/f1039pTigvtZhznbLs42fzunJEIgZPNI20XtOFCu0lPDQyknwZq0vf9EHiqb42M5nSrjjYapCBTinMsjN49Xmh0hLAsMqUJkAKdcBIN5pU85ft+2J8LP0lqznGm1YhD/w24YyUcN4dWI0kpOxZaaRw3hztWAgO1XoczrQFpBkPM2fq+8P8Sp4EC0AxDfrC6FGcXuRmylSkQYn1dbCfDaA1CkK1MId0MOor4weoSzcFB9DPEnMUE+r7fBb7VPxsZzfdXl4h0hBCQm6ziZPKY0cn0joMxGiebJzdZRQiIdBRzMdh8v5VwNhBc9ChxejwA59aa/LCxig5D7GyOXGUPIHfF2kJ2ooqdzaPDkB82Vjk3mHPcJOYKSBHo+/4PiXNCAOiqiCdrc/SiEGMM+eo0di4Pagd7oVLYmRy5yT0YY+hFIU/W5oZlBL6TcAWMBlj+afrgZH2Zk/VljFLYuTz5yh528hK1EZDfM02mUMSoaL3+QxjgaIBA3/f/E3isfxxqzXdr87SieGuvML0Pt1RGheGOGxvqKCRTnqQwNYvWmlYU8N3aPOFgx/lYwtE6Ngo5+Gz64GR9medXlzEqwrIdivsOIR0HM7q0s22hVYS0HYqzB7AcF6Minl/d0Ps+O2wYIdD3/SeBr6dt35w7z6XOGioMyBbHKe8/Eq9WaM32btLJ0MwYxmYO4uSLqCDkUmeNb86NpMd9PeFmAJsFvXwOWPfdxW6bxy6fJdAKFQbkq9Pk98zEIhHbeGwYSwVE5Kt7GZveB1oT6JDHLp9lcTD9VRNzMoINCfR9/3ng42nbcys1vr1wkSQnivKho+Qnp9BRkIg/bCdPFBij0VFAfnKK8qE74i1Mo/n2wiWeW6kNf+HjCScj2DTsyvf9zwNPpG2Pz13gmeUaRimk5VA6dCe5yh502Cdxe8AYjQ4DcpU9lA7dibQcjFI8s1zj8bkLw8WfSLjYEK8Wt/YBUktdXRXxjfMvcbpZR0chVibD+OFj5CvTmDDYFs3ZaI0JA/KVacYPH8PKZNBRyOlmnW+cf2l4zHeBmINNcVUCfd8/R6yDtX7VRhjwtTM/4kyrgQ5DLCfD+JFj5Kt7MUqhX7Mdi0An8ij56l7GjxzDcjLoMORMq8HXzvxoONk6Aj6ScLD5VW9UM2FPJsevH72bO7a5ZsKpVp2/O/0jrowKT2yNZkIfG6l2TLpZfuXQMY6PTyClva1UO7RWnFxd4h/PvbTRUv3Wqnb04Xnel4EPpW0lx+Vd+49y38QUjtXXjWnRWrhIp3YlXpjl9uvGaB2rvwkhyVarFKcP4hQKqCAg1JrvLS/wLxdOsxaNTAi+4vv+h6/1VjeiXPR54PfSNikEb6nu5aHZQ0y6OaRjIzR0Gsu05i8StOqJcpEEad1i5aL4PSxtm8zYOIWpGbLjkyAsdBiyHHZ4Yu48370yhxqt+5/5vv/713PPG9XO+hSx5N0A7hwr8/D+I9xZLMdhIZaNicJNtLPklqWOGa0wSifaWVYs+VSdwi1NIGw70c6KONVq8O8Xz/Bya0Od2k/7vj8yVXs13Ix62weJ54bjaXvRcXnrnhnun5xmOtlT7Sc0B80GnfoSQWMFFfRQURSLK0oJQ7HYw1468JzGAPFU0hiDZdtYbga3NEGuXMEtlmI9m2SmNN9p8+TSHE/VFoZ7WoAA+IDv+397IzzcrH7gW4A/Ad42fO5AvsibKlMD+oFC2git4zSq5irh2hpht43qda+qHwivbNgIQUo/MIuTzeMUCrjFcRw3h5ESoyOMUiz1uq+mH/gdYs/77xvlYCsULIvAF7lGBUshLEQq704FXVS3h1KbKFj2H7SvWplx48+Wg5XNYKVyN4zSGHNdCpYf9X1/0wLXgq3WUP0k8PrhczejoQp9HVWJkGI9a+omNFSfBT7/mtFQTcPzvFngt7hOFd+9mQKTmQx2Eou3WR9tkv8irVju9Zjv3ZCK75d83x9ZLbhRvCZ0pMdshzHboei6lF9FR7oe9WgGAa0opBWFO0tHehg/UTLfQvxES3+LsMGvORwH7mIoY+oasAS8RBye9yw7/dccNkNCaIU48Xuaa/s9kQXiqLKl203YMP4fLlAtG0nuiAcAAAAASUVORK5CYII=",
    "modern_sp": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAACXBIWXMAAAsTAAALEwEAmpwYAAAFwGlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtbG5zOmRjPSJodHRwOi8vcHVybC5vcmcvZGMvZWxlbWVudHMvMS4xLyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiB4bXA6Q3JlYXRvclRvb2w9IkFkb2JlIFBob3Rvc2hvcCAyNC40IChXaW5kb3dzKSIgeG1wOkNyZWF0ZURhdGU9IjIwMjYtMDctMDRUMDA6Mzg6NDErMDg6MDAiIHhtcDpNb2RpZnlEYXRlPSIyMDI2LTA3LTA0VDAwOjQwOjU4KzA4OjAwIiB4bXA6TWV0YWRhdGFEYXRlPSIyMDI2LTA3LTA0VDAwOjQwOjU4KzA4OjAwIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjg1YmJiZjQ0LWFiM2UtNGM0Yy04ZGYyLTljMDIwMDQ3NGNlZCIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDpFMUVDRTQ2NUVFRjIxMUVEQkQ5N0UzMzc5NDkyNDhBRCIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOkUxRUNFNDY1RUVGMjExRURCRDk3RTMzNzk0OTI0OEFEIiBkYzpmb3JtYXQ9ImltYWdlL3BuZyIgcGhvdG9zaG9wOkNvbG9yTW9kZT0iMyI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOkUxRUNFNDYyRUVGMjExRURCRDk3RTMzNzk0OTI0OEFEIiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOkUxRUNFNDYzRUVGMjExRURCRDk3RTMzNzk0OTI0OEFEIi8+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249InNhdmVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOjg1YmJiZjQ0LWFiM2UtNGM0Yy04ZGYyLTljMDIwMDQ3NGNlZCIgc3RFdnQ6d2hlbj0iMjAyNi0wNy0wNFQwMDo0MDo1OCswODowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiBzdEV2dDpjaGFuZ2VkPSIvIi8+IDwvcmRmOlNlcT4gPC94bXBNTTpIaXN0b3J5PiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PollUyoAAAopSURBVHic7ZxtjFTVGcd/59w7szs7zDLDgoCmQsVoYlRm6he/4BorviZqIoEYmpr6glAVa2ht8Utj7VsMVkPRKLTaSgCDYqvtB2yF2pIq1bBD3JYSfIukLhjZ953dnbn3ntMPd8ad3Z1ZZubcZXd1fgkJe++5z3nu/55z73Oec84IrTV1akdOtQMznbqAhtQFNKQuoCF1AQ2pC2hIXUBD6gIaUhfQkLqAhtiF/6RSqXnAPcANgJgyj6Y3nwG70+n0zsIBobUmlUqdD2wDrpwqz2YQCl+rdel0WtupVGousB/42tT6NWOQ+D1VAmtEMpl8DPjBqBJSsmzZMlauXMm58+fg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",
    "modern_auto": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAAA5CAYAAACh6qw/AAAACXBIWXMAAAsTAAALEwEAmpwYAAAE7mlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wNFQwMDozODozNCswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMDRUMDA6NDQ6NDIrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMDRUMDA6NDQ6NDIrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOjZmYjRiNjU2LTg4YWQtOWY0MC04NzlmLTgyY2E3OThjOThmOCIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo2ZmI0YjY1Ni04OGFkLTlmNDAtODc5Zi04MmNhNzk4Yzk4ZjgiIHhtcE1NOk9yaWdpbmFsRG9jdW1lbnRJRD0ieG1wLmRpZDo2ZmI0YjY1Ni04OGFkLTlmNDAtODc5Zi04MmNhNzk4Yzk4ZjgiPiA8eG1wTU06SGlzdG9yeT4gPHJkZjpTZXE+IDxyZGY6bGkgc3RFdnQ6YWN0aW9uPSJjcmVhdGVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOjZmYjRiNjU2LTg4YWQtOWY0MC04NzlmLTgyY2E3OThjOThmOCIgc3RFdnQ6d2hlbj0iMjAyNi0wNy0wNFQwMDozODozNCswODowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIi8+IDwvcmRmOlNlcT4gPC94bXBNTTpIaXN0b3J5PiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gPD94cGFja2V0IGVuZD0iciI/PqQCj80AAAq/SURBVHic7Zx5cFXVHcc/5+7Je3kvCy9AJAQHUazLlM0qjlRcWusUnNqqjLbUaeuCdBwEHAWdtiOL1gbQQqdstjq1/1iZLgTFYUpnumgdBhIjwgyLCSGAMUhC8njrvff0j7eQ5L285CUspuQ78+bN3HvO7/zO99zzO7/zO797hZQSgCnTJt8CPAvcDGiAzTBSECQ4+QzYClTv3rWnGUBIKZkybfIioPoiKjjUEARm7N61p1ZMnjrpLuDdi63REMR+YJIG/KTnnZEjR3L/fQ9w8/SbkVIiFIEQ4sKreBEhXYkQgmCwk3ff205NzVYikUjXIlcDD2nA7V2vBgIBli9bwZGmRub/9AmOHTuGqqmoinoh9b/osB0bpOSrkyaxeOHTVIyuYO26X5NaM5K4QSNhINO49zv30tLyGY8+9gjSBX+xH6IXVPcvBYQQuNLlrT+9xZGmJt58403+9e9/Ultb27VYsdaz4oxbvs5zzy/FdVyuumoi8Xj8wmn9JYOiKJSVllG7Zw8127Yy89bbehIYzyDQ7/fT2tqK319MPB7Hdd0Lp/GXDK7romkaHk8hDQ0N3HH7HRlllJ4XbMdG13VceekS1xWu66IoCoZp9rR/QBYCgUtuxe0LUoIiBG5/CRxG/zFM4CAxTOAgkbEK9wYh8tuNpFbvbPWklN0Mcm+yc8nIV4++2uoNfZXtk0AhBIqi0NbWxpngGYSSQ6BIbIFUVSUQCKAqKq0nW4lGoyiqAjLRIZ/Ph8/nS69wZ86cob29HUj4Xo7joGka5eXlCCE4deoU4XA4LaM/Otu2jWEYBAIBhBBImdArEonwxRdfpLeoWeUl+yGlpLSsNNEu2fudk8DUaDU3N1M1toq7v3U3tm336htKJLqmE4lGqKurIxqLMuOWGYwYUUYoHEYgsCyLww2HaWxoRNM0YrEYYyorufOOO3EcG9u2sawCgmeC1NXVYdsON02fzshAIC2jL0jpUlBYSGdnJ7W1tekB6ejsIBqO8s1v3IXf7yMcyS5PItFUFU3TOXjwIB+2fJjVhclJoJIk79OGT7l83OVUV69iyuQpOI6D7MVHlICmqrS1tfO9+79LR2cHCxYs4NprriMaiyIQGIbOptc2saq6Gm9REaFQiOk33sSzzyzBdV0cx8EwDE60nGDOnAeIhCM88uNHmH7T9KSMviElmJZJY0MDD/3gIWKxGJFohLZTbSx5ZgkPP/wjCgosYvFYVnkSUBUVVVX5VfXL7Pj7DhzX6SeBkuQjD8dPHOfKK67klTWvMm3atH6onoDryuS/i2VZGIaBYRhnG1W1xBRKTi1d17Esq5sMX5EPoST2o6n6XWX0B15vEYpQCIVD2HGbpc8+x/z589G0RLdN0+xThmmaOXdjGauwEAkjf/r06QGRB2DbZ4PZ2fbSifvJsRfgOJmj25eM/sCxbWzXJh6Ls3jh093I6y9c1825kGRxYwThcBjd0Fm8aHHe5J1TJGeDruf35KWgaionW08y69uzmDdvXt7k9QdZJTqOg6lbjK6oyLjX2NjI4cMH0XSdeCxOxWUVfOXqa865YpBYkaWEffs+wesppK2tjVgsSmlpGddeez2meZZY27bZu3cvLS2fYVompaWlNB89SjgcYezYsRnkdXZ2UF9fTyQSQVFUNF1lypSpFBYU5qVj9iER4EiHeCyWcWvbOzX8/Bc/o6SklLa2NubOncvq6jV5NdpfqKqKqiqseWU18XgcTdNobm5m5syZbNywiZHlI9NlQ6EQ1ate5u0tWxg/fjzxeBxd19MmKWVzUzhy5AhPLniSY8easawCiouL+cuf/8q4qnF56Zj3M62qGqZppn+6rucrIm9omoaiKKiqimWZ6IaR4X4IAbpuYJomhmGgKEruKSuUdB8MI1FvIM56/gRqKqZlJRq3TDT13NuVnkgNUiqspOt6Fr9WoOt6mhBVVVGU3neqihDoho5hmBimkXha++UkdUfevY/H4gSDQQzdIBgMEs0yzc81Uk5sair25tR2vZ+rXG/lB4K8gwlSyu4jNcCG/1+Q9xM4e9Zsrr/uenRdJx6PMXLUqAwDfSkhbwIrKyuprKw8H7oMSQzHAweJYQIHiWECB4m8bWDzsWaONjWh6Rp23CZQXs4V4684H7oNCeRNYE3NVpavWJbcyp3iwQe/z8svvXw+dBsSyJtA23EJh8NYVoRwOIJ9Cad+wAAINE0DX3ExPl8RjrQpKCg4H3oNGQxoJyJdN/k/8C2QJFn3ImWQSCTSJd2Pge6ozn8kIAuikSgdHacBOBM8Q7h74uIFgeu4BINBOjo6sCwLTdMGlEh1XglUFAXTsDKuz5o1m4kTJ6JpGrZtU5UlBpcrkpIPUmcqPbeaVVVjWV29KhlQVdB1nUAgkFF/0OfCA4UQgmgkSmNjAxMnTux2b8KECUyYMCFn/dbWk8Sig4/0mKZJU1MTsVis26GUz+dn5szbctZ1XZdTp04lUpx7CXWdN0c6FWxYtWY1e/fuzatua2sry5a/QFt726ACtq7rEhgRYPt729n82uZejyZ7q/v6G69Ts60Gb6EHVc2e4pydQAkCkbWSqqrdTvOzlVEUBaEoFBX5qK+v44n589i375N+KX7ixAkee/xRdux4D4/HkzmFJKiKkjHFUxHrnotaKpq9YuVy1q//bWLB6ANSSjZv3sTS55YQt+N4PJ5ey+Z8AgsLMw9YdFVHphiU2W2EpmngShRFobJyLPv372feE49T91FdTsU///xznlr4FDv/sZMxYyqzDo4kEY/0FnbvlMfjQSjirG5JuK6L1+vF4/HwwrIXWPubdX0mj/7u9d+z9PklFHoKKSspw7YdesspybCBEollWQgFNmzcwGUVl9EZ7AQEBQUW9fX1FHmLEELg9XrZU1vLipUrkFKm7UwoHCIcCScPdQRV46o4eOgQixYvZOatM5FSJpVKQFEEBQWF7N37Me9/8J/0KVrPVVFKSbG/mKPNzax4cSWWZRKLJQ6bBHDwwEECIwIZ9RzHwe/3I4Rg7bpXaTzSwMjyckKhEF3PBnRdJxQKsbXmb/h8PspHlBO3c28Usi4iuqGjqirb3tlGOBxOPwmu6+LxePB6vemsgyNHGvn443qAdKaBoiiUlJQkUoWTB9MVFRU0NTWxcdPGrCtsKh85EAigKEpWl0JKidfj5fTpdt784x/SslPT1u/34/P5sh7Up5KaIpEIW7a8nda3m3wSPqHP5yMQSJDXlzeQlcCUnfD5fFntUKpzUkoMw6CsrCxDRteOpf59Pl9OxzvVTi5/zHEdVFWlpKQka/1s5HXVO6Vvrih6KrurP+gzO6s//ti5zLe7EHIGk2/YE8PxwEFimMBBIjM7i0RK2aV5xpYd6cUxy7TPIPCskR+mEEh7BNFo9hcGMxaR9vZ2AoEAdXV1jB49+pJ/V05KSUdnB2MqK2lL5nF3RQaBH/z3fX4492F27tzJgYMHKPYXDzjmN5SRelvz+PHjTJs2jXtm38NLv3yxZzFdTJ466SgwJnUlEAiwcsWLHD50iPUb19PS0pLYZ17K7wsvepqPPqpj7bq1PX3UDWLy1ElvAfd1vTpq1CjmPDCHr91wI4hz6zcNFfTjjXWAecPfTBg4DgCTlN279mwHFl9sbYYYgsCc3bv2hESX78bcRoLI6Qx/N6Ynev1uzP8AFTGHfzFyym8AAAAASUVORK5CYII=",
    "modern_n": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABRCAYAAABFTSEIAAAACXBIWXMAAAsTAAALEwEAmpwYAAAGlmlUWHRYTUw6Y29tLmFkb2JlLnhtcAAAAAAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iQWRvYmUgWE1QIENvcmUgOS4xLWMwMDIgNzkuZjM1NGVmYywgMjAyMy8xMS8wOS0xMjo0MDoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczpkYz0iaHR0cDovL3B1cmwub3JnL2RjL2VsZW1lbnRzLzEuMS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgeG1sbnM6eG1wTU09Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9tbS8iIHhtbG5zOnN0RXZ0PSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvc1R5cGUvUmVzb3VyY2VFdmVudCMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiB4bXA6Q3JlYXRlRGF0ZT0iMjAyNi0wNy0wNFQwMDozODoyNiswODowMCIgeG1wOk1vZGlmeURhdGU9IjIwMjYtMDctMTdUMTE6MDY6MjgrMDg6MDAiIHhtcDpNZXRhZGF0YURhdGU9IjIwMjYtMDctMTdUMTE6MDY6MjgrMDg6MDAiIGRjOmZvcm1hdD0iaW1hZ2UvcG5nIiBwaG90b3Nob3A6Q29sb3JNb2RlPSIzIiB4bXBNTTpJbnN0YW5jZUlEPSJ4bXAuaWlkOmY1ZmE4MjM5LTM3M2QtOGU0Yy1iYzY1LTZhYzNiN2NjODRmNyIgeG1wTU06RG9jdW1lbnRJRD0iYWRvYmU6ZG9jaWQ6cGhvdG9zaG9wOjgwZDgzNjJlLWUwN2ItNDI0OS1iZmI4LTFlNTgxYWU2NmQ1YSIgeG1wTU06T3JpZ2luYWxEb2N1bWVudElEPSJ4bXAuZGlkOjgwZmU5YjZjLTQ0NGYtMjg0OS1hOTNjLWQ5NzcyZDFhMTFhMyI+IDx4bXBNTTpIaXN0b3J5PiA8cmRmOlNlcT4gPHJkZjpsaSBzdEV2dDphY3Rpb249ImNyZWF0ZWQiIHN0RXZ0Omluc3RhbmNlSUQ9InhtcC5paWQ6ODBmZTliNmMtNDQ0Zi0yODQ5LWE5M2MtZDk3NzJkMWExMWEzIiBzdEV2dDp3aGVuPSIyMDI2LTA3LTA0VDAwOjM4OjI2KzA4OjAwIiBzdEV2dDpzb2Z0d2FyZUFnZW50PSJBZG9iZSBQaG90b3Nob3AgMjUuNSAoV2luZG93cykiLz4gPHJkZjpsaSBzdEV2dDphY3Rpb249InNhdmVkIiBzdEV2dDppbnN0YW5jZUlEPSJ4bXAuaWlkOmNhY2RlYjg2LWYwY2UtNmQ0YS05OGEzLTUwY2E1Y2ZiZTVmMCIgc3RFdnQ6d2hlbj0iMjAyNi0wNy0xN1QxMTowNjoyOCswODowMCIgc3RFdnQ6c29mdHdhcmVBZ2VudD0iQWRvYmUgUGhvdG9zaG9wIDI1LjUgKFdpbmRvd3MpIiBzdEV2dDpjaGFuZ2VkPSIvIi8+IDxyZGY6bGkgc3RFdnQ6YWN0aW9uPSJzYXZlZCIgc3RFdnQ6aW5zdGFuY2VJRD0ieG1wLmlpZDpmNWZhODIzOS0zNzNkLThlNGMtYmM2NS02YWMzYjdjYzg0ZjciIHN0RXZ0OndoZW49IjIwMjYtMDctMTdUMTE6MDY6MjgrMDg6MDAiIHN0RXZ0OnNvZnR3YXJlQWdlbnQ9IkFkb2JlIFBob3Rvc2hvcCAyNS41IChXaW5kb3dzKSIgc3RFdnQ6Y2hhbmdlZD0iLyIvPiA8L3JkZjpTZXE+IDwveG1wTU06SGlzdG9yeT4gPC9yZGY6RGVzY3JpcHRpb24+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+IDw/eHBhY2tldCBlbmQ9InIiPz6fitdpAAAQGklEQVR4nO2da2xb53nHfzw3kRQvokiJlixZFztL7MSIj2XHlxgzkAQ17CZI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"
  },
  "system_source": "-- Build-local ACT_ST evidence, never character Action-ID semantics.\nlocal M = {}\nlocal function attack(n) return n == 29 or n == 30 or n == 31 end\nlocal function guard(n) return n == 27 or n == 28 end\nlocal function reaction(n) return n == 32 or n == 38 end\nM.attack, M.guard, M.reaction = attack, guard, reaction\nlocal function cause(rule, title, level)\n    return {rule=rule, title=title, level=level or \"observed\"}\nend\nfunction M.classify(f,settings)\n    if f.source_observed ~= 3-f.receiver then return cause(\"unresolved\", \"已确认掉血，来源尚未确定\", \"unknown\") end\n    if guard(f.current_state) and f.flags.guard and f.counter_at_damage == 0 then\n        return cause(\"guard_damage\", \"防住了，但仍然掉血\")\n    end\n    if f.current_state == 38 and f.other_state == 37 then\n        if f.previous_state == 39 then return cause(\"parry_caught\", \"蓝防后受伤（类型待确认）\", \"inferred\") end\n        if attack(f.previous_state) then return cause(\"attack_caught\", \"出招后受伤（类型待确认）\", \"inferred\") end\n        return cause(\"caught\", \"受伤类型待确认\", \"unknown\")\n    end\n    if f.previous_state == 35 then return cause(\"wakeup_hit\", \"起身时被压中\") end\n    if f.wakeup_last_frame and f.frame-f.wakeup_last_frame <= (settings and settings.wakeup_frames or 8) and attack(f.previous_state) and f.flags.counter then\n        return cause(\"wakeup_button_counter\", \"起身后抢招被打断\")\n    end\n    if attack(f.previous_state) and f.flags.punish then\n        if f.attack_start_observed and f.active_seen and not f.contact_seen\n            and (f.last_meter_type == 8 or f.last_meter_type == 13) then\n            return cause(\"whiff_punish_candidate\", \"出招落空后被惩罚\", \"inferred\")\n        end\n        return cause(\"attack_punished\", \"出招过程中被确反康\")\n    end\n    if attack(f.previous_state) and f.flags.counter then\n        if (f.previous_y or 0) > 0 then\n            if (f.other_y or 0) > 0 then return cause(\"air_attack_counter\", \"空中出招被打断\") end\n            return cause(\"air_ground_counter\", \"空中出招时被地面对手打中\")\n        end\n        if f.guard_end and f.frame-f.guard_end <= (settings and settings.guard_frames or 15) then return cause(\"guard_button_counter\", \"防御后抢招被打断\") end\n        return cause(\"attack_counter\", \"出招被对手抢先打断\")\n    end\n    if reaction(f.previous_state) then\n        if f.reaction_preceded_by_guard then return cause(\"guard_reaction_followup\", \"防御后陷入受击状态，被继续追击\") end\n        return cause(\"reaction_followup\", \"受击过程中继续掉血\")\n    end\n    if f.facing_changed and (f.other_y or 0) > 0 then return cause(\"side_change_air_hit\", \"换边时没有挡住空中进攻\", \"inferred\") end\n    if guard(f.previous_state) and f.current_state == 32 then\n        if f.previous_direction and f.current_direction and not f.previous_direction.back and not f.current_direction.back then\n            return cause(\"guard_not_held\", \"防御后没有继续维持后方向\", \"inferred\")\n        end\n        if f.previous_direction and f.previous_direction.back and f.previous_direction.down and (f.other_y or 0) > 0 then\n            return cause(\"crouch_guard_air_hit\", \"蹲防没有挡住后续空中进攻\", \"inferred\")\n        end\n        return cause(\"guard_broken\", \"防御转入受击\")\n    end\n    if f.previous_state == 10 then return cause(\"dash_intercepted\", \"冲刺途中被截停\") end\n    if f.previous_state == 8 or f.previous_state == 9 then\n        if f.previous_direction and f.previous_direction.forward then return cause(\"forward_walk_hit\", \"前走时被打中\", \"inferred\") end\n        return cause(\"movement_hit\", \"移动时被打中\")\n    end\n    if (f.previous_y or 0) > 0 then return cause(\"air_hit\", \"空中被打中\") end\n    return cause(\"unresolved\", \"已确认掉血，原因证据不足\", \"unknown\")\nend\nfunction M.with_settings(settings)\n    return {attack=M.attack,guard=M.guard,reaction=M.reaction,direction=M.direction,\n        classify=function(f) return M.classify(f,settings) end}\nend\nfunction M.direction(mask, facing)\n    if type(mask) ~= \"number\" or mask < 0 or mask%1 ~= 0 or (facing ~= 0 and facing ~= 1)\n        or mask & 12 == 12 or mask & 3 == 3 then return nil end\n    return {back=mask & (facing == 1 and 4 or 8) ~= 0,\n        forward=mask & (facing == 1 and 8 or 4) ~= 0, down=mask & 2 ~= 0}\nend\nreturn M\n"
};
