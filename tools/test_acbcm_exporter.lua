-- Offline check of the AC/BCM exporter's object-graph encoder with a fake
-- REFramework object model. Focus: Int32-keyed dictionaries must keep every
-- key, including keys >= Count, which get_Item(0..Count-1) used to drop.

local function definition(full_name, fields)
    local def = {}
    function def:get_full_name() return full_name end
    function def:get_name() return full_name end
    function def:get_fields() return fields or {} end
    return def
end

local function field(name, type_name)
    local f = {}
    local type_def = definition(type_name)
    function f:get_name() return name end
    function f:get_type() return type_def end
    function f:is_static() return false end
    function f:get_offset() return 0 end
    function f:get_data(instance) return instance.__data[name] end
    return f
end

local function managed(type_name, data, fields, extra)
    local object = { __data = data or {} }
    local def = definition(type_name, fields)
    function object:get_type_definition() return def end
    function object:get_field(name) return self.__data[name] end
    function object:call(name)
        local method = extra and extra[name]
        if method then return method() end
        return nil
    end
    return setmetatable(object, { __index = function(self, key)
        if extra and extra.items and type(key) == "number" then return extra.items[key] end
        if type(key) == "string" and key:sub(1, 1) == "_" and key ~= "__data" then
            return rawget(self, "__data")[key]
        end
        return nil
    end })
end

local group_fields = { field("Notice", "System.Byte") }
local function group(notice)
    return managed("BCM.TRIGGER_GROUP", { Notice = notice }, group_fields)
end

local function entry(key, hash_code, next_index, value)
    return managed("Entry", { key = key, hashCode = hash_code, next = next_index, value = value }, {}, nil)
end
-- Entries are read with safe_index(entry, "key"/"value"/...): plain fields.
local function entry_values(e) return setmetatable(e, { __index = function(self, key)
    return rawget(self, "__data")[key]
end }) end

local entries_items = {
    [0] = entry_values(entry(0, 0, -1, group(1))),
    [1] = entry_values(entry(5, 5, -1, nil)),            -- removed slot, value cleared
    [2] = entry_values(entry(60, 60, -1, group(2))),     -- key >= Count
    [3] = entry_values(entry(7, -1, -1, group(9))),      -- .NET Framework free entry
    [4] = entry_values(entry(8, 8, -4, group(9))),       -- .NET Core free-list entry
}
local entries = managed("System.Collections.Generic.Dictionary`2.Entry[]", {}, {}, {
    ["get_Count()"] = function() return 5 end,
    items = entries_items,
})
local dictionary = managed(
    "System.Collections.Generic.Dictionary`2<System.Int32,BCM.TRIGGER_GROUP>",
    { _entries = entries }, {}, { ["get_Count()"] = function() return 2 end }
)

_G.SF6CC_ACBCM_EXPORTER_NO_AUTORUN = true
local previous = { log = log, sdk = sdk, json = json }
log = { info = function() end, error = function() end }
sdk = {}
json = {}
assert(loadfile("tools/acbcm_exporter/SF6CC_ACBCM_Exporter.lua"))()
local exporter = assert(_G.SF6CC_ACBCMExporter)
local encoder = assert(exporter.__test)

local ctx = encoder.new_graph_context()
local ref = encoder.encode_value(ctx, dictionary, 20)
assert(ref.kind == "ref")
local node = ctx.objects[ref.object_id]
assert(node.kind == "collection" and node.dictionary == true)
assert(node.count == 2, "count stays the dictionary Count")
assert(#node.items == 2, "removed and free-list entries must be skipped")
assert(node.items[1].key == 0 and node.items[1].index == 0)
assert(node.items[2].key == 60 and node.items[2].index == 60, "keys >= Count must be exported")
assert(node.entry_count_mismatch == nil)
local value = ctx.objects[node.items[2].value.object_id]
assert(value.object_type == "BCM.TRIGGER_GROUP")
assert(value.fields[1].name == "Notice" and value.fields[1].value.value == 2)
assert(not ctx.truncated)

-- Keys inherit their frame window from via.fighter.ActionKey; get_fields()
-- only lists a type's own fields, so the encoder must walk game-data bases
-- (and stop at System.* / engine bases).
local function with_parent(def, parent)
    function def:get_parent_type() return parent end
    return def
end
local object_base = with_parent(definition("System.Object", { field("m_hidden", "System.Int32") }), nil)
local engine_base = with_parent(definition("via.clr.ManagedObject", { field("_Engine", "System.Int32") }), object_base)
local action_key = with_parent(definition("via.fighter.ActionKey", {
    field("_StartFrame", "System.Int32"), field("_EndFrame", "System.Int32"), field("Type", "System.Int32"),
}), engine_base)
local branch_def = with_parent(definition("CharacterAsset.BranchKey", {
    field("Type", "System.Int32"), field("Action", "System.Int32"),
}), action_key)
local branch = managed("CharacterAsset.BranchKey", {
    _StartFrame = 24, _EndFrame = 49, Type = 20, Action = 906, _Engine = 7, m_hidden = 1,
}, {})
function branch:get_type_definition() return branch_def end
local key_ctx = encoder.new_graph_context()
local key_ref = encoder.encode_value(key_ctx, branch, 4)
local key_node = key_ctx.objects[key_ref.object_id]
local names = {}
for _, item in ipairs(key_node.fields) do names[item.name] = item.value.value end
assert(names._StartFrame == 24 and names._EndFrame == 49, "inherited frame window must be exported")
assert(names.Type == 20 and names.Action == 906)
assert(names._Engine == nil and names.m_hidden == nil, "engine and System bases are not walked")
local field_count = 0
for _ in pairs(names) do field_count = field_count + 1 end
assert(field_count == 4, "a derived declaration hides the base field of the same name")
local catalog = key_ctx.type_catalog["CharacterAsset.BranchKey"]
assert(catalog and catalog.inherits[1] == "via.fighter.ActionKey" and catalog.inherits[3] == "System.Object")

log, sdk, json = previous.log, previous.sdk, previous.json
_G.SF6CC_ACBCM_EXPORTER_NO_AUTORUN = nil
_G.SF6CC_ACBCMExporter = nil
print("ACBCM exporter dictionary encoding tests passed")
