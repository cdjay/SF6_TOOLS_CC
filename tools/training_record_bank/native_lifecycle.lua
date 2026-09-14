-- Cross-thread hook notifications contain only an opaque session token and a
-- fixed event name. Native operations run only in tick on the captured thread.
-- This is not a native-save publication or consumer-completion authority.
local M={}
local EVENTS={save_pre=true,save_post=true,save_data_pre=true,save_data_post=true,
    release_pre=true,release_post=true}

function M.new(threads)
    local owner_thread=assert(threads.get_id(),"update thread unavailable")
    local active,busy=nil,false
    local self={}
    local function on_thread() return threads.get_id()==owner_thread end
    local function fail(reason)
        active.phase="blocked"
        active.reason=tostring(reason or "native operation unconfirmed")
        return false,active.reason
    end
    function self.watch(owner_address,mount,gates)
        if not on_thread() then return nil,"watch requires update thread" end
        if busy or (active and active.phase~="closed") then return nil,"previous native owner retained" end
        if type(owner_address)~="number" or owner_address<=0 or owner_address%1~=0 then
            return nil,"invalid manager address"
        end
        for _,key in ipairs({"retire","close"}) do
            assert(type(mount[key])=="function","missing mount operation: "..key)
        end
        for _,key in ipairs({"can_retire","can_dispose"}) do
            assert(type(gates[key])=="function","missing lifetime gate: "..key)
        end
        local token={}
        active={token=token,address=owner_address,mount=mount,gates=gates,
            phase="watching",requested=false,facts={}}
        return token
    end
    -- Called by a hook preamble. The token must be kept in invocation-local
    -- storage, not looked up again in the postamble (addresses can be reused).
    function self.capture(owner_address)
        if active and active.phase~="closed" and active.address==owner_address then return active.token end
    end
    function self.notify(token,event)
        if not active or token~=active.token or active.phase=="closed" or not EVENTS[event] then return false end
        active.facts[event]=true
        if event=="release_post" then active.requested=true end
        return true
    end
    function self.request_retire(token)
        if not on_thread() then return false,"retirement request requires update thread" end
        if not active or active.token~=token or active.phase=="closed" then return false,"inactive session" end
        active.requested=true
        return true
    end
    function self.hook_fault()
        if active and active.phase~="closed" then
            -- Record only a fixed diagnostic from workers, never log arbitrary
            -- native errors or guess at cleanup from the hook thread.
            active.phase="blocked"
            active.reason="native lifecycle hook observation failed"
        end
    end
    local function facts()
        local result={}
        for key,value in pairs(active.facts) do result[key]=value end
        return result
    end
    function self.tick()
        if not active or active.phase=="closed" then return true end
        if not on_thread() then return false,"native lifecycle tick requires update thread" end
        if busy then return false,"lifecycle operation in progress" end
        if active.phase=="blocked" then return false,active.reason end
        if not active.requested then return true end
        busy=true
        local ok,result,reason=pcall(function()
            if active.phase=="watching" then
                local ready,err=active.gates.can_retire(facts())
                if ready==false then return true,"waiting for safe retirement" end
                if ready~=true then return fail(err or "retirement gate unconfirmed") end
                -- Mark before calling native code. A throwing or partially
                -- completed operation must never be automatically retried.
                active.phase="retiring"
                local retired,retire_err=active.mount.retire()
                if retired~=true then return fail(retire_err) end
                active.phase="retired"
            end
            if active.phase=="retired" then
                local ready,err=active.gates.can_dispose(facts())
                if ready==false then return true,"waiting for native consumers" end
                if ready~=true then return fail(err or "consumer release unconfirmed") end
                active.phase="disposing"
                local closed,close_err=active.mount.close()
                if closed~=true then return fail(close_err) end
                active.phase="closed"
                active.mount,active.gates=nil,nil
            end
            return true
        end)
        busy=false
        if not ok then return fail(result) end
        return result,reason
    end
    function self.state() return active and active.phase or "idle" end
    function self.status()
        return {state=self.state(),requested=active and active.requested or false,
            facts=active and facts() or {},reason=active and active.reason}
    end
    return self
end

-- Install once per Lua state, not once per training entry. It never skips a
-- method or replaces a save return. Publication still needs a separate guard.
function M.install(api,callbacks,threads,life)
    local td=assert(api.find_type_definition("app.training.TrainingManager"))
    local specs={{"Save","save"},{"SaveSaveData","save_data"},{"Release","release"}}
    for _,spec in ipairs(specs) do spec[3]=assert(td:get_method(spec[1]),"missing lifecycle method") end
    for _,spec in ipairs(specs) do
        api.hook(spec[3],function(args)
            local ok=pcall(function()
                local token=life.capture(api.to_int64(args[2]))
                threads.get_hook_storage().sf6cc_record_bank_lifecycle=token
                if token then life.notify(token,spec[2].."_pre") end
            end)
            if not ok then life.hook_fault() end
        end,function(retval)
            local ok=pcall(function()
                local token=threads.get_hook_storage().sf6cc_record_bank_lifecycle
                if token then life.notify(token,spec[2].."_post") end
            end)
            if not ok then life.hook_fault() end
            return retval
        end)
    end
    callbacks.on_application_entry("UpdateBehavior",function() life.tick() end)
end
return M
