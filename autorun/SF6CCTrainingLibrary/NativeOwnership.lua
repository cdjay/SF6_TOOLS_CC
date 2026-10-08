-- Engine objects that game structures reference must not depend on
-- REFramework's Lua reference bookkeeping. That bookkeeping is keyed by raw
-- address, deduplicates add_ref, and lets a stale cached wrapper or a later
-- finalizer release a reference that belongs to a new object at the same
-- address. Objects injected into menus, tickers or recorder data therefore get
-- one permanent engine reference and are never released from Lua.
--
-- create_*_global is never used: it performs add_ref, Lua push and release,
-- and drops the only reference when the push reuses a stale cached wrapper.
local M = { MAX_STRINGS = 2048 }
local retained, string_count = {}, 0
-- Keyed by factory: every module shares sdk.create_managed_string in the game.
local caches = setmetatable({}, { __mode = "k" })

function M.retain(obj)
    assert(obj, "native allocation returned nil")
    obj:add_ref_permanent()
    -- Wrappers stay reachable for identity checks only; they own nothing.
    retained[#retained + 1] = obj
    return obj
end

function M.instance(api, type_name, simplify)
    return M.retain(api.create_instance(type_name, simplify))
end

function M.array(api, type_name, count)
    return M.retain(api.create_managed_array(type_name, count))
end

-- Hook results are shared, immutable System.String objects. Each distinct
-- text is created once instead of on every native GetMessage/GetOptionText.
function M.string(api, text)
    if type(text) ~= "string" then return nil end
    local factory = api.create_managed_string
    local cache = caches[factory]
    if not cache then cache = {}; caches[factory] = cache end
    local cached = cache[text]
    if cached then return cached end
    local value = factory(text)
    if not value then return nil end
    if string_count >= M.MAX_STRINGS then
        -- Bounded fallback: a frame-local string for the immediate caller only.
        return value
    end
    value:add_ref_permanent()
    cache[text], string_count = value, string_count + 1
    return value
end

function M.counts() return #retained, string_count end

return M
