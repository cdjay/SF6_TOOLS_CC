local Manual = require("tools/training_record_bank/manual_runtime")
local Session = require("tools/training_record_bank/session")
local Bank = require("tools/training_record_bank/core")
local Codec = require("tools/training_record_bank/json_codec")
local function clone(doc) return assert(Bank.open(doc)).snapshot() end
local function fixture()
    local reads, writes, prepares, attachments, retirements, captures = 0, 0, 0, 0, 0, 0
    local ctx = {allowed=true, idle=true, session={}, data={}, fighter_id=28}
    local bank = assert(Bank.open(assert(Bank.empty(28))))
    bank.add_slot({name="one",is_valid=true,is_active=true,weight=1,frame=1,input_buff={16},fields={},input_fields={}})
    local bytes, version = Codec.encode(bank.snapshot()), string.rep("a",64)
    local storage = {
        read=function(id) reads=reads+1; assert(id==28); return bytes,version end,
        replace=function(id, value, expected)
            assert(id==28 and version==expected); writes=writes+1
            bytes,version=value,string.format("%064x",writes); return bytes,version
        end,
    }
    local native, live = {}, nil
    function native.prepare(doc, owner)
        prepares=prepares+1
        assert(live == nil or live.attached)
        return {document=clone(doc),owner=owner,guard_ready=true}
    end
    function native.attach(lease) attachments=attachments+1; lease.attached=true; live=lease; return true end
    function native.retire(lease)
        retirements=retirements+1; lease.attached=false
        if live==lease then live=nil end
        return true
    end
    function native.discard_prepared(lease) assert(not lease.attached); return true end
    function native.capture(lease)
        captures=captures+1; local doc=clone(lease.document); doc.records[1].weight=7; return doc
    end
    local m = Manual.new(function() return Session.new(Codec,storage) end, native, function() return ctx end)
    return m, native, storage, ctx, function()
        return {reads=reads,writes=writes,prepares=prepares,attachments=attachments,retirements=retirements,captures=captures}
    end
end
local passed=0
local function test(name, fn) local ok,err=pcall(fn); assert(ok,name..": "..tostring(err)); passed=passed+1 end
test("entry and idle ticks never load write or allocate",function()
    local m,_,_,_,stats=fixture()
    for _=1,1000 do assert(m.tick()) end
    assert(m.state()=="unloaded" and not m.save())
    local s=stats(); assert(s.reads==0 and s.writes==0 and s.prepares==0)
end)
test("explicit load replaces runtime from file and save is explicit",function()
    local m,_,_,_,stats=fixture(); assert(m.load()); assert(m.state()=="active")
    for _=1,1000 do assert(m.tick()) end
    assert(stats().reads==1 and stats().writes==0 and stats().captures==0)
    assert(m.save()); assert(stats().writes==1 and m.snapshot().records[1].weight==7)
end)
test("character switch discards without automatic save or new load",function()
    local m,_,_,ctx,stats=fixture(); m.load(); ctx.fighter_id=19
    assert(m.tick() and m.state()=="unloaded")
    assert(stats().writes==0 and stats().reads==1 and stats().retirements==1)
end)
test("session exit discards without writing",function()
    local m,_,_,ctx,stats=fixture(); m.load(); ctx.allowed=false
    assert(m.tick() and not m.snapshot()); assert(stats().writes==0)
end)
test("busy training rejects loading saving and manual unloading",function()
    local m,_,_,ctx,stats=fixture(); m.load(); ctx.idle=false
    assert(not m.load() and not m.save() and not m.unload())
    assert(stats().reads==1 and stats().writes==0 and stats().captures==0)
end)
test("read or prepare failure keeps previous active configuration",function()
    local m,native,storage,_,stats=fixture(); m.load()
    storage.read=function() error("read failure") end
    assert(not m.load() and m.state()=="active" and stats().retirements==0)
    storage.read=function() return Codec.encode(assert(Bank.empty(28))),string.rep("a",64) end
    native.prepare=function() error("prepare failure") end
    assert(not m.load() and m.state()=="active" and stats().retirements==0)
end)
test("save protection is mandatory before attach",function()
    local m,native,_,_,stats=fixture()
    native.prepare=function() return {guard_ready=false} end
    assert(not m.load() and m.state()=="unloaded" and stats().attachments==0)
end)
test("partial attach failure retires candidate and never auto retries",function()
    local m,native,_,_,stats=fixture()
    local attach=native.attach
    native.attach=function(lease,ctx) attach(lease,ctx); error("partial attach") end
    assert(not m.load() and m.state()=="unloaded")
    assert(stats().retirements==1)
    m.tick(); assert(stats().attachments==1)
end)
test("unconfirmed native retirement blocks further operations",function()
    local m,native,_,ctx,stats=fixture(); m.load()
    native.retire=function() return false,"cannot safely detach" end
    ctx.fighter_id=19
    assert(not m.tick() and m.state()=="blocked")
    assert(not m.load() and not m.save() and not m.unload())
    assert(stats().reads==1 and stats().writes==0)
end)
test("invalid captured bank never reaches file writer",function()
    local m,native,_,_,stats=fixture(); m.load()
    native.capture=function() return Bank.empty(19) end
    assert(not m.save() and stats().writes==0 and m.snapshot().fighter_id==28)
end)
test("uncertain disk result requires manual reload not repeated writes",function()
    local m,_,storage,_,stats=fixture(); m.load()
    local replace=storage.replace
    storage.replace=function(...) replace(...); error("lost reply") end
    assert(not m.save() and not m.save() and stats().writes==1)
    assert(m.load()); storage.replace=replace; assert(m.save())
end)
test("context change during preparation never attaches stale candidate",function()
    local m,native,_,ctx,stats=fixture()
    local prepare=native.prepare
    native.prepare=function(...) local lease=prepare(...); ctx.fighter_id=19; return lease end
    assert(not m.load() and stats().attachments==0)
end)
test("nested commands cannot reenter a native operation",function()
    local m,native=fixture(); local prepare=native.prepare
    native.prepare=function(...)
        assert(not m.load() and not m.save() and not m.unload())
        return prepare(...)
    end
    assert(m.load())
end)
test("reenter training reloads remembered file and drops unsaved runtime state",function()
    local m,_,_,ctx,stats=fixture(); assert(m.load())
    ctx.allowed=false; assert(m.tick() and m.state()=="unloaded")
    assert(stats().writes==0)
    ctx.allowed=true; ctx.session={}; ctx.data={}
    assert(m.tick() and m.state()=="active")
    assert(stats().reads==2 and stats().attachments==2 and stats().writes==0)
    assert(m.snapshot().records[1].weight==1)
    for _=1,100 do assert(m.tick()) end
    assert(stats().reads==2)
end)
test("failed automatic reload is attempted only once per entry",function()
    local m,_,storage,ctx=fixture(); m.load(); ctx.allowed=false; m.tick()
    local tries=0
    storage.read=function() tries=tries+1; error("missing selected file") end
    ctx.allowed=true; ctx.session={}; ctx.data={}
    assert(not m.tick() and tries==1)
    for _=1,100 do m.tick() end
    assert(tries==1 and m.state()=="unloaded")
end)
test("manual unload suppresses reload until next training entry",function()
    local m,_,_,ctx,stats=fixture(); m.load(); assert(m.unload())
    for _=1,100 do m.tick() end
    assert(m.state()=="unloaded" and stats().reads==1)
    ctx.allowed=false; m.tick(); ctx.allowed=true; m.tick()
    assert(m.state()=="active" and stats().reads==2)
end)
test("automatic load waits for idle and never runs outside training",function()
    local m,_,_,ctx,stats=fixture(); m.load(); ctx.allowed=false; m.tick()
    for _=1,100 do m.tick() end
    assert(stats().reads==1)
    ctx.allowed=true; ctx.idle=false
    for _=1,100 do m.tick() end
    assert(stats().reads==1)
    ctx.idle=true; assert(m.tick() and stats().reads==2)
end)
test("deleted remembered file is not loaded as an empty replacement",function()
    local m,_,storage,ctx,stats=fixture(); m.load(); ctx.allowed=false; m.tick()
    storage.read=function() return nil,nil end
    ctx.allowed=true
    assert(not m.tick() and m.state()=="unloaded" and stats().attachments==1)
end)
print(passed.." training lifecycle contract tests passed (fake native adapter)")
