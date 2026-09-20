-- Review priority and player confirmations are separate from automatic causes.
local M={}
local function copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
local function integer(n) return type(n)=="number" and n==n and n>=0 and n<math.huge and n%1==0 end
local function automatic(item)
    if item.custom_rule and (item.custom_rule.priority=="P1" or item.custom_rule.priority=="P2" or item.custom_rule.priority=="P3") then return item.custom_rule.priority end
    if item.classification.level~="observed" then return "P3" end
    local flags=item.facts and item.facts.flags or {}
    return (flags.punish or flags.counter) and "P1" or "P2"
end
function M.build(items,capture,review,document,schema,indexed_rows)
    local base={}
    for _,item in ipairs(items) do
        local row=copy(item); row.priority=automatic(item); row.automatic_priority=row.priority
        base[#base+1]=row
    end
    if document==nil then return base end
    local ok,result=pcall(function()
        local meta=capture.metadata
        assert(document.replay_id==meta.replay_id and document.build==meta.version,"identity")
        for side=1,2 do
            local a,b=document.players[side],meta.players[side]
            assert(a.fighter_id==b.fighter_id and a.control_mode==b.control_mode,"players")
        end
        local ix,rows=schema.index,indexed_rows or {}
        for _,row in ipairs(indexed_rows and {} or capture.samples) do
            local round,frame=row[ix.round],row[ix.replay_frame]
            if round==row[ix.battle_round] then rows[round]=rows[round] or {}; rows[round][frame]=row end
        end
        local out,used={},{}
        for _,item in ipairs(base) do out[#out+1]=copy(item) end
        local function validate(note)
            assert(note.source=="user_verified" and (note.priority=="P0" or note.priority=="P1" or note.priority=="P2"),"confirmation")
            assert(integer(note.round) and note.round>=1 and integer(note.frame) and integer(note.review_from),"clock")
            assert(note.receiver==1 or note.receiver==2,"player")
            assert(type(note.title)=="string" and #note.title>0 and #note.title<=180,"title")
            local round=note.round-1
            local info=review.by_round[round]
            assert(info and note.review_from>=info.first_frame and note.review_from<=note.frame and note.frame<=info.last_frame,"bounds")
            assert(rows[round] and rows[round][note.frame] and rows[round][note.review_from],"anchors")
            local key=round..":"..note.frame..":"..note.receiver
            assert(not used[key],"duplicate"); used[key]=true
            return round
        end
        local function apply(item,note)
            item.human_review=note; item.priority=note.priority
            item.automatic_classification=item.classification
            item.classification={title=note.title,rule="player_confirmed",level="user_verified"}
            item.review_frame=note.review_from
        end
        assert(#(document.items or {})+#(document.opportunities or {})<=200,"too_many")
        for _,note in ipairs(document.items or {}) do
            local round=validate(note)
            local matched
            for _,item in ipairs(out) do
                if item.round==round and item.frame==note.frame and item.receiver==note.receiver then matched=item; break end
            end
            assert(matched,"damage_anchor")
            local a,b=rows[round][note.frame-1],rows[round][note.frame]
            local hp=ix["p"..note.receiver..".vital_new"]
            assert(a and b[ix.stage_frame]==a[ix.stage_frame]+1 and integer(note.first_damage) and note.first_damage>0
                and a[hp]-b[hp]==note.first_damage,"first_damage")
            apply(matched,note)
        end
        for _,note in ipairs(document.opportunities or {}) do
            local round=validate(note)
            assert(type(note.checks)=="table" and #note.checks>0 and #note.checks<=20,"checks")
            for _,check in ipairs(note.checks) do
                assert(integer(check.frame) and rows[round][check.frame] and ix[check.field]
                    and rows[round][check.frame][ix[check.field]]==check.value,"evidence")
            end
            local item={id=#out+1,round=round,frame=note.frame,receiver=note.receiver,damage=0,damage_observations=0,
                replay_id=meta.replay_id,build=meta.version,kind="confirmed_opportunity"}
            if note.native_value~=nil then
                assert(type(note.native_value)=="number" and ix.display_stun_frame
                    and rows[round][note.review_from][ix.display_stun_frame]==note.native_value,"native_value")
                item.native_advantage={value=note.native_value,frame=note.review_from,sign_basis_verified=false}
            end
            apply(item,note); out[#out+1]=item
        end
        return out
    end)
    if not ok then return base,"confirmation_mismatch" end
    return result
end
return M
