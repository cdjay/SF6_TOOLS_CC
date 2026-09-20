-- Offline evidence transport. No native objects, game control or file access.
local M={version="sf6cc.replay-workbench.v1",path="cfn-workbench.json"}
function M.build(analysis,schema,context_module,rules)
    assert(analysis.status=="ready" and analysis.capture and not analysis.damage_error and not analysis.guard_error,
        "analysis_not_ready")
    local capture=analysis.capture
    local context=analysis.fact_cache and analysis.fact_cache.context or context_module.new(capture,schema,rules)
    local events={}
    for _,kind in ipairs({"damage","guard"}) do
        for _,item in ipairs(kind=="damage" and analysis.damage_items or analysis.guard_items or {}) do
            local original=item.base_classification or item.classification
            events[#events+1]={id=kind.."_"..tostring(item.id),kind=kind,round=item.round,frame=item.frame,
                last_frame=item.last_frame,side=item.receiver,damage=item.damage,review_frame=item.review_frame,
                title=item.custom_title or item.classification and item.classification.title or "防御记录",
                base_title=original and original.title or "防御记录",context=context(item,kind),
                custom_rule=item.custom_rule,candidate=item.candidate,complete=item.complete}
        end
    end
    table.sort(events,function(a,b)
        if a.round~=b.round then return a.round<b.round end
        if a.frame~=b.frame then return a.frame<b.frame end
        return a.id<b.id
    end)
    local metadata={replay_id=capture.metadata.replay_id,version=capture.metadata.version,players={}}
    for side=1,2 do
        local p=(capture.metadata.players or {})[side] or {}
        metadata.players[side]={fighter_id=p.fighter_id,playing_fighter_id=p.playing_fighter_id,control_mode=p.control_mode}
    end
    return {schema=M.version,capture={schema=schema.version,columns=schema.columns,samples=capture.samples,
        metadata=metadata,stop_reason=capture.stop_reason,sample_count=#capture.samples},events=events,
        config=analysis.rule_engine and analysis.rule_engine.document,rule_name=analysis.rule_name,
        rule_error=analysis.rule_error,generation=analysis.rule_generation or 0}
end
return M
