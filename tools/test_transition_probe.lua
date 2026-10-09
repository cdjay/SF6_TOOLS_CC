-- Offline check of the transition probe with a fake engine: one record per
-- Action change, the previous Action's last frame, engine values copied, and
-- JSONL output per fighter.

local function managed(fields, calls)
    local object = { __fields = fields or {} }
    function object:get_field(name) return self.__fields[name] end
    function object:call(name) return calls and calls[name] and calls[name]() end
    function object:get_type_definition()
        return { get_field = function(_, name)
            return { get_data = function(_, value) return value.__fields[name] end }
        end }
    end
    return object
end

local state = { act = 600, frame = 0, flags = 0, code = 600, branch = 0, input = 0, sw = 16 }
local engine = managed({}, {
    get_ActionID = function() return state.act end,
    get_ActionFrame = function() return managed({ v = state.frame * 65536 }) end,
})
local param = managed({})
engine.__fields.mParam = param
local act_param = managed({})
act_param.__fields.ActionPart = managed({ _Engine = engine })
local key_input = managed({})
local branch = managed({})
act_param.__fields.KeyInput = key_input
act_param.__fields.Branch = branch
local p1 = managed({})
p1.__fields.mpActParam = act_param
local players = managed({ mPlayerType = { [0] = 12 }, mcPlayer = { [0] = p1 } })
local function sync()
    param.__fields.state_flags = state.flags
    key_input.__fields.Action = state.code
    branch.__fields.BranchType = state.branch
    p1.__fields.pl_input_new = state.input
    p1.__fields.pl_sw_new = state.sw
end

local files = {}
local previous = { sdk = sdk, json = json, io = io, fs = fs }
sdk = { find_type_definition = function(name)
    assert(name == "gBattle")
    return { get_field = function(_, field_name)
        assert(field_name == "Player")
        return { get_data = function() return players end }
    end }
end }
json = nil
fs = { create_dir = function() end }
io = { open = function(name, mode)
    assert(mode == "ab")
    files[name] = files[name] or {}
    return { write = function(_, ...) for _, part in ipairs({ ... }) do table.insert(files[name], part) end end,
        close = function() end }
end }

_G.SF6CC_TRANSITION_PROBE_NO_REGISTER = true
_G.SF6CC_TransitionProbe = nil
local Probe = assert(loadfile("tools/acbcm_exporter/SF6CC_Transition_Probe.lua"))()

sync()
assert(Probe.observe(Probe.read_p1()).act == 600, "the first sample is recorded")
for frame = 1, 5 do state.frame = frame; sync(); assert(Probe.observe(Probe.read_p1()) == nil) end
state.act, state.frame, state.flags, state.code, state.branch = 717, 0, 16, 0, 0x2000003F
sync()
local record = Probe.observe(Probe.read_p1())
assert(record.prev == 600 and record.prev_frame == 5, "the previous Action's last observed frame")
assert(record.act == 717 and record.flags == 16 and record.code == 0 and record.branch == 0x2000003F)
assert(record.fighter == 12 and record.sw == 16)
assert(Probe.flush())
local text = table.concat(files["SF6CC_ACBCM/transitions-f012.jsonl"], "")
assert(select(2, text:gsub("\n", "")) == 2, "one line per change")
assert(text:find('"act":717', 1, true) and text:find('"branch":536870975', 1, true))
assert(#Probe.buffer == 0 and Probe.written == 2)

-- A host json.dump_string (two return values from gsub broke the first
-- version) is not used: lines are encoded from plain numbers.
json = { dump_string = function() error("must not be called") end }
state.act, state.frame = 600, 3
sync()
Probe.observe(Probe.read_p1())
assert(Probe.flush() and Probe.written == 3)

-- An older probe left running upgrades in place: a newer copy keeps its
-- unsaved records, toggles recording off and saves them.
_G.SF6CC_TRANSITION_PROBE_NO_REGISTER = nil
local old_probe = {
    enabled = true, frame = 9, written = 0, last = nil,
    buffer = { { t = 1, fighter = 32, prev = 600, prev_frame = 4, act = 949, frame = 0, flags = 16, code = 949, branch = 0, input = 0, sw = 0 } },
    flush = function() error("old flush") end,
}
_G.SF6CC_TransitionProbe = old_probe
log = { info = function() end }
local upgraded = assert(loadfile("tools/acbcm_exporter/SF6CC_Transition_Probe.lua"))()
assert(upgraded == old_probe and upgraded.version == 2, "the running probe table is reused")
assert(upgraded.enabled == false and #upgraded.buffer == 0 and upgraded.written == 1)
assert(table.concat(files["SF6CC_ACBCM/transitions-f032.jsonl"], ""):find('"act":949', 1, true))

sdk, json, io, fs = previous.sdk, previous.json, previous.io, previous.fs
_G.SF6CC_TRANSITION_PROBE_NO_REGISTER = nil
_G.SF6CC_TransitionProbe = nil
print("transition probe tests passed")
