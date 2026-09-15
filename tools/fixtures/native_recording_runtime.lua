-- Shared native-runtime simulation; not evidence of engine allocation safety.
local Runtime = require("SF6CCTrainingLibrary/NativeRecordingRuntime")
local function fixture(options)
    options = options or {}
    local prepare_session=options.session or require("SF6CCTrainingLibrary/NativeRecordingSession")
    local address, hooks, tls, tid, objects = 100, {}, {}, 7, {}
    local slot_allocations = 0
    local native_work = { allocations=0, duplicates=0 }
    local function construction_boundary(stage, subject)
        if options.construction_fault then
            options.construction_fault(stage, subject, objects, native_work)
        end
    end
    local function obj(fields)
        address = address + 1
        local o = { fields = fields or {}, id = address, refs = 1 }
        objects[address] = o
        function o:get_address() return self.id end
        function o:get_field(k)
            construction_boundary("read:"..k,self)
            -- SDK parse_data/set_data uses boxed Guid size (32), while the
            -- inline Title occupies 16 bytes followed immediately by InputData.
            if k=="Title" and options.guid_overcopy then
                return {guid=self.fields.Title, trailing_input=self.fields.InputData}
            end
            return self.fields[k]
        end
        function o:set_field(k,v)
            construction_boundary("write:"..k,self)
            local previous=self.fields[k]
            if k=="IsUpdate" then
                native_work.dirty_writes=(native_work.dirty_writes or 0)+1
                if self.fields.Data and self.fields.Data.fields._FuncType==345 then
                    native_work.dirty_updates=(native_work.dirty_updates or 0)+1
                end
                if options.fail_dirty then error("injected dirty flag failure") end
            end
            if k=="_ChildData" then native_work.menu_writes=(native_work.menu_writes or 0)+1 end
            if options.menu_structs and type(v)=="table" and v.inline_struct then
                error("unsafe boxed-size inline menu struct copy: "..k)
            end
            if k=="Title" and options.guid_overcopy then
                self.fields.Title=v.guid; self.fields.InputData=v.trailing_input; return
            end
            self.fields[k] = v
            if self.kind=="app.training.TrainingMenuData" and k=="_SlotID"
                and v==options.menu_expire_on_assignment and previous==v then self:expire() end
        end
        function o:add_ref()
            assert(not self.expired, "cannot retain an invalid native object")
            if self.local_object then
                -- REFramework #1448/#1504: promotion can leave a second Lua
                -- wrapper whose finalizer releases the promoted native ref.
                self.local_object = false; self.refs = 1
                self.orphan_finalizer = true
            elseif not self.init_ref_loss and not self.menu_dedup then
                self.refs = self.refs + 1
            end
            if self.expire_stage == "retain" then self:expire() end
        end
        function o:expire() self.expired=true; self.refs=0; self.kind=nil; self.fields={} end
        function o:release() self.refs = self.refs - 1; assert(self.refs >= 0) end
        function o:get_reference_count() return self.refs end
        function o:get_type_definition()
            if self.expired then native_work.expired_type_reads=(native_work.expired_type_reads or 0)+1 end
            if self.refs == 0 or self.expired then return nil end
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
            construction_boundary("call:"..name,self)
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
            if name=="ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)" then
                native_work.view_updates=(native_work.view_updates or 0)+1
                error("forced native ViewUpdate is forbidden")
            end
            if name == "get_Count" then return #self.items end
            if name == "get_Item" then return self.items[a+1] end
            if name == "GetFighterIndex" then assert(a==28); return 0 end
            if name == "SetValue(System.Object, System.Int32)" then
                if a.expired then native_work.invalid_insertions=(native_work.invalid_insertions or 0)+1 end
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
    for i=1,(options.native_capacity or 8) do
        local inputs={}; for j=1,i do inputs[j]=i end
        original[i]=obj({Frame=i,Weight=1,IsValid=true,IsActive=true,Title="native-frame-format-"..i,
            InputData=obj({Num=i,buff=array(inputs)})})
    end
    local fighter=obj({FighterID=28,RecordSlots=array(original)})
    local data=obj({RecordSetting=obj({FighterDataList=array({fighter})})})
    local function duplicate(self)
        native_work.duplicates=native_work.duplicates+1
        local source=self.fields.RecordSetting.fields.FighterDataList.items[1].fields.RecordSlots.items
        local copies={}
        for i=1,#source do copies[i]=obj(); copies[i]:call("DeepCopy",source[i]) end
        local copied_bank=array(copies)
        copied_bank.slot_array=true
        local result=obj({RecordSetting=obj({FighterDataList=array({obj({FighterID=28,RecordSlots=copied_bank})})})})
        local basecall=result.call
        result.call=function(target,name,...)
            if name=="Duplicate" then return duplicate(target) end
            return basecall(target,name,...)
        end
        return result
    end
    local basecall=data.call
    data.call=function(self,name,...)
        if name=="Duplicate" then return duplicate(self) end
        return basecall(self,name,...)
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
    local stats={cancel=0,autoload=0,names_reset=0}
    local library={cancel=function() stats.cancel=stats.cancel+1 end,
        abandon=function() stats.abandoned=(stats.abandoned or 0)+1 end,
        has_pending=function() return stats.pending==true end,
        reset_slot_names=function() stats.names_reset=stats.names_reset+1 end,
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
            get_field=function(_,name) assert(name=="Success"); return {get_data=function() return options.save_success or 1 end} end,
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
        native_work.allocations=native_work.allocations+1
        if kind=="app.training.tf_RecordSetting.GameLocalData" then
            local counter=global and "recorder_global_creations" or "recorder_local_creations"
            native_work[counter]=(native_work[counter] or 0)+1
        end
        if kind=="app.training.TrainingMenuData" and options.menu_single_ref_reclaim then
            for _,old in pairs(objects) do
                if old.kind==kind and old.fields._SlotID==3 and old.fields._FuncType==118 then
                    native_work.reclaim_checks=(native_work.reclaim_checks or 0)+1
                    if old.refs==1 then
                        old:expire()
                        old.refs=1688060279 -- Observed overwritten header; not a valid reference count.
                    end
                end
            end
        end
        local value=obj(); value.kind=kind
        if kind=="app.training.TrainingMenuData" then
            native_work.menu_creations=(native_work.menu_creations or 0)+1
            construction_boundary("create",value)
        end
        value.menu_dedup=options.menu_single_ref_reclaim and kind=="app.training.TrainingMenuData"
        if options.menu_promotion_gc and kind=="app.training.TrainingMenuData" and not global then
            value.local_object=true; value.refs=-1
        end
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
        native_work.allocations=native_work.allocations+1
        if kind=="app.training.TrainingMenuData" and n==12 and options.menu_fault then
            native_work.menu_windows=(native_work.menu_windows or 0)+1
            if native_work.menu_windows==(options.menu_fault_window or 1) then
                options.menu_fault(objects,pages,native_work)
            end
        end
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
    local ui_phase=true
    local runtime=Runtime.new({api=api,threads=threads,library=library,in_ui_update=function() return ui_phase end,context=function()
        stats.context_reads=(stats.context_reads or 0)+1
        return ctx
    end,
        save_idle=function() return ctx.save_busy~=true end,
        trace=options.trace,
        log=function(message) stats.error=message; stats.logs=(stats.logs or 0)+1 end,
        prepare=function(...)
            local value,err,failed,deferred=prepare_session.prepare(...)
            session=value; return value,err,failed,deferred
        end})
    local function tick(count) for _=1,count or 45 do runtime.tick() end end
    local function call(name,owner,result,between)
        if name=="StartSaveDirectSlot(System.Int32, System.String)" and not hooks[name] then
            if between then between() end
            return result
        end
        local old=tls
        tls={}; local h=assert(hooks[name]); h[1]({0,owner}); if between then between() end
        local value=h[2](result); tls=old; return value
    end
    local function ui_tick(count) for _=1,count or 2 do runtime.ui_tick() end end
    local function focus_page(page_index)
        local page=pages[page_index]
        local v=obj({Data=page.fields._ChildData:get_element(0),ParentData=page,Index=0})
        local group=obj(); group.call=function() return 1 end
        local views={obj({Index=0}),v}
        for i=1,page.fields._ChildData:get_size()-1 do
            views[#views+1]=obj({Data=page.fields._ChildData:get_element(i),ParentData=page,Index=0,IsUpdate=false})
        end
        local param=obj({_SecondaryList=group,_ViewDataList=array(views),_SecondarySpinIndex=1})
        param.kind="app.training.UIFlowTrainingMenu.Param"
        manager.fields._UITrainingMenu=obj({_ParamData=param})
        return page,v,param
    end
    local function navigate(page_index,defer)
        local page,v,param=focus_page(page_index)
        local h=assert(hooks["Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"])
        local previous=tls; tls={}
        local wanted=page.fields._ChildData:get_element(1).fields._SlotID==8 and 0 or 1
        local skip=h[1]({0,manager.fields._UIFunc,345,param,v,wanted})
        local result=h[2](99); tls=previous
        if not defer then ui_tick() end
        return skip,result
    end
    local function arrow(page_index,wanted,defer,native_paint,action_args)
        local page,v,param=focus_page(page_index)
        local before=page.fields._ChildData
        local old=tls; tls={}
        local spin=assert(hooks["OnUpdateSpin()"]); spin[1]({0,param})
        local outer=tls; tls={}
        local getter=assert(hooks["GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)"])
        getter[1]({0,manager.fields._UIFunc,345,wanted,345})
        local result=getter[2](99); tls=outer
        v.fields.Index=result
        assert(page.fields._ChildData==before,
            "page rebuilt before native setter returned")
        if native_paint then
            -- Native UpdateSpinBox calls Function after committing Index, then
            -- UpdateSecondaryList before OnUpdateSpin returns (live disassembly).
            local outer_action=tls; tls={}
            local action=assert(hooks["Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"])
            local args={0,manager.fields._UIFunc,345,param,v,result}
            if action_args then args=action_args(args) end
            action[1](args)
            action[2](0); tls=outer_action
            native_paint(page,v,param)
        end
        spin[2](0); tls=old
        if not defer then ui_tick() end
        return result
    end
    local function read_page_focus(page_index)
        local _,v=focus_page(page_index)
        local h=assert(hooks["GetFocusIndex(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)"])
        local previous=tls; tls={}
        h[1]({0,manager.fields._UIFunc,345,v})
        local result=h[2](99); tls=previous
        return result
    end
    local function option_arrow(page_index,wanted,defer,native_paint,alter)
        return arrow(page_index,wanted,defer,native_paint,function(args)
            local row=args[5].fields.Data
            local option=row.fields._ChildData:get_element(wanted)
            args[5]=obj({Data=option,ParentData=row,Index=0})
            -- Captured native child Function uses the spinner's row index;
            -- upper pointer bits are not part of its System.Int32 argument.
            args[6]=0x100000000+args[4].fields._SecondarySpinIndex
            if alter then args=alter(args) end
            return args
        end)
    end
    local function hook_call(name,args)
        local previous=tls; tls={}
        local h=assert(hooks[name])
        local skip=h[1](args)
        local result=h[2](99); tls=previous
        return skip,result
    end
    return {runtime=runtime,tick=tick,call=call,ctx=ctx,stats=stats,fighter=fighter,data=data,manager=manager,
        pages=pages,obj=obj,array=array,record=record,objects=objects,thread=function(id) tid=id end,navigate=navigate,
        session=function() return session end,arrow=arrow,original=original,native_work=native_work,
        ui_tick=ui_tick,focus_page=focus_page,read_page_focus=read_page_focus,hook_call=hook_call,
        api=api,threads=threads,option_arrow=option_arrow,
        ui_phase=function(value) ui_phase=value end}
end
return fixture
