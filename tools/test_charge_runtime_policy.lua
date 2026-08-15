package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Policy = require("func/ComboTrials/ChargeRuntimePolicy")

assert(Policy.is_charge_stock_action("Ingrid", 969) == true)
assert(Policy.is_charge_stock_action("Ingrid", 970) == false)
assert(Policy.is_charge_stock_action("Ryu", 969) == false)
assert(Policy.should_track_physical_hold("Lily") == true)
assert(Policy.should_track_physical_hold("JP") == false)
assert(Policy.should_autodetect_charge_max("JP") == true)
assert(Policy.should_autodetect_charge_max("Lily") == true)
assert(Policy.should_autodetect_charge_max("Luke") == false)

assert(Policy.evaluate_status("Luke", 2, 2, nil, 5, 7) == "Instant")
assert(Policy.evaluate_status("Luke", 6, 2, nil, 5, 7) == "PERFECT!")
assert(Policy.evaluate_status("Luke", 4, 2, nil, 5, 7) == "Partial")
assert(Policy.evaluate_status("Luke", 8, 2, nil, 5, 7) == "LATE")
assert(Policy.evaluate_status("Luke", 4, 2, 6, nil, nil) == "Partial")
assert(Policy.evaluate_status("JP", 2, 2, 6) == "Instant")
assert(Policy.evaluate_status("JP", 6, 2, 6) == "FAKE")
assert(Policy.evaluate_status("JP", 4, 2, 6) == "Partial")
assert(Policy.evaluate_status("Lily", 2, 2, 6) == "Lv1")
assert(Policy.evaluate_status("Lily", 6, 2, 6) == "Lv3")
assert(Policy.evaluate_status("Lily", 4, 2, 6) == "Lv2")
assert(Policy.evaluate_status("Ryu", 0, 2, 6) == "Instant")
assert(Policy.evaluate_status("Ryu", 2, 2, 6) == "Instant")
assert(Policy.evaluate_status("Ryu", 4, 2, 6) == "Partial")
assert(Policy.evaluate_status("Ryu", 6, 2, 6) == "Maxed")

print("Charge runtime policy tests passed")
