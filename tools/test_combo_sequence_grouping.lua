local grouping = dofile("autorun/func/ComboTrials/SequenceGrouping.lua")
local character_rules = dofile("autorun/func/ComboTrials/CharacterRules.lua")

local deejay_grouping_rules = character_rules.build_sequence_grouping_rules({
    _character = {
        sequence_grouping = {
            structural_followup_chains = {
                { 1219, 1220, 1221, 1222, 1223, 1224, 1225 },
                { 1230, 1231, 1232, 1233, 1234, 1235, 1236 },
            },
        },
    },
}, {})
local juri_grouping_rules = character_rules.build_sequence_grouping_rules({
    _character = {
        sequence_grouping = { break_followup_after_ids = "1218" },
    },
}, {})
local ed_grouping_rules = character_rules.build_sequence_grouping_rules({
    _character = {
        sequence_grouping = {
            structural_followup_chains = {
                { 986, 989 },
                { 986, 990 },
                { 986, 991 },
                { 988, 989 },
                { 988, 990 },
                { 988, 991 },
            },
        },
    },
}, {})

local function group_ids(sequence)
    local ids = {}
    for index, step in ipairs(sequence) do ids[index] = step.group_id end
    return table.concat(ids, ",")
end

local sa2_hp = {
    { id = 1229, motion = "236236+HP", _xt_meta = { character = "DeeJay" } },
    { id = 1230, motion = "LP" },
    { id = 1231, motion = "MP" },
    { id = 1232, motion = "HP" },
    { id = 1233, motion = "LK" },
    { id = 1234, motion = "MK" },
    { id = 1235, motion = "HK" },
    { id = 1236, motion = "HK" }
}
grouping.assign_groups(sa2_hp, nil, deejay_grouping_rules)
assert(group_ids(sa2_hp) == "1,2,2,2,2,2,2,2",
    "Dee Jay HP SA2 rhythm inputs must share one row after the first LP")
assert(sa2_hp[3].motion == "MP",
    "structural grouping must not rewrite the recorded command text")

local sa2_mp = {
    { id = 1218, motion = "236236+MP" },
    { id = 1219, motion = "LP" },
    { id = 1220, motion = "MP" },
    { id = 1221, motion = "HP" },
    { id = 1222, motion = "LK" },
    { id = 1223, motion = "MK" },
    { id = 1224, motion = "HK" },
    { id = 1225, motion = "HK" }
}
grouping.assign_groups(sa2_mp, "Dee Jay", deejay_grouping_rules)
assert(group_ids(sa2_mp) == "1,2,2,2,2,2,2,2",
    "Dee Jay MP SA2 rhythm inputs must support normalized character names")

local interrupted = {
    { id = 1230, motion = "LP" },
    { id = 700, motion = "2+MP" },
    { id = 1231, motion = "MP" }
}
grouping.assign_groups(interrupted, "DeeJay", deejay_grouping_rules)
assert(group_ids(interrupted) == "1,2,3",
    "an interrupted SA2 action list must not merge unrelated steps")

local other_character = {
    { id = 1230, motion = "LP", _xt_meta = { character = "Juri" } },
    { id = 1231, motion = "MP" }
}
grouping.assign_groups(other_character)
assert(group_ids(other_character) == "1,2",
    "Dee Jay action IDs must not alter another character's grouping")

local legacy = {
    { id = 1, motion = "LP" },
    { id = 2, motion = ">MP" },
    { id = 3, motion = ">HP" }
}
grouping.assign_groups(legacy)
assert(group_ids(legacy) == "1,1,1",
    "legacy text-prefixed follow-ups must remain compatible")
assert(grouping.ensure_followup_prefix("MP") == ">MP",
    "group rendering must restore a missing follow-up marker")
assert(grouping.ensure_followup_prefix(">MP") == ">MP",
    "group rendering must not duplicate an existing follow-up marker")

local juri = {
    { id = 1218, motion = "236236+K", _xt_meta = { character = "Juri" } },
    { id = 999, motion = ">K" }
}
grouping.assign_groups(juri, nil, juri_grouping_rules)
assert(group_ids(juri) == "1,2" and juri[2].motion == "K",
    "the legacy Juri false-follow-up exception must remain intact")

local ed_kill_rush_followups = {
    { id = 986, motion = "KK" },
    { id = 989, motion = "6+P" },
    { id = 986, motion = "KK" },
    { id = 990, motion = "6+P" },
    { id = 986, motion = "KK" },
    { id = 991, motion = "6+P" },
    { id = 988, motion = "KK" },
    { id = 989, motion = "6+P" },
    { id = 988, motion = "KK" },
    { id = 990, motion = "6+P" },
    { id = 988, motion = "KK" },
    { id = 991, motion = "6+P" },
}
grouping.assign_groups(ed_kill_rush_followups, "Ed", ed_grouping_rules)
assert(group_ids(ed_kill_rush_followups)
        == "1,1,2,2,3,3,4,4,5,5,6,6",
    "all Ed KK to 6+P Action variants must render as one structural command row")
local unrelated_ed_followup = {
    { id = 621, motion = "HK" },
    { id = 989, motion = "6+P" },
}
grouping.assign_groups(unrelated_ed_followup, "Ed", ed_grouping_rules)
assert(group_ids(unrelated_ed_followup) == "1,2",
    "Ed 6+P must not join a row after an undeclared predecessor")

print("combo sequence grouping tests passed")
