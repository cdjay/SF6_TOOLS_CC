-- Native library action tab adapted from WTT's MIT-licensed NativePauseMenu.
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
local NativeTicker = require("SF6CCTrainingLibrary/NativeTicker")
local Feedback = require("SF6CCTrainingLibrary/NativeLibraryFeedback")
local View = require("SF6CCTrainingLibrary/NativeLibraryView")
local Editor = require("SF6CCTrainingLibrary/NativeNoteEditor")
local Pager = require("SF6CCTrainingLibrary/NativeLibraryPager")
local Ownership = require("SF6CCTrainingLibrary/NativeOwnership")
local library,ticker,feedback,view
local pager
local initializing_spin=false
local option_nodes,option_arrays={},{}
local editor,editor_attempted
local MENU, FUNC = "app.training.TrainingMenuData", "app.training.TrainingMenuFunc"
local DYNAMIC, REVERSAL = 345, 5
local ROWS={}
for i=1,View.COUNT do ROWS[i]={id=200+i} end
local owner, stopped, failed, tick = nil, false, false, 0
local hooks_ready = false
-- One permanently referenced page per Lua state; recreated training UIs adopt it.
local owned_page, published
local texts, layout = {}, {}
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
local function make_guid(i)
    local value=sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    local bytes=key(i)
    for offset=0,15 do value:write_byte(offset,tonumber(bytes:sub(offset*2+1,offset*2+2),16)) end
    return value
end
local function array(items)
    local value=Ownership.array(sdk,MENU,#items)
    for i,item in ipairs(items) do value:call("SetValue",item,i-1) end
    return value
end
local function node(kind,id,read_only)
    local value=Ownership.instance(sdk,MENU)
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
    local rows=view and view.rows() or {}
    for i,row in ipairs(ROWS) do texts[key(row.id)]=rows[i] and rows[i].text or "" end
    texts[key(5)]=library and ("当前配置："..library.selection_label()) or ""
    local info=view and view.paging()
    if info then
        for i=1,info.count do texts[key(300+i)]=i.." / "..info.count end
    end
end
local function prepare_options()
    -- Allocate only while the menu is closed. Navigation selects an existing,
    -- retained array, never allocates or replaces the native visible row list.
    for _,count in ipairs(view.page_counts()) do
        assert(count>=1 and count<=32,"unsupported library page count")
        if count>1 and not option_arrays[count] then
            local items={}
            for i=1,count do
                option_nodes[i]=option_nodes[i] or node(0,300+i,false)
                items[i]=option_nodes[i]
            end
            option_arrays[count]=array(items)
        end
    end
end
local function bind_rows(page)
    local rows=view.rows()
    local info=view.paging()
    local options=info and assert(option_arrays[info.count],"library pages changed; close and reopen menu")
    local native=read(page,"_ChildData")
    local pager_row=native:get_element(view.pager_row()-1)
    if options then
        local row=pager_row
        if not same(read(row,"_ChildData"),options) then row:set_field("_ChildData",options) end
    end
    owner.pager=pager_row
    for i,item in ipairs(rows) do
        local row=native:get_element(i-1)
        if read(row,"_Type")~=item.kind then row:set_field("_Type",item.kind) end
        if read(row,"IsCantFocus")~=item.readonly then row:set_field("IsCantFocus",item.readonly) end
    end
    snapshot()
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
    assert(#ROWS<=13 and rows:get_size()==#ROWS,"owned root row count changed; restart required")
    local nodes,actions={[page:get_address()]=true},{}
    for i,spec in ipairs(ROWS) do
        local row=assert(rows:get_element(i-1))
        local kind=read(row,"_Type")
        assert((kind==0 or ((i==2 or i==8) and kind==4) or ((i==1 or i==10) and kind==1)) and read(row,"_FuncType")==DYNAMIC
            and guid_key(read(row,"_MessageID"))==key(spec.id),"owned root row identity changed")
        nodes[row:get_address()]=true
        actions[row:get_address()]=i
    end
    local dynamic=assert(read(page,"DynamicChildData"))
    assert(dynamic:call("get_Count")==0,"owned dynamic children changed")
    return nodes,actions
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
    -- A page adopted after Reset may come from an older Lua state; give it our
    -- own permanent reference before any later UI can be built around it.
    if page and not owned_page then owned_page=Ownership.retain(page) end
    if not page then
        assert(n<16,"native root capacity reached")
        -- A session publishes at most one root array. A second one means the
        -- game replaced the menu mid-session; stop rather than leak per update.
        assert(not published or published.runtime~=runtime or published.session~=session,
            "native root menu replaced during session; restart required")
        if not owned_page then
            local built=node(read(template,"_Type"),1,false)
            built:set_field("NextButton",read(template,"NextButton"))
            built:set_field("PrevButton",read(template,"PrevButton"))
            local rows=Ownership.array(sdk,MENU,#ROWS)
            for i,spec in ipairs(ROWS) do rows:call("SetValue",node(0,spec.id,false),i-1) end
            built:set_field("_ChildData",rows)
            local source=assert(read(items[2],"DynamicChildData"))
            built:set_field("DynamicChildData",Ownership.retain(source:call("GetRange",0,0)))
            validate_page(built,template)
            owned_page=built
        end
        page=owned_page
        table.insert(items,insert_after+1,page)
        installed=array(items)
        published={runtime=runtime,session=session}
    end
    local nodes,actions=validate_page(page,template)
    local next_owner={runtime=runtime,session=session,tm=tm,data=read(tm,"_tData"),ui=ui,page=page,
        installed=installed,nodes=nodes,actions=actions,pager=read(page,"_ChildData"):get_element(9)}
    -- Publish once, only from a closed-menu update. Borrowed roots are untouched.
    if not existing then ui:set_field("_MenuData",installed) end
    owner=next_owner
    bind_rows(page)
    log.info("[NativeLibraryTab] Action root tab "..(existing and "adopted" or "installed").." after REVERSAL; shared operation queue")
end
local function update(install_hooks)
    local runtime,session=State.runtime,presentation_session()
    if session==nil then return end
    if not Safety.is_training_allowed() or Safety.pause_open()~=false then return end
    local tm=manager()
    if not tm or read(tm,"_IsInit")~=true then return end
    library=library or SharedLibrary.shared()
    if not library.loaded then library.refresh() end
    view=view or View.new(library,function() return editor and editor.available() end)
    view.set_context(SharedLibrary.runtime_context())
    if not ticker then
        ticker=NativeTicker.new({api=sdk,threads=thread,report=log.error})
        ticker.prepare()
        feedback=Feedback.new(library,ticker)
    end
    -- Requiring this optional UI must leave baseline startup completely dormant.
    -- A failed or partial hook setup is stopped by the caller, never retried.
    if not hooks_ready then install_hooks(); hooks_ready=true end
    if not editor_attempted then
        editor_attempted=true
        local ok,value=pcall(Editor.install)
        if ok then editor=value end
        if not ok or not editor or not editor.available() then
            library.status_ok,library.status=false,"名称编辑暂不可用，或有其他操作尚未完成"
            log.error("[NativeLibraryTab] Editor unavailable; other library actions unchanged: "..tostring(value))
        end
    end
    view.closed()
    prepare_options()
    snapshot()
    if not live(tm) then
        -- Do not restore or dereference a previous scene's UI objects.
        owner=nil
        install(tm,runtime,session)
    else
        bind_rows(owner.page)
    end
end
local function method(type_name,name)
    local td=sdk.find_type_definition(type_name)
    return assert(td and td:get_method(name),"Missing native method: "..type_name.."."..name)
end
local function message_id(ptr) return guid_key(sdk.to_valuetype(ptr,"System.Guid")) end
local function redraw_targets(param)
    assert(param and param:get_type_definition():get_full_name()=="app.training.UIFlowTrainingMenu.Param",
        "unexpected library view parameter")
    local list=assert(read(param,"_ViewDataList"))
    local count=list:call("get_Count")
    assert(type(count)=="number" and count>=View.COUNT and count<=32,"library view count changed")
    local targets,seen={},{}
    for i=0,count-1 do
        local item=list:call("get_Item",i)
        local data,parent=read(item,"Data"),read(item,"ParentData")
        local index=data and owner.actions[data:get_address()]
        if index and same(parent,owner.page) then
            assert(not seen[index],"duplicate library view")
            seen[index]=true; targets[#targets+1]=item
        end
    end
    assert(#targets==View.COUNT,"library view incomplete")
    local children=assert(read(read(param,"_SecondaryList"),"_Children"))
    local count=children:call("get_Count")
    assert(count>=View.COUNT and count<=32,"library display row count changed")
    local groups={}
    for _,index in ipairs({1,2,8,10}) do
        local group=assert(children:call("get_Item",index-1))
        assert(read(group,"<Index>k__BackingField")==index-1
            and read(group,"<Layout>k__BackingField")==5,"library display row identity changed")
        local focus=read(group,"_FocusIndex")
        assert(focus==0 or ((index==2 or index==8) and focus==4) or ((index==1 or index==10) and focus==1),"unexpected library display variant")
        assert(read(group,"_Children"):call("get_Count")>4,"library display variants missing")
        groups[index]=group
    end
    return targets,groups
end
local function redraw(param,change)
    local targets,groups=redraw_targets(param)
    local previous_pager=owner.pager
    local was_spin=read(owner.pager,"_Type")==1
    local previous_options=read(owner.pager,"_ChildData")
    if not change() then return false end
    bind_rows(owner.page)
    local ok,detail=pcall(function()
        local rows=view.rows()
        for index,group in pairs(groups) do
            if read(group,"_FocusIndex")~=rows[index].kind then
                group:call("ChangeFocusIndex(System.Int32)",rows[index].kind)
            end
        end
        local info=view.paging()
        for _,target in ipairs(targets) do
            if info and same(read(target,"Data"),owner.pager) and read(target,"Index")~=info.index then
                target:set_field("Index",info.index)
            end
            target:set_field("IsUpdate",true)
        end
        -- Showing the SPIN variant does not wire its native input delegates.
        -- Initialize only this owned row when it becomes a spin or changes its
        -- option array; ordinary page changes keep the existing callbacks.
        if info and (not same(previous_pager,owner.pager) or not was_spin
            or not same(previous_options,read(owner.pager,"_ChildData"))) then
            initializing_spin=true
            assert(param:call("InitSpinBox(System.Int32)",view.pager_row()-1)==true,"library page spin initialization failed")
        end
    end)
    initializing_spin=false
    if not ok then failed=true; error(detail) end
    return true
end
local function setup()
    local methods={
        message=method("app.helper.hMsg","GetMessage(System.Guid)"),
        action=method(FUNC,"Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"),
        active=method(FUNC,"GetIsActive(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)"),
        view=method(FUNC,"ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"),
        value=method(FUNC,"IsValueType"),visible=method(FUNC,"GetVisibleCase"),changed=method(FUNC,"IsChangedValue"),
        tab=method("app.training.UIFlowTrainingMenu.Param","ChangeTabIndex(System.Int32)"),
    }
    -- Reset our retained row data before the engine builds the next tab. Never
    -- rebuild the native view or touch another tab's rows from this callback.
    sdk.hook(methods.tab,function(args)
        if not serving() or initializing_spin or next(layout) then return end
        local ok,detail=pcall(function()
            local tm=manager()
            if not live(tm) then return end
            local param=sdk.to_managed_object(args[2])
            if not same(param,read(read(tm,"_UITrainingMenu"),"_ParamData")) then return end
            local before=param:call("get_PrimaryListIndex")
            local target=sdk.to_int64(args[3]) & 0xFFFFFFFF
            local roots=owner.installed
            local count=roots:get_size()
            if type(before)~="number" or before%1~=0 or before<0 or before>=count
                or target>=count or target==before then return end
            if not same(roots:get_element(before),owner.page)
                and not same(roots:get_element(target),owner.page) then return end
            if pager then pager.cancel() end
            view.closed()
            bind_rows(owner.page)
        end)
        if not ok then
            failed=true
            log.error("[NativeLibraryTab] Tab transition stopped: "..tostring(detail))
        end
    end,function(rv) return rv end)
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
        -- Shared permanent string: the native caller never depends on a Lua wrapper.
        local value=Ownership.string(sdk,text)
        if not value then return rv end
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
                        library.status_ok,library.status=false,"操作请求失败，详情见日志"
                        feedback.notify("操作请求失败，配置未修改，请稍后重试")
                        log.error("[NativeLibraryTab] Operation request failed: "..tostring(value))
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
        if initializing_spin or next(layout) then return 0 end
        local item=sdk.to_managed_object(args[5])
        local row=read(item,"Data")
        local index=row and owner.actions[row:get_address()]
        if not index or not same(read(item,"ParentData"),owner.page) then return 0 end
        local command=view.command(index)
        if not command then return 0 end
        local result
        local was_clear=view.confirming_clear()
        if command=="open" or command=="open_slots" or command=="choose" or command=="back"
            or command=="clear" or command=="restore_native" or was_clear then
            redraw(sdk.to_managed_object(args[4]),function()
                result=view.activate(index); return result.redraw or was_clear
            end)
        else result=view.activate(index) end
        if result.notice then feedback.notify(result.notice) end
        local kind=result.operation
        if not kind then return 0 end
        -- Match the established native menu return protocol. The shared Library
        -- queues work; the accepted entry executes it after the menu closes.
        local action
        if kind=="rename" then action=function() return editor.request() end end
        if kind=="slot_name" then action=function() return editor.request(result.slot) end end
        local accepted=feedback.request(kind,action)
        if not accepted then view.cancel_confirmation() end
        return accepted and 1 or 0
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
    local api=setmetatable({hook=function(m,pre,post)
        sdk.hook(m,function(args) if serving() then return pre(args) end end,post)
    end},{__index=sdk})
    local function current()
        if serving() and live(manager()) then return owner end
    end
    pager=Pager.new(api,thread,current,view,redraw,
        function() return not initializing_spin and current()~=nil and Safety.pause_open()==true and not library.has_pending() end,
        function(err) failed=true; log.error("[NativeLibraryTab] Pager stopped: "..tostring(err)) end,
        function() return initializing_spin or next(layout)~=nil or library.has_pending() end)
    pager.install()
end
re.on_pre_application_entry("LateUpdateBehavior",function()
    if stopped or failed then return end
    -- Drop confirmation even when closure falls between the slower mount checks.
    -- This touches Lua state only, never a closed/stale native view.
    if view and serving() then
        local ok,open=pcall(Safety.pause_open)
        if ok and open==false then view.cancel_confirmation() end
    end
    if pager then pager.tick() end
    tick=tick+1
    if feedback and tick%6==0 then
        feedback.tick(presentation_session()~=nil and Safety.is_training_allowed())
    end
    if tick%30~=0 then return end
    local success,detail=pcall(update,setup)
    if not success then
        failed=true
        log.error("[NativeLibraryTab] Stopped; restart required: "..tostring(detail))
    end
end)
re.on_script_reset(function()
    stopped=true
    if pager then pager.cancel() end
    if ticker then ticker.stop() end
    -- Never rewrite a live menu or release native-visible allocations on Reset.
    -- A later Lua state can adopt this GUID-scoped page once the menu is closed.
    if owner then log.warn("[NativeLibraryTab] Reset: root page retained; cold-start acceptance still required") end
end)
return true
