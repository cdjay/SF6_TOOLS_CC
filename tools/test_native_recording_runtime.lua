package.path = "autorun/?.lua;" .. package.path
local Runtime = require("SF6CCTrainingLibrary/NativeRecordingRuntime")
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
local function fixture(options)
    options = options or {}
    local address, hooks, tls, tid, objects = 100, {}, {}, 7, {}
    local slot_allocations = 0
    local function obj(fields)
        address = address + 1
        local o = { fields = fields or {}, id = address, refs = 1 }
        objects[address] = o
        function o:get_address() return self.id end
        function o:get_field(k)
            -- SDK parse_data/set_data uses boxed Guid size (32), while the
            -- inline Title occupies 16 bytes followed immediately by InputData.
            if k=="Title" and options.guid_overcopy then
                return {guid=self.fields.Title, trailing_input=self.fields.InputData}
            end
            return self.fields[k]
        end
        function o:set_field(k,v)
            if options.menu_structs and type(v)=="table" and v.inline_struct then
                error("unsafe boxed-size inline menu struct copy: "..k)
            end
            if k=="Title" and options.guid_overcopy then
                self.fields.Title=v.guid; self.fields.InputData=v.trailing_input; return
            end
            self.fields[k] = v
        end
        function o:add_ref()
            assert(not self.expired, "cannot retain an invalid native object")
            if self.local_object then
                -- REFramework #1448/#1504: promotion can leave a second Lua
                -- wrapper whose finalizer releases the promoted native ref.
                self.local_object = false; self.refs = 1
                self.orphan_finalizer = true
            elseif not self.init_ref_loss then
                self.refs = self.refs + 1
            end
            if self.expire_stage == "retain" then self:expire() end
        end
        function o:expire() self.expired=true; self.refs=0; self.kind=nil; self.fields={} end
        function o:release() self.refs = self.refs - 1; assert(self.refs >= 0) end
        function o:get_reference_count() return self.refs end
        function o:get_type_definition()
            if self.refs == 0 then return nil end
            return {
            get_full_name=function() return self.kind end,
            get_field=function(_,key) assert(key=="InputData"); return {get_offset_from_base=function() return 48 end} end,
            get_method=function(_,signature) return {get_function=function() return signature=="Init()" and "0x1000" or "0x2000" end} end,
        } end
        function o:read_qword(offset)
            assert(offset==48)
            if self.missing_input and options.raw_input then return options.raw_input end
            return self.fields.InputData and self.fields.InputData.id or 0
        end
        function o:get_size() return #self.items end
        function o:get_element(i)
            local item=self.items[i+1]
            -- Inject corruption at completed-bank validation, independent of
            -- whether insertion happens before or after native initialization.
            if self.slot_array and i==79 and options.alias and not self.alias_injected
                and item and item.fields.InputData and item.fields.InputData.fields.buff then
                self.alias_injected=true
                local donor=options.alias_original or self.items[9]
                if options.alias=="slot" then self.items[i+1]=donor
                elseif options.alias=="input" then item.fields.InputData=donor.fields.InputData
                elseif options.alias=="buffer" then item.fields.InputData.fields.buff=donor.fields.InputData.fields.buff end
            end
            return self.items[i+1]
        end
        function o:call(name,a,b)
            if name=="Init" and self.init_ref_loss then
                self:release()
                if self.refs==0 then self:expire() end
            end
            if name == self.expire_stage then self:expire() end
            if self.orphan_finalizer then
                self.orphan_finalizer = false; self:release()
                if self.refs == 0 then self.fields = {}; self.kind = nil end
            end
            if self.refs == 0 then return nil end
            local property=name:match("^set_(%w+)%(")
            if options.menu_structs and property then self.fields["_"..property]=a; return end
            if name=="set_MessageID(System.Guid)" then self.fields._MessageID=a; return end
            if name=="set_GuideMessage(System.Guid)" then self.fields._GuideMessage=a; return end
            if name=="ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)" then return true end
            if name == "get_Count" then return #self.items end
            if name == "get_Item" then return self.items[a+1] end
            if name == "GetFighterIndex" then assert(a==28); return 0 end
            if name == "SetValue(System.Object, System.Int32)" then
                assert(not a.expired,"cannot insert an invalid native object")
                local old=self.items[b+1]
                if old~=a then
                    if old then old:release() end
                    a.refs=a.refs+1
                end
                self.items[b+1] = a
                return
            end
            if name == "Init" then
                if self.missing_input then return end
                if self.kind:find("SlotData",1,true) then self.fields = { Frame=0,Weight=1,IsValid=false,
                    IsActive=false,InputData=obj({Num=0}) } end
                return
            end
            if name == "IsRecording" or name == "IsReplayNow" then return false end
            if name == "DeepCopy" then
                if self.missing_input then return end
                if options.copy_error and self.kind and self.kind:find("SlotData",1,true) then
                    error("sol_lua_push: test address is not a managed object")
                end
                for k,v in pairs(a.fields) do self.fields[k] = v end
                if a.fields.InputData then
                    local input=obj({Num=a.fields.InputData.fields.Num})
                    local buff=obj(); buff.items={}
                    for i,v in ipairs(a.fields.InputData.fields.buff and a.fields.InputData.fields.buff.items or {}) do
                        buff.items[i]=v
                    end
                    input.fields.buff=buff; self.fields.InputData=input
                end
                return
            end
            error("unexpected call: " .. name)
        end
        return o
    end
    local function array(items) local a=obj(); a.items=items or {}; return a end
    local original={}
    for i=1,8 do original[i]=obj({Frame=i,Weight=1,IsValid=true,IsActive=true,Title="native-frame-format-"..i,
        InputData=obj({Num=i,buff=array({i})})}) end
    local fighter=obj({FighterID=28,RecordSlots=array(original)})
    local data=obj({RecordSetting=obj({FighterDataList=array({fighter})})})
    local basecall=data.call
    function data:call(name,...)
        if name~="Duplicate" then return basecall(self,name,...) end
        local copies={}
        for i=1,8 do copies[i]=obj(); copies[i]:call("DeepCopy",original[i]) end
        return obj({RecordSetting=obj({FighterDataList=array({obj({FighterID=28,RecordSlots=array(copies)})})})})
    end
    local pages={}
    for _, spec in ipairs({{107,118},{108,131}}) do
        local rows={obj({_FuncType=spec[1]==107 and 0 or 130,_Type=spec[1]==107 and 9 or 0})}
        for i=0,7 do
            local fields={_FuncType=spec[2],_SlotID=i}
            if options.menu_structs then
                for _,key in ipairs({"_MessageID","_SubMessageID","_GuideMessage","_GuideMessageID","_EndWordsGuid","_LimitValue"}) do
                    fields[key]={inline_struct=true,key=key}
                end
            end
            rows[#rows+1]=obj(fields)
        end
        rows[#rows+1]=obj({_FuncType=0,_Type=4})
        rows[#rows+1]=obj({_FuncType=109})
        rows[#rows+1]=obj({_FuncType=113})
        pages[#pages+1]=obj({_FuncType=spec[1],_ChildData=array(rows)})
    end
    local manager=obj({_tData=data,_UIData=obj({_MenuData=array({obj({_FuncType=4,
        _ChildData=array({obj({_FuncType=106,_ChildData=array(pages)})})})})})})
    manager.fields._UIFunc=obj()
    local record=obj({_tData=data,_gData=obj({ReqType=0,State=0,SlotID=0})})
    local ctx={allowed=true,session=manager,data=data,fighter_id=28,busy=false,menu_closed=true,record_func=record}
    local stats={cancel=0,autoload=0}
    local library={cancel=function() stats.cancel=stats.cancel+1 end,has_pending=function() return false end,
        autoload=function(id) assert(id==28); stats.autoload=stats.autoload+1 end}
    local api={PreHookResult={SKIP_ORIGINAL="skip"}}
    function api.find_type_definition(kind)
        if kind=="System.Guid" then
            return {get_field=function() return {get_data=function() return {NewGuid=function()
                address=address+1; local id=address
                return {read_byte=function(_,i) return i==0 and id%255+1 or 0 end}
            end} end} end}
        end
        return {get_method=function(_,name) return name end,
            get_field=function(_,name) assert(name=="Success"); return {get_data=function() return 1 end} end,
            get_fields=function()
                local list={}
                local keys={"_FuncType","_SlotID"}
                if options.menu_structs then
                    for _,key in ipairs({"_MessageID","_SubMessageID","_GuideMessage","_GuideMessageID","_EndWordsGuid","_LimitValue"}) do keys[#keys+1]=key end
                end
                for _,key in ipairs(keys) do list[#list+1]={is_static=function() return false end,
                    get_name=function() return key end} end
                return list
            end}
    end
    local function create_instance(kind, global)
        local value=obj(); value.kind=kind
        if kind=="app.training.TrainingData.TM_RecordSetting.SlotData" then
            slot_allocations=slot_allocations+1
            value.missing_input=slot_allocations==options.missing_input_at
            -- Installed add_ref deduplicates a global object's Lua reference.
            -- Reproduce the observed 1 -> 0 loss across Init, without assuming
            -- which engine/framework operation released it.
            value.init_ref_loss=slot_allocations==options.init_ref_loss_at
            if slot_allocations==options.expire_slot then
                value.expire_stage=options.expire_stage
                if value.expire_stage=="create" then value:expire() end
            end
            if slot_allocations==options.promotion_gc_at and not global then
                value.local_object=true; value.refs=-1
            end
        end
        return value
    end
    function api.create_instance(kind) return create_instance(kind, false) end
    function api.create_instance_global(kind) return create_instance(kind, true) end
    function api.create_managed_array(kind,n)
        local values={}; for i=1,n do values[i]=false end
        local result=array(values)
        result.slot_array=kind=="app.training.TrainingData.TM_RecordSetting.SlotData"
        return result
    end
    function api.hook(method,pre,post) hooks[method]={pre,post} end
    function api.to_int64(value) return value end
    function api.to_ptr(value) return value end
    function api.to_managed_object(value) return value end
    local threads={get_id=function() return tid end,get_hook_storage=function() return tls end}
    local session
    local runtime=Runtime.new({api=api,threads=threads,library=library,context=function() return ctx end,
        log=function(message) stats.error=message; stats.logs=(stats.logs or 0)+1 end,
        prepare=function(...)
            local value,err,failed=require("SF6CCTrainingLibrary/NativeRecordingSession").prepare(...)
            session=value; return value,err,failed
        end})
    local function tick() for _=1,15 do runtime.tick() end end
    local function call(name,owner,result,between)
        local old=tls
        tls={}; local h=assert(hooks[name]); h[1]({0,owner}); if between then between() end
        local value=h[2](result); tls=old; return value
    end
    local function navigate(page_index)
        local page=pages[page_index]
        local v=obj({Data=page.fields._ChildData:get_element(0),ParentData=page})
        local param=obj(); param.kind="app.training.UIFlowTrainingMenu.Param"
        local h=assert(hooks["Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"])
        local previous=tls; tls={}
        local wanted=page.fields._ChildData:get_element(1).fields._SlotID==8 and 0 or 1
        local skip=h[1]({0,manager.fields._UIFunc,345,param,v,wanted})
        local result=h[2](99); tls=previous
        return skip,result
    end
    local function arrow(page_index,wanted)
        local page=pages[page_index]
        local v=obj({Data=page.fields._ChildData:get_element(0),ParentData=page,Index=0})
        local group=obj(); group.call=function() return 1 end
        local param=obj({_SecondaryList=group,_ViewDataList=array({obj({Index=0}),v})})
        param.kind="app.training.UIFlowTrainingMenu.Param"
        manager.fields._UITrainingMenu=obj({_ParamData=param})
        local old=tls; tls={}
        local spin=assert(hooks["OnUpdateSpin()"]); spin[1]({0,param})
        local outer=tls; tls={}
        local getter=assert(hooks["GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)"])
        getter[1]({0,manager.fields._UIFunc,345,wanted,345})
        local result=getter[2](99); tls=outer
        v.fields.Index=result
        assert(page.fields._ChildData:get_element(1).fields._SlotID~=wanted*8,
            "page rebuilt before native setter returned")
        spin[2](0); tls=old
        return result
    end
    return {runtime=runtime,tick=tick,call=call,ctx=ctx,stats=stats,fighter=fighter,data=data,manager=manager,
        pages=pages,obj=obj,array=array,record=record,objects=objects,thread=function(id) tid=id end,navigate=navigate,
        session=function() return session end,arrow=arrow,original=original}
end

test("private native bank retains slots across the observed Init reference loss",function()
    for _,index in ipairs({1,23,57,80}) do
        local f=fixture({init_ref_loss_at=index})
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
        local f=fixture({promotion_gc_at=index})
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
        local f=fixture({expire_slot=57,expire_stage=spec[1]})
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
        local f=fixture({missing_input_at=34,raw_input=raw})
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
    local f=fixture({copy_error=true})
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
test("release hook only notifies; game thread restores after native release",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick(); f.thread(22)
    f.call("Release",f.manager.id,0)
    assert(f.fighter.fields.RecordSlots:get_size()==80)
    f.thread(7); f.ctx.allowed=false; f.tick(); assert(f.fighter.fields.RecordSlots:get_size()==8)
end)
test("reset in idle restores native rows and recorder selection",function()
    local f=fixture(); f.runtime.install_hooks(); f.tick()
    f.record.fields._gData.fields.SlotID=8
    f.runtime.reset()
    assert(f.fighter.fields.RecordSlots:get_size()==8 and f.record.fields._gData.fields.SlotID==0)
    f.tick(); assert(f.fighter.fields.RecordSlots:get_size()==8)
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

test("fresh runtime refuses a residual eighty-slot bank without taking ownership or retrying",function()
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
print(passed .. " native runtime integration tests passed (fake SDK)")
