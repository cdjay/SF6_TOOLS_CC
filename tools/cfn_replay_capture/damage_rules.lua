-- Build-local ACT_ST evidence, never character Action-ID semantics.
local M = {}
local function attack(n) return n == 29 or n == 30 or n == 31 end
local function guard(n) return n == 27 or n == 28 end
local function reaction(n) return n == 32 or n == 38 end
M.attack, M.guard, M.reaction = attack, guard, reaction
local function cause(rule, title, level)
    return {rule=rule, title=title, level=level or "observed"}
end
function M.classify(f,settings)
    if f.source_observed ~= 3-f.receiver then return cause("unresolved", "已确认掉血，来源尚未确定", "unknown") end
    if guard(f.current_state) and f.flags.guard and f.counter_at_damage == 0 then
        return cause("guard_damage", "防住了，但仍然掉血")
    end
    if f.current_state == 38 and f.other_state == 37 then
        if f.previous_state == 39 then return cause("parry_caught", "蓝防后受伤（类型待确认）", "inferred") end
        if attack(f.previous_state) then return cause("attack_caught", "出招后受伤（类型待确认）", "inferred") end
        return cause("caught", "受伤类型待确认", "unknown")
    end
    if f.previous_state == 35 then return cause("wakeup_hit", "起身时被压中") end
    if f.wakeup_last_frame and f.frame-f.wakeup_last_frame <= (settings and settings.wakeup_frames or 8) and attack(f.previous_state) and f.flags.counter then
        return cause("wakeup_button_counter", "起身后抢招被打断")
    end
    if attack(f.previous_state) and f.flags.punish then
        if f.attack_start_observed and f.active_seen and not f.contact_seen
            and (f.last_meter_type == 8 or f.last_meter_type == 13) then
            return cause("whiff_punish_candidate", "出招落空后被惩罚", "inferred")
        end
        return cause("attack_punished", "出招过程中被确反康")
    end
    if attack(f.previous_state) and f.flags.counter then
        if (f.previous_y or 0) > 0 then
            if (f.other_y or 0) > 0 then return cause("air_attack_counter", "空中出招被打断") end
            return cause("air_ground_counter", "空中出招时被地面对手打中")
        end
        if f.guard_end and f.frame-f.guard_end <= (settings and settings.guard_frames or 15) then return cause("guard_button_counter", "防御后抢招被打断") end
        return cause("attack_counter", "出招被对手抢先打断")
    end
    if reaction(f.previous_state) then
        if f.reaction_preceded_by_guard then return cause("guard_reaction_followup", "防御后陷入受击状态，被继续追击") end
        return cause("reaction_followup", "受击过程中继续掉血")
    end
    if f.facing_changed and (f.other_y or 0) > 0 then return cause("side_change_air_hit", "换边时没有挡住空中进攻", "inferred") end
    if guard(f.previous_state) and f.current_state == 32 then
        if f.previous_direction and f.current_direction and not f.previous_direction.back and not f.current_direction.back then
            return cause("guard_not_held", "防御后没有继续维持后方向", "inferred")
        end
        if f.previous_direction and f.previous_direction.back and f.previous_direction.down and (f.other_y or 0) > 0 then
            return cause("crouch_guard_air_hit", "蹲防没有挡住后续空中进攻", "inferred")
        end
        return cause("guard_broken", "防御转入受击")
    end
    if f.previous_state == 10 then return cause("dash_intercepted", "冲刺途中被截停") end
    if f.previous_state == 8 or f.previous_state == 9 then
        if f.previous_direction and f.previous_direction.forward then return cause("forward_walk_hit", "前走时被打中", "inferred") end
        return cause("movement_hit", "移动时被打中")
    end
    if (f.previous_y or 0) > 0 then return cause("air_hit", "空中被打中") end
    return cause("unresolved", "已确认掉血，原因证据不足", "unknown")
end
function M.with_settings(settings)
    return {attack=M.attack,guard=M.guard,reaction=M.reaction,direction=M.direction,
        classify=function(f) return M.classify(f,settings) end}
end
function M.direction(mask, facing)
    if type(mask) ~= "number" or mask < 0 or mask%1 ~= 0 or (facing ~= 0 and facing ~= 1)
        or mask & 12 == 12 or mask & 3 == 3 then return nil end
    return {back=mask & (facing == 1 and 4 or 8) ~= 0,
        forward=mask & (facing == 1 and 8 or 4) ~= 0, down=mask & 2 ~= 0}
end
return M
