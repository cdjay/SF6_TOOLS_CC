package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local MotionPresentation = require("func/ComboTrials/MotionPresentation")

assert(MotionPresentation.resolve_named_sequence(1231, "Shun Goku Satsu")
    == "LP,LP,6,LK,HP (瞬狱杀)")
assert(MotionPresentation.resolve_named_sequence("1231", "瞬狱杀")
    == "LP,LP,6,LK,HP (瞬狱杀)")
assert(MotionPresentation.resolve_named_sequence(1231, "236236+P") == nil)
assert(MotionPresentation.resolve_named_sequence(1230, "Shun Goku Satsu") == nil)

print("Motion presentation tests passed")
