-- Exercise the real panel with duplicate visible titles, without game or disk IO.
package.path = "autorun/?.lua;" .. package.path
local Module = dofile("autorun/SF6CCTrainingLibrary/Library.lua")
local entries = { { path = "configs/a.json" }, { path = "configs/b.json" } }
local imports, scans = 0, 0
local records = {
    get_context = function() return { fighter_name = "Mai" } end,
    list_configs = function() scans = scans + 1; return entries end,
    read_config_metadata = function() return { title = "Mai 训练配置", fighter_name = "Mai" } end,
    import_from_file = function() imports = imports + 1 end,
}
local library = Module.new(records, function() return { allowed = false } end)
local panel, labels, choose, frame, draw
local noop = function() end
local modules = {
    ["SF6CCTrainingLibrary/Records"] = records,
    ["SF6CCTrainingLibrary/Library"] = { shared = function() return library end },
}
local env = setmetatable({
    require = function(name) return assert(modules[name], name) end,
    -- REFramework exposes text(), not the C++ ImGui TextWrapped name.
    imgui = { text = noop, text_colored = noop, same_line = noop,
        button = function() return false end, small_button = function() return false end,
        tree_node = function() return false end,
        combo = function(id, selected, items)
            assert(id == "##SF6CCTrainingConfigList")
            labels = items
            return choose ~= nil, choose or selected
        end },
    re = { on_pre_application_entry = noop, on_script_reset = noop, on_frame = function(fn) frame=fn end },
}, { __index = _G })
panel=assert(loadfile("autorun/SF6CCTrainingLibrary/Panel.lua", "t", env))()
local function id(label) return label:match(".*###(.*)$") or label end
panel()
assert(labels[1] ~= labels[2], "Duplicate visible configuration titles must not share ImGui IDs")
assert(id(labels[1]) ~= id(labels[2]), "ImGui effective IDs must be distinct")
local ids = { [entries[1].path] = id(labels[1]), [entries[2].path] = id(labels[2]) }
assert(labels[1]:match("^(.-)##") == "不知火舞 Mai [Mai 训练配置]")
assert(labels[2]:match("^(.-)##") == "不知火舞 Mai [Mai 训练配置]")
assert(library.labels[1] == "Mai 训练配置" and library.labels[2] == "Mai 训练配置",
    "Native labels must not contain ImGui suffixes")
local cached = labels
choose = 2; panel(); choose = nil
assert(library.selection().path == "configs/b.json" and imports == 0)
for _ = 1, 100 do panel(); assert(labels == cached) end
assert(scans == 1, "Hover/redraw must not scan files")
entries = { entries[2], entries[1] }
assert(library.refresh()); panel()
assert(library.selected == 1 and id(labels[1]) == ids[entries[1].path])
assert(id(labels[2]) == ids[entries[2].path])
entries = {}; assert(library.refresh()); panel()
assert(#labels == 1 and imports == 0)
local queued, before_scans = 0, scans
library.request = function(kind) assert(kind == "refresh"); queued = queued + 1; return true end
env.imgui.small_button = function() return true end
panel()
assert(queued == 1 and scans == before_scans, "ImGui refresh must enqueue, not mutate the native-visible catalog during drawing")
print("PASS duplicate titles: distinct stable IDs, same visible text, native labels unchanged")
print("PASS selection without import, cached redraw, reorder and empty list")
print("PASS ImGui refresh defers catalog changes to the shared closed-menu queue")

assert(frame==nil and draw==nil,"legacy fixed-position annotations must not return when capacity falls back to eight")
print("PASS native recording/reversal names never fall back to fixed-position ImGui annotations")
