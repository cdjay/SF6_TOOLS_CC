local M = {}

M.DEFAULTS = {
    corner_x = 730,
    distance = 100,
    edge_weight = 80,
    mid_weight = 20,
    normal_hp_min = 30,
    normal_hp_max = 100,
    low_hp = 20,
    low_health_chance = 50,
    drive_min = 1,
    drive_max = 6,
    super_min = 1,
    super_max = 3,
}

local ZONES = {
    { key = "left_corner", label = "左侧版边" },
    { key = "mid_screen", label = "版中" },
    { key = "right_corner", label = "右侧版边" },
}

local function clamp_integer(value, minimum, maximum, fallback)
    local number = tonumber(value)
    if number == nil then number = fallback end
    number = math.floor(number + 0.5)
    if number < minimum then number = minimum end
    if number > maximum then number = maximum end
    return number
end

function M.normalize_config(source)
    source = type(source) == "table" and source or {}
    local defaults = M.DEFAULTS
    local out = {
        corner_x = clamp_integer(source.corner_x, 100, 1000, defaults.corner_x),
        distance = clamp_integer(source.distance, 1, 500, defaults.distance),
        edge_weight = clamp_integer(source.edge_weight, 0, 100, defaults.edge_weight),
        mid_weight = clamp_integer(source.mid_weight, 0, 100, defaults.mid_weight),
        normal_hp_min = clamp_integer(source.normal_hp_min, 1, 100, defaults.normal_hp_min),
        normal_hp_max = clamp_integer(source.normal_hp_max, 1, 100, defaults.normal_hp_max),
        low_hp = clamp_integer(source.low_hp, 1, 25, defaults.low_hp),
        low_health_chance = clamp_integer(
            source.low_health_chance,
            0,
            100,
            defaults.low_health_chance
        ),
        drive_min = clamp_integer(source.drive_min, 0, 6, defaults.drive_min),
        drive_max = clamp_integer(source.drive_max, 0, 6, defaults.drive_max),
        super_min = clamp_integer(source.super_min, 0, 3, defaults.super_min),
        super_max = clamp_integer(source.super_max, 0, 3, defaults.super_max),
    }
    if out.normal_hp_min > out.normal_hp_max then
        out.normal_hp_min, out.normal_hp_max = out.normal_hp_max, out.normal_hp_min
    end
    if out.drive_min > out.drive_max then
        out.drive_min, out.drive_max = out.drive_max, out.drive_min
    end
    if out.super_min > out.super_max then
        out.super_min, out.super_max = out.super_max, out.super_min
    end
    if out.edge_weight + out.mid_weight <= 0 then
        out.edge_weight = defaults.edge_weight
        out.mid_weight = defaults.mid_weight
    end
    return out
end

local function normalize_seed(seed)
    local value = math.floor(tonumber(seed) or 1)
    value = value % 2147483647
    if value <= 0 then value = value + 2147483646 end
    return value
end

local function next_random(seed)
    local value = (normalize_seed(seed) * 48271) % 2147483647
    return value, value / 2147483647
end

local function random_integer(seed, minimum, maximum)
    local next_seed, unit = next_random(seed)
    local span = maximum - minimum + 1
    return minimum + math.floor(unit * span), next_seed
end

local function zone_positions(zone_key, corner_x, distance)
    if zone_key == "left_corner" then
        return -corner_x, -corner_x + distance
    end
    if zone_key == "right_corner" then
        return corner_x - distance, corner_x
    end
    local left = -math.floor(distance / 2)
    return left, left + distance
end

function M.generate(source_config, seed)
    local config = M.normalize_config(source_config)
    local zone_roll
    zone_roll, seed = random_integer(seed, 1, config.edge_weight + config.mid_weight)
    local zone_index = 2
    if zone_roll <= config.edge_weight then
        zone_index, seed = random_integer(seed, 1, 2)
        if zone_index == 2 then zone_index = 3 end
    end
    local p1_side_roll
    p1_side_roll, seed = random_integer(seed, 0, 1)
    local drive_bars
    drive_bars, seed = random_integer(seed, config.drive_min, config.drive_max)
    local super_bars
    super_bars, seed = random_integer(seed, config.super_min, config.super_max)

    local low_health = false
    if super_bars == 3 and config.low_health_chance > 0 then
        local low_roll
        low_roll, seed = random_integer(seed, 1, 100)
        low_health = low_roll <= config.low_health_chance
    end

    local hp_pct = config.low_hp
    if not low_health then
        hp_pct, seed = random_integer(seed, config.normal_hp_min, config.normal_hp_max)
    end

    local zone = ZONES[zone_index]
    local left_x, right_x = zone_positions(zone.key, config.corner_x, config.distance)
    local p1_on_left = p1_side_roll == 0

    return {
        zone = zone.key,
        zone_label = zone.label,
        p1_side = p1_on_left and "left" or "right",
        p1_side_label = p1_on_left and "P1在左" or "P1在右",
        p1_x = p1_on_left and left_x or right_x,
        p2_x = p1_on_left and right_x or left_x,
        distance = config.distance,
        hp_pct = hp_pct,
        is_low_health = low_health,
        drive_bars = drive_bars,
        drive_points = drive_bars * 10000,
        super_bars = super_bars,
        super_points = super_bars * 10000,
    }, seed
end

return M
