package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Checkpoint = require("func/ComboTrials/ComboAttemptCheckpoint")

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[deep_copy(key, seen)] = deep_copy(child, seen) end
    return result
end

local function test_hash(value)
    local accumulator = 2166136261
    for index = 1, #value do
        accumulator = ((accumulator ~ value:byte(index)) * 16777619) & 0xffffffff
    end
    return string.format("%08x", accumulator):rep(8)
end

local function assert_exact_keys(value, expected, label)
    local count = 0
    for key in pairs(value) do
        assert(expected[key], label .. " contains unexpected field: " .. tostring(key))
        count = count + 1
    end
    local expected_count = 0
    for key in pairs(expected) do
        expected_count = expected_count + 1
        assert(value[key] ~= nil, label .. " is missing field: " .. tostring(key))
    end
    assert(count == expected_count, label .. " field count changed")
end

local function new_harness()
    local harness = {
        files = {},
        decoded = {},
        failed_paths = {},
        probe_errors = {},
        temps = {},
        write_count = 0,
        epoch_count = 0,
        event_count = 0
    }
    harness.deps = {
        read = function(path) return harness.files[path] end,
        probe = function(path)
            if harness.probe_errors[path] then return nil, harness.probe_errors[path] end
            return harness.files[path] ~= nil and "exists" or "missing"
        end,
        read_events = function() return harness.files[Checkpoint.EVENTS_FILE] end,
        atomic_write = function(path, bytes)
            harness.write_count = harness.write_count + 1
            local temp = path .. ".tmp.test-" .. tostring(harness.write_count)
            harness.temps[temp] = bytes:sub(1, math.max(1, math.floor(#bytes / 2)))
            if harness.failed_paths[path] then return false, "injected replace failure" end
            harness.files[path] = bytes
            harness.temps[temp] = nil
            return true
        end,
        decode = function(raw)
            local decoded = harness.decoded[raw]
            if not decoded then error("fixture decoder rejected unknown bytes") end
            return deep_copy(decoded)
        end,
        sha256 = test_hash,
        new_epoch = function()
            harness.epoch_count = harness.epoch_count + 1
            return "0123456789abcdef0123456789abcdef"
        end
    }

    function harness:new_event(options)
        options = options or {}
        self.event_count = self.event_count + 1
        return {
            schema = "sf6cc.combo_attempt.v1",
            event_id = string.format("%064x", self.event_count),
            occurred_at = "2026-08-11T10:00:00Z",
            combo = {
                combo_id = options.combo_id or "fixture.combo",
                revision_hash = options.revision or ("sha256:" .. string.rep("a", 64)),
                identity_schema = "sf6cc.combo_identity.v1",
                title = options.title or "Fixture Combo",
                character = options.character or "ryu",
                sequence_length = options.sequence_length or 4
            },
            runtime = {
                player_control = options.control or "classic",
                position_side = options.side or "p1",
                source = options.source or "manual"
            },
            result = { outcome = options.outcome or "fail" }
        }
    end

    function harness:append(event)
        local line = '{"fixtureEvent":"' .. event.event_id .. '"}'
        self.decoded[line] = deep_copy(event)
        self.files[Checkpoint.EVENTS_FILE] = (self.files[Checkpoint.EVENTS_FILE] or "") .. line .. "\n"
        return line
    end

    function harness:record(producer, event)
        self:append(event)
        return producer:record_event(event)
    end

    function harness:remember(producer)
        self.decoded[self.files[Checkpoint.STATE_FILE]] = deep_copy(producer.state)
        local checkpoint_raw = self.files[Checkpoint.OUTPUT_FILE]
        if checkpoint_raw and not self.decoded[checkpoint_raw] then
            self.decoded[checkpoint_raw] = {
                schema = Checkpoint.SCHEMA,
                producerEpoch = producer.state.producerEpoch,
                checkpointSequence = producer.state.checkpointSequence,
                items = deep_copy(producer.state.items)
            }
        end
    end
    return harness
end

local harness = new_harness()
local producer = Checkpoint.new(harness.deps)
local initialized, initial_bytes = producer:initialize()
assert(initialized, initial_bytes)
assert(producer.state.checkpointSequence == 1 and #producer.state.items == 0,
    "initial checkpoint must be empty with sequence one")
assert(producer.state.historyStart == "all_time_v1"
    and producer.state.baselineCursor == "origin"
    and producer.state.legacyCursor == "origin", "initial WAL anchor invalid")
assert(initial_bytes == '{"schema":"sf6cc.combo_attempt_checkpoint.v1",'
    .. '"producerEpoch":"0123456789abcdef0123456789abcdef",'
    .. '"checkpointSequence":1,"items":[]}', "initial bytes must be canonical")
harness:remember(producer)

local republished, republished_bytes = producer:republish()
assert(republished and republished_bytes == initial_bytes, "republish must be byte-identical")
assert(producer.state.checkpointSequence == 1, "republish must not advance sequence")

local first_failure = harness:new_event({ outcome = "fail" })
assert(harness:record(producer, first_failure))
harness:remember(producer)
assert(producer.state.checkpointSequence == 2
    and producer.state.items[1].attempts == 1
    and producer.state.items[1].successes == 0, "failure counters must increment")

local first_success = harness:new_event({ outcome = "success" })
assert(harness:record(producer, first_success))
local modern_p1 = harness:new_event({ control = "modern", outcome = "success" })
local classic_p2 = harness:new_event({ side = "p2", outcome = "fail" })
local modern_p2 = harness:new_event({ control = "modern", side = "p2", outcome = "success" })
assert(harness:record(producer, modern_p1))
assert(harness:record(producer, classic_p2))
assert(harness:record(producer, modern_p2))
harness:remember(producer)
assert(producer.state.items[1].attempts == 2 and producer.state.items[1].successes == 1,
    "success counters must increment")
assert(#producer.state.items == 4, "control and side dimensions must remain distinct")

local restart_bytes = harness.files[Checkpoint.OUTPUT_FILE]
local restart_epoch = producer.state.producerEpoch
local restart_sequence = producer.state.checkpointSequence
local restarted = Checkpoint.new(harness.deps)
assert(restarted:initialize(), "restart must load durable state")
assert(restarted.state.producerEpoch == restart_epoch
    and restarted.state.checkpointSequence == restart_sequence,
    "restart must preserve epoch and counters")
assert(harness.files[Checkpoint.OUTPUT_FILE] == restart_bytes,
    "restart must preserve deterministic checkpoint bytes")
harness:remember(restarted)

-- Crash after legacy append but before checkpoint state write: startup replays it.
local append_only = harness:new_event({ outcome = "success" })
harness:append(append_only)
local replayed = Checkpoint.new(harness.deps)
assert(replayed:initialize(), "startup must replay an appended, unapplied event")
assert(replayed.state.legacyCursor == append_only.event_id
    and replayed.state.checkpointSequence == restart_sequence + 1,
    "append-before-state crash must advance exactly once")
harness:remember(replayed)
local replayed_attempts = replayed.state.items[1].attempts
local duplicate_restart = Checkpoint.new(harness.deps)
assert(duplicate_restart:initialize(), "duplicate restart must remain valid")
assert(duplicate_restart.state.items[1].attempts == replayed_attempts
    and duplicate_restart.state.checkpointSequence == replayed.state.checkpointSequence,
    "duplicate restart must not double count replayed events")
harness:remember(duplicate_restart)

-- Legacy append succeeds, state write fails, restart replays from the old cursor.
local state_failure_event = harness:new_event({ outcome = "fail" })
harness:append(state_failure_event)
local state_before_failure = harness.files[Checkpoint.STATE_FILE]
local checkpoint_before_failure = harness.files[Checkpoint.OUTPUT_FILE]
harness.failed_paths[Checkpoint.STATE_FILE] = true
assert(not duplicate_restart:record_event(state_failure_event), "injected state write must fail")
assert(harness.files[Checkpoint.STATE_FILE] == state_before_failure
    and harness.files[Checkpoint.OUTPUT_FILE] == checkpoint_before_failure,
    "state write failure must preserve durable files")
harness.failed_paths[Checkpoint.STATE_FILE] = nil
local recovered_state_failure = Checkpoint.new(harness.deps)
assert(recovered_state_failure:initialize(), "restart must replay after state write failure")
assert(recovered_state_failure.state.legacyCursor == state_failure_event.event_id,
    "state write failure event must become durable after restart")
local recovered_failure_attempts = recovered_state_failure.state.items[1].attempts
harness:remember(recovered_state_failure)
local no_double_recovery = Checkpoint.new(harness.deps)
assert(no_double_recovery:initialize())
assert(no_double_recovery.state.items[1].attempts == recovered_failure_attempts,
    "recovered state failure event must not double count")
harness:remember(no_double_recovery)

-- State is durable but checkpoint replace failed; unreadability must perform zero writes.
local checkpoint_failure_event = harness:new_event({ outcome = "success" })
harness:append(checkpoint_failure_event)
harness.failed_paths[Checkpoint.OUTPUT_FILE] = true
local old_checkpoint = harness.files[Checkpoint.OUTPUT_FILE]
assert(not no_double_recovery:record_event(checkpoint_failure_event))
assert(harness.files[Checkpoint.OUTPUT_FILE] == old_checkpoint,
    "failed checkpoint replace must preserve the last valid checkpoint")
harness:remember(no_double_recovery)
harness.failed_paths[Checkpoint.OUTPUT_FILE] = nil
local writes_before_probe_error = harness.write_count
local epochs_before_probe_error = harness.epoch_count
harness.probe_errors[Checkpoint.OUTPUT_FILE] = "injected sharing violation"
local unreadable_checkpoint = Checkpoint.new(harness.deps)
assert(not unreadable_checkpoint:initialize(), "checkpoint probe error must fail closed")
assert(harness.write_count == writes_before_probe_error
    and harness.epoch_count == epochs_before_probe_error,
    "temporary unreadability must generate no epoch and perform no writes")
harness.probe_errors[Checkpoint.OUTPUT_FILE] = nil
local repaired_checkpoint = Checkpoint.new(harness.deps)
assert(repaired_checkpoint:initialize(), "durable state must repair the older checkpoint")
harness:remember(repaired_checkpoint)

local state_probe_harness = new_harness()
local state_probe_source = Checkpoint.new(state_probe_harness.deps)
assert(state_probe_source:initialize())
state_probe_harness:remember(state_probe_source)
local state_probe_writes = state_probe_harness.write_count
local state_probe_epochs = state_probe_harness.epoch_count
local state_probe_state = state_probe_harness.files[Checkpoint.STATE_FILE]
local state_probe_checkpoint = state_probe_harness.files[Checkpoint.OUTPUT_FILE]
state_probe_harness.probe_errors[Checkpoint.STATE_FILE] = "injected access denied"
assert(not Checkpoint.new(state_probe_harness.deps):initialize(), "state probe error must fail closed")
assert(state_probe_harness.epoch_count == state_probe_epochs
    and state_probe_harness.write_count == state_probe_writes
    and state_probe_harness.files[Checkpoint.STATE_FILE] == state_probe_state
    and state_probe_harness.files[Checkpoint.OUTPUT_FILE] == state_probe_checkpoint,
    "state probe error must generate no epoch, write nothing, and preserve durable files")

local checkpoint_probe_harness = new_harness()
checkpoint_probe_harness.probe_errors[Checkpoint.OUTPUT_FILE] = "injected access denied"
assert(not Checkpoint.new(checkpoint_probe_harness.deps):initialize(),
    "checkpoint probe error must fail closed")
assert(checkpoint_probe_harness.epoch_count == 0 and checkpoint_probe_harness.write_count == 0,
    "checkpoint probe error must generate no epoch and perform no writes")

local events_probe_harness = new_harness()
events_probe_harness.probe_errors[Checkpoint.EVENTS_FILE] = "injected access denied"
assert(not Checkpoint.new(events_probe_harness.deps):initialize(),
    "legacy WAL probe error must fail closed")
assert(events_probe_harness.epoch_count == 0 and events_probe_harness.write_count == 0,
    "legacy WAL probe error must generate no epoch and perform no writes")

-- First installation anchors after unmarked legacy history instead of claiming it.
local baseline_harness = new_harness()
local historical = baseline_harness:new_event({ outcome = "success" })
baseline_harness:append(historical)
local baseline_producer = Checkpoint.new(baseline_harness.deps)
assert(baseline_producer:initialize())
assert(#baseline_producer.state.items == 0
    and baseline_producer.state.baselineCursor == historical.event_id
    and baseline_producer.state.legacyCursor == historical.event_id,
    "pre-existing legacy events must become an explicit all_time_v1 baseline")
baseline_harness:remember(baseline_producer)
local post_baseline = baseline_harness:new_event({ outcome = "success" })
assert(baseline_harness:record(baseline_producer, post_baseline))
assert(baseline_producer.state.items[1].attempts == 1,
    "only events after the baseline may enter all_time_v1 counters")

local rotation_harness = new_harness()
local rotation_producer = Checkpoint.new(rotation_harness.deps)
assert(rotation_producer:initialize())
local retained = rotation_harness:new_event({ outcome = "success" })
assert(rotation_harness:record(rotation_producer, retained))
rotation_harness:remember(rotation_producer)
local replacement = rotation_harness:new_event({ outcome = "fail" })
rotation_harness.files[Checkpoint.EVENTS_FILE] = ""
rotation_harness:append(replacement)
local rotation_writes = rotation_harness.write_count
local rotation_epochs = rotation_harness.epoch_count
local rotation_state = rotation_harness.files[Checkpoint.STATE_FILE]
local rotation_checkpoint = rotation_harness.files[Checkpoint.OUTPUT_FILE]
assert(not Checkpoint.new(rotation_harness.deps):initialize(),
    "missing cursor after rotation must fail closed")
assert(rotation_harness.write_count == rotation_writes
    and rotation_harness.epoch_count == rotation_epochs
    and rotation_harness.files[Checkpoint.STATE_FILE] == rotation_state
    and rotation_harness.files[Checkpoint.OUTPUT_FILE] == rotation_checkpoint,
    "cursor loss must perform no writes or epoch changes")

local overflow_state = repaired_checkpoint.state.items[1]
local overflow_state_bytes = harness.files[Checkpoint.STATE_FILE]
local overflow_checkpoint_bytes = harness.files[Checkpoint.OUTPUT_FILE]
overflow_state.attempts = Checkpoint._test.limits.max_attempts
local overflow_event = harness:new_event({
    control = overflow_state.playerControl,
    side = overflow_state.positionSide,
    revision = overflow_state.revisionHash
})
harness:append(overflow_event)
assert(not repaired_checkpoint:record_event(overflow_event), "attempt overflow must fail bounded")
assert(harness.files[Checkpoint.STATE_FILE] == overflow_state_bytes
    and harness.files[Checkpoint.OUTPUT_FILE] == overflow_checkpoint_bytes,
    "overflow must not replace durable files")

local item_limit_harness = new_harness()
local item_limit_producer = Checkpoint.new(item_limit_harness.deps)
assert(item_limit_producer:initialize())
for index = 1, Checkpoint._test.limits.max_items do
    item_limit_producer.state.items[index] = {
        revisionHash = "sha256:" .. string.format("%064x", index),
        identitySchema = "sf6cc.combo_identity.v1",
        title = "Fixture " .. tostring(index),
        character = "ryu",
        playerControl = "classic",
        positionSide = "p1",
        sequenceLength = 1,
        attempts = 0,
        successes = 0,
        lastPlayedAt = 0
    }
end
local item_limit_state = item_limit_harness.files[Checkpoint.STATE_FILE]
local item_limit_checkpoint = item_limit_harness.files[Checkpoint.OUTPUT_FILE]
local item_limit_event = item_limit_harness:new_event({
    revision = "sha256:" .. string.rep("f", 64),
    outcome = "fail"
})
item_limit_harness:append(item_limit_event)
assert(not item_limit_producer:record_event(item_limit_event), "the 513th item must fail bounded")
assert(item_limit_harness.files[Checkpoint.STATE_FILE] == item_limit_state
    and item_limit_harness.files[Checkpoint.OUTPUT_FILE] == item_limit_checkpoint,
    "item bound failure must not replace durable files")

local checkpoint_bytes = harness.files[Checkpoint.OUTPUT_FILE]
local state_bytes = harness.files[Checkpoint.STATE_FILE]
for _, forbidden in ipairs({
    "raw input", "raw_input", "replay", "failure_reason", "failure_code",
    "account", "machine", "cookie", "token", "file_path", "local_filename"
}) do
    assert(not checkpoint_bytes:lower():find(forbidden, 1, true),
        "checkpoint contains forbidden content: " .. forbidden)
    assert(not state_bytes:lower():find(forbidden, 1, true),
        "durable state contains forbidden content: " .. forbidden)
end
assert(#checkpoint_bytes <= Checkpoint._test.limits.max_file_bytes)

-- Integration: append-before-checkpoint, terminal dedup, auto-demo exclusion, append failure.
package.loaded["func/ComboTrials/Telemetry"] = nil
local integration_files = {}
local integration_events = ""
local fail_legacy_append = false
local original_open = io.open
fs = {
    create_dir = function() return true end,
    read = function(path) return integration_files[path] end
}
json = { load_string = function() error("integration test does not restart state") end }
sf6cc_atomic_file = {
    random_epoch = function() return "fedcba9876543210fedcba9876543210" end,
    probe = function(path) return integration_files[path] ~= nil and "exists" or "missing" end,
    write = function(path, bytes) integration_files[path] = bytes return true end
}
io.open = function(path, mode)
    if path == Checkpoint.EVENTS_FILE and mode == "rb" then
        local raw = integration_files[path]
        if raw == nil then return nil, "missing" end
        local position = 0
        return {
            seek = function(_, whence, offset)
                if whence == "end" then position = #raw return position end
                if whence == "set" then position = offset or 0 return position end
            end,
            read = function() return raw end,
            close = function() return true end
        }
    end
    assert(path:find("events.jsonl", 1, true) and mode == "ab", "legacy output path changed")
    if fail_legacy_append then return nil, "injected append failure" end
    local pending = ""
    return {
        write = function(_, ...) pending = pending .. table.concat({ ... }) end,
        flush = function()
            integration_events = integration_events .. pending
            integration_files[Checkpoint.EVENTS_FILE] = integration_events
            pending = ""
            return true
        end,
        close = function() return true end
    }
end

local Telemetry = require("func/ComboTrials/Telemetry")
local context = {
    sequence = { { action_id = 100, _xt_meta = { character = "ryu", combo_id = "integration.combo" } } },
    character = "ryu",
    declared_control = "classic",
    player_control = "classic",
    position_side = "p1",
    source = "manual",
    engine_frame = 100
}
Telemetry.begin_attempt(context)
local manual_ok, manual_event = Telemetry.finish_attempt("success", { engine_frame = 120 })
assert(manual_ok, "manual event must append")
assert_exact_keys(manual_event, {
    schema = true, event_id = true, anonymous = true, occurred_at = true,
    started_at = true, combo = true, runtime = true, result = true
}, "legacy event")
assert_exact_keys(manual_event.combo, {
    combo_id = true, revision_hash = true, identity_schema = true, title = true,
    character = true, declared_control = true, sequence_length = true
}, "legacy combo")
assert_exact_keys(manual_event.runtime, {
    sf6cc_version = true, player_control = true, projection = true,
    position_mode = true, position_side = true, source = true
}, "legacy runtime")
assert_exact_keys(manual_event.result, {
    outcome = true, total_steps = true, elapsed_frames = true
}, "legacy result")
assert(not integration_events:find("checkpoint_history", 1, true),
    "legacy JSONL must not gain a checkpoint marker field")
assert(not Telemetry.finish_attempt("success", { engine_frame = 121 }),
    "same terminal attempt must not double count")
local integration_producer = Telemetry.get_checkpoint_producer()
assert(integration_producer.state.items[1].attempts == 1
    and integration_producer.state.items[1].successes == 1,
    "terminal retry must not duplicate checkpoint counters")
local manual_sequence = integration_producer.state.checkpointSequence

context.source = "auto_demo"
Telemetry.begin_attempt(context)
assert(Telemetry.finish_attempt("success", { engine_frame = 140 }), "auto-demo legacy event must append")
assert(integration_producer.state.checkpointSequence == manual_sequence,
    "auto-demo must advance only the WAL cursor")

local attempts_before_append_failure = integration_producer.state.items[1].attempts
local cursor_before_append_failure = integration_producer.state.legacyCursor
fail_legacy_append = true
context.source = "manual"
Telemetry.begin_attempt(context)
assert(not Telemetry.finish_attempt("fail", { engine_frame = 160 }),
    "legacy append failure must remain visible")
assert(integration_producer.state.items[1].attempts == attempts_before_append_failure
    and integration_producer.state.legacyCursor == cursor_before_append_failure,
    "legacy append failure must not count or advance the cursor")
fail_legacy_append = false

local _, event_count = integration_events:gsub("\n", "\n")
assert(event_count == 2, "legacy events.jsonl must continue receiving successful terminal events")
io.open = original_open

print("combo attempt checkpoint tests passed")
