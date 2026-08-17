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
        files = {}, decoded = {}, failed_paths = {}, probe_errors = {},
        temps = {}, write_count = 0, epoch_count = 0, event_count = 0,
        probed_paths = {}
    }
    harness.deps = {
        read = function(path) return harness.files[path] end,
        probe = function(path)
            harness.probed_paths[path] = true
            if harness.probe_errors[path] then return nil, harness.probe_errors[path] end
            return harness.files[path] ~= nil and "exists" or "missing"
        end,
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

    function harness:remember(producer)
        local state_raw = self.files[Checkpoint.STATE_FILE]
        if state_raw then self.decoded[state_raw] = deep_copy(producer.state) end
        local pending_raw = self.files[Checkpoint.PENDING_FILE]
        if pending_raw then self.decoded[pending_raw] = deep_copy(producer.pending) end
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

    function harness:apply(producer, event)
        local prepared, should_commit = producer:prepare_event(event)
        if not prepared then return false, should_commit end
        if not should_commit then return true end
        return producer:commit_pending(event.event_id)
    end
    return harness
end

local harness = new_harness()
local producer = Checkpoint.new(harness.deps)
local initialized, initial_bytes = producer:initialize()
assert(initialized, initial_bytes)
assert(producer.state.historyStart == "all_time_v1"
    and producer.state.lastAppliedEventId == "origin"
    and producer.state.checkpointSequence == 1
    and #producer.state.items == 0, "initial durable state invalid")
assert(producer.pending.status == "empty", "initial pending journal must be canonical empty")
assert(initial_bytes == '{"schema":"sf6cc.combo_attempt_checkpoint.v1",'
    .. '"producerEpoch":"0123456789abcdef0123456789abcdef",'
    .. '"checkpointSequence":1,"items":[]}', "initial checkpoint bytes changed")
harness:remember(producer)

local republished, republished_bytes = producer:republish()
assert(republished and republished_bytes == initial_bytes)
assert(producer.state.checkpointSequence == 1, "republish must not advance sequence")

local first_failure = harness:new_event({ outcome = "fail" })
local state_before_pending = harness.files[Checkpoint.STATE_FILE]
local prepared, should_commit = producer:prepare_event(first_failure)
assert(prepared and should_commit and producer.pending.eventId == first_failure.event_id,
    "manual fact must enter pending before counting")
assert(harness.files[Checkpoint.STATE_FILE] == state_before_pending,
    "pending publication must not mutate cumulative state")
assert(producer:commit_pending(first_failure.event_id))
harness:remember(producer)
assert(producer.pending.status == "empty"
    and producer.state.lastAppliedEventId == first_failure.event_id
    and producer.state.items[1].attempts == 1
    and producer.state.items[1].successes == 0, "first failure did not commit")

local first_success = harness:new_event({ outcome = "success" })
assert(harness:apply(producer, first_success))
assert(harness:apply(producer, harness:new_event({ control = "modern", outcome = "success" })))
assert(harness:apply(producer, harness:new_event({ side = "p2", outcome = "fail" })))
assert(harness:apply(producer, harness:new_event({ control = "modern", side = "p2", outcome = "success" })))
harness:remember(producer)
assert(producer.state.items[1].attempts == 2 and producer.state.items[1].successes == 1)
assert(#producer.state.items == 4, "classic/modern and p1/p2 must remain distinct")

local restart_epoch = producer.state.producerEpoch
local restart_sequence = producer.state.checkpointSequence
local restart_checkpoint = harness.files[Checkpoint.OUTPUT_FILE]
local restarted = Checkpoint.new(harness.deps)
assert(restarted:initialize(), "normal restart must load empty pending and durable state")
assert(restarted.state.producerEpoch == restart_epoch
    and restarted.state.checkpointSequence == restart_sequence
    and harness.files[Checkpoint.OUTPUT_FILE] == restart_checkpoint,
    "normal restart must preserve epoch, sequence, counters, and deterministic bytes")
producer = restarted
harness:remember(producer)

local duplicate_sequence = producer.state.checkpointSequence
local duplicate_prepared, duplicate_should_commit = producer:prepare_event(
    harness:new_event({ outcome = "success" })
)
assert(duplicate_prepared and duplicate_should_commit)
local duplicate_event_id = producer.pending.eventId
assert(producer:commit_pending(duplicate_event_id))
harness:remember(producer)
local duplicate_again, duplicate_commit = producer:prepare_event({
    schema = "sf6cc.combo_attempt.v1", event_id = duplicate_event_id,
    occurred_at = "2026-08-11T10:00:00Z",
    combo = {
        combo_id = "fixture.combo", revision_hash = "sha256:" .. string.rep("a", 64),
        identity_schema = "sf6cc.combo_identity.v1", title = "Fixture Combo",
        character = "ryu", sequence_length = 4
    },
    runtime = { player_control = "classic", position_side = "p1", source = "manual" },
    result = { outcome = "success" }
})
assert(duplicate_again and duplicate_commit == false
    and producer.state.checkpointSequence == duplicate_sequence + 1,
    "lastAppliedEventId must deduplicate the same event")

-- Crash after pending write and before state write.
local pending_crash = harness:new_event({ outcome = "success" })
assert(producer:prepare_event(pending_crash))
harness:remember(producer)
local pending_crash_sequence = producer.state.checkpointSequence
local recovered_pending = Checkpoint.new(harness.deps)
assert(recovered_pending:initialize(), "pending event must recover after restart")
assert(recovered_pending.state.lastAppliedEventId == pending_crash.event_id
    and recovered_pending.state.checkpointSequence == pending_crash_sequence + 1
    and recovered_pending.pending.status == "empty", "pending recovery must apply exactly once")
harness:remember(recovered_pending)
local duplicate_recovery = Checkpoint.new(harness.deps)
assert(duplicate_recovery:initialize())
assert(duplicate_recovery.state.checkpointSequence == recovered_pending.state.checkpointSequence,
    "duplicate restart must not double count")
harness:remember(duplicate_recovery)

-- State write fails while pending remains durable; restart applies it.
local state_failure = harness:new_event({ outcome = "fail" })
assert(duplicate_recovery:prepare_event(state_failure))
harness:remember(duplicate_recovery)
local state_failure_raw = harness.files[Checkpoint.STATE_FILE]
harness.failed_paths[Checkpoint.STATE_FILE] = true
assert(not duplicate_recovery:commit_pending(state_failure.event_id))
assert(harness.files[Checkpoint.STATE_FILE] == state_failure_raw
    and duplicate_recovery.pending.status == "event", "state failure must retain pending")
harness.failed_paths[Checkpoint.STATE_FILE] = nil
local recovered_state_failure = Checkpoint.new(harness.deps)
assert(recovered_state_failure:initialize())
assert(recovered_state_failure.state.lastAppliedEventId == state_failure.event_id
    and recovered_state_failure.pending.status == "empty", "state failure was not replayed")
harness:remember(recovered_state_failure)

-- Checkpoint write fails after state: restart sees lastAppliedEventId and does not double count.
local checkpoint_failure = harness:new_event({ outcome = "success" })
assert(recovered_state_failure:prepare_event(checkpoint_failure))
harness:remember(recovered_state_failure)
local old_checkpoint = harness.files[Checkpoint.OUTPUT_FILE]
harness.failed_paths[Checkpoint.OUTPUT_FILE] = true
assert(not recovered_state_failure:commit_pending(checkpoint_failure.event_id))
assert(harness.files[Checkpoint.OUTPUT_FILE] == old_checkpoint
    and recovered_state_failure.state.lastAppliedEventId == checkpoint_failure.event_id
    and recovered_state_failure.pending.status == "event",
    "checkpoint failure must retain pending with already-applied state")
harness.failed_paths[Checkpoint.OUTPUT_FILE] = nil
harness:remember(recovered_state_failure)
local recovered_checkpoint_failure = Checkpoint.new(harness.deps)
assert(recovered_checkpoint_failure:initialize())
assert(recovered_checkpoint_failure.pending.status == "empty"
    and recovered_checkpoint_failure.state.lastAppliedEventId == checkpoint_failure.event_id,
    "checkpoint failure recovery must clear without double count")
harness:remember(recovered_checkpoint_failure)

-- Pending clear fails after checkpoint: restart republishes and clears without recounting.
local clear_failure = harness:new_event({ outcome = "fail" })
assert(recovered_checkpoint_failure:prepare_event(clear_failure))
harness:remember(recovered_checkpoint_failure)
harness.failed_paths[Checkpoint.PENDING_FILE] = true
assert(not recovered_checkpoint_failure:commit_pending(clear_failure.event_id))
assert(recovered_checkpoint_failure.state.lastAppliedEventId == clear_failure.event_id
    and recovered_checkpoint_failure.pending.status == "event", "clear failure must retain event")
harness.failed_paths[Checkpoint.PENDING_FILE] = nil
harness:remember(recovered_checkpoint_failure)
local clear_recovered = Checkpoint.new(harness.deps)
local clear_sequence = recovered_checkpoint_failure.state.checkpointSequence
assert(clear_recovered:initialize())
assert(clear_recovered.pending.status == "empty"
    and clear_recovered.state.checkpointSequence == clear_sequence,
    "clear recovery must not double count")
harness:remember(clear_recovered)

-- Malformed pending preserves checkpoint and performs no writes.
local malformed_checkpoint = harness.files[Checkpoint.OUTPUT_FILE]
local malformed_writes = harness.write_count
harness.files[Checkpoint.PENDING_FILE] = "{malformed"
local malformed = Checkpoint.new(harness.deps)
assert(not malformed:initialize(), "malformed pending must fail closed")
assert(harness.files[Checkpoint.OUTPUT_FILE] == malformed_checkpoint
    and harness.write_count == malformed_writes, "malformed pending must preserve checkpoint")
harness.files[Checkpoint.PENDING_FILE] = Checkpoint._test.encode_pending(clear_recovered.pending)
harness:remember(clear_recovered)

for _, path in ipairs({ Checkpoint.STATE_FILE, Checkpoint.OUTPUT_FILE, Checkpoint.PENDING_FILE }) do
    local probe_harness = new_harness()
    local probe_source = Checkpoint.new(probe_harness.deps)
    assert(probe_source:initialize())
    probe_harness:remember(probe_source)
    local writes_before = probe_harness.write_count
    local epochs_before = probe_harness.epoch_count
    local state_before = probe_harness.files[Checkpoint.STATE_FILE]
    local checkpoint_before = probe_harness.files[Checkpoint.OUTPUT_FILE]
    local pending_before = probe_harness.files[Checkpoint.PENDING_FILE]
    probe_harness.probe_errors[path] = "injected access denied"
    assert(not Checkpoint.new(probe_harness.deps):initialize(),
        "probe error must fail closed for " .. path)
    assert(probe_harness.write_count == writes_before
        and probe_harness.epoch_count == epochs_before
        and probe_harness.files[Checkpoint.STATE_FILE] == state_before
        and probe_harness.files[Checkpoint.OUTPUT_FILE] == checkpoint_before
        and probe_harness.files[Checkpoint.PENDING_FILE] == pending_before,
        "probe error must perform no writes or epoch changes")
end

-- Legacy JSONL lifecycle is independent: missing, rotated, or huge files are never probed.
local legacy_path = "SF6_TrainingRemoteControl_data/ComboTrialTelemetry/events.jsonl"
harness.files[legacy_path] = string.rep("x", 16777217)
harness.probe_errors[legacy_path] = "must not be observed"
harness.probed_paths = {}
local legacy_independent = Checkpoint.new(harness.deps)
assert(legacy_independent:initialize(), "oversized legacy log must not block producer startup")
assert(not harness.probed_paths[legacy_path], "formal producer must not probe legacy JSONL")
harness:remember(legacy_independent)
harness.files[legacy_path] = nil
local legacy_missing = Checkpoint.new(harness.deps)
assert(legacy_missing:initialize(), "missing or rotated legacy log must not block startup")
harness:remember(legacy_missing)

-- Bounds: total attempts, item count, and resulting checkpoint bytes.
local total_bound_state = legacy_missing.state.items[1]
local total_bound_state_raw = harness.files[Checkpoint.STATE_FILE]
local total_bound_checkpoint_raw = harness.files[Checkpoint.OUTPUT_FILE]
total_bound_state.attempts = Checkpoint._test.limits.max_attempts
local total_bound_event = harness:new_event({
    control = total_bound_state.playerControl, side = total_bound_state.positionSide,
    revision = total_bound_state.revisionHash
})
assert(legacy_missing:prepare_event(total_bound_event))
assert(not legacy_missing:commit_pending(total_bound_event.event_id), "attempt overflow must fail")
assert(harness.files[Checkpoint.STATE_FILE] == total_bound_state_raw
    and harness.files[Checkpoint.OUTPUT_FILE] == total_bound_checkpoint_raw)

local aggregate_harness = new_harness()
local aggregate_producer = Checkpoint.new(aggregate_harness.deps)
assert(aggregate_producer:initialize())
aggregate_producer.state.items = {
    {
        revisionHash = "sha256:" .. string.rep("1", 64),
        identitySchema = "sf6cc.combo_identity.v1", title = "First",
        character = "ryu", playerControl = "classic", positionSide = "p1",
        sequenceLength = 1, attempts = 5000000, successes = 0, lastPlayedAt = 0
    },
    {
        revisionHash = "sha256:" .. string.rep("2", 64),
        identitySchema = "sf6cc.combo_identity.v1", title = "Second",
        character = "ryu", playerControl = "classic", positionSide = "p1",
        sequenceLength = 1, attempts = 5000000, successes = 0, lastPlayedAt = 0
    }
}
local aggregate_state_raw = aggregate_harness.files[Checkpoint.STATE_FILE]
local aggregate_checkpoint_raw = aggregate_harness.files[Checkpoint.OUTPUT_FILE]
local aggregate_event = aggregate_harness:new_event({
    revision = "sha256:" .. string.rep("1", 64), outcome = "fail"
})
assert(aggregate_producer:prepare_event(aggregate_event))
assert(not aggregate_producer:commit_pending(aggregate_event.event_id),
    "aggregate attempts above 10,000,000 must fail independently of per-item bounds")
assert(aggregate_harness.files[Checkpoint.STATE_FILE] == aggregate_state_raw
    and aggregate_harness.files[Checkpoint.OUTPUT_FILE] == aggregate_checkpoint_raw)

local item_harness = new_harness()
local item_producer = Checkpoint.new(item_harness.deps)
assert(item_producer:initialize())
for index = 1, Checkpoint._test.limits.max_items do
    item_producer.state.items[index] = {
        revisionHash = "sha256:" .. string.format("%064x", index),
        identitySchema = "sf6cc.combo_identity.v1", title = "Fixture",
        character = "ryu", playerControl = "classic", positionSide = "p1",
        sequenceLength = 1, attempts = 0, successes = 0, lastPlayedAt = 0
    }
end
local item_state_raw = item_harness.files[Checkpoint.STATE_FILE]
local item_checkpoint_raw = item_harness.files[Checkpoint.OUTPUT_FILE]
local item_event = item_harness:new_event({ revision = "sha256:" .. string.rep("f", 64) })
assert(item_producer:prepare_event(item_event))
assert(not item_producer:commit_pending(item_event.event_id), "513th item must fail")
assert(item_harness.files[Checkpoint.STATE_FILE] == item_state_raw
    and item_harness.files[Checkpoint.OUTPUT_FILE] == item_checkpoint_raw)

local size_harness = new_harness()
local size_producer = Checkpoint.new(size_harness.deps)
assert(size_producer:initialize())
local wide = string.rep("\240\159\152\128", 240)
local wide_character = string.rep("\240\159\152\128", 64)
for index = 1, Checkpoint._test.limits.max_items do
    size_producer.state.items[index] = {
        comboId = string.rep("a", 128),
        revisionHash = "sha256:" .. string.format("%064x", index),
        identitySchema = "sf6cc.combo_identity.v1", title = wide,
        character = wide_character, playerControl = "classic", positionSide = "p1",
        sequenceLength = 1, attempts = 0, successes = 0, lastPlayedAt = 0
    }
end
local size_state_raw = size_harness.files[Checkpoint.STATE_FILE]
local size_checkpoint_raw = size_harness.files[Checkpoint.OUTPUT_FILE]
local size_event = size_harness:new_event({
    combo_id = string.rep("a", 128), revision = "sha256:" .. string.format("%064x", 1),
    title = wide, character = wide_character
})
assert(size_producer:prepare_event(size_event))
assert(not size_producer:commit_pending(size_event.event_id), "checkpoint byte overflow must fail")
assert(size_harness.files[Checkpoint.STATE_FILE] == size_state_raw
    and size_harness.files[Checkpoint.OUTPUT_FILE] == size_checkpoint_raw)

local checkpoint_bytes = harness.files[Checkpoint.OUTPUT_FILE]
local state_bytes = harness.files[Checkpoint.STATE_FILE]
local pending_bytes = harness.files[Checkpoint.PENDING_FILE]
for _, forbidden in ipairs({
    "raw input", "raw_input", "replay", "failure_reason", "failure_code",
    "account", "machine", "cookie", "token", "file_path", "local_filename"
}) do
    assert(not checkpoint_bytes:lower():find(forbidden, 1, true))
    assert(not state_bytes:lower():find(forbidden, 1, true))
    assert(not pending_bytes:lower():find(forbidden, 1, true))
end
assert(#checkpoint_bytes <= Checkpoint._test.limits.max_file_bytes)
assert(#pending_bytes <= Checkpoint._test.limits.max_pending_bytes)

-- Raw event reconstruction: events.jsonl fields are sufficient for an offline
-- Client to rebuild the cumulative counters without a runtime checkpoint.
local function rebuild_from_raw_events(events)
    local items = {}
    local seen = {}
    for _, event in ipairs(events) do
        local event_id = event.event_id
        if event_id and not seen[event_id] then
            seen[event_id] = true
            local runtime = event.runtime or {}
            local result = event.result or {}
            local outcome = result.outcome
            if runtime.source == "manual" and (outcome == "success" or outcome == "fail") then
                local key = event.combo.revision_hash .. "\0"
                    .. runtime.player_control .. "\0"
                    .. runtime.position_side
                local item = items[key] or {
                    revisionHash = event.combo.revision_hash,
                    playerControl = runtime.player_control,
                    positionSide = runtime.position_side,
                    character = event.combo.character,
                    title = event.combo.title,
                    sequenceLength = event.combo.sequence_length,
                    attempts = 0,
                    successes = 0,
                    lastPlayedAt = nil
                }
                item.attempts = item.attempts + 1
                if outcome == "success" then item.successes = item.successes + 1 end
                if event.occurred_at and (not item.lastPlayedAt or event.occurred_at > item.lastPlayedAt) then
                    item.lastPlayedAt = event.occurred_at
                end
                items[key] = item
            end
        end
    end
    return items
end

local raw_events = {
    {
        event_id = "raw-1",
        occurred_at = "2026-08-16T10:00:00Z",
        combo = {
            revision_hash = "hashed-combo", character = "Ryu", title = "Raw",
            sequence_length = 3
        },
        runtime = { source = "manual", player_control = "classic", position_side = "p1" },
        result = { outcome = "success" }
    },
    {
        event_id = "raw-2",
        occurred_at = "2026-08-16T10:01:00Z",
        combo = {
            revision_hash = "hashed-combo", character = "Ryu", title = "Raw",
            sequence_length = 3
        },
        runtime = { source = "manual", player_control = "classic", position_side = "p1" },
        result = { outcome = "fail" }
    },
    {
        event_id = "raw-3",
        occurred_at = "2026-08-16T10:02:00Z",
        combo = {
            revision_hash = "hashed-combo", character = "Ryu", title = "Raw",
            sequence_length = 3
        },
        runtime = { source = "auto_demo", player_control = "classic", position_side = "p1" },
        result = { outcome = "fail" }
    },
    {
        event_id = "raw-1",
        occurred_at = "2026-08-16T10:03:00Z",
        combo = {
            revision_hash = "hashed-combo", character = "Ryu", title = "Raw",
            sequence_length = 3
        },
        runtime = { source = "manual", player_control = "classic", position_side = "p1" },
        result = { outcome = "success" }
    }
}
local rebuilt_items = rebuild_from_raw_events(raw_events)
local rebuilt_item = rebuilt_items["hashed-combo\0classic\0p1"]
assert(rebuilt_item ~= nil, "raw event rebuild must produce the cumulative key")
assert(rebuilt_item.attempts == 2 and rebuilt_item.successes == 1,
    "raw event rebuild must count manual facts and outcomes deterministically")
assert(rebuilt_item.lastPlayedAt == "2026-08-16T10:01:00Z",
    "raw event rebuild must take the latest manual timestamp")
assert(rebuilt_item.character == "Ryu" and rebuilt_item.sequenceLength == 3,
    "raw event rebuild must preserve identity display fields")

-- Telemetry default gate: release defaults must keep checkpoint writes off.
_G.CT_TELEMETRY_CHECKPOINT = false
package.loaded["func/ComboTrials/Telemetry"] = nil
local disabled_files = {}
local disabled_events = ""
local original_open = io.open
fs = {
    create_dir = function() return true end,
    read = function(path) return disabled_files[path] end
}
json = { load_string = function() error("default gate does not restart state") end }
sf6cc_atomic_file = {
    random_epoch = function() return "fedcba9876543210fedcba9876543210" end,
    probe = function(path) return disabled_files[path] ~= nil and "exists" or "missing" end,
    write = function(path, bytes) disabled_files[path] = bytes return true end
}
io.open = function(path, mode)
    assert(path:find("events.jsonl", 1, true) and mode == "ab", "legacy output path changed")
    return {
        write = function(self, ...)
            disabled_events = disabled_events .. table.concat({ ... })
            return self
        end,
        flush = function() return true end,
        close = function() return true end
    }
end
local DisabledTelemetry = require("func/ComboTrials/Telemetry")
local disabled_context = {
    sequence = { { action_id = 100, _xt_meta = { character = "ryu", combo_id = "default.gate" } } },
    character = "ryu", declared_control = "classic", player_control = "classic",
    position_side = "p1", source = "manual", engine_frame = 100
}
DisabledTelemetry.begin_attempt(disabled_context)
assert(DisabledTelemetry.finish_attempt("success", { engine_frame = 120 }))
local disabled_producer = DisabledTelemetry.get_checkpoint_producer()
assert(disabled_producer.state == nil, "default gate must not initialize checkpoint")
assert(disabled_files[Checkpoint.OUTPUT_FILE] == nil
    and disabled_files[Checkpoint.STATE_FILE] == nil
    and disabled_files[Checkpoint.PENDING_FILE] == nil,
    "default gate must not create checkpoint files")
assert(disabled_events:find('"outcome":"success"', 1, true),
    "default gate must keep the legacy event stream")
io.open = original_open
_G.CT_TELEMETRY_CHECKPOINT = nil

-- Telemetry integration: exact legacy schema and checked write/flush/close returns.
_G.CT_TELEMETRY_CHECKPOINT = true
package.loaded["func/ComboTrials/Telemetry"] = nil
local integration_files = {}
local integration_events = ""
local io_failure
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
    assert(path:find("events.jsonl", 1, true) and mode == "ab", "legacy output path changed")
    local pending = ""
    return {
        write = function(self, ...)
            if io_failure == "write" then return nil, "injected write return failure" end
            pending = pending .. table.concat({ ... })
            return self
        end,
        flush = function()
            if io_failure == "flush" then return nil, "injected flush return failure" end
            integration_events = integration_events .. pending
            pending = ""
            return true
        end,
        close = function()
            if io_failure == "close" then return nil, "injected close return failure" end
            return true
        end
    }
end

local Telemetry = require("func/ComboTrials/Telemetry")
local context = {
    sequence = { { action_id = 100, _xt_meta = { character = "ryu", combo_id = "integration.combo" } } },
    character = "ryu", declared_control = "classic", player_control = "classic",
    position_side = "p1", source = "manual", engine_frame = 100
}
Telemetry.begin_attempt(context)
local manual_ok, manual_event = Telemetry.finish_attempt("success", { engine_frame = 120 })
assert(manual_ok, "successful legacy append must report success")
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
assert(not integration_events:find("checkpoint", 1, true),
    "legacy event JSON must not gain checkpoint fields")
local integration_producer = Telemetry.get_checkpoint_producer()
assert(integration_producer.state.items[1].attempts == 1)

context.source = "auto_demo"
Telemetry.begin_attempt(context)
assert(Telemetry.finish_attempt("success", { engine_frame = 140 }))
local auto_sequence = integration_producer.state.checkpointSequence
assert(integration_producer.state.items[1].attempts == 1, "auto-demo must not enter cumulative state")

context.source = "manual"
for _, failure in ipairs({ "write", "flush", "close" }) do
    io_failure = failure
    local attempts_before = integration_producer.state.items[1].attempts
    Telemetry.begin_attempt(context)
    local append_ok = Telemetry.finish_attempt("fail", { engine_frame = 160 })
    assert(not append_ok, failure .. " returned failure must be detected")
    assert(integration_producer.state.items[1].attempts == attempts_before + 1,
        "pending journal must preserve counting independently of legacy " .. failure .. " failure")
    assert(integration_producer.pending.status == "empty", "successful cumulative commit must clear pending")
end
io_failure = nil
assert(integration_producer.state.checkpointSequence == auto_sequence + 3)
io.open = original_open
_G.CT_TELEMETRY_CHECKPOINT = nil

print("combo attempt checkpoint tests passed")
