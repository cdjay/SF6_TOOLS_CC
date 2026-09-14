local Lifecycle=require("tools/training_record_bank/native_lifecycle")
local function fixture()
    local thread_id=1
    local threads={get_id=function() return thread_id end}
    local life=Lifecycle.new(threads)
    local calls={retire=0,close=0}
    local ready={retire=false,dispose=false}
    local mount={
        retire=function() assert(thread_id==1); calls.retire=calls.retire+1; return true end,
        close=function() assert(thread_id==1); calls.close=calls.close+1; return true end,
    }
    local gates={can_retire=function() return ready.retire end,can_dispose=function() return ready.dispose end}
    local token=assert(life.watch(77,mount,gates))
    return {life=life,threads=threads,calls=calls,ready=ready,mount=mount,gates=gates,token=token,
        thread=function(id) thread_id=id end}
end
local count=0
local function test(name,fn) local ok,err=pcall(fn); assert(ok,name..": "..tostring(err)); count=count+1 end
test("observed worker sequence does not call native objects or treat Save POST as completion",function()
    local f=fixture()
    f.thread(2); assert(f.life.notify(f.token,"save_pre")); assert(f.life.notify(f.token,"save_post"))
    f.thread(1); assert(f.life.tick() and f.calls.retire==0 and f.calls.close==0)
    f.thread(3); assert(f.life.notify(f.token,"save_data_pre")); assert(f.life.notify(f.token,"save_data_post"))
    f.thread(4); assert(f.life.notify(f.token,"release_pre")); assert(f.life.notify(f.token,"release_post"))
    assert(f.calls.retire==0 and f.calls.close==0 and not f.life.tick())
    f.thread(1); assert(f.life.tick() and f.calls.retire==0)
    f.ready.retire=true; assert(f.life.tick() and f.calls.retire==1 and f.calls.close==0)
    for _=1,100 do assert(f.life.tick()) end
    assert(f.calls.retire==1 and f.calls.close==0)
    f.ready.dispose=true; assert(f.life.tick() and f.calls.close==1 and f.life.state()=="closed")
end)
test("duplicate release notifications are bounded and retire only once",function()
    local f=fixture(); f.ready.retire=true; f.ready.dispose=true
    f.thread(4)
    for _=1,10000 do assert(f.life.notify(f.token,"release_post")) end
    f.thread(1); assert(f.life.tick() and f.life.tick())
    assert(f.calls.retire==1 and f.calls.close==1)
end)
test("stale session token is rejected even when manager address is reused",function()
    local f=fixture(); f.ready.retire=true; f.ready.dispose=true
    assert(f.life.request_retire(f.token) and f.life.tick())
    local next_token=assert(f.life.watch(77,f.mount,f.gates))
    assert(next_token~=f.token and not f.life.notify(f.token,"release_post"))
    assert(f.life.capture(77)==next_token and not f.life.capture(88))
    assert(f.life.tick() and f.calls.retire==1)
end)
test("unknown events and caller-edited status do not authorize cleanup",function()
    local f=fixture()
    assert(not f.life.notify(f.token,"storage_complete"))
    local status=f.life.status(); status.facts.release_post=true; status.requested=true
    assert(f.life.tick() and not f.life.status().requested and f.calls.retire==0)
end)
for _,operation in ipairs({"retire","close"}) do
    test(operation.." exception retains ownership and is not retried",function()
        local f=fixture(); f.ready.retire=true; f.ready.dispose=true
        f.mount[operation]=function() f.calls[operation]=f.calls[operation]+1; error("native failure") end
        assert(f.life.notify(f.token,"release_post"))
        assert(not f.life.tick() and f.life.state()=="blocked")
        for _=1,10 do assert(not f.life.tick()) end
        assert(f.calls[operation]==1 and not f.life.watch(78,f.mount,f.gates))
    end)
end
test("unconfirmed gate blocks instead of treating nil as wait or success",function()
    local f=fixture(); f.gates.can_retire=function() return nil,"unknown owner" end
    f.life.request_retire(f.token)
    assert(not f.life.tick() and f.life.state()=="blocked" and f.calls.retire==0)
end)
test("reentrant tick cannot repeat native retirement",function()
    local f=fixture(); f.ready.retire=true
    f.mount.retire=function()
        f.calls.retire=f.calls.retire+1
        assert(not f.life.tick())
        f.life.notify(f.token,"release_post")
        return true
    end
    f.life.request_retire(f.token)
    assert(f.life.tick() and f.calls.retire==1 and f.life.state()=="retired")
end)
test("hook router leaves every argument and return untouched, including nested foreign calls",function()
    local f=fixture(); local hooks,callback,stack={},{},{}
    f.threads.get_hook_storage=function() return assert(stack[#stack]) end
    local api={
        find_type_definition=function() return {get_method=function(_,name) return name end} end,
        hook=function(name,pre,post) hooks[name]={pre=pre,post=post} end,
        to_int64=function(value) return value end,
    }
    Lifecycle.install(api,{on_application_entry=function(name,fn) assert(name=="UpdateBehavior"); callback=fn end},f.threads,f.life)
    local function call(name,owner,retval,nested)
        stack[#stack+1]={}
        local args={99,owner,123}
        assert(hooks[name].pre(args)==nil and args[1]==99 and args[2]==owner and args[3]==123)
        if nested then nested() end
        assert(hooks[name].post(retval)==retval)
        stack[#stack]=nil
    end
    f.thread(2); call("Save",77,55,function() call("Release",88,66) end)
    assert(not f.life.status().requested and f.life.status().facts.save_post)
    f.thread(3); call("SaveSaveData",77,987)
    f.thread(4); call("Release",77,0)
    assert(f.calls.retire==0)
    f.thread(1); f.ready.retire=true; callback()
    assert(f.calls.retire==1 and f.calls.close==0)
end)
test("hook observation failure is visible and blocks new ownership without native calls",function()
    local f=fixture(); f.thread(4); f.life.hook_fault()
    assert(f.life.state()=="blocked" and f.calls.retire==0 and f.calls.close==0)
    f.thread(1)
    assert(not f.life.tick() and not f.life.watch(88,f.mount,f.gates))
end)
test("returned native failure is not retried",function()
    local f=fixture(); f.ready.retire=true
    f.mount.retire=function() f.calls.retire=f.calls.retire+1; return false,"restore failed" end
    f.life.notify(f.token,"release_post")
    assert(not f.life.tick() and not f.life.tick() and f.calls.retire==1 and f.calls.close==0)
end)
print("PASS "..count.." cross-thread lifecycle cases (simulated callbacks; no save publication)")
