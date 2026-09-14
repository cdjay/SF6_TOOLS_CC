-- Standalone native training library. Requires REFramework only.
local State = require("SF6CCTrainingLibrary/State")
if State.started then return end
State.started = true
log.info("[SF6CC TrainingLibrary] Standalone entry loaded; native expansion pending")
local Library = require("SF6CCTrainingLibrary/Library")
local shared = Library.shared()
local Runtime = require("SF6CCTrainingLibrary/NativeRecordingRuntime")
local runtime = Runtime.new({ api=sdk, threads=thread, library=shared,
    context=Library.runtime_context,
    save_idle=function(ctx)
        local manager=sdk.get_managed_singleton("app.storage.SaveManager")
        return manager and manager:call("get_IsBusy")==false
            and ctx.session:get_field("_IsSaveReq")==false
    end,
    log=function(message) log.error("[SF6CC TrainingLibrary] "..message) end })
State.runtime = runtime
local ok, err = pcall(runtime.install_hooks)
if not ok then
    shared.expansion_error = tostring(err)
    log.error("[SF6CC TrainingLibrary] Expansion disabled: "..tostring(err))
end
re.on_application_entry("UpdateBehavior", function()
    local success, detail = xpcall(runtime.tick, debug.traceback)
    if not success then
        pcall(runtime.reset)
        log.error("[SF6CC TrainingLibrary] Stopped: "..tostring(detail))
    end
end)
function State.tick_jobs()
    if not shared.has_pending() then return end
    local success, detail = xpcall(shared.tick, debug.traceback)
    if not success then
        shared.cancel()
        shared.status_ok, shared.status = false, "木人库操作已停止，详细原因见日志"
        log.error("[SF6CC TrainingLibrary] "..tostring(detail))
    end
end
re.on_pre_application_entry("LateUpdateBehavior", State.tick_jobs)
State.editor = require("SF6CCTrainingLibrary/NativeNoteEditor").install()
require("SF6CCTrainingLibrary/NativeMenu")
local draw_panel = require("SF6CCTrainingLibrary/Panel")
re.on_draw_ui(function()
    if imgui.tree_node("木人库（独立插件）") then draw_panel(); imgui.tree_pop() end
end)
re.on_script_reset(function()
    shared.cancel()
    local success, detail = pcall(runtime.reset)
    if not success then log.error("[SF6CC TrainingLibrary] Restart required: "..tostring(detail)) end
end)
