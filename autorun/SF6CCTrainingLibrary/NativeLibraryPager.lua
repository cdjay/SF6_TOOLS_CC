-- Adapt the proven native spin protocol to a fixed library list. No hooks or
-- allocations are performed by construction; the root controls installation.
local Spin=require("SF6CCTrainingLibrary/NativeRecordingPager")
local M={}
function M.new(api,threads,current,view,redraw,allowed,report,blocked)
    local entry,owner
    local function same(a,b) return a and b and a:get_address()==b:get_address() end
    local menu={}
    local function snapshot()
        local live=current()
        if not live then return nil end
        if live~=owner then
            owner=live
            entry={phase="active",manager=live.tm,menu=menu,
                with_menu_navigation=function(_,_,_,fn) return fn() end}
        end
        return entry
    end
    function menu.owns_pager(data,parent)
        return current()==owner and view.paging()~=nil and same(data,owner.pager)
            and same(parent,owner.page)
    end
    function menu.pager_info(data)
        if current()==owner and same(data,owner.pager) then return view.paging() end
    end
    function menu.pager_for_layout(data)
        if current()==owner and (same(data,owner.page) or same(data,owner.pager))
            and view.paging() then return owner.pager end
    end
    function menu.navigate(data,parent,index)
        if not menu.owns_pager(data,parent) then return false end
        -- Preflight before changing the Lua page. The same callback binds rows
        -- and marks them dirty before the native spin performs its own repaint.
        local param=owner.tm:get_field("_UITrainingMenu"):get_field("_ParamData")
        return redraw(param,function() return view.set_page(index) end)
    end
    function menu.invalidate_view() end -- redraw already invalidated owned rows.
    function menu.text() end -- Private GUID messages are served by the root.
    function menu.command_active(data,parent)
        if current()==owner and same(data,owner.pager) and same(parent,owner.page)
            and view.paging() then return not blocked() end
    end
    -- Two users of the same spin protocol share native methods. Namespace their
    -- per-invocation storage so one post-hook cannot consume the other's result.
    local scoped={get_id=threads.get_id,get_hook_storage=function()
        local storage=threads.get_hook_storage()
        return setmetatable({}, {
            __index=function(_,key) return storage["library_"..key] end,
            __newindex=function(_,key,value) storage["library_"..key]=value end,
        })
    end}
    return Spin.new(api,scoped,snapshot,allowed,report,blocked,function() return current()~=nil end)
end
return M
