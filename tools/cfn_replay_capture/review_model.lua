local M = {}
function M.new()
    local m={selected=nil,current=nil,replay_id=nil,player=1,priority=0,sort_column=nil,descending=false}
    function m:update(analysis,clock)
        local position=clock and clock.position
        local id=clock and clock.replay_id
        if id~=self.replay_id then self.player=1; self.player_manual=false end
        if id~=self.replay_id or position and position.round~=self.current then self.selected=position and position.round end
        if not self.player_manual and clock and (clock.local_side==1 or clock.local_side==2) then self.player=clock.local_side end
        self.replay_id=id; self.current=position and position.round
        self.rounds={}
        local seen={}
        local function add(n)
            if type(n)=="number" and n>=0 and n%1==0 and not seen[n] then seen[n]=true; self.rounds[#self.rounds+1]=n end
        end
        add(self.current)
        local capture=analysis.capture
        self.matching=capture and capture.metadata and capture.metadata.replay_id==id or false
        if self.matching then
            local count=capture.metadata.round_count
            if type(count)=="number" and count>=1 and count<=99 then for n=0,count-1 do add(n) end end
            for _,info in ipairs(analysis.damage_review and analysis.damage_review.rounds or {}) do add(info.round) end
        end
        table.sort(self.rounds)
        if not seen[self.selected] then self.selected=self.current or self.rounds[1] end
        self.items={}
        if self.matching then
            for _,item in ipairs(analysis.review_items or analysis.damage_items or {}) do
                if item.round==self.selected and item.receiver==self.player
                    and (not analysis.rule_engine or analysis.rule_engine:includes(item))
                    and (self.priority==0 or item.priority=="P"..(self.priority-1)) then self.items[#self.items+1]=item end
            end
        end
        local function value(i)
            if self.sort_column==0 then return i.frame end
            if self.sort_column==1 then return i.priority end
            if self.sort_column==2 then return i.classification.title end
            if self.sort_column==3 then return i.damage end
            if self.sort_column==4 then return i.native_advantage and i.native_advantage.value end
            return i.frame
        end
        table.sort(self.items,function(a,b)
            local av,bv=value(a),value(b)
            if av==bv then return a.frame==b.frame and a.id<b.id or a.frame<b.frame end
            if av==nil then return false end
            if bv==nil then return true end
            if self.descending then return av>bv end
            return av<bv
        end)
    end
    function m:select(round) self.selected=round end
    function m:select_player(side) if side==1 or side==2 then self.player=side; self.player_manual=true end end
    function m:sort(column,descending) self.sort_column=column; self.descending=descending==true end
    function m:can_locate(analysis,controls,item)
        local s=controls.snapshot
        return self.matching and item.round==self.current and not analysis.active
            and analysis.status=="ready" and not analysis.damage_error and s and s.paused and not s.result_open
            and not s.modal and not s.takeover and not s.changing_round and not controls.owner and not controls.speed_restore
    end
    return m
end
return M
