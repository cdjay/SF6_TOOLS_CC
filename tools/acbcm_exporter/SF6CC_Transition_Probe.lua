-- SF6CC_Transition_Probe.lua
-- Read-only capture of the engine's view of every P1 Action change.
--
-- Why: most remaining hand-written force / ignore / absorb_ids rules correct
-- how the Combo Trials runtime decides whether an Action is a player step.
-- That decision reads three engine values at each Action change:
-- mParam.state_flags, KeyInput.Action ("action_code") and Branch.BranchType.
-- AC+BCM say how each Action is entered (a BCM trigger, or a BranchKey of a
-- given Type/Param); this capture links those entries to the engine values,
-- so the rules can be derived instead of written by hand.
--
-- Use: Training Mode, P1 = the fighter to study. REFramework > ScriptRunner >
-- Run this file. Perform the fighter's moves (specials, follow-ups, holds,
-- throws, target combos, supers). Running the file again pauses / resumes
-- recording and saves. Output: reframework/data/SF6CC_ACBCM/transitions-fNNN.jsonl,
-- one JSON object per Action change, appended across sessions.
--
-- Running a newer copy of this file while an older probe is active upgrades
-- the running probe in place (its unsaved records are kept and saved).

local existing = rawget(_G, "SF6CC_TransitionProbe")
local register = rawget(_G, "SF6CC_TRANSITION_PROBE_NO_REGISTER") ~= true

local Probe = existing or {
    enabled = true,
    frame = 0,
    written = 0,
    buffer = {},
    last = nil,
}
Probe.FLUSH_RECORDS = 40
Probe.DIRECTORY = "SF6CC_ACBCM"
Probe.version = 2

local SFIX = 65536
local FIELDS = { "t", "fighter", "prev", "prev_frame", "act", "frame", "flags", "code", "branch", "input", "sw" }

local function try(fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

local function field(object, name)
    if object == nil then return nil end
    return try(function() return object:get_field(name) end)
end

local function sfix(raw)
    if type(raw) == "number" then return raw end
    local value = try(function()
        return raw:get_type_definition():get_field("v"):get_data(raw)
    end)
    return value and value / SFIX or nil
end

-- One sample of P1: { fighter, act, frame, flags, code, branch, input, sw }.
function Probe.read_p1()
    local battle = try(function() return sdk.find_type_definition("gBattle") end)
    local players = battle and try(function() return battle:get_field("Player"):get_data(nil) end)
    if players == nil then return nil end
    local player_types = field(players, "mPlayerType")
    local fighter = player_types and try(function() return player_types[0] end)
    local list = field(players, "mcPlayer")
    local p1 = list and try(function() return list[0] end)
    if p1 == nil then return nil end
    local sample = {
        fighter = tonumber(fighter),
        input = tonumber(field(p1, "pl_input_new")) or 0,
        sw = tonumber(field(p1, "pl_sw_new")) or 0,
    }
    local act_param = field(p1, "mpActParam")
    local action_part = field(act_param, "ActionPart")
    local engine = field(action_part, "_Engine")
    if engine == nil then return nil end
    sample.act = tonumber(try(function() return engine:call("get_ActionID") end))
    sample.frame = sfix(try(function() return engine:call("get_ActionFrame") end))
    sample.flags = tonumber(field(field(engine, "mParam"), "state_flags"))
    sample.code = tonumber(field(field(act_param, "KeyInput"), "Action"))
    sample.branch = tonumber(field(field(act_param, "Branch"), "BranchType"))
    if sample.act == nil then return nil end
    return sample
end

-- Records an Action change; returns the record or nil.
function Probe.observe(sample)
    Probe.frame = Probe.frame + 1
    if sample == nil then return nil end
    local last = Probe.last
    Probe.last = sample
    if last ~= nil and last.act == sample.act and last.fighter == sample.fighter then
        -- Remember how far the previous Action ran.
        return nil
    end
    local record = {
        t = Probe.frame,
        fighter = sample.fighter,
        prev = last and last.act or nil,
        prev_frame = last and last.frame or nil,
        act = sample.act,
        frame = sample.frame,
        flags = sample.flags,
        code = sample.code,
        branch = sample.branch,
        input = sample.input,
        sw = sample.sw,
    }
    Probe.buffer[#Probe.buffer + 1] = record
    return record
end

-- Plain numbers only, so the line never depends on the host JSON library.
function Probe.encode(record)
    local parts = {}
    for _, name in ipairs(FIELDS) do
        local value = tonumber(record[name])
        if value ~= nil then
            local text = math.type and math.type(value) == "integer" and tostring(value)
                or string.format("%.17g", value)
            parts[#parts + 1] = string.format('"%s":%s', name, text)
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Writes the buffered records; keeps them when a file cannot be opened.
function Probe.flush()
    if #Probe.buffer == 0 then return true end
    pcall(function() if fs and fs.create_dir then fs.create_dir(Probe.DIRECTORY) end end)
    local by_file = {}
    local order = {}
    for _, record in ipairs(Probe.buffer) do
        local name = string.format("%s/transitions-f%03d.jsonl", Probe.DIRECTORY, tonumber(record.fighter) or 0)
        if by_file[name] == nil then
            by_file[name] = {}
            order[#order + 1] = name
        end
        local lines = by_file[name]
        lines[#lines + 1] = Probe.encode(record)
    end
    for _, name in ipairs(order) do
        local ok, file = pcall(io.open, name, "ab")
        if not ok or not file then
            Probe.last_error = "cannot open " .. name
            return false
        end
        file:write(table.concat(by_file[name], "\n"), "\n")
        file:close()
    end
    Probe.written = Probe.written + #Probe.buffer
    Probe.buffer = {}
    Probe.last_error = nil
    return true
end

function Probe.on_frame()
    if not Probe.enabled then return end
    Probe.observe(Probe.read_p1())
    if #Probe.buffer >= Probe.FLUSH_RECORDS then Probe.flush() end
end

local function info(message)
    pcall(function() log.info("[SF6CC Transition Probe] " .. message) end)
end

_G.SF6CC_TransitionProbe = Probe

if existing ~= nil and register then
    -- Running the file again toggles recording; leaving recording saves.
    Probe.enabled = not Probe.enabled
    local saved = true
    if not Probe.enabled then saved = Probe.flush() end
    info(string.format("recording=%s written=%d pending=%d%s", tostring(Probe.enabled),
        Probe.written, #Probe.buffer, saved and "" or (" error=" .. tostring(Probe.last_error))))
    return Probe
end

if register then
    re.on_frame(function() pcall(Probe.on_frame) end)
    re.on_draw_ui(function()
        if imgui.tree_node("SF6CC Transition Probe") then
            imgui.text(string.format("recording=%s  written=%d  pending=%d",
                tostring(Probe.enabled), Probe.written, #Probe.buffer))
            if Probe.last_error then imgui.text("error: " .. tostring(Probe.last_error)) end
            local changed, value = imgui.checkbox("Recording", Probe.enabled)
            if changed then
                Probe.enabled = value
                if not value then Probe.flush() end
            end
            if imgui.button("Save now") then Probe.flush() end
            imgui.tree_pop()
        end
    end)
    info("recording=true")
end

return Probe
