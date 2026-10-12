package.path = "autorun/?.lua;" .. package.path

local State = require("func/ComboTrials/ComboListState")
local saved, events = nil, ""
local decoded = {}
local state = State.new({
    load = function() return saved end,
    save = function(_, value) saved = value return true end,
    open = function()
        if events == "" then return nil end
        local file = assert(io.tmpfile())
        file:write(events)
        file:seek("set", 0)
        return file
    end,
    decode = function(line) return decoded[line] end,
})

local first = { filepath = "TrainingComboTrials_data\\CustomCombos\\Ryu\\One.json",
    character = "Ryu", control_type = "classic" }
local second = { filepath = "TrainingComboTrials_data/CustomCombos/Ryu/Two.json",
    character = "Ryu", control_type = "classic" }
local items, infos = { "One", "Two" }, { first, second }
assert(state:load_favorites())
assert(not state:is_favorite(first))
assert(state:toggle_favorite(second))
assert(state:is_favorite(second) and not state:is_favorite(first))
assert(saved.schema == "sf6cc.combo_favorites.v1")
assert(state:order(items, infos)[1] == 2)
assert(state:order(items, infos, function(a, b) return a > b end)[1] == 2)
local many_items, many_info = {}, {}
for index = 1, 42 do
    many_items[index] = tostring(index)
    many_info[index] = { filepath = "TrainingComboTrials_data/CustomCombos/Ryu/" .. index .. ".json" }
end
local descending = state:order(many_items, many_info, function(a, b) return a > b end)
assert(descending[1] == 42 and descending[#descending] == 1,
    "descending table sort must remain a strict ordering")
assert(state:toggle_favorite(second))
assert(state:order(items, infos)[1] == 1)
assert(state:toggle_favorite(first))
local reloaded = State.new({ load = function() return saved end })
assert(reloaded:load_favorites() and reloaded:is_favorite(first))
assert(not reloaded:is_favorite(second))

local function event(id, filename, source, outcome, character, control)
    return {
        schema = "sf6cc.combo_attempt.v1", event_id = id,
        combo = { character = character or "Ryu", local_filename = filename,
            declared_control = control or "classic" },
        runtime = { source = source or "manual" }, result = { outcome = outcome },
    }
end
decoded.a = event("a", "One.json", "manual", "success")
decoded.b = event("b", "One.json", "manual", "fail")
decoded.c = event("c", "One.json", "auto_demo", "success")
decoded.d = event("d", "One.json", "manual", "success", "Ken")
decoded.e = event("e", "One.json", "manual", "success", "Ryu", "modern")
events = "a\nb\nc\nd\ne\na\n"
assert(state:refresh_stats())
local stat = assert(state:stat(first))
assert(stat.attempts == 2 and stat.successes == 1)
assert(state:stat(second) == nil)
assert(state:refresh_stats() and state:stat(first).attempts == 2)
decoded.f = event("f", "One.json", "manual", "success")
events = events .. "f\n"
assert(state:refresh_stats())
assert(state:stat(first).attempts == 3 and state:stat(first).successes == 2)
decoded.g = event("g", "One.json", "manual", "fail")
events = events .. "g"
assert(state:refresh_stats() and state:stat(first).attempts == 3,
    "unfinished log line must wait for its newline")
events = events .. "\n"
assert(state:refresh_stats() and state:stat(first).attempts == 4)
events = "a\n"
assert(state:refresh_stats())
assert(state:stat(first).attempts == 1)
assert(State._test.stat_key("Ryu", "Renamed.json", "classic", "combo-1")
    == State._test.stat_key("Ryu", "One.json", "classic", "combo-1"))
assert(State._test.stat_key("Ken", "One.json", "classic", "combo-1")
    ~= State._test.stat_key("Ryu", "One.json", "classic", "combo-1"))
print("combo list state: OK")
