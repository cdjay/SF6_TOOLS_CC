local M = {}

function M.attach(deps, state)
    assert(type(state.can_dispatch_control) == "function", "Control window API unavailable")
    local sdk, threads = deps.sdk, deps.thread
    local type_def = assert(sdk.find_type_definition("app.esports.ReplayUICtrl"))
    assert(deps.keyboard and deps.bindings, "Keyboard dependencies unavailable")
    local actions = assert(deps.bindings.actions)
    local method = assert(type_def:get_method("update"))
    local c = { status = "waiting", pending = nil, snapshot = nil, enabled = true, in_flight = 0 }
    local key = "sf6cc_cfn_replay_ui_control"
    local cancelled_ticket
    local analysis_actions = {previous_round=true,rewind=true, back=true, set_speed=true, resume=true, pause=true}
    local function recording_control(action)
        return c.owner ~= nil and c.purpose == "analysis" and (action == "resume" or action == "pause")
    end
    local function pause_matches(action, paused)
        return action == "pause" and paused == false or action ~= "pause" and paused == true
    end
    local function finish(status)
        if c.awaiting and c.awaiting.ticket then cancelled_ticket = c.awaiting.ticket end
        c.status, c.pending, c.awaiting, c.speed_wait, state.control_block = status, nil, nil, nil, c.owner ~= nil
    end
    function c:waiting_for_round(owner, request_id)
        local a = self.awaiting
        return owner ~= nil and self.owner == owner and (self.purpose == "analysis" or self.purpose == "round_navigation")
            and a ~= nil and a.request_id == request_id and (a.action == "previous_round" or a.action == "next_round")
            and a.sent ~= nil and state.render_tick <= a.expires
            and not (state.session and state.session:is_active())
    end
    local function missing_context()
        c.snapshot, c.clock = nil, nil
        c.context_missing_tick = c.context_missing_tick or state.render_tick
        if c:waiting_for_round(c.owner, c.awaiting and c.awaiting.request_id) then
            c.status = "round_transition"
        elseif c.status ~= "not_confirmed" then finish("outside") end
    end
    local function observe_end(ui)
        local witness = c.end_witness
        if not witness or not c.owner or c.purpose ~= "analysis" or state.session ~= witness.session
            or not state.session:is_active() then return false end
        if not ui or ui:get_address() ~= witness.ui_address then c.end_check="ui_changed"; return false end
        if ui:get_field("_ReplayEnd") ~= true then c.end_check="not_ended"; return false end
        if ui:call("get_IsResultMenuOpened") ~= true then c.end_check="window_not_open"; return false end
        local identity = deps.sampler:identity()
        if not identity or identity.replay_id ~= witness.replay_id or not identity.core
            or identity.core:get_address() ~= witness.core_address then c.end_check="identity_changed"; return false end
        c.end_event = {replay_id=witness.replay_id, core_address=witness.core_address,
            render_tick=state.render_tick, session=witness.session}
        state.session:stop("replay_end")
        c.snapshot, c.clock, c.end_check = nil, nil, "confirmed"
        finish("result_open")
        return true
    end
    local function poll_end()
        if not c.owner or c.purpose ~= "analysis" or not c.end_witness or not state.session
            or not state.session:is_active() then return false end
        -- The native UI may no longer run update at the final window. Reacquire for
        -- this read only, using the same getter route verified by read-only MCP.
        local gui = sdk.get_managed_singleton("app.GuiManager")
        local esports = gui and gui:call("get_Esports")
        return observe_end(esports and esports:call("GetReplayUICtrl"))
    end
    local function flush_cancel()
        if cancelled_ticket then
            local ticket = cancelled_ticket
            cancelled_ticket = nil
            local ok, err = pcall(deps.keyboard.cancel, deps.keyboard, ticket)
            if not ok then deps.report(tostring(err)) end
        end
    end
    local function save_result(s)
        local a = c.awaiting
        if a and a.sent and s and s.position and s.replay_id == a.before.replay_id then
            c.last_result = { before = a.before.position, after = s.position,
                key = a.binding.key, source = a.binding.source, action = a.action, render_tick = s.render_tick,
                request_id = a.request_id, timing = {
                    prepare = a.sent - a.queued_tick,
                    release = a.ack_tick and a.ack_tick - a.sent or nil,
                    confirm = a.ack_tick and math.max(0, state.render_tick - a.ack_tick) or nil,
                }, held_ms = a.held_ms, press_ms = a.press_ms, acknowledged = a.ack == true }
        end
    end
    local function observe(s)
        local a = c.awaiting
        if not a then return end
        if s.replay_id ~= a.before.replay_id or s.core_address ~= a.before.core_address then finish("replay_changed"); return end
        if not s.position then finish("position_unavailable"); return end
        if not a.sent then return end
        save_result(s)
        if a.last_frame ~= s.position.frame or a.last_round ~= s.position.round then
            a.stable = 0
        elseif a.observed_tick ~= state.render_tick then
            a.stable = (a.stable or 0) + 1
        end
        a.observed_tick = state.render_tick
        a.last_frame, a.last_round = s.position.frame, s.position.round
        -- The helper acknowledges after key-up; stable observations replace a fixed delay.
        if not a.ack then return end
        local delta = s.position.frame - a.before.position.frame
        local same_round = s.position.round == a.before.position.round
        local matched = (a.action == "resume" and not s.paused)
            or (a.action == "pause" and s.paused)
            or (a.action == "takeover" and (s.takeover or s.modal_reason == "dialog_open"))
            or (a.action == "next_round" and s.position.round == a.before.position.round + 1)
            or (a.action == "previous_round" and s.position.round == a.before.position.round - 1)
            or (a.action == "slower" and s.speed and a.before.speed and s.speed < a.before.speed)
            or (a.action == "faster" and s.speed and a.before.speed and s.speed > a.before.speed)
            or (a.action == "normal_speed" and s.speed == 1)
        if same_round and s.paused and a.stable >= a.stable_frames then
            matched = matched or (a.action == "step" and delta == 1) or (a.action == "back" and delta == -1)
                or ((a.action == "forward" or a.action == "medium_forward") and delta > 1)
                or ((a.action == "rewind" or a.action == "medium_back") and delta < -1)
        end
        if matched then finish("confirmed") end
    end
    local function fault(err)
        c.enabled, c.snapshot, c.clock = false, nil, nil
        if c.speed_restore then c.speed_restore,c.restore_status=nil,"failed" end
        finish("failed")
        deps.report(tostring(err))
    end
    function c:claim(owner, purpose)
        if not owner or self.owner or self.pending or self.awaiting or self.speed_wait or self.speed_restore or not state.alive or not self.enabled then return false end
        if purpose ~= nil and purpose ~= "analysis" and purpose ~= "round_navigation" then return false end
        self.owner, self.purpose, state.control_block, state.control_owner = owner, purpose, true, owner
        self.end_event, self.end_witness, self.context_missing_tick, self.end_check = nil, nil, nil, nil
        state:stop()
        return true
    end
    function c:release(owner)
        if self.owner ~= owner then return false end
        self.owner, self.purpose, state.control_owner = nil, nil, nil
        if self.pending or self.awaiting or self.speed_wait then finish("cancelled") else state.control_block = false end
        flush_cancel()
        return true
    end
    function c:restore_analysis_speed(owner, expected)
        if not owner or self.owner~=owner or self.purpose~="analysis" or not state.alive or not self.enabled
            or not deps.replay_speed or not expected or not expected.replay_id or not expected.core_address then return false end
        self.speed_restore={replay_id=expected.replay_id,version=expected.version,expires=state.render_tick+5400}
        self.restore_status="waiting"
        return true
    end
    local function restore_speed(ui,context,ended)
        local job,s=c.speed_restore,c.snapshot
        if not job then return false end
        local function done(status) c.speed_restore,c.restore_status=nil,status end
        if context.replay_id~=job.replay_id or job.version and context.version~=job.version then done("replay_changed"); return true end
        if job.core_address and job.core_address~=s.core_address then done("replay_changed"); return true end
        if c.owner or c.pending or c.awaiting or c.speed_wait or ended or s.modal or s.changing_round or s.takeover
            or state.session and state.session:is_active() or not state:can_dispatch_control(threads.get_id()) then return true end
        if deps.replay_speed.matches(s.speed,1) then
            job.first_match=job.first_match or state.render_tick
            if state.render_tick-job.first_match>=3 then done("restored") end
        elseif not job.sent then
            -- End windows can destroy the old core. Bind a fresh, same-replay core only
            -- at execution, then keep that identity for readback. No keyboard input.
            job.core_address,job.sent,job.expires=s.core_address,true,state.render_tick+180
            local ok,reason=deps.replay_speed.set(ui,1)
            if not ok then done(reason or "speed_unavailable") else c.restore_status="restoring" end
        else job.first_match=nil end
        return true
    end
    function c:request(action, owner, expected)
        if not state.alive or not self.enabled or self.pending or self.awaiting or self.speed_wait or self.speed_restore then return false end
        if self.owner ~= owner then return false end
        if action == "set_speed" then
            if not owner or self.purpose ~= "analysis" or not deps.replay_speed or not expected
                or type(expected.target_speed) ~= "number" then return false end
        elseif not actions[action] then return false end
        if action == "pause" and not recording_control(action) then return false end
        local allowed = self.purpose == "analysis" and analysis_actions or self.purpose == "round_navigation"
            and {previous_round=true,next_round=true} or {step=true, back=true, forward=true, rewind=true,
            medium_forward=true, medium_back=true}
        if owner and (not expected or not allowed[action]) then return false end
        local stable_frames = owner and expected.stable_frames or 3
        stable_frames = stable_frames or 3
        if stable_frames ~= 1 and stable_frames ~= 2 and stable_frames ~= 3 then return false end
        local snapshot = self.snapshot
        if (action == "set_speed" or action == "previous_round" and owner~=nil) and state.session and state.session:is_active() then self.status="capture_active"; return false end
        if not snapshot or state.render_tick - snapshot.render_tick > 120 then self.status = "waiting"; return false end
        if not pause_matches(action, snapshot.paused) then self.status = "pause_first"; return false end
        if not snapshot.position then self.status = "position_unavailable"; return false end
        if not recording_control(action) then state:stop() end
        state.latest = nil
        self.request_id = (self.request_id or 0) + 1
        self.pending = { action = action, replay_id = snapshot.replay_id, expires = state.render_tick + 600,
            request_id = self.request_id, expected = expected, stable_frames = stable_frames, queued_tick = state.render_tick,
            target_speed = expected and expected.target_speed,
            press_ms = owner and expected.press_ms or 45 }
        state.control_block, self.status = true, "queued"
        return true, self.request_id
    end
    function c:expire()
        if self.speed_restore and state.render_tick>self.speed_restore.expires then
            self.speed_restore,self.restore_status=nil,"not_confirmed"
        end
        if self.speed_wait and state.render_tick > self.speed_wait.expires then finish("not_confirmed") end
        if self.pending and state.render_tick > self.pending.expires then finish("expired") end
        if self.awaiting and state.render_tick > self.awaiting.expires then
            local clock = self.clock
            if clock and state.render_tick - clock.render_tick <= 2 then save_result(clock) end
            finish("not_confirmed")
        end
    end
    sdk.hook(method, function(args)
        local storage = threads.get_hook_storage()
        storage[key] = false
        if not state.alive or not c.enabled then return end
        if not c.owner and not c.pending and not c.awaiting and not c.speed_restore and state.render_tick > state.preview_until then return end
        c.in_flight = c.in_flight + 1
        storage[key] = { pointer = args[2], thread_id = threads.get_id() }
        if c.in_flight ~= 1 then fault("Overlapping replay UI updates") end
    end, function(retval)
        local storage = threads.get_hook_storage()
        local pending = storage[key]
        if not pending then return retval end
        storage[key] = false
        local ok, err = pcall(function()
            if not state.alive or not c.enabled then return end
            assert(c.in_flight == 1 and pending.thread_id == threads.get_id(), "Replay UI callback mismatch")
            c:expire()
            local ui = assert(sdk.to_managed_object(pending.pointer))
            -- The final window outlives the live replay context and its UI battle-core field.
            -- Bind the end edge to the same UI, selected replay and manager-owned core.
            local ended = ui:get_field("_ReplayEnd") == true
            if observe_end(ui) then return end
            local context = deps.sampler:context()
            if not context then missing_context(); return end
            local core = ui:get_field("_BattleCore")
            if not core or not context.core or core:get_address() ~= context.core:get_address() then
                c.snapshot = nil; finish("waiting"); return
            end
            local pause = ui:call("get_IsPaused")
            local switching = ui:call("get_IsChangeRound")
            local hijack = ui:call("get_IsHijackNow")
            local modal, modal_reason, result_open = false, nil, false
            for _, spec in ipairs({ { "get_IsPauseMenuOpened", "menu_open" }, { "get_IsDialogOpend", "dialog_open" },
                { "get_IsReplayListOpend", "list_open" }, { "get_IsResultMenuOpened", "result_open" },
                { "get_IsBattleSettingOpend", "settings_open" }, { "get_IsHUDSettingOpend", "hud_open" } }) do
                local value = ui:call(spec[1])
                assert(type(value) == "boolean", "Unknown replay UI state")
                modal = modal or value
                if spec[2]=="result_open" then result_open=value end
                if value and not modal_reason then modal_reason = spec[2] end
            end
            assert(type(pause) == "boolean" and type(switching) == "boolean" and type(hijack) == "boolean", "Unknown replay state")
            local speed = deps.replay_speed and deps.replay_speed.read(ui)
            c.snapshot = { replay_id = context.replay_id, paused = pause, changing_round = switching,
                takeover = hijack, modal = modal, modal_reason = modal_reason, result_open = result_open, speed = speed, render_tick = state.render_tick,
                position = deps.sampler:position(context), core_address = context.core:get_address() }
            if restore_speed(ui,context,ended) then return end
            if not ended and c.purpose == "analysis" and state.session and state.session:is_active() then
                c.end_witness = {session=state.session, replay_id=context.replay_id,
                    core_address=context.core:get_address(), ui_address=ui:get_address()}
            end
            c.context_missing_tick = nil
            if result_open and c.purpose=="analysis" and state.session and state.session:is_active()
                and state.session.metadata and state.session.metadata.replay_id==context.replay_id then
                state.session:stop("replay_end")
            end
            if c.speed_wait then
                local w,s = c.speed_wait,c.snapshot
                if s.replay_id ~= w.before.replay_id or s.core_address ~= w.before.core_address then finish("replay_changed"); return end
                if not s.position or s.position.round ~= w.before.position.round or s.position.frame ~= w.before.position.frame then finish("position_changed"); return end
                if not s.paused or s.modal or s.changing_round or s.takeover then finish("pause_first"); return end
                if deps.replay_speed.matches(s.speed,w.target) then
                    w.first_match = w.first_match or state.render_tick
                    if state.render_tick-w.first_match >= 3 then
                        c.last_result = {request_id=w.request_id,action="set_speed",source="native_speed",key=nil,
                            before=w.before.position,after=s.position,acknowledged=true,render_tick=state.render_tick,
                            before_speed=w.before.speed,after_speed=s.speed}
                        finish("confirmed")
                    end
                else w.first_match=nil end
                return
            end
            if c.awaiting then observe(c.snapshot); return end
            if not c.pending then
                if c.status == "waiting" or c.status == "outside" or c.status == "ready" or c.status == "pause_first" then
                    c.status = pause and "ready" or "pause_first"
                end
                return
            end
            local request = c.pending
            if request.replay_id ~= context.replay_id then finish("replay_changed"); return end
            -- Recheck at execution; never carry a command across resumed playback.
            if not pause_matches(request.action, pause) then finish("pause_first"); return end
            if switching then finish("round_changing"); return end
            if hijack then finish("takeover_active"); return end
            if modal then finish(modal_reason); return end
            if state.session and state.session:is_active() and not recording_control(request.action) then finish("capture_active"); return end
            if not state:can_dispatch_control(threads.get_id()) then finish("update_busy"); return end
            if not c.snapshot.position then finish("position_unavailable"); return end
            local expected = request.expected
            if expected and (expected.replay_id ~= context.replay_id or expected.core_address ~= c.snapshot.core_address
                or expected.round ~= c.snapshot.position.round
                or (request.action ~= "pause" and expected.frame ~= c.snapshot.position.frame)) then
                finish("position_changed"); return
            end
            if deps.keyboard:overlay_open() then c.status = "close_overlay"; return end
            local action = request.action
            if action == "set_speed" then
                c.pending=nil
                local changed,reason=deps.replay_speed.set(ui,request.target_speed)
                if not changed then finish(reason or "speed_unavailable"); return end
                c.speed_wait={target=request.target_speed,before=c.snapshot,request_id=request.request_id,expires=state.render_tick+180}
                c.status="setting_speed"
                return
            end
            if action == "previous_round" or action == "next_round" then
                local bar = ui:get_field("_UIReplaySeekBar")
                local allowed = bar and bar:call(action == "previous_round" and "get_ActivePrevRound" or "get_ActiveNextRound")
                if allowed ~= true then finish("round_unavailable"); return end
            end
            local binding, reason, detail = deps.bindings:resolve(ui, action)
            if not binding then c.binding_error = detail; finish(reason or "key_unavailable"); return end
            -- Prepare plain data only. File handoff happens on_frame, outside native hooks.
            c.pending = nil
            c.awaiting = { action = action, before = c.snapshot, binding = binding, expires = state.render_tick + 180,
                request_id = request.request_id, stable_frames = request.stable_frames, queued_tick = request.queued_tick,
                press_ms = request.press_ms or 45 }
            c.status = "key_queued"
        end)
        c.in_flight = c.in_flight - 1
        if not ok then fault(err) end
        return retval
    end)
    local function refresh_clock()
        if not c.owner and not c.pending and not c.awaiting and not c.speed_restore and state.render_tick > state.preview_until then return end
        if c.in_flight ~= 0 or not state:can_dispatch_control(threads.get_id()) then return end
        -- Reacquire for this read; a paused UI callback may stop before a jump settles.
        -- This does not refresh player samples or the UI pause/modal snapshot.
        local context = deps.sampler:context()
        if not context then
            if not poll_end() then missing_context() end
            return
        end
        local core_address = context.core and context.core:get_address()
        local before = c.awaiting and c.awaiting.before
        if before and (before.replay_id ~= context.replay_id or before.core_address ~= core_address) then
            c.clock, c.snapshot = nil, nil; finish("replay_changed"); return
        end
        local s = c.snapshot
        if s and (s.replay_id ~= context.replay_id or s.core_address ~= core_address) then
            c.clock, c.snapshot = nil, nil; finish("replay_changed"); return
        end
        local position = deps.sampler:position(context)
        if not position then c.clock = nil; return end
        if not state.alive or c.in_flight ~= 0 or not state:can_dispatch_control(threads.get_id()) then return end
        c.clock = { replay_id = context.replay_id, version = context.version, core_address = core_address,
            local_side = deps.sampler.local_side and deps.sampler:local_side(context),
            position = position, render_tick = state.render_tick }
        save_result(c.clock)
    end
    deps.re.on_frame(function()
        flush_cancel()
        if not state.alive or not c.enabled then return end
        local ok, err = pcall(function()
            refresh_clock()
            c:expire()
            local a, s = c.awaiting, c.snapshot
            if not a then return end
            if not a.sent then
                if not s or state.render_tick - s.render_tick > 2 or not pause_matches(a.action, s.paused) or s.modal or s.changing_round or s.takeover
                    or deps.keyboard:overlay_open() then finish("expired"); return end
                if s.replay_id ~= a.before.replay_id or not s.position or s.position.round ~= a.before.position.round
                    or (a.action ~= "pause" and s.position.frame ~= a.before.position.frame) then finish("position_changed"); return end
                if c.owner then
                    local clock = c.clock
                    if not clock or state.render_tick - clock.render_tick > 2 or clock.replay_id ~= s.replay_id
                        or clock.core_address ~= s.core_address or clock.position.round ~= s.position.round
                        or (a.action ~= "pause" and clock.position.frame ~= s.position.frame) then finish("position_changed"); return end
                end
                local ticket, reason = deps.keyboard:send(a.binding.key, a.press_ms)
                if not ticket then finish(reason); return end
                a.ticket, a.sent, c.status = ticket, state.render_tick, "key_sent"
            else
                local reply, detail = deps.keyboard:poll(a.ticket)
                if reply and reply ~= "sent" then finish(reply); return end
                if reply == "sent" and type(detail) == "table" and type(detail.held_ms) == "number"
                    and detail.held_ms >= 0 and detail.held_ms < 10000 then a.held_ms = detail.held_ms end
                if reply == "sent" and not a.ack_tick then a.ack_tick = state.render_tick end
                a.ack = reply == "sent" or a.ack
            end
        end)
        if not ok then fault(err) end
    end)
    deps.re.on_script_reset(function()
        c.speed_restore,c.restore_status=nil,nil
        c.enabled, c.snapshot, c.clock = false, nil, nil
        c.owner, c.purpose, state.control_owner = nil, nil, nil
        finish("disabled")
        flush_cancel()
    end)
    return c
end
return M
