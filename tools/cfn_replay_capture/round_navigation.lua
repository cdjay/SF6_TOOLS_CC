local M={}
function M.attach(deps,state,controls)
    local n={active=false,status="idle"}
    local function stop(reason)
        n.active,n.reason,n.status=false,reason,reason and "stopped" or "reached"
        controls:release(n)
    end
    local function ready()
        local c,s=controls.clock,controls.snapshot
        if not state.alive or not controls.enabled then return "disabled" end
        if not c or not c.position or state.render_tick-c.render_tick>2 or not s or state.render_tick-s.render_tick>120 then return "position_unavailable" end
        if c.replay_id~=s.replay_id or c.core_address~=s.core_address then return "replay_changed" end
        if not s.paused then return "pause_first" end
        if s.modal then return s.modal_reason or "menu_open" end
        if s.takeover then return "takeover_active" end
        if s.changing_round then return "round_changing" end
    end
    function n:start(target)
        if self.active or controls.owner or type(target)~="number" or target%1~=0 or target<0 or target>98 then return false end
        local reason=ready()
        if state.session and state.session:is_active() then reason="capture_active" end
        if reason then self.reason,self.status=reason,"stopped"; return false end
        local c=controls.clock
        if c.position.round==target then self.status,self.reason="reached",nil; return true end
        if not controls:claim(self,"round_navigation") then return false end
        self.active,self.status,self.reason=true,"close_overlay",nil
        self.target,self.round,self.replay_id,self.core_address=target,c.position.round,c.replay_id,c.core_address
        self.deadline,self.waiting=state.render_tick+1800,nil
        return true
    end
    function n:cancel() if self.active then stop("cancelled") end end
    local function update()
        if not n.active then return end
        if state.render_tick>n.deadline then stop("expired"); return end
        if not state.alive or not controls.enabled then stop("disabled"); return end
        if n.waiting and controls:waiting_for_round(n,n.waiting.id) then return end
        local reason=ready()
        if reason=="round_changing" and n.waiting then return end
        if reason then stop(reason); return end
        local c=controls.clock
        if c.replay_id~=n.replay_id or c.core_address~=n.core_address then stop("replay_changed"); return end
        if n.waiting then
            if controls.pending or controls.awaiting then return end
            local r,w=controls.last_result,n.waiting
            if controls.status~="confirmed" or not r or r.request_id~=w.id or r.action~=w.action or not r.acknowledged
                or r.before.round~=n.round or r.after.round~=w.expected or c.position.round~=w.expected then
                stop(controls.status=="confirmed" and "round_changed" or controls.status); return
            end
            n.round,n.waiting=c.position.round,nil
        elseif c.position.round~=n.round then stop("round_changed"); return end
        if c.position.round==n.target then stop(); return end
        if deps.keyboard:overlay_open() then n.status="close_overlay"; return end
        local direction=n.target>n.round and 1 or -1
        local action=direction==1 and "next_round" or "previous_round"
        local ok,id=controls:request(action,n,{replay_id=n.replay_id,core_address=n.core_address,
            round=n.round,frame=c.position.frame,stable_frames=3,press_ms=45})
        if not ok then stop(controls.status or "control_busy"); return end
        n.waiting,n.status={id=id,action=action,expected=n.round+direction},"changing"
    end
    deps.re.on_frame(function() local ok,err=pcall(update); if not ok then stop("failed"); deps.report(tostring(err)) end end)
    deps.re.on_script_reset(function() if n.active then stop("disabled") end end)
    return n
end
return M
