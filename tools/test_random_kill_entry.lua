local callbacks = {}
local registered_panel = nil
local import_calls = 0
local applied_scenarios = 0
local runtime_pending = nil
local current_fighter_id = 2
local p2_vital = 10000
local drawn_text = {}
local ticker_messages = {}

local dependency_names = {
    "func/SharedHooks",
    "func/RuntimeSafety",
    "func/GameState",
    "func/Training_SharedUI",
    "func/Training_MenuRegistry",
    "func/Training_SessionRecap",
    "func/DynamicRecords",
    "func/RandomKill/Scenario",
    "func/RandomKill/Runtime",
    "func/RandomKill/Stats",
}
local previous_loaded = {}
local previous_preload = {}
for _, name in ipairs(dependency_names) do
    previous_loaded[name] = package.loaded[name]
    previous_preload[name] = package.preload[name]
    package.loaded[name] = nil
end
local previous_globals = {
    re = re,
    imgui = imgui,
    json = json,
    safe_load_json = _G.safe_load_json,
    show_custom_ticker = _G.show_custom_ticker,
    CurrentTrainerMode = _G.CurrentTrainerMode,
}

re = {
    on_frame = function(callback)
        callbacks[#callbacks + 1] = callback
    end,
}
imgui = {
    get_window_size = function() return { x = 1000, y = 48 } end,
    text = function(value) drawn_text[#drawn_text + 1] = tostring(value) end,
    text_colored = function(value) drawn_text[#drawn_text + 1] = tostring(value) end,
    same_line = function() end,
    separator = function() end,
    drag_int = function(_, value) return false, value end,
    checkbox = function(_, value) return false, value end,
    button = function() return false end,
}
json = {
    load_file = function(path)
        if path == "TrainingRandomKill_data/Ryu_20260727_170833.json" then
            local group = {}
            for slot = 1, 10 do group[slot] = { slot = slot, active = slot == 1 } end
            local slots = {}
            for slot = 1, 8 do slots[slot] = { slot = slot, is_valid = false } end
            return {
                schema = "sf6cc.training_setup.v2",
                title = "随机斩杀训练",
                fighter_id = 1,
                source_player = "P2",
                slots = slots,
                reversals = { down = group, guard = group, damage = group },
            }
        end
        return nil
    end,
    dump_file = function() return true end,
}
_G.safe_load_json = function()
    return {
        schema = "sf6cc.random_kill_config.v1",
        user = { low_health_chance = 50, show_floating = true },
    }
end
_G.show_custom_ticker = function(message)
    ticker_messages[#ticker_messages + 1] = tostring(message)
end
_G.CurrentTrainerMode = 0

package.preload["func/SharedHooks"] = function() return {} end
package.preload["func/RuntimeSafety"] = function()
    return { is_training_allowed = function() return true end }
end
package.preload["func/GameState"] = function()
    return { in_pause_menu = false, frame = 1 }
end
package.preload["func/Training_SharedUI"] = function()
    return {
        begin_floating_window = function() return true, 1920, 1080 end,
        end_floating_window = function() end,
        draw_floating_bg = function() end,
        sf6_rect_button = function() return false end,
    }
end
package.preload["func/Training_MenuRegistry"] = function()
    return {
        register = function(panel_id, draw_fn)
            registered_panel = { id = panel_id, draw = draw_fn }
            return true
        end,
    }
end
package.preload["func/Training_SessionRecap"] = function()
    return {
        show_bars = function() return true end,
        hide = function() end,
    }
end
package.preload["func/DynamicRecords"] = function()
    return {
        SCHEMA = "sf6cc.training_setup.v2",
        get_context = function()
            return {
                fighter_id = current_fighter_id,
                fighter_name = current_fighter_id == 1 and "Ryu" or "Luke",
                source_player = "P2",
            }
        end,
        import_from_file = function()
            import_calls = import_calls + 1
            return true, "ok", import_calls == 1 and "backup.json" or "preset-backup.json"
        end,
    }
end
package.preload["func/RandomKill/Scenario"] = function()
    return dofile("autorun/func/RandomKill/Scenario.lua")
end
package.preload["func/RandomKill/Runtime"] = function()
    return {
        capture = function() return { saved = true }, nil end,
        apply_scenario = function()
            applied_scenarios = applied_scenarios + 1
            runtime_pending = "scenario"
            return true, nil
        end,
        restore = function()
            runtime_pending = "restore"
            return true, nil
        end,
        update = function()
            if runtime_pending == "scenario" then
                runtime_pending = nil
                return "ready", nil
            end
            if runtime_pending == "restore" then
                runtime_pending = nil
                return "restored", nil
            end
            return "idle", nil
        end,
        cancel_pending = function() runtime_pending = nil end,
        read_p2_vital = function() return p2_vital end,
    }
end
package.preload["func/RandomKill/Stats"] = function()
    return dofile("autorun/func/RandomKill/Stats.lua")
end

local api = dofile("autorun/TrainingRandomKill_v1.0.lua")
assert(api.mode_id == 5, "random kill must own mode 5")
assert(api.preset_path == "TrainingRandomKill_data/Ryu_20260727_170833.json",
    "entry must use the bundled Ryu preset")
assert(registered_panel and registered_panel.id == "random_kill_config",
    "entry must register its manager panel")
assert(#callbacks == 1, "entry must register one frame callback")
registered_panel.draw()
for _, text in ipairs(drawn_text) do
    assert(not text:find("固定预设槽位数量不完整", 1, true),
        "complete preset must not display an incomplete-slot warning")
end

_G.CurrentTrainerMode = 5
callbacks[1]()
callbacks[1]()
assert(import_calls == 0 and applied_scenarios == 0,
    "non-Ryu P2 must be rejected before any runtime mutation")
assert(api.get_session().phase == "waiting_ryu",
    "non-Ryu P2 must leave the one-click setup waiting safely")
for _ = 1, 90 do callbacks[1]() end
assert(#ticker_messages == 1,
    "waiting for a Ryu P2 must notify once instead of spamming the ticker")

current_fighter_id = 1
for _ = 1, 31 do callbacks[1]() end
assert(import_calls == 1, "one-click mode entry must import the preset exactly once")
assert(applied_scenarios == 1, "one-click mode entry must generate the first scenario")
assert(api.get_session().phase == "ready", "first scenario must become ready")
p2_vital = 6500
callbacks[1]()
api.next_scenario()
local damage_summary = api.get_stats_summary()
assert(damage_summary.samples == 1 and damage_summary.average_damage == 3500,
    "next scenario must record P2 damage under the completed resource combination")

api.stop()
for _ = 1, 5 do callbacks[1]() end
assert(import_calls == 2, "stop must restore the exact pre-session recording backup")
assert(api.get_session().phase == "idle", "stop must restore runtime state and become idle")

for _, name in ipairs(dependency_names) do
    package.loaded[name] = previous_loaded[name]
    package.preload[name] = previous_preload[name]
end
re = previous_globals.re
imgui = previous_globals.imgui
json = previous_globals.json
_G.safe_load_json = previous_globals.safe_load_json
_G.show_custom_ticker = previous_globals.show_custom_ticker
_G.CurrentTrainerMode = previous_globals.CurrentTrainerMode

print("random kill entry tests passed")
