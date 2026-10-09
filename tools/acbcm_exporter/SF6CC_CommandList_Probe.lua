-- SF6CC_CommandList_Probe.lua
-- Read-only discovery of the data behind the in-game command list
-- (Training > Command List: special moves, super arts, unique moves, throws,
-- common, assist combos; child rows are follow-ups). That list is the game's
-- own move names, categories and follow-up hierarchy; once its data source is
-- known it can replace the official-site data the generator still reads.
--
-- Run with the command list OPEN (REFramework > ScriptRunner > Run script).
-- Writes reframework/data/SF6CC_ACBCM/commandlist-probe.json:
--   types      fields / methods / parents of app.UICommandListWindow,
--              app.UIPartsCommandListSkillPanel and every type whose name
--              mentions the command list (when the type database is exposed)
--   instances  bounded object-graph dumps of the live window components
-- The probe registers no hooks and writes nothing back to the game.

local Probe = {
    OUTPUT = "SF6CC_ACBCM/commandlist-probe.json",
    ROOT_TYPES = { "app.UICommandListWindow", "app.UIPartsCommandListSkillPanel" },
    NAME_PATTERNS = { "commandlist", "skilllist", "movelist" },
    MAX_DEPTH = 6,
    MAX_OBJECTS = 30000,
    MAX_ITEMS = 2000,
}

local function try(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function full_name(definition)
    return definition and (try(function() return definition:get_full_name() end)
        or try(function() return definition:get_name() end)) or nil
end

local function type_of(value)
    return try(function() return value:get_type_definition() end)
end

local function is_scalar(value)
    local kind = type(value)
    return kind == "number" or kind == "boolean" or kind == "string"
end

-- Fields, methods and parents of one type definition.
function Probe.describe_type(definition)
    local result = { name = full_name(definition), parents = {}, fields = {}, methods = {} }
    local parent = try(function() return definition:get_parent_type() end)
    while parent ~= nil and #result.parents < 16 do
        result.parents[#result.parents + 1] = full_name(parent)
        parent = try(function() return parent:get_parent_type() end)
    end
    for _, field in ipairs(try(function() return definition:get_fields() end) or {}) do
        result.fields[#result.fields + 1] = {
            name = try(function() return field:get_name() end),
            type = full_name(try(function() return field:get_type() end)),
            static = try(function() return field:is_static() end) == true,
        }
    end
    for _, method in ipairs(try(function() return definition:get_methods() end) or {}) do
        result.methods[#result.methods + 1] = try(function() return method:get_name() end)
    end
    table.sort(result.methods, function(a, b) return tostring(a) < tostring(b) end)
    return result
end

local function collection_items(value, definition)
    local name = full_name(definition) or ""
    local items = nil
    if name:sub(-2) == "[]" then
        items = try(function() return value:get_elements() end)
    elseif name:find("System.Collections.Generic.List", 1, true) then
        local count = try(function() return value:call("get_Count") end)
        if type(count) == "number" then
            items = {}
            for index = 0, math.min(count, Probe.MAX_ITEMS) - 1 do
                items[#items + 1] = try(function() return value:call("get_Item", index) end) or false
            end
        end
    end
    return items
end

-- Bounded generic object graph: scalars inline, objects by id.
function Probe.new_graph()
    return { next_id = 1, ids = {}, objects = {}, truncated = false }
end

function Probe.encode(graph, value, depth)
    if value == nil or value == false then return nil end
    if is_scalar(value) then return value end
    local definition = type_of(value)
    if definition == nil then return tostring(value) end
    local name = full_name(definition) or "?"
    if name == "System.String" then
        return try(function() return value:call("ToString()") end) or tostring(value)
    end
    local identity = tostring(value)
    if graph.ids[identity] then return { ref = graph.ids[identity] } end
    if depth <= 0 or graph.next_id > Probe.MAX_OBJECTS then
        graph.truncated = true
        return { type = name, truncated = true }
    end
    local id = graph.next_id
    graph.next_id = id + 1
    graph.ids[identity] = id
    local node = { id = id, type = name, fields = {} }
    graph.objects[#graph.objects + 1] = node
    local items = collection_items(value, definition)
    if items then
        node.items = {}
        for index, item in ipairs(items) do
            if index > Probe.MAX_ITEMS then graph.truncated = true break end
            node.items[index] = Probe.encode(graph, item, depth - 1) or "nil"
        end
        return { ref = id }
    end
    local current = definition
    local seen = {}
    while current ~= nil do
        for _, field in ipairs(try(function() return current:get_fields() end) or {}) do
            local field_name = try(function() return field:get_name() end)
            local static = try(function() return field:is_static() end) == true
            if field_name and not static and not seen[field_name] then
                seen[field_name] = true
                local field_value = try(function() return field:get_data(value) end)
                node.fields[field_name] = Probe.encode(graph, field_value, depth - 1)
            end
        end
        current = try(function() return current:get_parent_type() end)
        local parent_name = full_name(current) or ""
        if parent_name:sub(1, 4) ~= "app." then break end
    end
    return { ref = id }
end

-- Every type whose name mentions the command list, when REFramework exposes
-- the type database.
function Probe.matching_types()
    local tdb = try(function() return sdk.get_tdb() end)
    local count = tdb and try(function() return tdb:get_num_types() end)
    if type(count) ~= "number" then return nil end
    local result = {}
    for index = 0, count - 1 do
        local definition = try(function() return tdb:get_type(index) end)
        local name = definition and full_name(definition)
        if name then
            local lowered = name:lower()
            for _, pattern in ipairs(Probe.NAME_PATTERNS) do
                if lowered:find(pattern, 1, true) then
                    result[#result + 1] = Probe.describe_type(definition)
                    break
                end
            end
        end
    end
    return result
end

function Probe.scene_components(type_name)
    local manager = try(function() return sdk.get_native_singleton("via.SceneManager") end)
    local manager_type = try(function() return sdk.find_type_definition("via.SceneManager") end)
    local scene = manager and manager_type
        and try(function() return sdk.call_native_func(manager, manager_type, "get_CurrentScene") end)
    local system_type = try(function() return sdk.typeof(type_name) end)
    local found = scene and system_type
        and try(function() return scene:call("findComponents(System.Type)", system_type) end)
    return found and try(function() return found:get_elements() end) or {}
end

function Probe.run()
    local report = {
        schema = "sf6cc.commandlist-probe.v1",
        types = {},
        matching_types = Probe.matching_types(),
        instances = {},
    }
    for _, type_name in ipairs(Probe.ROOT_TYPES) do
        local definition = try(function() return sdk.find_type_definition(type_name) end)
        report.types[type_name] = definition and Probe.describe_type(definition) or false
        local graph = Probe.new_graph()
        local roots = {}
        for _, component in ipairs(Probe.scene_components(type_name)) do
            roots[#roots + 1] = Probe.encode(graph, component, Probe.MAX_DEPTH)
        end
        report.instances[type_name] = {
            count = #roots, roots = roots, objects = graph.objects, truncated = graph.truncated,
        }
    end
    local ok, err = pcall(json.dump_file, Probe.OUTPUT, report)
    local window = report.instances[Probe.ROOT_TYPES[1]]
    local message = ok and ("[SF6CC] commandlist probe written: " .. Probe.OUTPUT
        .. " (windows=" .. tostring(window.count) .. ", objects=" .. tostring(#window.objects) .. ")")
        or ("[SF6CC] commandlist probe failed: " .. tostring(err))
    pcall(function() log.info(message) end)
    pcall(print, message)
    return ok, report
end

_G.SF6CC_CommandListProbe = Probe
if _G.SF6CC_COMMANDLIST_PROBE_NO_AUTORUN ~= true then
    Probe.run()
end
return Probe
