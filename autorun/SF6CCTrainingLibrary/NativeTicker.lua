-- Native ticker route adapted from WTT Training_ScriptManager (MIT).
-- Copyright (c) 2026 Wael Hadjmouldi
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local Ownership=require("SF6CCTrainingLibrary/NativeOwnership")
local M={}
function M.new(deps)
    local api,threads=deps.api,deps.threads
    local clock=deps.clock or os.clock
    local queue,owned={},{}
    local stopped,failed,ready=false,false,false
    local get_manager,last_send,last_text=nil,-math.huge,nil
    local self={}
    local function setup()
        local td=assert(api.find_type_definition("app.TickerRequestData"))
        assert(td:get_method("Init"))
        get_manager=assert(assert(api.find_type_definition("app.helper.hTicker")):get_method("get_Manager"))
        api.hook(assert(td:get_method("GetMessage")),function(args)
            local st=threads.get_hook_storage(); st.sf6cc_library_ticker_text=nil
            if stopped or next(owned)==nil then return end
            local req=api.to_managed_object(args[2])
            local item=req and owned[req:get_address()]
            if item then
                st.sf6cc_library_ticker_text=item.text
                return api.PreHookResult.SKIP_ORIGINAL
            end
        end,function(rv)
            local text=threads.get_hook_storage().sf6cc_library_ticker_text
            if text==nil then return rv end
            local value=Ownership.string(api,text)
            if not value then return rv end
            return api.to_ptr(value)
        end)
        ready=true
    end
    local function halt(err)
        failed=true; queue={}
        if deps.report then deps.report("[NativeLibraryTicker] Stopped: "..tostring(err)) end
    end
    function self.prepare()
        if stopped or failed then return false end
        if ready then return true end
        local ok,err=pcall(setup)
        if not ok then halt(err) end
        return ok
    end
    function self.enqueue(text)
        if stopped or failed or type(text)~="string" or text=="" then return false end
        text=text:gsub("[<>%c]"," ")
        -- Consecutive identical clicks do not fill the native request queue.
        if queue[#queue]==text then return true end
        if #queue>=20 then table.remove(queue,1) end
        queue[#queue+1]=text
        return true
    end
    function self.clear()
        -- Submitted requests belong to the native queue. Keep their text/lifetime
        -- until IsDisplayEnd; a scene transition must not invalidate GetMessage.
        queue={}; last_text=nil; last_send=-math.huge
    end
    function self.discard(text)
        -- Withdraw only unsent Lua messages. Never touch an in-flight native
        -- request or its text/ownership when the operation advances.
        for i=#queue,1,-1 do
            if queue[i]==text then table.remove(queue,i) end
        end
    end
    local function dispatch()
        local count=0
        for address,item in pairs(owned) do
            if item.request:get_field("IsDisplayEnd")==true then owned[address]=nil
            else count=count+1 end
        end
        if #queue==0 or count>=8 then return end
        local now=clock()
        if now-last_send<0.25 then return end
        if queue[1]==last_text and now-last_send<1 then table.remove(queue,1); return end
        local manager=get_manager:call(nil)
        if not manager then return end
        -- WTT's initialized base request; never call a ticker/UI update manually.
        -- Polled for IsDisplayEnd on later updates, so it keeps a permanent reference.
        local req=Ownership.instance(api,"app.TickerRequestData",true)
        req:call("Init",112,nil)
        req:set_field("TickerId",1)
        req:set_field("Category",6)
        req:set_field("DisplaySecond",4.0)
        req:set_field("IsForceDisplay",true)
        req:set_field("IsDisplayHistory",false)
        req:set_field("IsClearWhenSystemTransition",true)
        local text=queue[1]
        owned[req:get_address()]={request=req,text=text}
        manager:call("RequestShowTicker(app.TickerRequestData)",req)
        table.remove(queue,1)
        last_send,last_text=now,text
    end
    -- Called only from the owner's LateUpdateBehavior scope, never a menu hook.
    function self.tick(allowed)
        if stopped or failed then return end
        if not allowed then self.clear(); return end
        if not ready and (#queue==0 or not self.prepare()) then return end
        local ok,err=pcall(dispatch)
        if not ok then halt(err) end
    end
    function self.stop() stopped=true; queue={} end
    function self.pending_count() return #queue end
    return self
end
return M
