package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

local MoveCatalog = require("func/HitConfirm/MoveCatalog")
local CaseCatalog = require("func/HitConfirm/CaseCatalog")

local character = {
    id = 999,
    key = "ESF_TEST",
    name = "TestCharacter",
    display_name = "测试角色"
}

local catalog = MoveCatalog.from_document(character, {
    ["670"] = {
        classic_command = { display = "4+MK" },
        motion_command = { display = "4 + 中" },
        control_support = "classic_modern"
    },
    ["671"] = {
        classic_command = { display = ">HP" },
        motion_command = { display = "> 中" },
        control_support = "classic_modern"
    },
    ["675"] = {
        classic_command = { display = ">HP" },
        control_support = "classic_modern"
    }
})

assert(#catalog.moves == 3)
assert(catalog.moves[1].action_id == 670 and not catalog.moves[1].is_derived)
assert(catalog.moves[2].action_id == 671 and catalog.moves[2].is_derived)
assert(catalog.moves[3].action_id == 675 and catalog.moves[3].is_derived)
assert(catalog.moves[2].label ~= catalog.moves[3].label, "same command must remain distinct by Action ID")
assert(catalog.moves[2].parent_action_id == 670)
assert(catalog.moves[2].label:find("接 4+MK", 1, true))
assert(catalog.starter_labels[1]:find("前置：", 1, true))
assert(catalog.followup_labels[2]:find("后续：[派生", 1, true))

local case = CaseCatalog.build(character, catalog.moves[1], catalog.moves[2])
assert(case._starter_ids[670])
assert(case._followup_ids[671] and not case._followup_ids[675])
assert(case.followups[1].derived == true)

print("hit-confirm move catalog tests passed")
