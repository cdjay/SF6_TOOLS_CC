local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value
end

-- Load the pure normalizer block without booting REFramework/game globals.
local source = read_all("autorun/TrainingComboTrials_v1.0.lua")
local block = assert(source:match(
    "(CTTimelineSequenceNormalizer = CTTimelineSequenceNormalizer or {}.-)\nlocal function normalize_sequence_counter_types"))
is_drive_rush_id = function() return false end
assert(load(block, "timeline-normalizer", "t", _G))()

local timeline = {
    "1f : 2", "3f : 2+HP", "3f : 1+HP", "3f : 1", "3f : 2", "2f : 1",
    "5f : 1+LP", "1f : 4+LP", "22f : 5", "5f : 2", "2f : 1", "1f : 4",
    "3f : 7", "2f : 8", "3f : 5", "7f : 5+HK", "42f : 5", "5f : 5+HK",
    "1f : 2+HK", "5f : 2", "1f : 1", "1f : 4", "1f : 5", "4f : 2",
    "1f : 4", "4f : 7", "2f : 8", "6f : 5+LK", "586f : 5"
}
local sequence = {
    { id = 612, motion = "2HP", expected_combo = 1, expected_hp = 3000, damage_at_step = 800,
        has_hit = true, timeline = timeline },
    { id = 969, motion = "623+LP", expected_combo = 2, expected_hp = 3000, damage_at_step = 1500,
        has_hit = true },
    { id = 1037, motion = ">29 (cancel)", expected_combo = 2, expected_hp = 3000,
        damage_at_step = 1500, has_hit = true },
    { id = 961, motion = "j.236+HK (instant)", expected_combo = 3, expected_hp = 3000,
        damage_at_step = 2220, has_hit = true },
    { id = 608, motion = "HK", expected_combo = 4, expected_hp = 3000, damage_at_step = 2850,
        has_hit = true },
    { id = 1200, motion = "236236+K", expected_combo = 6, expected_hp = 3000,
        damage_at_step = 4050, has_hit = true }
}

local function resolve_classic(step)
    if step.id == 1037 then return "528" end
    return step.motion
end

CTTimelineSequenceNormalizer.expand(sequence, resolve_classic)
assert(#sequence == 7, "the second bracketed 528 occurrence must be restored")
assert(sequence[3].id == 1037 and sequence[6].id == 1037, "direction repeats must keep the action ID")
assert(sequence[6]._ct_direction_repeat == true, "the restored step must be traceable")
assert(sequence[6].motion == ">29 (cancel)", "recorded contextual motion must be preserved")
assert(sequence[6].expected_combo == 4, "a direction-only repeat must not increment combo count")
assert(sequence[6].damage_at_step == 2850 and sequence[6].has_hit == false,
    "the restored step must inherit the preceding hit state without becoming a hit")
assert(sequence[7].id == 1200, "the restored direction must precede the final command")

CTTimelineSequenceNormalizer.expand(sequence, resolve_classic)
assert(#sequence == 7, "normalization must be idempotent")

local bracketed = {
    "1f : 5", "1f : 2", "1f : 8", -- pre-trial movement
    "1f : 5+LP",                    -- first known action
    "1f : 5", "1f : 2", "1f : 8",
    "1f : 5+MP",                    -- second known action
    "1f : 5", "1f : 2", "1f : 8" -- trailing movement
}
local guarded = {
    { id = 1, motion = "LP", expected_combo = 1, timeline = bracketed },
    { id = 2, motion = "528", expected_combo = 1 },
    { id = 3, motion = "MP", expected_combo = 2 }
}
CTTimelineSequenceNormalizer.expand(guarded, function(step) return step.motion end)
assert(#guarded == 3, "unbracketed leading/trailing movement must not become trial steps")

local mixed_facing = {
    { index = 1, start_frame = 0, duration = 1, dir = "6" },
    { index = 2, start_frame = 1, duration = 1, dir = "5" },
    { index = 3, start_frame = 2, duration = 1, dir = "4" }
}
assert(#CTTimelineSequenceNormalizer.find_direction_occurrences(mixed_facing, "66") == 0,
    "one direction occurrence must use a consistent facing orientation")

print("combo timeline normalizer tests passed")
