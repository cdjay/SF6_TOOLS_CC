-- Anonymous, append-only combo attempt telemetry for the external tray uploader.
-- This module never performs network requests and never stores account identity.

local Telemetry = {
    SCHEMA = "sf6cc.combo_attempt.v1",
    IDENTITY_SCHEMA = "sf6cc.combo_identity.v1",
    OUTPUT_DIR = "SF6_TrainingRemoteControl_data/ComboTrialTelemetry",
    OUTPUT_FILE = "SF6_TrainingRemoteControl_data/ComboTrialTelemetry/events.jsonl",
    MOD_VERSION = "0.99"
}

local UINT32 = 0xffffffff
local SHA256_K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

local state = {
    attempt = nil,
    event_counter = 0,
    last_error = nil,
    identity_cache = setmetatable({}, { __mode = "k" })
}

local function add32(...)
    local total = 0
    for index = 1, select("#", ...) do
        total = (total + (select(index, ...) or 0)) & UINT32
    end
    return total
end

local function rotate_right(value, bits)
    value = value & UINT32
    return ((value >> bits) | (value << (32 - bits))) & UINT32
end

function Telemetry.sha256(message)
    message = tostring(message or "")
    local original_length = #message
    local bit_length = original_length * 8
    local bit_length_high = math.floor(bit_length / 0x100000000)
    local bit_length_low = bit_length & UINT32
    local zero_padding = (56 - ((original_length + 1) % 64)) % 64
    local padded_length = original_length + 1 + zero_padding + 8

    -- Read padding virtually instead of expanding a potentially large Raw Input
    -- combo into a second byte table.
    local function padded_byte(index)
        if index <= original_length then return string.byte(message, index) end
        if index == original_length + 1 then return 0x80 end
        if index <= padded_length - 8 then return 0 end
        local length_index = index - (padded_length - 7)
        if length_index < 4 then
            return (bit_length_high >> (24 - (length_index * 8))) & 0xff
        end
        return (bit_length_low >> (24 - ((length_index - 4) * 8))) & 0xff
    end

    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local words = {}

    for chunk = 1, padded_length, 64 do
        for index = 0, 15 do
            local offset = chunk + (index * 4)
            words[index] = ((padded_byte(offset) << 24)
                | (padded_byte(offset + 1) << 16)
                | (padded_byte(offset + 2) << 8)
                | padded_byte(offset + 3)) & UINT32
        end
        for index = 16, 63 do
            local x = words[index - 15]
            local y = words[index - 2]
            local s0 = rotate_right(x, 7) ~ rotate_right(x, 18) ~ (x >> 3)
            local s1 = rotate_right(y, 17) ~ rotate_right(y, 19) ~ (y >> 10)
            words[index] = add32(words[index - 16], s0, words[index - 7], s1)
        end

        local a, b, c, d = h0, h1, h2, h3
        local e, f, g, h = h4, h5, h6, h7
        for index = 0, 63 do
            local sum1 = rotate_right(e, 6) ~ rotate_right(e, 11) ~ rotate_right(e, 25)
            local choice = (e & f) ~ ((~e) & g)
            local temp1 = add32(h, sum1, choice, SHA256_K[index + 1], words[index])
            local sum0 = rotate_right(a, 2) ~ rotate_right(a, 13) ~ rotate_right(a, 22)
            local majority = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = add32(sum0, majority)
            h, g, f, e, d, c, b, a = g, f, e, add32(d, temp1), c, b, a, add32(temp1, temp2)
        end

        h0, h1, h2, h3 = add32(h0, a), add32(h1, b), add32(h2, c), add32(h3, d)
        h4, h5, h6, h7 = add32(h4, e), add32(h5, f), add32(h6, g), add32(h7, h)
    end

    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4, h5, h6, h7)
end

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
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(character)
        return JSON_ESCAPES[character] or string.format("\\u%04x", string.byte(character))
    end) .. '"'
end

local function table_is_array(value)
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
        if key > maximum then maximum = key end
    end
    return count > 0 and count == maximum
end

local function encode_json(value, stack)
    local value_type = type(value)
    if value_type == "nil" then return "null" end
    if value_type == "boolean" then return value and "true" or "false" end
    if value_type == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return "null" end
        return tostring(value)
    end
    if value_type == "string" then return encode_string(value) end
    if value_type ~= "table" then return "null" end

    stack = stack or {}
    if stack[value] then error("cyclic table cannot be encoded") end
    stack[value] = true

    local parts = {}
    if table_is_array(value) then
        for index = 1, #value do parts[#parts + 1] = encode_json(value[index], stack) end
        stack[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do
        if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = encode_string(tostring(key)) .. ":" .. encode_json(value[key], stack)
    end
    stack[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

Telemetry.encode_json = encode_json

local EXCLUDED_STEP_KEYS = {
    _xt_meta = true,
    _wtt_cn_meta = true,
    actual_combo = true,
    has_hit = true,
    last_frame_diff = true,
    ui_result_text = true,
    ui_result_kind = true,
    display_name = true,
    title = true,
    note = true,
    notes = true,
    author = true,
    tags = true,
    uploaded_at = true,
    upload_date = true,
    created_at = true,
    updated_at = true
}

local function semantic_copy(value, excluded_keys, seen)
    local value_type = type(value)
    if value_type == "string" or value_type == "number" or value_type == "boolean" then return value end
    if value_type ~= "table" then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true

    local output = {}
    for key, child in pairs(value) do
        local allowed_key = type(key) == "number"
            or (type(key) == "string" and not (excluded_keys and excluded_keys[key]))
        if allowed_key then
            local copied = semantic_copy(child, excluded_keys, seen)
            if copied ~= nil then output[key] = copied end
        end
    end
    seen[value] = nil
    return output
end

local function clean_text(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$") or ""
    if value == "" then return nil end
    return value
end

local function basename(path)
    local name = clean_text(path)
    if not name then return nil end
    return name:match("([^/\\]+)$") or name
end

function Telemetry.build_combo_identity(context)
    context = type(context) == "table" and context or {}
    local sequence = type(context.sequence) == "table" and context.sequence or {}
    local first = type(sequence[1]) == "table" and sequence[1] or {}
    local meta = type(first._xt_meta) == "table" and first._xt_meta
        or (type(first._wtt_cn_meta) == "table" and first._wtt_cn_meta or {})
    local control = clean_text(context.declared_control)
        or clean_text(meta.control_mode)
        or clean_text(meta.control_type)
        or clean_text(meta.timeline_input_profile)
        or "classic"
    control = control:lower() == "modern" and "modern" or "classic"

    local semantic_steps = {}
    for index, step in ipairs(sequence) do
        semantic_steps[index] = semantic_copy(step, EXCLUDED_STEP_KEYS) or {}
    end
    local semantic_payload = {
        schema = Telemetry.IDENTITY_SCHEMA,
        character = clean_text(context.character) or clean_text(meta.character) or "Unknown",
        control_mode = control,
        environment = semantic_copy(meta.environment),
        requires_dummy_crouch = meta.requires_dummy_crouch == true,
        sequence = semantic_steps
    }
    local canonical = encode_json(semantic_payload)
    local combo_id = clean_text(meta.combo_id) or clean_text(meta.comboId) or clean_text(meta.trial_id)
    local title = clean_text(meta.title) or clean_text(first.display_name) or clean_text(first.title)
        or basename(context.file_name) or basename(context.file_path) or "未命名连段"

    local identity = {
        combo_id = combo_id,
        revision_hash = "sha256:" .. Telemetry.sha256(canonical),
        identity_schema = Telemetry.IDENTITY_SCHEMA,
        title = title,
        author = clean_text(meta.author),
        character = semantic_payload.character,
        declared_control = control,
        sequence_length = #sequence,
        local_filename = basename(context.file_name) or basename(context.file_path)
    }
    return identity, canonical
end

local function iso8601_utc()
    return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function normalized_failure_code(reason)
    reason = clean_text(reason)
    if not reason then return nil end
    local code = reason:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if code == "" then return "unknown" end
    return code:sub(1, 80)
end

local function ensure_output_directory()
    if fs and fs.create_dir then
        pcall(fs.create_dir, "SF6_TrainingRemoteControl_data")
        pcall(fs.create_dir, Telemetry.OUTPUT_DIR)
    end
end

local function append_event(event)
    ensure_output_directory()
    local file, open_error = io.open(Telemetry.OUTPUT_FILE, "ab")
    if not file then return false, tostring(open_error or "open failed") end
    local ok, write_error = pcall(function()
        file:write(encode_json(event), "\n")
        file:flush()
    end)
    file:close()
    if not ok then return false, tostring(write_error) end
    return true
end

function Telemetry.begin_attempt(context)
    context = type(context) == "table" and context or {}
    local sequence = type(context.sequence) == "table" and context.sequence or nil
    local combo = sequence and state.identity_cache[sequence] or nil
    if not combo then
        combo = Telemetry.build_combo_identity(context)
        if sequence then state.identity_cache[sequence] = combo end
    end
    state.attempt = {
        combo = combo,
        source = context.source == "auto_demo" and "auto_demo" or "manual",
        player_control = context.player_control == "modern" and "modern" or "classic",
        projection = clean_text(context.projection) or "none",
        demo_kind = clean_text(context.demo_kind),
        started_at = iso8601_utc(),
        started_frame = tonumber(context.engine_frame or 0) or 0,
        terminal = false
    }
    return state.attempt
end

function Telemetry.cancel_attempt()
    state.attempt = nil
end

function Telemetry.finish_attempt(outcome, context)
    context = type(context) == "table" and context or {}
    if outcome ~= "success" and outcome ~= "fail" then return false, "unsupported outcome" end
    local attempt = state.attempt
    if not attempt or attempt.terminal then return false, "no active attempt" end
    attempt.terminal = true

    state.event_counter = state.event_counter + 1
    local occurred_at = iso8601_utc()
    local event_seed = table.concat({
        occurred_at,
        tostring(os.clock()),
        tostring(state.event_counter),
        tostring(attempt.combo.revision_hash),
        tostring(outcome)
    }, "|")
    local current_frame = tonumber(context.engine_frame or attempt.started_frame) or attempt.started_frame
    local event = {
        schema = Telemetry.SCHEMA,
        event_id = Telemetry.sha256(event_seed),
        anonymous = true,
        occurred_at = occurred_at,
        started_at = attempt.started_at,
        combo = attempt.combo,
        runtime = {
            sf6cc_version = Telemetry.MOD_VERSION,
            player_control = attempt.player_control,
            projection = attempt.projection,
            source = attempt.source,
            demo_kind = attempt.demo_kind
        },
        result = {
            outcome = outcome,
            failure_code = outcome == "fail" and normalized_failure_code(context.failure_reason) or nil,
            failure_reason = outcome == "fail" and clean_text(context.failure_reason) or nil,
            reached_step = tonumber(context.current_step),
            total_steps = tonumber(context.total_steps or attempt.combo.sequence_length),
            elapsed_frames = math.max(0, current_frame - attempt.started_frame)
        }
    }

    local ok, err = append_event(event)
    if not ok then
        state.last_error = err
        pcall(print, "[ComboTrials.Telemetry] append failed: " .. tostring(err))
        return false, err
    end
    state.last_error = nil
    return true, event
end

function Telemetry.get_state()
    return state
end

return Telemetry
