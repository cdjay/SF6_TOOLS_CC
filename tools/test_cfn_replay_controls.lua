package.path = "tools/cfn_replay_capture/?.lua;" .. package.path
local Controls = require("controls")
local count = 0
local function test(name, fn) fn(); count = count + 1; print("PASS " .. name) end
local function eq(a,b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function fixture(make_state)
    local f = { storage = {}, tid = 1, calls = {}, reports = {}, paused = true, allowed = true,
        frame = 1813, round = 0, native_calls = {}, cancelled = {} }
    local core = { get_address = function() return f.core_address or 123 end }
    local bar = { call = function() return f.allowed end }
    local ui = {
        get_address = function() return f.ui_address or 456 end,
        get_field = function(_, n)
            if n == "_ReplayEnd" then return f.ended or false end
            if n == "_BattleCore" then if not f.no_ui_core then return core end elseif n == "_UIReplaySeekBar" then return bar end
            if n == "_CurretSpeed" and f.speed_values then return f.speed_index or 0 end
            if n == "_ReplaySpeeds" and f.speed_values then return {
                get_size=function() return #f.speed_values end,
                get_element=function(_,i) return {
                    get_field=function(_,field) eq(field,"Speed"); return math.floor(f.speed_values[i+1]*10+0.5)+100 end,
                    call=function() return 0.5 end} end} end
            return nil
        end,
        call = function(_, n, v, remember)
            if n=="CanChangedSpeed(System.Int32)" then return not f.reject_speed end
            if n=="ChangeSpeed(System.Int32, System.Boolean)" then
                eq(remember,true)
                f.speed_calls=(f.speed_calls or 0)+1
                if not f.speed_no_effect then f.speed_index=v end
                return
            end
            if n == "get_IsPaused" then return f.paused end
            if n == "get_IsChangeRound" then return f.switching or false end
            if n == "get_IsHijackNow" then return f.hijack or false end
            if n:find("^get_") then return f.modal or n == f.modal_getter end
            f.native_calls[#f.native_calls + 1] = { n, v }
            error("Native control calls are forbidden")
        end,
    }
    local sdk = {
        get_managed_singleton = function(name)
            eq(name,"app.GuiManager")
            f.end_reads=(f.end_reads or 0)+1
            if f.no_gui then return nil end
            return {call=function(_,name)
                eq(name,"get_Esports")
                return {call=function(_,method) eq(method,"GetReplayUICtrl"); return ui end}
            end}
        end,
        find_type_definition = function() return { get_method = function() return "update" end } end,
        hook = function(_, pre, post) f.pre, f.post = pre, post end,
        to_managed_object = function() return ui end,
    }
    f.state = { alive = true, render_tick = 0, preview_until = 100, in_flight = 0,
        can_dispatch_control = function(s) return s.alive and s.in_flight == 0 end,
        stop = function(s) f.stopped = true; if s.session then s.session.active = false end end }
    if make_state then f.state = make_state(f) end
    f.c = Controls.attach({ sdk = sdk, sampler = { identity = function()
        if not f.no_identity then return {replay_id=f.identity or "TEST",core=core} end
    end, context = function()
        if f.outside then return nil end
        return { replay_id = f.identity or "TEST", version = f.version, core = core }
    end, position = function()
        if not f.no_position then return { frame = f.frame, round = f.round } end
    end }, thread = { get_hook_storage = function() return f.storage end, get_id = function() return f.tid end },
        replay_speed = require("replay_speed").new({find_type_definition=function() return {
            get_field=function(_,name)
                local value=tonumber((name:gsub("Speed_",""):gsub("_",".")))
                return {get_data=function() return math.floor(value*10+0.5)+100 end}
            end} end}),
        bindings = { actions = require("keybindings").actions, resolve = function(_, _, action)
            if f.missing_enum then return nil, "key_unavailable" end
            f.resolved = action
            return { key = f.bound_key or 67, source = "game" }
        end },
        keyboard = { overlay_open = function() return f.overlay or false end,
            send = function(_, key, press_ms)
                f.calls[#f.calls + 1] = { key = key, press_ms = press_ms }
                if f.throw then error("transport failure") end
                return { id = #f.calls }
            end,
            poll = function() if f.no_reply then return nil end; return f.reply or "sent", f.reply_detail end,
            cancel = function(_, ticket) f.cancelled[#f.cancelled + 1] = ticket end },
        re = { on_frame = function(fn) f.render = fn end, on_script_reset = function(fn) f.reset = fn end },
        report = function(e) f.reports[#f.reports + 1] = e end }, f.state)
    function f:tick()
        self.pre({ [2] = 123 }); eq(self.post(9), 9)
        self.render()
        eq(#self.native_calls, 0)
    end
    function f:advance(n)
        for _ = 1, n do self.state.render_tick = self.state.render_tick + 1; self:tick() end
    end
    f:tick()
    return f
end
local commands = { "resume", "step", "back", "slower", "faster", "normal_speed",
    "previous_round", "next_round", "rewind", "forward", "medium_forward", "medium_back", "takeover" }

test("paused clock refreshes selected replay version without a UI or battle update", function()
    local f=fixture()
    f.version=20004000; f.render()
    eq(f.c.clock.version,20004000); eq(f.state.latest,nil)
    f.state.render_tick=f.state.render_tick+10; f.version=20005000; f.render()
    eq(f.c.clock.version,20005000); eq(f.c.clock.render_tick,f.state.render_tick)
    f.version=nil; f.render(); eq(f.c.clock.version,nil)
    eq(f.c.enabled,true); eq(#f.calls,0); eq(#f.reports,0)
end)

test("temporary jump instrumentation is absent from runtime and deployment", function()
    for _, name in ipairs({ "CFN_ReplayCapture.lua", "controls.lua", "deploy.ps1" }) do
        local file = assert(io.open("tools/cfn_replay_capture/" .. name, "r"))
        local source = file:read("*a"); file:close()
        eq(source:find("jump_trace", 1, true), nil)
        eq(source:find("DEBUG-cfn-jump", 1, true), nil)
    end
    local file = io.open("tools/cfn_replay_capture/jump_trace.lua", "r")
    if file then file:close() end
    eq(file, nil)
end)

test("all controls send once outside the native UI callback and await evidence", function()
    for _, action in ipairs(commands) do
        local f = fixture(); eq(f.c:request(action), true); eq(#f.calls, 0)
        eq(f.stopped, true); eq(f.state.control_block, true); f:tick()
        eq(#f.calls, 1); eq(f.state.control_block, true); f:tick(); eq(#f.calls, 1)
    end
end)

test("playing clicks are rejected without queueing or stopping capture", function()
    for _, action in ipairs(commands) do
        local f = fixture(); f.paused = false; f:tick()
        f.state.session = { active = true, samples = { "evidence" } }
        eq(f.c:request(action), false); eq(f.c.status, "pause_first")
        eq(f.stopped, nil); eq(f.c.pending, nil); eq(f.state.session.active, true)
        eq(f.state.session.samples[1], "evidence"); eq(#f.calls, 0)
        f.paused = true; f:tick(); eq(#f.calls, 0)
    end
end)

test("plugin pause and unverified absolute seek are unavailable", function()
    local f = fixture()
    eq(f.c:request("pause"), false); eq(f.c:request("seek"), false); eq(f.c:request("unknown"), false)
    eq(f.stopped, nil); eq(#f.calls, 0)
end)

test("resume uses a resolved keyboard binding without calling native resume", function()
    local f = fixture(); f.c:request("resume"); f:tick()
    eq(f.calls[1].key, 67); eq(f.resolved, "resume"); eq(#f.native_calls, 0)
end)

test("resumed playback cancels every queued action before dispatch", function()
    for _, action in ipairs(commands) do
        local f = fixture(); f.c:request(action); f.paused = false; f:tick()
        eq(#f.calls, 0); eq(f.c.pending, nil); eq(f.c.status, "pause_first")
        f.paused = true; f:tick(); eq(#f.calls, 0)
    end
end)

test("a second click cannot replace the queued command", function()
    local f = fixture(); eq(f.c:request("step"), true); eq(f.c:request("resume"), false)
    f:tick(); eq(#f.calls, 1); eq(f.resolved, "step")
    eq(f.c:request("resume"), false)
end)

test("blocked update cancels rather than running later", function()
    local f = fixture(); f.c:request("step"); f.state.in_flight = 1; f:tick()
    eq(#f.calls, 0); eq(f.c.status, "update_busy"); eq(f.c.pending, nil)
    eq(f.state.control_block, false); f.state.in_flight = 0; f:tick(); eq(#f.calls, 0)
end)

test("expired commands do not run on a later UI update", function()
    local f = fixture(); f.c:request("step"); f.state.render_tick = 601; f.render(); f:tick()
    eq(#f.calls, 0); eq(f.c.status, "expired"); eq(f.c.pending, nil)
end)

test("stale snapshots cannot accept a command", function()
    local f = fixture(); f.state.render_tick = 121
    eq(f.c:request("step"), false); eq(f.stopped, nil); eq(f.c.status, "waiting")
end)

test("different replay and leaving playback cancel a command", function()
    local f = fixture(); f.c:request("step"); f.identity = "OTHER"; f:tick()
    eq(#f.calls, 0); eq(f.c.status, "replay_changed")
    local b = fixture(); b.c:request("step"); b.outside = true; b:tick()
    eq(#b.calls, 0); eq(b.c.status, "outside"); eq(b.c.snapshot, nil)
end)

test("each native menu cancels with a distinct reason", function()
    for getter, status in pairs({ get_IsPauseMenuOpened = "menu_open", get_IsDialogOpend = "dialog_open",
        get_IsReplayListOpend = "list_open", get_IsResultMenuOpened = "result_open",
        get_IsBattleSettingOpend = "settings_open", get_IsHUDSettingOpend = "hud_open" }) do
        local f = fixture(); f.c:request("step"); f.modal_getter = getter; f:tick()
        eq(#f.calls, 0); eq(f.c.status, status); eq(f.c.pending, nil)
        f.modal_getter = nil; f:tick(); eq(#f.calls, 0)
    end
end)

test("round transitions takeover and active capture still block dispatch", function()
    for field, status in pairs({ switching = "round_changing", hijack = "takeover_active" }) do
        local f = fixture(); f.c:request("step"); f[field] = true; f:tick()
        eq(#f.calls, 0); eq(f.c.status, status)
    end
    local f = fixture(); f.c:request("step"); f.state.session = { is_active = function() return true end }
    f:tick(); eq(#f.calls, 0); eq(f.c.status, "capture_active")
end)

test("round buttons respect native availability", function()
    for _, action in ipairs({ "previous_round", "next_round" }) do
        local f = fixture(); f.allowed = false; f.c:request(action); f:tick()
        eq(#f.calls, 0); eq(f.c.status, "round_unavailable")
    end
end)

test("missing shortcut enums fail closed", function()
    local f = fixture(); f.missing_enum = true; f.c:request("resume"); f:tick()
    eq(#f.calls, 0); eq(f.c.status, "key_unavailable"); eq(f.state.control_block, false)
end)

test("transport errors latch without retry", function()
    local f = fixture(); f.c:request("step"); f.throw = true; f:tick(); f:tick()
    eq(#f.calls, 1); eq(#f.reports, 1); eq(f.c:request("step"), false)
end)

test("reset prevents pending control calls", function()
    local f = fixture(); f.c:request("step"); f.reset(); f:tick()
    eq(#f.calls, 0); eq(f.c.status, "disabled"); eq(f.c.pending, nil)
end)

test("overlapping UI updates never dispatch", function()
    local f = fixture(); f.c:request("step"); f.pre({ [2] = 123 }); local first = f.storage
    f.storage = {}; f.pre({ [2] = 123 }); f.post(9); f.storage = first; f.post(9)
    eq(#f.calls, 0); eq(f.c.in_flight, 0)
end)

test("UI callback thread mismatch never dispatches", function()
    local f = fixture(); f.c:request("step"); f.pre({ [2] = 123 }); f.tid = 2; f.post(9)
    eq(#f.calls, 0); eq(f.c.status, "failed")
end)

local function battle_fixture()
    return fixture(function(owner)
        return require("runtime").attach({
            sdk = { find_type_definition = function() return { get_method = function() return "UpdateFrameMain" end } end,
                hook = function(_, pre, post) owner.battle_pre, owner.battle_post = pre, post end },
            thread = { get_hook_storage = function() return owner.storage end, get_id = function() return owner.tid end },
            re = { on_frame = function() end, on_script_reset = function() end },
            sampler = { context = function()
                if owner.during_read then owner.during_read() end
                return nil
            end },
            report = function(e) error(e) end,
        })
    end)
end

test("real runtime rejects both same-thread and other-thread open updates", function()
    for _, tid in ipairs({ 1, 2 }) do
        local f = battle_fixture(); f.state:request_preview(); f:tick()
        f.state.preview_until = -1; f.battle_pre(); f.tid = tid
        f.c:request("step"); f:tick(); eq(#f.calls, 0); eq(f.c.status, "update_busy")
        f.tid = 1; f.battle_post(9); f:tick(); eq(#f.calls, 0)
    end
end)

test("real runtime prevents reentrant controls during sample reads", function()
    local f = battle_fixture(); f.state:request_preview(); f:tick()
    f.battle_pre(); f.c:request("step")
    f.during_read = function() f:tick(); eq(#f.calls, 0); eq(f.c.status, "update_busy") end
    f.battle_post(9); f:tick(); eq(#f.calls, 0)
end)

test("paused control preserves stopped capture data", function()
    local f = battle_fixture(); f.state:request_preview(); f:tick()
    local session = { active = true, samples = { "evidence" },
        is_active = function(s) return s.active end,
        stop = function(s, reason) s.active, s.stop_reason = false, reason end }
    f.state.session = session
    f.c:request("resume"); f:tick(); eq(#f.calls, 1); eq(session.active, false)
    eq(session.samples[1], "evidence")
end)

test("two open battle updates never execute a control or defer it", function()
    local f = battle_fixture(); f.state:request_preview(); f:tick(); f.state.preview_until = -1
    f.battle_pre(); local first = f.storage; f.storage = {}; f.battle_pre()
    f.c:request("step"); f:tick(); eq(#f.calls, 0); eq(f.c.pending, nil)
    f.battle_post(9); f.storage = first; f.battle_post(9); f:tick(); eq(#f.calls, 0)
end)

test("overlay waits then sends only after closure", function()
    local f = fixture(); f.overlay = true; f.c:request("forward"); f:advance(5)
    eq(#f.calls, 0); eq(f.c.status, "close_overlay")
    f.overlay = false; f:tick(); eq(#f.calls, 1)
    f:advance(10); eq(#f.calls, 1)
end)

test("large jump does not confirm an intermediate one-frame advance", function()
    local f = fixture(); f.c:request("forward"); f:tick()
    f.frame = 1814; f:advance(20); eq(f.c.status, "key_sent")
    eq(f.c.last_result.after.frame, 1814)
    f.frame = 2113; f:advance(4); eq(f.c.status, "confirmed")
    eq(f.c.last_result.before.frame, 1813); eq(f.c.last_result.after.frame, 2113)
    eq(#f.calls, 1); eq(f.state.control_block, false)
end)

test("backward jumps use observed delta not a fixed step size", function()
    local f = fixture(); f.c:request("rewind"); f:tick()
    f.frame = 1550; f:advance(13); eq(f.c.status, "confirmed")
    eq(f.c.last_result.after.frame - f.c.last_result.before.frame, -263)
end)

test("single-frame keys require exactly one observed frame", function()
    for _, direction in ipairs({ {"step", 1}, {"back", -1} }) do
        local f = fixture(); f.c:request(direction[1]); f:tick()
        f.frame = f.frame + direction[2]; f:advance(13); eq(f.c.status, "confirmed")
    end
    local f = fixture(); f.c:request("step"); f:tick()
    f.frame = f.frame + 2; f:advance(181); eq(f.c.status, "not_confirmed")
    eq(#f.calls, 1)
end)

test("no movement expires without retry and preserves actual result", function()
    local f = fixture(); f.c:request("forward"); f:tick(); f:advance(181)
    eq(f.c.status, "not_confirmed"); eq(#f.calls, 1)
    eq(f.c.last_result.before.frame, f.c.last_result.after.frame)
    eq(f.state.control_block, false)
end)

test("helper failure cancels without retry", function()
    local f = fixture(); f.c:request("forward"); f:tick()
    f.reply = "focus_lost"; f:advance(5)
    eq(f.c.status, "focus_lost"); eq(#f.calls, 1); eq(#f.cancelled, 1)
end)

test("reset cancels outstanding helper ticket", function()
    local f = fixture(); f.c:request("forward"); f:tick(); f.reset()
    eq(f.c.status, "disabled"); eq(#f.cancelled, 1); f:advance(5); eq(#f.calls, 1)
end)

test("changed replay cancels outstanding helper ticket", function()
    local f = fixture(); f.c:request("forward"); f:tick(); f.identity = "OTHER"; f:tick()
    eq(f.c.status, "replay_changed"); eq(#f.cancelled, 1)
end)

test("unavailable clock prevents sending", function()
    local f = fixture(); f.no_position = true; f:tick()
    eq(f.c:request("forward"), false); eq(f.c.status, "position_unavailable"); eq(#f.calls, 0)
end)

test("preparation never writes a keyboard request from native callbacks", function()
    local f = fixture(); f.c:request("forward"); f.pre({[2] = 123}); f.post(9)
    eq(#f.calls, 0); eq(f.c.status, "key_queued")
    f.render(); eq(#f.calls, 1)
end)

test("stale prepared snapshot cancels before sending", function()
    local f = fixture(); f.c:request("forward"); f.pre({[2] = 123}); f.post(9)
    f.state.render_tick = 3; f.render(); eq(#f.calls, 0); eq(f.c.status, "expired")
end)

test("resume and round changes confirm against actual state", function()
    local f = fixture(); f.c:request("resume"); f:tick(); f.paused = false; f:advance(13)
    eq(f.c.status, "confirmed")
    local b = fixture(); b.c:request("next_round"); b:tick(); b.round = 1; b.frame = 0; b:advance(13)
    eq(b.c.status, "confirmed")
end)

test("read-only clock refreshes after the UI callback stops updating", function()
    local f = fixture(); eq(f.c.snapshot.position.frame, 1813)
    f.frame = 2112; f.state.render_tick = 1; f.render()
    assert(f.c.clock, "independent clock is missing")
    eq(f.c.clock.position.frame, 2112); eq(f.c.clock.render_tick, 1)
    eq(f.c.snapshot.position.frame, 1813); eq(#f.calls, 0)
end)

test("timed-out action keeps fresh observed frame rather than stale UI frame", function()
    local f = fixture(); f.c:request("step"); f:tick()
    f.frame = 2111
    for i = 1, 181 do f.state.render_tick = i; f.render() end
    eq(f.c.status, "not_confirmed")
    eq(f.c.last_result.before.frame, 1813); eq(f.c.last_result.after.frame, 2111)
    eq(f.c.snapshot.position.frame, 1813); eq(#f.calls, 1)
end)

test("clock read respects open battle and UI callbacks", function()
    local f = fixture(); local before = f.c.clock
    f.frame = 2112; f.state.in_flight = 1; f.render(); eq(f.c.clock, before)
    f.state.in_flight = 0; f.pre({[2] = 123}); f.render(); eq(f.c.clock, before)
    f.post(9); f.render(); eq(f.c.clock.position.frame, 2112)
end)

test("clock cannot refresh the age of the native UI state", function()
    local f = fixture(); f.state.render_tick = 121; f.state.preview_until = 123; f.render()
    eq(f.c.clock.render_tick, 121); eq(f.c.snapshot.render_tick, 0)
    eq(f.c:request("step"), false); eq(f.c.status, "waiting")
end)

test("clock is cleared on leaving replay or losing its getter", function()
    local f = fixture(); f.no_position = true; f.render(); eq(f.c.clock, nil)
    f.no_position = false; f.render(); assert(f.c.clock)
    f.outside = true; f.render(); eq(f.c.clock, nil); eq(f.c.status, "outside")
end)

test("independent clock cannot carry a command into a changed replay", function()
    local f = fixture(); f.c:request("forward"); f:tick(); f.identity = "OTHER"; f.render()
    eq(f.c.clock, nil); eq(f.c.snapshot, nil); eq(f.c.status, "replay_changed")
    eq(f.c.awaiting, nil); eq(#f.calls, 1)
end)

test("clock reads stop when preview is hidden and after reset", function()
    local f = fixture(); local before = f.c.clock
    f.state.preview_until = -1; f.frame = 2112; f.render(); eq(f.c.clock, before)
    f.reset(); f.state.preview_until = 100; f.render(); eq(f.c.clock, nil)
end)

test("medium jumps confirm actual variable distances", function()
    for _, spec in ipairs({{"medium_forward", 7}, {"medium_back", -9}}) do
        local f = fixture(); f.c:request(spec[1]); f:tick(); f.frame = f.frame + spec[2]
        f:advance(13); eq(f.c.status, "confirmed"); eq(#f.calls, 1)
    end
end)

test("sequence ownership blocks manual requests and capture between steps", function()
    local f = fixture(); local owner = {}; eq(f.c:claim(owner), true)
    eq(f.c:request("resume"), false); eq(f.c:claim({}), false)
    eq(f.c:request("next_round", owner, {}), false)
    local accepted, id = f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813})
    eq(accepted, true); f:tick(); f.frame = 1814; f:advance(13)
    eq(f.c.status, "confirmed"); eq(f.c.last_result.request_id, id)
    eq(f.state.control_block, true); eq(f.c:release({}), false)
    eq(f.c:release(owner), true); eq(f.state.control_block, false)
end)

test("owner keeps read-only UI and clock alive without player preview", function()
    local f = fixture(); f.c:claim({}); f.state.preview_until = -1; f.state.render_tick = 200
    f.frame = 2500; f:tick()
    eq(f.c.snapshot.position.frame, 2500); eq(f.c.clock.position.frame, 2500); eq(#f.calls, 0)
end)

test("expected identity and position are rechecked inside dispatch callback", function()
    for _, field in ipairs({"replay_id", "core_address", "round", "frame"}) do
        local f = fixture(); local owner = {}; f.c:claim(owner)
        local expected = {replay_id="TEST", core_address=123, round=0, frame=1813}
        expected[field] = field == "replay_id" and "OTHER" or 999
        eq(f.c:request("step", owner, expected), true); f:tick()
        eq(#f.calls, 0); eq(f.c.status, "position_changed")
        f.c:release(owner); eq(f.state.control_block, false)
    end
end)

test("clock drift after preparation prevents automatic send", function()
    local f = fixture(); local owner = {}; f.c:claim(owner)
    f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813})
    f.pre({[2]=123}); f.post(9); f.frame = 1814; f.render()
    eq(#f.calls, 0); eq(f.c.status, "position_changed")
end)

test("release cancels unsent and already handed-off owner requests", function()
    for _, sent in ipairs({false, true}) do
        local f = fixture(); local owner = {}; f.c:claim(owner)
        f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813})
        if sent then f:tick() end
        f.c:release(owner); f:advance(20)
        eq(#f.calls, sent and 1 or 0); eq(#f.cancelled, sent and 1 or 0)
        eq(f.state.control_block, false)
    end
end)

local function round_fixture()
    local f=fixture()
    f.rn=require("round_navigation").attach({re={on_frame=function(fn) f.round_pump=fn end,
        on_script_reset=function(fn) f.round_reset=fn end},keyboard={overlay_open=function() return f.overlay end},
        report=function(e) error(e) end},f.state,f.c)
    function f:pump() self:advance(1); self.round_pump() end
    return f
end
test("round selector confirms each native next or previous round without frame seeking",function()
    for _,target in ipairs({2,0}) do
        local f=round_fixture(); f.round=target==2 and 0 or 2; f:tick()
        eq(f.rn:start(target),true); local sent=0
        for _=1,60 do
            f:pump()
            if #f.calls>sent then
                sent=#f.calls
                local action=f.c.awaiting.action
                eq(action,target==2 and "next_round" or "previous_round")
                f.round=f.round+(target==2 and 1 or -1); f.frame=191
            end
            if not f.rn.active then break end
        end
        eq(f.rn.status,"reached"); eq(f.round,target); eq(sent,2); eq(f.c.owner,nil)
    end
end)
test("round selector cancels on unavailable target, wrong identity or reset",function()
    for _,mode in ipairs({"unavailable","foreign","reset","timeout"}) do
        local f=round_fixture(); eq(f.rn:start(2),true)
        if mode=="unavailable" then f.allowed=false
        elseif mode=="foreign" then f.identity="OTHER"
        elseif mode=="reset" then f.round_reset()
        else f.state.render_tick=f.rn.deadline+1; f.state.preview_until=f.state.render_tick+2 end
        for _=1,8 do f:pump() end
        eq(f.rn.active,false); eq(#f.calls,0); eq(f.c.owner,nil)
    end
end)
test("round selector waits through native context gap only for its acknowledged request",function()
    local f=round_fixture(); f.rn:start(1); f:pump(); f:pump(); eq(#f.calls,1)
    f.outside=true; f:pump(); eq(f.rn.active,true)
    f.outside=false; f.round=1; f.frame=191
    for _=1,8 do f:pump() end
    eq(f.rn.status,"reached"); eq(#f.calls,1)
end)

local function navigation_fixture()
    local f = fixture(); f.state.preview_until = -1
    f.n = require("navigation").attach({ re = {on_frame = function(fn) f.navigate = fn end,
        on_script_reset = function(fn) f.navigation_reset = fn end},
        keyboard = {overlay_open = function() return f.overlay or false end},
        report = function(e) error(e) end }, f.state, f.c)
    function f:pump()
        self:advance(1)
        self.navigate()
    end
    return f
end

test("real controls and navigator converge using all sizes in both directions", function()
    for _, target in ipairs({2737, 889}) do
        local f = navigation_fixture(); f.overlay = true; eq(f.n:start(target), true)
        f.overlay = false
        local handled, used = 0, {}
        for _ = 1, 1200 do
            f:pump()
            if #f.calls > handled then
                handled = #f.calls
                local action = f.c.awaiting.action
                used[action] = true
                f.frame = f.frame + assert(({forward=299, rewind=-299, medium_forward=8, medium_back=-8, step=1, back=-1})[action])
            end
            if not f.n.active then break end
        end
        eq(f.n.status, "reached"); eq(f.frame, target); eq(f.state.control_block, false)
        assert(used.forward or used.rewind); assert(used.medium_forward or used.medium_back); assert(used.step or used.back)
        eq(#f.native_calls, 0)
    end
end)

test("real transport refusal stops navigation without resending", function()
    local f = navigation_fixture(); f.n:start(2500); f:pump(); f:pump()
    eq(#f.calls, 1); f.reply = "focus_lost"; f:pump()
    eq(f.n.status, "stopped"); eq(f.n.reason, "focus_lost")
    f:pump(); eq(#f.calls, 1); eq(f.state.control_block, false)
end)

test("real round change before automatic send cannot cross rounds", function()
    local f = navigation_fixture(); f.n:start(2500); f:pump()
    f.round = 1; f.frame = 0; f:pump()
    eq(f.n.reason, "round_changed"); eq(#f.calls, 0); eq(f.c.pending, nil)
end)

test("reopening overlay cancels real queued sequence before any key", function()
    local f = navigation_fixture(); f.n:start(2500); f:pump()
    f.overlay = true; f:pump(); eq(f.n.status, "cancelled"); eq(#f.calls, 0)
    f.overlay = false; f:pump(); eq(#f.calls, 0)
end)

test("confirmed landing does not wait a fixed twelve render ticks", function()
    local f = fixture(); f.c:request("step"); f:tick()
    f.frame = f.frame + 1; f:advance(4)
    eq(f.c.status, "confirmed"); eq(#f.calls, 1)
end)

test("repeated UI callbacks in one render cannot fake landing stability", function()
    local f = fixture(); f.c:request("step"); f:tick(); f:advance(12)
    f.frame = f.frame + 1
    for _ = 1, 20 do f:tick() end
    eq(f.c.status, "key_sent")
    f:advance(3); eq(f.c.status, "confirmed")
end)

test("stable landing without release acknowledgement cannot confirm", function()
    local f = fixture(); f.no_reply = true
    f.c:request("step"); f:tick(); f.frame = f.frame + 1
    f:advance(20)
    eq(f.c.status, "key_sent"); eq(#f.calls, 1)
end)

test("owned speed profiles shorten only stable-read threshold", function()
    for _, stable in ipairs({1, 2, 3}) do
        local f = fixture(); local owner = {}; f.c:claim(owner)
        f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813, stable_frames=stable})
        f:tick(); f.frame = 1814; f:advance(stable)
        eq(f.c.status, "key_sent")
        f:advance(1); eq(f.c.status, "confirmed"); eq(#f.calls, 1)
    end
end)

test("zero or arbitrary confirmation thresholds cannot be requested", function()
    for _, stable in ipairs({0, -1, 0.5, 4, "1"}) do
        local f = fixture(); local owner = {}; f.c:claim(owner)
        eq(f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813, stable_frames=stable}), false)
        eq(#f.calls, 0)
    end
end)

test("fastest candidate still requires key-up acknowledgement", function()
    local f = fixture(); local owner = {}; f.c:claim(owner); f.no_reply = true
    f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813, stable_frames=1})
    f:tick(); f.frame = 1814; f:advance(8); eq(f.c.status, "key_sent")
    f.no_reply = false; f:advance(1); eq(f.c.status, "key_sent")
    f:advance(1); eq(f.c.status, "confirmed")
    eq(f.c.last_result.timing.release, 9); eq(f.c.last_result.timing.confirm, 1)
end)

test("fastest candidate does not count same-render callbacks as stable", function()
    local f = fixture(); local owner = {}; f.c:claim(owner)
    f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813, stable_frames=1})
    f:tick(); f.frame = 1814
    for _ = 1, 10 do f:tick() end
    eq(f.c.status, "key_sent"); f:advance(1); eq(f.c.status, "confirmed")
end)

test("timing sums distinguish preparation release and confirmation", function()
    local f = fixture(); f.c:request("step"); f.state.render_tick = 2; f:tick()
    f.frame = 1814; f:advance(4)
    local t = f.c.last_result.timing
    eq(t.prepare, 2); eq(t.release, 1); eq(t.confirm, 3)
    eq(t.prepare + t.release + t.confirm, f.state.render_tick)
end)

test("duration is passed to helper only for the owning sequence", function()
    local f = fixture(); f.c:request("step"); f:tick(); eq(f.calls[1].press_ms, 45)
    local b = fixture(); local owner = {}; b.c:claim(owner)
    b.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813, stable_frames=1, press_ms=20})
    b:tick(); eq(b.calls[1].press_ms, 20)
    b.reply_detail = {held_ms=22.5}; b.frame = 1814; b:advance(3)
    eq(b.c.last_result.press_ms, 20); eq(b.c.last_result.held_ms, 22.5)
end)
test("short press missing game input times out without retry", function()
    local f = fixture(); local owner = {}; f.c:claim(owner)
    f.c:request("step", owner, {replay_id="TEST", core_address=123, round=0, frame=1813, stable_frames=1, press_ms=12})
    f:tick(); f:advance(181); eq(f.c.status, "not_confirmed"); eq(#f.calls, 1)
end)
test("analysis ownership alone permits bounded speed resume and playing pause", function()
    local f=fixture(); local owner={}; eq(f.c:claim(owner,"analysis"),true)
    local expected={replay_id="TEST",core_address=123,round=0,frame=1813}
    eq(f.c:request("next_round",owner,expected),false)
    eq(f.c:request("takeover",owner,expected),false)
    eq(f.c:request("pause",owner,expected),false)
    f.paused=false; f:tick()
    f.state.session={active=true,is_active=function(s) return s.active end}
    eq(f.c:request("pause",owner,expected),true); eq(f.state.session.active,true)
    f.frame=1819; f:tick(); eq(#f.calls,1); eq(f.resolved,"pause")
    f:advance(1); f.paused=true; f:advance(1); eq(f.c.status,"confirmed")
    eq(f.c.last_result.acknowledged,true); eq(f.state.session.active,true)
end)
test("analysis resume does not stop its armed capture",function()
    local f=fixture(); local owner={}; f.c:claim(owner,"analysis")
    f.state.session={active=true,is_active=function(s) return s.active end}
    eq(f.c:request("resume",owner,{replay_id="TEST",core_address=123,round=0,frame=1813}),true)
    f:tick(); eq(#f.calls,1); eq(f.state.session.active,true)
    f:advance(1); f.paused=false; f:advance(1); eq(f.c.status,"confirmed")
end)
test("queued analysis pause cannot become resume after external pause or round transition",function()
    for _,change in ipairs({function(f) f.paused=true end,function(f) f.round=1 end}) do
        local f=fixture(); local owner={}; f.c:claim(owner,"analysis"); f.paused=false; f:tick()
        eq(f.c:request("pause",owner,{replay_id="TEST",core_address=123,round=0,frame=1813}),true)
        change(f); f:tick(); eq(#f.calls,0)
    end
end)
local function speed_fixture()
    local f=fixture(); f.speed_values={0.5,1,1.1,1.2,1.5,2,4,8}; f.speed_index=1; f:tick()
    f.owner={}; f.c:claim(f.owner,"analysis")
    f.expected={replay_id="TEST",core_address=123,round=0,frame=1813,target_speed=8}
    return f
end
test("direct speed selects native eight index once with no keys and verifies before resume",function()
    local f=speed_fixture(); eq(f.c:request("set_speed",f.owner,f.expected),true)
    f:tick(); eq(f.speed_calls,1); eq(f.speed_index,7); eq(#f.calls,0)
    eq(f.c.status,"setting_speed"); f:advance(4); eq(f.c.status,"confirmed")
    eq(f.c.last_result.after_speed,8); eq(f.c.last_result.key,nil); eq(f.c.last_result.acknowledged,true)
    eq(f.c.speed_wait,nil); eq(f.c.last_result.request_id,1)
end)
test("unconfirmed native speed expires without retry",function()
    local f=speed_fixture(); f.speed_no_effect=true; f.c:request("set_speed",f.owner,f.expected)
    f:tick(); f:advance(181); eq(f.c.status,"not_confirmed"); eq(f.speed_calls,1); eq(#f.calls,0)
end)
test("native speed is blocked outside analysis and during active capture",function()
    local f=fixture(); eq(f.c:request("set_speed"),false)
    local b=speed_fixture(); b.state.session={active=true,is_active=function(s) return s.active end}
    eq(b.c:request("set_speed",b.owner,b.expected),false); eq(b.state.session.active,true); eq(b.speed_calls,nil)
end)
test("native speed needs paused current context and clear UI callback window",function()
    for _,change in ipairs({function(f) f.paused=false end,function(f) f.round=1 end,
        function(f) f.state.in_flight=1 end,function(f) f.modal=true end}) do
        local f=speed_fixture(); f.c:request("set_speed",f.owner,f.expected); change(f); f:tick()
        eq(f.speed_calls,nil); eq(#f.calls,0)
    end
end)
test("speed readback does not accept another round and reset clears pending native work",function()
    local f=speed_fixture(); f.c:request("set_speed",f.owner,f.expected); f:tick(); f.round=1; f:advance(4)
    eq(f.c.status,"position_changed"); eq(f.c.last_result,nil); eq(f.speed_calls,1)
    local b=speed_fixture(); b.c:request("set_speed",b.owner,b.expected); b.reset(); b:tick(); eq(b.speed_calls,nil)
end)
test("real controls and analysis reach playback after native eight selection with no speed keys",function()
    local f=speed_fixture(); f.c:release(f.owner); f.frame=191; f:tick()
    function f.state:start(speed,opts,owner)
        eq(speed,"8x"); eq(opts.round_scope,nil); eq(opts.limit,120000); eq(owner,self.control_owner)
        self.session={samples={},active=true,is_active=function(s) return s.active end,stop=function(s) s.active=false end}
        return true
    end
    local analysis=require("analysis").attach({
        keyboard={overlay_open=function() return false end},match_review=require("match_review"),
        re={on_frame=function(fn) f.analyze=fn end,on_script_reset=function() end},report=function(e) error(e) end
    },f.state,f.c,{active=false},{})
    eq(analysis:start(),true)
    local handled=0
    for _=1,800 do
        f:advance(1); f.analyze()
        if #f.calls>handled then
            handled=#f.calls
            local action=assert(f.c.awaiting).action
            assert(action=="rewind" or action=="back" or action=="resume")
            if action=="resume" then f.paused=false end
        end
        if analysis.phase=="recording" then break end
    end
    eq(analysis.phase,"recording"); eq(f.paused,false); eq(f.speed_calls,1); eq(f.c.snapshot.speed,8)
    eq(#f.calls,3); eq(f.state.session.active,true)
    analysis:cancel()
end)
test("only analysis owner can return previous rounds and cannot do so while recording",function()
    local f=fixture(); f.round=2; f:tick(); local owner={}; f.c:claim(owner)
    local expected={replay_id="TEST",core_address=123,round=2,frame=1813}
    eq(f.c:request("previous_round",owner,expected),false)
    f.c:release(owner); f.c:claim(owner,"analysis")
    eq(f.c:request("previous_round",owner,expected),true); f:tick(); eq(f.resolved,"previous_round")
    f:advance(1); f.round=1; f:advance(1); eq(f.c.status,"confirmed")
    f.state.session={active=true,is_active=function(s) return s.active end}
    eq(f.c:request("previous_round",owner,expected),false); eq(f.state.session.active,true)
end)
test("native result signal stops owned matching capture but not manual or foreign capture",function()
    for _,mode in ipairs({"analysis","manual","foreign"}) do
        local f=fixture()
        if mode~="manual" then f.c:claim({},"analysis") end
        f.state.session={metadata={replay_id=mode=="foreign" and "OTHER" or "TEST"},active=true,
            is_active=function(s) return s.active end,stop=function(s,reason) s.active=false; s.stop_reason=reason end}
        f.modal_getter="get_IsResultMenuOpened"; f:tick()
        eq(f.c.snapshot.result_open,true)
        eq(f.state.session.active,mode~="analysis")
        if mode=="analysis" then eq(f.state.session.stop_reason,"replay_end") end
        eq(#f.calls,0)
    end
end)
test("owned previous-round handoff tolerates temporary missing context without sending another key",function()
    local f=fixture(); f.round=1; f:tick(); local owner={}; f.c:claim(owner,"analysis")
    f.c:request("previous_round",owner,{replay_id="TEST",core_address=123,round=1,frame=1813})
    f:tick(); f.outside=true; f:advance(30)
    eq(f.c.status,"round_transition"); assert(f.c.awaiting); eq(f.c.snapshot,nil); eq(#f.calls,1)
    f.outside=false; f.round=0; f.frame=191; f:advance(2)
    eq(f.c.status,"confirmed"); eq(f.c.last_result.after.round,0); eq(#f.calls,1)
end)
test("round handoff expires and rejects changed identity or core without retry",function()
    for _,mode in ipairs({"timeout","identity","core"}) do
        local f=fixture(); f.round=1; f:tick(); local owner={}; f.c:claim(owner,"analysis")
        f.c:request("previous_round",owner,{replay_id="TEST",core_address=123,round=1,frame=1813})
        f:tick(); f.outside=true; f:advance(10)
        if mode=="timeout" then f:advance(180); eq(f.c.awaiting,nil)
        else
            f.outside=false; f.round=0
            if mode=="identity" then f.identity="OTHER" else f.core_address=999 end
            f:advance(1); eq(f.c.status,"replay_changed"); eq(f.c.awaiting,nil)
        end
        eq(#f.calls,1)
    end
end)
test("manual previous round and unsent owned keys do not gain transition exemption",function()
    for _,owned in ipairs({true,false}) do
        local f=fixture(); f.round=1; f:tick(); local owner=owned and {} or nil
        if owner then f.c:claim(owner,"analysis") end
        f.c:request("previous_round",owner,owner and {replay_id="TEST",core_address=123,round=1,frame=1813})
        if not owned then f:tick() end
        f.outside=true; f:advance(1)
        eq(f.c.status,"outside"); eq(f.c.awaiting,nil)
    end
end)
test("native end window survives missing context and null UI core but requires witnessed identity",function()
    for _,mode in ipairs({"matching","identity","core","ui","no_identity","no_window","no_end","unwitnessed"}) do
        local f=fixture(); f.c:claim({},"analysis")
        f.state.session={metadata={replay_id="TEST"},active=true,
            is_active=function(s) return s.active end,stop=function(s,r) s.active=false; s.stop_reason=r end}
        if mode~="unwitnessed" then f:tick() end
        f.outside=true; f.no_ui_core=true; f.ended=mode~="no_end"
        if mode~="no_window" then f.modal_getter="get_IsResultMenuOpened" end
        if mode=="identity" then f.identity="OTHER" end
        if mode=="core" then f.core_address=999 end
        if mode=="ui" then f.ui_address=999 end
        if mode=="no_identity" then f.no_identity=true end
        f:advance(1)
        eq(f.c.end_event~=nil,mode=="matching"); eq(f.state.session.active,mode~="matching")
        eq(#f.calls,0)
        if mode=="matching" then eq(f.state.session.stop_reason,"replay_end") end
    end
end)
test("real analysis survives missing context during the sent previous-round command",function()
    local f=speed_fixture(); f.c:release(f.owner); f.round=1; f:tick()
    local analysis=require("analysis").attach({keyboard={overlay_open=function() return f.overlay end},
        re={on_frame=function(fn) f.analyze=fn end,on_script_reset=function() end},report=function(e) error(e) end
    },f.state,f.c,{active=false},{})
    eq(analysis:start(),true); f.analyze(); f:advance(1); f.analyze()
    eq(#f.calls,1); f.outside=true
    for _=1,30 do f:advance(1); f.analyze(); eq(analysis.active,true) end
    f.outside=false; f.round=0; f.frame=191; f:advance(1); f.analyze()
    eq(analysis.active,true); eq(analysis.phase,"rewind"); eq(#f.calls,1)
    eq(f.c.pending.action,"rewind")
end)
test("real runtime controls and analysis save at the destroyed-context end window and survive replay",function()
    local Schema=require("schema")
    local f=fixture(function(f)
        return require("runtime").attach({schema=Schema,sessions=require("session"),
            sdk={find_type_definition=function() return {get_method=function() return "battle" end} end,
                hook=function(_,pre,post) f.battle_pre,f.battle_post=pre,post end,to_int64=function(v) return v end},
            thread={get_hook_storage=function() return f.storage end,get_id=function() return f.tid end},
            re={on_frame=function(fn) f.battle_render=fn end,on_script_reset=function() end},
            sampler={context=function() if not f.outside then return {replay_id="TEST"} end end,
                metadata=function() return {replay_id="TEST",version=20004000,frame_meter_profile="native_cursor_cell_v1",round_count=1} end,
                sample=function(_,_,tick,tid) return {round=0,battle_round=0,replay_frame=f.frame,stage_frame=f.frame,
                    render_tick=tick,thread_id=tid,["p1.vital_new"]=10000,["p2.vital_new"]=f.hp or 10000,
                    play_timer=99,play_timer_ms=59} end},
            json={dump_file=function() f.writes=(f.writes or 0)+1; return true end},fs={glob=function() return {} end},
            date=function() return "TEST" end,report=function(e) error(e) end})
    end)
    local a=require("analysis").attach({schema=Schema,match_review=require("match_review"),
        keyboard={overlay_open=function() return false end},
        re={on_frame=function(fn) f.analyze=fn end,on_script_reset=function() end},report=function(e) error(e) end
    },f.state,f.c,{active=false},require("candidates"))
    f.speed_values={1,8}; f.state:request_preview(); f:tick()
    eq(a:start(),true); eq(f.state:start("8x",{wait_for_end=true},a),true)
    a.owns_capture,a.phase,a.started=true,"recording",true; f.paused=false
    f.battle_pre(); f.battle_post(1); f:advance(1); f.analyze()
    f.hp=0; f.frame=f.frame+1; f.battle_pre(); f.battle_post(1)
    f.outside=true; f.no_ui_core=true
    f.battle_pre(); f.battle_post(1); eq(f.state.session:is_active(),true)
    f:advance(1); f.analyze(); eq(a.active,true)
    f.ended=true; f.modal_getter="get_IsResultMenuOpened"
    f.state.render_tick=f.state.render_tick+1; f.render(); f.analyze(); f.analyze()
    eq(a.status,"ready"); eq(a.reason,"replay_end"); eq(a.review.coverage_ok,true); eq(f.writes,1)
    local capture,items=a.capture,a.items
    f.outside=false; f.no_ui_core=false; f.ended=false; f.modal_getter=nil; f.frame=191
    f:advance(1); f.battle_pre(); f.battle_post(1); f.analyze()
    eq(a.capture,capture); eq(a.items,items); eq(#a.capture.samples,2); eq(f.writes,1); eq(#f.calls,0)
end)
test("end notification is read after native UI updates stop without sending input",function()
    local f=fixture(); f.c:claim({},"analysis")
    f.state.session={metadata={replay_id="TEST"},active=true,
        is_active=function(s) return s.active end,stop=function(s,r) s.active=false; s.stop_reason=r end}
    f:tick()
    f.outside=true; f.no_ui_core=true; f.ended=true; f.modal_getter="get_IsResultMenuOpened"
    f.state.render_tick=f.state.render_tick+1
    f.render() -- No further ReplayUICtrl.update callbacks at the final window.
    eq(f.state.session.stop_reason,"replay_end"); assert(f.c.end_event); eq(#f.calls,0)
end)
test("end polling is read only scoped and refuses unrelated or unavailable windows",function()
    for _,mode in ipairs({"manual","busy","foreign","no_gui","no_window","expired"}) do
        local f=fixture()
        if mode~="manual" then f.c:claim({},"analysis") end
        f.state.session={metadata={replay_id="TEST"},active=true,
            is_active=function(s) return s.active end,stop=function(s,r) s.active=false; s.stop_reason=r end}
        f:tick(); f.end_reads=0
        f.outside=true; f.ended=true; f.modal_getter="get_IsResultMenuOpened"
        if mode=="busy" then f.state.in_flight=1 end
        if mode=="foreign" then f.identity="OTHER" end
        if mode=="no_gui" then f.no_gui=true end
        if mode=="no_window" then f.modal_getter=nil end
        if mode=="expired" then f.state.session:stop("left_replay") end
        f.render(); eq(f.c.end_event,nil); eq(#f.calls,0)
        if mode=="manual" or mode=="busy" or mode=="expired" then eq(f.end_reads,0) end
    end
end)
test("analysis restoration waits for replay window then restores while playing without keys",function()
    local f=speed_fixture(); f.speed_index=7
    eq(f.c:restore_analysis_speed(f.owner,f.expected),true); f.c:release(f.owner)
    f.modal_getter="get_IsResultMenuOpened"; f:advance(5); eq(f.speed_calls,nil)
    f.modal_getter=nil; f.paused=false; f.overlay=true; f.core_address=999
    f:advance(1); eq(f.speed_calls,1); eq(f.speed_index,1)
    for _=1,4 do f.frame=f.frame+1; f:advance(1) end
    eq(f.c.speed_restore,nil); eq(f.c.restore_status,"restored"); eq(#f.calls,0)
    f:advance(10); eq(f.speed_calls,1)
end)

test("restoration ownership identity and lifecycle gates prevent unsafe writes",function()
    for _,mode in ipairs({"foreign","busy","capture","reset","timeout","denied","already_normal"}) do
        local f=speed_fixture(); f.speed_index=mode=="already_normal" and 1 or 7
        eq(f.c:restore_analysis_speed({},f.expected),false)
        eq(f.c:restore_analysis_speed(f.owner,f.expected),true); f.c:release(f.owner)
        if mode=="foreign" then f.identity="OTHER" end
        if mode=="busy" then f.state.in_flight=1 end
        if mode=="capture" then f.state.session={is_active=function() return true end} end
        if mode=="reset" then f.reset() end
        if mode=="timeout" then f.state.render_tick=6000 end
        if mode=="denied" then f.reject_speed=true end
        f:advance(5); eq(f.speed_calls,nil); eq(#f.calls,0)
        if mode=="denied" then eq(f.c.restore_status,"speed_change_denied"); eq(f.c.speed_restore,nil) end
        if mode=="already_normal" then eq(f.c.restore_status,"restored"); eq(f.c.speed_restore,nil) end
    end
end)
test("speed restoration never resends on failed readback or carries across versions",function()
    local f=speed_fixture();f.speed_index=7;f.speed_no_effect=true
    f.c:restore_analysis_speed(f.owner,f.expected);f.c:release(f.owner);f:advance(200)
    eq(f.speed_calls,1);eq(f.c.speed_restore,nil);eq(f.c.restore_status,"not_confirmed");eq(#f.calls,0)
    f=speed_fixture();f.speed_index=7;f.expected.version=20004000;f.version=20005000
    f.c:restore_analysis_speed(f.owner,f.expected);f.c:release(f.owner);f:advance(1)
    eq(f.speed_calls,nil);eq(f.c.restore_status,"replay_changed")
end)
print(count .. " CFN control tests passed")
