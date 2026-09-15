-- Single-save root-tab pilot adapted from WTT's MIT-licensed NativePauseMenu.
-- The engine navigates/layouts this page. Never request a native view refresh.
--[[
Copyright (c) 2026 Wael Hadjmouldi

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]
local Safety = require("SF6CCTrainingLibrary/Context")
local State = require("SF6CCTrainingLibrary/State")
local SharedLibrary = require("SF6CCTrainingLibrary/Library")
local library
local MENU, FUNC = "app.training.TrainingMenuData", "app.training.TrainingMenuFunc"
local DYNAMIC, REVERSAL, MAX_MOUNTS = 345, 5, 4
local owner, stopped, failed, tick = nil, false, false, 0
local hooks_ready = false
local mounts, retained, texts, layout = 0, {}, {}, {}
-- Stable, plugin-private GUIDs let a new Lua state identify only its own page.
-- These are detached 16-byte values, installed through the native GUID setters.
local function key(i) return "d8f1c64a28b74e719e5ac310b672" .. string.format("%04x", i) end
local function read(obj, name) return obj and obj:get_field(name) end
local function same(a, b) return a and b and a:get_address() == b:get_address() end
local function guid_key(guid)
    if not guid then return nil end
    local bytes = {}
    for i=0,15 do bytes[#bytes+1]=string.format("%02x",guid:read_byte(i)) end
    return table.concat(bytes)
end
local function own(value)
    assert(value, "native allocation returned nil")
    value:add_ref(); retained[#retained+1]=value
    return value
end
local function make_guid(i)
    local value=sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    local bytes=key(i)
    for offset=0,15 do value:write_byte(offset,tonumber(bytes:sub(offset*2+1,offset*2+2),16)) end
    return value
end
local function array(items)
    local value=own(sdk.create_managed_array(MENU,#items))
    for i,item in ipairs(items) do value:call("SetValue",item,i-1) end
    return value
end
local function node(kind,id,read_only)
    local value=own(sdk.create_instance_global(MENU))
    for name,v in pairs({_Type=kind,_FuncType=DYNAMIC,IsEnabled=true,
        IsCantFocus=read_only==true,IsNotFocusFunc=false,_Interval=1,_Interval_Option=1,
        _GuidIcon=-1,_GuidAddIcon=-1,VisibleCase=0}) do value:set_field(name,v) end
    value:call("set_MessageID(System.Guid)",make_guid(id))
    value:call("set_GuideMessage(System.Guid)",make_guid(5))
    assert(guid_key(read(value,"_MessageID"))==key(id),"GUID setter round-trip failed")
    return value
end
local function snapshot()
    texts[key(1)]="木人库"
    texts[key(2)]="保存当前配置"
    texts[key(5)]=library and ("当前配置："..library.selection_label().."\n"..tostring(library.status or "")) or ""
end
local function manager() return sdk.get_managed_singleton("app.training.TrainingManager") end
local function presentation_session()
    local runtime=State.runtime
    if runtime and runtime.state()=="active" and runtime.presentation_session then
        return runtime.presentation_session()
    end
end
local function same_session()
    local session=presentation_session()
    return owner and session~=nil and owner.runtime==State.runtime and owner.session==session
end
local function live(tm)
    return same_session() and same(tm,owner.tm) and same(read(tm,"_tData"),owner.data)
        and same(read(tm,"_UIData"),owner.ui)
        and same(read(read(tm,"_UIData"),"_MenuData"),owner.installed)
end
local function owns(data)
    if not data or not owner then return false end
    return owner.nodes[data:get_address()] == true
end
local function serving()
    return not stopped and not failed and same_session()
end
local function owned_call(args,view_arg)
    if not serving() then return false end
    local tm=manager()
    if not live(tm) or not same(sdk.to_managed_object(args[2]),read(tm,"_UIFunc")) then return false end
    return owns(read(sdk.to_managed_object(args[view_arg]),"Data"))
end
local function validate_page(page,template)
    assert(read(page,"_Type")==read(template,"_Type") and read(page,"_FuncType")==DYNAMIC,
        "owned root page layout changed; restart required")
    local rows=assert(read(page,"_ChildData"))
    assert(rows:get_size()==1,"owned root row count changed; restart required")
    local nodes={[page:get_address()]=true}
    for i=0,0 do
        local row=assert(rows:get_element(i))
        assert(read(row,"_Type")==0 and read(row,"_FuncType")==DYNAMIC
            and guid_key(read(row,"_MessageID"))==key(i+2),"owned root row identity changed")
        nodes[row:get_address()]=true
    end
    local dynamic=assert(read(page,"DynamicChildData"))
    assert(dynamic:call("get_Count")==0,"owned dynamic children changed")
    return nodes
end
local function install(tm,runtime,session)
    local ui=assert(read(tm,"_UIData"))
    local original=assert(read(ui,"_MenuData"))
    local n=original:get_size()
    assert(n>=8 and n<=16,"unsupported native root count")
    local items,existing,insert_after,existing_index={},nil,nil,nil
    for i=0,n-1 do
        local item=assert(original:get_element(i))
        if guid_key(read(item,"_MessageID"))==key(1) then
            assert(not existing,"duplicate owned root page; restart required")
            existing,existing_index=item,i+1
        else
            if #items<8 then assert(read(item,"_FuncType")==#items+1,"native root ordering changed") end
            items[#items+1]=item
            if read(item,"_FuncType")==REVERSAL then
                assert(not insert_after,"duplicate native reversal root")
                insert_after=#items
            end
        end
    end
    assert(#items>=8 and insert_after,"native reversal root missing")
    if existing then assert(existing_index==insert_after+1,"owned root position changed; restart required") end
    local template=items[1]
    local page,installed=existing,original
    if not page then
        assert(n<16,"native root capacity reached")
        assert(mounts<MAX_MOUNTS,"root-tab pilot mount limit reached; restart required")
        mounts=mounts+1
        page=node(read(template,"_Type"),1,false)
        page:set_field("NextButton",read(template,"NextButton"))
        page:set_field("PrevButton",read(template,"PrevButton"))
        -- Reuse the accepted single-row layout for the first shared operation.
        local rows={node(0,2,false)}
        page:set_field("_ChildData",array(rows))
        local source=assert(read(items[2],"DynamicChildData"))
        page:set_field("DynamicChildData",own(source:call("GetRange",0,0)))
        validate_page(page,template)
        table.insert(items,insert_after+1,page)
        installed=array(items)
    end
    local next_owner={runtime=runtime,session=session,tm=tm,data=read(tm,"_tData"),ui=ui,page=page,
        installed=installed,nodes=validate_page(page,template),
        save_row=read(page,"_ChildData"):get_element(0):get_address()}
    -- Publish once, only from a closed-menu update. Borrowed roots are untouched.
    if not existing then ui:set_field("_MenuData",installed) end
    owner=next_owner
    log.info("[NativeLibraryTab] Save root tab "..(existing and "adopted" or "installed").." after REVERSAL; shared save queue")
end
local function update(install_hooks)
    local runtime,session=State.runtime,presentation_session()
    if session==nil then return end
    if not Safety.is_training_allowed() or Safety.pause_open()~=false then return end
    local tm=manager()
    if not tm or read(tm,"_IsInit")~=true then return end
    library=library or SharedLibrary.shared()
    -- Requiring this optional UI must leave baseline startup completely dormant.
    -- A failed or partial hook setup is stopped by the caller, never retried.
    if not hooks_ready then install_hooks(); hooks_ready=true end
    snapshot()
    if not live(tm) then
        -- Do not restore or dereference a previous scene's UI objects.
        owner=nil
        install(tm,runtime,session)
    end
end
local function method(type_name,name)
    local td=sdk.find_type_definition(type_name)
    return assert(td and td:get_method(name),"Missing native method: "..type_name.."."..name)
end
local function message_id(ptr) return guid_key(sdk.to_valuetype(ptr,"System.Guid")) end
local function setup()
    local methods={
        message=method("app.helper.hMsg","GetMessage(System.Guid)"),
        action=method(FUNC,"Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"),
        active=method(FUNC,"GetIsActive(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)"),
        view=method(FUNC,"ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"),
        value=method(FUNC,"IsValueType"),visible=method(FUNC,"GetVisibleCase"),changed=method(FUNC,"IsChangedValue"),
    }
    sdk.hook(methods.message,function(args)
        local st=thread.get_hook_storage(); st.library_root_text=nil
        if not serving() then return end
        local ok,id=pcall(message_id,args[2])
        if ok and id==key(5) then snapshot() end
        if ok and texts[id]~=nil then
            st.library_root_text=texts[id]; return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,function(rv)
        local text=thread.get_hook_storage().library_root_text
        if text==nil then return rv end
        local value=sdk.create_managed_string(text)
        value:add_ref() -- One reference for the native consumer, one for Lua.
        return sdk.to_ptr(value)
    end)
    local function view_hook(m,arg_index,result,action)
        sdk.hook(m,function(args)
            local st=thread.get_hook_storage(); st.library_root_result=nil
            if serving() and (sdk.to_int64(args[3]) & 0xFFFFFFFF)==DYNAMIC and owned_call(args,arg_index) then
                st.library_root_result=result
                if action then
                    local ok,value=pcall(action,args)
                    if ok then st.library_root_result=value
                    else
                        library.request_cancel()
                        library.status_ok,library.status=false,"保存请求失败，详情见日志"
                        log.error("[NativeLibraryTab] Save request failed: "..tostring(value))
                    end
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end,function(rv)
            local result_value=thread.get_hook_storage().library_root_result
            if result_value~=nil then return sdk.to_ptr(result_value) end
            return rv
        end)
    end
    view_hook(methods.action,5,0,function(args)
        if next(layout) or library.has_pending() then return 0 end
        local row=read(sdk.to_managed_object(args[5]),"Data")
        if not row or row:get_address()~=owner.save_row then return 0 end
        -- Match the established native menu return protocol. The shared Library
        -- queues work; the accepted entry executes it after the menu closes.
        return library.request("save") and 1 or 0
    end)
    view_hook(methods.active,4,1)
    -- Observe engine layout, never call it. Primitive WTT getters lack a row
    -- argument, so scope them to this thread's current owned layout only.
    sdk.hook(methods.view,function(args)
        local id=thread.get_id(); local stack=layout[id] or {}; layout[id]=stack
        if not serving() then stack[#stack+1]=false; return end
        local tm=manager()
        stack[#stack+1]=not stopped and not failed and live(tm)
            and same(sdk.to_managed_object(args[2]),read(tm,"_UIFunc"))
            and owns(sdk.to_managed_object(args[4])) or false
    end,function(rv)
        local id=thread.get_id(); local stack=layout[id]
        if stack then table.remove(stack); if #stack==0 then layout[id]=nil end end
        return rv
    end)
    for _,m in ipairs({methods.value,methods.visible,methods.changed}) do
        sdk.hook(m,function(args)
            local st=thread.get_hook_storage(); st.library_root_zero=false
            local stack=layout[thread.get_id()]
            if serving() and stack and stack[#stack]
                and (sdk.to_int64(args[3]) & 0xFFFFFFFF)==DYNAMIC then
                st.library_root_zero=true; return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end,function(rv)
            if thread.get_hook_storage().library_root_zero then return sdk.to_ptr(0) end
            return rv
        end)
    end
end
re.on_pre_application_entry("LateUpdateBehavior",function()
    if stopped or failed then return end
    tick=tick+1; if tick%30~=0 then return end
    local success,detail=pcall(update,setup)
    if not success then
        failed=true
        log.error("[NativeLibraryTab] Stopped; restart required: "..tostring(detail))
    end
end)
re.on_script_reset(function()
    stopped=true
    -- Never rewrite a live menu or release native-visible allocations on Reset.
    -- A later Lua state can adopt this GUID-scoped page once the menu is closed.
    if owner then log.warn("[NativeLibraryTab] Reset: root page retained; cold-start acceptance still required") end
end)
return true
