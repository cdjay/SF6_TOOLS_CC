-- FallbackComboMigration.lua
-- A fighter that data/SF6CC/fighters.json does not list yet is stored under
-- its fallback key ESF_<id> (FighterRoster.fallback_key), so a new fighter
-- can be recorded on release day. Once a later roster names the fighter, its
-- combos would stay behind in CustomCombos/ESF_<id>/. This copies them into
-- CustomCombos/<Key>/ once per session: the file-name prefix and
-- _xt_meta.character are rewritten to the new key, existing files are never
-- overwritten, and the originals stay in place (REFramework's Lua sandbox
-- offers no rename or delete).

local FallbackComboMigration = {
    name = "ComboTrials.FallbackComboMigration",
    ROOT = "TrainingComboTrials_data/CustomCombos/",
}

local function file_name(path)
    return tostring(path or ""):match("([^/\\]+)$")
end

local function escape_pattern(text)
    return (tostring(text):gsub("([^%w])", "%%%1"))
end

-- deps: glob(pattern) -> paths, load(path) -> table|nil,
--       dump(path, table) -> boolean, create_dir(path),
--       fallback_key(character) -> "ESF_034" | nil for unknown fighters.
-- Returns migrate(character) -> number of files copied.
function FallbackComboMigration.new(deps)
    local done = {}
    return function(character)
        if type(character) ~= "string" or character == "" or done[character] then return 0 end
        done[character] = true
        local legacy = deps.fallback_key(character)
        if type(legacy) ~= "string" or legacy == "" or legacy == character then return 0 end

        local ok_sources, sources = pcall(deps.glob,
            "TrainingComboTrials_data\\\\CustomCombos\\\\" .. legacy .. "\\\\.*json")
        if not ok_sources or type(sources) ~= "table" or #sources == 0 then return 0 end
        local ok_targets, targets = pcall(deps.glob,
            "TrainingComboTrials_data\\\\CustomCombos\\\\" .. character .. "\\\\.*json")
        local existing = {}
        for _, path in ipairs(ok_targets and type(targets) == "table" and targets or {}) do
            local name = file_name(path)
            if name then existing[name:lower()] = true end
        end

        if deps.create_dir then
            pcall(deps.create_dir, "TrainingComboTrials_data/CustomCombos")
            pcall(deps.create_dir, FallbackComboMigration.ROOT .. character)
        end
        local prefix = "^" .. escape_pattern(legacy) .. "_"
        local copied = 0
        for _, source in ipairs(sources) do
            local name = file_name(source)
            if name then
                local target_name = name:gsub(prefix, character .. "_")
                if not existing[target_name:lower()] then
                    local ok_load, sequence = pcall(deps.load, source)
                    local first = ok_load and type(sequence) == "table" and sequence[1] or nil
                    if type(first) == "table" then
                        local meta = first._xt_meta
                        if type(meta) == "table" and meta.character == legacy then meta.character = character end
                        local ok_dump, written = pcall(deps.dump,
                            FallbackComboMigration.ROOT .. character .. "/" .. target_name, sequence)
                        if ok_dump and written ~= false then
                            existing[target_name:lower()] = true
                            copied = copied + 1
                        end
                    end
                end
            end
        end
        return copied
    end
end

return FallbackComboMigration
