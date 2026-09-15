package.path = "autorun/?.lua;" .. package.path
local Runtime = require("SF6CCTrainingLibrary/NativeRecordingRuntime")
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
local fixture = require("tools.fixtures.native_recording_runtime")
local function pre_seed_fixture(options)
    options=options or {}
    options.session=require("tools.fixtures.native_recording_session_pre_seed")
    return fixture(options)
end

test("captured temporary child-option callback paints the selected page on its first click",function()
    for _,page_index in ipairs({1,2}) do
        local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
        local allocations=f.native_work.allocations
        for _,wanted in ipairs({1,2,3,2,0}) do
            local painted
            f.option_arrow(page_index,wanted,true,function(page)
                painted=page.fields._ChildData:get_element(1).fields._SlotID
            end)
            assert(painted==wanted*8,"child callback painted old page: wanted="..wanted.." slot="..painted)
            f.ui_tick(3)
            assert(f.pages[page_index].fields._ChildData:get_element(1).fields._SlotID==wanted*8)
        end
        assert(f.native_work.allocations==allocations,"pager allocated native objects")
        assert(not f.native_work.view_updates,"forced native refresh")
    end
end)

test("temporary child spin rejects foreign ownership, selection and spinner arguments",function()
    for _,change in ipairs({
        function(f,args) args[5].fields.ParentData=f.obj() end,
        function(f,args) args[5].fields.Data=f.obj() end,
        function(_,args) args[5].fields.Data=args[5].fields.ParentData.fields._ChildData:get_element(2) end,
        function(f,args) args[4]=f.obj() end,
        function(_,args) args[6]=2 end,
        function(_,args) args[4].fields._SecondarySpinIndex=0; args[6]=0 end,
        function(_,args) args[5].fields.ParentData.fields._ChildData.items={} end,
    }) do
        local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
        local painted
        f.option_arrow(1,1,true,function(page) painted=page.fields._ChildData:get_element(1).fields._SlotID end,
            function(args) change(f,args); return args end)
        assert(painted==0,"unverified child callback changed visible data")
        assert(not f.stats.error,"invalid child callback stopped pager: "..tostring(f.stats.error))
    end
end)

test("temporary child action outside its native spin cannot request navigation",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    local page,v,param=f.focus_page(1)
    local row=v.fields.Data
    local child=f.obj({Data=row.fields._ChildData:get_element(1),ParentData=row,Index=0})
    v.fields.Index=1
    local skip=f.hook_call("Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)",
        {0,f.manager.fields._UIFunc,345,param,child,1})
    f.ui_tick(3)
    assert(skip==nil and page.fields._ChildData:get_element(1).fields._SlotID==0)
end)

test("temporary child spin waits while a library operation blocks navigation",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    f.stats.pending=true
    local painted
    f.option_arrow(1,1,true,function(page) painted=page.fields._ChildData:get_element(1).fields._SlotID end)
    assert(painted==0,"blocked child action committed navigation")
    f.ui_tick(3); assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==0)
    f.stats.pending=false; f.ui_tick(2)
    assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==8)
end)

test("native spin repaint sees the newly committed page without a second click",function()
    for _,page_index in ipairs({1,2}) do
        local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
        local allocations=f.native_work.allocations
        local painted={}
        for _,wanted in ipairs({1,2,3,2,1,0}) do
            f.arrow(page_index,wanted,true,function(page)
                painted[#painted+1]=page.fields._ChildData:get_element(1).fields._SlotID
            end)
            assert(painted[#painted]==wanted*8,
                "native repaint saw previous page: wanted="..wanted.." first_slot="..painted[#painted])
            f.ui_tick(3)
            assert(f.pages[page_index].fields._ChildData:get_element(1).fields._SlotID==wanted*8,
                "post-spin fallback applied page twice")
        end
        assert(f.native_work.allocations==allocations,"native spin allocated menu objects")
        assert(not f.native_work.view_updates,"forced native refresh")
    end
end)

test("native spin does not commit a foreign callback or an uncommitted value",function()
    for _,change in ipairs({
        function(f,args) args[4]=f.obj(); return args end,
        function(f,args) args[5]=f.obj({Data=args[5].fields.Data,ParentData=args[5].fields.ParentData,Index=1}); return args end,
        function(_,args) args[6]=2; return args end,
    }) do
        local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
        local painted
        f.arrow(1,1,true,function(page) painted=page.fields._ChildData:get_element(1).fields._SlotID end,
            function(args) return change(f,args) end)
        assert(painted==0,"foreign or uncommitted spin changed visible data")
        f.ui_tick(2)
        assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==8,
            "verified post-spin fallback lost the native selection")
    end
end)

test("native spin waits while a library operation blocks navigation",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    f.stats.pending=true
    local painted
    f.arrow(1,1,true,function(page) painted=page.fields._ChildData:get_element(1).fields._SlotID end)
    assert(painted==0,"blocked operation committed native spin")
    f.stats.pending=false
    f.ui_tick(2)
    assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==8)
end)

test("reopening may read page2 while commands remain blocked until the menu is open",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    f.arrow(1,1)
    local rows=f.pages[1].fields._ChildData
    f.ctx.menu_closed=true
    assert(f.read_page_focus(1)==1,"opening initialization fell back to page1")
    assert(f.navigate(1)==nil and f.pages[1].fields._ChildData==rows)
    f.ctx.allowed=false
    assert(f.read_page_focus(1)==99,"read permission escaped offline training")
end)

test("pager input only queues, two safe ticks rebind and mark once without native allocation",function()
    for _,source in ipairs({"arrow","navigate"}) do
        local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
        local before=f.pages[1].fields._ChildData
        local allocations=f.native_work.allocations
        if source=="arrow" then f.arrow(1,1,true) else f.navigate(1,true) end
        assert(f.pages[1].fields._ChildData==before,"inline input callback rebuilt the page")
        assert(not f.native_work.view_updates,"inline ViewUpdate")
        f.ui_tick(1); assert(before:get_element(1).fields._SlotID==0,"rebound before two safe ticks")
        f.ui_tick(1); assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==8)
        f.ui_tick(5); assert(f.native_work.dirty_updates==1,"repeated deferred invalidation")
        assert(not f.native_work.view_updates and f.pages[1].fields._ChildData==before)
        assert(f.native_work.allocations==allocations,"paging allocated native data")
    end
end)

test("pending page is superseded or cancelled by rapid reverse input",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    f.arrow(1,1,true); f.ui_tick(1); f.arrow(1,2,true)
    f.ui_tick(); assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==16)
    f.arrow(1,3,true); f.arrow(1,2,true); f.ui_tick()
    assert(f.native_work.dirty_updates==1,"reverse to committed page must cancel pending move")
end)

test("pending page never survives native context replacement or reset",function()
    for _,change in ipairs({"focus","param","owner","close","exit","release","reset"}) do
        local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
        f.arrow(1,1,true)
        if change=="focus" then f.focus_page(2)
        elseif change=="param" then f.focus_page(1)
        elseif change=="owner" then f.manager.fields._UIFunc=f.obj()
        elseif change=="close" then f.ctx.menu_closed=true
        elseif change=="exit" then f.ctx.allowed=false
        elseif change=="release" then f.session().released=true
        else f.runtime.reset() end
        f.ui_tick(5); assert(not f.native_work.dirty_updates,"stale navigation: "..change)
        f.ctx.menu_closed=false; f.ctx.allowed=true; f.ui_tick(5)
        assert(not f.native_work.dirty_updates,"cancelled request revived: "..change)
    end
end)

test("library dialog or job delays row invalidation until two unblocked ticks",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    f.arrow(1,1,true); f.stats.pending=true; f.ui_tick(5)
    assert(not f.native_work.dirty_updates)
    f.stats.pending=false; f.ui_tick(1); assert(not f.native_work.dirty_updates)
    f.ui_tick(1); assert(f.native_work.dirty_updates==1)
end)

test("deferred dirty flag failure is reported once and never retried",function()
    local f=fixture({fail_dirty=true}); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    f.arrow(1,1,true); f.ui_tick(5)
    assert(f.stats.error and f.stats.error:find("injected dirty flag failure",1,true))
    assert(f.native_work.dirty_writes==1 and not f.native_work.view_updates)
    f.navigate(1,true); f.ui_tick(5); assert(f.native_work.dirty_writes==1)
end)

test("automatic startup bypasses failing per-slot Init for an existing eighty-slot bank",function()
    local f=fixture({native_capacity=80,expire_slot=53,expire_stage="Init"})
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active",f.stats.error or "automatic paging missing")
    assert(f.stats.autoload==1 and f.native_work.duplicates==2)
end)

test("native menu factory avoids the local promotion finalizer model",function()
    local f=fixture({menu_promotion_gc=true})
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active",f.stats.error or "menu promotion lost rows")
end)

-- Locks down the factory selected by the live differential, not native GC behavior.
for _,capacity in ipairs({8,80}) do
    test("recorder baseline uses global factory with native capacity "..capacity,function()
        local f=fixture({native_capacity=capacity})
        f.runtime.install_hooks(); f.tick()
        assert(f.runtime.state()=="active",f.stats.error or "preparation failed")
        assert((f.native_work.recorder_local_creations or 0)==0,"recorder baseline used local factory")
        assert(f.native_work.recorder_global_creations==1,"expected one global recorder baseline")
        local session=f.session()
        assert(session.idle_gdata~=session.gdata,"recorder baseline aliases live state")
        assert(session.idle_gdata:get_reference_count()>0)
    end)
end

test("expanded menu rows gain native array ownership before later row allocations",function()
    -- Models the observed sole-Lua-reference window, not the unknown releasing instruction.
    local f=fixture({menu_single_ref_reclaim=true})
    f.runtime.install_hooks(); f.tick()
    assert((f.native_work.reclaim_checks or 0)>0,"lifetime stress did not run")
    assert(f.runtime.state()=="active",f.stats.error or "menu not mounted")
    assert((f.native_work.invalid_insertions or 0)==0)
end)

-- These faults test diagnostic attribution and refusal, not the native crash cause.
for _,spec in ipairs({
    {event="create",stage="after_create"},
    {event="read:_MessageID",stage="after_read:_MessageID"},
    {event="call:set_MessageID(System.Guid)",stage="after_write:_MessageID"},
}) do
    test("construction diagnosis catches earlier row corruption at "..spec.event,function()
        local injected=false
        local f=fixture({menu_structs=true,construction_fault=function(event,subject,objects,work)
            if injected or work.menu_creations~=5 or event~=spec.event then return end
            for _,row in pairs(objects) do
                if row.kind=="app.training.TrainingMenuData" and row.fields._SlotID==3
                    and row.fields._FuncType==118 then
                    injected=true; row:expire(); row.refs=1688060279
                    return
                end
            end
            error("construction fault target missing")
        end})
        local bank,rows=f.fighter.fields.RecordSlots,f.pages[1].fields._ChildData
        f.runtime.install_hooks(); f.tick()
        assert(injected,"fault did not run")
        local message=f.stats.error or ""
        for _,part in ipairs({"origin=expanded_slot","slot=4","refs=1688060279",
            "stage=construction_slot_5:"..spec.stage}) do
            assert(message:find(part,1,true),"missing boundary "..part..": "..message)
        end
        assert(f.native_work.menu_creations==5,"continued allocating after corruption")
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
        assert((f.native_work.invalid_insertions or 0)==0)
        local allocations,logs=f.native_work.allocations,f.stats.logs
        f.tick(450)
        assert(f.native_work.allocations==allocations and f.stats.logs==logs,"retried failed construction")
    end)
end

for _,spec in ipairs({
    {origin="expanded_slot",slot=1,page=107,window=1},
    {origin="expanded_slot",slot=8,page=108,window=2},
    {origin="native_slot",slot=1,page=107,window=1},
    {origin="native_footer",row=10,page=107,window=1},
    {origin="pager",page=107,window=1},
}) do
    test("expired menu diagnostic identifies "..spec.origin.." on page "..spec.page,function()
        local victim
        local f=fixture({menu_fault_window=spec.window,menu_fault=function(objects,pages)
            local page=pages[spec.page==107 and 1 or 2]
            if spec.origin=="native_slot" then victim=page.fields._ChildData:get_element(spec.slot)
            elseif spec.origin=="native_footer" then victim=page.fields._ChildData:get_element(spec.row)
            else
                for _,value in pairs(objects) do
                    local fields=value.fields
                    local matches=spec.origin=="pager" and fields._FuncType==345 and fields._Type==1
                        or spec.origin=="expanded_slot" and value.kind=="app.training.TrainingMenuData"
                            and fields._SlotID==spec.slot-1
                            and fields._FuncType==(spec.page==107 and 118 or 131)
                    if matches then victim=value; break end
                end
            end
            assert(victim,"fault target missing")
            victim:expire()
        end})
        local bank=f.fighter.fields.RecordSlots
        local rows=f.pages[1].fields._ChildData
        f.runtime.install_hooks(); f.tick()
        local message=f.stats.error or ""
        for _,part in ipairs({"[DEBUG-SF6CC-menu-lifetime]","origin="..spec.origin,
            "page="..spec.page,"stage=after_window_allocation","last=before_window_allocation",
            "address="..victim.id,"refs=0","last_refs="}) do
            assert(message:find(part,1,true),"missing diagnostic "..part..": "..message)
        end
        if spec.slot then assert(message:find("slot="..spec.slot,1,true),message) end
        assert((f.native_work.invalid_insertions or 0)==0)
        assert((f.native_work.expired_type_reads or 0)==0,"dereferenced a known expired menu row")
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
        local allocations,logs=f.native_work.allocations,f.stats.logs
        f.tick(450)
        assert(f.native_work.allocations==allocations and f.stats.logs==logs,"automatic retry after dead row")
    end)
end

test("menu lifetime diagnosis stops at slot assignment before reading expired fields",function()
    local f=fixture({menu_expire_on_assignment=3})
    local bank=f.fighter.fields.RecordSlots
    f.runtime.install_hooks(); f.tick()
    local message=f.stats.error or ""
    for _,part in ipairs({"[DEBUG-SF6CC-menu-lifetime]","origin=expanded_slot","page=107",
        "slot=4","stage=slot assignment:_SlotID","last=after copy:_FuncType","refs=0"}) do
        assert(message:find(part,1,true),message)
    end
    assert(f.fighter.fields.RecordSlots==bank and (f.native_work.invalid_insertions or 0)==0)
    assert((f.native_work.expired_type_reads or 0)==0)
end)

test("automatic readiness requires consecutive stable idle checks and resets across interruptions",function()
    local f=fixture(); f.runtime.install_hooks()
    f.tick(30)
    assert(f.native_work.allocations==0,"allocated before layout stabilized")
    f.ctx.busy=true; f.tick(15)
    f.ctx.busy=false; f.tick(30)
    assert(f.native_work.allocations==0)
    f.stats.pending=true; f.tick(15)
    f.stats.pending=false; f.tick(30)
    assert(f.native_work.allocations==0)
    f.ctx.save_busy=true; f.tick(15)
    f.ctx.save_busy=false; f.tick(30)
    assert(f.native_work.allocations==0)
    f.ctx.menu_closed=false; f.tick(15)
    f.ctx.menu_closed=true; f.tick(30)
    assert(f.native_work.allocations==0)
    f.tick(15)
    assert(f.runtime.state()=="active" and f.stats.autoload==1)
end)

test("automatic paging waits for native layout without allocations and recovers when ready",function()
    local f=fixture()
    local header=f.pages[1].fields._ChildData:get_element(0)
    header.fields._FuncType=345
    f.runtime.install_hooks()
    for i=1,100 do f.tick() end
    assert(f.native_work.allocations==0 and f.native_work.duplicates==0)
    header.fields._FuncType=0
    f.tick()
    assert(f.runtime.state()=="active",f.stats.error or "no automatic recovery")
    assert(f.stats.autoload==1)
end)

test("owned pagination restores automatically while idle without changing recordings or importing",function()
    local f=fixture()
    local rows={f.pages[1].fields._ChildData,f.pages[2].fields._ChildData}
    f.runtime.install_hooks(); f.tick()
    local bank=f.fighter.fields.RecordSlots
    local work=f.native_work.allocations
    f.pages[1].fields._ChildData=rows[1]; f.pages[2].fields._ChildData=rows[2]
    f.ctx.menu_closed=false; f.tick()
    assert(f.pages[1].fields._ChildData==rows[1])
    f.ctx.menu_closed=true; f.ctx.busy=true; f.tick()
    assert(f.pages[1].fields._ChildData==rows[1])
    f.ctx.busy=false; f.tick()
    assert(f.pages[1].fields._ChildData~=rows[1] and f.pages[2].fields._ChildData~=rows[2])
    assert(f.fighter.fields.RecordSlots==bank and f.native_work.allocations==work)
    assert(f.stats.autoload==1 and f.stats.names_reset==1)
    local writes=f.native_work.menu_writes
    for i=1,100 do f.tick() end
    assert(f.native_work.menu_writes==writes and f.native_work.allocations==work,
        "healthy menus must not be rewritten or recreated by automatic checks")
end)

test("manual reload recovers failed per-slot initialization without importing or changing names",function()
    local f=pre_seed_fixture({expire_slot=67,expire_stage="Init"})
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="unloaded" and f.stats.error:find("slot 67",1,true))
    local original=f.fighter.fields.RecordSlots
    f.ctx.menu_closed=false
    assert(f.runtime.request_reload())
    assert(not f.runtime.request_reload())
    f.tick(); assert(f.runtime.state()=="unloaded")
    f.ctx.menu_closed=true; f.tick()
    assert(f.runtime.state()=="active",f.stats.error)
    assert(f.stats.autoload==0 and f.stats.names_reset==0,"manual reload must not import or reset names")
    assert(f.session().array~=original and f.session().array:get_element(79).fields.Frame==0)
    f.runtime.reset(); assert(f.fighter.fields.RecordSlots==original)
end)

test("manual reload restores owned page rows without replacing recordings",function()
    local f=fixture()
    local rows={f.pages[1].fields._ChildData,f.pages[2].fields._ChildData}
    f.runtime.install_hooks(); f.tick()
    local bank=f.fighter.fields.RecordSlots
    bank:get_element(79).fields.Frame=100
    f.pages[1].fields._ChildData=rows[1]; f.pages[2].fields._ChildData=rows[2]
    assert(f.runtime.request_reload()); f.tick()
    assert(f.fighter.fields.RecordSlots==bank and bank:get_element(79).fields.Frame==100)
    assert(f.pages[1].fields._ChildData~=rows[1] and f.pages[2].fields._ChildData~=rows[2])
    assert(f.stats.autoload==1,"menu reload must not auto-import again")
    assert(f.stats.names_reset==1,"menu reload must not reset names again")
end)

test("manual reload refuses foreign menu or bank without partially restoring pages",function()
    for _,fault in ipairs({"menu","bank"}) do
        local f=fixture(); local rows=f.pages[1].fields._ChildData
        f.runtime.install_hooks(); f.tick()
        f.pages[1].fields._ChildData=rows
        if fault=="menu" then f.pages[2].fields._ChildData=f.array({})
        else f.fighter.fields.RecordSlots=f.array({}) end
        local bank=f.fighter.fields.RecordSlots
        assert(f.runtime.request_reload()); f.tick()
        assert(f.pages[1].fields._ChildData==rows and f.fighter.fields.RecordSlots==bank)
        assert(f.stats.logs==1 and f.stats.autoload==1)
        local reads=f.stats.context_reads
        for i=1,100 do assert(not f.runtime.request_reload()) end
        assert(f.stats.context_reads==reads and f.stats.logs==1)
    end
end)

test("manual failure locks further reload attempts instead of accumulating failed native objects",function()
    local f=fixture({native_capacity=80})
    f.original[79].fields.InputData=nil
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.request_reload()); f.tick()
    local work=f.native_work.allocations
    local copies,logs=f.native_work.duplicates,f.stats.logs
    for i=1,100 do assert(not f.runtime.request_reload()); f.tick() end
    assert(f.native_work.allocations==work and f.stats.autoload==0)
    assert(f.native_work.duplicates==copies and f.stats.logs==logs)
    f.ctx.allowed=false; f.tick()
    f.ctx.allowed=true; f.tick()
    assert(not f.runtime.request_reload() and f.native_work.allocations==work)
end)

test("stale recording headers after script toggle are rejected before native allocation or copying",function()
    local f=fixture({native_capacity=80})
    f.pages[1].fields._ChildData:get_element(0).fields._FuncType=345
    local bank=f.fighter.fields.RecordSlots
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.request_reload()); f.tick()
    assert(f.runtime.state()=="unloaded" and f.stats.error:find("recording header layout changed",1,true))
    assert(f.native_work.allocations==0 and f.native_work.duplicates==0,"stale menu reached the native allocator")
    assert(f.call("SaveSaveData",f.manager.id,f.data.id)==f.data.id)
    for i=1,100 do assert(not f.runtime.request_reload()); f.tick() end
    assert(f.fighter.fields.RecordSlots==bank and f.native_work.allocations==0)
    for i=1,100 do f.tick() end
    assert(f.stats.logs==1,"blocked clicks must not spam native failure logs")
end)

test("manual reload refuses busy state and cancels on environment change",function()
    local f=fixture(); f.runtime.install_hooks()
    f.ctx.busy=true; assert(not f.runtime.request_reload())
    f.ctx.busy=false; assert(f.runtime.request_reload())
    f.ctx.allowed=false; f.tick()
    assert(f.runtime.state()=="unloaded" and f.stats.autoload==0)
    assert(not f.runtime.request_reload())
    f.ctx.allowed=true; f.runtime.reset(); assert(not f.runtime.request_reload())
end)

test("existing native eighty-slot bank gets ten pages without truncation or live-data reuse",function()
    local f=fixture({native_capacity=80})
    local original=f.fighter.fields.RecordSlots
    local rows=f.pages[1].fields._ChildData
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active",f.stats.error or "pagination missing for existing eighty-slot bank")
    local s=f.session()
    assert(s.array~=original and s.original==original and s.original_copy:get_size()==80)
    assert(f.stats.autoload==1 and f.pages[1].fields._ChildData~=rows)
    for i=0,79 do
        local slot=s.array:get_element(i)
        local source=original:get_element(i)
        assert(slot~=source and slot.fields.Frame==i+1 and slot.fields.IsValid)
        assert(slot.fields.InputData~=source.fields.InputData)
        assert(slot.fields.InputData.fields.Num==i+1)
        assert(slot.fields.InputData.fields.buff~=source.fields.InputData.fields.buff)
        assert(slot.fields.InputData.fields.buff.items[i+1]==i+1)
    end
    f.ctx.menu_closed=false
    assert(f.arrow(1,9)==9)
    assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==72)
    assert(f.arrow(2,9)==9)
    assert(f.pages[2].fields._ChildData:get_element(8).fields._SlotID==79)
    s.array:get_element(79).fields.Frame=200
    local saved=f.call("SaveSaveData",f.manager.id,f.data.id)
    assert(saved==s.baseline.id and s.original_copy:get_element(79).fields.Frame==80)
    f.ctx.menu_closed=true; f.runtime.reset()
    assert(f.fighter.fields.RecordSlots==original and original:get_size()==80)
    assert(original:get_element(79).fields.Frame==80 and f.pages[1].fields._ChildData==rows)
end)

test("unsupported native counts stay untouched and are not retried",function()
    for _,count in ipairs({0,9,79,81}) do
        local f=fixture({native_capacity=count})
        local bank,rows=f.fighter.fields.RecordSlots,f.pages[1].fields._ChildData
        f.runtime.install_hooks(); f.tick(); f.tick()
        assert(f.runtime.state()=="unloaded" and f.stats.autoload==0 and f.stats.logs==1)
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
        assert(f.stats.error:find("unsupported original recording count: "..count,1,true))
    end
end)

test("preexisting eighty-slot banks reject missing inputs, invalid lengths and source aliases",function()
    for _,fault in ipairs({"input","length","frame","slot_alias","input_alias","buffer_alias"}) do
        local f=fixture({native_capacity=80})
        local bank,rows=f.fighter.fields.RecordSlots,f.pages[1].fields._ChildData
        local slot,first=f.original[80],f.original[1]
        if fault=="input" then slot.fields.InputData=nil
        elseif fault=="length" then slot.fields.InputData.fields.Num=3601
        elseif fault=="frame" then slot.fields.Frame=-1
        elseif fault=="slot_alias" then bank.items[80]=first
        elseif fault=="input_alias" then slot.fields.InputData=first.fields.InputData
        else slot.fields.InputData.fields.buff=first.fields.InputData.fields.buff end
        f.runtime.install_hooks(); f.tick(); f.tick()
        assert(f.runtime.state()=="unloaded" and f.stats.autoload==0 and f.stats.logs==1,fault)
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows,fault)
    end
end)

test("all-empty preexisting eighty-slot bank retains its original buffers across reset",function()
    local f=fixture({native_capacity=80})
    local bank=f.fighter.fields.RecordSlots
    for _,slot in ipairs(f.original) do
        slot.fields.Frame=0; slot.fields.IsValid=false; slot.fields.IsActive=false
        slot.fields.InputData.fields.Num=0; slot.fields.InputData.fields.buff=nil
    end
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active",f.stats.error)
    for i=0,79 do
        local slot=f.session().array:get_element(i)
        assert(slot.fields.Frame==0 and not slot.fields.IsValid)
        assert(slot.fields.InputData.fields.buff:get_size()==3600)
        assert(f.original[i+1].fields.InputData.fields.buff==nil)
    end
    f.runtime.reset()
    assert(f.fighter.fields.RecordSlots==bank and bank:get_size()==80)
end)

test("private native bank retains slots across the observed Init reference loss",function()
    for _,index in ipairs({1,23,57,80}) do
        local f=pre_seed_fixture({init_ref_loss_at=index})
        f.runtime.install_hooks(); f.tick()
        assert(f.runtime.state()=="active",f.stats.error or "paging was not mounted")
        local slot=f.fighter.fields.RecordSlots:get_element(index-1)
        assert(slot:get_reference_count()>0 and slot:get_field("InputData"))
        assert(f.fighter.fields.RecordSlots:get_size()==80 and f.stats.autoload==1)
        assert(f.original[1].fields.Frame==1 and f.original[8].fields.Frame==8)
        f.ctx.allowed=false; f.tick()
        assert(f.runtime.state()=="unloaded" and f.fighter.fields.RecordSlots:get_size()==8)
    end
end)

test("upstream promotion model uses global factory (not a live-game reproducer)",function()
    for _,index in ipairs({1,23,52,80}) do
        local f=pre_seed_fixture({promotion_gc_at=index})
        f.runtime.install_hooks(); f.tick()
        assert(f.runtime.state()=="active",f.stats.error or "pagination missing after native slot lifetime loss")
        assert(f.fighter.fields.RecordSlots:get_size()==80 and f.stats.autoload==1)
        assert(f.pages[1].fields._ChildData:get_element(0).fields._FuncType==345)
        for i=0,79 do
            local slot=f.fighter.fields.RecordSlots:get_element(i)
            assert(slot:get_reference_count()>0 and slot:get_field("InputData"),"dead native slot")
        end
    end
end)

test("failure-only lifetime boundaries distinguish creation retention init and copy",function()
    for _,spec in ipairs({{"create","created"},{"retain","retained"},{"Init","initialized"},{"DeepCopy","copied"}}) do
        local f=pre_seed_fixture({expire_slot=57,expire_stage=spec[1]})
        local bank=f.fighter.fields.RecordSlots; local rows=f.pages[1].fields._ChildData
        f.runtime.install_hooks(); f.tick()
        assert(f.runtime.state()=="unloaded" and f.stats.autoload==0)
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
        local message=assert(f.stats.error)
        assert(message:find("[SlotLifetime]",1,true))
        local first_dead=message:match("([%w_]+){address=%d+,refs=0,type=unavailable}")
        assert(first_dead==spec[2],message)
        assert(message:find("slot 57 /",1,true),"wrong allocation boundary")
        f.tick(); assert(f.stats.logs==1,"diagnostic must not retry allocations")
    end
end)

test("late empty input reports raw field and native call identity without mounting or retrying",function()
    for _,raw in ipairs({0,123456}) do
        local f=pre_seed_fixture({missing_input_at=34,raw_input=raw})
        local bank=f.fighter.fields.RecordSlots; local rows=f.pages[1].fields._ChildData
        f.runtime.install_hooks(); f.tick()
        assert(f.runtime.state()=="unloaded" and f.stats.autoload==0)
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
        assert(f.stats.error:find("slot 34 / copy",1,true))
        assert(f.stats.error:find("target.raw_input="..raw,1,true), "failure must distinguish null storage from a failed Lua field read")
        assert(f.stats.error:find("init_function=0x1000",1,true))
        assert(f.stats.error:find("target.refs=",1,true) and f.stats.error:find("source.raw_input=",1,true))
        f.tick(); assert(f.stats.logs==1)
    end
end)

test("failed expansion preserves stage and stack without touching original eight slots",function()
    local f=pre_seed_fixture({copy_error=true})
    local original=f.fighter.fields.RecordSlots
    local rows=f.pages[1].fields._ChildData
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="unloaded")
    assert(f.fighter.fields.RecordSlots==original and f.pages[1].fields._ChildData==rows)
    assert(f.stats.autoload==0)
    assert(f.stats.error and f.stats.error:find("slot 1 / copy",1,true), "missing failing stage")
    assert(f.stats.error:find("stack traceback:",1,true), "missing native failure callsite")
    f.tick(); assert(f.stats.logs==1,"must not retry failed native mutation")
end)

test("native menu structs never use boxed-size generic field assignment",function()
    local f=fixture({menu_structs=true}); f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active","native menu struct copy prevented expansion")
    f.ctx.menu_closed=false; f.thread(99); assert(f.arrow(1,1)==1)
    local row=f.pages[1].fields._ChildData:get_element(1)
    for _,key in ipairs({"_MessageID","_SubMessageID","_GuideMessage","_GuideMessageID","_EndWordsGuid","_LimitValue"}) do
        assert(row.fields[key].key==key,"native property setter lost "..key)
    end
end)

test("inline GUID cannot alias eighty recording inputs or mutate original recordings",function()
    local f=fixture({guid_overcopy=true}); f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active")
    local inputs,buffers={},{}
    for _,slot in ipairs(f.original) do
        inputs[slot.fields.InputData]=true; buffers[slot.fields.InputData.fields.buff]=true
    end
    for i=0,79 do
        local slot=f.fighter.fields.RecordSlots:get_element(i)
        local input=slot.fields.InputData
        assert(not inputs[input],"slot "..(i+1).." shares InputData")
        assert(not buffers[input.fields.buff],"slot "..(i+1).." shares input buffer")
        inputs[input]=true; buffers[input.fields.buff]=true
    end
end)

test("reject any late slot input or buffer alias before mounting or autoloading",function()
    for _,kind in ipairs({"slot","input","buffer"}) do
        for _,external in ipairs({false,true}) do
            local options={alias=kind}; local f=fixture(options)
            if external then options.alias_original=f.original[3] end
            local bank=f.fighter.fields.RecordSlots; local rows=f.pages[1].fields._ChildData
            f.runtime.install_hooks(); f.tick()
            assert(f.runtime.state()=="unloaded",kind.." alias was mounted")
            assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
            assert(f.stats.autoload==0)
        end
    end
end)

test("empty originals get private buffers without touching originals or save snapshot",function()
    local f=fixture()
    for _,index in ipairs({1,6,8}) do
        local slot=f.original[index]
        slot.fields.Frame=0; slot.fields.IsValid=false; slot.fields.Title="empty-native-title"
        slot.fields.InputData.fields.Num=0
        slot.fields.InputData.fields.buff=index==6 and nil or f.array()
    end
    f.runtime.install_hooks(); f.tick(); assert(f.runtime.state()=="active")
    local bank=f.fighter.fields.RecordSlots
    for _,index in ipairs({1,6,8}) do
        local slot=bank:get_element(index-1)
        assert(slot.fields.InputData.fields.buff:get_size()==3600 and slot.fields.Frame==0)
        for _,source in ipairs({f.original[index],f.session().original_copy:get_element(index-1)}) do
            local buffer=source.fields.InputData.fields.buff
            assert(not buffer or buffer:get_size()==0,"empty source modified by allocation")
        end
    end
    for i=8,79 do
        assert(bank:get_element(i).fields.Title==f.original[2].fields.Title,
            "expanded frames inherited empty native title")
    end
end)

test("all-empty native bank remains empty and independent across eighty slots",function()
    local f=fixture()
    for _,slot in ipairs(f.original) do
        slot.fields.Frame=0; slot.fields.IsValid=false; slot.fields.InputData.fields.Num=0
        slot.fields.InputData.fields.buff=f.array()
    end
    f.runtime.install_hooks(); f.tick(); assert(f.runtime.state()=="active")
    local seen={}
    for i=0,79 do
        local slot=f.fighter.fields.RecordSlots:get_element(i)
        local buff=slot.fields.InputData.fields.buff
        assert(not seen[buff] and buff:get_size()==3600 and slot.fields.Frame==0)
        assert(slot.fields.IsValid==false); seen[buff]=true
    end
end)

test("actual session mounts eighty once with ten pages; autoload once",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.tick()
    assert(f.runtime.state()=="active" and f.fighter.fields.RecordSlots:get_size()==80)
    for _,page in ipairs(f.pages) do assert(page.fields._ChildData:get_size()==12) end
    assert(f.stats.autoload==1)
    local bank=f.fighter.fields.RecordSlots
    for i=8,79 do
        assert(bank:get_element(i).fields.InputData.fields.buff:get_size()==3600)
        assert(bank:get_element(i).fields.IsValid==false)
        assert(bank:get_element(i).fields.InputData.fields.Num==0)
    end
    for _,page in ipairs(f.pages) do
        assert(page.fields._ChildData:get_element(0).fields._ChildData:get_size()==10)
    end
end)
test("unrelated mode, open menu and recorder busy cannot mount",function()
    for _,change in ipairs({"mode","menu","busy"}) do
        local f=fixture(); f.runtime.install_hooks()
        if change=="mode" then f.ctx.allowed=false elseif change=="menu" then f.ctx.menu_closed=false
        else f.ctx.busy=true end
        f.tick(); assert(f.fighter.fields.RecordSlots:get_size()==8 and f.stats.autoload==0)
    end
end)

test("actual runtime hook switches visible menu without changing recordings",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    local bank=f.fighter.fields.RecordSlots
    local skip,result=f.navigate(1)
    assert(skip=="skip" and result==0 and f.pages[1].fields._ChildData:get_size()==12)
    assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==8)
    assert(f.pages[2].fields._ChildData:get_size()==12)
    assert(f.fighter.fields.RecordSlots==bank and bank:get_size()==80)
    f.navigate(1); assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==0)
    f.navigate(2); assert(f.pages[2].fields._ChildData:get_element(1).fields._SlotID==8)
    f.runtime.reset(); assert(f.pages[2].fields._ChildData:get_size()==12)
    assert(f.fighter.fields.RecordSlots:get_size()==8)
end)

test("owned native UI navigation may use a different thread than bank mounting",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    local bank=f.fighter.fields.RecordSlots
    f.thread(99)
    local skip,result=f.navigate(1)
    assert(skip=="skip" and result==0 and f.pages[1].fields._ChildData:get_element(1).fields._SlotID==8,
        "native UI thread was denied page navigation")
    assert(f.fighter.fields.RecordSlots==bank and f.runtime.state()=="active")
    f.thread(7); f.runtime.reset()
    assert(f.fighter.fields.RecordSlots:get_size()==8)
end)

test("actual native arrow path without Function replaces slot rows on the UI thread",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false; f.thread(99)
    local bank=f.fighter.fields.RecordSlots
    assert(f.arrow(1,1)==1)
    assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==8)
    assert(f.arrow(1,0)==0)
    assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==0)
    assert(f.arrow(2,1)==1)
    assert(f.pages[2].fields._ChildData:get_element(1).fields._SlotID==8)
    assert(f.fighter.fields.RecordSlots==bank)
    f.thread(7); f.runtime.reset()
    assert(f.fighter.fields.RecordSlots:get_size()==8)
end)

test("expanded slots inherit native frame labels without copying recordings",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    local bank=f.fighter.fields.RecordSlots
    for i=8,79 do
        local slot=bank:get_element(i)
        assert(slot.fields.Title==bank:get_element(0).fields.Title,
            "expanded slot has no native localized frame-count format")
        assert(slot.fields.Frame==0 and slot.fields.IsValid==false)
        assert(slot.fields.InputData.fields.Num==0)
        assert(slot.fields.InputData.fields.buff:get_size()==3600)
        assert(slot.fields.InputData~=bank:get_element(i%8).fields.InputData)
    end
end)

test("ten pages expose eighty unique native slots in both record and play",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false; f.thread(99)
    for p,page in ipairs(f.pages) do
        local footer=page.fields._ChildData:get_element(11)
        for index=1,9 do
            assert(f.arrow(p,index)==index)
            local rows=page.fields._ChildData
            assert(rows:get_size()==12 and rows:get_element(11)==footer)
            for i=1,8 do assert(rows:get_element(i).fields._SlotID==index*8+i-1) end
        end
        assert(f.arrow(p,0)==0)
    end
    f.thread(7); f.runtime.reset()
    assert(f.fighter.fields.RecordSlots:get_size()==8)
end)

test("UI permission expires on error and never grants bank retirement permission",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.ctx.menu_closed=false
    local s=f.session(); local parent=f.pages[1]
    local row=parent.fields._ChildData:get_element(0)
    local ui=f.manager.fields._UIFunc
    assert(not pcall(s.menu.navigate,row,parent),"unscoped paging was permitted")
    assert(not pcall(s.with_menu_navigation,f.obj(),row,parent,function() error("must not run") end))
    f.thread(99)
    assert(not pcall(s.with_menu_navigation,ui,row,parent,function()
        assert(not pcall(s.retire),"UI thread retired recordings")
        assert(not s.can_close())
        assert(s.menu.navigate(row,parent,1))
        error("injected refresh failure")
    end))
    assert(not pcall(s.menu.navigate,row,parent),"failed callback leaked UI permission")
    assert(s.with_menu_navigation(ui,row,parent,function() return s.menu.navigate(row,parent,0) end))
    f.thread(7); assert(s.retire())
end)
test("exit discards edited clone, restores both native rows and never saves JSON",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    f.fighter.fields.RecordSlots:get_element(0).fields.Frame=900
    f.ctx.allowed=false; f.tick()
    assert(f.fighter.fields.RecordSlots:get_size()==8 and f.fighter.fields.RecordSlots:get_element(0).fields.Frame==1)
    assert(f.pages[1].fields._ChildData:get_size()==12 and f.runtime.state()=="unloaded")
    f.ctx.allowed=true; f.tick(); assert(f.runtime.state()=="active" and f.stats.autoload==2)
end)
test("worker save returns independent original-eight baseline without allocation",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.thread(22)
    local result=f.call("SaveSaveData",f.manager.id,f.data.id)
    assert(result~=f.data.id)
    assert(f.fighter.fields.RecordSlots:get_size()==80)
    assert(f.call("SaveSaveData",99999,88888)==88888)
    f.thread(7); f.ctx.allowed=false; f.tick(); assert(f.fighter.fields.RecordSlots:get_size()==8)
end)
for _,cleanup in ipairs({"retire","discard"}) do
test("shared borrowed wrappers survive menu and session "..cleanup,function()
    local f
    f=fixture(cleanup=="discard" and {menu_fault=function() f.ctx.save_busy=true end} or nil)
    local borrowed={f.manager,f.data,f.fighter,f.record,f.record.fields._gData,
        f.fighter.fields.RecordSlots}
    for _,page in ipairs(f.pages) do
        borrowed[#borrowed+1]=page
        borrowed[#borrowed+1]=page.fields._ChildData
    end
    -- Sdk.cpp deduplicates add_ref for the same Lua wrapper. Explicit release
    -- consumes that shared reference, not a separate module-owned reference.
    for _,value in ipairs(borrowed) do
        value.refs=2
        value.lua_owned=true
        value.manual_releases=0
        value.add_ref=function(self) assert(self.lua_owned) end
        value.release=function(self)
            self.manual_releases=self.manual_releases+1
            if self.lua_owned then self.refs=self.refs-1; self.lua_owned=false end
        end
    end
    f.runtime.install_hooks(); f.tick()
    local old=f.session()
    if cleanup=="retire" then
        assert(f.runtime.state()=="active",f.stats.error)
        f.call("Release",f.manager.id,0,function()
            f.manager.fields._tData=nil
            -- Only model the engine releasing its direct TrainingData reference.
            -- The fixture still holds the Lua wrapper, as another consumer can.
            f.data.refs=f.data.refs-1
        end)
        f.ctx.allowed=false; f.tick()
        assert(f.runtime.state()=="unloaded",f.stats.error)
    end
    assert(old and old.phase=="closed",f.stats.error)
    for _,value in ipairs(borrowed) do
        assert(value.manual_releases==0 and value.lua_owned and value:get_type_definition(),
            "cleanup released a borrowed Lua wrapper still referenced by another consumer")
    end
end)
end

test("release hook only notifies; game thread restores after native release",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.thread(22)
    f.call("Release",f.manager.id,0)
    assert(f.fighter.fields.RecordSlots:get_size()==80)
    f.thread(7); f.ctx.allowed=false; f.tick(); assert(f.fighter.fields.RecordSlots:get_size()==8)
end)

test("native Release replacing the bank restores owned menus and allows a fresh training session",function()
    local f=fixture(); local native_rows=f.pages[1].fields._ChildData
    f.runtime.install_hooks(); f.tick()
    f.ctx.menu_closed=false; assert(f.arrow(1,9)==9)
    f.ctx.menu_closed=true
    local old=f.session()
    f.thread(22)
    f.call("Release",f.manager.id,0,function()
        f.fighter.fields.RecordSlots=f.array(f.original)
    end)
    local new_bank=f.fighter.fields.RecordSlots
    f.thread(7); f.ctx.allowed=false; f.tick()
    assert(f.fighter.fields.RecordSlots==new_bank,"retirement overwrote the game's replacement bank")
    assert(f.pages[1].fields._ChildData==native_rows,"released session left its pager behind")
    assert(old.phase=="closed" and f.runtime.state()=="unloaded",f.stats.error)
    f.ctx.allowed=true; f.tick()
    assert(f.runtime.state()=="active" and f.session()~=old and f.stats.autoload==2)
    f.ctx.menu_closed=false
    local pager=f.pages[1].fields._ChildData:get_element(0)
    assert(f.session().menu.pager_info(pager).index==0)
    assert(f.arrow(1,9)==9)
    assert(not f.stats.logs,"normal released-bank replacement must not log errors")
end)

test("failed retirement reports once rather than repeating native work every tick",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    f.fighter.fields.RecordSlots=f.array({})
    f.ctx.allowed=false
    for i=1,100 do f.tick() end
    assert(f.stats.logs==1,"retirement kept logging the same error")
end)

test("initial recorder busy state waits without allocation and recovers in the same context",function()
    for _,field in ipairs({"ReqType","State"}) do
        local f=fixture(); local rows=f.pages[1].fields._ChildData
        local bank=f.fighter.fields.RecordSlots
        f.record.fields._gData.fields[field]=1
        f.runtime.install_hooks(); f.tick(450)
        assert(f.native_work.allocations==0 and f.native_work.duplicates==0,"busy preflight allocated native data")
        assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
        assert(not f.stats.logs,"transient busy state became an expansion error")
        f.record.fields._gData.fields[field]=0; f.tick()
        assert(f.runtime.state()=="active",f.stats.error or "transient busy state latched forever")
        assert(f.fighter.fields.RecordSlots:get_size()==80 and not f.stats.logs)
    end
end)

test("temporary native recorder request defers automatic recovery without locking it",function()
    local f=fixture(); local rows=f.pages[1].fields._ChildData
    f.runtime.install_hooks(); f.tick()
    f.pages[1].fields._ChildData=rows
    f.record.fields._gData.fields.ReqType=1
    for i=1,10 do f.tick() end
    assert(f.pages[1].fields._ChildData==rows and not f.stats.logs)
    f.record.fields._gData.fields.ReqType=0; f.tick()
    assert(f.pages[1].fields._ChildData~=rows and not f.stats.logs)
end)

test("released session clears prior recovery block without overwriting replacement bank",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    f.fighter.fields.RecordSlots=f.array(f.original)
    f.tick(); assert(f.stats.logs==1)
    local bank=f.fighter.fields.RecordSlots
    f.call("Release",f.manager.id,0)
    f.ctx.allowed=false; f.tick()
    assert(f.fighter.fields.RecordSlots==bank)
    f.ctx.allowed=true; f.tick()
    assert(f.runtime.state()=="active" and f.stats.autoload==2 and f.stats.logs==1)
end)
test("safe update shutdown in idle restores native rows and recorder selection",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    f.record.fields._gData.fields.SlotID=8
    f.runtime.reset()
    assert(f.fighter.fields.RecordSlots:get_size()==8 and f.record.fields._gData.fields.SlotID==0)
    f.tick(); assert(f.fighter.fields.RecordSlots:get_size()==8)
end)
test("script Reset outside safe update abandons jobs without native cancellation or menu writes",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    local bank=f.fighter.fields.RecordSlots
    local rows=f.pages[1].fields._ChildData
    local writes=f.native_work.menu_writes
    local cancelled=f.stats.cancel
    f.ui_phase(false); f.runtime.reset(); f.ui_tick(5)
    assert(f.stats.cancel==cancelled,"script Reset ran native task cancellation")
    assert(f.stats.abandoned==1 and f.runtime.state()=="stopped")
    assert(f.pages[1].fields._ChildData==rows and f.native_work.menu_writes==writes)
    assert(f.fighter.fields.RecordSlots==bank and f.stats.error)
end)

test("foreign bank refusal cannot restore only the menu and leave eighty recordings",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    local s=f.session()
    local record_rows=f.pages[1].fields._ChildData
    local play_rows=f.pages[2].fields._ChildData
    local other={}
    for i=0,79 do other[#other+1]=s.array:get_element(i) end
    local replacement=f.array(other)
    f.fighter.fields.RecordSlots=replacement
    f.runtime.reset()
    assert(f.pages[1].fields._ChildData==record_rows and f.pages[2].fields._ChildData==play_rows,
        "reset restored eight-row UI before rejecting an unowned eighty-slot bank")
    assert(f.fighter.fields.RecordSlots==replacement,"foreign recordings must not be overwritten")
    assert(s.phase=="active" and s.menu.state()=="attached","failed preflight must not partially retire")
end)

test("fresh runtime refuses an incomplete residual eighty-slot bank without taking ownership or retrying",function()
    local f=fixture()
    local leftover={}; for i=1,80 do leftover[i]=f.obj({Frame=i}) end
    local bank=f.array(leftover); f.fighter.fields.RecordSlots=bank
    local rows=f.pages[1].fields._ChildData
    f.runtime.install_hooks(); f.tick(); f.tick()
    assert(f.runtime.state()=="unloaded" and f.stats.autoload==0)
    assert(f.fighter.fields.RecordSlots==bank and f.pages[1].fields._ChildData==rows)
    assert(f.session()==nil,"leftover banks require recovery, not silent adoption")
end)
test("wrong update thread cannot attach",function()
    local f=fixture(); f.runtime.install_hooks(); f.runtime.tick(); f.thread(22)
    assert(not pcall(f.tick)); assert(f.fighter.fields.RecordSlots:get_size()==8)
end)
test("save snapshots retained until matching controller, object and successful completion",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    local result=f.call("SaveSaveData",f.manager.id,f.data.id)
    local snapshot=assert(f.objects[result]); local refs=snapshot.refs
    f.ctx.allowed=false; f.tick(); assert(snapshot.refs==refs)
    local controller=f.obj({saveKey="SYSTEM_SAVE_DATA",saveDataIns=f.obj({List=f.array({snapshot})})})
    f.call("FinishSave",controller,1); f.tick(); assert(snapshot.refs==refs)
    controller.fields.saveKey="TRAINING_SAVE_DATA"
    controller.fields.saveDataIns.fields.List=f.array({f.data})
    f.call("FinishSave",controller,1); f.tick(); assert(snapshot.refs==refs)
    controller.fields.saveDataIns.fields.List=f.array({snapshot})
    f.call("FinishSave",controller,0); f.tick(); assert(snapshot.refs==refs)
    f.call("FinishSave",controller,1); f.tick(); assert(snapshot.refs==refs-1)
end)
test("older finish callback cannot release a later save generation",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    local result=f.call("SaveSaveData",f.manager.id,f.data.id)
    local snapshot=f.objects[result]; local refs=snapshot.refs
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA",saveDataIns=f.obj({List=f.array({snapshot})})})
    f.call("FinishSave",controller,1,function() f.call("SaveSaveData",f.manager.id,f.data.id) end)
    f.ctx.allowed=false; f.tick(); assert(snapshot.refs==refs)
    f.call("FinishSave",controller,1); f.tick(); assert(snapshot.refs==refs-1)
end)
test("bounded save diagnosis distinguishes missing data and matched completion without native writes",function()
    local events={}
    local f=fixture({trace=function(event,values) events[#events+1]={event=event,values=values} end})
    f.runtime.install_hooks(); f.tick()
    local snapshot=f.objects[f.call("SaveSaveData",f.manager.id,f.data.id)]
    local allocations=f.native_work.allocations
    local writes=f.native_work.menu_writes
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA"})
    f.call("FinishSave",controller,1)
    assert(events[3].event=="finish_pre" and events[3].values.detail.reason=="no_saved_data")
    assert(f.session().issued==1 and f.session().completed==0)
    controller.fields.saveDataIns=f.obj({List=f.array({snapshot})})
    f.call("FinishSave",controller,1)
    assert(events[5].values.detail.matches==1 and f.session().completed==1)
    assert(f.native_work.allocations==allocations and f.native_work.menu_writes==writes)
    local function scalar(value)
        if type(value)=="table" then
            assert(not value.get_address and not value.fields,"trace retained native wrapper")
            for _,v in pairs(value) do scalar(v) end
        else assert(type(value)~="function" and type(value)~="userdata") end
    end
    scalar(events)
    for _=1,100 do f.call("FinishSave",controller,1) end
    assert(#events==48,"save diagnosis exceeded its bound")
end)

test("failed save diagnostic callback cannot block save substitution or completion",function()
    local f=fixture({trace=function() error("trace failure") end})
    f.runtime.install_hooks(); f.tick()
    local snapshot=f.objects[f.call("SaveSaveData",f.manager.id,f.data.id)]
    assert(snapshot==f.session().baseline and f.session().readers==0)
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA",saveDataIns=f.obj({List=f.array({snapshot})})})
    f.call("FinishSave",controller,1)
    assert(f.session().completed==1 and not f.stats.error)
end)

test("real capture mismatch reports original versus snapshot identity without releasing the session",function()
    local events={}
    local f=fixture({save_success=2,trace=function(event,values) events[event]=values end})
    f.runtime.install_hooks(); f.tick()
    local entry=f.session()
    local snapshot=f.objects[f.call("SaveSaveData",f.manager.id,f.data.id)]
    assert(events.save_post.detail.input_address==f.data.id)
    assert(events.save_post.detail.output_address==snapshot.id)
    assert(events.save_post.entries[1].baseline_address==snapshot.id)
    local copy=f.obj(); copy.kind="app.training.TrainingData"
    copy.fields.RecordSetting=snapshot.fields.RecordSetting
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA",saveDataIns=f.obj({List=f.array({copy})})})
    f.call("FinishSave",controller,2)
    assert(events.finish_pre.detail.saved0_address==copy.id)
    assert(events.finish_pre.detail.saved0_type=="app.training.TrainingData")
    assert(events.finish_pre.detail.saved0_fighter28_capacity==8)
    assert(events.finish_pre.detail.matches==0)
    f.call("Release",f.manager.id,0); f.ctx.allowed=false; f.tick()
    assert(entry.phase=="retired" and entry.issued==1 and entry.completed==0,
        "observation must not turn a distinct storage object into an unsafe release permit")
end)

test("failed optional saved-object detail read cannot affect a valid completion",function()
    local events={}
    local f=fixture({trace=function(event,values) events[event]=values end})
    f.runtime.install_hooks(); f.tick()
    local snapshot=f.objects[f.call("SaveSaveData",f.manager.id,f.data.id)]
    snapshot.get_type_definition=function() error("diagnostic read failed") end
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA",saveDataIns=f.obj({List=f.array({snapshot})})})
    f.call("FinishSave",controller,1)
    assert(f.session().completed==1 and not f.stats.error)
    assert(events.finish_pre.detail.detail_error,"optional failure was not identified")
end)

local function storage_save(f, controller, during)
    local snapshot,copy
    f.call("StartSaveDirectSlot(System.Int32, System.String)",controller,1,function()
        snapshot=f.objects[f.call("SaveSaveData",f.manager.id,f.data.id)]
        copy=f.obj({RecordSetting=snapshot.fields.RecordSetting})
        copy.kind="app.training.TrainingData"
        controller.fields.saveDataIns=f.obj({List=f.array({copy})})
        if during then during() end
    end)
    return snapshot,copy
end

test("captured native save handoff closes retired sessions even when storage holds a different object",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks(); f.tick()
    local entry=f.session()
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA"})
    local snapshot,copy=storage_save(f,controller)
    assert(snapshot~=copy and snapshot~=f.data)
    f.call("FinishSave",controller,2,function() controller.fields.saveDataIns=nil end)
    assert(entry.completed==1,"successful correlated storage copy was not acknowledged")
    f.call("Release",f.manager.id,0); f.ctx.allowed=false; f.tick()
    assert(entry.phase=="closed","successful save left the old session occupying the retention cap")
end)

test("six real-shaped save and reentry cycles do not exhaust the four retained sessions",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks()
    for _=1,6 do
        f.ctx.allowed=true; f.tick()
        assert(f.runtime.state()=="active",f.stats.error)
        local entry=f.session()
        local controller=f.obj({saveKey="TRAINING_SAVE_DATA"})
        storage_save(f,controller)
        f.call("FinishSave",controller,2)
        f.call("Release",f.manager.id,0); f.ctx.allowed=false; f.tick()
        assert(entry.phase=="closed" and f.runtime.state()=="unloaded")
    end
    assert(f.stats.autoload==6 and not f.stats.error)
end)

test("newer save finishing before older save cannot release outstanding readers",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks(); f.tick()
    local a=f.obj({saveKey="TRAINING_SAVE_DATA"})
    local b=f.obj({saveKey="TRAINING_SAVE_DATA"})
    storage_save(f,a,function() storage_save(f,b) end)
    local entry=f.session()
    f.call("FinishSave",b,2)
    assert(entry.completed==1 and entry.issued==2)
    f.ctx.allowed=false; f.tick(); assert(entry.phase=="retired")
    f.call("FinishSave",b,2); assert(entry.completed==1,"duplicate completion counted twice")
    f.call("FinishSave",a,2); f.tick(); assert(entry.phase=="closed")
end)

test("storage handoff requires controller container contents and success to match",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks(); f.tick()
    local a=f.obj({saveKey="TRAINING_SAVE_DATA"})
    storage_save(f,a)
    local saved=a.fields.saveDataIns
    local list=saved.fields.List
    local b=f.obj({saveKey="TRAINING_SAVE_DATA",saveDataIns=saved})
    f.call("FinishSave",b,2)
    a.fields.saveDataIns=f.obj({List=list}); f.call("FinishSave",a,2)
    a.fields.saveDataIns=saved; saved.fields.List=f.array({f.data}); f.call("FinishSave",a,2)
    saved.fields.List=list; f.call("FinishSave",a,0)
    assert(f.session().completed==0)
    f.call("FinishSave",a,2); assert(f.session().completed==1)
end)

test("foreign thread save cannot join the caller's native storage handoff",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks(); f.tick()
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA"})
    storage_save(f,controller,function()
        f.thread(22); f.call("SaveSaveData",f.manager.id,f.data.id); f.thread(7)
    end)
    f.call("FinishSave",controller,2)
    assert(f.session().issued==2 and f.session().completed==1)
    f.ctx.allowed=false; f.tick(); assert(f.session().phase=="retired")
end)

test("failed start does not authorize completion or leak its call scope",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks(); f.tick()
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA"})
    f.call("StartSaveDirectSlot(System.Int32, System.String)",controller,0,function()
        local result=f.call("SaveSaveData",f.manager.id,f.data.id)
        controller.fields.saveDataIns=f.obj({List=f.array({f.objects[result]})})
    end)
    f.call("FinishSave",controller,2); assert(f.session().completed==0)
    -- A subsequent independent handoff can complete only its own ticket.
    storage_save(f,controller); f.call("FinishSave",controller,2)
    assert(f.session().issued==2 and f.session().completed==1)
end)

test("finish captured before a newer start cannot acknowledge the newer save",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks(); f.tick()
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA"})
    storage_save(f,controller)
    f.call("FinishSave",controller,2,function() storage_save(f,controller) end)
    assert(f.session().issued==2 and f.session().completed==1)
    f.ctx.allowed=false; f.tick(); assert(f.session().phase=="retired")
    f.call("FinishSave",controller,2); f.tick(); assert(f.session().phase=="closed")
end)

test("unconfirmed saves remain bounded and never turn an overflow into completion",function()
    local f=fixture({save_success=2}); f.runtime.install_hooks(); f.tick()
    local controller=f.obj({saveKey="TRAINING_SAVE_DATA"})
    for _=1,65 do storage_save(f,controller) end
    local entry=f.session()
    local count=0; for _ in pairs(entry.pending_saves) do count=count+1 end
    assert(count==64 and entry.issued==65)
    f.call("FinishSave",controller,2)
    f.ctx.allowed=false; f.tick()
    assert(entry.completed==0 and entry.phase=="retired")
end)

print(passed .. " native runtime integration tests passed (fake SDK)")
