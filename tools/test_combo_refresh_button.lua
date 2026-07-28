local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value:gsub("\r\n", "\n")
end

local source = read_all("autorun/func/ComboTrials_UI.lua")
local single_line = assert(source:match(
    "(local function draw_single_line_content%(%).-)\nlocal function draw_combo_trials_content"
), "single-line combo toolbar is missing")

local refresh_pos = assert(single_line:find(
    'styled_sf6_button("刷新列表"', 1, true
), "combo toolbar must expose the refresh-list button")
local record_pos = assert(single_line:find(
    'styled_sf6_button("录制连段"', 1, true
), "combo toolbar record button is missing")

assert(refresh_pos < record_pos,
    "refresh-list button must stay beside the list and before record")
assert(single_line:find(
    'file_system.request_combo_list_refresh("manual list refresh", true)', 1, true
), "manual refresh must use the safe queued refresh path and reload the selected JSON")
assert(single_line:find("local visible_button_count = 3", 1, true),
    "idle toolbar layout must reserve width for the refresh-list button")

print("combo refresh button tests passed")
