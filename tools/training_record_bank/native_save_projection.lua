-- Research-only independent native save snapshots. No hooks, live writes or IO.
-- Publication/async ownership and reset integration are NOT implemented here.
local M={MAX_PROJECTIONS=2}

function M.prepare(manager,fighter_id,threads)
    local roots,published,known={},false,{}
    local uncertain=false
    local data,baseline,baseline_bank,selection,owner_thread
    local calls,phase=0,"preparing"
    local lease={guard_ready=false}
    local function own(value)
        assert(value,"native allocation returned nil")
        roots[#roots+1]=value
        value:add_ref()
        return value
    end
    local function same(a,b) return a and b and a:get_address()==b:get_address() end
    local function on_thread()
        assert(threads.get_id()==owner_thread,"native projection called on different thread")
    end
    local function banks(value)
        local settings=assert(value:get_field("RecordSetting"))
        local list=assert(settings:get_field("FighterDataList"))
        local n=list:call("get_Count")
        assert(type(n)=="number" and n>=1 and n<=64,"fighter list bound")
        local result,ids={},{}
        for i=0,n-1 do
            local fighter=assert(list:call("get_Item",i))
            local id=fighter:get_field("FighterID")
            assert(type(id)=="number" and id%1==0 and id>=0 and not ids[id],"fighter identity")
            ids[id]=true
            local bank=assert(fighter:get_field("RecordSlots"))
            local size=bank:get_size()
            assert(size>=1 and size<=(id==fighter_id and 9 or 8),"record bank bound")
            for slot=0,size-1 do
                local row=assert(bank:get_element(slot))
                local input=row:get_field("InputData")
                local buffer=input and input:get_field("buff")
                assert(not buffer or buffer:get_size()<=3600,"input buffer bound")
            end
            result[#result+1]={id=id,owner=fighter,bank=bank,size=size}
        end
        assert(ids[fighter_id],"selected fighter missing")
        return result
    end
    local function selected(layout)
        for _,entry in ipairs(layout) do if entry.id==fighter_id then return entry end end
        error("selected fighter missing")
    end
    local function independent(source,copy)
        assert(#source==#copy,"copy changed fighter count")
        for i,original in ipairs(source) do
            local dest=copy[i]
            assert(original.id==dest.id and original.size==dest.size,"copy changed fighter identity/capacity")
            assert(not same(original.owner,dest.owner) and not same(original.bank,dest.bank),"copy aliases fighter/bank")
            for j=0,original.size-1 do
                local a,b=original.bank:get_element(j),dest.bank:get_element(j)
                assert(not same(a,b),"copy aliases slot")
                for _,key in ipairs({"Frame","Weight","IsActive","IsValid"}) do
                    assert(a:get_field(key)==b:get_field(key),"copy changed slot metadata")
                end
                local ai,bi=a:get_field("InputData"),b:get_field("InputData")
                assert((ai==nil)==(bi==nil),"copy changed input presence")
                if ai then
                    assert(not same(ai,bi),"copy aliases input")
                    local ab,bb=ai:get_field("buff"),bi:get_field("buff")
                    assert((ab==nil)==(bb==nil) and (not ab or not same(ab,bb)),"copy aliases input buffer")
                    assert(not ab or ab:get_size()==bb:get_size(),"copy changed buffer capacity")
                end
            end
        end
    end
    local function duplicate()
        local source=banks(data)
        local copy=own(data:call("Duplicate"))
        assert(not same(copy,data),"Duplicate returned live data")
        local layout=banks(copy)
        independent(source,layout)
        return copy,layout
    end
    local function prepare()
        assert(type(fighter_id)=="number" and fighter_id%1==0 and fighter_id>=0,"invalid fighter")
        owner_thread=threads.get_id()
        assert(owner_thread~=nil,"thread identity unavailable")
        manager=own(manager)
        data=own(manager:get_field("_tData"))
        assert(selected(banks(data)).size==8,"baseline requires original eight slots")
        local layout
        baseline,layout=duplicate()
        baseline_bank=selected(layout).bank
        selection=baseline:get_field("SelectChildIndex")
        assert(selection~=nil,"native selection baseline missing")
        known[baseline]=true
        phase="ready"
    end
    function lease.project()
        if phase=="blocked" then return baseline,"projection blocked; use retained fallback" end
        if phase~="ready" then return nil,"projection unavailable" end
        local result
        local ok,err=pcall(function()
            on_thread()
            assert(same(manager:get_field("_tData"),data),"training owner changed")
            assert(calls<M.MAX_PROJECTIONS,"projection budget exhausted")
            calls=calls+1
            uncertain=true
            local copy,layout=duplicate()
            local target=selected(layout)
            -- Do not DeepCopy an entire donor FighterData: that also changes ID.
            target.owner:set_field("RecordSlots",baseline_bank)
            assert(target.owner:get_field("FighterID")==fighter_id
                and same(target.owner:get_field("RecordSlots"),baseline_bank),"save bank replacement failed")
            copy:set_field("SelectChildIndex",selection)
            assert(selected(banks(copy)).size==8,"save projection still expanded")
            known[copy]=true
            result=copy
            uncertain=false
        end)
        if not ok then phase="blocked"; return baseline,tostring(err) end
        return result
    end
    function lease.mark_returned(value)
        if not known[value] then return false,"unknown save result" end
        published=true
        return true
    end
    function lease.close_unpublished()
        if published then return false,"native save consumer lifetime is not established" end
        if uncertain then return false,"native projection failure retained; no speculative release" end
        if phase~="ready" and phase~="blocked" then return false,"projection not releasable" end
        local permitted,err=pcall(on_thread)
        if not permitted then return false,err end
        phase="failed"
        local ok,reason=pcall(function()
            for i=#roots,1,-1 do roots[i]:release(); roots[i]=nil end
            data,baseline,baseline_bank,selection,manager,known=nil,nil,nil,nil,nil,{}
            phase="closed"
        end)
        return ok,reason
    end
    function lease.state() return phase end
    local ok,err=pcall(prepare)
    if not ok then phase="failed"; return nil,tostring(err),lease end
    return lease
end
return M
