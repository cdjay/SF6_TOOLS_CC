local MoveResolverShadow = {
    name = "ComboTrials.Semantic.MoveResolverShadow",
}

local function difference_category(legacy_matched, candidate_matched, candidate_status)
    if candidate_matched == nil then return "UNKNOWN" end
    if legacy_matched == candidate_matched then
        return candidate_matched and "IDENTITY_MATCH" or "DISTINCT_MATCH"
    end
    if legacy_matched then return "LEGACY_ONLY" end
    return "CANDIDATE_ONLY"
end

function MoveResolverShadow.compare_match(resolver, params)
    params = type(params) == "table" and params or {}
    local comparison = resolver:compare_actions(
        params.fighter_id,
        params.expected_action_id,
        params.observed_action_id
    )
    local candidate_matched = comparison.equivalent
    local legacy_matched = params.legacy_matched == true
    local category = difference_category(
        legacy_matched,
        candidate_matched,
        comparison.status
    )
    local mismatch = category == "LEGACY_ONLY" or category == "CANDIDATE_ONLY"
    local expected = mismatch and params.expected_difference == true

    return {
        schema = "sf6cc.move-resolver-shadow.v1",
        authority = "diagnostic_only",
        production_result = "legacy",
        character = params.character,
        fighter_id = params.fighter_id,
        runtime_action = params.observed_action_id,
        expected_action = params.expected_action_id,
        consumer = params.consumer or "unknown",
        legacy_classification = legacy_matched and "MATCH" or "NO_MATCH",
        candidate_classification = candidate_matched == nil and comparison.status
            or (candidate_matched and "MATCH" or "NO_MATCH"),
        difference_category = category,
        expected = expected,
        severity = category == "UNKNOWN" and "BLOCKED"
            or (mismatch and not expected and "P1" or "INFO"),
        source_evidence = params.source_evidence,
        compatibility_projection = params.compatibility_projection == true,
        runtime_mechanism = params.runtime_mechanism == true,
        move_identity = {
            shared = comparison.shared_move_identities,
            shared_current_move_uids = comparison.shared_current_move_uids,
            expected = comparison.left.identities,
            observed = comparison.right.identities,
        },
        comparison = comparison,
    }
end

return MoveResolverShadow
