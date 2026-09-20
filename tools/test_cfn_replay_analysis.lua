package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Analysis,Candidates,Schema,Sessions=require("analysis"),require("candidates"),require("schema"),require("session")
package.loaded["func/CFNReplayCapture/schema"]=Schema
local count=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local function fixture()
    local f={overlay=true,requests={}}
    local state={alive=true,render_tick=0,exported=true}
    local c={enabled=true,status="ready",snapshot={paused=true,speed=1,position={round=0,frame=500},replay_id="TEST",core_address=1,render_tick=0},
        clock={position={round=0,frame=500},replay_id="TEST",version=20004000,core_address=1,render_tick=0}}
    local meta={version=20004000,frame_meter_profile="native_cursor_cell_v1",replay_id="TEST",round_count=3}
    function state:stop() if self.session then self.session:stop("manual") end end
    function state:save() f.saves=(f.saves or 0)+1; self.exported=not f.save_fails; return self.exported end
    function state:start(speed,options,owner)
        eq(owner,c.owner); eq(speed,"8x"); eq(options.round_scope,nil); eq(options.stop_at_finish,nil); eq(options.limit,120000)
        self.session=Sessions.new(Schema,options); self.exported=false; return true
    end
    function c:claim(owner,purpose) if self.owner then return false end; self.owner=owner; eq(purpose,"analysis"); return true end
    function c:release(owner) if self.owner==owner then self.owner=nil; self.pending=nil end end
    function c:restore_analysis_speed(owner,expected)
        eq(owner,self.owner);eq(expected.replay_id,"TEST");eq(expected.core_address,1)
        f.restore_calls=(f.restore_calls or 0)+1;return true
    end
    function c:request(action,owner,expected)
        eq(owner,self.owner); assert(not self.pending); eq(expected.round,self.clock.position.round); eq(expected.press_ms,45)
        assert(action~="next_round" and action~="pause")
        self.pending={action=action,id=#f.requests+1,frame=self.clock.position.frame,round=self.clock.position.round}
        if action=="set_speed" then self.pending.target_speed=expected.target_speed end
        f.requests[#f.requests+1]=action; return true,self.pending.id
    end
    local n={active=false,start=function(_,frame) f.located=frame; return true end}
    local a=Analysis.attach({schema=Schema,match_review=require("match_review"),saved_capture=require("saved_capture"),
        damage_review=require("damage_review"),damage_rules=require("damage_rules"),review_assessments=require("review_assessments"),statistics=require("statistics"),
        guard_review=require("guard_review"),
        rule_config=require("rule_config"),rule_context=require("rule_context"),rule_evaluation=require("rule_evaluation"),workbench=require("workbench"),
        fs={glob=function() local paths={}; for path in pairs(f.files or {}) do paths[#paths+1]=path end; return paths end},
        json={load_file=function(path) return f.files and f.files[path] end,dump_file=function(path,doc)
            f.exports=f.exports or {};f.exports[path]=doc;return not f.export_fail end},keyboard={overlay_open=function() return f.overlay end},
        re={on_frame=function(fn) f.update=fn end,on_script_reset=function(fn) f.reset=fn end},
        report=function(e) error(e) end},state,c,n,Candidates)
    f.a,f.c,f.state,f.meta=a,c,state,meta
    function f:tick()
        state.render_tick=state.render_tick+1; c.snapshot.render_tick=state.render_tick; c.clock.render_tick=state.render_tick
        self.update()
    end
    function f:complete(frame,status,ack,round)
        local w=assert(c.pending); c.pending=nil
        round=round or w.round
        c.clock.position={round=round,frame=frame}; c.snapshot.position={round=round,frame=frame}
        c.last_result={request_id=w.id,action=w.action,acknowledged=ack~=false,
            before={round=w.round,frame=w.frame},after={round=round,frame=frame}}
        c.status=status or "confirmed"
        self:tick()
    end
    function f:prepare()
        eq(a:start(),true); self:tick(); eq(#self.requests,0)
        self.overlay=false; self:tick(); eq(c.pending.action,"rewind")
        self:complete(191); eq(c.pending.action,"rewind")
        self:complete(191,"not_confirmed"); eq(c.pending.action,"back")
        self:complete(191,"not_confirmed"); eq(c.pending.action,"set_speed"); eq(c.pending.target_speed,8)
        c.snapshot.speed=8; self:complete(191)
        eq(c.pending.action,"resume"); assert(state.session:is_active())
        c.snapshot.paused=false; self:complete(192); eq(a.phase,"recording")
    end
    function f:sample(frame,hp,timer,part)
        local round=c.clock.position.round
        local v={round=round,battle_round=round,replay_frame=frame,stage_frame=frame,thread_id=1,render_tick=state.render_tick,
            ["p1.vital_new"]=10000,["p2.vital_new"]=hp or 10000,play_timer=timer or 99,play_timer_ms=part or 59}
        return state.session:add(meta,v)
    end
    return f
end
test("whole match records through knockout and saves at result window without pause or restore keys",function()
    local f=fixture(); f:prepare(); f:sample(192); f:sample(193,0); eq(f.state.session:is_active(),true)
    f.c.snapshot.result_open=true; f.c.snapshot.modal=true; f.c.snapshot.modal_reason="result_open"; f:tick()
    eq(f.a.status,"analyzing"); eq(f.saves,1); f:tick(); eq(f.a.status,"ready"); eq(f.a.reason,"replay_end")
    eq(f.state.session.stop_reason,"replay_end"); eq(f.c.pending,nil)
    eq(f.c.owner,nil); eq(f.a.start_frame,191); eq(f.a.start_verified,false)
end)
test("whole match crosses rounds without terminating or emitting pause input",function()
    local f=fixture(); f:prepare()
    for i=1,8 do f:sample(191+i,i>=3 and 0 or 10000) end
    eq(#f.state.session.samples,8); eq(f.state.session:is_active(),true)
    f.c.clock.position.round=1; f.c.snapshot.position.round=1; local n=#f.requests; f:tick()
    f:sample(192); eq(#f.state.session.samples,9)
    eq(#f.requests,n); eq(f.a.active,true); eq(f.c.owner,f.a)
end)
test("timeout cannot silently count missed input as start without acknowledgement",function()
    local f=fixture(); f.a:start(); f.overlay=false; f:tick()
    f:complete(500,"not_confirmed",false); eq(f.a.active,false); eq(#f.requests,1)
end)
test("successful single back after large boundary probe continues rewinding",function()
    local f=fixture(); f.a:start(); f.overlay=false; f:tick(); f:complete(500,"not_confirmed")
    eq(f.c.pending.action,"back"); f:complete(499); eq(f.c.pending.action,"rewind"); eq(f.state.session,nil)
end)
test("panel reopen cancellation stops collection preserves raw data and does not send pause behind panel",function()
    local f=fixture(); f:prepare(); f:sample(192); local n=#f.requests; f.overlay=true; f:tick()
    eq(f.a.active,false); eq(f.state.session:is_active(),false); eq(f.saves,1); eq(#f.requests,n)
end)
test("identity change aborts no action sent to another replay",function()
    local f=fixture(); f.a:start(); f.c.clock.replay_id="OTHER"; f.overlay=false; f:tick()
    eq(f.a.active,false); eq(f.a.reason,"replay_changed"); eq(#f.requests,0)
end)
test("failed preservation never discards previous raw recording",function()
    local f=fixture(); local old={samples={1},is_active=function() return false end}
    f.state.session=old; f.state.exported=false; f.save_fails=true
    eq(f.a:start(),false); eq(f.state.session,old); eq(f.a.reason,"export_failed")
end)
test("candidate navigation rejects different replay or round",function()
    local f=fixture(); local item={replay_id="TEST",round=1,frame=1000}
    eq(f.a:locate(item,3,45),false); eq(f.located,nil)
    item.round=0; eq(f.a:locate(item,3,45),true); eq(f.located,1000)
    item.replay_id="OTHER"; eq(f.a:locate(item,3,45),false)
end)
test("manual active capture is never silently replaced",function()
    local f=fixture(); f.state.session={is_active=function() return true end}; eq(f.a:start(),false)
    eq(f.a.reason,"capture_active"); eq(#f.requests,0)
end)
test("reset only disables analysis no extra keyboard actions or disk writes",function()
    local f=fixture(); f:prepare(); local n=#f.requests; f.reset(); eq(f.a.active,false); eq(#f.requests,n); eq(f.saves,nil)
end)
test("analysis selects eight directly without any incremental speed hotkeys",function()
    local f=fixture(); f.a:start(); f.overlay=false; f:tick(); f:complete(191)
    f:complete(191,"not_confirmed"); f:complete(191,"not_confirmed")
    eq(f.c.pending.action,"set_speed"); eq(f.c.pending.target_speed,8)
    f.c.snapshot.speed=8; f:complete(191)
    eq(f.c.pending and f.c.pending.action,"resume"); eq(f.state.session:is_active(),true)
    f.c.snapshot.paused=false; f:complete(192); f:sample(192,0); f:tick()
    eq(f.c.pending,nil); eq(f.a.active,true)
    f.c.snapshot.result_open=true; f:tick()
    eq(f.a.active,false); eq(f.a.status,"analyzing"); eq(f.a.reason,"replay_end")
    eq(f.a.speed_requests,1)
    for _,action in ipairs(f.requests) do assert(action~="faster" and action~="slower") end
end)
test("float rounding near eight is accepted and native transition slowdown does not abort capture",function()
    local f=fixture(); f.a:start(); f.overlay=false; f:tick()
    f:complete(191); f:complete(191,"not_confirmed")
    f.c.snapshot.speed=7.9; f:complete(191,"not_confirmed"); eq(f.c.pending.action,"set_speed")
    f.c.snapshot.speed=7.9999995; f:complete(191); eq(f.c.pending.action,"resume")
    f.c.snapshot.paused=false; f:complete(192); eq(f.a.active,true); eq(f.a.phase,"recording")
    f:sample(192); f.c.snapshot.speed=1; f.c.snapshot.changing_round=true; f:tick()
    eq(f.a.active,true); eq(f.c.pending,nil)
end)
test("unconfirmed direct speed stops without resending or starting capture",function()
    local f=fixture(); f.a:start(); f.overlay=false; f:tick()
    f:complete(191); f:complete(191,"not_confirmed"); f:complete(191,"not_confirmed")
    local n=#f.requests; f:complete(191,"not_confirmed")
    eq(f.a.active,false); eq(f.a.reason,"not_confirmed"); eq(f.c.pending,nil); eq(f.state.session,nil); eq(#f.requests,n)
end)
test("speed refusal preserves its reason instead of masking it with a stale back result",function()
    local f=fixture(); f.a:start(); f.overlay=false; f:tick()
    f:complete(191); f:complete(191,"not_confirmed"); f:complete(191,"not_confirmed")
    eq(f.c.pending.action,"set_speed")
    f.c.pending=nil; f.c.status="speed_unavailable"; f:tick()
    eq(f.a.active,false); eq(f.a.reason,"speed_unavailable"); eq(f.a.stopped_phase,"speed")
    eq(f.state.session,nil)
end)
test("starting in round three returns through verified previous round controls before capture",function()
    local f=fixture(); f.c.clock.position.round=2; f.c.snapshot.position.round=2
    eq(f.a:start(),true); f.overlay=false; f:tick(); eq(f.c.pending.action,"previous_round")
    f:complete(191,"confirmed",true,1); eq(f.c.pending.action,"previous_round"); eq(f.state.session,nil)
    f:complete(191,"confirmed",true,0); eq(f.c.pending.action,"rewind"); eq(f.a.round,0)
end)
test("missed or unexpected previous round response stops without starting capture",function()
    for _,round in ipairs({0,2}) do
        local f=fixture(); f.c.clock.position.round=2; f.c.snapshot.position.round=2
        f.a:start(); f.overlay=false; f:tick(); f:complete(191,"confirmed",true,round)
        eq(f.a.active,false); eq(f.a.reason,"not_confirmed"); eq(f.state.session,nil)
    end
end)
test("result window wins over panel cancellation and a stale battle clock",function()
    local f=fixture(); f:prepare(); f:sample(192)
    f.overlay=true; f.c.snapshot.result_open=true; f.c.snapshot.modal=true
    f.state.render_tick=100; f.c.snapshot.render_tick=100; f.c.clock.render_tick=0
    f.update(); eq(f.a.reason,"replay_end"); eq(f.saves,1); eq(f.c.pending,nil)
end)
test("result window from another replay is never successful completion",function()
    local f=fixture(); f:prepare(); f:sample(192)
    f.c.snapshot.replay_id="OTHER"; f.c.snapshot.result_open=true; f:tick()
    eq(f.a.reason,"replay_changed"); eq(f.saves,1)
end)
test("midmatch pause becomes partial result while brief transition pause is tolerated",function()
    local f=fixture(); f:prepare(); f:sample(192); f.c.snapshot.paused=true
    for _=1,20 do f:tick() end; eq(f.a.active,true)
    f.c.snapshot.paused=false; f:tick(); eq(f.a.active,true)
    f.c.snapshot.paused=true; for _=1,31 do f:tick() end
    eq(f.a.reason,"paused_early"); eq(f.saves,1); eq(f.state.session.stop_reason,"paused_early")
end)
test("failed capture or backwards round never keeps recording",function()
    local f=fixture(); f:prepare(); f:sample(192); f.state.session:stop("capacity"); f:tick()
    eq(f.a.reason,"capacity"); eq(f.saves,1)
    local b=fixture(); b:prepare(); b:sample(192); b.c.clock.position.round=1; b.c.snapshot.position.round=1; b:tick()
    b.c.clock.position.round=0; b.c.snapshot.position.round=0; b:tick(); eq(b.a.reason,"rewound_capture")
end)
test("two three and five round flows all finish only on the native result signal",function()
    for _,n in ipairs({2,3,5}) do
        local f=fixture(); f.meta.round_count=n; f:prepare()
        local requests=#f.requests
        for round=0,n-1 do
            f.c.clock.position.round=round; f.c.snapshot.position.round=round
            f:sample(192); f:sample(193,0); f:tick()
            eq(f.a.active,true); eq(#f.requests,requests)
        end
        f.c.snapshot.result_open=true; f:tick(); f:tick()
        eq(f.a.status,"ready"); eq(f.a.review.coverage_ok,true); eq(#f.a.review.rounds,n)
        eq(f.saves,1); eq(#f.requests,requests); eq(f.c.owner,nil)
    end
end)
test("stale or unrelated menu state never completes the match",function()
    local f=fixture(); f:prepare(); f:sample(192)
    f.c.snapshot.modal=true; f.c.snapshot.modal_reason="dialog_open"; f:tick(); eq(f.a.reason,"dialog_open")
    local b=fixture(); b:prepare(); b:sample(192); b.c.snapshot.result_open=true
    b.state.render_tick=200; b.update(); eq(b.a.reason,"position_unavailable")
end)
test("result dialog cannot hide a capture failure that already stopped sampling",function()
    local f=fixture(); f:prepare(); f:sample(192); f.state.session:fail("overlapping_update")
    f.c.snapshot.result_open=true; f:tick(); f:tick()
    eq(f.a.reason,"overlapping_update"); eq(f.a.review.playback_finished,false); eq(f.saves,1)
end)
test("failed preparation retains the previously saved result",function()
    local f=fixture(); local old={samples={1}}; local items={{round=0,frame=123}}
    f.a.capture=old; f.a.items=items; f.a.saved=true
    eq(f.a:start(),true); eq(f.a.capture,old); eq(f.a.items,items)
    f.overlay=false; f:tick(); f.c.pending=nil; f.c.status="focus_lost"; f:tick()
    eq(f.a.active,false); eq(f.a.capture,old); eq(f.a.items,items); eq(f.a.saved,true)
end)
test("end event saves independently of destroyed live context and restarting preserves results",function()
    local f=fixture(); f:prepare(); f:sample(192); f:sample(193,0)
    f.c.snapshot=nil; f.c.clock=nil
    f.c.end_event={session=f.state.session,replay_id="TEST",core_address=1,render_tick=f.state.render_tick}
    f.update(); eq(f.a.reason,"replay_end"); eq(f.saves,1); f.update()
    local saved=f.a.capture; local items=f.a.items
    f.c.end_event=nil; f.update(); eq(f.a.capture,saved); eq(f.a.items,items); eq(f.a.status,"ready")
end)
test("foreign or stale end events cannot complete capture",function()
    for _,mode in ipairs({"session","identity","core","stale"}) do
        local f=fixture(); f:prepare(); f:sample(192)
        local e={session=f.state.session,replay_id="TEST",core_address=1,render_tick=f.state.render_tick}
        if mode=="session" then e.session={} elseif mode=="identity" then e.replay_id="OTHER"
        elseif mode=="core" then e.core_address=2 else e.render_tick=-100 end
        f.c.end_event=e; f:tick(); eq(f.a.active,true); eq(f.saves,nil)
    end
end)
test("capture waits only a bounded time for ending and overlay still cancels",function()
    for _,overlay in ipairs({true,false}) do
        local f=fixture(); f:prepare(); f:sample(192)
        f.c.snapshot=nil; f.c.clock=nil; f.c.context_missing_tick=f.state.render_tick; f.overlay=overlay
        f.update()
        if not overlay then eq(f.a.active,true); f.state.render_tick=f.state.render_tick+120; f.update() end
        eq(f.a.active,false); eq(f.saves,1); assert(f.a.reason~="replay_end")
    end
end)
local function saved_record()
    local f=fixture(); f:prepare(); f:sample(192); f:sample(193,0); f.state.session:stop("left_replay")
    return f.state.session:export()
end

test("precise review starter loads by name with no invented rules and preserves saved facts",function()
    local file=assert(io.open("tools/cfn_replay_capture/profiles/precise-review.json","rb"))
    local doc=assert(require("tools/training_record_bank/vendor/dkjson").decode(file:read("*a")));file:close()
    local config=require("rule_config");assert(config.validate(doc));eq(#doc.rules,0)
    local record=saved_record();local f=fixture()
    for _,row in ipairs(record.samples) do for i in ipairs(Schema.columns) do if row[i]==false then row[i]=0 end end end
    f.files={["cfn-capture-TEST-20260920-032052.json"]=record,[config.path]=doc}
    eq(f.a:load_saved(),true);for _=1,12 do f:tick() end
    eq(f.a.status,"ready");eq(f.a.rule_error,nil);eq(f.a.rule_name,"精准问题定义")
    eq(f.a.capture,record);assert(f.a.fact_cache)
    eq(f.saves,nil);eq(#f.requests,0)
    for _,item in ipairs(f.a.damage_items) do eq(item.custom_rule,nil) end
    local model=require("review_model").new()
    for side=1,2 do
        model:select_player(side);model:update(f.a,f.c.clock)
        eq(#model.items,0)
    end
end)

test("custom rules load once per analysis and reloading saved evidence applies a new snapshot without input",function()
    local config=require("rule_config");local doc=config.defaults()
    doc.rules={{id="custom",title="自定义检查",enabled=true,scope="damage",priority="P1",when={field="damage",op="ge",value=1}}}
    local capture=saved_record();local f=fixture()
    for _,row in ipairs(capture.samples) do for i in ipairs(Schema.columns) do if row[i]==false then row[i]=0 end end end
    f.files={["cfn-capture-20260920-032052.json"]=capture,[config.path]=doc}
    eq(f.a:load_saved(),true)
    for _=1,10 do f:tick();if f.a.status~="loading_saved" then break end end
    eq(f.a.status,"analyzing")
    doc.rules[1].title="下一轮规则"
    for _=1,10 do f:tick() end
    eq(f.a.status,"ready");eq(f.a.rule_error,nil);assert(#f.a.damage_items>0)
    eq(f.a.damage_items[1].classification.title,"自定义检查");eq(f.a.review_items[1].priority,"P1")
    local total=f.a.statistics.all.players[1].damage_received+f.a.statistics.all.players[2].damage_received
    eq(f.a:load_saved(),true);for _=1,10 do f:tick() end
    eq(f.a.damage_items[1].classification.title,"下一轮规则")
    eq(f.a.statistics.all.players[1].damage_received+f.a.statistics.all.players[2].damage_received,total)
    eq(#f.requests,0);eq(f.saves,nil)
end)

test("invalid user rules fall back visibly without losing damage records or accepting P0",function()
    local config=require("rule_config");local bad=config.defaults()
    bad.rules={{id="bad",title="不能自动确认",enabled=true,scope="damage",priority="P0",when={field="damage",op="ge",value=1}}}
    local record=saved_record()
    for _,row in ipairs(record.samples) do for i in ipairs(Schema.columns) do if row[i]==false then row[i]=0 end end end
    local f=fixture();f.files={["cfn-capture-20260920-032052.json"]=record,[config.path]=bad}
    eq(f.a:load_saved(),true);for _=1,10 do f:tick() end
    eq(f.a.status,"ready");assert(f.a.rule_error);assert(#f.a.damage_items>0)
    eq(f.a.damage_items[1].custom_rule,nil);eq(f.a.rule_name,"系统规则");eq(#f.requests,0)
end)
test("restart loads prior recording without recording playback controls or rewriting the file",function()
    local old=saved_record(); local f=fixture(); f.files={["cfn-capture-20260920-032052.json"]=old}
    eq(f.a:load_saved(),true); eq(f.a.status,"loading_saved")
    for _=1,10 do f:tick() end
    eq(f.a.status,"ready"); eq(f.a.capture,old); eq(f.a.saved,true); eq(f.a.reason,"left_replay")
    eq(f.a.review.playback_finished,false); eq(f.state.session,nil); eq(f.saves,nil); eq(#f.requests,0); eq(f.c.owner,nil)
end)
test("read failure preserves existing analysis and changed replay cannot receive loaded results",function()
    for _,mode in ipairs({"missing","invalid","changed"}) do
        local f=fixture(); local old={samples={1}}; local items={{frame=1984}}
        f.a.capture,f.a.items,f.a.status=old,items,"ready"
        local record=saved_record()
        if mode=="invalid" then record.columns={table.unpack(record.columns)}; record.columns[1]="bad" end
        f.files=mode=="missing" and {} or {["cfn-capture-20260920-032052.json"]=record}
        eq(f.a:load_saved(),true)
        if mode=="changed" then f.c.clock.replay_id="OTHER" end
        for _=1,5 do f:tick() end
        eq(f.a.capture,old); eq(f.a.items,items); eq(f.a.status,"ready"); assert(f.a.load_error)
        eq(f.saves,nil); eq(#f.requests,0)
    end
end)
test("loading can be cancelled and cannot interrupt an active capture",function()
    local f=fixture(); f.files={["cfn-capture-20260920-032052.json"]=saved_record()}
    eq(f.a:load_saved(),true); eq(f.a:start(),false); f.a:cancel(); f:tick()
    eq(f.a.loader,nil); eq(f.a.status,"idle"); eq(f.a.capture,nil)
    f.state.session={is_active=function() return true end}
    eq(f.a:load_saved(),false); eq(f.a.load_error,"control_busy"); eq(#f.requests,0)
end)
test("paused review can locate without a fresh battle simulation sample",function()
    local f=fixture()
    local item={replay_id="TEST",build=20004000,round=0,frame=1949,review_frame=1829}
    f.a.damage_items={item}; f.a.status="ready"
    f.a.damage_review={by_round={[0]={first_frame=191,last_frame=3412}}}
    f.c.clock.version=20004000
    eq(f.state.latest,nil)
    assert(f.a:locate_review(item,1,45), "paused click rejected: "..tostring(f.a.locate_reason))
    eq(f.located,1829)
    f.state.latest={render_tick=0,metadata={replay_id="TEST",version=20004000}}
    for _=1,10 do f:tick() end
    f.located=nil
    assert(f.a:locate_review(item,1,45), "paused stale sample rejected: "..tostring(f.a.locate_reason))
    eq(f.located,1829)
end)

test("review clicks use pre-event frame and reject cross-round or stale results",function()
    local f=fixture()
    local item={replay_id="TEST",build=20004000,round=0,frame=1949,review_frame=1829}
    f.a.damage_items={item}; f.a.status="ready"
    f.a.damage_review={by_round={[0]={first_frame=191,last_frame=3412}}}
    f.state.latest={render_tick=0,metadata={replay_id="TEST",version=20004000}}
    eq(f.a:locate_review(item,1,45),true); eq(f.located,1829)
    f.located=nil; item.review_frame=20
    eq(f.a:locate_review(item,1,45),true); eq(f.located,191)
    f.located=nil; item.round=1
    f.a.damage_review.by_round[1]={first_frame=191,last_frame=2000}
    eq(f.a:locate_review(item,1,45),false); eq(f.located,nil)
    item.round=0; f.c.clock.version=1
    eq(f.a:locate_review(item,1,45),false); eq(f.located,nil)
    eq(f.a.locate_reason,"replay_changed")
    f.c.clock.version=20004000; f.state.render_tick=3
    eq(f.a:locate_review(item,1,45),false); eq(f.located,nil)
    eq(f.a.locate_reason,"position_unavailable")
    f.state.render_tick=0
    f.c.clock.replay_id="OTHER"
    eq(f.a:locate_review(item,1,45),false); eq(f.a.locate_reason,"replay_changed"); eq(f.located,nil)
    f.c.clock.replay_id="TEST"; f.c.clock.version=nil
    eq(f.a:locate_review(item,1,45),false); eq(f.a.locate_reason,"position_unavailable"); eq(f.located,nil)
    f.c.clock.version=20004000
    eq(f.a:locate_review(item,1,45),true); eq(f.a.locate_reason,nil); eq(f.a.locate_round,nil)
    eq(f.a:locate_review({replay_id="TEST",round=0,frame=1,review_frame=1},1,45),false)
end)
test("saved capture is classified by the real incremental runtime pipeline",function()
    local record=saved_record()
    for _,row in ipairs(record.samples) do
        for i in ipairs(Schema.columns) do if row[i]==false then row[i]=0 end end
        row[Schema.index["p2.vital_new"]]=10000
        row[Schema.index["p2.damage_source"]]=1
        row[Schema.index["p2.act_st"]]=8
        row[Schema.index["p2.pl_input_new"]]=4
    end
    local last=record.samples[2]
    last[Schema.index["p2.vital_new"]]=9800
    last[Schema.index["p2.act_st"]]=32
    last[Schema.index["p1.mComboCount"]]=1
    last[Schema.index["p1.combo_cnt"]]=1
    last[Schema.index["p1.mComboDamage"]]=200
    local f=fixture(); f.files={["cfn-capture-20260920-032052.json"]=record}
    eq(f.a:load_saved(),true)
    for _=1,10 do f:tick() end
    eq(f.a.status,"ready"); eq(f.a.damage_error,nil); eq(#f.a.damage_items,1)
    eq(f.a.damage_items[1].classification.rule,"forward_walk_hit")
    eq(f.a.damage_items[1].damage,200); eq(f.a.damage_items[1].review_frame,193)
    eq(f.a.review_items[1].priority,"P3"); eq(f.a.confirmation_error,nil)
    eq(f.a.guard_review.finished,true);eq(f.a.guard_error,nil)
    eq(f.a:locate_review(f.a.review_items[1],1,45),true); eq(f.located,193)
    eq(#f.requests,0); eq(f.saves,nil)
end)
test("canceling data analysis retains raw capture but does not expose partial damage results",function()
    local f=fixture(); local capture={samples={}}
    f.a.status="analyzing"; f.a.capture=capture; f.a.damage_items={{}}
    f.a:cancel(); eq(f.a.status,"stopped"); eq(f.a.capture,capture); eq(#f.a.damage_items,0)
end)
test("statistics seeking requires finished matching data and same-round fresh clock",function()
    local f=fixture()
    local report={finished=true,metadata={version=20004000,replay_id="TEST"},nearest_frame=function(_,round,frame)
        if round==0 or round==1 then return frame<191 and 191 or frame end
    end}
    f.a.statistics=report;f.a.status="ready"
    eq(f.a:locate_statistics(0,180),true);eq(f.located,191)
    f.located=nil;eq(f.a:locate_statistics(1,500),false);eq(f.a.locate_reason,"round_changed");eq(f.located,nil)
    eq(f.a:locate_statistics(5,500),false);eq(f.a.locate_reason,"unavailable_review")
    f.c.clock.version=1;eq(f.a:locate_statistics(0,500),false);eq(f.a.locate_reason,"replay_changed")
    f.c.clock.version=20004000;f.c.clock.replay_id="OTHER"
    eq(f.a:locate_statistics(0,500),false);eq(f.a.locate_reason,"replay_changed")
    f.c.clock.replay_id="TEST";f.state.render_tick=3
    eq(f.a:locate_statistics(0,500),false);eq(f.a.locate_reason,"position_unavailable")
    f.state.render_tick=0;report.error="conflicting_samples"
    eq(f.a:locate_statistics(0,500),false);eq(f.a.locate_reason,"unavailable_review")
    report.error=nil;report.finished=false;eq(f.a:locate_statistics(0,500),false)
    report.finished=true;f.a.status="analyzing";eq(f.a:locate_statistics(0,500),false)
end)
test("ending or cancelling an eight-speed analysis arms restoration before releasing control",function()
    for _,mode in ipairs({"end","cancel","lost"}) do
        local f=fixture();f:prepare();f:sample(192)
        if mode=="end" then f.c.snapshot.result_open=true;f:tick()
        elseif mode=="cancel" then f.a:cancel()
        else f.c.snapshot=nil;f.c.clock=nil;f.update() end
        eq(f.restore_calls,1);eq(f.c.owner,nil)
    end
    local f=fixture();f.a:start();f.a:cancel();eq(f.restore_calls,nil)
end)
test("guard navigation only accepts owned finished evidence in the current replay and round",function()
    local f=fixture();local item={round=0,review_frame=195,build=20004000,replay_id="TEST"}
    f.a.guard_review={finished=true};f.a.guard_items={item};f.a.status="ready"
    eq(f.a:locate_guard(item),true);eq(f.located,195)
    eq(f.a:locate_guard({}),false)
    item.round=1;eq(f.a:locate_guard(item),false);eq(f.a.locate_reason,"round_changed")
    item.round=0;f.c.clock.version=1;eq(f.a:locate_guard(item),false);eq(f.a.locate_reason,"replay_changed")
    f.c.clock.version=20004000;f.state.render_tick=3;eq(f.a:locate_guard(item),false)
    f.state.render_tick=0;f.a.guard_error="conflicting_samples";eq(f.a:locate_guard(item),false)
    f.a.guard_error=nil;f.a.status="analyzing";eq(f.a:locate_guard(item),false)
end)
local function ready_rules()
    local f=fixture();local config=require("rule_config");local doc=config.defaults();local record=saved_record()
    for _,row in ipairs(record.samples) do for i in ipairs(Schema.columns) do if row[i]==false then row[i]=0 end end end
    f.files={["cfn-capture-20260920-032052.json"]=record,[config.path]=doc}
    assert(f.a:load_saved());for _=1,12 do f:tick() end
    assert(f.a.fact_cache);return f,doc
end
test("live rule update judges cached facts without sampling rebuilding or changing statistics totals",function()
    local f,doc=ready_rules();local cache,capture,stats=f.a.fact_cache,f.a.capture,f.a.statistics
    local total=stats.all.players[1].damage_received+stats.all.players[2].damage_received
    f.a.review.add=function() error("must not rebuild facts") end
    f.a.damage_review.add=f.a.review.add;f.a.guard_review.add=f.a.review.add;stats.add=f.a.review.add
    local cursor=f.a.cursor
    doc.rules={{id="live",title="新判断",scope="damage",priority="P1",enabled=true,when={field="damage",op="gt",value=0}}}
    eq(f.a:reload_rules(),true);eq(f.a.status,"ready");eq(f.a.fact_cache,cache);eq(f.a.capture,capture)
    eq(f.a.cursor,cursor);eq(f.a.statistics,stats);eq(f.a.damage_items[1].classification.title,"新判断")
    eq(stats.all.players[1].damage_received+stats.all.players[2].damage_received,total)
    doc.rules[1].enabled=false;eq(f.a:reload_rules(),true);eq(f.a.damage_items[1].custom_rule,nil)
    eq(#f.requests,0);eq(f.saves,nil)
end)

test("config-only issues change with enabled matches while facts totals and manual notes remain stored",function()
    local f,doc=ready_rules();local cache,capture,stats=f.a.fact_cache,f.a.capture,f.a.statistics
    local total=stats.all.players[1].damage_received+stats.all.players[2].damage_received
    local facts=#f.a.damage_items;assert(facts>0)
    local model=require("review_model").new()
    local function visible()
        local n=0
        for side=1,2 do model:select_player(side);model:update(f.a,f.c.clock);n=n+#model.items end
        return n
    end
    doc.include_system=false;assert(f.a:reload_rules());eq(visible(),0)
    for _,p in ipairs(stats.all.players) do eq(next(p.priorities),nil) end
    local sample=f.a.review_items[1]
    local manual={};for k,v in pairs(sample) do manual[k]=v end
    manual.id=999;manual.priority="P0";manual.human_review={source="user_verified"}
    f.a.review_items[#f.a.review_items+1]=manual;eq(visible(),0)
    doc.rules={{id="one",title="本次定义",scope="damage",priority="P1",enabled=true,
        when={all={{field="frame",op="eq",value=sample.frame},{field="side",op="eq",value=sample.receiver}}}}}
    assert(f.a:reload_rules());eq(visible(),1)
    eq(stats.all.players[sample.receiver].priorities.P1,1)
    doc.rules[1].enabled=false;assert(f.a:reload_rules());eq(visible(),0)
    doc.include_system=true;assert(f.a:reload_rules());assert(visible()>0)
    eq(f.a.fact_cache,cache);eq(f.a.capture,capture);eq(f.a.statistics,stats);eq(#f.a.damage_items,facts)
    eq(stats.all.players[1].damage_received+stats.all.players[2].damage_received,total)
    eq(#f.requests,0);eq(f.saves,nil)
end)
test("bad missing or busy rule updates preserve the last results and issue no inputs",function()
    local f,doc=ready_rules();local items=f.a.damage_items;doc.rules={{id="bad",priority="P0"}}
    eq(f.a:reload_rules(),false);eq(f.a.damage_items,items)
    f.files[require("rule_config").path]=nil;eq(f.a:reload_rules(),false);eq(f.a.damage_items,items)
    f.c.snapshot.paused=false;eq(f.a:reload_rules(),false)
    f.c.snapshot.paused=true;f.c.clock.replay_id="OTHER";eq(f.a:reload_rules(),false)
    eq(f.a.damage_items,items);eq(#f.requests,0)
end)
test("opt-in watcher applies valid profiles once and exported evidence acknowledges exact profile",function()
    local f,doc=ready_rules();eq(f.a:export_workbench(),true)
    local old=f.exports["cfn-workbench.json"];eq(old.schema,"sf6cc.replay-workbench.v1")
    doc.name="第二套规则";f.a.auto_rules=true;f:tick()
    eq(f.a.rule_name,doc.name);assert(f.exports["cfn-workbench.json"]~=old)
    local generation=f.a.rule_generation
    for _=1,250 do f:tick() end
    eq(f.a.rule_generation,generation);eq(#f.requests,0)
    f.export_fail=true;eq(f.a:export_workbench(),false)
end)
print(count.." CFN analysis tests passed")
