local Installer = {}

local function valid_sequence(value)
    if type(value) ~= "table" or type(value[1]) ~= "table" then return false end
    for _, step in ipairs(value) do
        if type(step) ~= "table" then return false end
    end
    return true
end

local function basename(path)
    return tostring(path or ""):match("([^/\\]+)$")
end

local function write_file(writer, path, value)
    if type(writer) ~= "function" then return false end
    local ok, result = pcall(writer, path, value)
    return ok and result ~= false
end

local function deep_equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] ~= nil then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not deep_equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deep_copy(key, seen)] = deep_copy(child, seen)
    end
    return copy
end

local function sequence_matches(left, right)
    if not valid_sequence(left) or not valid_sequence(right) then return false end
    return deep_equal(left, right)
end

function Installer.plan(item, options)
    item = type(item) == "table" and item or {}
    if item.status ~= "passed" then return nil, "candidate_not_passed" end
    if item.raw_replay_verified ~= true then
        return nil, "candidate_not_raw_replay_verified"
    end

    local source_path = tostring(item.source_file or "")
    local candidate_path = tostring(item.candidate_file or "")
    local source_name = basename(source_path)
    local candidate_name = basename(candidate_path)
    if source_name == nil or candidate_name == nil then
        return nil, "candidate_path_missing"
    end
    if source_name ~= candidate_name then
        return nil, "candidate_source_name_mismatch"
    end

    local normalized_source = source_path:gsub("\\", "/")
    local source_character = normalized_source:match(
        "^TrainingComboTrials_data/CustomCombos/([^/]+)/[^/]+%.json$"
    )
    if source_character == nil then return nil, "source_not_runtime_combo" end

    local normalized_candidate = candidate_path:gsub("\\", "/")
    local candidate_dir, candidate_character, normalized_candidate_name =
        normalized_candidate:match(
            "^(TrainingComboTrials_data/TranscribedCandidates/([^/]+)/.+)/([^/]+%.json)$"
        )
    if candidate_dir == nil then return nil, "candidate_not_transcription_output" end
    if candidate_character ~= source_character
        or normalized_candidate_name ~= source_name then
        return nil, "candidate_source_scope_mismatch"
    end
    local source_dir, source_stem = source_path:match("^(.*[/\\])(.+)%.json$")
    if source_dir == nil or source_stem == nil then
        return nil, "source_copy_path_invalid"
    end
    return {
        source_path = source_path,
        candidate_path = candidate_path,
        target_path = source_dir .. source_stem .. "_z.json",
    }
end

function Installer.install(item, dependencies)
    dependencies = type(dependencies) == "table" and dependencies or {}
    local plan, plan_error = Installer.plan(item, dependencies)
    if not plan then return nil, plan_error end

    local load_file = dependencies.load_file
    if type(load_file) ~= "function" then return nil, "load_file_unavailable" end
    local candidate_ok, candidate = pcall(load_file, plan.candidate_path)
    if not candidate_ok or not valid_sequence(candidate) then
        return nil, "candidate_load_failed"
    end
    local source_ok, source = pcall(load_file, plan.source_path)
    if not source_ok or not valid_sequence(source) then
        return nil, "source_load_failed"
    end

    local installed_candidate = deep_copy(candidate)
    local first = installed_candidate[1]
    if type(first._xt_meta) ~= "table" then
        return nil, "candidate_title_metadata_missing"
    end
    first._xt_meta.title = tostring(first._xt_meta.title or "") .. "z"
    if not write_file(dependencies.dump_file, plan.target_path, installed_candidate) then
        return nil, "candidate_copy_write_failed"
    end

    local verify_ok, installed = pcall(load_file, plan.target_path)
    if not verify_ok or not sequence_matches(installed_candidate, installed) then
        return nil, "candidate_copy_verify_failed"
    end
    plan.step_count = #installed_candidate
    plan.title = first._xt_meta.title
    return plan
end

Installer.valid_sequence = valid_sequence
Installer.sequence_matches = sequence_matches

return Installer
