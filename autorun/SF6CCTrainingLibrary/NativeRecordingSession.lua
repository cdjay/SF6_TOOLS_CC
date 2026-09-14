-- Bank allocation/lifecycle use the entry thread; paging uses scoped native UI navigation.
local Menu = require("SF6CCTrainingLibrary/NativeRecordingMenu")
local M = { CAPACITY = require("SF6CCTrainingLibrary/TrainingSlotLayout").EXPANDED_RECORDS }
local SLOT = "app.training.TrainingData.TM_RecordSetting.SlotData"
local SET = "SetValue(System.Object, System.Int32)"
local function same(a, b) return a and b and a:get_address() == b:get_address() end

local function lifetime_snapshot(label, obj)
    local function read(fn)
        local ok, value = pcall(fn)
        return ok and tostring(value) or "unavailable"
    end
    return label .. "{address=" .. read(function() return obj:get_address() end)
        .. ",refs=" .. read(function() return obj:get_reference_count() end)
        .. ",type=" .. read(function() return obj:get_type_definition():get_full_name() end) .. "}"
end

-- Failure-only evidence; never repair pointers or retry native initialization here.
local function input_failure_details(target, source)
    local values = {}
    local function capture(key, fn)
        local ok, value = pcall(fn)
        values[#values + 1] = key .. "=" .. (ok and tostring(value) or "unavailable")
    end
    for _, pair in ipairs({ { "target", target }, { "source", source } }) do
        local name, obj = pair[1], pair[2]
        capture(name .. ".address", function() return obj:get_address() end)
        capture(name .. ".type", function() return obj:get_type_definition():get_full_name() end)
        capture(name .. ".refs", function() return obj:get_reference_count() end)
        capture(name .. ".raw_input", function()
            local offset = obj:get_type_definition():get_field("InputData"):get_offset_from_base()
            return obj:read_qword(offset)
        end)
        capture(name .. ".frame", function() return obj:get_field("Frame") end)
    end
    capture("init_function", function() return target:get_type_definition():get_method("Init()"):get_function() end)
    capture("copy_function", function()
        return target:get_type_definition():get_method("DeepCopy(" .. SLOT .. ")"):get_function()
    end)
    return table.concat(values, "; ")
end

function M.prepare(api, threads, ctx, protection)
    local roots, entry_thread, navigation = {}, threads.get_id(), nil
    local stage, slot_lifetime = "context", nil
    local self = { manager = ctx.session, data = ctx.data, fighter_id = ctx.fighter_id,
        readers = 0, issued = 0, completed = 0, released = false, phase = "preparing" }
    local function own(obj)
        assert(obj, "native allocation returned nil")
        obj:add_ref(); roots[#roots + 1] = obj
        return obj
    end
    local function game_thread() return threads.get_id() == entry_thread end
    local function bank(data)
        local setting = assert(data:get_field("RecordSetting"))
        local list = assert(setting:get_field("FighterDataList"))
        local index = setting:call("GetFighterIndex", ctx.fighter_id)
        assert(type(index) == "number" and index >= 0 and index < list:call("get_Count"), "fighter index")
        local fighter = assert(list:call("get_Item", index))
        assert(fighter:get_field("FighterID") == ctx.fighter_id, "fighter identity")
        return fighter, assert(fighter:get_field("RecordSlots"))
    end
    local function idle()
        return self.record:call("IsRecording") == false and self.record:call("IsReplayNow") == false
            and self.gdata:get_field("ReqType") == 0 and self.gdata:get_field("State") == 0
    end
    local permit = { guard_ready = protection == true }
    function permit.allows(stage, target, id)
        if id ~= self.fighter_id or not protection then return false end
        if not same(target, self.manager) and not same(target, self.fighter) then return false end
        if stage == "menu_page" then
            return navigation ~= nil and navigation.thread == threads.get_id()
                and self.phase == "active" and not self.released
                and same(self.manager:get_field("_tData"), self.data)
        end
        if not game_thread() then return false end
        if stage == "menu_discard" then return self.phase == "prepared" end
        if stage == "menu_retire" or stage == "detach" then return self.released or idle() end
        if stage == "menu_dispose" or stage == "dispose" then return self.phase == "retired" end
        return self.phase == "preparing" and same(self.manager:get_field("_tData"), self.data) and idle()
    end
    local recording = { capacity = M.CAPACITY, fighter_id = ctx.fighter_id }
    local attached = false
    function recording.verify()
        assert(self.array:get_size() == M.CAPACITY and self.original:get_size() == 8)
        local slots, inputs, buffers = {}, {}, {}
        local function reserve(seen, value, message)
            if not value then return end
            local address = value:get_address()
            assert(not seen[address], message)
            seen[address] = true
        end
        for _, source in ipairs({ self.original, self.original_copy }) do
            for i = 0, 7 do
                local slot = assert(source:get_element(i))
                reserve(slots, slot, "protected slot alias")
                local input = assert(slot:get_field("InputData"))
                reserve(inputs, input, "protected input alias")
                reserve(buffers, input:get_field("buff"), "protected buffer alias")
            end
        end
        for i = 0, M.CAPACITY - 1 do
            local slot = assert(self.array:get_element(i))
            reserve(slots, slot, "slot alias")
            local input = assert(slot:get_field("InputData"))
            reserve(inputs, input, "input alias")
            local buffer = assert(input:get_field("buff"))
            reserve(buffers, buffer, "input buffer alias")
            assert(buffer:get_size() > 0 and buffer:get_size() <= 3600, "buffer capacity")
        end
        for i = 0, 7 do
            local a, b = self.array:get_element(i), self.original:get_element(i)
            assert(not same(a, b) and a:get_field("Frame") == b:get_field("Frame"), "slot clone")
            local ai, bi = a:get_field("InputData"), b:get_field("InputData")
            assert(ai and bi and not same(ai, bi), "input clone")
            local ab, bb = ai:get_field("buff"), bi:get_field("buff")
            assert(not ab or not bb or not same(ab, bb), "input buffer alias")
        end
        return true
    end
    function recording.attach(target, supplied)
        assert(supplied == permit and permit.allows("attach", target, ctx.fighter_id))
        assert(same(target:get_field("RecordSlots"), self.original), "bank changed")
        recording.verify()
        attached = true
        target:set_field("RecordSlots", self.array)
        assert(same(target:get_field("RecordSlots"), self.array), "bank attach readback")
        return true
    end
    function recording.detach(supplied)
        assert(supplied == permit and permit.allows("detach", self.fighter, ctx.fighter_id))
        local current = self.fighter:get_field("RecordSlots")
        assert(same(current, self.array) or same(current, self.original), "foreign bank replacement")
        if not self.released then self.gdata:call("DeepCopy", self.idle_gdata) end
        local selection = self.baseline:get_field("SelectChildIndex")
        if selection then self.data:set_field("SelectChildIndex", selection) end
        self.fighter:set_field("RecordSlots", self.original)
        assert(same(self.fighter:get_field("RecordSlots"), self.original), "bank restore readback")
        attached = false
        return true
    end
    function recording.state() return attached and "attached" or "prepared" end
    function recording.close() return not attached end
    function self.with_menu_navigation(owner, row, parent, callback)
        assert(protection and self.phase == "active" and not self.released and not navigation,
            "menu navigation scope unavailable")
        assert(same(owner, self.manager:get_field("_UIFunc"))
            and same(self.manager:get_field("_tData"), self.data)
            and self.menu.owns_pager(row, parent), "foreign menu navigation")
        -- The native Function callback may run on another game thread. Only
        -- page-array changes are permitted here, never bank attach/detach/save.
        navigation = { thread = threads.get_id() }
        local ok, result = pcall(callback)
        navigation = nil
        if not ok then error(result, 0) end
        return result
    end
    function self.attach()
        assert(game_thread() and self.phase == "prepared")
        self.phase = "preparing"
        local ok, err = self.menu.attach()
        self.phase = ok and "active" or "attach_uncertain"
        return ok, err
    end
    function self.retire()
        if self.phase == "retired" then return true end
        assert(game_thread(), "retire thread")
        if navigation then return false, "native menu navigation still active" end
        if not self.released and not idle() then return false, "recorder still busy" end
        -- Validate the bank before Menu.retire restores any visible rows.
        -- An unknown replacement must leave both UI and recordings untouched.
        local current = self.fighter:get_field("RecordSlots")
        if not same(current, self.array) and not same(current, self.original) then
            return false, "recording bank changed; restart required (menu and recordings left unchanged)"
        end
        local ok, err = self.menu.retire()
        if ok then self.phase = "retired" end
        return ok, err
    end
    function self.can_close()
        -- Only a correlated training FinishSave success completes an issued save.
        return not navigation and self.phase == "retired" and self.readers == 0 and self.completed >= self.issued
    end
    function self.discard()
        assert(game_thread() and self.phase == "prepared" and self.issued == 0 and self.readers == 0)
        assert(self.menu.close())
        for i = #roots, 1, -1 do roots[i]:release(); roots[i] = nil end
        self.phase = "closed"
    end
    function self.close()
        assert(game_thread() and self.can_close(), "native reader still owns session")
        assert(self.menu.close())
        for i = #roots, 1, -1 do roots[i]:release(); roots[i] = nil end
        self.phase = "closed"
    end
    local ok, err = xpcall(function()
        assert(protection and game_thread(), "save hooks unavailable")
        own(self.manager); own(self.data)
        self.record = own(ctx.record_func)
        assert(same(self.record:get_field("_tData"), self.data), "recorder owner mismatch")
        self.gdata = own(self.record:get_field("_gData"))
        assert(idle(), "recorder not idle")
        stage = "recorder baseline"
        self.idle_gdata = own(api.create_instance("app.training.tf_RecordSetting.GameLocalData"))
        self.idle_gdata:call("Init"); self.idle_gdata:call("DeepCopy", self.gdata)
        self.fighter, self.original = bank(self.data)
        own(self.fighter); own(self.original)
        assert(self.original:get_size() == 8, "expected original eight slots; cold restart required")
        -- Native auto-save receives the entry baseline, never the temporary bank.
        stage = "save baseline duplicate"
        self.baseline = own(self.data:call("Duplicate"))
        assert(not same(self.baseline, self.data), "save baseline aliases live data")
        local _, original_copy = bank(self.baseline)
        assert(original_copy:get_size() == 8 and not same(original_copy, self.original), "save baseline bank")
        self.original_copy = original_copy
        stage = "recording template"
        local template = self.original:get_element(0)
        for i = 0, 7 do
            local candidate = self.original:get_element(i)
            if candidate:get_field("IsValid") and candidate:get_field("Frame") > 0 then
                template = candidate
                break
            end
        end
        stage = "recording array allocation"
        self.array = own(api.create_managed_array(SLOT, M.CAPACITY))
        for i = 0, M.CAPACITY - 1 do
            stage = "slot " .. (i + 1) .. " / init"
            -- Only keep the current slot's boundary snapshots; emit on failure.
            -- The global factory alone did not resolve the live lifetime loss.
            slot_lifetime = {}
            local slot = api.create_instance_global(SLOT)
            slot_lifetime[#slot_lifetime + 1] = lifetime_snapshot("created", slot)
            own(slot)
            slot_lifetime[#slot_lifetime + 1] = lifetime_snapshot("retained", slot)
            -- Give Init a native owner, not only Lua wrapper roots. This array
            -- stays private until every slot and the original bank are verified.
            stage = "slot " .. (i + 1) .. " / array insertion"
            self.array:call(SET, slot, i)
            assert(same(self.array:get_element(i), slot), "private slot insertion readback")
            slot_lifetime[#slot_lifetime + 1] = lifetime_snapshot("array_owned", slot)
            stage = "slot " .. (i + 1) .. " / init"
            slot:call("Init")
            slot_lifetime[#slot_lifetime + 1] = lifetime_snapshot("initialized", slot)
            local initialized_input = slot:get_field("InputData") ~= nil
            -- Native DeepCopy copies the inline Guid at its actual size. Lua's
            -- generic Title setter can copy boxed-size bytes over InputData.
            local source = i < 8 and self.original:get_element(i) or template
            assert(source:get_field("InputData"), "slot " .. (i + 1) .. ": source InputData empty")
            stage = "slot " .. (i + 1) .. " / copy"
            slot_lifetime[#slot_lifetime + 1] = lifetime_snapshot("before_copy", slot)
            slot:call("DeepCopy", source)
            slot_lifetime[#slot_lifetime + 1] = lifetime_snapshot("copied", slot)
            local input = slot:get_field("InputData")
            if not input then
                error("slot " .. (i + 1) .. ": native DeepCopy left InputData empty (Init="
                    .. tostring(initialized_input) .. "); " .. input_failure_details(slot, source))
            end
            stage = "slot " .. (i + 1) .. " / buffer"
            local buffer = input:get_field("buff")
            if i >= 8 then
                buffer = own(api.create_managed_array("System.UInt16", 3600))
                input:set_field("buff", buffer); input:set_field("Num", 0)
                slot:set_field("Frame", 0); slot:set_field("IsValid", false)
                slot:set_field("IsActive", false); slot:set_field("Weight", 1)
            elseif not buffer or buffer:get_size() == 0 then
                assert(slot:get_field("Frame") == 0 and input:get_field("Num") == 0
                    and not slot:get_field("IsValid"), "recorded slot has no buffer")
                buffer = own(api.create_managed_array("System.UInt16", 3600))
                input:set_field("buff", buffer)
            end
            assert(not buffer or buffer:get_size() <= 3600, "buffer capacity")
        end
        slot_lifetime = nil
        stage = "recording ownership verification"
        recording.verify()
        local why, failed
        stage = "menu preparation"
        self.menu, why, failed = Menu.prepare(api, self.manager, recording, ctx.fighter_id, permit)
        self.failed_menu = failed
        assert(self.menu, why)
        self.phase = "prepared"
    end, function(detail)
        local evidence = slot_lifetime and ("; [SlotLifetime] " .. table.concat(slot_lifetime, " -> ")) or ""
        return debug.traceback("[" .. stage .. "] " .. tostring(detail) .. evidence, 2)
    end)
    if not ok then self.phase = "failed"; return nil, tostring(err), self end
    return self
end
return M
