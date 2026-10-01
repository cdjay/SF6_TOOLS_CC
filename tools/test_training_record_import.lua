-- Import boundary regression: captured 170/262-frame inputs into lazy empty slots.
package.path = "autorun/?.lua;" .. package.path
local passed = 0
local function test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end
local function fixture(capacity, fault, native_slots)
    native_slots = native_slots or 8
    local stats = { reads = 0, backups = 0, starts = {}, writes = 0, tick = 0, forces = 0 }
    local function object(fields)
        return {
            get_field = function(_, key) return fields[key] end,
            set_field = function(_, key, value) fields[key] = value end,
            get_type_definition = function()
                return { get_field = function(_, key) return fields[key] ~= nil and {} or nil end,
                    get_fields = function()
                        local result = {}
                        for key in pairs(fields) do result[#result + 1] = {
                            get_name = function() return key end,
                        } end
                        return result
                    end }
            end,
        }
    end
    local function collection(values)
        return { call = function(_, name, index, value)
            if name == "set_Item" then values[index] = value; return end
            assert(name == "get_Item"); return values[index]
        end }
    end
    local slots, imported, capacities = {}, {}, {}
    for slot = 1, native_slots do
        capacities[slot] = fault == "all_empty" and 0 or ((slot == 4 or slot == 5) and capacity or 3600)
        local buffer = { call = function(_, method, value, index)
            if fault == "capacity_read" then error("unreadable capacity") end
            if method == "get_Length" then return capacities[slot] end
            if method == "GetValue" then return object({mValue=16}) end
            assert(method == "SetValue" and index < capacities[slot])
            assert(value == 16); stats.writes = stats.writes + 1
        end }
        slots[slot - 1] = object({ Frame = 0, Weight = 1, IsValid = false, IsActive = false,
            InputData = object({ buff = buffer, Num = 0 }) })
    end
    for _, spec in ipairs({ { 4, 170 }, { 5, 262 } }) do
        local inputs = {}; for i = 1, spec[2] do inputs[i] = 16 end
        imported[#imported + 1] = { slot = spec[1], is_valid = true, frame = spec[2],
            input_num = spec[2], input_buff = inputs }
    end
    local data = { schema = "sf6cc.dynamic_records.v1", fighter_id = 28, source_player = "P2", slots = imported }
    local native_bank = collection(slots)
    native_bank.get_size = function() return native_slots end
    local fighter = object({ RecordSlots = native_bank, RecordSlot = 2 })
    local settings = object({ FighterDataList = collection({ [28] = fighter }), RecordStartType = 2 })
    local reversal_fields = {}
    data.reversals = {}
    for key, field in pairs({ down = "DownReversalDatas", guard = "GuardReversalDatas", damage = "DamageReversalDatas" }) do
        local group = {}; data.reversals[key] = {}
        for slot = 1, 10 do
            group[slot - 1] = object({ IsActive = false, Type = 0, SkillIndex = 0 })
            data.reversals[key][slot] = { slot = slot, active = false, type = 0, skill_index = 0 }
        end
        reversal_fields[field] = collection(group)
    end
    local guard_fields = object({ GuardType = 0, GuardWeight = 40, GuardCount = 2,
        IsGuardSwitching = false, GuardOnlyType = 0 })
    stats.guard_fields = guard_fields
    local td = object({ RecordSetting = settings,
        GuardSetting = object({ DummyData = guard_fields }),
        ReversalSetting = object({ FighterDataList = collection({ [28] = object(reversal_fields) }), ReversalType = 0 }) })
    local reversal = object({ _tData = td }); reversal.call = function() end
    local rec = object({ _tData = td })
    local ctx = { allowed = true, data = td, fighter_id = 28, busy = false,
        recording = false, replay = false, combo_busy = false, menu_closed = true }
    local manager = object({ _tData = td })
    ctx.session, ctx.record_func = manager, rec
    local active_slot, idle_tick
    manager.call = function(_, name, state)
        if name == "get_RecordFunc" then return rec end
        if name == "get_ReversalFunc" then return reversal end
        assert((name == "ChangeState" or name == "ChangeState(app.training.TrainingManager.ETrainingState)")
            and (state == 3 or state == 4))
        if state == 3 then ctx.recording, ctx.busy = true, true else idle_tick = stats.tick end
    end
    rec.call = function(_, name, a, b)
        if name == "ChangeRecordStartSetting" then settings:set_field("RecordStartType", a)
        elseif name == "SetStartRecord" then
            assert(a == 16); active_slot = b + 1
            stats.starts[#stats.starts + 1] = active_slot
            fighter:set_field("RecordSlot", b)
            if fault == "start" then error("start failed") end
        elseif name == "StopRecord" then
            assert(idle_tick, "must return to idle before stopping")
            ctx.recording, ctx.busy = false, false
            if fault ~= "no_capacity" then capacities[active_slot] = 3600 end
        elseif name == "ForceApply" then stats.forces = stats.forces + 1
        else assert(name == "ReleaseDummyData" or name == "CopyDummyData", name) end
    end
    local env = setmetatable({
        sdk = { get_managed_singleton = function() return manager end,
            create_uint16 = function(value) return value end },
        json = { load_file = function() stats.reads = stats.reads + 1; return data end,
            dump_file=function(_,snapshot) stats.exported=snapshot; return true end }, fs = {},
    }, { __index = _G })
    _G.sdk = env.sdk
    local backend = assert(loadfile(os.getenv("SF6CC_DYNAMIC_RECORDS_TEST_SOURCE")
        or "autorun/SF6CCTrainingLibrary/Records.lua", "t", env))()
    backend.get_context = function() return { fighter_id = 28, source_player = "P2" } end
    backend.backup_current = function() stats.backups = stats.backups + 1; return true, "saved", "backup.json" end
    local function advance(task)
        stats.tick = stats.tick + 1
        return task.tick(ctx)
    end
    return backend, stats, ctx, advance, data, settings, fighter, slots, env, guard_fields
end
test("clear empties all eighty recordings and thirty reversals without replacing the bank or files", function()
    local records, stats, ctx, _, _, _, fighter, slots = fixture(3600, nil, 80)
    local bank = fighter:get_field("RecordSlots")
    local reversals = ctx.data:get_field("ReversalSetting"):get_field("FighterDataList"):call("get_Item", 28)
    for i = 1, 80 do
        local slot = slots[i - 1]
        slot:set_field("Frame", 120); slot:set_field("Weight", 5)
        slot:set_field("IsValid", true); slot:set_field("IsActive", true)
        slot:get_field("InputData"):set_field("Num", 120)
        assert(records.set_slot_name(i, "测试" .. i))
    end
    for _, field in ipairs({ "DownReversalDatas", "GuardReversalDatas", "DamageReversalDatas" }) do
        for i = 0, 9 do
            local slot = reversals:get_field(field):call("get_Item", i)
            for key, value in pairs({ IsActive = true, IsValid = true, IsFrame = true,
                Type = 1, SkillIndex = 79, Delay = 12, Count = 3, Level = 2, Frame = 7 }) do
                slot:set_field(key, value)
            end
        end
    end
    local ok, msg = records.clear_current_configuration()
    assert(ok, msg)
    assert(msg:find("80", 1, true) and msg:find("30", 1, true))
    assert(fighter:get_field("RecordSlots") == bank and bank:get_size() == 80)
    for i = 1, 80 do
        local slot = slots[i - 1]
        assert(slot:get_field("Frame") == 0 and slot:get_field("Weight") == 1)
        assert(not slot:get_field("IsValid") and not slot:get_field("IsActive"))
        assert(slot:get_field("InputData"):get_field("Num") == 0 and records.get_slot_name(i) == "")
    end
    for _, field in ipairs({ "DownReversalDatas", "GuardReversalDatas", "DamageReversalDatas" }) do
        for i = 0, 9 do
            local slot = reversals:get_field(field):call("get_Item", i)
            assert(not slot:get_field("IsActive") and slot:get_field("Type") == -1 and slot:get_field("SkillIndex") == -1)
        end
    end
    assert(stats.backups == 1 and stats.forces == 1 and stats.reads == 0 and not stats.exported)
    assert(#stats.starts == 0 and stats.writes == 0)
end)

test("clear stops before native writes when the existing automatic backup fails", function()
    local records, stats, _, _, _, _, _, slots = fixture(3600)
    slots[0]:set_field("Frame", 100)
    records.backup_current = function() return false, "backup failure" end
    assert(not records.clear_current_configuration())
    assert(slots[0]:get_field("Frame") == 100 and stats.forces == 0)
end)

test("empty slots initialize then import once from one read and one backup", function()
    local records, stats, ctx, tick, _, settings, fighter, slots = fixture(0)
    local ok, msg, _, _, receipt = records.begin_import("config.json", { force_apply_after_import = true }, ctx)
    assert(ok, msg)
    assert(receipt.kind == "initializing" and stats.writes == 0 and #stats.starts == 0)
    local done, success, result
    for _ = 1, 100 do done, success, result = tick(receipt.task); if done then break end end
    assert(done and success, result)
    assert(table.concat(stats.starts, ",") == "4,5")
    assert(stats.writes == 432 and stats.backups == 1 and stats.reads == 1)
    assert(settings:get_field("RecordStartType") == 2 and fighter:get_field("RecordSlot") == 2)
    assert(slots[3]:get_field("Frame") == 170 and slots[4]:get_field("Frame") == 262)
    local count = stats.writes; tick(receipt.task); assert(stats.writes == count)
end)
test("already allocated buffers stay synchronous", function()
    local records, stats, ctx = fixture(3600)
    local ok, msg, _, _, receipt = records.begin_import("config.json", {}, ctx)
    assert(ok, msg); assert(receipt.kind == "import" and #stats.starts == 0 and stats.writes == 432)
end)

test("B edits cannot leak into A after initializing eighty empty slots", function()
    local records,stats,ctx,tick,data,_,_,slots=fixture(0,"all_empty",80)
    data.schema="sf6cc.training_setup.v2"
    data.slots={}; data.annotations={record_slots={}}
    for i=1,80 do
        data.slots[i]={slot=i,is_valid=true,is_active=true,frame=1,input_num=1,input_buff={16}}
        data.annotations.record_slots[i]={slot=i,text="A"..i}
    end
    records.set_slot_name(9,"B edited")
    local ok,msg,_,_,receipt=records.begin_import("A.json",{},ctx)
    assert(ok,msg)
    assert(receipt and receipt.kind=="initializing" and receipt.count==80)
    assert(records.get_slot_name(9)=="B edited","pending import changed names early")
    local done,success,result
    for _=1,1800 do done,success,result=tick(receipt.task); if done then break end end
    assert(done and success,result)
    assert(#stats.starts==80 and stats.writes==80 and stats.reads==1)
    for i=1,80 do
        assert(records.get_slot_name(i)=="A"..i and slots[i-1]:get_field("Frame")==1)
        data.annotations.record_slots[i].text="B"..i
    end
    records.set_slot_name(9,"A edited")
    ok,msg=records.begin_import("B.json",{},ctx); assert(ok,msg)
    for i=1,80 do assert(records.get_slot_name(i)=="B"..i) end
    assert(data.annotations.record_slots[9].text=="B9","edit mutated imported file data")
end)

test("initialization rejects overflow, duplicate slots and invalid lengths before native calls",function()
    local Import=require("SF6CCTrainingLibrary/TrainingRecordImport")
    local function denied(slots) assert(not pcall(Import.new,{}, {},slots)) end
    local slots={}; for i=1,81 do slots[i]={slot=i,required=1} end
    denied(slots); denied({{slot=81,required=1}})
    denied({{slot=1,required=1},{slot=1,required=1}})
    denied({{slot=1,required=0}}); denied({{slot=1,required=3601}})
end)
test("unreadable capacity is not treated as an uninitialized slot", function()
    local records, stats, ctx = fixture(0, "capacity_read")
    local ok = records.begin_import("config.json", {}, ctx)
    assert(not ok and #stats.starts == 0 and stats.writes == 0)
end)
test("invalid input and oversized buffers never start native recording", function()
    for _, invalid in ipairs({ "input", "size" }) do
        local records, stats, ctx, _, data = fixture(0)
        if invalid == "input" then data.slots[2].input_buff[3] = "bad"
        else for i = 263, 3601 do data.slots[2].input_buff[i] = 16 end end
        local ok = records.begin_import("config.json", {}, ctx)
        assert(not ok and #stats.starts == 0 and stats.writes == 0)
    end
end)
test("lost environment abandons native references and never imports", function()
    local records, stats, ctx, tick = fixture(0)
    local _, _, _, _, receipt = records.begin_import("config.json", {}, ctx)
    tick(receipt.task)
    ctx.session = {}
    local done, ok = tick(receipt.task)
    assert(done and not ok and stats.writes == 0 and #stats.starts == 1)
end)
test("capacity recheck rejects allocation failure without retry or partial import", function()
    local records, stats, ctx, tick = fixture(0, "no_capacity")
    local _, _, _, _, receipt = records.begin_import("config.json", {}, ctx)
    local done, ok
    for _ = 1, 100 do done, ok = tick(receipt.task); if done then break end end
    assert(done and not ok and #stats.starts == 1 and stats.writes == 0)
end)
test("pause cancels initialization and restores original settings", function()
    local records, stats, ctx, tick, _, settings = fixture(0)
    local _, _, _, _, receipt = records.begin_import("config.json", {}, ctx)
    tick(receipt.task); ctx.menu_closed = false
    local done, ok
    for _ = 1, 10 do done, ok = tick(receipt.task); if done then break end end
    assert(done and not ok and stats.writes == 0 and not ctx.recording)
    assert(settings:get_field("RecordStartType") == 2)
end)
test("synchronous direct callers remain fail-closed on empty buffers", function()
    local records, stats = fixture(0)
    local ok, msg = records.import_from_file("config.json")
    assert(not ok and msg:find("capacity 0", 1, true) and stats.writes == 0)
end)
test("shared controller keeps selection locked and publishes completion only once", function()
    local records, stats, ctx = fixture(0)
    records.list_configs = function() return { { path = "config.json", filename = "config.json" } } end
    records.read_config_metadata = function() return { fighter_id = 28, source_player = "P2" } end
    local library = dofile(os.getenv("SF6CC_TRAINING_LIBRARY_TEST_SOURCE")
        or "autorun/SF6CCTrainingLibrary/Library.lua").new(records, function() return ctx end)
    library.refresh(); local revision = library.result_revision
    assert(library.request("import")); library.tick()
    assert(library.has_pending() and not library.select(1) and not library.request("export"))
    assert(library.result_revision == revision and stats.writes == 0)
    for _ = 1, 100 do stats.tick = stats.tick + 1; library.tick() end
    assert(not library.has_pending() and library.status_ok, library.status)
    assert(library.result_revision == revision + 1 and stats.writes == 432)
    assert(library.status:find("已导入 2 个录像栏位", 1, true))
    assert(library.status:find("已初始化 2 个空栏位", 1, true))
end)
test("script reset cleanup is bounded and does not write imported input", function()
    local records, stats, ctx, tick, _, settings = fixture(0)
    local _, _, _, _, receipt = records.begin_import("config.json", {}, ctx)
    tick(receipt.task)
    receipt.task.cancel(ctx); receipt.task.cancel(ctx)
    assert(not ctx.recording and stats.writes == 0 and settings:get_field("RecordStartType") == 2)
    local done, ok = tick(receipt.task); assert(done and not ok)
end)
test("failure during start never retries and returns original recording settings", function()
    local records, stats, ctx, tick, _, settings = fixture(0, "start")
    local _, _, _, _, receipt = records.begin_import("config.json", {}, ctx)
    local done, ok = tick(receipt.task)
    assert(done and not ok and #stats.starts == 1 and stats.writes == 0)
    assert(settings:get_field("RecordStartType") == 2)
end)
test("wall clock timeout cancels once and restores the initialized empty slots", function()
    local saved_time, now = os.time, 100
    os.time = function() return now end
    local result = table.pack(pcall(function()
        local records, stats, ctx, tick = fixture(0)
        local _, _, _, _, receipt = records.begin_import("config.json", {}, ctx)
        tick(receipt.task); now = 111
        local done, ok
        for _ = 1, 4 do done, ok = tick(receipt.task); if done then break end end
        assert(done and not ok and #stats.starts == 1 and stats.writes == 0 and not ctx.recording)
    end))
    os.time = saved_time
    assert(result[1], result[2])
end)
test("v2 settings and thirty reversals are applied after initialization", function()
    local records, stats, ctx, tick, data, settings = fixture(0)
    local guard_fields = stats.guard_fields
    data.schema = "sf6cc.training_setup.v2"
    data.settings = {
        record = { record_setting_fields = { RecordStartType = 1 } },
        dummy = { guard_fields = { GuardType = 3, GuardWeight = 70,
            GuardCount = 4, IsGuardSwitching = true, GuardOnlyType = 1 } },
    }
    local ok, msg, _, _, receipt = records.begin_import("config.json", {}, ctx)
    assert(ok, msg)
    local done, success, result, final
    for _ = 1, 100 do
        local values = table.pack(tick(receipt.task))
        done, success, result, final = values[1], values[2], values[3], values[6]
        if done then break end
    end
    assert(done and success, result)
    assert(final.reversals == 30 and final.guard_settings == 5 and stats.writes == 432
        and settings:get_field("RecordStartType") == 1)
    assert(guard_fields:get_field("GuardType") == 3 and guard_fields:get_field("GuardWeight") == 70
        and guard_fields:get_field("GuardCount") == 4
        and guard_fields:get_field("IsGuardSwitching") == true
        and guard_fields:get_field("GuardOnlyType") == 1)
end)
test("older v2 configs preserve the current dummy guard settings", function()
    local records, stats, ctx, _, data = fixture(3600)
    local guard_fields = stats.guard_fields
    data.schema = "sf6cc.training_setup.v2"
    data.settings = { record = { record_setting_fields = { RecordStartType = 1 } } }
    guard_fields:set_field("GuardType", 4)
    local ok, msg, _, _, receipt = records.begin_import("old-v2.json", {}, ctx)
    assert(ok, msg)
    assert(receipt.guard_settings == 0 and guard_fields:get_field("GuardType") == 4)
end)
test("invalid dummy guard settings abort before backup or native writes", function()
    local records, stats, ctx, _, data = fixture(3600)
    data.schema = "sf6cc.training_setup.v2"
    data.settings = { dummy = { guard_fields = { GuardType = "all" } } }
    local ok = records.begin_import("invalid-guard.json", {}, ctx)
    assert(not ok and stats.backups == 0 and stats.writes == 0)
end)
test("v2 reversal errors abort before any initialization", function()
    local records, stats, ctx, _, data = fixture(0)
    data.schema = "sf6cc.training_setup.v2"; data.reversals.down[1].active = "bad"
    local ok = records.begin_import("config.json", {}, ctx)
    assert(not ok and #stats.starts == 0 and stats.writes == 0)
end)
test("unsupported file capacity aborts before backup and all native work", function()
    for _, kind in ipairs({ "record", "reversal", "sparse", "fraction" }) do
        local records, stats, ctx, _, data = fixture(0)
        if kind == "record" then data.slots[2].slot = 9
        elseif kind == "reversal" then
            data.schema = "sf6cc.training_setup.v2"
            data.reversals.down[10].slot = 11
        elseif kind == "sparse" then data.slots[4] = data.slots[2]; data.slots[2] = nil
        else data.slots[2].slot = 5.5 end
        local ok = records.begin_import("config.json", {}, ctx)
        assert(not ok and stats.backups == 0 and #stats.starts == 0 and stats.writes == 0)
    end
end)
test("live ninth slot imports, then an eight-slot file clears the stale extra", function()
    local records, stats, ctx, _, data, _, _, slots = fixture(3600, nil, 9)
    data.slots[3]={slot=9,is_valid=true,is_active=true,frame=1,input_num=1,input_buff={16}}
    local ok, msg = records.begin_import("config.json", {clear_empty_slots=true}, ctx)
    assert(ok,msg); assert(slots[8]:get_field("Frame")==1 and stats.writes==433)
    data.slots[3]=nil
    ok,msg=records.begin_import("eight.json", {clear_empty_slots=true}, ctx)
    assert(ok,msg); assert(slots[8]:get_field("IsValid")==false and slots[8]:get_field("Frame")==0)
end)
test("ninth file cannot authorize a missing live ninth slot", function()
    local records, stats, ctx, _, data=fixture(3600,nil,8)
    data.slots[3]={slot=9,is_valid=true,frame=1,input_num=1,input_buff={16}}
    assert(not records.begin_import("nine.json",{},ctx))
    assert(stats.writes==0 and stats.backups==0)
end)

test("eighty-slot import preserves slot80 name and clears omitted extra recordings",function()
    local records,stats,ctx,_,data,_,_,slots=fixture(3600,nil,80)
    data.slots[3]={slot=80,is_valid=true,is_active=true,frame=1,input_num=1,input_buff={16}}
    data.annotations={record_slots={{slot=80,text="对空"}}}
    assert(records.begin_import("eighty.json",{clear_empty_slots=true},ctx))
    assert(slots[79]:get_field("Frame")==1 and records.get_slot_name(80)=="对空")
    local before=stats.writes
    assert(records.set_slot_name(1,"防跳") and records.set_slot_name(80,"新名字"))
    assert(records.get_slot_name(1)=="防跳" and records.get_slot_name(80)=="新名字")
    assert(not records.set_slot_name(81,"invalid") and not records.set_slot_name(2,string.rep("x",16)))
    assert(stats.writes==before and slots[79]:get_field("Frame")==1)
    local exported,message=records.export_current("test-export.json")
    assert(exported,message)
    assert(#stats.exported.slots==80 and stats.exported.slots[80].name=="新名字")
    assert(stats.exported.annotations.record_slots[1].text=="防跳")
    assert(stats.exported.annotations.record_slots[80].text=="新名字")
    assert(stats.exported.settings.dummy.guard_fields.GuardType==0)
    assert(stats.exported.slots[80].input_buff[1]==16 and stats.writes==before)
    data.slots[3]=nil; data.annotations=nil
    assert(records.begin_import("eight.json",{clear_empty_slots=true},ctx))
    assert(slots[79]:get_field("Frame")==0 and records.get_slot_name(80)=="")
end)
test("save current captures all eighty slots and three native reversal groups into same file",function()
    local records,stats,ctx,_,_,_,_,slots,env=fixture(3600,nil,80)
    local guard_fields=stats.guard_fields
    local Json=require("tools/training_record_bank/vendor/dkjson")
    local path="SF6CC_TrainingConfigs/configs/test.json"
    local raw=Json.encode({schema="sf6cc.training_setup.v2",fighter_id=28,source_player="P2",
        title="keep title",description="keep note",slots={}})
    local files={[path]=raw}
    local writes={}
    env.fs.read=function(p)return files[p]end
    env.fs.glob=function(p)return files[p] and {p} or {}end
    env.fs.write=function(p,text)files[p]=text; writes[#writes+1]=p; return true end
    env.json.load_string=function(text)return assert(Json.decode(text))end
    -- REFramework bindings/Json.cpp encodes empty tables as null, then decodes
    -- null as nil. A generic JSON codec that preserves {} missed the live bug.
    local function native_json_value(value)
        if type(value)~="table" then return value end
        if next(value)==nil then return Json.null end
        local result={}
        for key,child in pairs(value) do result[key]=native_json_value(child) end
        return result
    end
    env.json.dump_string=function(value)return Json.encode(native_json_value(value),{indent=true})end
    assert(guard_fields:get_field("GuardType")==0 and guard_fields:get_field("GuardWeight")==40)
    assert(records.set_slot_name(80,"last"))
    slots[79]:set_field("Frame",3); slots[79]:set_field("IsValid",true)
    local ok,message=records.save_current(path)
    assert(ok,message)
    assert(#writes==2 and writes[1]~=path and writes[2]==path and files[writes[1]]==raw)
    local saved=assert(Json.decode(files[path]))
    assert(saved.title=="keep title" and saved.description=="keep note" and #saved.slots==80)
    assert(saved.slots[80].input_buff[3]==16 and saved.slots[80].name=="last")
    assert(saved.annotations.record_slots[80].text=="last")
    assert(saved.settings.dummy.guard_fields.GuardType==guard_fields:get_field("GuardType"))
    assert(saved.settings.dummy.guard_fields.GuardWeight==guard_fields:get_field("GuardWeight"))
    assert(saved.slots[1].frame==0 and saved.slots[1].input_buff==nil)
    for _,g in ipairs({"down","guard","damage"}) do assert(#saved.reversals[g]==10) end
    assert(stats.writes==0 and stats.forces==0 and #stats.starts==0)
end)
print(passed .. " recording import tests passed")
