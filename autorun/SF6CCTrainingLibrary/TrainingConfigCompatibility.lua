-- One P2 ownership rule for cached menu previews and fresh import validation.
local M = {}
local function fighter_id(value)
    if type(value) ~= "number" and type(value) ~= "string" then return nil end
    local id = tonumber(value)
    if not id or id <= 0 or id == math.huge or id % 1 ~= 0 then return nil end
    return id
end
function M.check(data, ctx, options)
    data, ctx, options = data or {}, ctx or {}, options or {}
    local current, saved = fighter_id(ctx.fighter_id), fighter_id(data.fighter_id)
    if ctx.error or not current then
        return false, "无法确认当前 P2 角色，禁止导入", "unknown_current"
    end
    if not saved then return false, "配置缺少有效角色 ID，禁止导入", "unknown_file" end
    -- Older exports may omit the side. An explicit other side is never P2 data.
    if data.source_player ~= nil and data.source_player ~= "P2" then
        return false, "配置并非 P2 木人数据，禁止导入", "wrong_side"
    end
    if saved ~= current then
        local message = "角色不匹配：配置 ID " .. saved .. "，当前 P2 ID " .. current
        if options.reject_fighter_mismatch == false then
            return true, message .. "（已手动关闭拦截）", "override"
        end
        return false, message .. "，禁止导入", "mismatch"
    end
    return true, "与当前 P2 角色匹配（ID " .. current .. "）", "match"
end
return M
