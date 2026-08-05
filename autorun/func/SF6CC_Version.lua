local Version = {
    FILE = "SF6CC/version.json",
    PRODUCT_ID = "sf6cc",
    PRODUCT_VERSION = "unknown",
    GAME_ID = "sf6",
    GAME_VERSION = "unknown",
    COMBO_JSON_ID = "xt.combo_trial",
    COMBO_JSON_VERSION = "unknown",
    COMBO_JSON_SCHEMA = 0,
    loaded = false,
    error = nil
}

local function fail(message)
    Version.error = tostring(message)
    pcall(function()
        if log and log.error then
            log.error("[SF6CC] 无法读取产品版本：" .. Version.error)
        end
    end)
end

local function load_version()
    if type(json) ~= "table" or type(json.load_file) ~= "function" then
        fail("json.load_file 不可用")
        return
    end

    local ok, document = pcall(json.load_file, Version.FILE)
    if not ok then
        fail(document)
        return
    end
    if type(document) ~= "table" or document.schema ~= "sf6cc.product_version.v1" then
        fail("版本文件缺失或 schema 无效：" .. Version.FILE)
        return
    end

    local product = document.product
    local recording = document.recording
    local game = type(recording) == "table" and recording.game or nil
    local formats = document.formats
    local combo = type(formats) == "table" and formats.combo_trial or nil
    if type(product) ~= "table"
        or type(product.id) ~= "string" or product.id == ""
        or type(product.version) ~= "string"
        or not product.version:match("^%d+%.%d+%.%d+[%w%.%+%-]*$")
        or type(game) ~= "table"
        or type(game.id) ~= "string" or game.id == ""
        or type(game.version) ~= "string"
        or not game.version:match("^%d%d%d%d%-%d%d%-%d%d$")
        or type(combo) ~= "table"
        or type(combo.id) ~= "string" or combo.id == ""
        or type(combo.version) ~= "string" or combo.version == ""
        or type(combo.schema) ~= "number"
        or combo.schema < 1 or combo.schema ~= math.floor(combo.schema) then
        fail("版本文件字段不完整：" .. Version.FILE)
        return
    end

    Version.PRODUCT_ID = product.id
    Version.PRODUCT_VERSION = product.version
    Version.GAME_ID = game.id
    Version.GAME_VERSION = game.version
    Version.COMBO_JSON_ID = combo.id
    Version.COMBO_JSON_VERSION = combo.version
    Version.COMBO_JSON_SCHEMA = math.floor(combo.schema)
    Version.loaded = true
end

load_version()
_G.SF6CC_VERSION = Version.PRODUCT_VERSION

return Version
