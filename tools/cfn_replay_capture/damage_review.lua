-- Incremental saved-data analysis. No game objects, input, files or Action mappings.
local M = {}
local function integer(n) return type(n) == "number" and n == n and math.abs(n) < math.huge and n%1 == 0 end
function M.new(schema, metadata, rules)
    if not metadata or metadata.version ~= 20004000 then return nil, "unsupported_analysis" end
    local ix = schema.index
    local d = {items={}, rounds={}, by_round={}, observations=0, rules_version=1}
    local previous, history, active, highest = nil, {}, {}, nil
    local seen={}
    local function get(r, n) local v = r and r[ix[n]]; if integer(v) then return v end end
    local function p(r, s, n) return get(r, "p"..s.."."..n) end
    local function contiguous(a, b)
        return a and b and get(a,"round")==get(b,"round") and get(a,"battle_round")==get(b,"battle_round")
            and get(b,"replay_frame")==get(a,"replay_frame")+1 and get(b,"stage_frame")==get(a,"stage_frame")+1
    end
    local function sameflow(a,b) return contiguous(a,b) and get(a,"fight_st")==get(b,"fight_st") end
    local function fresh(a,b,s)
        if metadata.frame_meter_profile ~= "native_cursor_cell_v1" or not contiguous(a,b)
            or get(a,"display_prev_frame") ~= get(a,"stage_frame") or get(b,"display_prev_frame") ~= get(b,"stage_frame")
            or not get(b,"meter_start_frame") or get(a,"meter_start_frame") ~= get(b,"meter_start_frame") then return nil end
        for _, r in ipairs({a,b}) do
            local cursor=p(r,s,"display_meter_index")
            if p(r,s,"display_meter_size") ~= 80 or not cursor or cursor<0 or cursor>=80 then return nil end
        end
        for _, flag in ipairs({"empty","changed","end","not_add","not_whole"}) do
            local v=p(b,s,"display_meter_"..flag)
            if v~=0 and v~=1 then return nil end
        end
        local kind=p(b,s,"display_meter_type")
        if not kind or kind<0 or kind>14 or p(b,s,"display_meter_empty")~=0 or p(b,s,"display_meter_not_add")~=0
            or p(b,s,"display_meter_not_whole")~=0 or p(b,s,"display_meter_index")~=(p(a,s,"display_meter_index")+1)%80 then return nil end
        return kind
    end
    local function counter(r,s)
        if not r or not s then return nil end
        local n,damage=p(r,s,"mComboCount"),p(r,s,"mComboDamage")
        if n and n>=0 and n==p(r,s,"combo_cnt") and damage and damage>=0 then return {n=n,damage=damage} end
    end
    local function held(r,s,source)
        return p(r,s,"act_st")==38 and p(r,source,"act_st")==37 and p(r,s,"damage_source")==source
    end
    local function facts(row,s,source,flags,now)
        local other=3-s
        local last=history[#history]
        local f={frame=get(row,"replay_frame"),receiver=s,source_observed=source,flags=flags,
            previous_state=p(last,s,"act_st"),current_state=p(row,s,"act_st"),other_state=p(row,other,"act_st"),
            previous_y=p(last,s,"y_raw"),other_y=p(row,other,"y_raw"),counter_at_damage=now and now.n,
            previous_direction=rules.direction(p(last,s,"pl_input_new"),p(last,s,"facing_right")),
            current_direction=rules.direction(p(row,s,"pl_input_new"),p(row,s,"facing_right")),
            context_start=get(history[1] or row,"replay_frame")}
        if not last then return f end
        local face,old=p(row,s,"facing_right"),p(last,s,"facing_right")
        f.facing_changed=(face==0 or face==1) and (old==0 or old==1) and face~=old
        f.last_meter_type=fresh(history[#history-1],last,s)
        for j=math.max(2,#history-29),#history do
            local r,b=history[j],history[j-1]
            if rules.guard(p(b,s,"act_st")) and (p(b,s,"guard_time") or 0)>0 and not rules.guard(p(r,s,"act_st")) then
                f.guard_end=get(r,"replay_frame")
            end
            if p(r,s,"act_st")==35 then f.wakeup_last_frame=get(r,"replay_frame") end
        end
        if rules.reaction(f.previous_state) then
            local start=#history
            while start>1 and rules.reaction(p(history[start-1],s,"act_st")) do start=start-1 end
            if start>1 then
                f.reaction_start=get(history[start],"replay_frame")
                f.reaction_preceded_by_guard=rules.guard(p(history[start-1],s,"act_st"))
                if f.reaction_preceded_by_guard then
                    for j=start-1,math.max(2,start-60),-1 do
                        if rules.guard(p(history[j],s,"act_st")) and p(history[j],s,"vital_new")<p(history[j-1],s,"vital_new") then
                            f.preceding_guard_damage_frame=get(history[j],"replay_frame"); break
                        end
                    end
                end
            end
        end
        if rules.attack(f.previous_state) then
            local start=#history
            while start>1 do
                local a,b=history[start-1],history[start]
                local changed=not rules.attack(p(a,s,"act_st"))
                for _,n in ipairs({"action_id","engine_style_index","engine_loop_count"}) do
                    if p(a,s,n)~=p(b,s,n) then changed=true end
                end
                if changed or (p(b,s,"action_frame_raw") or 0)<(p(a,s,"action_frame_raw") or 0) then break end
                start=start-1
            end
            f.attack_start=get(history[start],"replay_frame")
            f.attack_start_observed=start>1 and p(history[start],s,"action_frame_raw")==0
            for j=start,#history do
                local r,b=history[j],history[j-1]
                if fresh(b,r,s)==13 then f.active_seen=true end
                if b and (p(r,other,"vital_new")<p(b,other,"vital_new") or (p(r,other,"guard_time") or 0)>0
                    or ((p(r,other,"hit_st") or 0) & ~(p(b,other,"hit_st") or 0) & 0x8184)~=0
                    or p(r,other,"act_st")==39) then f.contact_seen=true end
            end
        end
        return f
    end
    local function native_context(row)
        local frame=get(row,"replay_frame")
        local best
        for side=1,2 do
            for j=#history,1,-1 do
                local r=history[j]
                if frame-get(r,"replay_frame")>30 then break end
                if rules.guard(p(r,side,"act_st")) and (p(r,side,"guard_time") or 0)>0 then
                    local after=history[j+1] or row
                    if rules.guard(p(after,side,"act_st")) and (p(after,side,"guard_time") or 0)>0 then return nil end
                    if not best or j>best.last then best={last=j,side=side} end
                    break
                end
            end
        end
        if not best then return nil end
        local start=best.last
        while start>1 and rules.guard(p(history[start-1],best.side,"act_st"))
            and (p(history[start-1],best.side,"guard_time") or 0)>0 do start=start-1 end
        if start==1 then return nil end
        local value,changed
        for j=start,best.last do
            local r,b=history[j],history[j-1]
            local n,old=get(r,"display_stun_frame"),get(b,"display_stun_frame")
            if not contiguous(b,r) or get(r,"display_prev_frame")~=get(r,"stage_frame")
                or get(b,"display_prev_frame")~=get(b,"stage_frame") or not n or not old then return nil end
            value=n
            if n~=old then changed=get(r,"replay_frame") end
        end
        if not changed then return nil end
        return {value=value,frame=changed,guard_side=best.side,guard_start=get(history[start],"replay_frame"),
            guard_end=get(history[best.last+1] or row,"replay_frame"),sign_basis_verified=false}
    end
    function d:add(row)
        if self.error then return end
        local round,frame,stage=get(row,"round"),get(row,"replay_frame"),get(row,"stage_frame")
        if not round or round<0 or not frame or frame<0 or not stage or stage<0 then self.error="invalid_clock"; return end
        if highest and round<highest then self.error="rewound_capture"; return end
        highest=round
        if get(row,"battle_round")~=round then previous=nil; history={}; active={}; return end
        local key=round..":"..frame..":"..stage
        if seen[key] and (not previous or get(previous,"round")~=round
            or get(previous,"replay_frame")~=frame or get(previous,"stage_frame")~=stage) then
            self.error="rewound_capture"; return
        end
        seen[key]=true
        for s=1,2 do
            for _,n in ipairs({"vital_new","hit_st","damage_source","act_st","action_frame_raw","action_id","y_raw"}) do
                if not p(row,s,n) then self.error="missing_damage_data"; return end
            end
        end
        local info=self.by_round[round]
        if not info then
            info={round=round,first_frame=frame,last_frame=frame,damage={0,0}}
            self.by_round[round]=info; self.rounds[#self.rounds+1]=info
        end
        if previous and get(previous,"round")==round then
            if frame==get(previous,"replay_frame") and stage==get(previous,"stage_frame") then
                for i,n in ipairs(schema.columns) do
                    if n:match("^p[12]%.") and not n:find(".display_",1,true) and row[i]~=previous[i] then
                        self.error="conflicting_samples"; return
                    end
                end
                if get(previous,"fight_st")~=get(row,"fight_st") then history={row}; active={} end
                return
            end
            if frame<get(previous,"replay_frame") or stage<get(previous,"stage_frame") then self.error="rewound_capture"; return end
        end
        local continuous=contiguous(previous,row)
        if not sameflow(previous,row) then history={}; active={} end
        info.last_frame=frame
        local matched={}
        if continuous then
            for s=1,2 do
                local hp,before_hp=p(row,s,"vital_new"),p(previous,s,"vital_new")
                local loss=math.max(0,before_hp-hp)
                if loss>0 then
                    self.observations=self.observations+1; info.damage[s]=info.damage[s]+loss
                    local source=p(row,s,"damage_source")
                    local valid=(source==1 or source==2) and source~=s
                    local before=valid and sameflow(previous,row) and counter(previous,source) or nil
                    local now=valid and counter(row,source) or nil
                    local held_pair=valid and held(previous,s,source) and held(row,s,source)
                    local function matches(n)
                        return n==loss or hp==0 and loss==before_hp and n>loss
                            or hp==1 and held_pair and n>loss
                    end
                    local carried=before and now and matches(now.damage-before.damage)
                    local first=before and now and before.n==0 and now.n==1 and (matches(now.damage) or carried)
                    local next_hit=before and now and now.n==before.n+1 and carried
                    local terminal=before and now and held_pair and before_hp==1 and hp==0
                        and now.n==before.n and now.damage==before.damage
                        and p(previous,s,"action_id")==p(row,s,"action_id")
                        and p(previous,source,"action_id")==p(row,source,"action_id")
                        and active[source] and now.damage>active[source].damage
                    local item=(next_hit or terminal) and active[source] or nil
                    if item and (item.receiver~=s or item.last_native_count~=before.n) then item=nil end
                    if not item then
                        local flags={}
                        for name,mask in pairs({guard=4,hit=0x8000,counter=0x80,punish=0x100}) do
                            flags[name]=p(row,s,"hit_st") & mask ~= 0 and p(previous,s,"hit_st") & mask == 0
                        end
                        local f=facts(row,s,source,flags,now)
                        local classification=rules.classify(f)
                        local basis=f.preceding_guard_damage_frame or f.reaction_start or f.attack_start or frame
                        local native=native_context(row)
                        local display=get(row,"display_stun_frame")
                        local snapshot=display and get(row,"display_prev_frame")==stage
                            and {value=display,frame=frame,associated=false} or nil
                        item={id=#self.items+1,round=round,frame=frame,receiver=s,damage=0,damage_observations=0,
                            replay_id=metadata.replay_id,build=metadata.version,classification=classification,facts=f,
                            priority=classification.level=="observed" and "P2" or "P3",
                            native_advantage=native,native_snapshot=snapshot,review_basis_frame=native and native.frame or basis,
                            review_frame=math.max(info.first_frame,native and native.frame or basis),
                            first_hit_candidate=not not first,last_native_count=now and now.n}
                        self.items[#self.items+1]=item
                        if valid then active[source]=first and item or nil end
                    end
                    if item.first_hit_candidate then matched[source]=true end
                    item.damage=item.damage+loss; item.damage_observations=item.damage_observations+1
                    item.last_frame=frame; item.last_native_count=now and now.n
                    item.native_combo_damage=now and now.damage
                end
            end
        end
        for source in pairs(active) do
            if not matched[source] then
                local a,b=counter(previous,source),counter(row,source)
                local item=active[source]; local victim=item.receiver
                local count_only=sameflow(previous,row) and a and b and b.n==a.n+1 and b.damage==a.damage
                    and item.last_native_count==a.n and p(previous,victim,"vital_new")==p(row,victim,"vital_new")
                    and p(row,victim,"vital_new")>0 and rules.reaction(p(previous,victim,"act_st"))
                    and rules.reaction(p(row,victim,"act_st")) and p(row,victim,"damage_source")==source
                if count_only then
                    item.last_native_count=b.n; item.count_only_contacts=(item.count_only_contacts or 0)+1
                elseif not continuous or not a or not b or b.n==0 or a.n~=b.n or a.damage~=b.damage then active[source]=nil end
            end
        end
        history[#history+1]=row
        if #history>600 then table.remove(history,1) end
        previous=row
    end
    function d:finish()
        if self.error then self.items={} end
        return self.items
    end
    return d
end
return M
