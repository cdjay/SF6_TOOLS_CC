-- Native recording/playback row binding; shared by runtime and offline tests.
-- Caller supplies an owned recording lease and a real save/thread permit.
-- This module does not install hooks, refresh views, save files, or run on load.
local M = {}
local Pager = require("SF6CCTrainingLibrary/NativeRecordingPager")
local Layout = require("SF6CCTrainingLibrary/TrainingSlotLayout")
local PAGE_SIZE = 8
local MENU = "app.training.TrainingMenuData"
local SET = "SetValue(System.Object, System.Int32)"
local STRUCT_SETTERS = {
    _MessageID = "set_MessageID(System.Guid)",
    _SubMessageID = "set_SubMessageID(System.Guid)",
    _GuideMessage = "set_GuideMessage(System.Guid)",
    _GuideMessageID = "set_GuideMessageID(System.Guid)",
    _EndWordsGuid = "set_EndWordsGuid(System.Guid)",
    _LimitValue = "set_LimitValue(via.Int2)",
}

function M.prepare(api, manager, recording, fighter_id, permit)
    local roots, pages = {}, {}
    local data, fighter
    local phase, touched = "preparing", false
    local lease = {guard_ready=false}
    local function own(value)
        assert(value, "missing native object")
        roots[#roots+1]=value
        value:add_ref()
        return value
    end
    local function equal(a,b) return a and b and a:get_address()==b:get_address() end
    local function allow(stage)
        assert(type(permit)=="table" and permit.guard_ready==true and type(permit.allows)=="function",
            "save/thread protection required")
        assert(permit.allows(stage,manager,fighter_id)==true, "native context denied: "..stage)
    end
    local function bounded(array,min,max)
        assert(array, "missing native array")
        local n=array:get_size()
        assert(n>=min and n<=max, "native menu shape outside research bound")
        return n
    end
    local function find_pages()
        local tabs=assert(manager:get_field("_UIData")):get_field("_MenuData")
        local found={}
        for i=0,bounded(tabs,1,16)-1 do
            local root=assert(tabs:get_element(i))
            if root:get_field("_FuncType")==4 then
                local selectors=root:get_field("_ChildData")
                assert(bounded(selectors,1,1)==1)
                local selector=assert(selectors:get_element(0))
                assert(selector:get_field("_FuncType")==106, "record selector changed")
                local children=selector:get_field("_ChildData")
                for j=0,bounded(children,2,3)-1 do
                    local page=assert(children:get_element(j))
                    local kind=page:get_field("_FuncType")
                    if kind==107 or kind==108 then
                        assert(not found[kind], "duplicate native page")
                        found[kind]=page
                    end
                end
            end
        end
        assert(found[107] and found[108], "record/play page missing")
        return found
    end
    local function check_owner()
        assert(equal(manager:get_field("_tData"),data), "training owner changed")
        local settings=assert(data:get_field("RecordSetting"))
        local list=assert(settings:get_field("FighterDataList"))
        local index=settings:call("GetFighterIndex",fighter_id)
        assert(type(index)=="number" and index>=0 and index<list:call("get_Count"), "fighter index changed")
        assert(equal(list:call("get_Item",index),fighter) and fighter:get_field("FighterID")==fighter_id,
            "fighter owner changed")
    end
    local function prepare()
        allow("menu_prepare")
        assert((recording.capacity==9 or recording.capacity==Layout.EXPANDED_RECORDS)
            and recording.fighter_id==fighter_id, "supported recording lease required")
        assert(recording.verify())
        manager=own(manager)
        data=own(manager:get_field("_tData"))
        local setting=assert(data:get_field("RecordSetting"))
        local list=assert(setting:get_field("FighterDataList"))
        local index=setting:call("GetFighterIndex",fighter_id)
        assert(type(index)=="number" and index>=0 and index<list:call("get_Count"), "fighter index")
        fighter=own(list:call("get_Item",index))
        check_owner()
        local found=find_pages()
        -- Validate both pages before constructing either replacement.
        for _,spec in ipairs({{107,118},{108,131}}) do
            local page=own(found[spec[1]])
            local original=own(page:get_field("_ChildData"))
            local n=bounded(original,8,19)
            local count,first,last,template,separator=0,nil,nil,nil,nil
            local slots={}
            for i=0,n-1 do
                local row=assert(original:get_element(i))
                if row:get_field("_FuncType")==spec[2] then
                    assert(row:get_field("_SlotID")==count, "noncontiguous native slot IDs")
                    first=first or i
                    assert(i==first+count,"noncontiguous native slot rows")
                    count,last,template=count+1,i,row
                    slots[#slots+1]=row
                elseif row:get_field("_Type")==4 then
                    assert(not separator,"multiple recording separators")
                    separator=i
                end
            end
            assert(count==8, "expected eight native slot rows")
            assert(separator and separator>last,"recording separator missing")
            local header=original:get_element(0)
            assert(first==1 and separator==9 and
                ((spec[1]==107 and header:get_field("_Type")==9 and header:get_field("_FuncType")==0) or
                 (spec[1]==108 and header:get_field("_Type")==0 and header:get_field("_FuncType")==130)),
                "recording header layout changed")
            pages[#pages+1]={node=page,original=original,n=n,last=last,template=template,
                separator=separator,slots=slots,index=1,windows={},kind=spec[1]}
        end
        local td=assert(api.find_type_definition(MENU))
        for _,page in ipairs(pages) do
          for slot_index=8,recording.capacity-1 do
            local row=own(api.create_instance(MENU))
            local copied=0
            local function check_field(key,expected,stage)
                local actual=row:get_field(key)
                assert(actual==expected, string.format(
                    "expanded row %s mismatch: field=%s expected=%s (%s) actual=%s (%s) copied=%d",
                    stage,key,tostring(expected),type(expected),tostring(actual),type(actual),copied))
            end
            for _,field in ipairs(td:get_fields()) do
                if not field:is_static() then
                    local key=field:get_name()
                    local value=page.template:get_field(key)
                    -- Generic SDK value-type writes use boxed size; native
                    -- setters preserve adjacent inline fields and references.
                    if STRUCT_SETTERS[key] then row:call(STRUCT_SETTERS[key],value)
                    else row:set_field(key,value) end
                    copied=copied+1
                    if key=="_SlotID" or key=="_FuncType" then check_field(key,value,"copy") end
                end
            end
            assert(copied>0,"ninth row field enumeration empty")
            check_field("_FuncType",page.template:get_field("_FuncType"),"after copy")
            row:set_field("_SlotID",slot_index)
            check_field("_SlotID",slot_index,"slot assignment")
            check_field("_FuncType",page.template:get_field("_FuncType"),"after slot assignment")
            page.slots[#page.slots+1]=row
          end
            page.pager,page.texts,page.labels=Pager.control(api,own,#page.slots,PAGE_SIZE)
            local blank=own(api.create_instance(MENU))
            for key,value in pairs({_Type=9,_FuncType=0,IsEnabled=true,IsCantFocus=true,
                IsNotFocusFunc=true,_SlotID=1,_Interval=1,_Interval_Option=1}) do blank:set_field(key,value) end
            for p=1,math.ceil(#page.slots/PAGE_SIZE) do
                -- Keep slot/footer row positions identical to the native page.
                -- Playback's start hint occupies the old separator; recording's
                -- empty header is replaced by the pager, not an extra row.
                local rows={page.pager}
                for j=1,PAGE_SIZE do
                    rows[#rows+1]=page.slots[(p-1)*PAGE_SIZE+j] or blank
                end
                rows[#rows+1]=page.original:get_element(page.kind==108 and 0 or page.separator)
                for i=page.separator+1,page.n-1 do
                    rows[#rows+1]=page.original:get_element(i)
                end
                assert(#rows<=page.n,"paged menu grew beyond native row budget")
                local expanded=own(api.create_managed_array(MENU,#rows))
                for i,value in ipairs(rows) do
                    expanded:call(SET,value,i-1)
                    assert(equal(expanded:get_element(i-1),value),"paged menu array readback failed")
                end
                page.windows[p]=expanded
            end
            for i=9,#page.slots do
                assert(page.slots[i]:get_reference_count()>=2, "menu array did not retain row")
            end
            page.expanded=page.windows[1]
        end
        phase="prepared"
        lease.guard_ready=true
    end
    function lease.owns_pager(row,parent)
        if phase~="attached" then return false end
        for _,page in ipairs(pages) do
            if equal(row,page.pager) and equal(parent,page.node) then return true end
        end
        return false
    end
    function lease.text(key)
        if phase~="attached" then return nil end
        for _,page in ipairs(pages) do
            if page.texts[key] then return page.texts[key] end
        end
    end
    function lease.slot_info(row,parent)
        if phase~="attached" then return end
        for _,page in ipairs(pages) do
            if equal(parent,page.node) then
                for i=(page.index-1)*PAGE_SIZE+1,math.min(page.index*PAGE_SIZE,#page.slots) do
                    if equal(row,page.slots[i]) then return {slot=i,page=page.kind} end
                end
            end
        end
    end
    function lease.pager_info(row)
        if phase~="attached" then return nil end
        for _,page in ipairs(pages) do
            if equal(row,page.pager) then return {index=page.index-1,count=#page.windows,label=page.labels[page.index]} end
        end
    end
    function lease.navigate(row,parent,index)
        if not lease.owns_pager(row,parent) then return false end
        allow("menu_page")
        check_owner()
        for _,page in ipairs(pages) do
            if equal(row,page.pager) and equal(parent,page.node) then
                assert(equal(page.node:get_field("_ChildData"),page.expanded),"paged menu replaced externally")
                if type(index)~="number" or index%1~=0 or index<0 or index>=#page.windows then return false end
                local next_index=index+1
                if next_index==page.index then return true end
                page.node:set_field("_ChildData",page.windows[next_index])
                -- Keep the attempted array rooted even if native readback fails.
                page.expanded=page.windows[next_index]
                assert(equal(page.node:get_field("_ChildData"),page.expanded),"page assignment readback failed")
                page.index=next_index
                return true
            end
        end
        return false
    end
    function lease.attach()
        if phase~="prepared" or touched then return false,"mount not attachable" end
        local ok,err=pcall(function()
            allow("menu_attach")
            check_owner()
            local current=find_pages()
            for _,page in ipairs(pages) do
                assert(equal(current[page.node:get_field("_FuncType")],page.node), "menu rebuilt")
                assert(equal(page.node:get_field("_ChildData"),page.original), "menu changed before attach")
            end
            touched,phase=true,"attach_uncertain"
            assert(recording.attach(fighter,permit))
            for _,page in ipairs(pages) do
                page.node:set_field("_ChildData",page.expanded)
                assert(equal(page.node:get_field("_ChildData"),page.expanded), "menu attach readback failed")
            end
            phase="attached"
        end)
        -- Caller keeps this lease and retires on the certified game thread.
        -- Never retry a partially completed attachment.
        return ok,err
    end
    function lease.retire()
        if phase~="attached" and phase~="attach_uncertain" then return false,"mount not attached" end
        local permitted,err=pcall(allow,"menu_retire")
        if not permitted then return false,err end
        phase="failed"
        local ok,reason=pcall(function()
            local function owned_window(page,value)
                for _,window in ipairs(page.windows) do if equal(window,value) then return true end end
                return false
            end
            -- After native Release, _tData may be cleared. The permit must attest
            -- that the retained old owners are idle/released on the game thread.
            for _,page in ipairs(pages) do
                local current=page.node:get_field("_ChildData")
                assert(equal(current,page.original) or owned_window(page,current), "menu replaced externally")
            end
            for i=#pages,1,-1 do
                local page=pages[i]
                if owned_window(page,page.node:get_field("_ChildData")) then
                    page.node:set_field("_ChildData",page.original)
                end
                assert(equal(page.node:get_field("_ChildData"),page.original), "menu restoration failed")
            end
            if recording.state()=="attached" or recording.state()=="attach_uncertain" then
                assert(recording.detach(permit))
            else assert(recording.state()=="prepared", "recording requires recovery") end
            phase="retired"
        end)
        return ok,reason
    end
    function lease.close()
        if phase~="prepared" and phase~="retired" then return false,"mount cannot release" end
        local permitted,err=pcall(allow,touched and "menu_dispose" or "menu_discard")
        if not permitted then return false,err end
        phase="failed"
        local ok,reason=pcall(function()
            assert(recording.close(permit))
            for i=#roots,1,-1 do roots[i]:release(); roots[i]=nil end
            pages,data,fighter,manager=nil,nil,nil,nil
            phase="closed"
        end)
        return ok,reason
    end
    function lease.state() return phase end
    local ok,err=xpcall(prepare,debug.traceback)
    if not ok then phase="failed"; return nil,tostring(err),lease end
    return lease
end
return M
