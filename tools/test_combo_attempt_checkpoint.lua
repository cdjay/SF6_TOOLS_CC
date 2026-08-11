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

local function new_harness()
    local harness = {
        files = {},
        decoded = {},
        failed_paths = {},
        temps = {},
        write_count = 0,
        now = 1786400000
    }
    harness.deps = {
        read = function(path) return harness.files[path] end,
        exists = function(path) return harness.files[path] ~= nil end,
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
        new_epoch = function() return "0123456789abcdef0123456789abcdef" end,
        now = function() return harness.now end
    }
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

local function attempt(control, side, revision, combo_id)
    return {
        source = "manual",
        player_control = control,
        position_side = side,
        combo = {
            combo_id = combo_id or "fixture.combo",
            revision_hash = revision or ("sha256:" .. string.rep("a", 64)),
            identity_schema = "sf6cc.combo_identity.v1",
            title = "Fixture Combo",
            character = "ryu",
            sequence_length = 4
        }
    }
end

local harness = new_harness()
local producer = Checkpoint.new(harness.deps)
local initialized, initial_bytes = producer:initialize()
assert(initialized, initial_bytes)
assert(producer.state.checkpointSequence == 1, "initial sequence must be one")
assert(#producer.state.items == 0, "initial checkpoint must be empty")
assert(initial_bytes == '{"schema":"sf6cc.combo_attempt_checkpoint.v1",'
    .. '"producerEpoch":"0123456789abcdef0123456789abcdef",'
    .. '"checkpointSequence":1,"items":[]}', "initial bytes must be canonical")
harness:remember(producer)

local republished, republished_bytes = producer:republish()
assert(republished and republished_bytes == initial_bytes, "same checkpoint must republish byte-identically")
assert(producer.state.checkpointSequence == 1, "republish must not advance sequence")

assert(producer:record(attempt("classic", "p1"), "fail"))
harness:remember(producer)
assert(producer.state.checkpointSequence == 2, "first fact must advance sequence")
assert(producer.state.items[1].attempts == 1 and producer.state.items[1].successes == 0,
    "failure counters must increment")

harness.now = harness.now + 1
assert(producer:record(attempt("classic", "p1"), "success"))
harness:remember(producer)
assert(producer.state.items[1].attempts == 2 and producer.state.items[1].successes == 1,
    "success counters must increment")

assert(producer:record(attempt("modern", "p1"), "success"))
assert(producer:record(attempt("classic", "p2"), "fail"))
assert(producer:record(attempt("modern", "p2"), "success"))
harness:remember(producer)
assert(#producer.state.items == 4, "control and side dimensions must remain distinct")

local restart_bytes = harness.files[Checkpoint.OUTPUT_FILE]
local restart_epoch = producer.state.producerEpoch
local restart_sequence = producer.state.checkpointSequence
local restarted = Checkpoint.new(harness.deps)
local restart_ok, restarted_bytes = restarted:initialize()
assert(restart_ok, restarted_bytes)
assert(restarted.state.producerEpoch == restart_epoch, "restart must preserve epoch")
assert(restarted.state.checkpointSequence == restart_sequence, "restart must preserve sequence")
assert(restarted_bytes == restart_bytes, "restart must preserve deterministic checkpoint bytes")

local prior_checkpoint = harness.files[Checkpoint.OUTPUT_FILE]
harness.failed_paths[Checkpoint.OUTPUT_FILE] = true
harness.now = harness.now + 1
local publish_ok = restarted:record(attempt("classic", "p1"), "fail")
assert(not publish_ok, "injected checkpoint replace must fail")
assert(harness.files[Checkpoint.OUTPUT_FILE] == prior_checkpoint,
    "failed replace must preserve the last valid checkpoint")
local has_partial_temp = false
for path in pairs(harness.temps) do
    if path:find("cumulative%-checkpoint%-v1%.json%.tmp", 1) then has_partial_temp = true end
end
assert(has_partial_temp, "failure fixture must retain only its simulated partial temp")
harness:remember(restarted)
harness.failed_paths[Checkpoint.OUTPUT_FILE] = nil
local recovered = Checkpoint.new(harness.deps)
assert(recovered:initialize(), "valid durable state must repair checkpoint after restart")
assert(recovered.state.producerEpoch == restart_epoch, "repair must not rotate epoch")
assert(recovered.state.checkpointSequence == restart_sequence + 1,
    "repair must publish the already durable sequence")

local before_overflow_state = harness.files[Checkpoint.STATE_FILE]
local before_overflow_checkpoint = harness.files[Checkpoint.OUTPUT_FILE]
recovered.state.items[1].attempts = Checkpoint._test.limits.max_attempts
local overflow_ok = recovered:record(attempt(
    recovered.state.items[1].playerControl,
    recovered.state.items[1].positionSide,
    recovered.state.items[1].revisionHash
), "fail")
assert(not overflow_ok, "attempt overflow must fail bounded")
assert(harness.files[Checkpoint.STATE_FILE] == before_overflow_state
    and harness.files[Checkpoint.OUTPUT_FILE] == before_overflow_checkpoint,
    "overflow must not replace durable files")

local item_limit_harness = new_harness()
local item_limited = Checkpoint.new(item_limit_harness.deps)
assert(item_limited:initialize())
for index = 1, Checkpoint._test.limits.max_items do
    item_limited.state.items[index] = {
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
assert(not item_limited:record(attempt("classic", "p1", "sha256:" .. string.rep("f", 64)), "fail"),
    "the 513th item must fail bounded")
assert(item_limit_harness.files[Checkpoint.STATE_FILE] == item_limit_state
    and item_limit_harness.files[Checkpoint.OUTPUT_FILE] == item_limit_checkpoint,
    "item bound failure must not replace durable files")

local checkpoint_bytes = harness.files[Checkpoint.OUTPUT_FILE]
for _, forbidden in ipairs({
    "raw input", "raw_input", "replay", "failure_reason", "failure_code",
    "account", "machine", "cookie", "token", "file_path", "local_filename"
}) do
    assert(not checkpoint_bytes:lower():find(forbidden, 1, true),
        "checkpoint contains forbidden content: " .. forbidden)
end
assert(#checkpoint_bytes <= Checkpoint._test.limits.max_file_bytes, "checkpoint byte limit exceeded")

local conflict_harness = new_harness()
conflict_harness.files[Checkpoint.OUTPUT_FILE] = "{existing-checkpoint}"
local conflicted = Checkpoint.new(conflict_harness.deps)
assert(not conflicted:initialize(), "checkpoint without durable state must fail closed")
assert(conflict_harness.files[Checkpoint.OUTPUT_FILE] == "{existing-checkpoint}",
    "fail-closed initialization must preserve existing checkpoint")

local empty_conflict_harness = new_harness()
empty_conflict_harness.files[Checkpoint.OUTPUT_FILE] = ""
local empty_conflicted = Checkpoint.new(empty_conflict_harness.deps)
assert(not empty_conflicted:initialize(), "empty checkpoint without state must fail closed")
assert(empty_conflict_harness.files[Checkpoint.OUTPUT_FILE] == "",
    "empty conflicting checkpoint must not be replaced")

local sequence_conflict_harness = new_harness()
local sequence_source = Checkpoint.new(sequence_conflict_harness.deps)
assert(sequence_source:initialize())
assert(sequence_source:record(attempt("classic", "p1"), "success"))
sequence_conflict_harness:remember(sequence_source)
local conflicting_checkpoint = {
    schema = Checkpoint.SCHEMA,
    producerEpoch = sequence_source.state.producerEpoch,
    checkpointSequence = sequence_source.state.checkpointSequence,
    items = deep_copy(sequence_source.state.items)
}
conflicting_checkpoint.items[1].title = "Conflicting title"
local conflict_bytes = Checkpoint._test.encode_checkpoint(conflicting_checkpoint)
sequence_conflict_harness.files[Checkpoint.OUTPUT_FILE] = conflict_bytes
sequence_conflict_harness.decoded[conflict_bytes] = deep_copy(conflicting_checkpoint)
local sequence_conflicted = Checkpoint.new(sequence_conflict_harness.deps)
assert(not sequence_conflicted:initialize(), "same sequence with different payload must fail closed")
assert(sequence_conflict_harness.files[Checkpoint.OUTPUT_FILE] == conflict_bytes,
    "same-sequence conflict must preserve the published file")

-- Integration: terminal attempt deduplication, auto-demo exclusion, and legacy JSONL append.
package.loaded["func/ComboTrials/Telemetry"] = nil
local integration_files = {}
local integration_events = ""
local integration_failed_path
local original_open = io.open
fs = {
    create_dir = function() return true end,
    read = function(path) return integration_files[path] end
}
json = { load_string = function() error("integration test does not restart state") end }
sf6cc_atomic_file = {
    random_epoch = function() return "fedcba9876543210fedcba9876543210" end,
    write = function(path, bytes)
        if path == integration_failed_path then return nil, "injected native failure" end
        integration_files[path] = bytes
        return true
    end
}
io.open = function(path, mode)
    if mode == "rb" then
        if integration_files[path] == nil then return nil, "missing" end
        return { close = function() return true end }
    end
    assert(path:find("events.jsonl", 1, true) and mode == "ab", "legacy output path changed")
    return {
        write = function(_, ...) integration_events = integration_events .. table.concat({ ... }) end,
        flush = function() return true end,
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
assert(Telemetry.finish_attempt("success", { engine_frame = 120 }), "manual event must append")
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
    "auto-demo must not affect cumulative checkpoint")

integration_failed_path = Checkpoint.STATE_FILE
context.source = "manual"
Telemetry.begin_attempt(context)
assert(Telemetry.finish_attempt("fail", { engine_frame = 160 }),
    "checkpoint persistence failure must not suppress legacy event")
assert(Telemetry.get_state().checkpoint_error ~= nil,
    "isolated checkpoint failure must remain diagnosable")
local _, event_count = integration_events:gsub("\n", "\n")
assert(event_count == 3, "legacy events.jsonl must continue receiving terminal events")
io.open = original_open

print("combo attempt checkpoint tests passed")
