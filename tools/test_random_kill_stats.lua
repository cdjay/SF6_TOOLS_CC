local Stats = dofile("autorun/func/RandomKill/Stats.lua")

local state = Stats.new()
Stats.record(state, { drive_bars = 1, super_bars = 3, is_low_health = false }, 3200)
Stats.record(state, { drive_bars = 1, super_bars = 3, is_low_health = false }, 4800)
Stats.record(state, { drive_bars = 1, super_bars = 3, is_low_health = true }, 5100)
Stats.record(state, { drive_bars = 2, super_bars = 1, is_low_health = false }, 1700)

local summary = Stats.summary(state)
assert(summary.samples == 4 and summary.groups == 3,
    "statistics must count attempts and distinct resource combinations")
assert(summary.average_damage == 3700,
    "statistics must expose the overall average damage")

local bars = Stats.bars(state)
assert(#bars == 3, "statistics must produce one bar per sampled combination")
assert(bars[1].label == "1斗气 + SA3"
        and bars[1].value == 4000
        and bars[1].samples == 2,
    "same resource combination must aggregate to average damage")
assert(bars[2].label == "1斗气 + CA" and bars[2].value == 5100,
    "CA must be separate from ordinary SA3")
assert(bars[3].label == "2斗气 + SA1" and bars[3].value == 1700,
    "bars must sort by drive then super variant")

Stats.reset(state)
summary = Stats.summary(state)
assert(summary.samples == 0 and summary.groups == 0 and summary.average_damage == nil,
    "reset must clear every aggregate")

print("random kill stats tests passed")
