-- Native recording/playback row binding; shared by runtime and offline tests.
-- Caller supplies an owned recording lease and a real save/thread permit.
-- This module marks owned views dirty, but never invokes native UI rebuilds.
local M = {}
local Pager = require("SF6CCTrainingLibrary/NativeRecordingPager")
local Layout = require("SF6CCTrainingLibrary/TrainingSlotLayout")
local PAGE_SIZE = 8
local MENU = "app.training.TrainingMenuData"
local SET = "SetValue(System.Object, System.Int32)"
local BIND_FIELDS = {"_SlotID", "_Type", "_FuncType", "IsEnabled", "IsCantFocus"}
local STRUCT_SETTERS = {
    _MessageID = "set_MessageID(System.Guid)",
    _SubMessageID = "set_SubMessageID(System.Guid)",
    _GuideMessage = "set_GuideMessage(System.Guid)",
    _GuideMessageID = "set_GuideMessageID(System.Guid)",
    _EndWordsGuid = "set_EndWordsGuid(System.Guid)",
    _LimitValue = "set_LimitValue(via.Int2)",
}

    local function bounded(array,min,max)
        assert(array, "missing native array")
        local n=array:get_size()
        assert(n>=min and n<=max, "native menu shape outside research bound")
        return n
    end
    local function find_pages(manager)
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
    -- Read-only preflight: no allocation, reference retention, or native writes.
    local function inspect_native(manager)
        local pages,found={},find_pages(manager)
        -- Validate both pages before constructing either replacement.
        for _,spec in ipairs({{107,118},{108,131}}) do
            local page=found[spec[1]]
            local original=page:get_field("_ChildData")
            local n=bounded(original,8,19)
            local count,first,last,separator=0,nil,nil,nil
            local slots,native_rows={},{}
            for i=0,n-1 do
                local row=assert(original:get_element(i))
                native_rows[i+1]=row
                if row:get_field("_FuncType")==spec[2] then
                    assert(row:get_field("_SlotID")==count, "noncontiguous native slot IDs")
                    first=first or i
                    assert(i==first+count,"noncontiguous native slot rows")
                    count,last=count+1,i
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
            pages[#pages+1]={node=page,original=original,n=n,
                separator=separator,slots=slots,index=1,kind=spec[1],native_rows=native_rows}
        end
        return pages
    end

function M.validate_native(manager)
    return pcall(inspect_native,manager)
end

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
    local function check_owner()
        assert(equal(manager:get_field("_tData"),data), "training owner changed")
        local settings=assert(data:get_field("RecordSetting"))
        local list=assert(settings:get_field("FighterDataList"))
        local index=settings:call("GetFighterIndex",fighter_id)
        assert(type(index)=="number" and index>=0 and index<list:call("get_Count"), "fighter index changed")
        assert(equal(list:call("get_Item",index),fighter) and fighter:get_field("FighterID")==fighter_id,
            "fighter owner changed")
    end
    local function binding(page,index,i)
        local slot=(index-1)*PAGE_SIZE+i-1
        if slot>=recording.capacity then
            return {_SlotID=0,_Type=9,_FuncType=0,IsEnabled=false,IsCantFocus=true}
        end
        local source=page.defaults[i]
        return {_SlotID=slot,_Type=source._Type,_FuncType=source._FuncType,
            IsEnabled=source.IsEnabled,IsCantFocus=source.IsCantFocus}
    end
    local function assert_binding(page,index)
        assert(not page.invalid,"window binding is unavailable")
        for i,row in ipairs(page.slots) do
            assert(row:get_reference_count()>0 and row:get_type_definition(),"window row expired")
            local expected=binding(page,index,i)
            for _,key in ipairs(BIND_FIELDS) do
                assert(row:get_field(key)==expected[key],"window binding changed externally: "..key)
            end
        end
    end
    local function bind(page,index)
        -- A partial native write must not authorize a mixed page of commands.
        page.invalid=true
        for i,row in ipairs(page.slots) do
            local expected=binding(page,index,i)
            for _,key in ipairs(BIND_FIELDS) do
                if row:get_field(key)~=expected[key] then row:set_field(key,expected[key]) end
                assert(row:get_field(key)==expected[key],"window binding readback failed: "..key)
            end
        end
        page.index=index
        page.invalid=false
    end
    local function prepare()
        allow("menu_prepare")
        assert((recording.capacity==9 or recording.capacity==Layout.EXPANDED_RECORDS)
            and recording.fighter_id==fighter_id, "supported recording lease required")
        assert(recording.verify())
        pages=inspect_native(manager)
        -- Keep borrowed wrappers in this lease, not in the manual-release list.
        -- Lua add_ref is shared/deduplicated across the menu and recording lease.
        data=assert(manager:get_field("_tData"))
        local setting=assert(data:get_field("RecordSetting"))
        local list=assert(setting:get_field("FighterDataList"))
        local index=setting:call("GetFighterIndex",fighter_id)
        assert(type(index)=="number" and index>=0 and index<list:call("get_Count"), "fighter index")
        fighter=assert(list:call("get_Item",index))
        check_owner()
        local td=assert(api.find_type_definition(MENU))
        for _,page in ipairs(pages) do
          -- Temporary, bounded initialization diagnostics. Identities and the
          -- last successful observation are cached before an object can expire.
          local observed,by_value={},{}
          local function checkpoint(value,stage)
            local item=assert(by_value[value],"untracked native menu object")
            local ok,refs,typed=pcall(function()
                local count=value:get_reference_count()
                return count,count>0 and value:get_type_definition()~=nil
            end)
            if not ok or not typed then
                error(string.format(
                    "[DEBUG-SF6CC-menu-lifetime] native menu row expired; array insertion refused; "..
                    "origin=%s page=%d slot=%s native_row=%s address=%s stage=%s "..
                    "refs=%s type_available=%s last=%s last_refs=%s created_refs=%s",
                    item.origin,page.kind,tostring(item.slot),tostring(item.native_row),item.address,stage,
                    ok and tostring(refs) or "read_failed",tostring(typed==true),item.last,
                    tostring(item.refs),tostring(item.created_refs)),0)
            end
            item.last,item.refs=stage,refs
          end
          local function watch(value,origin,slot,native_row,retain)
            assert(value,"missing native menu object: "..origin)
            local item={value=value,origin=origin,slot=slot,native_row=native_row,
                address=tostring(value:get_address()),last="unobserved"}
            by_value[value]=item; observed[#observed+1]=item
            if retain then
                item.created_refs=value:get_reference_count()
                own(value)
            end
            checkpoint(value,retain and "retained" or "source")
            return value
          end
          local function checkpoint_all(stage)
            for _,item in ipairs(observed) do checkpoint(item.value,stage) end
          end
          -- Startup-only diagnosis: detect damage to earlier rows at the next
          -- native boundary, rather than after all row allocations. Bound the
          -- detailed window to eight rows; the whole-page checks remain below.
          local function checkpoint_recent(stage,slot)
            local boundary="construction_slot_"..slot..":"..stage
            for i=math.max(1,#page.slots-7),#page.slots do
                checkpoint(page.slots[i],boundary)
            end
          end
          for i,value in ipairs(page.native_rows) do
              local slot=i>=2 and i<=9 and i-1 or nil
              watch(value,slot and "native_slot" or (i==1 and "native_header" or
                  (i==page.separator+1 and "native_separator" or "native_footer")),slot,i-1)
          end
          -- Hold each new row in a native array before copying or allocating the
          -- next row. Lua add_ref is deduplicated and is not an extra native owner.
          local sources=page.slots
          page.slots,page.defaults={},{}
          local staged_rows=own(api.create_managed_array(MENU,PAGE_SIZE))
          for slot_index=0,PAGE_SIZE-1 do
            local source=sources[slot_index+1]
            local defaults={}
            for _,key in ipairs(BIND_FIELDS) do defaults[key]=source:get_field(key) end
            page.defaults[slot_index+1]=defaults
            checkpoint_recent("before_create",slot_index+1)
            local row=watch(api.create_instance_global(MENU),"expanded_slot",slot_index+1,nil,true)
            checkpoint_recent("after_create",slot_index+1)
            staged_rows:call(SET,row,slot_index)
            checkpoint_recent("after_staging",slot_index+1)
            checkpoint(row,"native_root_owned")
            assert(equal(staged_rows:get_element(slot_index),row),"staged menu row readback failed")
            assert(row:get_reference_count()>=2,"staged native array did not retain menu row")
            local copied=0
            local function check_field(key,expected,stage)
                checkpoint(row,stage..":"..key)
                local actual=row:get_field(key)
                assert(actual==expected, string.format(
                    "expanded row %s mismatch: field=%s expected=%s (%s) actual=%s (%s) copied=%d",
                    stage,key,tostring(expected),type(expected),tostring(actual),type(actual),copied))
            end
            for _,field in ipairs(td:get_fields()) do
                if not field:is_static() then
                    local key=field:get_name()
                    local value=source:get_field(key)
                    checkpoint_recent("after_read:"..key,slot_index+1)
                    checkpoint(row,"before_write:"..key)
                    -- Generic SDK value-type writes use boxed size; native
                    -- setters preserve adjacent inline fields and references.
                    if STRUCT_SETTERS[key] then row:call(STRUCT_SETTERS[key],value)
                    else row:set_field(key,value) end
                    checkpoint_recent("after_write:"..key,slot_index+1)
                    checkpoint(row,"after_write:"..key)
                    copied=copied+1
                    if key=="_SlotID" or key=="_FuncType" then check_field(key,value,"copy") end
                end
            end
            assert(copied>0,"private row field enumeration empty")
            checkpoint(row,"fields_copied")
            check_field("_FuncType",source:get_field("_FuncType"),"after copy")
            row:set_field("_SlotID",slot_index)
            checkpoint_recent("after_slot_assignment",slot_index+1)
            check_field("_SlotID",slot_index,"slot assignment")
            check_field("_FuncType",source:get_field("_FuncType"),"after slot assignment")
            checkpoint(row,"slot_assigned")
            page.slots[#page.slots+1]=row
          end
            checkpoint_all("after_slot_creation")
            local pager_part=0
            page.pager,page.texts,page.labels=Pager.control(api,function(value)
                pager_part=pager_part+1
                return watch(value,"pager_part_"..pager_part,nil,nil,true)
            end,recording.capacity,PAGE_SIZE)
            by_value[page.pager].origin="pager"
            checkpoint_all("after_pager_creation")
            bind(page,1)
            do
                -- Keep slot/footer row positions identical to the native page.
                -- Playback's start hint occupies the old separator; recording's
                -- empty header is replaced by the pager, not an extra row.
                local rows={page.pager}
                for j=1,PAGE_SIZE do
                    rows[#rows+1]=page.slots[j]
                end
                rows[#rows+1]=page.native_rows[(page.kind==108 and 0 or page.separator)+1]
                for i=page.separator+1,page.n-1 do
                    rows[#rows+1]=page.native_rows[i+1]
                end
                assert(#rows<=page.n,"paged menu grew beyond native row budget")
                checkpoint_all("before_window_allocation")
                local expanded=own(api.create_managed_array(MENU,#rows))
                checkpoint_all("after_window_allocation")
                for i,value in ipairs(rows) do
                    checkpoint(value,"before_array_insertion")
                    expanded:call(SET,value,i-1)
                    assert(equal(expanded:get_element(i-1),value),"paged menu array readback failed")
                    checkpoint(value,"array_owned")
                end
                page.expanded=expanded
            end
            checkpoint_all("page_prepared")
            for i=1,#page.slots do
                assert(page.slots[i]:get_reference_count()>=2, "menu array did not retain row")
            end
            page.count=math.ceil(recording.capacity/PAGE_SIZE)
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
            if not page.invalid and equal(parent,page.node) then
                for i,value in ipairs(page.slots) do
                    local slot=(page.index-1)*PAGE_SIZE+i
                    if equal(row,value) and slot<=recording.capacity then
                        local expected=binding(page,page.index,i)
                        for _,key in ipairs(BIND_FIELDS) do
                            if row:get_field(key)~=expected[key] then return end
                        end
                        return {slot=slot,page=page.kind}
                    end
                end
            end
        end
    end
    function lease.command_active(row,parent)
        if phase~="attached" then return nil end
        for _,page in ipairs(pages) do
            if equal(parent,page.node) then
                if equal(row,page.pager) then return not page.invalid end
                for _,value in ipairs(page.slots) do
                    if equal(row,value) then return lease.slot_info(row,parent)~=nil end
                end
            end
        end
    end
    function lease.invalidate_view(param,row,parent)
        assert(lease.owns_pager(row,parent),"unknown window pager")
        allow("menu_page")
        check_owner()
        local list=assert(param:get_field("_ViewDataList"),"missing native view data")
        local count=list:call("get_Count")
        assert(type(count)=="number" and count%1==0 and count>=1 and count<=32,"native view count outside bound")
        local targets,has_pager={},false
        for i=0,count-1 do
            local view=assert(list:call("get_Item",i))
            local data,p=view:get_field("Data"),view:get_field("ParentData")
            if equal(p,parent) and (equal(data,row) or lease.command_active(data,p)~=nil) then
                targets[#targets+1]=view
                has_pager=has_pager or equal(data,row)
            end
        end
        assert(has_pager,"current native view does not own this pager")
        -- Request the engine's normal row update; never invoke a GUI rebuild.
        for _,view in ipairs(targets) do view:set_field("IsUpdate",true) end
    end
    function lease.pager_info(row)
        if phase~="attached" then return nil end
        for _,page in ipairs(pages) do
            if equal(row,page.pager) then return {index=page.index-1,count=page.count,label=page.labels[page.index]} end
        end
    end
    function lease.pager_for_layout(row)
        if phase~="attached" then return nil end
        for _,page in ipairs(pages) do
            if equal(row,page.node) or equal(row,page.pager) then return page.pager end
        end
    end
    function lease.navigate(row,parent,index)
        if not lease.owns_pager(row,parent) then return false end
        allow("menu_page")
        check_owner()
        for _,page in ipairs(pages) do
            if equal(row,page.pager) and equal(parent,page.node) then
                assert(equal(page.node:get_field("_ChildData"),page.expanded),"paged menu replaced externally")
                if type(index)~="number" or index%1~=0 or index<0 or index>=page.count then return false end
                assert_binding(page,page.index)
                local next_index=index+1
                if next_index==page.index then return true end
                bind(page,next_index)
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
            local current=find_pages(manager)
            for _,page in ipairs(pages) do
                assert_binding(page,page.index)
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
    function lease.reload()
        if phase~="attached" then return false,"分页未挂载，不能局部恢复" end
        return pcall(function()
            local changed=false
            allow("menu_reload")
            check_owner()
            local current=find_pages(manager)
            for _,page in ipairs(pages) do
                assert(equal(current[page.node:get_field("_FuncType")],page.node),"menu rebuilt; restart required")
                local rows=page.node:get_field("_ChildData")
                local owned=equal(rows,page.original)
                owned=owned or equal(rows,page.expanded)
                assert(owned,"foreign menu replacement; reload refused")
                assert_binding(page,page.index)
            end
            for _,page in ipairs(pages) do
                if not equal(page.node:get_field("_ChildData"),page.expanded) then
                    changed=true
                    page.node:set_field("_ChildData",page.expanded)
                end
                assert(equal(page.node:get_field("_ChildData"),page.expanded),"menu reload readback failed")
            end
            return changed
        end)
    end
    function lease.retire()
        if phase~="attached" and phase~="attach_uncertain" then return false,"mount not attached" end
        local permitted,err=pcall(allow,"menu_retire")
        if not permitted then return false,err end
        phase="failed"
        local ok,reason=pcall(function()
            local function owned_window(page,value)
                return equal(value,page.expanded)
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
