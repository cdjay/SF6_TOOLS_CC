-- Native navigation only: never rebuild widgets from an update callback.
-- Message routing follows the MIT-licensed Wael NativeOptions technique.
local M = {}
local DYNAMIC = 345
local VIEW = "ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"

function M.key(guid)
    local bytes = {}
    for i = 0, 15 do bytes[#bytes + 1] = string.format("%02x", guid:read_byte(i)) end
    return table.concat(bytes)
end

function M.control(api, own, capacity, page_size)
    local texts={}
    local function item(kind,text)
        local guid = assert(api.find_type_definition("System.Guid")):get_field("Empty"):get_data(nil):NewGuid()
        local key = M.key(guid)
        assert(key ~= string.rep("0", 32) and not texts[key], "invalid pager GUID")
        local row = own(api.create_instance("app.training.TrainingMenuData"))
        for key, value in pairs({ _Type = kind, _FuncType = DYNAMIC, IsEnabled = true,
            IsCantFocus = false, IsNotFocusFunc = false, _Interval = 1, _Interval_Option = 1,
            _GuidIcon = -1, _GuidAddIcon = -1, VisibleCase = 0 }) do row:set_field(key, value) end
        row:call("set_MessageID(System.Guid)", guid)
        row:call("set_GuideMessage(System.Guid)", guid)
        assert(M.key(row:get_field("_MessageID")) == key, "pager title readback")
        texts[key]=text
        return row
    end
    local row=item(1,"页码")
    local count=math.ceil(capacity/page_size)
    local options=own(api.create_managed_array("app.training.TrainingMenuData",count))
    local labels={}
    for i=1,count do
        labels[i]=string.format("%d / %d（栏位 %d-%d）",i,count,(i-1)*page_size+1,math.min(i*page_size,capacity))
        local option=item(0,labels[i])
        options:call("SetValue(System.Object, System.Int32)",option,i-1)
    end
    row:set_field("_ChildData",options)
    return row,texts,labels
end

function M.new(api, threads, current, allowed, report)
    local self, depths, layouts, spins, refreshing, stopped = {}, {}, {}, {}, false, false
    local function equal(a,b) return a and b and a:get_address()==b:get_address() end
    local function menu(owner)
        if not allowed() then return nil end
        local entry = current()
        if not entry or entry.phase ~= "active" or entry.released then return nil end
        local actual = api.to_managed_object(owner)
        local expected = entry.manager:get_field("_UIFunc")
        if not actual or not expected or actual:get_address() ~= expected:get_address() then return nil end
        return entry.menu, entry
    end
    local function spin_context(owner)
        local m,entry=menu(owner); if not m then return end
        local layout=layouts[threads.get_id()]
        if depths[threads.get_id()] then
            return m,layout and m.pager_info(layout) or nil,layout
        end
        -- No remembered row from an earlier layout: resolve the current native focus.
        local ui=entry.manager:get_field("_UITrainingMenu")
        local param=ui and ui:get_field("_ParamData")
        local group=param and param:get_field("_SecondaryList")
        local list=param and param:get_field("_ViewDataList")
        if not group or not list then return end
        local focus=group:call("GetFocusIndex")
        local count=list:call("get_Count")
        if type(count)~="number" or count<0 or count>32 then return end
        if type(focus)~="number" or focus%1~=0 or focus<0 or focus>=count then return end
        -- ViewData.Index is the row's option value, not its position in the list.
        local v=list:call("get_Item",focus)
        local data,parent=v and v:get_field("Data"),v and v:get_field("ParentData")
        if m.owns_pager(data,parent) then return m,m.pager_info(data),data,parent,param,entry,v end
    end
    local function change(ui,m,entry,param,data,parent,wanted)
        if stopped or refreshing then return end
        local info=m.pager_info(data)
        if not info or wanted<0 or wanted>=info.count or wanted==info.index then return end
        assert(param:get_type_definition():get_full_name()=="app.training.UIFlowTrainingMenu.Param",
            "unexpected pager parameter")
        refreshing=true
        local ok,err=pcall(function()
            entry.with_menu_navigation(ui,data,parent,function()
                assert(m.navigate(data,parent,wanted),"pager navigation refused")
                assert(ui:call(VIEW,param,parent,0)==true,"pager view update failed")
            end)
        end)
        refreshing=false
        if not ok then stopped=true; pcall(report,tostring(err)) end
    end
    function self.install()
        local function method(kind, signature)
            return assert(assert(api.find_type_definition(kind)):get_method(signature), signature)
        end
        local view = method("app.training.TrainingMenuFunc", VIEW)
        local action = method("app.training.TrainingMenuFunc",
            "Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)")
        local active = method("app.training.TrainingMenuFunc",
            "GetIsActive(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)")
        local message = method("app.helper.hMsg", "GetMessage(System.Guid)")
        local focus=method("app.training.TrainingMenuFunc","GetFocusIndex(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)")
        local index=method("app.training.TrainingMenuFunc","GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)")
        local option_text=method("app.training.TrainingMenuFunc","GetOptionText(app.training.TrainingFuncType)")
        local spin=method("app.training.UIFlowTrainingMenu.Param","OnUpdateSpin()")
        -- GetOptionIndex also probes neighbouring options. Only the ViewData
        -- selection committed by the native setter authorizes a page rebuild.
        api.hook(spin,function(args)
            local storage=threads.get_hook_storage()
            local id=threads.get_id()
            storage.sf6cc_pager_previous_spin=spins[id]
            spins[id]=nil
            if stopped or refreshing or depths[id] then return end
            local ok,ctx=pcall(function()
                local entry=current(); if not entry then return end
                local ui=entry.manager:get_field("_UIFunc")
                local m,info,data,parent,param,_,v=spin_context(ui)
                if not info or not equal(param,api.to_managed_object(args[2])) then return end
                return {ui=ui,m=m,entry=entry,param=param,data=data,parent=parent,view=v,index=info.index}
            end)
            if ok then spins[id]=ctx end
        end,function(retval)
            local id=threads.get_id(); local ctx=spins[id]
            spins[id]=threads.get_hook_storage().sf6cc_pager_previous_spin
            if ctx then
                local ok,err=pcall(function()
                    local m,info,data,parent,param,entry,v=spin_context(ctx.ui)
                    if m~=ctx.m or entry~=ctx.entry or not equal(param,ctx.param)
                        or not equal(data,ctx.data) or not equal(parent,ctx.parent)
                        or not equal(v,ctx.view) or info.index~=ctx.index then return end
                    local wanted=v:get_field("Index")
                    if type(wanted)~="number" or wanted%1~=0 or wanted<0 or wanted>=info.count then return end
                    change(ctx.ui,m,entry,param,data,parent,wanted)
                end)
                if not ok then stopped=true; pcall(report,tostring(err)) end
            end
            return retval
        end)
        api.hook(view, function(args)
            local id=threads.get_id(); depths[id]=(depths[id] or 0)+1
            local storage=threads.get_hook_storage()
            storage.sf6cc_pager_previous_layout=layouts[id]
            layouts[id]=nil
            local ok,data=pcall(function() if menu(args[2]) then return api.to_managed_object(args[4]) end end)
            if ok then layouts[id]=data end
        end, function(retval)
            local id=threads.get_id(); local depth=(depths[id] or 1)-1
            depths[id]=depth>0 and depth or nil
            layouts[id]=depth>0 and threads.get_hook_storage().sf6cc_pager_previous_layout or nil
            return retval
        end)
        local function value_hook(target,key,read)
            api.hook(target,function(args)
                local storage=threads.get_hook_storage(); storage[key]=nil
                if (api.to_int64(args[3]) & 0xFFFFFFFF)~=DYNAMIC then return end
                local ok,value=pcall(function()
                    local result=read(args)
                    if type(result)=="string" then
                        local str=api.create_managed_string(result); str:add_ref(); return str
                    end
                    return result
                end)
                if ok and value~=nil then storage[key]=value; return api.PreHookResult.SKIP_ORIGINAL end
            end,function(retval)
                local value=threads.get_hook_storage()[key]
                if value==nil then return retval end
                return api.to_ptr(value)
            end)
        end
        value_hook(focus,"sf6cc_pager_focus",function(args)
            local m=menu(args[2]); local v=api.to_managed_object(args[4])
            if m and v and m.owns_pager(v:get_field("Data"),v:get_field("ParentData")) then
                return m.pager_info(v:get_field("Data")).index
            end
        end)
        value_hook(index,"sf6cc_pager_index",function(args)
            local _,info=spin_context(args[2]); if not info then return end
            if stopped or depths[threads.get_id()] then return info.index end
            local wanted=api.to_int64(args[4]) & 0xFFFFFFFF
            if wanted>=0x80000000 then wanted=wanted-0x100000000 end
            wanted=wanted % info.count
            return wanted
        end)
        value_hook(option_text,"sf6cc_pager_option_text",function(args)
            local _,info=spin_context(args[2]); return info and info.label or nil
        end)
        api.hook(action, function(args)
            local storage = threads.get_hook_storage()
            storage.sf6cc_record_pager_result = nil
            local ok, err = pcall(function()
                if (api.to_int64(args[3]) & 0xFFFFFFFF) ~= DYNAMIC then return end
                local m, entry = menu(args[2]); if not m then return end
                local view_data = api.to_managed_object(args[5]); if not view_data then return end
                local data, parent = view_data:get_field("Data"), view_data:get_field("ParentData")
                if not m.owns_pager(data, parent) then return end
                storage.sf6cc_record_pager_result = 0
                if stopped or depths[threads.get_id()] or refreshing then return end
                if spins[threads.get_id()] then return end
                local wanted=api.to_int64(args[6]) & 0xFFFFFFFF
                local info=m.pager_info(data)
                if wanted>=info.count or wanted==info.index then return end
                local param = assert(api.to_managed_object(args[4]))
                local ui = api.to_managed_object(args[2])
                change(ui,m,entry,param,data,parent,wanted)
            end)
            if not ok then refreshing = false; stopped = true; pcall(report,tostring(err)) end
            if storage.sf6cc_record_pager_result ~= nil then return api.PreHookResult.SKIP_ORIGINAL end
        end, function(retval)
            local value = threads.get_hook_storage().sf6cc_record_pager_result
            return value ~= nil and api.to_ptr(value) or retval
        end)
        api.hook(active, function(args)
            local storage = threads.get_hook_storage()
            storage.sf6cc_record_pager_active = nil
            local ok, owned = pcall(function()
                if (api.to_int64(args[3]) & 0xFFFFFFFF) ~= DYNAMIC then return false end
                local m = menu(args[2]); if not m then return false end
                local v = api.to_managed_object(args[4])
                return v and m.owns_pager(v:get_field("Data"), v:get_field("ParentData"))
            end)
            if ok and owned then
                storage.sf6cc_record_pager_active = true
                return api.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval)
            if threads.get_hook_storage().sf6cc_record_pager_active then return api.to_ptr(stopped and 0 or 1) end
            return retval
        end)
        api.hook(message, function(args)
            local storage = threads.get_hook_storage()
            storage.sf6cc_record_pager_text = nil
            local entry = current()
            if not entry or entry.phase ~= "active" or entry.released then return end
            local ok, text = pcall(function()
                local value=entry.menu.text(M.key(api.to_valuetype(args[2], "System.Guid")))
                if value then
                    local str=api.create_managed_string(value); str:add_ref(); return str
                end
            end)
            if ok and text then
                storage.sf6cc_record_pager_text = text
                return api.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval)
            local text = threads.get_hook_storage().sf6cc_record_pager_text
            if text then return api.to_ptr(text) end
            return retval
        end)
    end
    return self
end
return M
