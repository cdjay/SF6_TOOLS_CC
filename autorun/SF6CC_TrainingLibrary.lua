-- Native eight-slot library: observe training readiness, then run queued jobs.
local State = require("SF6CCTrainingLibrary/State")
if State.started then return end
State.started = true

local Library = require("SF6CCTrainingLibrary/Library")
local Runtime = require("SF6CCTrainingLibrary/NativeEightRuntime")
local library = Library.shared()
local stopped = false

local function save_idle(ctx)
    local manager = sdk.get_managed_singleton("app.storage.SaveManager")
    return manager and manager:call("get_IsBusy") == false
        and ctx.session:get_field("_IsSaveReq") == false
end

local runtime = Runtime.new({library=library, context=Library.runtime_context, save_idle=save_idle})
State.runtime = runtime

re.on_pre_application_entry("LateUpdateBehavior", function()
    if stopped then return end
    local ok, err = xpcall(function()
        runtime.tick()
        if runtime.state() == "active" and library.has_pending() then
            local ctx = Library.runtime_context()
            -- A legacy bank only reaches here for the explicit restore job;
            -- Library refuses every other operation on that bank.
            if ctx.allowed and (not ctx.error or ctx.bank_unsupported == true) and ctx.menu_closed == true
                and ctx.busy == false and save_idle(ctx) then library.tick() end
        end
    end, debug.traceback)
    if not ok then
        stopped = true
        runtime.reset()
        log.error("[SF6CC-Library] Stopped: " .. tostring(err))
    end
end)

local draw_panel = require("SF6CCTrainingLibrary/Panel")
re.on_draw_ui(function()
    if stopped then return end
    if imgui.tree_node("木人库（独立插件）") then
        local ok, err = pcall(draw_panel)
        imgui.tree_pop()
        if not ok then
            library.status_ok, library.status = false, "管理面板显示失败，详情见日志"
            log.error("[SF6CC-Library] " .. tostring(err))
        end
    end
end)
re.on_script_reset(function()
    stopped = true
    runtime.reset()
end)

local ok, err = pcall(require,"SF6CCTrainingLibrary/NativeLibraryTab")
if not ok then log.error("[SF6CC-Library] Menu unavailable: " .. tostring(err)) end
local names_ok, names_err = pcall(require,"SF6CCTrainingLibrary/NativeSlotNames")
if not names_ok then log.error("[SF6CC-Library] Slot names unavailable: " .. tostring(names_err)) end
