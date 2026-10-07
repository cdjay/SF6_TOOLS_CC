-- Plain-Lua presentation state. A fixed 13-row body avoids rebuilding native
-- arrays while navigating. Catalog labels and paths always share one revision.
local M={COUNT=13,PAGE_SIZE=8}
local Compatibility=require("SF6CCTrainingLibrary/TrainingConfigCompatibility")
local Layout=require("SF6CCTrainingLibrary/TrainingSlotLayout")
function M.new(library,can_rename)
    local self={}
    local mode,page,catalog,revision,armed="main",1,{},nil,nil
    local fighter
    local session,data,slots=nil,nil,{}
    local frames={}
    local clear_armed=false
    local function row(text,command,index) return {text=text,command=command,index=index,readonly=command==nil,kind=0} end
    local function separator() return {text="",readonly=true,kind=4} end
    local function info(text) return row("<color A8DEFF>"..text.."</color>") end
    local function selected_path() local e=library.selection(); return e and e.path end
    local function matches(entry)
        return entry and Compatibility.check(entry.metadata,{fighter_id=fighter},{reject_fighter_mismatch=true})==true
    end
    local function capture()
        catalog={}; revision=library.revision; armed=nil
        for i,entry in ipairs(library.entries) do
            if matches(entry) then catalog[#catalog+1]={path=entry.path,label=library.selection_label(i),source_index=i} end
        end
        page=math.min(page,math.max(1,math.ceil(#catalog/M.PAGE_SIZE)))
    end
    function self.closed()
        mode,page,armed="main",1,nil
        clear_armed=false
    end
    function self.set_context(ctx)
        local next_fighter=ctx and ctx.allowed and not ctx.error and ctx.fighter_id or nil
        if fighter~=next_fighter or session~=(ctx and ctx.session) or data~=(ctx and ctx.data) then
            fighter=next_fighter
            self.closed()
            capture()
        end
        session,data=ctx and ctx.session,ctx and ctx.data
        -- Read native capacity only in the caller's closed-menu update, never
        -- from a message or navigation hook. The list consumes this Lua snapshot.
        local previous_count=#slots
        slots={}; frames={}
        if fighter and library.can_edit_slot_names and library.can_edit_slot_names() then
            local ok,names=pcall(function()
                local count=library.slot_capacity()
                assert(count==Layout.NATIVE_RECORDS)
                local values={}
                for i=1,count do
                    values[i]=library.slot_name(i)
                    assert(type(values[i])=="string")
                end
                return values
            end)
            if ok then slots=names end
            if #slots>0 and library.record_frames then
                local ready,snapshot=pcall(library.record_frames)
                if ready and type(snapshot)=="table" and snapshot.fighter_id==fighter
                    and type(snapshot.frames)=="table" and #snapshot.frames==#slots then
                    for i=1,#slots do
                        local frame=snapshot.frames[i]
                        if type(frame)=="number" and frame%1==0 and frame>=0 then frames[i]=frame end
                    end
                end
            end
        end
        if mode=="slots" and previous_count~=#slots then self.closed() end
    end
    local function slots_editable()
        return #slots>0 and can_rename and can_rename() and library.can_edit_slot_names()
    end
    function self.page_counts()
        local count=0
        for _,entry in ipairs(library.entries) do if matches(entry) then count=count+1 end end
        return {math.max(1,math.ceil(count/M.PAGE_SIZE)),math.max(1,math.ceil(#slots/M.PAGE_SIZE))}
    end
    function self.paging()
        if mode=="main" then return nil end
        local count=math.max(1,math.ceil((mode=="slots" and #slots or #catalog)/M.PAGE_SIZE))
        if count==1 then return nil end
        return {index=page-1,count=count,label=page.." / "..count}
    end
    function self.pager_row() return mode=="slots" and 1 or 10 end
    function self.set_page(index)
        local info=self.paging()
        if not info or library.has_pending() or type(index)~="number" or index%1~=0
            or index<0 or index>=info.count then return false end
        page=index+1; armed=nil; clear_armed=false
        return true
    end
    function self.rows()
        if mode=="main" then
            local selected=matches(library.selection())
            local d=selected and library.selection_details() or {character="-",slots="-",saved="-"}
            return {
                row("切换配置【当前："..(selected and library.selection_label() or "未选择配置").."】","open"),
                separator(),row("保存当前配置",selected and "save" or nil),row("另存当前配置","export"),
                row("修改当前配置名称",selected and can_rename and can_rename() and "rename" or nil),
                row("修改栏位说明",slots_editable() and "open_slots" or nil),
                row((clear_armed and "【再次确认清空】" or "").."清空所有栏位","clear"),separator(),
                info("配置信息"),info("角色："..d.character),
                info(d.slots),info("保存时间："..d.saved),row(""),
            }
        end
        local editing_slots=mode=="slots"
        local count=editing_slots and #slots or #catalog
        local pages=math.max(1,math.ceil(count/M.PAGE_SIZE))
        local page_row=pages>1 and {text="页码",command="page",readonly=false,kind=1} or row("页码 1 / 1")
        local rows={editing_slots and page_row or info("选择配置（"..page.."/"..pages.."）")}
        for i=1,M.PAGE_SIZE do
            local index=(page-1)*M.PAGE_SIZE+i
            if editing_slots then
                local name=slots[index]
                local frame=frames[index]
                local length=frame==nil and "帧数暂不可用" or (frame==0 and " - " or (frame.."帧"))
                local label="栏位"..index
                local text=label.."："..(name and name~="" and name or label).."（"..length.."）"
                if frame==0 then text="<color 999999>"..text.."</color>" end
                rows[#rows+1]=name and row(text,
                    slots_editable() and "slot_name" or nil,index) or row("")
            else
                local entry=catalog[index]
                local marker=entry and armed==entry.path and selected_path()==entry.path and "【再次确认导入】" or ""
                rows[#rows+1]=entry and row(marker..entry.label,"choose",index)
                    or (i==1 and #catalog==0 and info("当前角色暂无配置") or row(""))
            end
        end
        rows[10]=editing_slots and row("返回","back") or (pages>1 and page_row or row(""))
        rows[11]=row("")
        rows[12]=editing_slots and row("") or row("刷新配置列表","refresh")
        rows[13]=editing_slots and row("") or row("返回","back")
        return rows
    end
    function self.command(index)
        if type(index)~="number" or index%1~=0 then return nil end
        local item=self.rows()[index]
        return item and item.command
    end
    function self.activate(index)
        local item=self.rows()[index]
        if not item or item.command~="clear" or library.has_pending() then clear_armed=false end
        if not item or not item.command then return {} end
        if library.has_pending() then return {notice="上一次操作尚未完成，请稍候"} end
        local kind=item.command
        if kind=="clear" then
            armed=nil
            if clear_armed then clear_armed=false; return {operation="clear",redraw=true} end
            clear_armed=true
            return {redraw=true}
        end
        if kind=="open" then mode="list"; page=1; capture(); return {redraw=true} end
        if kind=="open_slots" then mode="slots"; page=1; armed=nil; return {redraw=true} end
        if kind=="slot_name" then return {operation="slot_name",slot=item.index} end
        if kind=="back" then self.closed(); return {redraw=true} end
        if kind=="refresh" then armed=nil; return {operation="refresh"} end
        if kind=="page" then return {} end -- Native spin commits through set_page.
        if kind=="choose" then
            local entry=catalog[item.index]
            local live=entry and library.entries[entry.source_index]
            if revision~=library.revision or not live or not entry or live.path~=entry.path or not matches(live) then
                capture()
                return {redraw=true,notice="配置列表已变化，请重新选择"}
            end
            if armed==entry.path and selected_path()==entry.path then
                armed=nil
                return {operation="import"}
            end
            armed=nil
            if library.select(entry.source_index) then armed=entry.path; return {redraw=true} end
            return {notice="暂时无法选择配置"}
        end
        armed=nil
        return {operation=kind}
    end
    function self.cancel_confirmation() armed=nil; clear_armed=false end
    function self.confirming_clear() return clear_armed end
    return self
end
return M
