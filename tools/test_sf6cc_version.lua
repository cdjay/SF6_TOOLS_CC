package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

json = {
    load_file = function(path)
        assert(path == "SF6CC/version.json", "version module must use the canonical runtime path")
        return {
            schema = "sf6cc.product_version.v1",
            product = {
                id = "sf6cc",
                version = "1.2.3",
            },
            recording = {
                game = {
                    id = "sf6",
                    version = "2026-08-03",
                },
            },
            formats = {
                combo_trial = {
                    id = "xt.combo_trial",
                    version = "2.1.0",
                    schema = 3,
                },
            },
        }
    end,
}

local Version = require("func/SF6CC_Version")

assert(Version.loaded == true, "valid canonical version data must load")
assert(Version.PRODUCT_ID == "sf6cc", "product id must come from the version file")
assert(Version.PRODUCT_VERSION == "1.2.3", "product version must come from the version file")
assert(Version.GAME_ID == "sf6", "recording game id must come from the version file")
assert(Version.GAME_VERSION == "2026-08-03",
    "recording game version must come from the version file")
assert(Version.COMBO_JSON_ID == "xt.combo_trial", "combo format id must come from the version file")
assert(Version.COMBO_JSON_VERSION == "2.1.0", "combo format version must come from the version file")
assert(Version.COMBO_JSON_SCHEMA == 3, "combo schema must come from the version file")
assert(_G.SF6CC_VERSION == "1.2.3", "global product version must match the version file")

package.loaded["func/SF6CC_Version"] = nil
json.load_file = function() return nil end
local MissingVersion = require("func/SF6CC_Version")
assert(MissingVersion.loaded == false, "missing version data must not be accepted")
assert(MissingVersion.PRODUCT_VERSION == "unknown", "missing product version must never use a stale fallback")
assert(MissingVersion.GAME_VERSION == "unknown", "missing game version must never use a stale fallback")
assert(type(MissingVersion.error) == "string", "missing version data must report an error")

print("SF6CC version tests passed")
