local M = {}

local VARIANT_ORDER = {
    SA1 = 1,
    SA2 = 2,
    SA3 = 3,
    CA = 4,
}

local VARIANT_COLORS = {
    SA1 = 0xFF44DDFF,
    SA2 = 0xFF00DD88,
    SA3 = 0xFFFFAA44,
    CA = 0xFF5555FF,
}

local function resource_variant(scenario)
    if scenario.is_low_health == true then return "CA" end
    return "SA" .. tostring(math.max(1, math.min(3, tonumber(scenario.super_bars) or 1)))
end

function M.new()
    return {
        groups = {},
        total_samples = 0,
        total_damage = 0,
    }
end

function M.reset(state)
    state.groups = {}
    state.total_samples = 0
    state.total_damage = 0
end

function M.record(state, scenario, damage)
    if type(state) ~= "table" or type(scenario) ~= "table" then return false end
    local drive = math.max(1, math.min(6, math.floor(tonumber(scenario.drive_bars) or 1)))
    local variant = resource_variant(scenario)
    local value = math.max(0, math.floor((tonumber(damage) or 0) + 0.5))
    local key = tostring(drive) .. ":" .. variant
    local group = state.groups[key]
    if not group then
        group = {
            key = key,
            drive_bars = drive,
            variant = variant,
            samples = 0,
            total_damage = 0,
        }
        state.groups[key] = group
    end
    group.samples = group.samples + 1
    group.total_damage = group.total_damage + value
    state.total_samples = state.total_samples + 1
    state.total_damage = state.total_damage + value
    return true
end

function M.summary(state)
    local groups = 0
    for _ in pairs(state and state.groups or {}) do groups = groups + 1 end
    local samples = tonumber(state and state.total_samples) or 0
    local total_damage = tonumber(state and state.total_damage) or 0
    return {
        groups = groups,
        samples = samples,
        average_damage = samples > 0 and total_damage / samples or nil,
    }
end

function M.bars(state)
    local out = {}
    for _, group in pairs(state and state.groups or {}) do
        local average = group.samples > 0 and group.total_damage / group.samples or 0
        out[#out + 1] = {
            key = group.key,
            label = tostring(group.drive_bars) .. "斗气 + " .. group.variant,
            line1 = tostring(group.drive_bars) .. "斗气",
            line2 = group.variant,
            value = average,
            samples = group.samples,
            color = VARIANT_COLORS[group.variant],
            drive_bars = group.drive_bars,
            variant_order = VARIANT_ORDER[group.variant] or 99,
        }
    end
    table.sort(out, function(a, b)
        if a.drive_bars ~= b.drive_bars then return a.drive_bars < b.drive_bars end
        return a.variant_order < b.variant_order
    end)
    return out
end

return M
