-- All observed guard intervals, including zero-damage interactions. No move IDs or verdicts.
local M={}
local function integer(n) return type(n)=="number" and n==n and math.abs(n)<math.huge and n%1==0 end
function M.new(schema,metadata,rules,settings)
    if not metadata or metadata.version~=20004000 then return nil,"unsupported_analysis" end
    local ix=schema.index
    local d={items={},by_round={},rounds={}}
    local previous,active,responses,highest=nil,{},{},nil
    local function get(r,n) local v=r and r[ix[n]]; if integer(v) then return v end end
    local function p(r,s,n) return get(r,"p"..s.."."..n) end
    local function guard(r,s) return rules.guard(p(r,s,"act_st")) and (p(r,s,"guard_time") or 0)>0 end
    local function continuous(a,b)
        return a and get(a,"round")==get(b,"round") and get(a,"battle_round")==get(b,"battle_round")
            and get(a,"fight_st")==get(b,"fight_st") and get(b,"replay_frame")==get(a,"replay_frame")+1
            and get(b,"stage_frame")==get(a,"stage_frame")+1
    end
    local function synced(r) return r and get(r,"display_prev_frame")==get(r,"stage_frame") and get(r,"display_stun_frame")~=nil end
    local function close(side,row,reason)
        local item=active[side]; if not item then return end
        item.complete=item.start_observed and reason=="guard_end"
        item.end_reason=reason
        if reason=="guard_end" then item.guard_end=get(row,"replay_frame") end
        if item.complete and item.display_complete and item.last_change then
            item.native_advantage={value=item.last_value,frame=item.last_change,guard_side=side,
                guard_start=item.frame,guard_end=item.guard_end,sign_basis_verified=false}
            item.review_frame=item.last_change
        end
        item.candidate=item.native_advantage~=nil and math.abs(item.native_advantage.value)>=(settings and settings.advantage_min or 4)
        if reason=="guard_end" then responses[side]=item end
        active[side]=nil
    end
    function d:add(row)
        if self.finished or self.error then return end
        local round,frame,stage=get(row,"round"),get(row,"replay_frame"),get(row,"stage_frame")
        if not round or round<0 or not frame or frame<0 or not stage or stage<0 then self.error="invalid_clock"; return end
        if highest and round<highest then self.error="rewound_capture";return end
        highest=round
        if get(row,"battle_round")~=round then
            for s=1,2 do close(s,nil,"boundary") end
            for _,item in pairs(responses) do item.response.reason="boundary" end
            responses={};previous=nil;return
        end
        if previous and (round<get(previous,"round") or round==get(previous,"round") and
            (frame<get(previous,"replay_frame") or stage<get(previous,"stage_frame"))) then self.error="rewound_capture"; return end
        if previous and round==get(previous,"round") and frame==get(previous,"replay_frame") and stage==get(previous,"stage_frame") then
            for n,name in ipairs(schema.columns) do
                if name~="render_tick" and name~="thread_id" and name~="update_result" and name~="fight_st" and row[n]~=previous[n] then
                    self.error="conflicting_samples"; return
                end
            end
            if get(row,"fight_st")~=get(previous,"fight_st") then
                for s=1,2 do close(s,nil,"boundary") end
                for _,item in pairs(responses) do item.response.reason="boundary" end
                responses={};previous=row
            end
            return
        end
        local connected=continuous(previous,row)
        if not connected or get(row,"battle_round")~=round then
            for s=1,2 do close(s,nil,"boundary") end
            for _,item in pairs(responses) do item.response.reason="boundary" end
            responses={}
        end
        if get(row,"battle_round")~=round then previous=row; return end
        local info=self.by_round[round]
        if not info then info={round=round,first_frame=frame,last_frame=frame};self.by_round[round]=info;self.rounds[#self.rounds+1]=info end
        info.last_frame=frame
        for side=1,2 do
            if not p(row,side,"act_st") or not p(row,side,"guard_time") then self.error="missing_guard_data"; return end
            local guarding=guard(row,side)
            if active[side] and not guarding then close(side,row,"guard_end") end
            local response=responses[side]
            if response then
                local r=response.response; r.through=frame
                if frame-response.guard_end>=(settings and settings.response_frames or 30) then r.reason="limit";responses[side]=nil
                elseif guarding or rules.reaction(p(row,side,"act_st")) or p(row,side,"act_st")==35
                    or connected and p(row,side,"vital_new") and p(previous,side,"vital_new")
                        and p(row,side,"vital_new")<p(previous,side,"vital_new") then r.reason="new_reaction";responses[side]=nil
                elseif rules.attack(p(row,side,"act_st")) then
                    r.frame,r.delay,r.reason=frame,frame-response.guard_end,"attack_observed";responses[side]=nil
                end
            end
            if guarding then
                local item=active[side]
                if not item then
                    item={id=#self.items+1,replay_id=metadata.replay_id,build=metadata.version,round=round,
                        receiver=side,frame=frame,last_frame=frame,review_frame=frame,damage=0,
                        response_limit=settings and settings.response_frames or 30,advantage_min=settings and settings.advantage_min or 4,
                        start_observed=connected and not guard(previous,side) or false,
                        display_complete=connected and synced(previous) or false,response={reason="not_observed"}}
                    self.items[#self.items+1]=item; active[side]=item
                end
                item.last_frame=frame
                if not synced(row) or not connected or not synced(previous) then item.display_complete=false end
                if synced(row) then
                    local value=get(row,"display_stun_frame")
                    item.last_value=value;item.native_snapshot={value=value,frame=frame,associated=false}
                    if connected and synced(previous) and value~=get(previous,"display_stun_frame") then item.last_change=frame end
                end
                if connected and p(row,side,"vital_new") and p(previous,side,"vital_new") then
                    item.damage=item.damage+math.max(0,p(previous,side,"vital_new")-p(row,side,"vital_new"))
                end
            end
        end
        previous=row
    end
    function d:finish(windows)
        if self.finished then return self.items end
        for s=1,2 do close(s,nil,"capture_end") end
        for _,item in pairs(responses) do item.response.reason="capture_end" end
        self.finished=true
        if self.error then self.items={}; return self.items end
        for _,item in ipairs(self.items) do
            for _,window in ipairs(windows or {}) do
                if item.complete and window.round==item.round and window.defender==item.receiver and window.frame==item.guard_end then
                    item.window=window;item.candidate=true;break
                end
            end
        end
        return self.items
    end
    return d
end
return M
