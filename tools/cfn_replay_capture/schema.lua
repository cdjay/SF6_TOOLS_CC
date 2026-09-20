local M = { version = "sf6cc.cfn-state-capture.experimental.v1" }

M.clock_columns = {
    "round", "replay_frame", "battle_round", "stage_frame", "render_tick",
    "thread_id", "update_result", "fight_st", "play_timer", "play_timer_ms",
    "display_prev_frame", "display_stun_frame", "display_attack_side",
    "meter_frame", "meter_start_frame", "meter_stop_frame", "meter_active",
}
M.player_columns = {
    "vital_new", "vital_old", "vital_max", "heal_new", "focus_new", "focus_max",
    "mSuperGauge", "mSuperGaugeMax", "mSingleDamage", "mComboDamage", "mComboCount",
    "action_id", "action_frame_raw", "x_raw", "y_raw", "z_raw", "facing_right",
    "act_st", "hit_st", "hit_st_old", "hit_stop", "damage_type", "damage_source",
    "combo_cnt", "pl_input_new", "pl_sw_new", "display_current_frame",
    "display_prev_action_frame", "display_atk_margin", "display_hit_id",
    "guard_time", "damage_time", "pose_st", "free_to_move",
    "engine_action_id", "engine_action_frame_raw", "engine_frame_num_raw",
    "engine_margin_start_raw", "engine_speed_raw", "engine_state_flags",
    "engine_battle_version", "engine_loop_count", "engine_style_index",
    "display_meter_size", "display_meter_index", "display_meter_type",
    "display_meter_empty", "display_meter_changed", "display_meter_end",
    "display_meter_not_add", "display_meter_not_whole",
}
M.columns = {}
for _, name in ipairs(M.clock_columns) do M.columns[#M.columns + 1] = name end
for side = 1, 2 do
    for _, name in ipairs(M.player_columns) do
        M.columns[#M.columns + 1] = "p" .. side .. "." .. name
    end
end
M.index = {}
for index, name in ipairs(M.columns) do M.index[name] = index end
return M
