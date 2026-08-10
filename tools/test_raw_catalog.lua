package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local RawCatalog = require("func/ComboTrials/Raw/RawCatalog")
local Telemetry = require("func/ComboTrials/Telemetry")

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = deep_copy(item)
    end
    return copy
end

-- Pure-Lua fixture. The module under test never touches the REFramework
-- globals when read_file/decode/sha256 are injected. Profiles use the plural
-- parallel command-variant contract: command_definition_uids,
-- variant_indexes and direct_command_tokens always have equal length.
local function make_artifact(overrides)
    local artifact = {
        schema = "sf6.raw.current.v1",
        algorithm_version = "raw-current.v1",
        authority = "current_full_bcm_atomic_fact_only",
        auto_approved = false,
        build = {
            build_uid = "sf6b_c0269f7351fc73e06633b780",
            display_version = "2026-08-03",
            game_version = "1.001.000",
            captured_at = "2026-08-03T00:00:00Z",
            exporter = { name = "test", version = "1", commit = "abc" },
        },
        source = {
            ac = { file = "ac.bin", schema = "x", sha256 = ("a"):rep(64), bytes = 1, capture = {} },
            bcm = { file = "bcm.bin", schema = "x", sha256 = ("b"):rep(64), bytes = 1, capture = {} },
        },
        character = { fighter_id = 20, character = "EHonda" },
        action_catalog = {
            actions = {
                {
                    raw_action_uid = "act_1",
                    source_scope = "character",
                    style_index = 0,
                    resource_index = 0,
                    action_id = 600,
                    dictionary_index = nil,
                    dictionary_key = nil,
                    dictionary_hash_code = nil,
                    root_object_id = nil,
                    root_fields = {},
                    raw_locator = {},
                },
            },
            edges = {},
        },
        command_catalog = {
            definitions = {
                {
                    definition_uid = "def_1",
                    command_no = 1,
                    variant_index = 0,
                    charge_bit = "0",
                    max_frame = 20,
                    total_frame = 20,
                    raw_locator = {},
                    inputs = {
                        {
                            input_uid = "in_1",
                            ordinal = 0,
                            direction = "2",
                            raw_mask = "16",
                            frame_count = 10,
                            input_type = 1,
                            charge_id = nil,
                            charge_release = false,
                        },
                    },
                },
                {
                    definition_uid = "def_2",
                    command_no = 1,
                    variant_index = 1,
                    charge_bit = "0",
                    max_frame = 30,
                    total_frame = 30,
                    raw_locator = {},
                    inputs = {
                        {
                            input_uid = "in_2",
                            ordinal = 0,
                            direction = "6",
                            raw_mask = "16",
                            frame_count = 12,
                            input_type = 1,
                            charge_id = nil,
                            charge_release = false,
                        },
                    },
                },
                {
                    definition_uid = "def_3",
                    command_no = 2,
                    variant_index = 0,
                    charge_bit = "0",
                    max_frame = 40,
                    total_frame = 40,
                    raw_locator = {},
                    inputs = {},
                },
            },
            triggers = {
                {
                    raw_trigger_uid = "trg_1",
                    trigger_index = 10,
                    action_id = 600,
                    raw_object_id = 7,
                    conditions = { kind = "opaque" },
                    raw_locator = { source = "bcm.bin", row = 3 },
                    profiles = {
                        {
                            raw_command_uid = "cmd_norm",
                            profile_name = "norm",
                            command_no = 1,
                            command_index = 0,
                            command_definition_uids = { "def_1" },
                            variant_indexes = { 0 },
                            direct_command_tokens = { "2+P" },
                            ng_flag = false,
                            enabled = true,
                            button_mask = "16",
                            button_condition = "0",
                            dc_exc_flags = "0",
                            ng_key_flags = "0",
                            preceding_time = 4,
                            raw_profile = {},
                            raw_locator = { source = "bcm.bin", row = 3, profile = "norm" },
                        },
                        {
                            raw_command_uid = "cmd_easy",
                            profile_name = "easy",
                            command_no = 1,
                            command_index = 1,
                            command_definition_uids = { "def_2" },
                            variant_indexes = { 1 },
                            direct_command_tokens = { "2+PP" },
                            ng_flag = false,
                            enabled = true,
                            button_mask = "16",
                            button_condition = "0",
                            dc_exc_flags = "0",
                            ng_key_flags = "0",
                            preceding_time = 4,
                            raw_profile = {},
                            raw_locator = { source = "bcm.bin", row = 3, profile = "easy" },
                        },
                    },
                },
                {
                    raw_trigger_uid = "trg_2",
                    trigger_index = 11,
                    action_id = 600,
                    raw_object_id = 7,
                    conditions = {},
                    raw_locator = { source = "bcm.bin", row = 4 },
                    profiles = {
                        {
                            raw_command_uid = "cmd_multi",
                            profile_name = "norm",
                            command_no = 1,
                            command_index = 2,
                            command_definition_uids = { "def_1", "def_2" },
                            variant_indexes = { 0, 1 },
                            direct_command_tokens = { "2+P", "2+PP" },
                            ng_flag = true,
                            enabled = false,
                            button_mask = "16",
                            button_condition = "0",
                            dc_exc_flags = "0",
                            ng_key_flags = "0",
                            preceding_time = 5,
                            raw_profile = {},
                            raw_locator = { source = "bcm.bin", row = 4, profile = "norm" },
                        },
                    },
                },
                {
                    raw_trigger_uid = "trg_3",
                    trigger_index = 12,
                    action_id = 601,
                    raw_object_id = 8,
                    conditions = {},
                    raw_locator = { source = "bcm.bin", row = 5 },
                    profiles = {
                        {
                            raw_command_uid = "cmd_601",
                            profile_name = "sprt",
                            command_no = 2,
                            command_index = 3,
                            command_definition_uids = { "def_3" },
                            variant_indexes = { 0 },
                            direct_command_tokens = { "1+P" },
                            ng_flag = nil,
                            enabled = true,
                            button_mask = "1",
                            button_condition = "0",
                            dc_exc_flags = "0",
                            ng_key_flags = "0",
                            preceding_time = nil,
                            raw_profile = {},
                            raw_locator = { source = "bcm.bin", row = 5, profile = "sprt" },
                        },
                    },
                },
                {
                    raw_trigger_uid = "trg_4",
                    trigger_index = 13,
                    action_id = 602,
                    raw_object_id = 9,
                    conditions = {},
                    raw_locator = { source = "bcm.bin", row = 6 },
                    profiles = {
                        {
                            raw_command_uid = "cmd_button",
                            profile_name = "norm",
                            command_no = -1,
                            command_index = -1,
                            command_definition_uids = {},
                            variant_indexes = {},
                            direct_command_tokens = { "MP" },
                            ng_flag = false,
                            enabled = true,
                            button_mask = "32",
                            button_condition = "0",
                            dc_exc_flags = "0",
                            ng_key_flags = "0",
                            preceding_time = 4,
                            raw_profile = {},
                            raw_locator = { source = "bcm.bin", row = 6, profile = "norm" },
                        },
                    },
                },
            },
        },
        counts = {
            actions = 1,
            ac_edges = 0,
            bcm_triggers = 4,
            bcm_commands = 5,
            bcm_command_definitions = 3,
            bcm_inputs = 2,
        },
    }
    if type(overrides) == "function" then
        overrides(artifact)
    elseif type(overrides) == "table" then
        for _, fn in ipairs(overrides) do
            fn(artifact)
        end
    end
    return artifact
end

local function derive_root_digest(manifest)
    local characters = {}
    for _, entry in ipairs(manifest.characters) do
        characters[#characters + 1] = {
            fighter_id = entry.fighter_id,
            character = entry.character,
            file = entry.file,
            sha256 = entry.sha256,
            bytes = entry.bytes,
            counts = entry.counts,
            source = {
                ac = {
                    file = entry.source.ac.file,
                    schema = entry.source.ac.schema,
                    sha256 = entry.source.ac.sha256,
                    bytes = entry.source.ac.bytes,
                },
                bcm = {
                    file = entry.source.bcm.file,
                    schema = entry.source.bcm.schema,
                    sha256 = entry.source.bcm.sha256,
                    bytes = entry.source.bcm.bytes,
                },
            },
        }
    end
    table.sort(characters, function(left, right)
        return left.fighter_id < right.fighter_id
    end)
    return Telemetry.sha256(Telemetry.encode_json({
        schema = manifest.schema,
        algorithm_version = manifest.algorithm_version,
        authority = manifest.authority,
        auto_approved = manifest.auto_approved,
        build = manifest.build,
        generator = manifest.generator,
        source = manifest.source,
        generated_at = manifest.generated_at,
        character_coverage = {
            expected = manifest.character_coverage.expected,
            generated = manifest.character_coverage.generated,
            failed_count = #manifest.character_coverage.failed,
        },
        totals = manifest.totals,
        characters = characters,
    }))
end

local function make_manifest(artifact, overrides)
    local manifest = {
        schema = "sf6.raw.current-manifest.v1",
        algorithm_version = "raw-current.v1",
        authority = "current_full_bcm_atomic_fact_only",
        auto_approved = false,
        build = deep_copy(artifact.build),
        generator = { name = "sf6acbcm-raw-current", version = "raw-current.v1" },
        source = {
            manifest = {
                file = "raw-current-manifest.v1.json",
                schema = "sf6acbcm.build-manifest.v1",
                sha256 = ("c"):rep(64),
                bytes = 1,
            },
        },
        characters = {
            {
                fighter_id = artifact.character.fighter_id,
                character = artifact.character.character,
                file = "f" .. string.format("%03d", artifact.character.fighter_id)
                    .. "-raw-current.v1.json",
                sha256 = ("d"):rep(64),
                bytes = 1234,
                counts = deep_copy(artifact.counts),
                source = {
                    ac = {
                        file = artifact.source.ac.file,
                        schema = artifact.source.ac.schema,
                        sha256 = artifact.source.ac.sha256,
                        bytes = artifact.source.ac.bytes,
                        capture = deep_copy(artifact.source.ac.capture),
                    },
                    bcm = {
                        file = artifact.source.bcm.file,
                        schema = artifact.source.bcm.schema,
                        sha256 = artifact.source.bcm.sha256,
                        bytes = artifact.source.bcm.bytes,
                        capture = deep_copy(artifact.source.bcm.capture),
                    },
                },
            },
        },
        character_coverage = { expected = 1, generated = 1, failed = {} },
        totals = deep_copy(artifact.counts),
        root_digest = ("e"):rep(64),
        generated_at = artifact.build.captured_at,
    }
    if type(overrides) == "function" then
        overrides(manifest)
    elseif type(overrides) == "table" then
        for _, fn in ipairs(overrides) do
            fn(manifest)
        end
    end
    manifest.root_digest = derive_root_digest(manifest)
    return manifest
end

local function load_fixture(options)
    options = options or {}
    local artifact = options.artifact or make_artifact()
    local fighter_id = options.fighter_id or 20
    local file = options.file
        or ("f%03d-raw-current.v1.json"):format(fighter_id)
    local manifest_file = options.manifest_file or "raw-current-manifest.v1.json"
    local dir = options.dir or "raw/current"
    local artifact_raw = options.artifact_raw
        or ("%s raw artifact bytes"):format(file)
    local manifest_raw = options.manifest_raw
        or ("%s manifest bytes"):format(manifest_file)
    local artifact_reads = 0
    local manifest_reads = 0

    local catalog, status = RawCatalog.load({
        dir = dir,
        fighter_id = fighter_id,
        file = file,
        manifest_file = manifest_file,
        manifest_required = options.manifest_required,
        use_cache = options.use_cache,
        expected_build_uid = options.expected_build_uid,
        expected_display_version = options.expected_display_version,
        read_file = function(path)
            local expected_manifest_path = dir .. "/" .. manifest_file
            local expected_artifact_path = dir .. "/" .. file
            if path == expected_manifest_path then
                manifest_reads = manifest_reads + 1
                if options.manifest_unreadable == true then return nil end
                return manifest_raw
            end
            assert(path == expected_artifact_path,
                "unexpected artifact read path " .. tostring(path))
            artifact_reads = artifact_reads + 1
            if options.artifact_unreadable == true then return nil end
            return artifact_raw
        end,
        decode = function(raw)
            if raw == manifest_raw then
                if options.manifest_malformed == true then return nil end
                local manifest = options.manifest or make_manifest(artifact)
                local entry
                for _, candidate in ipairs(manifest.characters) do
                    if candidate.fighter_id == fighter_id then
                        entry = candidate
                        break
                    end
                end
                if entry ~= nil then
                    entry.bytes = #artifact_raw
                    entry.sha256 = Telemetry.sha256(artifact_raw)
                end
                if options.mutate_manifest then
                    options.mutate_manifest(manifest)
                end
                if options.recompute_root ~= false then
                    manifest.root_digest = derive_root_digest(manifest)
                end
                return manifest
            end
            assert(raw == artifact_raw, "unexpected artifact decode input")
            if options.artifact_malformed == true then return nil end
            if options.mutate_artifact then
                options.mutate_artifact(artifact)
            end
            return artifact
        end,
        sha256 = Telemetry.sha256,
    })
    return catalog, status, artifact_reads, manifest_reads
end

local function expect_load_failure(status, code)
    assert(type(status) == "table" and status.ok == false,
        "load must fail closed, got ok=" .. tostring(status and status.ok))
    assert(status.code == code,
        "expected error code " .. code .. ", got " .. tostring(status.code)
            .. " (" .. tostring(status.message) .. ")")
end

RawCatalog.reset_cache()

-- Contract constants and default data location.
assert(RawCatalog.SCHEMA == "sf6.raw.current.v1")
assert(RawCatalog.ALGORITHM_VERSION == "raw-current.v1")
assert(RawCatalog.AUTHORITY == "current_full_bcm_atomic_fact_only")
assert(RawCatalog.DIRECTORY == "TrainingComboTrials_data/raw/current")

-- Valid load verifies bytes/SHA-256 and exposes build, character, counts and
-- file facts.
local catalog, status, reads, manifest_reads = load_fixture()
assert(catalog ~= nil and status.ok == true,
    "valid artifact must load: " .. tostring(status and status.message))
assert(reads == 1)
assert(manifest_reads == 1)
assert(status.cache_hit == false)
assert(status.file == "f020-raw-current.v1.json")
assert(catalog:get_file() == "f020-raw-current.v1.json")
assert(catalog:get_read_count() == 1)
local build = catalog:get_build_info()
assert(build.build_uid == "sf6b_c0269f7351fc73e06633b780")
assert(build.display_version == "2026-08-03")
local character = catalog:get_character()
assert(character.fighter_id == 20 and character.character == "EHonda")
local counts = catalog:get_counts()
assert(counts.bcm_triggers == 4 and counts.bcm_commands == 5)
assert(counts.bcm_command_definitions == 3 and counts.bcm_inputs == 2)

-- Direct bindings preserve trigger order, profile order, duplicates, all
-- profile variants and disabled rows. Command references are plural arrays.
local bindings, binding_status = catalog:get_bindings(600)
assert(bindings ~= nil and binding_status == "DIRECT")
assert(#bindings == 3, "action 600 must keep all three direct profile rows")
assert(bindings[1].raw_trigger_uid == "trg_1")
assert(bindings[1].profile_name == "norm" and bindings[1].enabled == true)
assert(bindings[1].command_definition_uids[1] == "def_1")
assert(bindings[1].variant_indexes[1] == 0)
assert(bindings[1].direct_command_tokens[1] == "2+P")
assert(bindings[1].command_index == 0)
assert(bindings[1].action_id == 600)
assert(bindings[1].conditions.kind == "opaque")
assert(bindings[1].profile_raw_locator.profile == "norm")
assert(bindings[2].profile_name == "easy")
assert(bindings[2].command_definition_uids[1] == "def_2")
assert(bindings[2].variant_indexes[1] == 1)
assert(bindings[2].direct_command_tokens[1] == "2+PP")
assert(bindings[3].raw_trigger_uid == "trg_2")
assert(bindings[3].profile_name == "norm"
    and bindings[3].enabled == false and bindings[3].ng_flag == true)
assert(#bindings[3].command_definition_uids == 2)
assert(#bindings[3].variant_indexes == 2)
assert(#bindings[3].direct_command_tokens == 2)
assert(bindings[3].direct_command_tokens[2] == "2+PP")
assert(catalog:has_direct_binding(600) == true)
local binding_snapshot = catalog:get_bindings_snapshot(600)
assert(binding_snapshot[1].direct_command_tokens[1] == "2+P")
binding_snapshot[1].direct_command_tokens[1] = "changed"
assert(catalog:get_bindings(600)[1].direct_command_tokens[1] == "2+P")

-- Definitions resolve by uid; variant_index is a definition fact, not a
-- profile selector.
local def_lookup = catalog:get_definition("def_1")
assert(def_lookup ~= nil and def_lookup.command_no == 1)
assert(def_lookup.variant_index == 0)
assert(#def_lookup.inputs == 1)
assert(def_lookup.inputs[1].direction == "2")
assert(catalog:get_definition("def_2").variant_index == 1)
assert(catalog:get_definition("def_missing") == nil)
assert(#catalog:list_definitions() == 3)

-- Unknown actions return the deterministic no-direct status, never nil-only
-- ambiguity and never owner/alias/AC inheritance.
local none, none_status = catalog:get_bindings(999999)
assert(none == nil and none_status == "NO_DIRECT_BCM_BINDING")
assert(catalog:has_direct_binding(999999) == false)
local zero, zero_status = catalog:get_bindings(0)
assert(zero == nil and zero_status == "NO_DIRECT_BCM_BINDING")

-- Audit view lists facts, integrity and an independently rebuilt index
-- reconciliation. Nothing is hardcoded to zero.
local audit = catalog:get_audit_info()
assert(audit.bindings.direct_binding_count == 5)
assert(audit.bindings.direct_action_count == 3)
assert(audit.counts.bcm_triggers == 4)
local reconciliation = audit.reconciliation
assert(reconciliation.indexed_direct_bindings == 5)
assert(reconciliation.declared_bcm_commands == 5)
assert(reconciliation.direct_binding_match == true)
assert(reconciliation.indexed_actions == 1
    and reconciliation.declared_actions == 1 and reconciliation.action_match == true)
assert(reconciliation.indexed_ac_edges == 0
    and reconciliation.declared_ac_edges == 0 and reconciliation.ac_edge_match == true)
assert(reconciliation.indexed_triggers == 4
    and reconciliation.declared_bcm_triggers == 4 and reconciliation.trigger_match == true)
assert(reconciliation.indexed_definitions == 3
    and reconciliation.declared_bcm_command_definitions == 3
    and reconciliation.definition_match == true)
assert(reconciliation.indexed_bcm_inputs == 2
    and reconciliation.declared_bcm_inputs == 2 and reconciliation.input_match == true)
assert(reconciliation.indexed_definition_refs == 5)
assert(reconciliation.referenced_definition_count == 3)
assert(reconciliation.all_match == true)
local integrity = audit.integrity
assert(integrity.verified == true)
assert(integrity.artifact_sha256 == Telemetry.sha256("f020-raw-current.v1.json raw artifact bytes"))
assert(integrity.artifact_bytes == #"f020-raw-current.v1.json raw artifact bytes")
assert(integrity.manifest_root_digest_verified == true)
assert(audit.manifest.root_digest ~= nil)
assert(audit.manifest.loaded_from == "raw-current-manifest.v1.json")
local direct_actions = catalog:list_actions_with_direct_bindings()
assert(#direct_actions == 3
    and direct_actions[1] == 600 and direct_actions[2] == 601 and direct_actions[3] == 602)

-- Read-only views cannot leak mutation back into the catalog.
local mutate_ok = pcall(function() bindings[1].enabled = false end)
assert(mutate_ok == false)
assert(catalog:get_bindings(600)[1].enabled == true)
mutate_ok = pcall(function() bindings[3].direct_command_tokens[1] = "x" end)
assert(mutate_ok == false)
assert(catalog:get_bindings(600)[3].direct_command_tokens[1] == "2+P")
mutate_ok = pcall(function() build.build_uid = "hacked" end)
assert(mutate_ok == false)
mutate_ok = pcall(function() catalog.injected = true end)
assert(mutate_ok == false)
assert(catalog:get_build_info().build_uid == "sf6b_c0269f7351fc73e06633b780")

-- Lazy single-slot cache: second load for the same directory/fighter reuses
-- the same catalog and does not read files again.
local cached_catalog, cached_status, cached_reads, cached_manifest_reads = load_fixture()
assert(cached_catalog == catalog and cached_status.cache_hit == true)
assert(cached_reads == 0)
assert(cached_manifest_reads == 0)
assert(cached_status.read_count == 1)

-- A different directory evicts the single active entry; the original
-- directory must be read again instead of retaining every visited character.
local other, other_status, other_reads = load_fixture({
    dir = "raw/other",
    artifact = make_artifact(),
})
assert(other ~= catalog and other_status.ok == true and other_reads == 1)
local evicted, evicted_status, evicted_reads = load_fixture({})
assert(evicted ~= catalog, "single active character cache must evict old entries")
assert(evicted_status.ok == true and evicted_reads == 1)

-- use_cache=false forces a fresh read and returns a fresh catalog.
RawCatalog.reset_cache()
local fresh, fresh_status, fresh_reads = load_fixture({ use_cache = false })
assert(fresh ~= catalog and fresh_status.cache_hit == false)
assert(fresh_reads == 1 and fresh_status.read_count == 1)

-- The fighter_id in the file name and the artifact must agree.
local fighter6_manifest = make_manifest(make_artifact(), function(m)
    m.characters[1].fighter_id = 6
    m.characters[1].file = "f006-raw-current.v1.json"
end)
local wrong_fighter, wrong_status, wrong_reads = load_fixture({
    fighter_id = 6,
    file = "f006-raw-current.v1.json",
    manifest = fighter6_manifest,
})
assert(wrong_fighter == nil and wrong_reads == 1)
expect_load_failure(wrong_status, "character_mismatch")

-- Optional build assertions fail closed.
local wrong_build, wrong_build_status = load_fixture({
    expected_build_uid = "sf6b_otherbuild",
    use_cache = false,
})
assert(wrong_build == nil)
expect_load_failure(wrong_build_status, "build_mismatch")
local wrong_display, wrong_display_status = load_fixture({
    expected_display_version = "2025-01-01",
    use_cache = false,
})
assert(wrong_display == nil)
expect_load_failure(wrong_display_status, "build_mismatch")

-- Cache entry with a matching expected build is trusted.
RawCatalog.reset_cache()
local first_gate, first_gate_status = load_fixture({})
assert(first_gate ~= nil and first_gate_status.cache_hit == false)
local gate_hit, gate_hit_status = load_fixture({
    expected_build_uid = "sf6b_c0269f7351fc73e06633b780",
})
assert(gate_hit == first_gate and gate_hit_status.cache_hit == true)

-- Schema/algorithm/authority/auto_approved envelope failures.
local bad_schema, bad_schema_status = load_fixture({
    artifact = make_artifact(function(a) a.schema = "sf6.raw.current.v2" end),
    use_cache = false,
})
assert(bad_schema == nil)
expect_load_failure(bad_schema_status, "unsupported_schema")
local bad_algorithm, bad_algorithm_status = load_fixture({
    artifact = make_artifact(function(a) a.algorithm_version = "other" end),
    use_cache = false,
})
assert(bad_algorithm == nil)
expect_load_failure(bad_algorithm_status, "unsupported_algorithm")
local bad_authority, bad_authority_status = load_fixture({
    artifact = make_artifact(function(a) a.authority = "semantic" end),
    use_cache = false,
})
assert(bad_authority == nil)
expect_load_failure(bad_authority_status, "authority_mismatch")
local auto_approved, auto_approved_status = load_fixture({
    artifact = make_artifact(function(a) a.auto_approved = true end),
    use_cache = false,
})
assert(auto_approved == nil)
expect_load_failure(auto_approved_status, "auto_approved_violation")

-- Count mismatches fail closed instead of returning partial indexes.
local bad_commands, bad_commands_status = load_fixture({
    artifact = make_artifact(function(a) a.counts.bcm_commands = 3 end),
    use_cache = false,
})
assert(bad_commands == nil)
expect_load_failure(bad_commands_status, "count_mismatch")
local bad_triggers, bad_triggers_status = load_fixture({
    artifact = make_artifact(function(a) a.counts.bcm_triggers = 2 end),
    use_cache = false,
})
assert(bad_triggers == nil)
expect_load_failure(bad_triggers_status, "count_mismatch")
local bad_definitions, bad_definitions_status = load_fixture({
    artifact = make_artifact(function(a) a.counts.bcm_command_definitions = 1 end),
    use_cache = false,
})
assert(bad_definitions == nil)
expect_load_failure(bad_definitions_status, "count_mismatch")
local bad_inputs, bad_inputs_status = load_fixture({
    artifact = make_artifact(function(a) a.counts.bcm_inputs = 99 end),
    use_cache = false,
})
assert(bad_inputs == nil)
expect_load_failure(bad_inputs_status, "count_mismatch")
local bad_counts, bad_counts_status = load_fixture({
    artifact = make_artifact(),
    mutate_artifact = function(a) a.counts.bcm_triggers = "3" end,
    use_cache = false,
})
assert(bad_counts == nil)
expect_load_failure(bad_counts_status, "invalid_counts")
local bad_actions, bad_actions_status = load_fixture({
    artifact = make_artifact(function(a) a.counts.actions = 2 end),
    use_cache = false,
})
assert(bad_actions == nil)
expect_load_failure(bad_actions_status, "count_mismatch")

-- Duplicate UIDs and unknown definition references fail.
local dup_trigger, dup_trigger_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[2].raw_trigger_uid = "trg_1"
    end),
    use_cache = false,
})
assert(dup_trigger == nil)
expect_load_failure(dup_trigger_status, "invalid_artifact")
local dup_command, dup_command_status = load_fixture({
    artifact = make_artifact(function(a)
        local duplicate = deep_copy(a.command_catalog.triggers[2].profiles[1])
        duplicate.raw_command_uid = "cmd_multi"
        a.command_catalog.triggers[2].profiles[2] = duplicate
        a.counts.bcm_commands = 6
    end),
    use_cache = false,
})
assert(dup_command == nil)
expect_load_failure(dup_command_status, "invalid_artifact")
local missing_def, missing_def_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[3].profiles[1].command_definition_uids = { "def_missing" }
        a.command_catalog.triggers[3].profiles[1].variant_indexes = { 0 }
        a.command_catalog.triggers[3].profiles[1].direct_command_tokens = { "1+P" }
    end),
    use_cache = false,
})
assert(missing_def == nil)
expect_load_failure(missing_def_status, "invalid_artifact")

-- Variant selection must agree with the referenced definition fact.
local variant_mismatch, variant_mismatch_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[3].profiles[1].variant_indexes = { 1 }
    end),
    use_cache = false,
})
assert(variant_mismatch == nil)
expect_load_failure(variant_mismatch_status, "profile_variant_mismatch")

-- The old singular profile fields are forbidden; parallel arrays are the only
-- command-variant representation.
local singular_token, singular_token_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[1].profiles[1].command_token = "2+P"
    end),
    use_cache = false,
})
assert(singular_token == nil)
expect_load_failure(singular_token_status, "invalid_artifact")
assert(singular_token_status.message:find("forbidden key") ~= nil)
local singular_uid, singular_uid_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[1].profiles[1].command_definition_uid = "def_1"
    end),
    use_cache = false,
})
assert(singular_uid == nil)
expect_load_failure(singular_uid_status, "invalid_artifact")
local singular_variant, singular_variant_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[1].profiles[1].variant_index = 0
    end),
    use_cache = false,
})
assert(singular_variant == nil)
expect_load_failure(singular_variant_status, "invalid_artifact")

-- The reference arrays (uids/variants) must stay equal length.
local ragged, ragged_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[1].profiles[1].command_definition_uids = { "def_1", "def_2" }
    end),
    use_cache = false,
})
assert(ragged == nil)
expect_load_failure(ragged_status, "invalid_artifact")
assert(ragged_status.message:find("equal length") ~= nil)

-- direct_command_tokens is an independent list: a button-only row can carry a
-- token with zero definition references, and extra tokens may exceed refs.
local button_only, button_only_status = load_fixture({
    use_cache = false,
})
assert(button_only ~= nil and button_only_status.ok == true)
local button_binding = button_only:get_bindings(602)[1]
assert(#button_binding.command_definition_uids == 0)
assert(#button_binding.variant_indexes == 0)
assert(#button_binding.direct_command_tokens == 1)
assert(button_binding.direct_command_tokens[1] == "MP")
assert(button_binding.command_no == -1 and button_binding.command_index == -1)
local empty_tokens, empty_tokens_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[4].profiles[1].direct_command_tokens = {}
    end),
    use_cache = false,
})
assert(empty_tokens ~= nil and empty_tokens_status.ok == true)
assert(#empty_tokens:get_bindings(602)[1].direct_command_tokens == 0)
local extra_tokens, extra_tokens_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[1].profiles[1].direct_command_tokens = { "2+P", "extra" }
    end),
    use_cache = false,
})
assert(extra_tokens ~= nil and extra_tokens_status.ok == true)
assert(#extra_tokens:get_bindings(600)[1].direct_command_tokens == 2)

-- Invalid profile names, empty triggers and malformed counts all fail closed.
local bad_profile, bad_profile_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[3].profiles[1].profile_name = "pro"
    end),
    use_cache = false,
})
assert(bad_profile == nil)
expect_load_failure(bad_profile_status, "invalid_artifact")
local empty_trigger, empty_trigger_status = load_fixture({
    artifact = make_artifact(function(a)
        a.command_catalog.triggers[3].profiles = {}
    end),
    use_cache = false,
})
assert(empty_trigger == nil)
expect_load_failure(empty_trigger_status, "invalid_artifact")
local missing_catalog, missing_catalog_status = load_fixture({
    artifact = make_artifact(function(a) a.action_catalog = nil end),
    use_cache = false,
})
assert(missing_catalog == nil)
expect_load_failure(missing_catalog_status, "invalid_artifact")

-- Strict action schema rejects forbidden semantic keys and invalid fields.
local semantic_action, semantic_action_status = load_fixture({
    artifact = make_artifact(function(a)
        a.action_catalog.actions[1].move_uid = "m1"
    end),
    use_cache = false,
})
assert(semantic_action == nil)
expect_load_failure(semantic_action_status, "invalid_artifact")
assert(semantic_action_status.message:find("forbidden key") ~= nil)
local missing_action_uid, missing_action_uid_status = load_fixture({
    artifact = make_artifact(function(a)
        a.action_catalog.actions[1].raw_action_uid = nil
    end),
    use_cache = false,
})
assert(missing_action_uid == nil)
expect_load_failure(missing_action_uid_status, "invalid_artifact")
local bad_scope, bad_scope_status = load_fixture({
    artifact = make_artifact(function(a)
        a.action_catalog.actions[1].source_scope = "universal"
    end),
    use_cache = false,
})
assert(bad_scope == nil)
expect_load_failure(bad_scope_status, "invalid_artifact")
local dup_action, dup_action_status = load_fixture({
    artifact = make_artifact(function(a)
        local second = deep_copy(a.action_catalog.actions[1])
        second.action_id = 601
        a.action_catalog.actions[2] = second
        a.counts.actions = 2
    end),
    use_cache = false,
})
assert(dup_action == nil)
expect_load_failure(dup_action_status, "invalid_artifact")

-- Strict AC edge schema: forbidden keys, dangling references and malformed
-- params all fail closed.
local function artifact_with_edge(overrides)
    return make_artifact(function(a)
        a.action_catalog.edges = {
            {
                raw_edge_uid = "edge_1",
                source_raw_action_uid = "act_1",
                target_action_id = 601,
                branch_type = 0,
                attr = 0,
                action_frame = 1,
                trigger_id = 0,
                params = { 1, nil },
                ordinal = 0,
                raw_evidence = {},
            },
        }
        a.counts.ac_edges = 1
        if overrides then overrides(a) end
    end)
end
local edge_ok, edge_ok_status = load_fixture({
    artifact = artifact_with_edge(),
    use_cache = false,
})
assert(edge_ok ~= nil and edge_ok_status.ok == true)
assert(edge_ok:get_audit_info().reconciliation.indexed_ac_edges == 1)
local semantic_edge, semantic_edge_status = load_fixture({
    artifact = artifact_with_edge(function(a)
        a.action_catalog.edges[1].presentation = "combo"
    end),
    use_cache = false,
})
assert(semantic_edge == nil)
expect_load_failure(semantic_edge_status, "invalid_artifact")
assert(semantic_edge_status.message:find("forbidden key") ~= nil)
local dangling_source, dangling_source_status = load_fixture({
    artifact = artifact_with_edge(function(a)
        a.action_catalog.edges[1].source_raw_action_uid = "act_missing"
    end),
    use_cache = false,
})
assert(dangling_source == nil)
expect_load_failure(dangling_source_status, "invalid_artifact")
local projected_target, projected_target_status = load_fixture({
    artifact = artifact_with_edge(function(a)
        a.action_catalog.edges[1].target_raw_action_uid = "act_missing"
    end),
    use_cache = false,
})
assert(projected_target == nil)
expect_load_failure(projected_target_status, "invalid_artifact")
local bad_params, bad_params_status = load_fixture({
    artifact = artifact_with_edge(function(a)
        a.action_catalog.edges[1].params = "1"
    end),
    use_cache = false,
})
assert(bad_params == nil)
expect_load_failure(bad_params_status, "invalid_artifact")
local dup_edge, dup_edge_status = load_fixture({
    artifact = artifact_with_edge(function(a)
        a.action_catalog.edges[2] = deep_copy(a.action_catalog.edges[1])
        a.action_catalog.edges[2].ordinal = 1
        a.counts.ac_edges = 2
    end),
    use_cache = false,
})
assert(dup_edge == nil)
expect_load_failure(dup_edge_status, "invalid_artifact")

-- Read/decode failures are explicit.
RawCatalog.reset_cache()
local unreadable, unreadable_status = RawCatalog.load({
    dir = "raw/current",
    fighter_id = 20,
    read_file = function() return nil end,
    decode = function() return make_artifact() end,
    sha256 = Telemetry.sha256,
})
assert(unreadable == nil)
expect_load_failure(unreadable_status, "read_failed")
local manifest_unreadable, manifest_unreadable_status = load_fixture({
    manifest_unreadable = true,
    use_cache = false,
})
assert(manifest_unreadable == nil)
expect_load_failure(manifest_unreadable_status, "read_failed")
local artifact_unreadable, artifact_unreadable_status = load_fixture({
    artifact_unreadable = true,
    use_cache = false,
})
assert(artifact_unreadable == nil)
expect_load_failure(artifact_unreadable_status, "read_failed")
local malformed_manifest, malformed_manifest_status = load_fixture({
    manifest_malformed = true,
    use_cache = false,
})
assert(malformed_manifest == nil)
expect_load_failure(malformed_manifest_status, "malformed_json")
local malformed_artifact, malformed_artifact_status = load_fixture({
    artifact_malformed = true,
    use_cache = false,
})
assert(malformed_artifact == nil)
expect_load_failure(malformed_artifact_status, "malformed_json")

-- Actual bytes must match the sealed manifest size and SHA-256.
local size_mismatch, size_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.characters[1].bytes = m.characters[1].bytes + 1
    end,
    use_cache = false,
})
assert(size_mismatch == nil)
expect_load_failure(size_mismatch_status, "artifact_size_mismatch")
local hash_mismatch, hash_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.characters[1].sha256 = ("0"):rep(64)
    end,
    use_cache = false,
})
assert(hash_mismatch == nil)
expect_load_failure(hash_mismatch_status, "artifact_hash_mismatch")

-- Manifest identity failures fail closed before the catalog is usable.
local no_entry, no_entry_status = load_fixture({
    mutate_manifest = function(m)
        m.characters[1].fighter_id = 999
    end,
    use_cache = false,
})
assert(no_entry == nil)
expect_load_failure(no_entry_status, "manifest_character_missing")
local bad_manifest_schema, bad_manifest_schema_status = load_fixture({
    mutate_manifest = function(m) m.schema = "wrong" end,
    use_cache = false,
})
assert(bad_manifest_schema == nil)
expect_load_failure(bad_manifest_schema_status, "unsupported_manifest_schema")
local manifest_count_mismatch, manifest_count_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.characters[1].counts.bcm_commands = 99
        m.totals.bcm_commands = 99
    end,
    use_cache = false,
})
assert(manifest_count_mismatch == nil)
expect_load_failure(manifest_count_mismatch_status, "manifest_count_mismatch")
local manifest_file_mismatch, manifest_file_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.characters[1].file = "f999-raw-current.v1.json"
    end,
    use_cache = false,
})
assert(manifest_file_mismatch == nil)
expect_load_failure(manifest_file_mismatch_status, "manifest_file_mismatch")
local root_mismatch, root_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.root_digest = ("0"):rep(64)
    end,
    recompute_root = false,
    use_cache = false,
})
assert(root_mismatch == nil)
expect_load_failure(root_mismatch_status, "manifest_root_digest_mismatch")
for _, mutate in ipairs({
    function(m) m.build.display_version = "tampered" end,
    function(m) m.generator.name = "tampered" end,
    function(m) m.source.manifest.sha256 = ("f"):rep(64) end,
    function(m) m.characters[1].source.ac.sha256 = ("e"):rep(64) end,
}) do
    local bound, bound_status = load_fixture({
        mutate_manifest = mutate,
        recompute_root = false,
        use_cache = false,
    })
    assert(bound == nil)
    expect_load_failure(bound_status, "manifest_root_digest_mismatch")
end
local source_capture_mismatch, source_capture_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.characters[1].source.ac.capture = { changed = true }
    end,
    use_cache = false,
})
assert(source_capture_mismatch == nil)
expect_load_failure(source_capture_mismatch_status, "manifest_source_mismatch")
local totals_mismatch, totals_mismatch_status = load_fixture({
    mutate_manifest = function(m) m.totals.actions = 999 end,
    use_cache = false,
})
assert(totals_mismatch == nil)
expect_load_failure(totals_mismatch_status, "manifest_totals_mismatch")
local coverage_mismatch, coverage_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.character_coverage.expected = 2
        m.character_coverage.generated = 2
    end,
    use_cache = false,
})
assert(coverage_mismatch == nil)
expect_load_failure(coverage_mismatch_status, "coverage_mismatch")
local coverage_failed, coverage_failed_status = load_fixture({
    mutate_manifest = function(m)
        m.character_coverage.failed = { "Ryu" }
    end,
    use_cache = false,
})
assert(coverage_failed == nil)
expect_load_failure(coverage_failed_status, "coverage_mismatch")
local generated_at_mismatch, generated_at_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.generated_at = "2026-08-04T00:00:00Z"
    end,
    use_cache = false,
})
assert(generated_at_mismatch == nil)
expect_load_failure(generated_at_mismatch_status, "manifest_generated_at_mismatch")
local manifest_build_mismatch, manifest_build_mismatch_status = load_fixture({
    mutate_manifest = function(m)
        m.build.build_uid = "sf6b_111111111111111111111111"
    end,
    use_cache = false,
})
assert(manifest_build_mismatch == nil)
expect_load_failure(manifest_build_mismatch_status, "manifest_build_mismatch")
local duplicate_manifest_entry, duplicate_manifest_entry_status = load_fixture({
    mutate_manifest = function(m)
        m.characters[2] = deep_copy(m.characters[1])
    end,
    use_cache = false,
})
assert(duplicate_manifest_entry == nil)
expect_load_failure(duplicate_manifest_entry_status, "invalid_manifest")
local forbidden_manifest_key, forbidden_manifest_key_status = load_fixture({
    mutate_manifest = function(m) m.move_resolver_uid = "x" end,
    use_cache = false,
})
assert(forbidden_manifest_key == nil)
expect_load_failure(forbidden_manifest_key_status, "invalid_manifest")
assert(forbidden_manifest_key_status.message:find("forbidden key") ~= nil)

-- manifest_required=false is an explicit diagnostics escape hatch and reports
-- itself as unverified rather than pretending bytes were checked.
local unverified, unverified_status = load_fixture({
    manifest_required = false,
    use_cache = false,
})
assert(unverified ~= nil and unverified_status.ok == true)
local unverified_audit = unverified:get_audit_info()
assert(unverified_audit.integrity.verified == false)
assert(unverified_audit.integrity.reason == "manifest_not_required")
assert(unverified_audit.integrity.manifest_root_digest_verified == false)

-- Default REFramework load path uses fs.read + json.load_string and verifies
-- real bytes through Telemetry.sha256.
local saved_json, saved_fs = json, fs
local default_artifact = make_artifact()
local default_raw = "f020 raw bytes"
local default_manifest = make_manifest(default_artifact)
default_manifest.characters[1].bytes = #default_raw
default_manifest.characters[1].sha256 = Telemetry.sha256(default_raw)
default_manifest.root_digest = derive_root_digest(default_manifest)
local load_string_calls = 0
RawCatalog.reset_cache()
json = {
    load_string = function(raw)
        load_string_calls = load_string_calls + 1
        if raw == "manifest bytes" then return default_manifest end
        assert(raw == default_raw)
        return default_artifact
    end,
}
fs = {
    read = function(path)
        if path == "raw/current/raw-current-manifest.v1.json" then
            return "manifest bytes"
        end
        assert(path == "raw/current/f020-raw-current.v1.json")
        return default_raw
    end,
}
local default_loaded, default_status = RawCatalog.load({
    dir = "raw/current",
    fighter_id = 20,
    use_cache = false,
})
assert(default_loaded ~= nil and default_status.ok == true)
assert(load_string_calls == 2)
assert(default_loaded:get_bindings(600)[1].direct_command_tokens[1] == "2+P")
assert(default_loaded:get_audit_info().integrity.verified == true)
json, fs = saved_json, saved_fs

-- from_artifact validates the same contract and can inject a file label;
-- decoded-artifact diagnostics never claim byte-level integrity.
local direct_artifact = make_artifact()
local direct, direct_status = RawCatalog.from_artifact(direct_artifact, {
    fighter_id = 20,
    file = "f020-raw-current.v1.json",
    manifest = make_manifest(direct_artifact),
})
assert(direct ~= nil and direct_status.ok == true)
assert(#direct:get_bindings(600) == 3)
assert(direct:get_bindings(600)[3].direct_command_tokens[2] == "2+PP")
local direct_audit = direct:get_audit_info()
assert(direct_audit.integrity.verified == false)
assert(direct_audit.integrity.reason == "decoded_artifact_only")
assert(direct_audit.manifest.root_digest ~= nil)
local direct_bad, direct_bad_status = RawCatalog.from_artifact(make_artifact(function(a)
    a.character.fighter_id = 6
end), { fighter_id = 20 })
assert(direct_bad == nil)
expect_load_failure(direct_bad_status, "character_mismatch")

-- Bad options fail before any read.
local bad_options, bad_options_status = RawCatalog.load({
    dir = "",
    fighter_id = 20,
})
assert(bad_options == nil)
expect_load_failure(bad_options_status, "invalid_options")
local bad_fighter, bad_fighter_status = RawCatalog.load({
    dir = "raw/current",
    fighter_id = 0,
})
assert(bad_fighter == nil)
expect_load_failure(bad_fighter_status, "invalid_options")
local bad_file, bad_file_status = RawCatalog.load({
    dir = "raw/current",
    fighter_id = 20,
    file = "a/../b.json",
})
assert(bad_file == nil)
expect_load_failure(bad_file_status, "invalid_options")

print("raw catalog tests passed")
