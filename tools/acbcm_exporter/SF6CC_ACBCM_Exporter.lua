-- SF6CC_ACBCM_Exporter.lua
--
-- One-shot exporter of the current P1 fighter's native AC and BCM data.
-- Origin: SF6CR-evidence/tools/SF6CR_ExportFullEvidence.lua, adopted by
-- SF6CC so the AC+BCM pipeline can run on a fighter's release day.
--
-- Usage (see tools/acbcm_exporter/README.md): enter Training Mode with the
-- fighter as P1 and Classic controls, then run this file once from
-- REFramework (ScriptRunner > Run script). Each run writes two files:
--   reframework/data/SF6CC_ACBCM/f<id>-fab-action-catalog-full-classic.json
--   reframework/data/SF6CC_ACBCM/f<id>-fab-bcm-full-classic.json
--
-- The exporter is read-only and registers no frame callback.
-- It does not decode commands, choose norm/sprt/easy/supr, or classify AC edges.
-- It exports a normalized object graph:
--   * type_catalog: reflected field definitions + scalar static fields once per type
--   * objects: every encountered managed object/collection exactly once
--   * records/refs: stable references into the object table
-- Int32-keyed dictionaries (BCM trigger groups, commands, charges) are
-- exported from their backing entries with every key; items carry
-- index == key. Earlier SF6CR exports enumerated get_Item(0..Count-1), which
-- is a key lookup and silently dropped every key >= Count.
--
-- The mode label is supplied by the caller. The script does not change the
-- game's control mode and does not guess it.

-- Set this before each run:
--   "classic" after switching the game to Classic controls
--   "modern"  after switching the game to Modern controls
local AUTO_CAPTURE_MODE = "classic"

local PLAYER_INDEX = 0
local CHARACTER_RESOURCE_INDEX = 0
local COMMON_RESOURCE_INDEX = 6

local OUTPUT_DIR = "SF6CC_ACBCM/"
local AC_SCHEMA = "sf6cr.action-catalog-full.v2"
local BCM_SCHEMA = "sf6cr.bcm-full.v2"

-- Safety limits are deliberately generous. If any limit is reached, the JSON
-- is still written but hard_gate_passed=false and truncation_reasons is filled.
local MAX_DEPTH = 20
local MAX_OBJECTS = 1000000
local MAX_COLLECTION_ITEMS = 1000000

local status = {
    schema = "sf6cr.full-evidence-status.v2",
    ready = false,
    capture_in_progress = false,
    capture_count = 0,
    fighter_id = nil,
    character_name = nil,
    character_slug = nil,
    character_name_source = nil,
    last_mode = nil,
    ac_output_path = nil,
    bcm_output_path = nil,
    ac_record_count = 0,
    bcm_trigger_count = 0,
    ac_hard_gate_passed = false,
    bcm_hard_gate_passed = false,
    last_error = nil,
}

local function log_info(message)
    if log ~= nil and log.info ~= nil then
        log.info("[SF6CC ACBCM Exporter] " .. tostring(message))
    end
end

local function log_error(message)
    if log ~= nil and log.error ~= nil then
        log.error("[SF6CC ACBCM Exporter] " .. tostring(message))
    end
end

local function safe_index(object, key)
    if object == nil then
        return nil
    end

    local ok, value = pcall(function()
        return object[key]
    end)
    if ok and value ~= nil then
        return value
    end

    if type(key) == "string" then
        local ok_field, field_value = pcall(function()
            return object:get_field(key)
        end)
        if ok_field then
            return field_value
        end
    end

    return nil
end

local function safe_call(object, method_names, ...)
    if object == nil then
        return nil
    end

    local args = { ... }
    for _, method_name in ipairs(method_names) do
        local ok, value = pcall(function()
            return object:call(method_name, table.unpack(args))
        end)
        if ok and value ~= nil then
            return value
        end

        local direct_name = method_name:gsub("%(%).*", "")
        local direct = safe_index(object, direct_name)
        if type(direct) == "function" then
            local ok_direct, direct_value =
                pcall(direct, object, table.unpack(args))
            if ok_direct and direct_value ~= nil then
                return direct_value
            end
        end
    end

    return nil
end

local function scalar_value(value)
    local value_type = type(value)
    if value == nil
        or value_type == "string"
        or value_type == "number"
        or value_type == "boolean" then
        return value
    end

    for _, name in ipairs({
        "value__",
        "mValue",
        "Value",
        "value",
        "v",
    }) do
        local candidate = safe_index(value, name)
        local candidate_type = type(candidate)
        if candidate_type == "string"
            or candidate_type == "number"
            or candidate_type == "boolean" then
            return candidate
        end
    end

    return nil
end

local function integer_value(value)
    local scalar = scalar_value(value)
    if type(scalar) == "number" then
        return math.tointeger(scalar) or math.floor(scalar)
    end
    return nil
end

local function type_definition(object)
    if object == nil then
        return nil
    end

    local ok, definition = pcall(function()
        return object:get_type_definition()
    end)
    if ok then
        return definition
    end
    return nil
end

local function definition_name(definition)
    if definition == nil then
        return nil
    end

    local ok, name = pcall(function()
        return definition:get_full_name() or definition:get_name()
    end)
    if ok then
        return name
    end
    return nil
end

local function type_name(object)
    return definition_name(type_definition(object))
end

local function field_name(field)
    if field == nil then
        return nil
    end

    local ok, name = pcall(function()
        return field:get_name()
    end)
    if ok then
        return name
    end
    return nil
end

local function declared_type_name(field)
    if field == nil then
        return nil
    end

    local ok, field_type = pcall(function()
        return field:get_type()
    end)
    if ok and field_type ~= nil then
        return definition_name(field_type)
    end
    return nil
end

local function field_is_static(field)
    if field == nil then
        return false
    end

    local ok, result = pcall(function()
        return field:is_static()
    end)
    return ok and result == true
end

local function field_offset(field)
    if field == nil then
        return nil
    end

    local ok, result = pcall(function()
        return field:get_offset()
    end)
    if ok and type(result) == "number" then
        return result
    end
    return nil
end

-- Base classes whose fields are game data. get_fields() only returns the
-- fields a type declares itself, so without walking these parents every
-- CharacterAsset.*Key would lose the frame window it inherits from
-- via.fighter.ActionKey. System.* and engine object bases are not walked.
-- Marked in each export as inherited_fields = "game-namespaces.v1".
local INHERITED_FIELD_NAMESPACES = {
    "via.fighter.",
    "CharacterAsset.",
    "app.battle.",
    "BCM.",
}

local function walks_inherited_fields(definition)
    local name = definition_name(definition)
    if type(name) ~= "string" then
        return false
    end
    for _, prefix in ipairs(INHERITED_FIELD_NAMESPACES) do
        if name:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function parent_definition(definition)
    local ok, parent = pcall(function()
        return definition:get_parent_type()
    end)
    if ok then
        return parent
    end
    return nil
end

local MAX_INHERITANCE_DEPTH = 16

-- Native bases keep their data behind property getters instead of TDB
-- fields: the first export with the inherited-field walk (2026-10-09) found
-- no fields on CharacterAsset.ActionBase or via.fighter.ActionKey, which own
-- every key's frame window. For these bases, zero-argument instance getters
-- with a primitive return type are read as extra fields (source = "property"),
-- and every member is listed in base_type_catalog.
local PROPERTY_BASES = {
    ["via.fighter.ActionKey"] = true,
    ["CharacterAsset.ActionBase"] = true,
}
local PRIMITIVE_TYPES = {
    ["System.Boolean"] = true, ["System.Byte"] = true, ["System.SByte"] = true,
    ["System.Int16"] = true, ["System.UInt16"] = true,
    ["System.Int32"] = true, ["System.UInt32"] = true,
    ["System.Int64"] = true, ["System.UInt64"] = true,
    ["System.Single"] = true, ["System.Double"] = true,
}

local function resolve_definition(object_or_definition)
    local definition = object_or_definition
    if definition ~= nil then
        local ok_type = pcall(function()
            return definition:get_fields()
        end)
        if not ok_type then
            definition = type_definition(object_or_definition)
        end
    end
    return definition
end

-- Full names of the parent chain, nearest first.
local function inheritance_chain(object_or_definition)
    local chain = {}
    local current = parent_definition(resolve_definition(object_or_definition))
    while current ~= nil and #chain < MAX_INHERITANCE_DEPTH do
        local name = definition_name(current)
        if name == nil then
            break
        end
        chain[#chain + 1] = name
        current = parent_definition(current)
    end
    return chain
end

local function member_name(member)
    local ok, name = pcall(function()
        return member:get_name()
    end)
    if ok then
        return name
    end
    return nil
end

local function method_param_count(method)
    local ok, count = pcall(function()
        return method:get_num_params()
    end)
    if ok and type(count) == "number" then
        return count
    end
    return nil
end

local function method_return_type(method)
    local ok, return_type = pcall(function()
        return method:get_return_type()
    end)
    if ok then
        return definition_name(return_type)
    end
    return nil
end

local function method_is_static(method)
    local ok, static = pcall(function()
        return method:is_static()
    end)
    return ok and static == true
end

-- Members of one property base, for base_type_catalog.
local function describe_base(definition)
    local result = { fields = {}, methods = {} }
    local ok_fields, fields = pcall(function()
        return definition:get_fields()
    end)
    if ok_fields and fields ~= nil then
        pcall(function()
            for _, field in pairs(fields) do
                result.fields[#result.fields + 1] = member_name(field)
            end
        end)
    end
    local ok_methods, methods = pcall(function()
        return definition:get_methods()
    end)
    if ok_methods and methods ~= nil then
        pcall(function()
            for _, method in pairs(methods) do
                result.methods[#result.methods + 1] = {
                    name = member_name(method),
                    params = method_param_count(method),
                    returns = method_return_type(method),
                    static = method_is_static(method),
                }
            end
        end)
    end
    table.sort(result.fields, function(a, b) return tostring(a) < tostring(b) end)
    table.sort(result.methods, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end

local property_getter_cache = {}

-- Zero-argument instance getters with a primitive return type declared on a
-- property base in the type's parent chain (nearest first, first name wins).
-- base_catalog receives the members of every property base on the chain.
local function property_getters(definition, base_catalog)
    local key = definition_name(definition)
    if key == nil then
        return {}
    end
    local cached = property_getter_cache[key]
    if cached ~= nil then
        if base_catalog ~= nil then
            for name, base in pairs(cached.bases) do
                if base_catalog[name] == nil then
                    base_catalog[name] = describe_base(base)
                end
            end
        end
        return cached.getters
    end
    local getters = {}
    local bases = {}
    local seen = {}
    local current = definition
    local depth = 0
    while current ~= nil and depth < MAX_INHERITANCE_DEPTH do
        local name = definition_name(current)
        if name ~= nil and PROPERTY_BASES[name] then
            bases[name] = current
            if base_catalog ~= nil and base_catalog[name] == nil then
                base_catalog[name] = describe_base(current)
            end
            local ok, methods = pcall(function()
                return current:get_methods()
            end)
            if ok and methods ~= nil then
                pcall(function()
                    for _, method in pairs(methods) do
                        local method_label = member_name(method)
                        local returns = method_return_type(method)
                        if type(method_label) == "string"
                            and method_label:sub(1, 4) == "get_"
                            and method_param_count(method) == 0
                            and not method_is_static(method)
                            and PRIMITIVE_TYPES[returns] then
                            local property = method_label:sub(5)
                            if property ~= "" and not seen[property] then
                                seen[property] = true
                                getters[#getters + 1] = {
                                    name = property,
                                    method = method,
                                    returns = returns,
                                    declared_in = name,
                                }
                            end
                        end
                    end
                end)
            end
        end
        current = parent_definition(current)
        depth = depth + 1
    end
    table.sort(getters, function(a, b) return a.name < b.name end)
    property_getter_cache[key] = { getters = getters, bases = bases }
    return getters
end

local function reflected_fields(object_or_definition)
    local definition = resolve_definition(object_or_definition)
    if definition == nil then
        return {}
    end

    local result = {}
    local seen = {}
    local current = definition
    local depth = 0
    while current ~= nil and depth < MAX_INHERITANCE_DEPTH do
        local ok, fields = pcall(function()
            return current:get_fields()
        end)
        if ok and fields ~= nil then
            pcall(function()
                for _, field in pairs(fields) do
                    local name = field ~= nil and field_name(field) or nil
                    -- A derived declaration hides a base field of the same name.
                    if name ~= nil and not seen[name] then
                        seen[name] = true
                        result[#result + 1] = field
                    end
                end
            end)
        end
        local parent = parent_definition(current)
        if parent == nil or not walks_inherited_fields(parent) then
            break
        end
        current = parent
        depth = depth + 1
    end

    table.sort(result, function(a, b)
        return tostring(field_name(a) or "")
            < tostring(field_name(b) or "")
    end)
    return result
end

local function read_field_value(instance, field, name)
    if field ~= nil then
        local ok, value = pcall(function()
            return field:get_data(instance)
        end)
        if ok then
            return true, value
        end
    end

    local ok_index, value = pcall(function()
        return safe_index(instance, name)
    end)
    if ok_index then
        return true, value
    end

    return false, nil
end

local function collection_count(collection)
    if collection == nil then
        return nil
    end

    local count = safe_call(collection, {
        "get_Count()",
        "get_Count",
        "get_Length()",
        "get_Length",
        "GetCount()",
        "GetCount",
    })
    count = integer_value(count)
    if count ~= nil then
        return count
    end

    local object_type = type_name(collection) or ""
    local is_known_collection =
        object_type:match("%[%]$") ~= nil
        or object_type:find("System.Collections.", 1, true) ~= nil
        or object_type:find("System.Array", 1, true) ~= nil

    if not is_known_collection then
        return nil
    end

    for _, name in ipairs({
        "_size",
        "Count",
        "Length",
        "length",
    }) do
        local candidate = integer_value(safe_index(collection, name))
        if candidate ~= nil then
            return candidate
        end
    end

    return nil
end

local function collection_item(collection, index)
    if collection == nil then
        return nil
    end

    local direct = safe_index(collection, index)
    if direct ~= nil then
        return direct
    end

    return safe_call(collection, {
        "get_Item(System.Int32)",
        "get_Item",
        "Get(System.Int32)",
        "Get",
    }, index)
end

local function read_first(object, names)
    for _, name in ipairs(names) do
        local value = safe_index(object, name)
        if value ~= nil then
            return value, name
        end
    end
    return nil, nil
end

local function read_int(object, names)
    local value, source_name = read_first(object, names)
    return integer_value(value), source_name
end

-- Slots at or beyond the dictionary's internal used-slot count were never
-- used. A struct-valued dictionary (BCM.TRIGGER_GROUP) still holds default
-- values there, which read as non-nil (the first fixed export on 2026-10-09
-- carried 41-48 such key-0 slots per fighter), so the used-slot count bounds
-- the enumeration. Count (live entries) is the fallback; it is exact for
-- dictionaries that never had removals, which is how game data is loaded.
local function used_entry_slots(dictionary)
    for _, name in ipairs({ "_count", "count" }) do
        local ok, raw = pcall(function()
            return dictionary:get_field(name)
        end)
        local value = ok and integer_value(raw) or nil
        if value ~= nil and value >= 0 then
            return value, name
        end
    end
    return collection_count(dictionary), "Count"
end

local function dictionary_entries(dictionary)
    local result = {}
    if dictionary == nil then
        return result
    end

    local entries = safe_index(dictionary, "_entries")
    if entries == nil then
        return result
    end

    local used_slots, used_slots_source = used_entry_slots(dictionary)
    result.used_slots = used_slots
    result.used_slots_source = used_slots_source

    local count = collection_count(entries)
    if count ~= nil and used_slots ~= nil then
        count = math.min(count, used_slots)
    end
    if count ~= nil then
        for index = 0, count - 1 do
            local entry = collection_item(entries, index)
            if entry ~= nil then
                local value = safe_index(entry, "value")
                if value ~= nil then
                    result[#result + 1] = {
                        entry_index = index,
                        key = scalar_value(safe_index(entry, "key")),
                        hash_code =
                            scalar_value(safe_index(entry, "hashCode")),
                        next = scalar_value(safe_index(entry, "next")),
                        value = value,
                    }
                end
            end
        end
    else
        pcall(function()
            for index, entry in pairs(entries) do
                local slot = tonumber(index)
                local unused = used_slots ~= nil and slot ~= nil and slot >= used_slots
                if entry ~= nil and not unused then
                    local value = safe_index(entry, "value")
                    if value ~= nil then
                        result[#result + 1] = {
                            entry_index = scalar_value(index),
                            key = scalar_value(safe_index(entry, "key")),
                            hash_code =
                                scalar_value(safe_index(entry, "hashCode")),
                            next = scalar_value(safe_index(entry, "next")),
                            value = value,
                        }
                    end
                end
            end
        end)
    end

    table.sort(result, function(a, b)
        if tostring(a.key) ~= tostring(b.key) then
            return tostring(a.key) < tostring(b.key)
        end
        return tostring(a.entry_index) < tostring(b.entry_index)
    end)
    return result
end

local function is_int_keyed_dictionary(object_type)
    return type(object_type) == "string"
        and object_type:find("System.Collections.Generic.Dictionary`2<System.Int32,", 1, true) == 1
end

-- A removed entry keeps its slot: .NET Framework marks it with
-- hashCode == -1, .NET Core with next <= -3 (StartOfFreeList - freeList).
local function is_live_dictionary_entry(entry)
    local hash_code = tonumber(entry.hash_code)
    local next_index = tonumber(entry.next)
    return not (hash_code == -1 or (next_index ~= nil and next_index <= -3))
end

local function new_graph_context()
    return {
        next_object_id = 1,
        object_ids = {},
        objects = {},
        type_catalog = {},
        base_type_catalog = {},
        truncation_reasons = {},
        truncated = false,
    }
end

local function add_truncation(ctx, reason)
    ctx.truncated = true
    for _, existing in ipairs(ctx.truncation_reasons) do
        if existing == reason then
            return
        end
    end
    ctx.truncation_reasons[#ctx.truncation_reasons + 1] = reason
end

local function object_identity(object)
    local ok, text = pcall(tostring, object)
    if ok then
        return text
    end
    return nil
end

local function register_type(ctx, object)
    local definition = type_definition(object)
    local object_type = definition_name(definition) or "<unknown>"
    if ctx.type_catalog[object_type] ~= nil then
        return object_type
    end

    local entry = {
        object_type = object_type,
        inherits = inheritance_chain(definition),
        instance_fields = {},
        static_fields = {},
    }

    ctx.type_catalog[object_type] = entry

    for _, field in ipairs(reflected_fields(definition)) do
        local name = field_name(field)
        if name ~= nil then
            local definition_record = {
                name = name,
                declared_type = declared_type_name(field),
                offset = field_offset(field),
            }

            if field_is_static(field) then
                local ok, value = read_field_value(object, field, name)
                local scalar = ok and scalar_value(value) or nil
                if scalar ~= nil then
                    definition_record.value = scalar
                elseif ok and value ~= nil then
                    definition_record.value_type = type_name(value)
                elseif not ok then
                    definition_record.read_error = true
                end
                entry.static_fields[#entry.static_fields + 1] =
                    definition_record
            else
                entry.instance_fields[#entry.instance_fields + 1] =
                    definition_record
            end
        end
    end

    table.sort(entry.instance_fields, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)
    table.sort(entry.static_fields, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    return object_type
end

local encode_value

encode_value = function(ctx, value, depth)
    local scalar = scalar_value(value)
    if scalar ~= nil then
        return {
            kind = type(scalar),
            value = scalar,
        }
    end

    if value == nil then
        return {
            kind = "nil",
        }
    end

    local identity = object_identity(value)
    if identity ~= nil and ctx.object_ids[identity] ~= nil then
        return {
            kind = "ref",
            object_id = ctx.object_ids[identity],
        }
    end

    if #ctx.objects >= MAX_OBJECTS then
        add_truncation(ctx, "max-objects")
        return {
            kind = "truncated",
            reason = "max-objects",
            object_type = type_name(value),
        }
    end

    local object_id = ctx.next_object_id
    ctx.next_object_id = ctx.next_object_id + 1

    if identity ~= nil then
        ctx.object_ids[identity] = object_id
    end

    local object_type = register_type(ctx, value)
    local node = {
        object_id = object_id,
        object_type = object_type,
        kind = "managed-object",
        fields = {},
    }
    ctx.objects[#ctx.objects + 1] = node

    if depth <= 0 then
        add_truncation(ctx, "max-depth")
        node.truncated = true
        node.truncation_reason = "max-depth"
        return {
            kind = "ref",
            object_id = object_id,
        }
    end

    if is_int_keyed_dictionary(object_type) then
        local entries = {}
        local all_entries = dictionary_entries(value)
        for _, entry in ipairs(all_entries) do
            if is_live_dictionary_entry(entry) and tonumber(entry.key) ~= nil then
                entries[#entries + 1] = entry
            end
        end
        table.sort(entries, function(a, b)
            return tonumber(a.key) < tonumber(b.key)
        end)
        node.kind = "collection"
        node.dictionary = true
        node.count = collection_count(value) or #entries
        node.used_slots = all_entries.used_slots
        node.used_slots_source = all_entries.used_slots_source
        node.items = {}
        for _, entry in ipairs(entries) do
            node.items[#node.items + 1] = {
                index = tonumber(entry.key),
                key = tonumber(entry.key),
                entry_index = entry.entry_index,
                value = encode_value(ctx, entry.value, depth - 1),
            }
        end
        if #entries ~= node.count then
            node.entry_count_mismatch = { count = node.count, entries = #entries }
        end
        return {
            kind = "ref",
            object_id = object_id,
        }
    end

    local count = collection_count(value)
    if count ~= nil then
        node.kind = "collection"
        node.count = count
        node.items = {}

        local limit = count
        if count > MAX_COLLECTION_ITEMS then
            limit = MAX_COLLECTION_ITEMS
            add_truncation(ctx, "max-collection-items")
            node.items_truncated = count - limit
        end

        for index = 0, limit - 1 do
            node.items[#node.items + 1] = {
                index = index,
                value = encode_value(
                    ctx,
                    collection_item(value, index),
                    depth - 1
                ),
            }
        end

        return {
            kind = "ref",
            object_id = object_id,
        }
    end

    for _, field in ipairs(reflected_fields(value)) do
        if not field_is_static(field) then
            local name = field_name(field)
            if name ~= nil then
                local ok, field_value =
                    read_field_value(value, field, name)
                if ok then
                    node.fields[#node.fields + 1] = {
                        name = name,
                        declared_type = declared_type_name(field),
                        value = encode_value(
                            ctx,
                            field_value,
                            depth - 1
                        ),
                    }
                else
                    node.fields[#node.fields + 1] = {
                        name = name,
                        declared_type = declared_type_name(field),
                        value = {
                            kind = "read-error",
                        },
                    }
                end
            end
        end
    end

    local value_definition = type_definition(value)
    if value_definition ~= nil then
        local present = {}
        for _, field in ipairs(node.fields) do
            present[field.name] = true
        end
        for _, getter in ipairs(property_getters(value_definition, ctx.base_type_catalog)) do
            if not present[getter.name] then
                local ok, result = pcall(function()
                    return getter.method:call(value)
                end)
                local scalar = ok and scalar_value(result) or nil
                if scalar ~= nil then
                    node.fields[#node.fields + 1] = {
                        name = getter.name,
                        declared_type = getter.returns,
                        source = "property",
                        declared_in = getter.declared_in,
                        value = {
                            kind = type(scalar),
                            value = scalar,
                        },
                    }
                end
            end
        end
    end

    table.sort(node.fields, function(a, b)
        return tostring(a.name) < tostring(b.name)
    end)

    return {
        kind = "ref",
        object_id = object_id,
    }
end

local function type_catalog_to_list(ctx)
    local result = {}
    for _, entry in pairs(ctx.type_catalog) do
        result[#result + 1] = entry
    end
    table.sort(result, function(a, b)
        return tostring(a.object_type) < tostring(b.object_type)
    end)
    return result
end

local function get_runtime()
    local g_battle_type = sdk.find_type_definition("gBattle")
    if g_battle_type == nil then
        return nil, "gBattle type definition unavailable"
    end

    local player_field = g_battle_type:get_field("Player")
    local resource_field = g_battle_type:get_field("Resource")
    local command_field = g_battle_type:get_field("Command")

    if player_field == nil
        or resource_field == nil
        or command_field == nil then
        return nil,
            "gBattle Player/Resource/Command field unavailable"
    end

    local player = player_field:get_data()
    local resource = resource_field:get_data()
    local command = command_field:get_data()

    if player == nil or resource == nil or command == nil then
        return nil,
            "gBattle Player/Resource/Command unavailable; enter Training Mode"
    end

    local player_types = safe_index(player, "mPlayerType")
    local fighter_id_raw = safe_index(player_types, PLAYER_INDEX)
    local fighter_id = integer_value(fighter_id_raw)
    if fighter_id == nil then
        return nil, "could not read P1 fighter_id"
    end

    return {
        player = player,
        resource = resource,
        command = command,
        fighter_id = fighter_id,
        fighter_id_raw = fighter_id_raw,
        player_types = player_types,
    }, nil
end

local function trim_string(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("%z", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function title_case_enum(value)
    value = trim_string(value)
    if value == nil then
        return nil
    end

    if value:match("^[A-Z][A-Z0-9_%-]*$") then
        local parts = {}
        for part in value:gmatch("[^_%-]+") do
            if #part <= 2 then
                parts[#parts + 1] = part
            else
                parts[#parts + 1] =
                    part:sub(1, 1)
                    .. part:sub(2):lower()
            end
        end
        if #parts > 0 then
            return table.concat(parts, "-")
        end
    end

    return value
end

local function slugify(value)
    value = trim_string(value) or ""
    value = value:lower()
    value = value:gsub("[^%w]+", "-")
    value = value:gsub("^%-+", ""):gsub("%-+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function plausible_name(value)
    value = trim_string(value)
    if value == nil or #value < 2 or #value > 80 then
        return false
    end

    if value:find("\n", 1, true)
        or value:find("\r", 1, true) then
        return false
    end

    local lowered = value:lower()
    if lowered:find("system.", 1, true)
        or lowered:find("characterasset.", 1, true)
        or lowered:find("managedobject", 1, true)
        or lowered == "null"
        or lowered == "none" then
        return false
    end

    return value:match("[%a]") ~= nil
end

local function add_identity_candidate(
    candidates,
    value,
    source,
    score
)
    value = trim_string(value)
    if not plausible_name(value) then
        return
    end

    local normalized = title_case_enum(value)
    local slug = slugify(normalized)
    if slug == nil then
        return
    end

    for _, existing in ipairs(candidates) do
        if existing.normalized == normalized
            and existing.source == source then
            return
        end
    end

    candidates[#candidates + 1] = {
        raw = value,
        normalized = normalized,
        slug = slug,
        source = source,
        score = score,
    }
end

local function try_static_enum_name(
    runtime,
    candidates
)
    local player_definition = type_definition(runtime.player)
    if player_definition == nil then
        return
    end

    local ok_field, player_type_field = pcall(function()
        return player_definition:get_field("mPlayerType")
    end)
    if not ok_field or player_type_field == nil then
        return
    end

    local declared = declared_type_name(player_type_field)
    if declared == nil then
        return
    end

    local element_type_name =
        declared:gsub("%[%]$", "")
    local enum_definition =
        sdk.find_type_definition(element_type_name)
    if enum_definition == nil then
        return
    end

    for _, field in ipairs(reflected_fields(enum_definition)) do
        if field_is_static(field) then
            local name = field_name(field)
            local value = nil

            local ok_nil, result_nil = pcall(function()
                return field:get_data(nil)
            end)
            if ok_nil then
                value = result_nil
            else
                local ok_noarg, result_noarg = pcall(function()
                    return field:get_data()
                end)
                if ok_noarg then
                    value = result_noarg
                end
            end

            if integer_value(value) == runtime.fighter_id then
                add_identity_candidate(
                    candidates,
                    name,
                    "mPlayerType-enum-static-field",
                    1000
                )
            end
        end
    end
end

local function scan_name_candidates(
    object,
    path,
    depth,
    candidates,
    seen
)
    if object == nil or depth < 0 then
        return
    end

    local scalar = scalar_value(object)
    if type(scalar) == "string" then
        add_identity_candidate(
            candidates,
            scalar,
            path,
            40
        )
        return
    end
    if scalar ~= nil then
        return
    end

    local identity = tostring(object)
    if seen[identity] then
        return
    end
    seen[identity] = true

    for _, method_name in ipairs({
        "get_CharacterName()",
        "get_FighterName()",
        "get_CharaName()",
        "get_Name()",
        "ToString()",
    }) do
        local value = safe_call(object, { method_name })
        if type(value) == "string" then
            local score =
                method_name == "ToString()" and 25 or 300
            add_identity_candidate(
                candidates,
                value,
                path .. ":" .. method_name,
                score
            )
        end
    end

    local count = collection_count(object)
    if count ~= nil then
        local limit = math.min(count, 8)
        for index = 0, limit - 1 do
            scan_name_candidates(
                collection_item(object, index),
                path .. "[" .. tostring(index) .. "]",
                depth - 1,
                candidates,
                seen
            )
        end
        return
    end

    for _, field in ipairs(reflected_fields(object)) do
        if not field_is_static(field) then
            local name = field_name(field)
            if name ~= nil then
                local ok, value =
                    read_field_value(object, field, name)
                if ok and value ~= nil then
                    local lowered = name:lower()
                    local score = 10
                    if lowered == "charactername"
                        or lowered == "fightername"
                        or lowered == "charaname"
                        or lowered == "name"
                        or lowered == "_name" then
                        score = 700
                    elseif lowered:find("name", 1, true) then
                        score = 450
                    elseif lowered:find("character", 1, true)
                        or lowered:find("fighter", 1, true)
                        or lowered:find("chara", 1, true) then
                        score = 250
                    elseif lowered:find("path", 1, true)
                        or lowered:find("resource", 1, true)
                        or lowered:find("asset", 1, true) then
                        score = 80
                    end

                    local scalar_value_found =
                        scalar_value(value)
                    if type(scalar_value_found) == "string" then
                        add_identity_candidate(
                            candidates,
                            scalar_value_found,
                            path .. "." .. name,
                            score
                        )
                    elseif depth > 0
                        and (
                            score >= 80
                            or name == "FAB"
                            or name == "Data"
                        ) then
                        scan_name_candidates(
                            value,
                            path .. "." .. name,
                            depth - 1,
                            candidates,
                            seen
                        )
                    end
                end
            end
        end
    end
end

local function detect_character_identity(runtime)
    local candidates = {}

    local enum_text = safe_call(
        runtime.fighter_id_raw,
        { "ToString()" }
    )
    if type(enum_text) == "string" then
        add_identity_candidate(
            candidates,
            enum_text,
            "fighter-id-enum-ToString",
            900
        )
    end

    try_static_enum_name(runtime, candidates)

    local resources = safe_index(
        runtime.resource,
        "Data"
    )
    local character_resource = safe_index(
        resources,
        CHARACTER_RESOURCE_INDEX
    )

    scan_name_candidates(
        character_resource,
        "gBattle.Resource.Data[0]",
        3,
        candidates,
        {}
    )

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        if #a.normalized ~= #b.normalized then
            return #a.normalized < #b.normalized
        end
        return a.normalized < b.normalized
    end)

    local selected = candidates[1]
    local name = nil
    local slug = nil
    local source = nil
    local confidence = "fallback"

    if selected ~= nil then
        name = selected.normalized
        slug = selected.slug
        source = selected.source
        confidence =
            selected.score >= 700 and "high"
            or selected.score >= 250 and "medium"
            or "low"
    end

    if name == nil or slug == nil then
        name = "Fighter " .. tostring(runtime.fighter_id)
        slug = "fighter-" .. tostring(runtime.fighter_id)
        source = "fighter-id-fallback"
    end

    local prefix = string.format("f%03d-fab", runtime.fighter_id)

    return {
        fighter_id = runtime.fighter_id,
        character_name = name,
        character_slug = slug,
        file_prefix = prefix,
        character_name_source = source,
        character_name_confidence = confidence,
        candidates = candidates,
    }
end

local function collect_action_catalog(runtime, identity, mode_label)
    local ctx = new_graph_context()
    local records = {}
    local collection_errors = {}
    local unique_ids_by_scope = {
        character = {},
        common = {},
    }
    local unique_sets = {
        character = {},
        common = {},
    }

    local resources = safe_index(runtime.resource, "Data")
    if resources == nil then
        error("gBattle.Resource.Data unavailable")
    end

    local function collect_resource(
        resource_index,
        source_scope
    )
        local resource = safe_index(resources, resource_index)
        if resource == nil then
            collection_errors[#collection_errors + 1] = {
                source_scope = source_scope,
                resource_index = resource_index,
                error = "resource unavailable",
            }
            return
        end

        local fab = safe_index(resource, "FAB")
        local style_dict = safe_index(fab, "StyleDict")
        local style_count = collection_count(style_dict)

        if fab == nil or style_dict == nil or style_count == nil then
            collection_errors[#collection_errors + 1] = {
                source_scope = source_scope,
                resource_index = resource_index,
                error = "FAB/StyleDict unavailable",
            }
            return
        end

        for style_index = 0, style_count - 1 do
            local style = safe_index(style_dict, style_index)
            local action_list = safe_index(style, "ActionList")

            for _, entry in ipairs(dictionary_entries(action_list)) do
                local action = entry.value
                local action_id =
                    integer_value(safe_index(action, "ActionID"))

                records[#records + 1] = {
                    native_action_id = action_id,
                    source_scope = source_scope,
                    resource_index = resource_index,
                    style_index = style_index,
                    dictionary_entry_index = entry.entry_index,
                    dictionary_key = entry.key,
                    dictionary_hash_code = entry.hash_code,
                    dictionary_next = entry.next,
                    action_ref = encode_value(
                        ctx,
                        action,
                        MAX_DEPTH
                    ),
                }

                if action_id ~= nil
                    and not unique_sets[source_scope][action_id] then
                    unique_sets[source_scope][action_id] = true
                    unique_ids_by_scope[source_scope][
                        #unique_ids_by_scope[source_scope] + 1
                    ] = action_id
                end
            end
        end
    end

    collect_resource(
        CHARACTER_RESOURCE_INDEX,
        "character"
    )
    collect_resource(
        COMMON_RESOURCE_INDEX,
        "common"
    )

    table.sort(records, function(a, b)
        if tostring(a.source_scope) ~= tostring(b.source_scope) then
            return tostring(a.source_scope) < tostring(b.source_scope)
        end
        if (a.style_index or -1) ~= (b.style_index or -1) then
            return (a.style_index or -1) < (b.style_index or -1)
        end
        if (a.native_action_id or -1)
            ~= (b.native_action_id or -1) then
            return (a.native_action_id or -1)
                < (b.native_action_id or -1)
        end
        return tostring(a.dictionary_key)
            < tostring(b.dictionary_key)
    end)

    table.sort(unique_ids_by_scope.character)
    table.sort(unique_ids_by_scope.common)
    table.sort(ctx.truncation_reasons)

    return {
        schema = AC_SCHEMA,
        dictionary_encoding = "int-keyed-entries.v2",
        inherited_fields = "game-namespaces.v2",
        fighter_id = runtime.fighter_id,
        character = identity.character_name,
        character_slug = identity.character_slug,
        character_name_source =
            identity.character_name_source,
        character_name_confidence =
            identity.character_name_confidence,
        character_identity_candidates =
            identity.candidates,
        control_mode_label = mode_label,
        control_mode_runtime_verified = false,
        control_mode_source = "manual-game-switch-plus-caller-label",
        capture_profile =
            "full-character-and-common-action-object-graph",
        source_resources = {
            {
                source_scope = "character",
                resource_index = CHARACTER_RESOURCE_INDEX,
            },
            {
                source_scope = "common",
                resource_index = COMMON_RESOURCE_INDEX,
            },
        },
        record_count = #records,
        unique_action_ids_by_scope = unique_ids_by_scope,
        records = records,
        type_catalog = type_catalog_to_list(ctx),
        base_type_catalog = ctx.base_type_catalog,
        objects = ctx.objects,
        graph_stats = {
            object_count = #ctx.objects,
            type_count = #type_catalog_to_list(ctx),
        },
        limits = {
            max_depth = MAX_DEPTH,
            max_objects = MAX_OBJECTS,
            max_collection_items = MAX_COLLECTION_ITEMS,
        },
        hard_gate_passed =
            (not ctx.truncated and #collection_errors == 0),
        truncated = ctx.truncated,
        truncation_reasons = ctx.truncation_reasons,
        collection_errors = collection_errors,
        notes = {
            "No Action ID selection or sampling is applied.",
            "Character and Common records remain separate even when Action IDs overlap.",
            "All non-static reflected fields are stored in the normalized object graph.",
            "Static reflected fields are stored once per type in type_catalog.",
            "No AC semantic classification is performed by this exporter.",
            "The mode label is manually supplied and is not runtime-verified.",
        },
    }
end

local function collect_bcm(runtime, identity, mode_label)
    local ctx = new_graph_context()

    local bcm_resources, bcm_resources_field = read_first(
        runtime.command,
        {
            "mpBCMResource",
            "mBCMResource",
            "BCMResource",
        }
    )
    if bcm_resources == nil then
        error("BCM resource collection unavailable")
    end

    local bcm_resource =
        collection_item(bcm_resources, PLAYER_INDEX)
        or safe_index(bcm_resources, PLAYER_INDEX)
    if bcm_resource == nil then
        error("P1 BCM resource unavailable")
    end

    local command_root, command_root_field = read_first(
        bcm_resource,
        {
            "pCommand",
            "Command",
            "command",
            "commands",
            "Commands",
        }
    )
    if command_root == nil then
        error("P1 BCM command root unavailable")
    end

    local user_engines = safe_call(runtime.command, {
        "get_mUserEngine()",
        "get_mUserEngine",
    })
    if user_engines == nil then
        user_engines = safe_index(
            runtime.command,
            "mUserEngine"
        )
    end
    if user_engines == nil then
        error("P1 command user engine collection unavailable")
    end

    local user_engine =
        collection_item(user_engines, PLAYER_INDEX)
        or safe_index(user_engines, PLAYER_INDEX)
    if user_engine == nil then
        error("P1 command user engine unavailable")
    end

    local trigger_collection = safe_call(user_engine, {
        "GetTrigger()",
        "GetTrigger",
        "get_Trigger()",
        "get_Trigger",
    })
    if trigger_collection == nil then
        trigger_collection =
            safe_index(user_engine, "Trigger")
    end
    if trigger_collection == nil then
        error("P1 BCM trigger collection unavailable")
    end

    local trigger_count = collection_count(trigger_collection)
    if trigger_count == nil then
        error("could not determine trigger collection count")
    end

    local triggers = {}
    local unique_action_ids = {}
    local unique_action_id_set = {}

    for trigger_index = 0, trigger_count - 1 do
        local trigger =
            collection_item(trigger_collection, trigger_index)
        if trigger ~= nil then
            local action_id, action_id_field = read_int(
                trigger,
                {
                    "action_id",
                    "ActionID",
                    "actionID",
                    "ActionId",
                    "action",
                    "Action",
                }
            )

            triggers[#triggers + 1] = {
                trigger_index = trigger_index,
                native_action_id = action_id,
                action_id_source_field = action_id_field,
                trigger_ref = encode_value(
                    ctx,
                    trigger,
                    MAX_DEPTH
                ),
            }

            if action_id ~= nil
                and not unique_action_id_set[action_id] then
                unique_action_id_set[action_id] = true
                unique_action_ids[#unique_action_ids + 1] =
                    action_id
            end
        end
    end

    table.sort(unique_action_ids)
    table.sort(ctx.truncation_reasons)

    local command_root_ref = encode_value(
        ctx,
        command_root,
        MAX_DEPTH
    )

    local bcm_resource_ref = encode_value(
        ctx,
        bcm_resource,
        MAX_DEPTH
    )

    return {
        schema = BCM_SCHEMA,
        dictionary_encoding = "int-keyed-entries.v2",
        inherited_fields = "game-namespaces.v2",
        fighter_id = runtime.fighter_id,
        character = identity.character_name,
        character_slug = identity.character_slug,
        character_name_source =
            identity.character_name_source,
        character_name_confidence =
            identity.character_name_confidence,
        character_identity_candidates =
            identity.candidates,
        player_index = PLAYER_INDEX,
        control_mode_label = mode_label,
        control_mode_runtime_verified = false,
        control_mode_source = "manual-game-switch-plus-caller-label",
        capture_profile =
            "full-bcm-resource-command-and-trigger-object-graph",
        source_contract = {
            bcm_resources_field = bcm_resources_field,
            command_root_field = command_root_field,
            bcm_resource_path =
                "gBattle.Command/mpBCMResource[0]",
            trigger_path =
                "gBattle.Command/get_mUserEngine()[0]/GetTrigger()",
        },
        trigger_count = #triggers,
        unique_action_id_count = #unique_action_ids,
        unique_action_ids = unique_action_ids,
        triggers = triggers,
        bcm_resource_ref = bcm_resource_ref,
        command_root_ref = command_root_ref,
        type_catalog = type_catalog_to_list(ctx),
        base_type_catalog = ctx.base_type_catalog,
        objects = ctx.objects,
        graph_stats = {
            object_count = #ctx.objects,
            type_count = #type_catalog_to_list(ctx),
        },
        limits = {
            max_depth = MAX_DEPTH,
            max_objects = MAX_OBJECTS,
            max_collection_items = MAX_COLLECTION_ITEMS,
        },
        hard_gate_passed = not ctx.truncated,
        truncated = ctx.truncated,
        truncation_reasons = ctx.truncation_reasons,
        notes = {
            "No command decoding or button-token conversion is performed.",
            "All trigger profiles and nested BCM objects are preserved as raw reflected fields.",
            "The command root and BCM resource are stored as normalized object-graph references.",
            "The exporter does not choose norm, sprt, easy, supr, or any other profile.",
            "The mode label is manually supplied and is not runtime-verified.",
        },
    }
end

local function write_json(path, payload)
    if json == nil or json.dump_file == nil then
        error("json.dump_file unavailable")
    end

    local ok, write_error =
        pcall(json.dump_file, path, payload)
    if not ok then
        error(
            "failed to write " .. tostring(path)
            .. ": " .. tostring(write_error)
        )
    end
end

local function capture(mode_label)
    if mode_label ~= "classic" and mode_label ~= "modern" then
        return false,
            "mode_label must be exactly 'classic' or 'modern'"
    end

    if status.capture_in_progress then
        return false, "capture already in progress"
    end

    status.capture_in_progress = true
    status.ready = false
    status.last_error = nil
    status.last_mode = mode_label

    local ac_path = nil
    local bcm_path = nil

    local ok, result_or_error = pcall(function()
        local runtime, runtime_error = get_runtime()
        if runtime == nil then
            error(runtime_error)
        end

        local identity =
            detect_character_identity(runtime)

        status.fighter_id = runtime.fighter_id
        status.character_name =
            identity.character_name
        status.character_slug =
            identity.character_slug
        status.character_name_source =
            identity.character_name_source

        ac_path =
            OUTPUT_DIR
            .. identity.file_prefix
            .. "-action-catalog-full-"
            .. mode_label
            .. ".json"
        bcm_path =
            OUTPUT_DIR
            .. identity.file_prefix
            .. "-bcm-full-"
            .. mode_label
            .. ".json"

        status.ac_output_path = ac_path
        status.bcm_output_path = bcm_path

        log_info(
            "detected fighter_id="
            .. tostring(runtime.fighter_id)
            .. ", character="
            .. tostring(identity.character_name)
            .. ", source="
            .. tostring(identity.character_name_source)
        )

        log_info(
            "capturing full AC for mode=" .. mode_label
        )
        local ac_payload =
            collect_action_catalog(
                runtime,
                identity,
                mode_label
            )
        write_json(ac_path, ac_payload)

        log_info(
            "capturing full BCM for mode=" .. mode_label
        )
        local bcm_payload =
            collect_bcm(
                runtime,
                identity,
                mode_label
            )
        write_json(bcm_path, bcm_payload)

        return {
            ac = ac_payload,
            bcm = bcm_payload,
        }
    end)

    status.capture_in_progress = false

    if not ok then
        status.last_error = tostring(result_or_error)
        log_error(status.last_error)
        return false, status.last_error
    end

    local result = result_or_error
    status.capture_count = status.capture_count + 1
    status.ac_record_count = result.ac.record_count
    status.bcm_trigger_count = result.bcm.trigger_count
    status.ac_hard_gate_passed =
        result.ac.hard_gate_passed
    status.bcm_hard_gate_passed =
        result.bcm.hard_gate_passed
    status.ready =
        result.ac.hard_gate_passed
        and result.bcm.hard_gate_passed

    log_info(
        "wrote AC: " .. ac_path
        .. " | records=" .. tostring(result.ac.record_count)
        .. " | objects="
        .. tostring(result.ac.graph_stats.object_count)
        .. " | hard_gate="
        .. tostring(result.ac.hard_gate_passed)
    )

    log_info(
        "wrote BCM: " .. bcm_path
        .. " | triggers=" .. tostring(result.bcm.trigger_count)
        .. " | unique_action_ids="
        .. tostring(result.bcm.unique_action_id_count)
        .. " | objects="
        .. tostring(result.bcm.graph_stats.object_count)
        .. " | hard_gate="
        .. tostring(result.bcm.hard_gate_passed)
    )

    return true, {
        mode = mode_label,
        fighter_id = status.fighter_id,
        character_name = status.character_name,
        character_slug = status.character_slug,
        character_name_source =
            status.character_name_source,
        ac_output_path = ac_path,
        bcm_output_path = bcm_path,
        ac_record_count = result.ac.record_count,
        bcm_trigger_count = result.bcm.trigger_count,
        ac_hard_gate_passed =
            result.ac.hard_gate_passed,
        bcm_hard_gate_passed =
            result.bcm.hard_gate_passed,
    }
end

local api = {
    capture = capture,
    capture_classic = function()
        return capture("classic")
    end,
    capture_modern = function()
        return capture("modern")
    end,
    get_status = function()
        return status
    end,
}

-- Offline tests load the file with this flag set and drive the encoder
-- directly; in the game the script captures immediately.
api.__test = {
    encode_value = encode_value,
    new_graph_context = new_graph_context,
}

_G.SF6CC_ACBCMExporter = api

if _G.SF6CC_ACBCM_EXPORTER_NO_AUTORUN ~= true then
    log_info(
        "loaded; automatic capture mode=" .. tostring(AUTO_CAPTURE_MODE)
    )

    local auto_ok, auto_result = capture(AUTO_CAPTURE_MODE)
    if not auto_ok then
        log_error(
            "automatic capture failed: " .. tostring(auto_result)
        )
    else
        log_info(
            "automatic capture completed for mode="
            .. tostring(AUTO_CAPTURE_MODE)
        )
    end
end
