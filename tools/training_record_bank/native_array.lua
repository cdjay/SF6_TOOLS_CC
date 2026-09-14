-- Research adapter. No automatic attachment or hooks; a verified save/thread
-- permit is required for explicit live binding. No such permit ships here.
local M = { MAX_TEST_SLOTS = 9, BUFFER_CAPACITY = 3600, MAX_TEST_INPUT_VALUES = 4096 }
local INPUT_KEYS = {Cursor="number", IsForceStop="boolean", isLoop="boolean",
    State="number", cmd_type="number", negativeEdge="boolean"}
local SLOT_TYPE = "app.training.TrainingData.TM_RecordSetting.SlotData"

function M.prepare(Bank, api, document, capacity)
    local editor, reason = Bank.open(document)
    if not editor then return nil, reason end
    local expected = editor.snapshot()
    if type(capacity) ~= "number" or capacity % 1 ~= 0 or capacity < 1
        or capacity > M.MAX_TEST_SLOTS or #expected.records > capacity then
        return nil, "native research capacity bound"
    end
    if #expected.record_refs ~= 0 then return nil, "native reversal references not implemented" end
    -- The file model is wider than this native binding. Reject unsupported data
    -- before allocating, rather than silently dropping fields or narrowing input.
    local total = 0
    for _, record in ipairs(expected.records) do
        total = total + record.recording.frame
        if total > M.MAX_TEST_INPUT_VALUES then return nil, "native research input budget" end
        if next(record.recording.fields) ~= nil then return nil, "unsupported native slot scalar" end
        for key, value in pairs(record.recording.input_fields) do
            if INPUT_KEYS[key] ~= type(value) then return nil, "unsupported native input field: " .. key end
            if type(value) == "number" and (value % 1 ~= 0 or value < -2147483648 or value > 2147483647) then
                return nil, "native input scalar outside Int32"
            end
        end
        for _, value in ipairs(record.recording.input_buff) do
            if value > 65535 then return nil, "input does not fit native UInt16 buffer" end
        end
    end
    local roots, slots, buffers = {}, {}, {}
    local array, phase = nil, "preparing"
    local lease = {guard_ready=false,capacity=capacity,fighter_id=expected.fighter_id}
    local fighter, original, mounted_once, mount_permit
    local function own(value)
        assert(value, "native allocation returned nil")
        roots[#roots+1] = value
        value:add_ref()
        return value
    end
    local function prepare()
        array = own(api.create_managed_array(SLOT_TYPE, capacity))
        assert(array:get_size() == capacity, "allocated length mismatch")
        for i = 1, capacity do
            local slot = own(api.create_instance(SLOT_TYPE))
            slot:call("Init")
            assert(slot:get_type_definition():get_full_name() == SLOT_TYPE, "allocated slot type mismatch")
            local input = assert(slot:get_field("InputData"), "Init did not create input data")
            local buffer = own(api.create_managed_array("System.UInt16", M.BUFFER_CAPACITY))
            assert(buffer:get_size() == M.BUFFER_CAPACITY, "input buffer length mismatch")
            input:set_field("buff", buffer)
            assert(buffer:get_reference_count() >= 2, "input buffer field ownership not established")
            local record = expected.records[i]
            slot:set_field("Frame", record and record.recording.frame or 0)
            slot:set_field("Weight", record and record.weight or 1)
            slot:set_field("IsActive", record and record.enabled or false)
            slot:set_field("IsValid", record ~= nil)
            input:set_field("Num", record and record.recording.frame or 0)
            if record then
                for key, value in pairs(record.recording.input_fields) do input:set_field(key, value) end
                for frame, value in ipairs(record.recording.input_buff) do
                    buffer:call("SetValue(System.Object, System.Int32)", api.create_uint16(value), frame - 1)
                end
            end
            array:call("SetValue(System.Object, System.Int32)", slot, i - 1)
            assert(slot:get_reference_count() >= 2, "slot array ownership not established")
            slots[i], buffers[i] = slot:get_address(), buffer:get_address()
        end
        phase = "prepared"
    end
    local function verify()
        assert(phase == "prepared", "native lease is not prepared")
        assert(array:get_size() == capacity, "array size changed")
        for i = 1, capacity do
            local slot = assert(array:get_element(i - 1))
            assert(slot:get_address() == slots[i], "slot identity changed")
            assert(slot:get_type_definition():get_full_name() == SLOT_TYPE, "slot type changed")
            local record = expected.records[i]
            assert(slot:get_field("Frame") == (record and record.recording.frame or 0), "Frame changed")
            assert(slot:get_field("Weight") == (record and record.weight or 1), "Weight changed")
            assert(slot:get_field("IsActive") == (record and record.enabled or false), "IsActive changed")
            assert(slot:get_field("IsValid") == (record ~= nil), "IsValid changed")
            local input = assert(slot:get_field("InputData"))
            assert(input:get_field("Num") == (record and record.recording.frame or 0), "Num changed")
            local buffer = assert(input:get_field("buff"))
            assert(buffer:get_address() == buffers[i] and buffer:get_size() == M.BUFFER_CAPACITY,
                "buffer identity/capacity changed")
            if record then
                for key, value in pairs(record.recording.input_fields) do
                    assert(input:get_field(key) == value, "input metadata changed: " .. key)
                end
                for frame, value in ipairs(record.recording.input_buff) do
                    local actual = buffer:call("GetValue", frame - 1)
                    if type(actual) ~= "number" then
                        assert(actual and actual:get_type_definition():get_full_name() == "System.UInt16", "input type")
                        actual = actual:get_field("mValue")
                    end
                    assert(actual == value, "input roundtrip mismatch at slot " .. i .. " frame " .. frame)
                end
            end
        end
        return true
    end
    function lease.verify()
        assert(phase == "prepared", "native lease is not prepared")
        local ok, result = pcall(verify)
        if not ok then phase = "failed"; error(result) end
        return result
    end
    function lease.attach(target, permit)
        if phase ~= "prepared" or mounted_once then return false, "lease not attachable" end
        local ok, err = pcall(function()
            assert(type(permit)=="table" and permit.guard_ready==true
                and type(permit.allows)=="function", "save/thread protection required")
            assert(permit.allows("attach", target, expected.fighter_id)==true, "attach context denied")
            assert(target:get_field("FighterID")==expected.fighter_id, "fighter mismatch")
            local bank=assert(target:get_field("RecordSlots"))
            assert(bank:get_size()==8, "expected original eight-slot bank")
            lease.verify()
            -- Retain both old owner and old array before touching the live field.
            -- A setter can throw after writing, so detach must handle either value.
            phase = "binding"
            fighter, original = own(target), own(bank)
            mount_permit, mounted_once = permit, true
            assert(permit.allows("attach", target, expected.fighter_id)==true, "attach context changed")
            phase = "attach_uncertain"
            target:set_field("RecordSlots", array)
            assert(target:get_field("RecordSlots"):get_address()==array:get_address(), "attach readback failed")
            phase = "attached"
        end)
        if not ok and phase=="binding" then phase="failed" end
        return ok, err
    end
    function lease.detach(permit)
        if phase ~= "attached" and phase ~= "attach_uncertain" then return false, "lease not attached" end
        -- Denied thread/context is not permission to touch even a rooted object.
        local allowed, result=pcall(function()
            return permit==mount_permit and permit.guard_ready==true
                and permit.allows("detach", fighter, expected.fighter_id)==true
        end)
        if not allowed or result~=true then return false, "retirement context denied" end
        phase="failed"
        local ok, err=pcall(function()
            assert(fighter:get_field("FighterID")==expected.fighter_id, "fighter changed")
            local current=assert(fighter:get_field("RecordSlots"))
            local address=current:get_address()
            assert(address==array:get_address() or address==original:get_address(), "bank replaced externally")
            if address==array:get_address() then fighter:set_field("RecordSlots",original) end
            assert(fighter:get_field("RecordSlots"):get_address()==original:get_address(), "restore readback failed")
            phase="prepared"
        end)
        return ok, err
    end
    function lease.close(permit)
        if phase ~= "prepared" then return false, "lease not releasable; no retry" end
        if mounted_once then
            local ok, allowed=pcall(function()
                return permit==mount_permit and permit.guard_ready==true
                    and permit.allows("dispose",fighter,expected.fighter_id)==true
            end)
            if not ok or allowed~=true then return false,"consumer release not confirmed" end
        end
        phase = "failed"
        local ok, err = pcall(function()
            for i = 0, capacity - 1 do
                array:call("SetValue(System.Object, System.Int32)", nil, i)
                assert(array:get_element(i) == nil, "array clear failed")
            end
            -- Reverse creation order balances only explicit Lua-owned references.
            -- No native object is inspected after its release call.
            for i = #roots, 1, -1 do roots[i]:release(); roots[i] = nil end
            array, phase = nil, "closed"
        end)
        return ok, err
    end
    function lease.state() return phase end
    local ok, err = pcall(prepare)
    if not ok then
        phase = "failed"
        -- Caller keeps the failed lease for the short diagnostic session. Do not
        -- guess at cleanup after a native exception or auto-retry allocation.
        return nil, tostring(err), lease
    end
    return lease
end
return M
