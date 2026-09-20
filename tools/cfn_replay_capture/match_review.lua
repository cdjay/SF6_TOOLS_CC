-- Partitions captured evidence without allowing a candidate window to span rounds.
local M = {}
function M.new(schema, metadata, candidates)
    local probe,err=candidates.new(schema,metadata,0)
    if not probe then return nil,err end
    local ix=schema.index
    local review={items={},rounds={},by_round={},transition_samples=0,gaps=0}
    local detector,info,previous,highest
    local function close(reason)
        if not detector then return end
        for _,item in ipairs(detector:finish(reason)) do review.items[#review.items+1]=item end
        if detector.reason=="conflicting_samples" or detector.reason=="rewound_capture" then
            review.error=detector.reason
        end
        detector=nil
    end
    local function integer(n) return type(n)=="number" and n>=0 and n%1==0 end
    function review:add(row)
        if self.error then return end
        local round,frame,stage=row[ix.round],row[ix.replay_frame],row[ix.stage_frame]
        if not integer(round) or not integer(frame) or not integer(stage) then self.error="invalid_clock"; return end
        if highest and round<highest then self.error="rewound_capture"; self.items={}; return end
        highest=round
        if row[ix.battle_round]~=round then
            if info and not info.finish_frame and info.round==round then info.gaps=info.gaps+1; self.gaps=self.gaps+1 end
            close("round_boundary"); previous=nil; self.transition_samples=self.transition_samples+1; return
        end
        if not info or info.round~=round then
            close("round_boundary"); previous=nil
            info={round=round,first_frame=frame,last_frame=frame,samples=0,gaps=0}
            self.rounds[#self.rounds+1]=info; self.by_round[round]=info
        end
        if previous then
            if frame<previous.frame or stage<previous.stage then self.error="rewound_capture"; self.items={}; return end
            if frame>previous.frame+1 or stage>previous.stage+1 then
                info.gaps=info.gaps+1; self.gaps=self.gaps+1
            end
        end
        previous={frame=frame,stage=stage}
        info.samples=info.samples+1; info.last_frame=frame
        if info.finish_frame then return end
        detector=detector or assert(candidates.new(schema,metadata,round))
        detector:add(row)
        local hp1,hp2,timer,part=row[ix["p1.vital_new"]],row[ix["p2.vital_new"]],row[ix.play_timer],row[ix.play_timer_ms]
        if type(hp1)=="number" and type(hp2)=="number" and type(timer)=="number" and type(part)=="number" then
            if hp1>0 and hp2>0 and timer>0 then info.seen_live=true end
            if info.seen_live and (hp1<=0 or hp2<=0 or timer==0 and part==0) then
                info.finish_frame=frame; close("round_end")
            end
        end
    end
    function review:finish(playback_finished)
        close("capture_end")
        self.playback_finished=playback_finished==true
        self.expected_rounds=metadata.round_count
        self.coverage_ok=self.playback_finished and not self.error and self.gaps==0
            and integer(self.expected_rounds) and self.expected_rounds>0
            and #self.rounds==self.expected_rounds
        for round=0,#self.rounds-1 do
            local entry=self.by_round[round]
            if not entry or not entry.finish_frame then self.coverage_ok=false end
        end
        if self.error then self.items={} end
        -- Coverage checks do not prove the first actionable frame or every field's semantics.
        self.full_replay_verified=false
        table.sort(self.items,function(a,b) return a.round<b.round or a.round==b.round and
            (a.frame<b.frame or a.frame==b.frame and a.defender<b.defender) end)
        return self.items
    end
    return review
end
return M
