-- Optional native library editor. No hooks are installed until install() is called.
local Editor = {}
function Editor.install()
    local Module = require("SF6CCTrainingLibrary/Library")
    local Library = Module.shared()
    local Context = require("SF6CCTrainingLibrary/Context")
    local Notes = require("SF6CCTrainingLibrary/TrainingConfigNotes")
    local M = {}
    local pending, active, delegate, stopped, ready, halted, tick
    stopped, ready, halted, tick = false, false, false, 0
    local factory, request_type, visual_type
    local function status(ok, text) Library.status_ok, Library.status = ok, text end
    local function release_prefill(job)
        if job and job.prefill then
            job.prefill:release()
            job.prefill = nil
        end
    end
    local function context()
        local ok, ctx = pcall(Module.runtime_context)
        if ok and ctx and ctx.allowed == true and ctx.busy == false and not ctx.error
            and ctx.session and ctx.data and ctx.fighter_id ~= nil then return ctx end
    end
    local function same(ctx, job)
        return ctx and ctx.session == job.session and ctx.data == job.data and ctx.fighter_id == job.fighter_id
    end
    local function owned(args)
        return not stopped and active and active.widget and sdk.to_managed_object(args[2]) == active.widget
    end
    local function signature(name, method)
        return assert(assert(sdk.find_type_definition(name)):get_method(method))
    end
    local function enum(name, key)
        local value = tonumber(assert(assert(sdk.find_type_definition(name)):get_field(key)):get_data(nil))
        assert(value and value >= 0 and value % 1 == 0)
        return value
    end
    local function set_title(widget)
        local flow = widget:call("get_FlowParam")
        if not flow or flow:get_field("Flow") ~= widget then return false end
        local td, agent, matches = flow:get_type_definition(), nil, 0
        -- Resolve the declared UIAgent reference, never guess private field names.
        for _ = 1, 6 do
            if not td then break end
            for _, field in ipairs(td:get_fields() or {}) do
                if field:get_type():get_full_name() == "app.UIAgent" then
                    matches = matches + 1; agent = field:get_data(flow)
                end
            end
            td = td:get_parent_type()
        end
        if matches ~= 1 or not agent then return false end
        local root = agent:call("get_ControlMain")
        local work, seen, titles, cursor = { root }, {}, {}, 1
        while cursor <= #work and cursor <= 160 do
            local node = work[cursor]; cursor = cursor + 1
            if node and not seen[node] then
                seen[node] = true
                if node:call("get_Name") == "e_text_title"
                    and node:get_type_definition():get_full_name() == "via.gui.Text" then titles[#titles + 1] = node end
                local child, siblings = node:call("get_Child"), {}
                while child and not siblings[child] and #work < 160 do
                    siblings[child] = true; work[#work + 1] = child; child = child:call("get_Next")
                end
            end
        end
        if #titles ~= 1 then return false end
        titles[1]:call("set_Message", active and active.slot and ("槽位"..active.slot.."名称") or "备注")
        return true
    end
    local function hide()
        if not active or active.hide_requested then return end
        active.hide_requested, active.aborted, active.text = true, true, nil
        active.hide_deadline = os.time() + 10
        Library.cancel_note_edit(active)
        pcall(function() active.widget:call("RequestHide(System.Boolean, System.Boolean)", false, false) end)
    end
    ready = pcall(function()
        assert(type(sdk.create_delegate) == "function")
        factory = signature("app.UITextInputDialog", "OpenTextInputDialog(app.UITextInputDialog.ResultFunc, app.UITextInputDialog.RequestType, app.UITextInputDialog.VisualType, System.String, System.UInt32)")
        local decide = signature("app.UITextInputDialog", "Decide()")
        local cancel = signature("app.UITextInputDialog", "Cancel()")
        local result = signature("app.UITextInputDialog", "InvokeResultEvent(System.String)")
        signature("app.UIWidget", "RequestHide(System.Boolean, System.Boolean)")
        signature("app.UIWidget", "get_IsEnd()")
        request_type = enum("app.UITextInputDialog.RequestType", "ReciperMemo")
        visual_type = enum("app.UITextInputDialog.VisualType", "FG")
        local function unchanged(retval) return retval end
        sdk.hook(decide, function(args) if owned(args) then active.phase = "decide" end end, unchanged)
        sdk.hook(cancel, function(args) if owned(args) then active.phase = "cancel"; active.text = nil end end, unchanged)
        sdk.hook(result, function(args)
            local storage = thread.get_hook_storage()
            storage.sf6cc_note_result_owner = nil
            if not owned(args) or active.aborted then return end
            storage.sf6cc_note_result_owner = active
            storage.sf6cc_note_previous_result = active.in_result
            active.in_result = true
            local success = pcall(function()
                active.result_phase = active.phase
                if active.phase ~= "decide" then return end
                local value = sdk.to_managed_object(args[3])
                local text = value and value:call("ToString")
                if Notes.valid_note(text) then active.text = text end
            end)
            if not success then active.text = nil end
        end, function(retval)
            local storage = thread.get_hook_storage()
            local owner = storage.sf6cc_note_result_owner
            if owner then owner.in_result = storage.sf6cc_note_previous_result end
            return retval
        end)
    end)
    function M.request(slot)
        if stopped or not ready or halted or pending or active or Library.has_pending() then
            status(false, "备注编辑暂不可用，或有其他操作尚未完成"); return false
        end
        pending = Library.begin_note_edit(slot)
        if not pending then return false end
        pending.deadline = os.time() + 10
        status(true, slot and "关闭暂停菜单后修改槽位名称；导出配置后保留" or "关闭暂停菜单后编辑所选配置的备注")
        return true
    end
    local function update()
        local ctx = context()
        if pending then
            if not same(ctx, pending) or os.time() > pending.deadline then
                Library.cancel_note_edit(pending); pending = nil; return
            end
            if ctx.menu_closed ~= true or Context.pause_open() ~= false then return end
            local job = pending
            pending = nil
            local initial = Library.prepare_note_edit(job)
            if initial == nil then return end
            active = job
            job.deadline = os.time() + 120
            -- Reuse one delegate; do not retain a new Lua callback/transaction after every edit.
            if not delegate then
                delegate = assert(sdk.create_delegate("app.UITextInputDialog.ResultFunc", 1))
                delegate:add_ref()
                delegate[0] = function()
                    if not stopped and active and active.in_result and not active.aborted then active.callback_seen = true end
                end
            end
            -- Older REFramework marshals numeric Lua strings as double bits.
            -- Pass an explicit System.String and retain it until the dialog ends.
            job.prefill = assert(sdk.create_managed_string(initial), "native prefill allocation failed")
            job.prefill:add_ref()
            job.widget = assert(factory:call(nil, delegate, request_type, visual_type, job.prefill, 0),
                "native input dialog could not open")
            job.widget:add_ref()
            return
        end
        if not active then return end
        local job = active
        if job.widget:call("get_IsEnd") == true then
            if job.aborted or job.phase == "cancel" then Library.cancel_note_edit(job)
            elseif job.result_phase == "decide" and job.callback_seen and job.text ~= nil then
                Library.submit_note_edit(job, job.text)
            else Library.cancel_note_edit(job); status(false, "未收到有效的确认结果，备注未保存") end
            release_prefill(job)
            job.text, active = nil, nil
            return
        end
        if job.hide_requested and os.time() > job.hide_deadline then
            halted = true; status(false, "请按游戏返回键关闭弹窗，备注未保存"); return
        end
        if not same(ctx, job) or os.time() > job.deadline then hide(); return end
        if not job.shown and job.widget:call("get_IsShow") == true then
            job.shown = true
            local title_ok, changed = pcall(set_title, job.widget)
            M.title_changed = title_ok and changed == true
            if not M.title_changed then log.warn("[NativeNoteEditor] Native title was not found; input dialog remains usable.") end
        end
    end
    re.on_pre_application_entry("LateUpdateBehavior", function()
        if stopped or halted or (not pending and not active) then return end
        tick = tick + 1
        if tick % 6 ~= 0 then return end
        local ok, detail = xpcall(update, debug.traceback)
        if not ok then
            ready, halted = false, true
            Library.cancel_note_edit(pending or active)
            pending = nil
            if active and active.widget then hide() else release_prefill(active); active = nil end
            if log and log.error then log.error("[NativeNoteEditor] Stopped: " .. tostring(detail)) end
            status(false, "备注编辑已停止，文件未修改，请正常关闭弹窗")
        end
    end)
    re.on_script_reset(function()
        Library.cancel_note_edit(pending or active)
        pending = nil
        if active and active.widget then hide() end
        stopped = true
    end)
    function M.available() return ready and not stopped and not halted end
    return M
end
return Editor
