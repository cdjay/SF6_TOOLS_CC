-- DataBuildGuard.lua
-- Checks that a fighter's generated command table was built from the game
-- data that is actually running. The generator stores a fingerprint of the
-- BCM trigger table in command_display/<key>.json (_meta.bcm_trigger_fingerprint,
-- tools/action_runtime_compiler/bcm_fingerprint.js); GameProbe computes the
-- same fingerprint from live memory. A mismatch means a game update changed
-- the fighter's commands or Action IDs and the table must be regenerated.

local DataBuildGuard = {
    name = "ComboTrials.DataBuildGuard",
    ALGORITHM = "bcm-trigger-action-multiset.fnv1a32.v1",
}

function DataBuildGuard.fnv1a32(text)
    local hash = 0x811c9dc5
    text = tostring(text or "")
    for index = 1, #text do
        hash = hash ~ text:byte(index)
        hash = (hash * 0x01000193) & 0xFFFFFFFF
    end
    return string.format("%08x", hash)
end

-- action_ids: the action_id of every BCM trigger (any order, may contain
-- non-positive or missing values, which are ignored).
function DataBuildGuard.fingerprint(action_ids)
    local ids = {}
    for _, value in pairs(action_ids or {}) do
        local id = math.tointeger(tonumber(value))
        if id ~= nil and id > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids)
    local parts = {}
    for index, id in ipairs(ids) do parts[index] = tostring(id) end
    return {
        algorithm = DataBuildGuard.ALGORITHM,
        count = #ids,
        hash = DataBuildGuard.fnv1a32(table.concat(parts, ",")),
    }
end

-- expected: _meta.bcm_trigger_fingerprint of the loaded table (nil when the
--           table predates fingerprints).
-- table_status: the renderer's load status ("loaded", "map_load_failed", ...).
-- live: DataBuildGuard.fingerprint of the running game, nil while unknown.
-- Returns match | mismatch | missing_table | invalid_table | unverified | pending.
function DataBuildGuard.evaluate(expected, table_status, live)
    if type(live) ~= "table" then return "pending" end
    if table_status == "map_load_failed" or table_status == "invalid_character" then
        return "missing_table"
    end
    if table_status ~= "loaded" then return "invalid_table" end
    if type(expected) ~= "table" or expected.algorithm ~= DataBuildGuard.ALGORITHM then
        return "unverified"
    end
    if tonumber(expected.count) == live.count and tostring(expected.hash) == live.hash then
        return "match"
    end
    return "mismatch"
end

local MESSAGES = {
    mismatch = "【数据版本不一致】%s 的指令表不是用当前游戏数据生成的，录制、判定和指令显示可能出错。"
        .. "请按 tools/acbcm_exporter/README.md 重新导出并生成。",
    missing_table = "【缺少指令表】%s 还没有生成指令表，可以录制，但指令显示和部分判定不可用。",
    invalid_table = "【指令表无效】%s 的指令表未通过校验，已停用。请重新生成并部署。",
}

function DataBuildGuard.message(character, status)
    local template = MESSAGES[status]
    if template == nil then return nil end
    return string.format(template, tostring(character or "?"))
end

-- Reports each (character, status) once per Lua state.
function DataBuildGuard.new_reporter(report)
    local seen = {}
    return function(character, status)
        local message = DataBuildGuard.message(character, status)
        if message == nil then return nil end
        local key = tostring(character) .. "|" .. tostring(status)
        if seen[key] then return nil end
        seen[key] = true
        if type(report) == "function" then pcall(report, message, status, character) end
        return message
    end
end

return DataBuildGuard
