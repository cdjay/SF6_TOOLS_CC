local json = json

local BcmCatalog = {
    name = "ComboTrials.BcmCatalog"
}

local CATALOG_DIR = "TrainingComboTrials_data/bcm_catalog/"
local EXPECTED_SCHEMA = "sf6cc.bcm-runtime.v1"
local cache = {}

local function safe_character_name(character_name)
    return tostring(character_name or ""):gsub("[^%w_]", "")
end

function BcmCatalog.get_filename(character_name)
    return CATALOG_DIR .. safe_character_name(character_name) .. ".json"
end

function BcmCatalog.load_for_character(character_name)
    local key = safe_character_name(character_name)
    if key == "" or key == "Unknown" then return nil end
    if cache[key] ~= nil then return cache[key] ~= false and cache[key] or nil end

    local ok, loaded = pcall(json.load_file, BcmCatalog.get_filename(key))
    if not ok or type(loaded) ~= "table" or loaded.schema ~= EXPECTED_SCHEMA or type(loaded.actions) ~= "table" then
        cache[key] = false
        return nil
    end
    if loaded.character and safe_character_name(loaded.character) ~= key then
        cache[key] = false
        return nil
    end
    cache[key] = loaded
    return loaded
end

function BcmCatalog.get_classic_display(catalog, action_id)
    if type(catalog) ~= "table" or type(catalog.actions) ~= "table" then return nil end
    local display = catalog.actions[tostring(action_id)]
    if type(display) == "string" and display ~= "" then return display end
    return nil
end

function BcmCatalog.clear_cache(character_name)
    if character_name then cache[safe_character_name(character_name)] = nil else cache = {} end
end

return BcmCatalog
