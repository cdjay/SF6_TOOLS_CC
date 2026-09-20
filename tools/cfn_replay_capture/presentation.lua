local M = {}
-- Display-only roster labels, following Records.lua; no Action or move mapping.
local characters = {
    [1] = "隆 Ryu", [2] = "卢克 Luke", [3] = "金伯利 Kimberly", [4] = "春丽 Chun-Li",
    [5] = "曼侬 Manon", [6] = "桑吉尔夫 Zangief", [7] = "JP", [8] = "达尔西姆 Dhalsim",
    [9] = "嘉米 Cammy", [10] = "肯 Ken", [11] = "迪杰 Dee Jay", [12] = "莉莉 Lily",
    [13] = "阿鬼 A.K.I.", [14] = "拉希德 Rashid", [15] = "布兰卡 Blanka", [16] = "蛛俐 Juri",
    [17] = "玛丽莎 Marisa", [18] = "古烈 Guile", [19] = "爱德 Ed", [20] = "本田 E. Honda",
    [21] = "杰米 Jamie", [22] = "豪鬼 Akuma", [23] = "维嘉 M. Bison", [24] = "特瑞 Terry",
    [25] = "沙加特 Sagat", [26] = "维嘉 M. Bison", [27] = "特瑞 Terry", [28] = "不知火舞 Mai",
    [29] = "艾莲娜 Elena", [30] = "毒蛇 Viper", [32] = "英格丽德 Ingrid",
}
local function value(v)
    if v == nil or v == false then return "未知" end
    return tostring(v):gsub("[%c]", " ")
end
function M.player_title(meta,side)
    local p=(meta.players or {})[side] or {}
    local id=characters[p.playing_fighter_id] and p.playing_fighter_id or p.fighter_id
    return (characters[id] or "未知角色").." / "..(({[0]="经典",[1]="现代"})[p.control_mode] or "未知操作模式")
end
local function fixed(v) return type(v) == "number" and string.format("%.2f", v / 65536) or "未知" end
local function round_number(v) return type(v) == "number" and tostring(v + 1) or "未知" end
local function gauge(n, max)
    local text = value(n) .. " / " .. value(max)
    if type(n) == "number" and type(max) == "number" and max > 0 then text = text .. string.format("（%.1f%%）", n / max * 100) end
    return text
end
function M.lines(snapshot)
    local meta, v = snapshot.metadata, snapshot.values
    local out = { summary = {
        "录像：" .. value(meta.replay_id),
        "读取时第 " .. round_number(v.round) .. " 局 / 共 " .. value(meta.round_count) .. " 局",
        "读取时录像帧：" .. value(v.replay_frame),
        "读取时战斗第 " .. round_number(v.battle_round) .. " 局 / 战斗帧：" .. value(v.stage_frame),
    }, players = {} }
    if v.round ~= v.battle_round then out.summary[#out.summary + 1] = "正在换局，两个计数尚未同步" end
    if type(v["p1.x_raw"]) == "number" and type(v["p2.x_raw"]) == "number" then
        out.summary[#out.summary + 1] = "双方位置间距：" .. fixed(math.abs(v["p1.x_raw"] - v["p2.x_raw"])) .. "（不是招式射程）"
    end
    for side = 1, 2 do
        local p = (meta.players or {})[side] or {}
        local function g(n) return v["p" .. side .. "." .. n] end
        local id = p.playing_fighter_id
        if not characters[id] then id = p.fighter_id end
        local mode = ({ [0] = "经典", [1] = "现代" })[p.control_mode] or ("未知（" .. value(p.control_mode) .. "）")
        local facing = g("facing_right") == 1 and "朝右" or g("facing_right") == 0 and "朝左" or "未知"
        out.players[side] = {
            tostring(side) .. "P：" .. (characters[id] or ("未知角色 " .. value(id))) .. " / " .. mode .. " / " .. facing,
            "玩家：" .. value(p.name) .. " / CFN：" .. value(p.short_id),
            "血量：" .. gauge(g("vital_new"), g("vital_max")),
            "斗气：" .. gauge(g("focus_new"), g("focus_max")),
            "能量：" .. gauge(g("mSuperGauge"), g("mSuperGaugeMax")),
            "本次伤害：" .. value(g("mSingleDamage")) .. " / 连段伤害：" .. value(g("mComboDamage")) .. " / 连击数：" .. value(g("mComboCount")),
            "位置 X：" .. fixed(g("x_raw")) .. " / Y：" .. fixed(g("y_raw")) .. " / Z：" .. fixed(g("z_raw")),
            "动作编号：" .. value(g("action_id")) .. " / 动作进度：" .. fixed(g("action_frame_raw")),
            "防御剩余计数：" .. value(g("guard_time")) .. " / 受击剩余计数：" .. value(g("damage_time")) .. " / 停顿计数：" .. value(g("hit_stop")),
            "LP：" .. value(p.league_point) .. " / MR：" .. value(p.master_rating),
        }
        local types = { [0] = "无分类", [7] = "可被打康", [8] = "可被打确反康", [9] = "受击硬直", [10] = "防御硬直", [13] = "攻击判定", [14] = "飞行道具" }
        out.players[side][#out.players[side] + 1] = "帧数表：" .. (types[g("display_meter_type")] or ("待核对类别 " .. value(g("display_meter_type"))))
            .. " / 格号：" .. value(g("display_meter_index")) .. "（格子可能保留旧状态）"
    end
    return out
end
function M.draw(imgui, snapshot, schema)
    local view = M.lines(snapshot)
    for _, text in ipairs(view.summary) do imgui.text(text) end
    for side = 1, 2 do
        imgui.separator()
        for _, text in ipairs(view.players[side]) do imgui.text(text) end
    end
    if imgui.tree_node("更多读数（供核对）") then
        imgui.text("录像版本：" .. value(snapshot.metadata.version) .. " / 场景编号：" .. value(snapshot.metadata.stage_id))
        for _, n in ipairs(schema.columns) do imgui.text(n .. "：" .. value(snapshot.values[n])) end
        imgui.tree_pop()
    end
end
return M
