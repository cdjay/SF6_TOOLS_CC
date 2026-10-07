-- Standalone REFramework management panel; shares only this plugin's controller.
-- Independent ImGui panel for SF6 native recording slots and reversal settings.

local imgui = imgui
local re = re

local DynamicRecords = require("SF6CCTrainingLibrary/Records")
local Library = require("SF6CCTrainingLibrary/Library").shared()

local options = Library.options

local status_msg = "Ready."
local status_ok = true
local last_slots = nil
local last_snapshot = nil
local last_fighter_id = nil
local last_result_revision = Library.result_revision
local config_labels_revision = -1
local config_imgui_labels = {}
local function set_status(ok, msg)
    status_ok = ok == true
    status_msg = tostring(msg or "")
    Library.status_ok, Library.status = status_ok, status_msg
end

local function selected_config()
    return Library.selection()
end

local function refresh_config_list(select_path)
    return Library.refresh(select_path)
end

local function refresh_slots(silent)
    local ok, slots_or_err, err_or_nil, snapshot_or_nil = pcall(function()
        local slots, err, snapshot = DynamicRecords.get_slot_summaries()
        return slots, err, snapshot
    end)

    if not ok then
        set_status(false, "Refresh failed: " .. tostring(slots_or_err))
        return false
    end

    local slots = slots_or_err
    local err = err_or_nil
    local snapshot = snapshot_or_nil
    if not slots then
        last_slots = nil
        last_snapshot = nil
        set_status(false, "Refresh failed: " .. tostring(err))
        return false
    end

    last_slots = slots
    last_snapshot = snapshot
    if not silent then set_status(true, "Refreshed") end
    return true
end

local function import_selected_config()
    Library.request("import")
end

local function status_color()
    if status_ok then return 0xFF00FF00 end
    return 0xFF0000FF
end

local function draw_paths()
    local paths = DynamicRecords.paths_for_display()
    imgui.text("Configs: " .. paths.configs)
    imgui.text("Backups: " .. paths.backups)
    imgui.text("Editor: " .. tostring(paths.editor or ""))
    imgui.text("Legacy: " .. paths.legacy)
    imgui.text("Config glob matches: " .. tostring(paths.config_glob_count or 0))
    imgui.text("Config glob: " .. tostring(paths.config_glob or ""))
end

local function draw_config_selector()
    if not Library.loaded then refresh_config_list(nil, true) end
    if config_labels_revision ~= Library.revision then
        config_imgui_labels = {}
        for index, entry in ipairs(Library.entries) do
            -- Keep native labels plain; encode paths so file names cannot inject ImGui ID syntax.
            local key = entry.path:gsub(".", function(char) return string.format("%02x", char:byte()) end)
            config_imgui_labels[index] = Library.selection_label(index) .. "###SF6CCTrainingConfigEntry_" .. key
        end
        if #config_imgui_labels == 0 then config_imgui_labels[1] = "（暂无配置）" end
        config_labels_revision = Library.revision
    end

    imgui.text("训练配置")
    local changed, new_index = imgui.combo(
        "##SF6CCTrainingConfigList", Library.selected, config_imgui_labels)
    if changed then Library.select(new_index) end
    imgui.same_line()
    if imgui.small_button("刷新列表") then Library.request("refresh") end

    local entry = selected_config()
    if entry then
        local detail = Library.selection_details()
        imgui.text_colored("文件：" .. detail.file, 0xFFAAAAAA)
        imgui.text("角色：" .. detail.character)
        imgui.text("保存时间：" .. detail.saved)
        imgui.text(detail.slots)
        imgui.text("备注：" .. detail.notes)
    end
end

local function draw_primary_actions()
    if imgui.button("保存当前配置") then Library.request("save") end
    imgui.same_line()
    if imgui.button("导出配置") then
        Library.request("export")
    end
    imgui.same_line()

    if imgui.button("导入配置") then
        import_selected_config()
    end
    imgui.same_line()

    if imgui.button("清空") then
        Library.request("clear")
    end
end

local function draw_debug_actions()
    if imgui.button("刷新") then
        refresh_slots(false)
    end
    imgui.same_line()

    if imgui.button("备份当前完整配置") then
        Library.request("backup")
    end
    imgui.same_line()

    if imgui.button("恢复最近备份") then
        Library.request("restore")
    end
end

local function draw_options()
    local changed

    changed, options.only_import_valid = imgui.checkbox("只导入有效栏位", options.only_import_valid)
    imgui.same_line()
    changed, options.clear_empty_slots = imgui.checkbox("清空空栏位", options.clear_empty_slots)
    imgui.same_line()
    changed, options.reject_fighter_mismatch = imgui.checkbox("角色 ID 不匹配时拒绝", options.reject_fighter_mismatch)
    imgui.same_line()
    changed, options.force_apply_after_import = imgui.checkbox("导入后 ForceApply", options.force_apply_after_import)
end

local function draw_slots_table(slots)
    if not slots then
        imgui.text_colored("没有可显示的栏位数据。", 0xFF888888)
        return
    end

    if imgui.begin_table("SF6CCDynamicRecordsSlots", 6, 1 << 0) then
        imgui.table_setup_column("栏位", 0, 30)
        imgui.table_setup_column("有效", 0, 50)
        imgui.table_setup_column("启用", 0, 50)
        imgui.table_setup_column("帧数", 0, 60)
        imgui.table_setup_column("权重", 0, 60)
        imgui.table_setup_column("输入帧", 0, 70)
        imgui.table_headers_row()

        for _, slot in ipairs(slots) do
            imgui.table_next_row()

            imgui.table_next_column()
            imgui.text(tostring(slot.slot or "-"))

            imgui.table_next_column()
            imgui.text_colored(slot.is_valid and "yes" or "no", slot.is_valid and 0xFF00FF00 or 0xFF888888)

            imgui.table_next_column()
            imgui.text_colored(slot.is_active and "on" or "off", slot.is_active and 0xFF00FF00 or 0xFF888888)

            imgui.table_next_column()
            imgui.text(tostring(slot.frame or 0))

            imgui.table_next_column()
            imgui.text(tostring(slot.weight or 0))

            imgui.table_next_column()
            imgui.text(tostring(slot.input_num or 0))
        end

        imgui.end_table()
    end
end

local function draw_reversal_table(reversals)
    if type(reversals) ~= "table" then
        imgui.text_colored("没有可显示的反击设置。", 0xFF888888)
        return
    end

    local groups = {
        { key = "down", label = "倒地反击" },
        { key = "guard", label = "格挡反击" },
        { key = "damage", label = "受击反击" },
    }

    for _, group in ipairs(groups) do
        if imgui.tree_node(group.label .. "##SF6CCReversalDebug" .. group.key) then
            local entries = reversals[group.key]
            if type(entries) == "table" then
                for _, entry in ipairs(entries) do
                    imgui.text("栏位 " .. tostring(entry.slot or "-")
                        .. " | active=" .. tostring(entry.active)
                        .. " | type=" .. tostring(entry.type)
                        .. " | skill=" .. tostring(entry.skill_index)
                        .. " | delay=" .. tostring(entry.delay_frame)
                        .. " | count=" .. tostring(entry.count)
                        .. " | meaty=" .. tostring(entry.meaty_frame))
                end
            else
                imgui.text_colored("组数据不可用。", 0xFF888888)
            end
            imgui.tree_pop()
        end
    end
end

local function draw_debug_panel()
    local ctx = DynamicRecords.get_context()
    local fighter_id = ctx.fighter_id
    local fighter_name = ctx.fighter_name or ""
    local source_player = ctx.source_player or "P2"

    if fighter_id ~= last_fighter_id then
        last_fighter_id = fighter_id
        last_slots = nil
        last_snapshot = nil
    end

    imgui.text("当前角色: " .. tostring(fighter_name)
        .. " / fighter_id=" .. tostring(fighter_id or "?")
        .. " / source=" .. tostring(source_player))

    if ctx.error and fighter_id == nil then
        imgui.text_colored("Context: " .. tostring(ctx.error), 0xFF0000FF)
    end

    draw_debug_actions()
    draw_options()
    imgui.separator()
    draw_paths()
    imgui.separator()

    if not last_slots then refresh_slots(true) end
    draw_slots_table(last_slots)

    imgui.separator()
    draw_reversal_table(last_snapshot and last_snapshot.reversals or nil)

    imgui.separator()
    imgui.text("状态: ")
    imgui.same_line()
    imgui.text_colored(status_msg, status_color())
end

local function draw_panel()
    if last_result_revision ~= Library.result_revision then
        last_result_revision = Library.result_revision
        last_slots, last_snapshot = nil, nil
    end
    status_msg, status_ok = Library.status, Library.status_ok
    local ctx = DynamicRecords.get_context()
    local fighter_name = tostring(ctx.fighter_name or "未知")
    imgui.text("当前角色 [" .. fighter_name .. "]")

    draw_config_selector()
    local compatible, compatibility_text, compatibility_code = Library.selection_compatibility(ctx)
    imgui.text_colored(compatibility_text,
        compatible and compatibility_code == "match" and 0xFF00FF00 or 0xFF8888FF)
    draw_primary_actions()
    imgui.text_colored(Library.status, Library.status_ok and 0xFF00FF00 or 0xFF0000FF)

    if imgui.tree_node("高级 / 调试") then
        draw_debug_panel()
        imgui.tree_pop()
    end
    imgui.text_colored("提醒：具体配置请在网站上配置和保存", 0xFF888888)
end

return draw_panel
