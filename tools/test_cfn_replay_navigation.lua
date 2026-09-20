package.path = "tools/cfn_replay_capture/?.lua;" .. package.path
local Navigation = require("navigation")
local count = 0
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn) fn(); count = count + 1; print("PASS " .. name) end
local function fixture(frame)
    local f = { overlay = true, requests = {}, reports = {} }
    f.state = { alive = true, render_tick = 0 }
    f.c = { enabled = true, status = "ready", snapshot = { replay_id = "A", paused = true,
        render_tick = 0, position = {round = 0, frame = frame or 100} } }
    function f.c:claim(owner)
        if self.owner or self.pending or self.awaiting then return false end
        self.owner, f.state.control_block = owner, true; return true
    end
    function f.c:release(owner)
        if self.owner ~= owner then return false end
        self.owner, self.pending, self.awaiting, f.state.control_block = nil, nil, nil, false
        f.releases = (f.releases or 0) + 1; return true
    end
    function f.c:request(action, owner, expected)
        eq(owner, self.owner); eq(f.overlay, false); eq(self.pending, nil)
        eq(expected.frame, self.clock.position.frame); eq(expected.round, self.clock.position.round)
        f.requests[#f.requests + 1] = action
        self.pending, self.status = {action = action, stable_frames = expected.stable_frames, press_ms = expected.press_ms}, "queued"
        return true, #f.requests
    end
    f.n = Navigation.attach({ re = {on_frame = function(fn) f.pump = fn end,
        on_script_reset = function(fn) f.reset = fn end}, keyboard = {overlay_open = function() return f.overlay end},
        now = function() return f.state.render_tick / 60 end,
        navigation_report = function(result) f.reported = result end,
        report = function(err) f.reports[#f.reports + 1] = err end }, f.state, f.c)
    function f:tick(stale)
        self.state.render_tick = self.state.render_tick + 1
        if self.c.snapshot and not stale then
            local s = self.c.snapshot
            s.render_tick = self.state.render_tick
            self.c.clock = { replay_id = s.replay_id, core_address = s.core_address, render_tick = s.render_tick,
                position = {round = s.position.round, frame = s.position.frame} }
        end
        self.pump()
    end
    function f:complete(delta, status)
        local action = assert(self.c.pending).action
        local s = self.c.snapshot
        self.c.last_result = { action = action, request_id = #self.requests, before = {round = s.position.round, frame = s.position.frame},
            after = {round = s.position.round, frame = s.position.frame + delta} }
        s.position.frame = s.position.frame + delta
        self.c.pending, self.c.status = nil, status or "confirmed"
        self:tick()
    end
    function f:run(target, stride)
        eq(self.n:start(target), true); self.overlay = false; self:tick()
        for _ = 1, 520 do
            if not self.n.active then break end
            local action = assert(self.c.pending).action
            local delta = ({step = 1, back = -1, forward = stride, rewind = -stride, medium_forward = 8, medium_back = -8})[action]
            self:complete(delta)
        end
    end
    f:tick()
    return f
end
test("nearby target uses single frames and stops exactly", function()
    local f = fixture(); f:run(103, 300)
    eq(f.n.status, "reached"); eq(#f.requests, 3); eq(f.n.current, 103)
    for _, a in ipairs(f.requests) do eq(a, "step") end
    eq(f.state.control_block, false)
end)
test("backward nearby target uses backward single frames", function()
    local f = fixture(); f:run(96, 300); eq(f.n.status, "reached"); eq(#f.requests, 4)
    for _, a in ipairs(f.requests) do eq(a, "back") end
end)
test("unknown stride is measured rather than assumed to be 300", function()
    local f = fixture(); f:run(900, 263)
    eq(f.n.status, "reached"); eq(f.n.current, 900)
    eq(f.n.strides.forward, 263); eq(#f.requests, 7)
    eq(f.requests[1], "forward"); eq(f.requests[3], "forward"); eq(f.requests[4], "medium_forward")
end)
test("coarse backward positioning also learns actual distance", function()
    local f = fixture(1000); f:run(192, 400)
    eq(f.n.status, "reached"); eq(f.n.current, 192); eq(#f.requests, 3)
end)
test("large overshoot reduces to medium then single frames without bouncing", function()
    local f = fixture(100); f:run(400, 400)
    eq(f.n.status, "reached"); eq(#f.requests, 17); eq(f.n.max_tier, 2)
    eq(f.requests[1], "forward")
    for i = 2, 13 do eq(f.requests[i], "medium_back") end
    for i = 14, #f.requests do eq(f.requests[i], "back") end
end)
test("variable coarse step updates conservative estimate", function()
    local f = fixture(); f.n:start(1000); f.overlay = false; f:tick()
    f:complete(263); f:complete(400)
    eq(f.n.strides.forward, 400); eq(f.c.pending.action, "forward")
end)
test("already at target sends nothing", function()
    local f = fixture(); f:run(100, 300); eq(f.n.status, "reached"); eq(#f.requests, 0)
end)
test("overlay must close before first request", function()
    local f = fixture(); f.n:start(101); f:tick(); eq(#f.requests, 0)
    eq(f.n.status, "close_overlay"); f.overlay = false; f:tick(); eq(#f.requests, 1)
end)
test("opening overlay during positioning cancels outstanding control", function()
    local f = fixture(); f.n:start(105); f.overlay = false; f:tick(); f.overlay = true; f:tick()
    eq(f.n.status, "cancelled"); eq(f.c.pending, nil); eq(f.state.control_block, false)
    f.overlay = false; f:tick(); eq(#f.requests, 1)
end)
test("a second target cannot replace an active run", function()
    local f = fixture(); eq(f.n:start(105), true); eq(f.n:start(200), false); eq(f.n.target, 105)
end)
test("invalid target does not claim control", function()
    for _, target in ipairs({-1, 1.5, "100", math.huge, 1000001}) do
        local f = fixture(); eq(f.n:start(target), false); eq(f.c.owner, nil); eq(f.n.status, "invalid_target")
    end
end)
test("playing stale modal and transitioning snapshots block start", function()
    for _, change in ipairs({function(f) f.c.snapshot.paused = false end,
        function(f) f.state.render_tick = 130 end, function(f) f.c.snapshot.modal = true end,
        function(f) f.c.snapshot.changing_round = true end, function(f) f.c.snapshot.takeover = true end}) do
        local f = fixture(); change(f); eq(f.n:start(101), false); eq(f.c.owner, nil)
    end
end)
test("busy control is never taken over", function()
    local f = fixture(); f.c.pending = {action = "resume"}
    eq(f.n:start(101), false); eq(f.n.reason, "control_busy"); eq(f.c.pending.action, "resume")
end)
test("scene replay and round changes cancel without crossing a boundary", function()
    for _, change in ipairs({function(f) f.c.snapshot = nil end,
        function(f) f.c.snapshot.replay_id = "B" end, function(f) f.c.snapshot.position.round = 1 end,
        function(f) f.c.snapshot.paused = false end, function(f) f.c.snapshot.modal = true end}) do
        local f = fixture(); f.n:start(500); f.overlay = false; f:tick(); change(f); f:tick()
        eq(f.n.status, "stopped"); eq(f.n.active, false); eq(f.c.pending, nil); eq(#f.requests, 1)
    end
end)
test("unconfirmed movement stops rather than resending", function()
    local f = fixture(); f.n:start(500); f.overlay = false; f:tick(); f:complete(1, "not_confirmed")
    eq(f.n.status, "stopped"); eq(f.n.reason, "not_confirmed"); eq(#f.requests, 1)
end)
test("pending intermediate position never triggers another key", function()
    local f = fixture(); f.n:start(500); f.overlay = false; f:tick()
    f.c.snapshot.position.frame = 101; f:tick(); eq(#f.requests, 1); eq(f.n.active, true)
end)
test("wrong direction and invalid single frame response stop", function()
    for _, delta in ipairs({-1, 0, 2}) do
        local f = fixture(); f.n:start(103); f.overlay = false; f:tick(); f:complete(delta)
        eq(f.n.status, "stopped"); eq(f.n.reason, "position_changed"); eq(#f.requests, 1)
    end
end)
test("helper acknowledgement alone cannot complete positioning", function()
    local f = fixture(); f.n:start(101); f.overlay = false; f:tick(); f:complete(1, "key_sent")
    eq(f.n.status, "stopped"); eq(f.n.reason, "key_sent")
end)
test("external movement before dispatch cancels", function()
    local f = fixture(); f.n:start(500); f.c.snapshot.position.frame = 200
    f.overlay = false; f:tick(); eq(f.n.reason, "position_changed"); eq(#f.requests, 0)
end)
test("stale result cannot be accepted", function()
    local f = fixture(); f.n:start(101); f.overlay = false; f:tick()
    f.c.pending, f.c.status = nil, "confirmed"
    f.c.last_result = {action = "step", before = {round = 0, frame = 99}, after = {round = 0, frame = 100}}
    f:tick(); eq(f.n.reason, "position_changed")
end)
test("stale clock during a run cancels", function()
    local f = fixture(); f.n:start(500); f.overlay = false; f:tick()
    f.state.render_tick = 10; f:tick(true); eq(f.n.reason, "position_unavailable")
end)
test("close-overlay wait and overall run are bounded", function()
    local f = fixture(); f.n:start(500); f.state.render_tick = f.n.deadline; f:tick()
    eq(f.n.reason, "expired"); eq(#f.requests, 0)
    local b = fixture(); b.n:start(500); b.overlay = false; b:tick()
    b.state.render_tick = b.n.deadline; b:tick(); eq(b.n.reason, "navigation_limit"); eq(#b.requests, 1)
end)
test("command count is bounded for an unreachable distant target", function()
    local f = fixture(); f:run(1000000, 2)
    eq(f.n.reason, "navigation_limit"); eq(#f.requests, 512); eq(f.n.active, false)
end)
test("cancel and reset stop future requests and release recording block", function()
    for _, reset in ipairs({false, true}) do
        local f = fixture(); f.n:start(500); f.overlay = false; f:tick()
        if reset then f.reset() else f.n:cancel() end
        f:tick(); eq(f.n.active, false); eq(#f.requests, 1); eq(f.state.control_block, false)
    end
end)
test("medium overshoot retires both jump sizes and uses singles", function()
    local f = fixture(); f.n:start(111); f.overlay = false; f:tick()
    eq(f.c.pending.action, "medium_forward"); f:complete(13)
    eq(f.c.pending.action, "back"); eq(f.n.max_tier, 1)
    f:complete(-1); f:complete(-1); eq(f.n.status, "reached")
end)

test("variable medium size is an estimate not a required delta", function()
    local f = fixture(); f.n:start(126); f.overlay = false; f:tick()
    f:complete(7); eq(f.c.pending.action, "medium_forward")
    f:complete(9); f:complete(9); eq(f.c.pending.action, "step")
    f:complete(1); eq(f.n.status, "reached"); eq(f.n.current, 126)
end)

test("starting uses independent clock rather than stale UI frame", function()
    local f = fixture(); f.c.clock.position.frame = 1089
    eq(f.n:start(1089), true); eq(f.n.status, "reached"); eq(#f.requests, 0)
end)

test("fresh clock cannot disguise stale pause state", function()
    local f = fixture(); f.state.render_tick = 200; f.c.clock.render_tick = 200
    eq(f.n:start(101), false); eq(f.n.reason, "waiting")
end)

test("result from another request cannot complete a run", function()
    local f = fixture(); f.n:start(101); f.overlay = false; f:tick()
    f.c.pending, f.c.status = nil, "confirmed"
    f.c.snapshot.position.frame = 101
    f.c.last_result = {request_id = 999, action = "step", before = {round=0, frame=100}, after = {round=0, frame=101}}
    f:tick(); eq(f.n.reason, "position_changed")
end)

test("new core under same replay identifier cancels", function()
    local f = fixture(); f.n:start(500); f.overlay = false; f:tick()
    f.c.snapshot.core_address = 999; f:tick()
    eq(f.n.reason, "replay_changed"); eq(#f.requests, 1)
end)

test("native boundary no-progress stops and never switches rounds", function()
    local f = fixture(999); f.n:start(2000); f.overlay = false; f:tick()
    f:complete(0, "not_confirmed"); eq(f.n.status, "stopped"); eq(#f.requests, 1)
    f:tick(); eq(#f.requests, 1)
end)

test("all three sizes converge across multiple variable-distance runs", function()
    for start = 100, 3000, 137 do
        for _, target in ipairs({0, 97, 800, 3011}) do
            local f = fixture(start); f:run(target, 299)
            eq(f.n.status, "reached"); eq(f.n.current, target)
            for _, action in ipairs(f.requests) do
                assert(action ~= "previous_round" and action ~= "next_round")
            end
        end
    end
end)

test("191 opening frame is an absolute clock not a target offset", function()
    local f = fixture(191); f:run(1000, 299)
    eq(f.n.status, "reached"); eq(f.n.current, 1000); assert(#f.requests <= 14)
    local b = fixture(1000); b:run(191, 299)
    eq(b.n.status, "reached"); eq(b.n.current, 191); assert(#b.requests <= 14)
end)

test("nearer large landing avoids a long medium-only tail", function()
    local f = fixture(789); f:run(1000, 299)
    eq(f.requests[1], "forward"); eq(f.n.current, 1000); eq(#f.requests, 12)
end)

test("opening panel after confirmed final step keeps reached status", function()
    local f = fixture(); f.n:start(101); f.overlay = false; f:tick()
    f.overlay = true; f:complete(1)
    eq(f.n.status, "reached"); eq(f.n.current, 101)
end)

test("fast profiles retain final three-render validation", function()
    for _, stable in ipairs({1, 2}) do
        local f = fixture(); f.n:start(101, stable); f.overlay = false; f:tick()
        eq(f.c.pending.stable_frames, stable); f:complete(1)
        eq(f.n.status, "settling"); eq(f.n.active, true)
        f:tick(); f:tick(); eq(f.n.active, true)
        f:tick(); eq(f.n.status, "reached"); eq(#f.requests, 1)
    end
end)

test("late drift at final target stops rather than reporting success", function()
    local f = fixture(); f.n:start(101, 1); f.overlay = false; f:tick(); f:complete(1)
    f.c.snapshot.position.frame = 102; f:tick()
    eq(f.n.reason, "position_changed"); eq(f.reported.status, "stopped")
end)

test("run speed is frozen and invalid profile never claims controls", function()
    local f = fixture(); eq(f.n:start(200, 0), false); eq(f.c.owner, nil)
    f.n:start(116, 2); f.overlay = false; f:tick(); eq(f.n:start(300, 1), false)
    f:complete(8); eq(f.c.pending.stable_frames, 2)
end)

test("elapsed comparison excludes time waiting for panel closure", function()
    local f = fixture(); f.n:start(101); for _ = 1, 120 do f:tick() end
    f.overlay = false; f:tick(); f:complete(1)
    assert(math.abs(f.n.elapsed - 1/60) < 0.00001)
    eq(f.reported.render_ticks, 1); eq(f.reported.start_frame, 100)
    eq(f.reported.current, 101); eq(f.reported.stable_frames, 3)
end)

test("recent result history is bounded and includes failures", function()
    local f = fixture()
    for _ = 1, 15 do
        f.n:start(f.c.clock.position.frame + 1); f.overlay = false; f:tick(); f:complete(1)
    end
    eq(#f.n.history, 12); eq(f.n.history[1].current, 115)
    f.n:start(116); f:tick(); f:complete(0, "not_confirmed")
    eq(#f.n.history, 12); eq(f.n.history[1].status, "stopped")
end)

test("duration selection is frozen per run and rejects unbounded values", function()
    local f = fixture(); eq(f.n:start(116, 1, 1), false); eq(f.c.owner, nil)
    eq(f.n:start(116, 1, 20), true); f.overlay = false; f:tick()
    eq(f.c.pending.press_ms, 20); eq(f.n:start(116, 1, 12), false)
    f:complete(8); eq(f.c.pending.press_ms, 20)
    f:complete(8); f:tick(); f:tick(); f:tick()
    eq(f.n.history[1].press_ms, 20); eq(f.n.history[1].held_samples, 0)
end)
print(count .. " CFN navigation tests passed")
