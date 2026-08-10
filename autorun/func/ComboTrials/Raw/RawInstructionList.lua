-- RawInstructionList.lua
-- Builds one display row per Atomic Action instance from RawCatalog facts.

local RawInstructionList = {
    name = "ComboTrials.Raw.RawInstructionList",
    NO_DIRECT_BCM_BINDING = "NO_DIRECT_BCM_BINDING",
}

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")

local function clone(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = clone(item) end
    return copy
end

local function instances_from(source)
    if AtomicTrace.is_trace(source) then return source:get_instances() end
    if type(source) == "table" and type(source.instances) == "table" then
        return source.instances
    end
    if type(source) == "table" then return source end
    return nil
end

local function ordered_bindings(bindings, preferred_profile)
    local ordered = {}
    for index, binding in ipairs(bindings or {}) do
        ordered[index] = { binding = binding, source_index = index }
    end
    table.sort(ordered, function(left, right)
        local left_preferred = left.binding.profile_name == preferred_profile
        local right_preferred = right.binding.profile_name == preferred_profile
        if left_preferred ~= right_preferred then return left_preferred end
        return left.source_index < right.source_index
    end)
    local result = {}
    for index, item in ipairs(ordered) do result[index] = item.binding end
    return result
end

local function variant_from(catalog, binding, binding_index)
    local definition_uid = type(binding.command_definition_uids) == "table"
        and binding.command_definition_uids[binding_index] or nil
    local definition = definition_uid and catalog:get_definition(definition_uid) or nil
    local token = type(binding.direct_command_tokens) == "table"
        and binding.direct_command_tokens[binding_index] or nil
    local variant_index = type(binding.variant_indexes) == "table"
        and binding.variant_indexes[binding_index] or nil
    return {
        profile_name = binding.profile_name,
        enabled = binding.enabled == true,
        ng_flag = binding.ng_flag,
        command_token = tostring(token or ""),
        raw_command_uid = binding.raw_command_uid,
        raw_trigger_uid = binding.raw_trigger_uid,
        trigger_index = binding.trigger_index,
        command_definition_uid = definition_uid,
        command_no = binding.command_no,
        command_index = binding.command_index,
        variant_index = variant_index,
        inputs = definition and clone(definition.inputs) or {},
        button_mask = binding.button_mask,
        button_condition = binding.button_condition,
        dc_exc_flags = binding.dc_exc_flags,
        ng_key_flags = binding.ng_key_flags,
        preceding_time = binding.preceding_time,
    }
end

local function display_for_variants(action_id, variants)
    local labels = {}
    for _, variant in ipairs(variants) do
        if variant.command_token ~= "" then
            local variant_label = variant.variant_index ~= nil
                and string.format(" v%s", tostring(variant.variant_index)) or ""
            labels[#labels + 1] = string.format("[%s%s] %s%s",
                tostring(variant.profile_name),
                variant_label,
                variant.command_token,
                variant.enabled and "" or " (disabled)")
        end
    end
    if #labels == 0 then
        return "Action " .. tostring(action_id), RawInstructionList.NO_DIRECT_BCM_BINDING
    end
    return "Action " .. tostring(action_id) .. " | "
        .. table.concat(labels, " | "), "DIRECT"
end

function RawInstructionList.build_rows(source, catalog, preferred_profile)
    local instances = instances_from(source)
    if type(instances) ~= "table" then return nil, "invalid_atomic_trace" end
    if type(catalog) ~= "table" or type(catalog.get_bindings) ~= "function"
        or type(catalog.get_definition) ~= "function" then
        return nil, "invalid_raw_catalog"
    end
    local rows = {}
    for index, instance in ipairs(instances) do
        if type(instance) ~= "table" or type(instance.action_id) ~= "number" then
            return nil, "invalid_atomic_instance"
        end
        local bindings = catalog:get_bindings(instance.action_id)
        local ordered = ordered_bindings(bindings or {}, preferred_profile)
        local variants = {}
        for _, binding in ipairs(ordered) do
            local definition_count = type(binding.command_definition_uids) == "table"
                and #binding.command_definition_uids or 0
            local token_count = type(binding.direct_command_tokens) == "table"
                and #binding.direct_command_tokens or 0
            local variant_count = type(binding.variant_indexes) == "table"
                and #binding.variant_indexes or 0
            local binding_count = math.max(definition_count, token_count, variant_count)
            for binding_index = 1, binding_count do
                variants[#variants + 1] = variant_from(catalog, binding, binding_index)
            end
        end
        local display_text, status = display_for_variants(instance.action_id, variants)
        rows[index] = {
            step = instance.step or index,
            occurrence = instance.occurrence,
            action_id = instance.action_id,
            enter_frame = instance.enter_frame,
            exit_frame = instance.exit_frame,
            action_frame_start = instance.action_frame_start,
            action_frame_end = instance.action_frame_end,
            status = status,
            display_text = display_text,
            variants = variants,
        }
    end
    return rows
end

return RawInstructionList
