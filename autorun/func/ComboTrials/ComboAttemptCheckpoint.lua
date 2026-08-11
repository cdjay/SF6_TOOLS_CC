-- Durable all-time combo-attempt checkpoint producer.
-- The caller supplies hashing, JSON decoding, time, and atomic persistence.

local Checkpoint = {}
Checkpoint.__index = Checkpoint

Checkpoint.SCHEMA = "sf6cc.combo_attempt_checkpoint.v1"
Checkpoint.STATE_SCHEMA = "sf6cc.combo_attempt_checkpoint_state.v1"
Checkpoint.IDENTITY_SCHEMA = "sf6cc.combo_identity.v1"
Checkpoint.OUTPUT_DIR = "SF6_TrainingRemoteControl_data/ComboTrialTelemetry"
Checkpoint.OUTPUT_FILE = Checkpoint.OUTPUT_DIR .. "/cumulative-checkpoint-v1.json"
Checkpoint.STATE_FILE = Checkpoint.OUTPUT_DIR .. "/producer-state-v1.json"

local MAX_SAFE_INTEGER = 9007199254740991
local MAX_ITEMS = 512
local MAX_ATTEMPTS = 10000000
local MAX_FILE_BYTES = 524288
local MAX_TIMESTAMP = 4102444800

local JSON_ESCAPES = {
    ['"'] = '\\"',
    ['\\'] = '\\\\',
    ['\b'] = '\\b',
    ['\f'] = '\\f',
    ['\n'] = '\\n',
    ['\r'] = '\\r',
    ['\t'] = '\\t'
}

local function encode_string(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        return JSON_ESCAPES[character] or string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

local function integer(value, minimum, maximum)
    return type(value) == "number"
        and value == math.floor(value)
        and value >= minimum
        and value <= maximum
end

local function exact_keys(value, required, optional)
    if type(value) ~= "table" then return false end
    local seen = 0
    for key in pairs(value) do
        if not required[key] and not optional[key] then return false end
        seen = seen + 1
    end
    local required_count = 0
    for key in pairs(required) do
        required_count = required_count + 1
        if value[key] == nil then return false end
    end
    return seen >= required_count
end

local function utf8_codepoints(value)
    if type(value) ~= "string" then return nil end
    local index, count, length = 1, 0, #value
    while index <= length do
        local first = value:byte(index)
        local width
        if first <= 0x7f then
            width = 1
        elseif first >= 0xc2 and first <= 0xdf then
            width = 2
        elseif first >= 0xe0 and first <= 0xef then
            width = 3
        elseif first >= 0xf0 and first <= 0xf4 then
            width = 4
        else
            return nil
        end
        if index + width - 1 > length then return nil end
        for offset = 1, width - 1 do
            local continuation = value:byte(index + offset)
            if continuation < 0x80 or continuation > 0xbf then return nil end
        end
        if width == 3 then
            local second = value:byte(index + 1)
            if (first == 0xe0 and second < 0xa0) or (first == 0xed and second >= 0xa0) then
                return nil
            end
        elseif width == 4 then
            local second = value:byte(index + 1)
            if (first == 0xf0 and second < 0x90) or (first == 0xf4 and second >= 0x90) then
                return nil
            end
        end
        index = index + width
        count = count + 1
    end
    return count
end

local ITEM_REQUIRED = {
    revisionHash = true,
    identitySchema = true,
    title = true,
    character = true,
    playerControl = true,
    positionSide = true,
    sequenceLength = true,
    attempts = true,
    successes = true,
    lastPlayedAt = true
}
local ITEM_OPTIONAL = { comboId = true }

local function valid_item(item)
    if not exact_keys(item, ITEM_REQUIRED, ITEM_OPTIONAL) then return false end
    if type(item.revisionHash) ~= "string"
        or not item.revisionHash:match("^sha256:[0-9a-f]+$")
        or #item.revisionHash ~= 71 then return false end
    if item.identitySchema ~= Checkpoint.IDENTITY_SCHEMA then return false end
    local title_length = utf8_codepoints(item.title)
    local character_length = utf8_codepoints(item.character)
    if not title_length or title_length < 1 or title_length > 240 then return false end
    if not character_length or character_length < 1 or character_length > 64 then return false end
    if item.playerControl ~= "classic" and item.playerControl ~= "modern" then return false end
    if item.positionSide ~= "p1" and item.positionSide ~= "p2" then return false end
    if not integer(item.sequenceLength, 1, 1000) then return false end
    if not integer(item.attempts, 0, MAX_ATTEMPTS) then return false end
    if not integer(item.successes, 0, item.attempts) then return false end
    if not integer(item.lastPlayedAt, 0, MAX_TIMESTAMP) then return false end
    if item.comboId ~= nil and (type(item.comboId) ~= "string"
        or #item.comboId > 128
        or not item.comboId:match("^[A-Za-z0-9][A-Za-z0-9._-]*$")) then return false end
    return true
end

local function item_key(item)
    return item.revisionHash .. "\0" .. item.playerControl .. "\0" .. item.positionSide
end

local function copy_item(item)
    return {
        comboId = item.comboId,
        revisionHash = item.revisionHash,
        identitySchema = item.identitySchema,
        title = item.title,
        character = item.character,
        playerControl = item.playerControl,
        positionSide = item.positionSide,
        sequenceLength = item.sequenceLength,
        attempts = item.attempts,
        successes = item.successes,
        lastPlayedAt = item.lastPlayedAt
    }
end

local function sorted_items(items)
    local result = {}
    for index, item in ipairs(items) do result[index] = copy_item(item) end
    table.sort(result, function(left, right) return item_key(left) < item_key(right) end)
    return result
end

local function encode_item(item)
    local fields = {}
    if item.comboId ~= nil then fields[#fields + 1] = '"comboId":' .. encode_string(item.comboId) end
    fields[#fields + 1] = '"revisionHash":' .. encode_string(item.revisionHash)
    fields[#fields + 1] = '"identitySchema":' .. encode_string(item.identitySchema)
    fields[#fields + 1] = '"title":' .. encode_string(item.title)
    fields[#fields + 1] = '"character":' .. encode_string(item.character)
    fields[#fields + 1] = '"playerControl":' .. encode_string(item.playerControl)
    fields[#fields + 1] = '"positionSide":' .. encode_string(item.positionSide)
    fields[#fields + 1] = '"sequenceLength":' .. tostring(item.sequenceLength)
    fields[#fields + 1] = '"attempts":' .. tostring(item.attempts)
    fields[#fields + 1] = '"successes":' .. tostring(item.successes)
    fields[#fields + 1] = '"lastPlayedAt":' .. tostring(item.lastPlayedAt)
    return "{" .. table.concat(fields, ",") .. "}"
end

local function encode_items(items)
    local encoded = {}
    for index, item in ipairs(sorted_items(items)) do encoded[index] = encode_item(item) end
    return "[" .. table.concat(encoded, ",") .. "]"
end

local function encode_checkpoint(state)
    return "{" .. table.concat({
        '"schema":' .. encode_string(Checkpoint.SCHEMA),
        '"producerEpoch":' .. encode_string(state.producerEpoch),
        '"checkpointSequence":' .. tostring(state.checkpointSequence),
        '"items":' .. encode_items(state.items)
    }, ",") .. "}"
end

local function encode_state_without_hash(state)
    return "{" .. table.concat({
        '"schema":' .. encode_string(Checkpoint.STATE_SCHEMA),
        '"producerEpoch":' .. encode_string(state.producerEpoch),
        '"checkpointSequence":' .. tostring(state.checkpointSequence),
        '"contentHash":' .. encode_string(state.contentHash),
        '"items":' .. encode_items(state.items)
    }, ",") .. "}"
end

local function encode_state(state)
    local without_hash = encode_state_without_hash(state)
    return without_hash:sub(1, -2) .. ',"stateHash":' .. encode_string(state.stateHash) .. "}"
end

local STATE_REQUIRED = {
    schema = true,
    producerEpoch = true,
    checkpointSequence = true,
    contentHash = true,
    items = true,
    stateHash = true
}

local CHECKPOINT_REQUIRED = {
    schema = true,
    producerEpoch = true,
    checkpointSequence = true,
    items = true
}

local function validate_items(items)
    if type(items) ~= "table" or #items > MAX_ITEMS then return nil, "items invalid" end
    local seen, total = {}, 0
    for _, item in ipairs(items) do
        if not valid_item(item) then return nil, "item invalid" end
        local key = item_key(item)
        if seen[key] then return nil, "duplicate item" end
        seen[key] = true
        total = total + item.attempts
        if total > MAX_ATTEMPTS then return nil, "attempt total overflow" end
    end
    return sorted_items(items)
end

local function validate_state(self, candidate, raw)
    if not exact_keys(candidate, STATE_REQUIRED, {}) then return nil, "state fields invalid" end
    if candidate.schema ~= Checkpoint.STATE_SCHEMA then return nil, "state schema invalid" end
    if type(candidate.producerEpoch) ~= "string"
        or #candidate.producerEpoch ~= 32
        or not candidate.producerEpoch:match("^[0-9a-f]+$") then return nil, "epoch invalid" end
    if not integer(candidate.checkpointSequence, 1, MAX_SAFE_INTEGER) then
        return nil, "sequence invalid"
    end
    if type(candidate.contentHash) ~= "string" or #candidate.contentHash ~= 64
        or not candidate.contentHash:match("^[0-9a-f]+$") then return nil, "content hash invalid" end
    if type(candidate.stateHash) ~= "string" or #candidate.stateHash ~= 64
        or not candidate.stateHash:match("^[0-9a-f]+$") then return nil, "state hash invalid" end
    local items, items_error = validate_items(candidate.items)
    if not items then return nil, items_error end
    candidate.items = items
    local expected_content_hash = self.deps.sha256(encode_items(candidate.items))
    if candidate.contentHash ~= expected_content_hash then return nil, "content hash mismatch" end
    local expected_state_hash = self.deps.sha256(encode_state_without_hash(candidate))
    if candidate.stateHash ~= expected_state_hash then return nil, "state hash mismatch" end
    if raw ~= encode_state(candidate) then return nil, "state is not canonical" end
    local checkpoint_bytes = encode_checkpoint(candidate)
    if #checkpoint_bytes > MAX_FILE_BYTES then return nil, "checkpoint too large" end
    return candidate
end

local function validate_checkpoint(candidate, raw)
    if not exact_keys(candidate, CHECKPOINT_REQUIRED, {}) then return nil, "checkpoint fields invalid" end
    if candidate.schema ~= Checkpoint.SCHEMA then return nil, "checkpoint schema invalid" end
    if type(candidate.producerEpoch) ~= "string" or #candidate.producerEpoch ~= 32
        or not candidate.producerEpoch:match("^[0-9a-f]+$") then return nil, "checkpoint epoch invalid" end
    if not integer(candidate.checkpointSequence, 1, MAX_SAFE_INTEGER) then
        return nil, "checkpoint sequence invalid"
    end
    local items, items_error = validate_items(candidate.items)
    if not items then return nil, items_error end
    candidate.items = items
    if raw ~= encode_checkpoint(candidate) then return nil, "checkpoint is not canonical" end
    if #raw > MAX_FILE_BYTES then return nil, "checkpoint too large" end
    return candidate
end

local function finalize_state(self, state)
    state.items = sorted_items(state.items)
    state.contentHash = self.deps.sha256(encode_items(state.items))
    state.stateHash = self.deps.sha256(encode_state_without_hash(state))
    return state
end

local function read_optional(self, path)
    local ok, value = pcall(self.deps.read, path)
    if not ok then return nil, tostring(value) end
    if value == nil or value == "" then return nil end
    if type(value) ~= "string" then return nil, "read returned non-string" end
    return value
end

local function write_atomic(self, path, bytes)
    local ok, result, err = pcall(self.deps.atomic_write, path, bytes)
    if not ok then return false, tostring(result) end
    if result ~= true then return false, tostring(err or result or "atomic write failed") end
    return true
end

function Checkpoint.new(deps)
    assert(type(deps) == "table", "checkpoint dependencies required")
    assert(type(deps.read) == "function", "read dependency required")
    assert(type(deps.exists) == "function", "exists dependency required")
    assert(type(deps.atomic_write) == "function", "atomic_write dependency required")
    assert(type(deps.decode) == "function", "decode dependency required")
    assert(type(deps.sha256) == "function", "sha256 dependency required")
    assert(type(deps.new_epoch) == "function", "new_epoch dependency required")
    assert(type(deps.now) == "function", "now dependency required")
    return setmetatable({ deps = deps, state = nil, blocked = false, last_error = nil }, Checkpoint)
end

function Checkpoint:_fail(message)
    self.last_error = tostring(message)
    if self.deps.log then pcall(self.deps.log, self.last_error) end
    return false, self.last_error
end

function Checkpoint:_block(message)
    self.blocked = true
    return self:_fail(message)
end

function Checkpoint:initialize()
    if self.state then return self:republish() end
    if self.blocked then return false, self.last_error end

    local state_exists_ok, state_exists = pcall(self.deps.exists, Checkpoint.STATE_FILE)
    if not state_exists_ok then return self:_block("state existence check failed") end
    if state_exists then
        local state_raw, state_read_error = read_optional(self, Checkpoint.STATE_FILE)
        if state_read_error then return self:_block("state read failed: " .. state_read_error) end
        if not state_raw then return self:_block("durable state is empty") end
        local decoded_ok, candidate = pcall(self.deps.decode, state_raw)
        if not decoded_ok or type(candidate) ~= "table" then
            return self:_block("durable state decode failed")
        end
        local valid, validation_error = validate_state(self, candidate, state_raw)
        if not valid then
            return self:_block("durable state rejected: " .. tostring(validation_error))
        end
        self.state = valid
        return self:recover_checkpoint()
    end

    local checkpoint_exists_ok, checkpoint_exists = pcall(self.deps.exists, Checkpoint.OUTPUT_FILE)
    if not checkpoint_exists_ok then return self:_block("checkpoint existence check failed") end
    if checkpoint_exists then
        local existing_checkpoint, checkpoint_read_error = read_optional(self, Checkpoint.OUTPUT_FILE)
        if checkpoint_read_error then
            return self:_block("checkpoint read failed before initialization: " .. checkpoint_read_error)
        end
        return self:_block(existing_checkpoint
            and "checkpoint exists without provable durable state"
            or "empty checkpoint exists without provable durable state")
    end

    local epoch_ok, epoch, epoch_error = pcall(self.deps.new_epoch)
    if not epoch_ok or type(epoch) ~= "string" or #epoch ~= 32
        or not epoch:match("^[0-9a-f]+$") then
        return self:_block("epoch generation failed: " .. tostring(epoch_error or epoch))
    end
    local initial = finalize_state(self, {
        schema = Checkpoint.STATE_SCHEMA,
        producerEpoch = epoch,
        checkpointSequence = 1,
        items = {}
    })
    local state_ok, state_error = write_atomic(self, Checkpoint.STATE_FILE, encode_state(initial))
    if not state_ok then return self:_fail("initial state publish failed: " .. state_error) end
    self.state = initial
    return self:republish()
end

function Checkpoint:recover_checkpoint()
    if not self.state then return false, "producer not initialized" end
    local exists_ok, exists = pcall(self.deps.exists, Checkpoint.OUTPUT_FILE)
    if not exists_ok then return self:_block("checkpoint existence check failed during recovery") end
    if not exists then return self:republish() end

    local raw, read_error = read_optional(self, Checkpoint.OUTPUT_FILE)
    if read_error then return self:_block("checkpoint read failed during recovery: " .. read_error) end
    if not raw then return self:_block("published checkpoint is empty") end
    local decoded_ok, candidate = pcall(self.deps.decode, raw)
    if not decoded_ok or type(candidate) ~= "table" then
        return self:_block("published checkpoint decode failed")
    end
    local valid, validation_error = validate_checkpoint(candidate, raw)
    if not valid then return self:_block("published checkpoint rejected: " .. tostring(validation_error)) end
    if valid.producerEpoch ~= self.state.producerEpoch then return self:_block("checkpoint epoch conflict") end
    if valid.checkpointSequence > self.state.checkpointSequence then
        return self:_block("checkpoint sequence is newer than durable state")
    end

    local expected = encode_checkpoint(self.state)
    if valid.checkpointSequence == self.state.checkpointSequence then
        if raw ~= expected then return self:_block("same-sequence checkpoint conflict") end
        return self:republish()
    end

    local current_by_key = {}
    for _, item in ipairs(self.state.items) do current_by_key[item_key(item)] = item end
    for _, previous in ipairs(valid.items) do
        local current = current_by_key[item_key(previous)]
        if not current or current.attempts < previous.attempts
            or current.successes < previous.successes
            or (current.successes - previous.successes) > (current.attempts - previous.attempts) then
            return self:_block("durable state regresses published counters")
        end
    end
    return self:republish()
end

function Checkpoint:republish()
    if not self.state then return false, "producer not initialized" end
    local bytes = encode_checkpoint(self.state)
    if #bytes > MAX_FILE_BYTES then return self:_fail("checkpoint exceeds byte limit") end
    local ok, err = write_atomic(self, Checkpoint.OUTPUT_FILE, bytes)
    if not ok then return self:_fail("checkpoint publish failed: " .. err) end
    self.last_error = nil
    return true, bytes
end

local function item_from_attempt(attempt, outcome, timestamp)
    if type(attempt) ~= "table" or type(attempt.combo) ~= "table" then
        return nil, "attempt facts missing"
    end
    local combo = attempt.combo
    local combo_id = combo.combo_id
    if type(combo_id) ~= "string" or #combo_id > 128
        or not combo_id:match("^[A-Za-z0-9][A-Za-z0-9._-]*$") then combo_id = nil end
    local item = {
        comboId = combo_id,
        revisionHash = combo.revision_hash,
        identitySchema = combo.identity_schema,
        title = combo.title,
        character = combo.character,
        playerControl = attempt.player_control,
        positionSide = attempt.position_side,
        sequenceLength = combo.sequence_length,
        attempts = 1,
        successes = outcome == "success" and 1 or 0,
        lastPlayedAt = timestamp
    }
    if not valid_item(item) then return nil, "attempt facts violate checkpoint contract" end
    return item
end

function Checkpoint:record(attempt, outcome)
    if outcome ~= "success" and outcome ~= "fail" then return false, "unsupported outcome" end
    if type(attempt) ~= "table" or attempt.source ~= "manual" then return true, "ignored" end
    if not self.state then
        local initialized, initialize_error = self:initialize()
        if not initialized then return false, initialize_error end
    end
    if self.blocked then return false, self.last_error end

    local timestamp = tonumber(self.deps.now())
    if not integer(timestamp, 0, MAX_TIMESTAMP) then return self:_block("timestamp outside contract") end
    local incoming, incoming_error = item_from_attempt(attempt, outcome, timestamp)
    if not incoming then return self:_block(incoming_error) end

    local next_state = {
        schema = Checkpoint.STATE_SCHEMA,
        producerEpoch = self.state.producerEpoch,
        checkpointSequence = self.state.checkpointSequence,
        items = sorted_items(self.state.items)
    }
    local found
    for _, item in ipairs(next_state.items) do
        if item_key(item) == item_key(incoming) then found = item break end
    end
    if found then
        if found.attempts >= MAX_ATTEMPTS then return self:_block("item attempt overflow") end
        found.attempts = found.attempts + 1
        if outcome == "success" then found.successes = found.successes + 1 end
        found.lastPlayedAt = math.max(found.lastPlayedAt, timestamp)
        found.comboId = incoming.comboId
        found.title = incoming.title
        found.character = incoming.character
        found.sequenceLength = incoming.sequenceLength
    else
        if #next_state.items >= MAX_ITEMS then return self:_block("item limit reached") end
        next_state.items[#next_state.items + 1] = incoming
    end

    local total = 0
    for _, item in ipairs(next_state.items) do
        total = total + item.attempts
        if total > MAX_ATTEMPTS then return self:_block("total attempt overflow") end
    end
    if self.state.checkpointSequence >= MAX_SAFE_INTEGER then return self:_block("sequence overflow") end
    next_state.checkpointSequence = next_state.checkpointSequence + 1
    finalize_state(self, next_state)
    local checkpoint_bytes = encode_checkpoint(next_state)
    if #checkpoint_bytes > MAX_FILE_BYTES then return self:_block("checkpoint exceeds byte limit") end

    local state_ok, state_error = write_atomic(self, Checkpoint.STATE_FILE, encode_state(next_state))
    if not state_ok then return self:_block("state publish failed after terminal fact: " .. state_error) end
    self.state = next_state
    local checkpoint_ok, checkpoint_error = write_atomic(self, Checkpoint.OUTPUT_FILE, checkpoint_bytes)
    if not checkpoint_ok then return self:_fail("checkpoint publish failed: " .. checkpoint_error) end
    self.last_error = nil
    return true, checkpoint_bytes
end

Checkpoint._test = {
    encode_checkpoint = encode_checkpoint,
    encode_state = encode_state,
    encode_items = encode_items,
    valid_item = valid_item,
    item_key = item_key,
    limits = {
        max_items = MAX_ITEMS,
        max_attempts = MAX_ATTEMPTS,
        max_file_bytes = MAX_FILE_BYTES
    }
}

return Checkpoint
