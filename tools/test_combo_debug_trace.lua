package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local writes = 0
json = {
    dump_file = function()
        writes = writes + 1
        return true
    end,
}

CT_DIAGNOSTIC_TRACE = false
CT_VERIFY_TRACE = false
CT_STATE_DUMP_TRACE = false

package.loaded["func/ComboTrials/DebugTrace"] = nil
local DebugTrace = require("func/ComboTrials/DebugTrace")

local disabled = {}
DebugTrace.record_validation_debug(disabled, { branch = "disabled" })
DebugTrace.record_auto_advance(disabled, { branch = "disabled" })
DebugTrace.record_step_confirmation(disabled, { step = 1 })
DebugTrace.record_visual_step_state(disabled, { validation_step = 1, visual_step = 1 })
DebugTrace.record_match_probe(disabled, { expected_id = 100 })
DebugTrace.record_last_fail(disabled, { failed = true }, "ignored.json")
assert(disabled._validation_debug == nil, "disabled diagnostics stored validation state")
assert(disabled._auto_advance_debug == nil, "disabled diagnostics stored auto-advance state")
assert(disabled._step_confirmation_trace == nil, "disabled diagnostics stored confirmation history")
assert(disabled._visual_step_trace == nil, "disabled diagnostics stored visual history")
assert(disabled._match_probe_history == nil, "disabled diagnostics stored match history")
assert(writes == 0, "disabled diagnostics wrote a file")

CT_DIAGNOSTIC_TRACE = true
local enabled = {}
DebugTrace.record_validation_debug(enabled, { branch = "enabled" })
DebugTrace.record_auto_advance(enabled, { branch = "enabled" })
DebugTrace.record_step_confirmation(enabled, { step = 1 })
DebugTrace.record_visual_step_state(enabled, { validation_step = 1, visual_step = 1 })
DebugTrace.record_match_probe(enabled, { expected_id = 100 })
DebugTrace.record_last_fail(enabled, { failed = true }, "LastFail.json")
assert(enabled._validation_debug.branch == "enabled", "enabled validation trace missing")
assert(enabled._auto_advance_debug.branch == "enabled", "enabled auto-advance trace missing")
assert(#enabled._step_confirmation_trace == 1, "enabled confirmation trace missing")
assert(#enabled._visual_step_trace == 1, "enabled visual trace missing")
assert(#enabled._match_probe_history == 1, "enabled match trace missing")
assert(writes == 1, "enabled failure trace was not written exactly once")

CT_DIAGNOSTIC_TRACE = false
local audit = { _runtime_auditing = true }
DebugTrace.record_step_confirmation(audit, { step = 2 })
DebugTrace.record_match_probe(audit, { expected_id = 200 })
assert(#audit._step_confirmation_trace == 1, "runtime audit confirmation trace missing")
assert(#audit._match_probe_history == 1, "runtime audit match trace missing")

print("combo debug trace tests passed")
