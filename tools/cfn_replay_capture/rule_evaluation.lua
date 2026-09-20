-- A fixed fact snapshot can be judged by many profiles without replaying samples.
local M={version=1,observation_limit=120}
local function copy(v)
    if type(v)~="table" then return v end
    local out={};for k,x in pairs(v) do out[k]=copy(x) end;return out
end
function M.new(capture,damage,guards,schema,rules,contexts)
    local base_damage,base_guards=copy(damage),copy(guards)
    local context,rows=contexts.new(capture,schema,rules)
    return {rows=rows,context=context,evaluate=function(_,engine)
        local ds,gs=copy(base_damage),copy(base_guards)
        local settings=engine.document.settings
        for _,item in ipairs(ds) do
            item.classification=rules.classify(item.facts,settings)
            item.base_classification,item.custom_rule=nil,nil
        end
        for _,item in ipairs(gs) do
            item.response_limit,item.advantage_min=settings.response_frames,settings.advantage_min
            local r=item.response
            if r and item.guard_end and r.through and r.through-item.guard_end>=settings.response_frames then
                item.response={through=item.guard_end+settings.response_frames,reason="limit"}
            end
            item.candidate=item.window~=nil or item.native_advantage~=nil and math.abs(item.native_advantage.value)>=settings.advantage_min
            item.custom_rule,item.custom_title=nil,nil
        end
        contexts.apply(engine,context,ds,"damage");contexts.apply(engine,context,gs,"guard")
        return ds,gs
    end}
end
return M
