-- Owns keyboard navigation/playback and the direct-speed adapter through controls.
local M = {}
local function same_speed(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a-b) <= 0.0001
end
function M.attach(deps, state, controls, navigation, candidates)
    local a = {active=false, status="idle", items={}}
    local function prepare_damage(metadata,prepared)
        a.fact_cache=nil
        a.rule_engine,a.rule_error,a.rule_name=nil,nil,nil
        local rules,settings=deps.damage_rules,nil
        if deps.rule_config then
            local read,document
            if prepared then read,document=true,prepared.document
            else read,document=pcall(deps.json.load_file,deps.rule_config.path) end
            local supplied=read and document~=nil
            local unreadable=false
            if read and document==nil and deps.fs and deps.fs.glob then
                local found,paths=pcall(deps.fs.glob,[[cfn-replay-rules\.json]])
                if found and type(paths)=="table" then for _,path in ipairs(paths) do
                    if type(path)=="string" and path:match("cfn%-replay%-rules%.json$") then unreadable=true end
                end end
            end
            if not read then a.rule_error="规则文件无法读取，已使用系统规则" end
            if not read or document==nil then document=deps.rule_config.defaults() end
            a.rule_engine,a.rule_error=deps.rule_config.compile(document)
            if not a.rule_engine then
                a.rule_engine=assert(deps.rule_config.compile(deps.rule_config.defaults()))
                a.rule_error="规则配置无效，已使用系统规则"
            elseif not read or unreadable then a.rule_error="规则文件无法读取，已使用系统规则" end
            settings=a.rule_engine.document.settings
            a.rule_name=supplied and not a.rule_error and a.rule_engine.document.name or "系统规则"
            if rules.with_settings then rules=rules.with_settings(settings) end
        end
        a.damage_items, a.damage_error, a.damage_review, a.review_items, a.confirmation_error = {}, nil, nil, nil, nil
        if deps.damage_review then
            a.damage_review, a.damage_error = deps.damage_review.new(deps.schema, metadata, rules)
        end
        a.statistics,a.statistics_error=nil,nil
        if deps.statistics then a.statistics,a.statistics_error=deps.statistics.new(deps.schema,metadata) end
        a.guard_review,a.guard_error,a.guard_items=nil,nil,{}
        local observation=settings
        if deps.rule_evaluation then observation={response_frames=deps.rule_evaluation.observation_limit,advantage_min=4} end
        if deps.guard_review then a.guard_review,a.guard_error=deps.guard_review.new(deps.schema,metadata,rules,observation) end
    end
    local function report(event,action)
        if not deps.analysis_report then return end
        local s=controls.snapshot
        local ok,err=pcall(deps.analysis_report,{event=event,phase=a.phase,action=action,
            reason=a.reason,round=a.round,speed=s and s.speed,control_status=controls.status,end_check=controls.end_check,
            frame=controls.clock and controls.clock.position and controls.clock.position.frame})
        if not ok then deps.report(tostring(err)) end
    end
    local function build(reason)
        a.stopped_phase=a.phase
        if reason=="replay_end" and a.owns_capture and state.session and not state.session:is_active()
            and state.session.stop_reason~="replay_end" then reason=state.session.stop_reason end
        if a.owns_capture and state.session then state.session:stop(reason or "manual") end
        if controls.restore_analysis_speed and (a.owns_capture or (a.speed_requests or 0)>0) then
            controls:restore_analysis_speed(a,{replay_id=a.replay_id,core_address=a.core_address,version=a.version})
        end
        controls:release(a)
        a.active, a.reason, a.waiting = false, reason, nil
        report("stop")
        local session = a.owns_capture and state.session or nil
        a.owns_capture = false
        if not session or #session.samples == 0 then a.status = "stopped"; return end
        a.capture = session
        a.saved = state:save()
        a.review, a.error = deps.match_review.new(deps.schema, session.metadata, candidates)
        prepare_damage(session.metadata)
        a.items, a.cursor = {}, 1
        a.status = a.review and "analyzing" or "stopped"
    end
    local function valid()
        local s, c = controls.snapshot, controls.clock
        if not state.alive or not controls.enabled then return "disabled" end
        if not s or state.render_tick - s.render_tick > 120 or not c or not c.position
            or state.render_tick - c.render_tick > 2 then return "position_unavailable" end
        if s.replay_id ~= a.replay_id or c.replay_id ~= a.replay_id
            or s.core_address ~= a.core_address or c.core_address ~= a.core_address then return "replay_changed" end
        local whole_playback=a.owns_capture and (a.phase=="recording" or a.phase=="resuming")
        local selecting=a.phase=="first_round" and (not a.waiting or a.waiting.action=="previous_round")
        if not whole_playback and not selecting
            and (c.position.round ~= a.round or s.position.round ~= a.round or s.changing_round) then return "round_changed" end
        if s.modal then return s.modal_reason or "menu_open" end
        if s.takeover then return "takeover_active" end
    end
    local function request(action,target_speed)
        local c = controls.clock
        local ok, id = controls:request(action, a, {replay_id=a.replay_id, core_address=a.core_address,
            round=c.position.round, frame=c.position.frame, stable_frames=3, press_ms=45,target_speed=target_speed})
        if not ok then build(controls.status or "control_busy"); return false end
        a.waiting = {id=id, action=action, round=c.position.round, frame=c.position.frame,target_speed=target_speed}
        report("request",action)
        a.commands = a.commands + 1
        return true
    end
    function a:start()
        if self.loader or self.active or self.status == "analyzing" or navigation.active or controls.owner then return false end
        local s, c = controls.snapshot, controls.clock
        if not s or not c or not c.position or not s.position then self.status="stopped"; self.reason="position_unavailable"; return false end
        self.replay_id, self.round, self.core_address = c.replay_id, c.position.round, c.core_address
        self.version=c.version
        self.phase,self.owns_capture,self.waiting="first_round",false,nil
        local reason = valid()
        if reason or not s.paused or type(s.speed) ~= "number" or s.speed <= 0 then
            self.status, self.reason = "stopped", reason or "pause_first"; return false
        end
        if state.session and state.session:is_active() then self.status, self.reason="stopped","capture_active"; return false end
        if state.session and #state.session.samples > 0 and not state.exported and not state:save() then
            self.status, self.reason="stopped","export_failed"; return false
        end
        if not controls:claim(self, "analysis") then return false end
        self.active, self.started, self.status, self.reason = true, false, "close_overlay", nil
        self.load_error=nil
        self.phase, self.waiting, self.commands, self.owns_capture = "first_round", nil, 0, false
        self.deadline, self.speed_requests = state.render_tick+600, 0
        self.previous_result = self.capture ~= nil
        self.last_round,self.paused_tick,self.selection_deadline,self.current_round,self.locate_round=nil,nil,nil,nil,nil
        self.locate_reason, self.end_reason, self.stopped_phase = nil, nil, nil
        report("start")
        return true
    end
    function a:cancel()
        if self.loader then self.loader=nil; self.status=self.load_status_before; return end
        if self.status=="analyzing" then
            self.status,self.reason,self.damage_items="stopped","cancelled",{}
            return
        end
        if self.active then build("cancelled") end
    end
    function a:load_saved()
        if self.loader or self.active or self.status == "analyzing" or navigation.active or controls.owner
            or state.session and state.session:is_active() then self.load_error="control_busy"; return false end
        local c=controls.clock
        if not state.alive or not c or not c.position or state.render_tick-c.render_tick>2 then
            self.load_error="position_unavailable"; return false
        end
        local ok,loader=pcall(deps.saved_capture.new,deps,deps.schema,c.replay_id)
        if not ok then self.load_error="saved_read_failed"; return false end
        if loader.error then self.load_error=loader.error; return false end
        self.loader,self.load_replay_id,self.load_status_before=loader,c.replay_id,self.status
        self.status,self.load_error="loading_saved",nil
        return true
    end
    local function safe_rule_update()
        local c,s=controls.clock,controls.snapshot
        return state.alive and a.status=="ready" and a.capture and not a.loader and not a.active
            and not navigation.active and not controls.owner and not controls.pending
            and not (state.session and state.session:is_active())
            and c and c.position and state.render_tick-c.render_tick<=2
            and s and state.render_tick-s.render_tick<=120 and s.paused
            and not s.modal and not s.takeover and not s.changing_round and not s.result_open
            and c.replay_id==a.capture.metadata.replay_id and c.version==a.capture.metadata.version
            and s.replay_id==c.replay_id and s.core_address==c.core_address
    end
    function a:reload_rules(automatic)
        if not safe_rule_update() then
            if not automatic then self.rule_reload_message="请暂停当前录像，并停止分析或定位" end
            return false
        end
        local ok,document=pcall(deps.json.load_file,deps.rule_config.path)
        if not ok or not document then self.rule_reload_message="未读到新配置，保留当前结果";return false end
        local engine,err=deps.rule_config.compile(document)
        if not engine then self.rule_reload_message="配置无效，保留当前结果："..tostring(err);return false end
        if self.rule_engine and deps.rule_config.equal(document,self.rule_engine.document) then
            self.rule_error,self.rule_name=nil,document.name
            self.rule_reload_message="当前结果已使用这份配置";return true
        end
        if not self.fact_cache then self.rule_reload_message="当前记录没有事实快照，请先读取一次已保存数据";return false end
        local evaluated,ds,gs=pcall(self.fact_cache.evaluate,self.fact_cache,engine)
        if not evaluated then self.rule_reload_message="规则判断失败，保留当前结果";return false end
        local read,document=pcall(deps.json.load_file,"cfn-review-confirmations.json")
        local assessed,items,confirmation_error=pcall(deps.review_assessments.build,ds,self.capture,self.damage_review,
            read and document or nil,deps.schema,self.fact_cache.rows)
        if not assessed then self.rule_reload_message="规则判断失败，保留当前结果";return false end
        self.damage_items,self.guard_items,self.review_items=ds,gs,items
        self.confirmation_error=read and confirmation_error or "confirmation_read_failed"
        self.rule_engine,self.rule_name,self.rule_error=engine,engine.document.name,nil
        if self.statistics and self.statistics.relabel then self.statistics:relabel(ds,items,engine) end
        self.rule_generation=(self.rule_generation or 0)+1
        self.rule_reload_message="新规则已应用，事实未重新采集或生成"
        if self.workbench_linked then self:export_workbench() end
        return true
    end
    function a:export_workbench()
        if not safe_rule_update() or not deps.workbench then self.workbench_message="请先暂停当前录像并完成分析";return false end
        local built,packet=pcall(deps.workbench.build,self,deps.schema,deps.rule_context,deps.damage_rules)
        if not built then self.workbench_message="事实数据尚未准备好";return false end
        local id=packet.capture.metadata.replay_id
        if type(id)~="string" or #id>64 or not id:match("^[A-Za-z0-9_]+$") then self.workbench_message="录像编号无效，未导出";return false end
        local archived,archive_result=pcall(deps.json.dump_file,"cfn-workbench-"..id..".json",packet,2)
        if not archived or archive_result==false then self.workbench_message="离线数据保存失败";return false end
        local ok,result=pcall(deps.json.dump_file,deps.workbench.path,packet,2)
        if not ok or result==false then self.workbench_message="离线数据保存失败";return false end
        self.workbench_linked=true
        self.workbench_message="离线数据已更新"
        return true
    end
    function a:locate(item, stable_frames, press_ms)
        if self.loader or self.active or self.status == "analyzing" then return false end
        self.locate_round=nil
        if controls.snapshot and controls.snapshot.result_open then self.locate_reason="result_open"; return false end
        local c = controls.clock
        if not c or not c.position or c.replay_id ~= item.replay_id or c.position.round ~= item.round then
            if c and c.replay_id==item.replay_id then self.locate_round=item.round end
            self.locate_reason = "round_changed"; return false
        end
        self.locate_reason = nil
        return navigation:start(item.frame, stable_frames, press_ms)
    end
    function a:locate_review(item, stable_frames, press_ms)
        self.locate_round=nil
        local owned = false
        for _, candidate in ipairs(self.review_items or self.damage_items or {}) do if candidate == item then owned=true; break end end
        if not owned or self.damage_error then self.locate_reason="unavailable_review"; return false end
        -- Paused playback can stop battle samples; the live clock reacquires the selected replay.
        local clock=controls.clock
        if not clock or not clock.position or state.render_tick-clock.render_tick>2
            or type(clock.version)~="number" then self.locate_reason="position_unavailable"; return false end
        if clock.replay_id~=item.replay_id or clock.version~=item.build then
            self.locate_reason="replay_changed"; return false
        end
        local info=self.damage_review and self.damage_review.by_round[item.round]
        if not info or type(item.review_frame)~="number" then self.locate_reason="unavailable_review"; return false end
        return self:locate({replay_id=item.replay_id,round=item.round,
            frame=math.max(info.first_frame,math.min(item.review_frame,info.last_frame))},stable_frames,press_ms)
    end
    function a:locate_statistics(round,frame)
        local report,clock=self.statistics,controls.clock
        if not report or not report.finished or report.error or self.status~="ready" then self.locate_reason="unavailable_review"; return false end
        if not clock or not clock.position or state.render_tick-clock.render_tick>2 then self.locate_reason="position_unavailable"; return false end
        if clock.replay_id~=report.metadata.replay_id or clock.version~=report.metadata.version then self.locate_reason="replay_changed"; return false end
        local target=report:nearest_frame(round,frame)
        if not target then self.locate_reason="unavailable_review"; return false end
        return self:locate({replay_id=report.metadata.replay_id,round=round,frame=target},1,45)
    end
    function a:locate_guard(item)
        if self.guard_error or not self.guard_review or not self.guard_review.finished or self.status~="ready" then
            self.locate_reason="unavailable_review";return false
        end
        local owned=false
        for _,entry in ipairs(self.guard_items or {}) do if entry==item then owned=true;break end end
        if not owned then self.locate_reason="unavailable_review";return false end
        local clock=controls.clock
        if not clock or not clock.position or state.render_tick-clock.render_tick>2 then self.locate_reason="position_unavailable";return false end
        if clock.replay_id~=item.replay_id or clock.version~=item.build then self.locate_reason="replay_changed";return false end
        return self:locate({replay_id=item.replay_id,round=item.round,frame=item.review_frame},1,45)
    end
    local function update()
        if a.loader then
            local c=controls.clock
            if not c or not c.position or state.render_tick-c.render_tick>2 or c.replay_id~=a.load_replay_id then
                a.loader,a.load_error,a.status=nil,"replay_changed",a.load_status_before; return
            end
            local loaded,done=pcall(a.loader.step,a.loader)
            if not loaded then a.loader,a.load_error,a.status=nil,"saved_read_failed",a.load_status_before; return end
            if not done then return end
            local loader=a.loader; a.loader=nil
            if loader.error then a.load_error,a.status=loader.error,a.load_status_before; return end
            local review,err=deps.match_review.new(deps.schema,loader.capture.metadata,candidates)
            if not review then a.load_error,a.status=err,a.load_status_before; return end
            a.capture,a.review,a.cursor,a.items=loader.capture,review,1,{}
            prepare_damage(loader.capture.metadata)
            a.reason,a.saved,a.saved_path=loader.capture.stop_reason,true,loader.path
            a.error,a.stopped_phase,a.previous_result,a.load_error=nil,nil,false,nil
            a.locate_reason,a.locate_round=nil,nil
            a.status="analyzing"
            return
        end
        if a.status == "analyzing" then
            local rows = a.capture.samples
            for _ = 1, 256 do
                local row = rows[a.cursor]
                if not row then
                    a.items = a.review:finish(a.reason=="replay_end")
                    if a.guard_review then
                        a.guard_items=a.guard_review:finish(a.items)
                        a.guard_error=a.guard_review.error
                    end
                    if a.damage_review then
                        a.damage_items=a.damage_review:finish()
                        a.damage_error=a.damage_review.error
                        if a.rule_engine and deps.rule_evaluation and not a.damage_error and not a.guard_error then
                            a.fact_cache=deps.rule_evaluation.new(a.capture,a.damage_items,a.guard_items,deps.schema,deps.damage_rules,deps.rule_context)
                            a.damage_items,a.guard_items=a.fact_cache:evaluate(a.rule_engine)
                        elseif a.rule_engine and deps.rule_context and not a.damage_error then
                            local context=deps.rule_context.new(a.capture,deps.schema,deps.damage_rules)
                            deps.rule_context.apply(a.rule_engine,context,a.damage_items,"damage")
                            if not a.guard_error then deps.rule_context.apply(a.rule_engine,context,a.guard_items,"guard") end
                        end
                        if deps.review_assessments and not a.damage_error then
                            local read,document=pcall(deps.json.load_file,"cfn-review-confirmations.json")
                            a.review_items,a.confirmation_error=deps.review_assessments.build(a.damage_items,a.capture,
                                a.damage_review,read and document or nil,deps.schema)
                            if not read then a.confirmation_error="confirmation_read_failed" end
                        end
                    end
                    a.error = a.review.error
                    if a.statistics then
                        if a.damage_error then a.statistics.error=a.damage_error end
                        a.statistics:finish(a.damage_items,a.review_items or a.damage_items,a.reason=="replay_end",a.rule_engine)
                    end
                    a.status = "ready"
                    a.rule_generation=(a.rule_generation or 0)+1
                    return
                end
                a.review:add(row)
                if a.damage_review then a.damage_review:add(row) end
                if a.statistics then a.statistics:add(row) end
                if a.guard_review then a.guard_review:add(row) end
                a.cursor = a.cursor + 1
            end
            return
        end
        if not a.active then
            if a.auto_rules and deps.rule_config and state.render_tick>=(a.next_rule_poll or 0) then
                a.next_rule_poll=state.render_tick+120
                a:reload_rules(true)
            end
            return
        end
        local event = controls.end_event
        if a.owns_capture and event and event.session == state.session
            and event.replay_id == a.replay_id and event.core_address == a.core_address
            and state.render_tick-event.render_tick <= 2 then
            build("replay_end"); return
        end
        -- The result window may stop battle-clock updates. Require a fresh matching UI,
        -- not a fresh battle tick; never dismiss the game's final window or send a pause key.
        local ending=controls.snapshot
        if a.owns_capture and ending and ending.result_open and not ending.takeover
            and ending.replay_id==a.replay_id and ending.core_address==a.core_address
            and state.render_tick-ending.render_tick<=2 then
            build("replay_end"); return
        end
        if deps.keyboard:overlay_open() then
            if a.started then build("overlay_open")
            elseif state.render_tick > a.deadline then build("expired") end
            return
        end
        local handoff = a.phase == "first_round" and a.waiting and a.waiting.action == "previous_round"
            and controls.waiting_for_round and controls:waiting_for_round(a, a.waiting.id)
        if handoff and (not controls.snapshot or not controls.clock) then return end
        -- Give the already-running capture a bounded window for the native end notification.
        -- No inputs are sent and no samples are fabricated while live context is absent.
        if a.owns_capture and state.session and state.session:is_active() and controls.context_missing_tick
            and state.render_tick-controls.context_missing_tick < 120
            and (not controls.snapshot or not controls.clock) then return end
        local reason = valid()
        if reason then build(reason); return end
        if not a.started then a.started, a.deadline = true, state.render_tick+36000 end
        if state.render_tick > a.deadline or a.commands >= 256 then build("navigation_limit"); return end
        local s, c = controls.snapshot, controls.clock
        if a.waiting then
            if controls.pending or controls.awaiting or controls.speed_wait then return end
            local w, r = a.waiting, controls.last_result
            a.waiting = nil
            report("result",w.action)
            if controls.status ~= "confirmed" and controls.status ~= "not_confirmed" then
                build(controls.status or "not_confirmed"); return
            end
            local after_round=w.action=="previous_round" and w.round-1 or w.round
            if not r or r.request_id ~= w.id or r.action ~= w.action or not r.acknowledged
                or r.before.round ~= w.round or r.after.round ~= after_round then build("not_confirmed"); return end
            local stationary = r.before.frame == r.after.frame and c.position.frame == w.frame
            if controls.status ~= "confirmed" then
                -- Two distinct acknowledged controls, large-back then single-back,
                -- provide a bounded lower-limit probe. This is not a proven round-start timestamp.
                if controls.status == "not_confirmed" and stationary and s.paused and w.action == "rewind" then
                    a.phase = "boundary_check"
                elseif controls.status == "not_confirmed" and stationary and s.paused and w.action == "back" then
                    a.start_frame, a.phase, a.start_verified = c.position.frame, "speed", false
                else build(controls.status); return end
            elseif w.action == "resume" then a.phase = "recording"
            elseif w.action == "previous_round" then
                a.round=after_round; a.selection_deadline=state.render_tick+600
            elseif w.action == "back" then a.phase = "rewind" end
            if w.action=="set_speed" and not same_speed(s.speed,w.target_speed) then build("speed_unavailable"); return end
        end
        if a.phase == "recording" then
            a.status = "recording"
            a.current_round=c.position.round
            if a.last_round and c.position.round<a.last_round then build("rewound_capture"); return end
            a.last_round=c.position.round
            if not state.session or not state.session:is_active() then
                build(state.session and state.session.stop_reason or "capture_stopped"); return
            end
            if s.paused and not s.changing_round then
                a.paused_tick=a.paused_tick or state.render_tick
                if state.render_tick-a.paused_tick>=30 then build("paused_early") end
            else a.paused_tick=nil end
            return
        end
        if a.phase=="first_round" then
            a.status="first_round"
            a.selection_deadline=a.selection_deadline or state.render_tick+600
            if state.render_tick>a.selection_deadline then build("not_confirmed"); return end
            if s.changing_round or s.position.round~=c.position.round then return end
            if not s.paused then build("pause_first"); return end
            a.round=c.position.round
            if a.round>0 then request("previous_round"); return end
            a.phase="rewind"
        end
        if not s.paused then build("pause_first"); return end
        if a.phase == "rewind" then a.status="rewinding"; request("rewind")
        elseif a.phase == "boundary_check" then a.status="rewinding"; request("back")
        elseif a.phase == "speed" then
            local target = 8
            a.status = "setting_speed"
            if type(s.speed) ~= "number" or s.speed <= 0 then build("speed_unavailable"); return end
            if same_speed(s.speed,target) then
                if not state:start("8x", {limit=120000, wait_for_end=true}, a) then build(state.status); return end
                a.items, a.review, a.capture, a.saved, a.error, a.previous_result = {}, nil, nil, nil, nil, false
                a.owns_capture, a.phase, a.status = true, "resuming", "resuming"
                request("resume")
            else
                a.speed_requests = a.speed_requests+1
                if a.speed_requests > 1 then build("speed_unavailable"); return end
                request("set_speed",target)
            end
        end
    end
    deps.re.on_frame(function()
        if not state.alive then return end
        local ok, err = pcall(update)
        if not ok then build("failed"); deps.report(tostring(err)) end
    end)
    deps.re.on_script_reset(function()
        a.loader=nil
        a.active, a.status = false, "stopped"
        a.reason = "disabled"
    end)
    return a
end
return M
