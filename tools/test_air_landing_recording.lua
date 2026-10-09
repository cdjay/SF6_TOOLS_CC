package.path = "autorun/?.lua;autorun/?/init.lua;./?.lua;" .. package.path

-- Jump-in recordings with the shipped command tables. An air normal lands
-- into an internal execution phase (ac_type13_air_landing_execution_phase).
-- That phase must never become a step of its own, whether the jump-in button
-- is released before landing or the next command is pressed before, on or
-- after the landing frame; the buffered command keeps its own step.

local Json = require("tools/training_record_bank/vendor/dkjson")

local function read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text
end

local decoded = {}
local function load_json(path)
    local normalized = tostring(path or ""):gsub("\\", "/")
    if decoded[normalized] == nil then
        local text = read("data/" .. normalized)
        decoded[normalized] = text and Json.decode(text) or false
    end
    return decoded[normalized] or nil
end

json = { load_file = load_json, load_string = function() return nil end }
_G.safe_load_json = load_json
fs = { read = function() return nil end }
log = { warn = function() end, error = function() end, info = function() end }
sdk = {}
imgui = setmetatable({}, { __index = function() return function() return nil end end })
re = { on_frame = function() end, on_draw_ui = function() end, on_application_entry = function() end }

local Consumer = require("func/ComboTrials/UnifiedActionConsumer")
local CharacterRules = require("func/ComboTrials/CharacterRules")
local Renderer = require("func/ComboTrials_ImGui")
Renderer.init({
    d2d_cfg = { allow_classic_trials_in_modern = false, modern_display_mode = "simple",
        show_unresolved_action_ids = true, font_size = 0.02, trial_title_font_size = 0.03 },
    trial_state = {},
    players = {},
    sf6_menu_state = {},
    is_runtime_allowed = function() return false end,
})
local common = CharacterRules.load_common()

local UP, DOWN, FORWARD, LP, HP = 1, 2, 4, 16, 64
local BUTTON = { ["j.HK"] = 512, ["j.HP"] = 64 }

-- Action IDs of the landing phase, one air normal and two ground normals.
local function ids_for(character, air)
    local document = load_json("TrainingComboTrials_data/command_display/" .. character .. ".json")
    local relation
    for _, item in ipairs(document._meta.suppressed_internal_transitions) do
        if item.kind == "ac_type13_air_landing_execution_phase" then relation = item end
    end
    assert(relation, character .. " must declare an air-landing execution phase")
    local function display(id)
        local entry = document[tostring(id)]
        return type(entry) == "table" and type(entry.classic_command) == "table"
            and entry.classic_command.display or nil
    end
    local ids = { L = relation.target_action_id }
    for _, id in ipairs(relation.source_action_ids) do
        if display(id) == air then ids.A = ids.A or id end
    end
    for key, value in pairs(document) do
        if key:match("^%d+$") then
            local id = tonumber(key)
            if display(id) == "HP" and (ids.G == nil or id < ids.G) then ids.G = id end
            if display(id) == "2+LP" and (ids.C == nil or id < ids.C) then ids.C = id end
        end
    end
    assert(ids.A and ids.G and ids.C, character .. " test Actions must resolve")
    assert(document[tostring(ids.L)].ownership == "internal_execution_phase")
    return ids
end

local function seg(action, n, input, combo, hp)
    return { action = action, n = n, input = input or 0, combo = combo or 0, hp = hp or 10000 }
end

local function record(character, frames)
    local exceptions = CharacterRules.load_for_character(character)
    local relations = select(1, Consumer.load_generated_action_relations(character, load_json))
    assert(relations, character .. " generated relations must load")
    local function resolver(action_id, event, session)
        return Consumer.resolve_compiled_motion(character, action_id, event, session, Renderer)
    end
    local session = Consumer.new_capture({
        character = character, control_mode = "classic", source = "recording", frame = 0,
        motion_resolver = resolver,
        action_event_projection_rules = CharacterRules.build_action_event_projection_rules(exceptions, common),
        action_event_rules = CharacterRules.build_action_event_rules(exceptions, common),
        action_relations = relations,
    })
    local frame, current, action_frame = 0, nil, 0
    for _, item in ipairs(frames) do
        for _ = 1, item.n do
            frame = frame + 1
            action_frame = item.action == current and action_frame + 1 or 0
            current = item.action
            Consumer.observe_capture(session, {
                frame = frame, action_id = item.action, action_frame = action_frame,
                direct_input = item.input, facing_right = true, combo_count = item.combo,
                actor_hp = 10000, actor_drive = 60000, actor_super = 0,
                victim_hp = item.hp, victim_damage_type = 0, victim_hit_stop = 0,
            })
        end
    end
    local compiled = Consumer.finalize_capture(session, { motion_resolver = resolver })
    local ids = {}
    for _, step in ipairs(compiled.steps) do ids[#ids + 1] = tostring(step.id) end
    return table.concat(ids, ",")
end

local function check(character, air)
    local ids = ids_for(character, air)
    local A, L, G, C = ids.A, ids.L, ids.G, ids.C
    -- Forward jump; the air normal is released before it lands and hits.
    local jump = { seg(1, 10), seg(1, 1, UP | FORWARD), seg(34, 4, UP | FORWARD), seg(37, 6, UP | FORWARD),
        seg(37, 14), seg(37, 1, BUTTON[air]), seg(A, 7, BUTTON[air]) }
    local hit = 9300
    local tail = { seg(G, 18, 0, 2, 8500), seg(1, 40, 0, 0, 8500) }
    local function with(...)
        local frames = {}
        for _, part in ipairs({ jump, ... }) do
            for _, item in ipairs(part) do frames[#frames + 1] = item end
        end
        return frames
    end
    local cases = {
        { "jump-in only", { seg(A, 7, 0, 1, hit), seg(L, 3, 0, 1, hit), seg(1, 40, 0, 0, hit) },
            {}, { 37, A } },
        { "HP after landing", { seg(A, 7, 0, 1, hit), seg(L, 3, 0, 1, hit), seg(1, 3, 0, 1, hit),
            seg(1, 1, HP, 1, hit), seg(G, 7, HP, 1, hit) }, tail, { 37, A, G } },
        { "HP 4f before landing", { seg(A, 3, 0, 1, hit), seg(A, 4, HP, 1, hit), seg(L, 3, 0, 1, hit),
            seg(G, 7, 0, 1, hit) }, tail, { 37, A, G } },
        { "HP 2f before landing", { seg(A, 5, 0, 1, hit), seg(A, 2, HP, 1, hit), seg(L, 3, HP, 1, hit),
            seg(G, 2, HP, 1, hit), seg(G, 5, 0, 1, hit) }, tail, { 37, A, G } },
        { "HP on landing frame", { seg(A, 7, 0, 1, hit), seg(L, 3, HP, 1, hit),
            seg(G, 2, HP, 1, hit), seg(G, 5, 0, 1, hit) }, tail, { 37, A, G } },
        { "HP during landing", { seg(A, 7, 0, 1, hit), seg(L, 1, 0, 1, hit), seg(L, 2, HP, 1, hit),
            seg(G, 2, HP, 1, hit), seg(G, 5, 0, 1, hit) }, tail, { 37, A, G } },
        { "2LP 2f before landing", { seg(A, 3, 0, 1, hit), seg(A, 2, DOWN, 1, hit),
            seg(A, 2, DOWN | LP, 1, hit), seg(L, 3, DOWN | LP, 1, hit), seg(C, 2, DOWN | LP, 1, hit),
            seg(C, 4, DOWN, 1, hit), seg(C, 10, 0, 2, 8800), seg(1, 40, 0, 0, 8800) }, {}, { 37, A, C } },
    }
    for _, case in ipairs(cases) do
        local actual = record(character, with(case[2], case[3]))
        local expected = {}
        for _, id in ipairs(case[4]) do expected[#expected + 1] = tostring(id) end
        assert(actual == table.concat(expected, ","), string.format(
            "%s %s %s: recorded %s, expected %s", character, air, case[1], actual,
            table.concat(expected, ",")))
    end
end

check("Ryu", "j.HK")
check("Luke", "j.HK")
check("Lily", "j.HK")
check("Jamie", "j.HK")
check("Jamie", "j.HP")

print("air landing recording tests passed")
