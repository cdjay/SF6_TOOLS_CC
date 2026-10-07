-- Plain Lua event routing. Operation reasons/results belong to native tickers,
-- never to a pause-menu status row or an ImGui fallback.
local Messages=require("SF6CCTrainingLibrary/LibraryMessages")
local Safety=require("SF6CCTrainingLibrary/Context")
local M={}
local waits={
    ["已排队，关闭游戏暂停菜单后执行"]=true,
}
function M.new(library,ticker,deps)
    local pause_open=deps and deps.pause_open or Safety.pause_open
    local last_text,last_ok,last_revision
    local waiting
    local self={}
    local function clear_wait()
        if waiting and ticker.discard then ticker.discard(waiting.text) end
        waiting=nil
    end
    local function remember()
        last_text,last_ok,last_revision=library.status,library.status_ok,library.result_revision
    end
    function self.notify(text)
        remember()
        local detail=tostring(text or library.status or "操作未完成")
        if log and log.info then pcall(log.info,"[NativeLibraryFeedback] "..detail) end
        -- The editor queues this after its dialog has ended; only the commit
        -- result is useful to the user, not a redundant close-dialog reminder.
        if (detail=="配置名称已确认，关闭弹窗后保存" or detail=="名称已确认，关闭弹窗后应用")
            and library.status_ok==true then clear_wait(); return end
        local result=library.result_configuration
        local title=result and result.revision==library.result_revision and result.title or nil
        local message=Messages.format(detail,library.status_ok,title)
        if waits[detail] and library.status_ok==true then
            if not waiting or waiting.detail~=detail then
                clear_wait()
                waiting={detail=detail,text=message,checks=0,sent=false}
            end
            return
        end
        clear_wait()
        ticker.enqueue(message)
    end
    function self.request(kind,action)
        if library.has_pending() then
            self.notify("上一次操作尚未完成，请稍候")
            return false
        end
        local accepted
        if action then accepted=action() else accepted=library.request(kind) end
        -- This entry is used only by native action rows, which return the
        -- game's close-menu result on acceptance. Library.tick already waits
        -- for menu_closed before executing. Do not race that close animation
        -- with a manual-close reminder; polling will deliver the final result.
        if accepted then clear_wait(); remember()
        else self.notify(library.status) end
        return accepted
    end
    function self.tick(allowed)
        if not allowed then clear_wait(); remember(); ticker.tick(false); return end
        if library.status~=last_text or library.status_ok~=last_ok or library.result_revision~=last_revision then
            if library.status and library.status~="" and library.status~="就绪" then self.notify(library.status)
            else remember() end
        end
        if waiting then
            if library.status~=waiting.detail or library.status_ok~=true then clear_wait()
            else
                -- Only read pause state on the existing safe update, never in
                -- a menu callback. Allow its native auto-close to settle first.
                local ok,open=pcall(pause_open)
                if ok and open==true then
                    waiting.checks=waiting.checks+1
                    if waiting.checks>=2 and not waiting.sent then
                        ticker.enqueue(waiting.text)
                        waiting.sent=true
                    end
                else
                    waiting.checks=0
                    if ticker.discard then ticker.discard(waiting.text) end
                end
            end
        end
        ticker.tick(true)
    end
    remember()
    return self
end
return M
