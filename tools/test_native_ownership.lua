-- Fake SDK contract for injected native objects; not live-game evidence.
package.path = "autorun/?.lua;" .. package.path
local Ownership = require("SF6CCTrainingLibrary/NativeOwnership")
local passed = 0
local function check(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end

local function object(kind)
    local o = { kind = kind, permanent = 0 }
    function o:add_ref_permanent() self.permanent = self.permanent + 1 end
    function o:add_ref() error("Lua reference bookkeeping must not own injected objects") end
    function o:release() error("injected objects must never be released from Lua") end
    return o
end
local function api()
    local a = { created = {}, strings = 0 }
    function a.create_instance(name, simplify)
        a.created[#a.created + 1] = { name = name, simplify = simplify }
        return object(name)
    end
    function a.create_instance_global() error("global factory releases its only reference on a stale wrapper") end
    function a.create_managed_array(name, count) return object(name .. "[" .. count .. "]") end
    function a.create_managed_string(text) a.strings = a.strings + 1; local s = object("string"); s.text = text; return s end
    return a
end

check("instances use the local factory and gain one permanent reference", function()
    local a = api()
    local value = Ownership.instance(a, "app.TickerRequestData", true)
    assert(value.permanent == 1 and #a.created == 1)
    assert(a.created[1].name == "app.TickerRequestData" and a.created[1].simplify == true)
    local plain = Ownership.instance(a, "app.training.TrainingMenuData")
    assert(plain.permanent == 1 and a.created[2].simplify == nil)
end)
check("arrays and adopted objects gain exactly one permanent reference", function()
    local a = api()
    local arr = Ownership.array(a, "app.training.TrainingMenuData", 13)
    assert(arr.kind == "app.training.TrainingMenuData[13]" and arr.permanent == 1)
    local adopted = object("page")
    assert(Ownership.retain(adopted) == adopted and adopted.permanent == 1)
    assert(not pcall(Ownership.retain, nil), "nil allocation must fail loudly")
end)
check("each distinct text is one permanent string per factory", function()
    local a = api()
    local first = Ownership.string(a, "保存当前配置")
    assert(first.text == "保存当前配置" and first.permanent == 1 and a.strings == 1)
    assert(Ownership.string(a, "保存当前配置") == first and a.strings == 1, "repeated text allocated again")
    local other = Ownership.string(a, "另存当前配置")
    assert(other ~= first and other.permanent == 1 and a.strings == 2)
    local b = api()
    local separate = Ownership.string(b, "保存当前配置")
    assert(separate ~= first and b.strings == 1, "a different factory must not reuse another cache")
    assert(Ownership.string(a, nil) == nil and Ownership.string(a, 5) == nil)
end)
check("string retention is bounded; overflow returns a frame-local string", function()
    local a = api()
    local limit = Ownership.MAX_STRINGS
    local _, used = Ownership.counts()
    Ownership.MAX_STRINGS = used + 1
    local kept = Ownership.string(a, "kept")
    assert(kept.permanent == 1)
    local transient = Ownership.string(a, "overflow")
    assert(transient.text == "overflow" and transient.permanent == 0, "overflow string was retained")
    assert(Ownership.string(a, "overflow") ~= transient, "overflow string was cached")
    assert(Ownership.string(a, "kept") == kept)
    Ownership.MAX_STRINGS = limit
end)
print(string.format("PASS %d native ownership checks (not live-game evidence)", passed))
