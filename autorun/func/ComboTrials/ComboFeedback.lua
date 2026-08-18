local SF6CCVersion = require("func/SF6CC_Version")
local Telemetry = require("func/ComboTrials/Telemetry")

local Feedback = {
    SCHEMA = "sf6cc.combo_feedback_outbox.v1",
    ITEM_SCHEMA = "sf6cc.combo_feedback.v1",
    ACK_SCHEMA = "sf6cc.combo_feedback_ack.v1",
    OUTPUT_DIR = "SF6_TrainingRemoteControl_data/ComboFeedback",
    OUTPUT_FILE = "SF6_TrainingRemoteControl_data/ComboFeedback/feedback-outbox-v1.json",
    ACK_FILE = "SF6_TrainingRemoteControl_data/ComboFeedback/feedback-ack-v1.json",
    MAX_ITEMS = 100,
    MAX_DESCRIPTION_BYTES = 1024,
    MAX_OUTPUT_BYTES = 262144,
}

local ALLOWED_CATEGORIES = {
    unrecognized_action_id = true,
    detection_error = true,
    demo_error = true,
    other = true,
}

local function clean_text(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function valid_id(value)
    return type(value) == "string" and #value == 32
        and value:match("^[0-9a-f]+$") ~= nil
end

local function empty_outbox()
    return { schema = Feedback.SCHEMA, items = {} }
end

local function validate_outbox(value)
    if type(value) ~= "table" or value.schema ~= Feedback.SCHEMA then
        return nil, "invalid_outbox_schema"
    end
    if type(value.items) ~= "table" or #value.items > Feedback.MAX_ITEMS then
        return nil, "invalid_outbox_items"
    end
    for _, item in ipairs(value.items) do
        if type(item) ~= "table" or item.schema ~= Feedback.ITEM_SCHEMA
            or not valid_id(item.feedback_id)
            or ALLOWED_CATEGORIES[item.category] ~= true then
            return nil, "invalid_outbox_item"
        end
    end
    return value
end

function Feedback.new(dependencies)
    local deps = assert(type(dependencies) == "table" and dependencies,
        "ComboFeedback dependencies are required")
    for _, name in ipairs({
        "probe", "read", "decode", "encode", "atomic_write",
        "random_id", "now", "build_identity",
    }) do
        assert(type(deps[name]) == "function", "ComboFeedback dependency missing: " .. name)
    end

    local producer = {}

    local function read_outbox()
        local ok_probe, status, probe_error = pcall(deps.probe, Feedback.OUTPUT_FILE)
        if not ok_probe then return nil, tostring(status) end
        if status == nil then return nil, tostring(probe_error or "outbox_probe_failed") end
        if status == "missing" then return empty_outbox() end
        if status ~= "exists" then return nil, "invalid_outbox_probe_status" end

        local ok_read, raw = pcall(deps.read, Feedback.OUTPUT_FILE)
        if not ok_read then return nil, tostring(raw) end
        local ok_decode, value = pcall(deps.decode, raw)
        if not ok_decode then return nil, tostring(value) end
        return validate_outbox(value)
    end

    local function acknowledged_ids()
        local ok_read, raw = pcall(deps.read, Feedback.ACK_FILE)
        if not ok_read or raw == nil or raw == "" then return {} end
        local ok_decode, value = pcall(deps.decode, raw)
        if not ok_decode or type(value) ~= "table" or value.schema ~= Feedback.ACK_SCHEMA
            or type(value.acknowledged_feedback_ids) ~= "table" then
            return {}
        end

        local ids = {}
        local count = 0
        for _, feedback_id in ipairs(value.acknowledged_feedback_ids) do
            if valid_id(feedback_id) then
                ids[feedback_id] = true
                count = count + 1
                if count >= Feedback.MAX_ITEMS * 4 then break end
            end
        end
        return ids
    end

    function producer:submit(context)
        context = type(context) == "table" and context or {}
        if ALLOWED_CATEGORIES[context.category] ~= true then
            return false, "invalid_category"
        end

        local description = clean_text(context.description)
        if #description > Feedback.MAX_DESCRIPTION_BYTES then
            return false, "description_too_long"
        end

        local sequence = context.sequence
        if type(sequence) ~= "table" and type(context.file_path) == "string" then
            local ok_load, loaded = pcall(json.load_file, context.file_path)
            if ok_load then sequence = loaded end
        end
        if type(sequence) ~= "table" or type(sequence[1]) ~= "table" then
            return false, "combo_load_failed"
        end

        local outbox, outbox_error = read_outbox()
        if not outbox then return false, outbox_error end

        local acked = acknowledged_ids()
        local retained = {}
        for _, item in ipairs(outbox.items) do
            if acked[item.feedback_id] ~= true then retained[#retained + 1] = item end
        end
        if #retained >= Feedback.MAX_ITEMS then return false, "outbox_full" end

        local ok_identity, identity = pcall(deps.build_identity, {
            sequence = sequence,
            file_path = context.file_path,
            character = context.character,
            declared_control = context.declared_control,
        })
        if not ok_identity or type(identity) ~= "table"
            or type(identity.revision_hash) ~= "string"
            or identity.identity_schema ~= Telemetry.IDENTITY_SCHEMA then
            return false, "identity_failed"
        end

        local ok_id, feedback_id = pcall(deps.random_id)
        if not ok_id or not valid_id(feedback_id) then return false, "feedback_id_failed" end

        local event = {
            schema = Feedback.ITEM_SCHEMA,
            feedback_id = feedback_id,
            created_at = deps.now(),
            category = context.category,
            description = description,
            combo = {
                combo_id = clean_text(identity.combo_id) ~= "" and identity.combo_id or nil,
                revision_hash = identity.revision_hash,
                identity_schema = identity.identity_schema,
                title = clean_text(identity.title) ~= "" and identity.title or "未命名连段",
                author = clean_text(identity.author) ~= "" and identity.author or nil,
                character = clean_text(identity.character) ~= "" and identity.character or "Unknown",
                control_mode = identity.declared_control == "modern" and "modern" or "classic",
                step_count = math.max(0, math.floor(tonumber(context.display_step_count)
                    or tonumber(identity.sequence_length) or #sequence)),
            },
            runtime = {
                mod_version = deps.mod_version,
                game_build = deps.game_build,
            },
        }

        retained[#retained + 1] = event
        local next_outbox = { schema = Feedback.SCHEMA, items = retained }
        local ok_encode, raw = pcall(deps.encode, next_outbox)
        if not ok_encode or type(raw) ~= "string" or raw == "" then
            return false, "outbox_encode_failed"
        end
        if #raw > Feedback.MAX_OUTPUT_BYTES then return false, "outbox_too_large" end

        local ok_write, write_result, write_error = pcall(
            deps.atomic_write,
            Feedback.OUTPUT_FILE,
            raw
        )
        if not ok_write or write_result ~= true then
            return false, tostring(write_error or write_result or "outbox_write_failed")
        end
        return true, event
    end

    return producer
end

local runtime_producer

local function runtime()
    if runtime_producer then return runtime_producer end
    runtime_producer = Feedback.new({
        probe = function(path)
            if type(sf6cc_atomic_file) ~= "table"
                or type(sf6cc_atomic_file.probe) ~= "function" then
                return nil, "native_atomic_probe_unavailable"
            end
            return sf6cc_atomic_file.probe(path)
        end,
        read = function(path)
            if not fs or type(fs.read) ~= "function" then error("fs.read unavailable") end
            return fs.read(path)
        end,
        decode = function(raw)
            if not json or type(json.load_string) ~= "function" then
                error("json.load_string unavailable")
            end
            return json.load_string(raw)
        end,
        encode = function(value)
            if not json or type(json.dump_string) ~= "function" then
                error("json.dump_string unavailable")
            end
            return json.dump_string(value, 2)
        end,
        atomic_write = function(path, raw)
            if type(sf6cc_atomic_file) ~= "table"
                or type(sf6cc_atomic_file.write) ~= "function" then
                return false, "native_atomic_write_unavailable"
            end
            return sf6cc_atomic_file.write(path, raw)
        end,
        random_id = function()
            if type(sf6cc_atomic_file) ~= "table"
                or type(sf6cc_atomic_file.random_id) ~= "function" then
                return nil
            end
            return sf6cc_atomic_file.random_id()
        end,
        now = function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end,
        build_identity = Telemetry.build_combo_identity,
        mod_version = SF6CCVersion.PRODUCT_VERSION,
        game_build = SF6CCVersion.GAME_VERSION,
    })
    return runtime_producer
end

function Feedback.submit(context)
    local ok, result, detail = pcall(runtime().submit, runtime(), context)
    if not ok then return false, tostring(result) end
    return result, detail
end

return Feedback
