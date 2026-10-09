-- Offline check of the command list probe with a fake REFramework object
-- model: type description, bounded graph encoding (lists, strings, app.*
-- parents only) and the report written by run().

local function definition(name, fields, parent, methods)
    local def = {}
    function def:get_full_name() return name end
    function def:get_name() return name end
    function def:get_fields() return fields or {} end
    function def:get_parent_type() return parent end
    function def:get_methods()
        local list = {}
        for _, method in ipairs(methods or {}) do
            list[#list + 1] = { get_name = function() return method end }
        end
        return list
    end
    return def
end

local function field(name, type_name, static)
    local type_def = definition(type_name)
    return {
        get_name = function() return name end,
        get_type = function() return type_def end,
        is_static = function() return static == true end,
        get_data = function(_, instance) return instance.__data[name] end,
    }
end

local function managed(def, data)
    return { __data = data or {}, get_type_definition = function() return def end }
end

local behavior = definition("via.Behavior", { field("GameObject", "via.GameObject") })
local window_base = definition("app.UIWindowBase", { field("_IsOpen", "System.Boolean") }, behavior)
local skill_def = definition("app.CommandListSkillData", {
    field("Name", "System.String"), field("ActionId", "System.Int32"), field("Children", "System.Int32[]"),
    field("Shared", "System.Int32", true),
})
local list_def = definition("System.Collections.Generic.List`1<app.CommandListSkillData>")
local window_def = definition("app.UICommandListWindow", {
    field("_Category", "app.UICommandListWindow.eCategoryType"),
    field("_Skills", "System.Collections.Generic.List`1<app.CommandListSkillData>"),
}, window_base, { "updateList", "open" })

local child_array = { get_type_definition = function() return definition("System.Int32[]") end,
    get_elements = function() return { 901, 902 } end }
local hadoken = managed(skill_def, { Name = "Hadoken", ActionId = 900, Children = child_array })
local list = managed(list_def)
function list:call(name, index)
    if name == "get_Count" then return 2 end
    if name == "get_Item" then return index == 0 and hadoken or hadoken end
end
local window = managed(window_def, {
    _Category = 0, _Skills = list, _IsOpen = true,
    GameObject = managed(definition("via.GameObject"), {}),
})

local written = nil
local previous = { sdk = sdk, json = json, log = log }
sdk = {
    find_type_definition = function(name)
        if name == "app.UICommandListWindow" then return window_def end
        if name == "via.SceneManager" then return definition("via.SceneManager") end
        return nil
    end,
    typeof = function(name) return name end,
    get_native_singleton = function() return {} end,
    call_native_func = function() return {
        call = function(_, method, system_type)
            assert(method == "findComponents(System.Type)")
            local found = system_type == "app.UICommandListWindow" and { window } or {}
            return { get_elements = function() return found end }
        end,
    } end,
}
json = { dump_file = function(path, payload) written = { path = path, payload = payload }; return true end }
log = { info = function() end }
_G.SF6CC_COMMANDLIST_PROBE_NO_AUTORUN = true
local Probe = assert(loadfile("tools/acbcm_exporter/SF6CC_CommandList_Probe.lua"))()

local described = Probe.describe_type(window_def)
assert(described.name == "app.UICommandListWindow")
assert(described.parents[1] == "app.UIWindowBase" and described.parents[2] == "via.Behavior")
assert(described.fields[2].name == "_Skills" and described.methods[1] == "open")

local ok, report = Probe.run()
assert(ok and written.path == "SF6CC_ACBCM/commandlist-probe.json" and written.payload == report)
assert(report.types["app.UICommandListWindow"].name == "app.UICommandListWindow")
assert(report.types["app.UIPartsCommandListSkillPanel"] == false, "unknown types are reported, not fatal")
local instance = report.instances["app.UICommandListWindow"]
assert(instance.count == 1 and not instance.truncated)
local by_id = {}
for _, node in ipairs(instance.objects) do by_id[node.id] = node end
local root = by_id[instance.roots[1].ref]
assert(root.type == "app.UICommandListWindow" and root.fields._Category == 0)
assert(root.fields._IsOpen == true, "app.* parent fields are included")
assert(root.fields.GameObject == nil, "engine parents (via.*) are not walked")
local skills = by_id[root.fields._Skills.ref]
assert(#skills.items == 2 and skills.items[1].ref == skills.items[2].ref, "shared objects are referenced once")
local skill = by_id[skills.items[1].ref]
assert(skill.fields.Name == "Hadoken" and skill.fields.ActionId == 900 and skill.fields.Shared == nil)
assert(by_id[skill.fields.Children.ref].items[2] == 902)

sdk, json, log = previous.sdk, previous.json, previous.log
_G.SF6CC_COMMANDLIST_PROBE_NO_AUTORUN = nil
_G.SF6CC_CommandListProbe = nil
print("command list probe tests passed")
