package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local RawSha256 = require("func/ComboTrials/Raw/RawSha256")

assert(RawSha256.digest("") ==
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
assert(RawSha256.digest("abc") ==
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
assert(RawSha256.digest(string.rep("a", 1000000)) ==
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")

print("raw sha256 tests passed")
