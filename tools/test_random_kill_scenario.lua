local Scenario = dofile("autorun/func/RandomKill/Scenario.lua")

local first, first_seed = Scenario.generate({}, 123456)
local repeated, repeated_seed = Scenario.generate({}, 123456)
assert(first_seed == repeated_seed, "same seed must advance identically")
for key, value in pairs(first) do
    assert(repeated[key] == value, "same seed must reproduce field " .. tostring(key))
end

local seen = {}
local seed = 987654
for _ = 1, 2000 do
    local scenario
    scenario, seed = Scenario.generate({}, seed)
    assert(math.abs(scenario.p1_x - scenario.p2_x) == 100,
        "every scenario must preserve the fixed center distance")
    assert(scenario.drive_bars >= 1 and scenario.drive_bars <= 6,
        "drive must stay within one to six bars")
    assert(scenario.drive_points == scenario.drive_bars * 10000,
        "drive bars must map to native points")
    assert(scenario.super_bars >= 1 and scenario.super_bars <= 3,
        "super must stay within one to three bars")
    assert(scenario.super_points == scenario.super_bars * 10000,
        "super bars must map to native points")
    if scenario.is_low_health then
        assert(scenario.super_bars == 3 and scenario.hp_pct == 20,
            "low-health scenarios require SA3 and fixed 20 percent health")
    else
        assert(scenario.hp_pct >= 30 and scenario.hp_pct <= 100,
            "normal scenarios must stay within 30 to 100 percent health")
    end
    seen[scenario.zone .. ":" .. scenario.p1_side] = true
end

for _, zone in ipairs({ "left_corner", "mid_screen", "right_corner" }) do
    assert(seen[zone .. ":left"], "P1-left variant missing for " .. zone)
    assert(seen[zone .. ":right"], "P1-right variant missing for " .. zone)
end

local low_scenario = Scenario.generate({
    super_min = 3,
    super_max = 3,
    low_health_chance = 100,
}, 42)
assert(low_scenario.is_low_health == true and low_scenario.hp_pct == 20,
    "100 percent CA chance must always select the 20 percent case")

local normal_scenario = Scenario.generate({
    super_min = 3,
    super_max = 3,
    low_health_chance = 0,
}, 42)
assert(normal_scenario.is_low_health == false
        and normal_scenario.hp_pct >= 30
        and normal_scenario.hp_pct <= 100,
    "zero CA chance must retain the normal health range")

local edge_count = 0
local mid_count = 0
seed = 246810
for _ = 1, 10000 do
    local scenario
    scenario, seed = Scenario.generate({}, seed)
    if scenario.zone == "mid_screen" then
        mid_count = mid_count + 1
    else
        edge_count = edge_count + 1
    end
end
local edge_ratio = edge_count / (edge_count + mid_count)
assert(edge_ratio > 0.77 and edge_ratio < 0.83,
    "default position weighting must be approximately 80 percent edge")

seed = 13579
for _ = 1, 100 do
    local scenario
    scenario, seed = Scenario.generate({ edge_weight = 0, mid_weight = 100 }, seed)
    assert(scenario.zone == "mid_screen", "zero edge weight must force mid-screen")
end

local seen_left_edge = false
local seen_right_edge = false
seed = 97531
for _ = 1, 100 do
    local scenario
    scenario, seed = Scenario.generate({ edge_weight = 100, mid_weight = 0 }, seed)
    assert(scenario.zone ~= "mid_screen", "zero mid-screen weight must force an edge")
    seen_left_edge = seen_left_edge or scenario.zone == "left_corner"
    seen_right_edge = seen_right_edge or scenario.zone == "right_corner"
end
assert(seen_left_edge and seen_right_edge,
    "edge selection must retain both fixed left and right positions")

print("random kill scenario tests passed")
