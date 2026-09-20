local count = 0
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn) fn(); count = count + 1; print("PASS " .. name) end
local function fixture(fail_navigation)
    local f = {buttons = {}, texts = {}, requested = {}, previews = 0, depth = 0, combos={}, trees={}}
    local state = {render_tick = 0, status = "ready", request_preview = function() f.previews = f.previews + 1 end}
    local controls = {status="ready", request = function(_, action) f.requested[#f.requested+1] = action end}
    f.controls=controls
    local navigation = {status="idle", start = function(_, target, stable_frames, press_ms)
        f.target, f.stable_frames, f.press_ms = target, stable_frames, press_ms end,
        cancel = function(self) self.active = false; f.cancelled = true end}
    f.navigation = navigation
    local analysis = {status="idle", items={}, start=function() f.analysis_started=true; return true end,
        load_saved=function() f.saved_loaded=true; return true end,
        cancel=function() f.analysis_cancelled=true end, locate=function(_, item) f.located=item end}
    f.analysis = analysis
    f.state=state
    f.popups={visible=false,any_visible=function(self) return self.visible end,
        draw=function(_,_,_,_,_,_,_,callbacks) f.statistics_drawn=(f.statistics_drawn or 0)+1;f.statistics_callbacks=callbacks end}
    f.review={visible=true,model={update=function() end},draw=function() f.review_drawn=(f.review_drawn or 0)+1 end}
    local modules = {
        schema = {}, session = {}, sampler = {new = function() return {} end},
        runtime = {attach = function() return state end}, presentation = {},
        controls = {attach = function() return controls end}, keyboard = {new = function() return {update_handoff=function(_,busy) f.handoff_busy=busy end} end, press_ms_options = {45,30,20,12}},
        keybindings = {new = function() return {overrides = {}} end},
        navigation = {attach = function() if fail_navigation then error("test failure") end; return navigation end},
        round_navigation = {attach = function() return {} end},
        candidates = {}, match_review = {}, saved_capture = {}, replay_speed = {new=function() return {} end}, analysis = {attach=function() return analysis end},
        review_panel = dofile("tools/cfn_replay_capture/review_panel.lua"),
        damage_review = {}, damage_rules = {}, rule_config={},rule_context={},workbench={},rule_evaluation={},review_assessments = {}, statistics={}, statistics_window={new=function() return {} end}, review_model = {new=function() return {} end},
        guard_review={},guard_window={new=function() return {} end},statistics_popups={new=function() return f.popups end},
        review_window = {new=function() return f.review end,surface_size=function() return 1920,1080 end},
    }
    local imgui = {
        tree_node = function(name)
            f.trees[name]=true
            local opened = not f.collapsed and not name:find("按键设置", 1, true)
            if opened then f.depth = f.depth + 1 end
            return opened
        end,
        tree_pop = function() f.depth = f.depth - 1; assert(f.depth >= 0, "Unexpected TreePop") end,
        separator = function() end, same_line = function() end,
        text = function(value) f.texts[#f.texts+1] = value end,
        checkbox = function(_, value) if f.live_off then return true, false end; return false, value end,
        -- REFramework exposes input_text; do not invent imgui.input_int in the fixture.
        input_text = function(_, value) return f.input ~= nil, f.input ~= nil and tostring(f.input) or value end,
        combo = function(label, value)
            f.combos[label]=true
            if label == "定位速度" and f.speed then return true, f.speed end
            if label == "按键时长" and f.press then return true, f.press end
            return false, value
        end,
        button = function(label) f.buttons[label] = true; return f.click == label end,
        load_font=function() return nil end,
    }
    local env = setmetatable({
        require = function(path) return assert(modules[path:match("([^/]+)$")]) end,
        re = {on_draw_ui = function(fn) f.draw = fn end, on_frame=function(fn) f.frame=fn end,
            on_script_reset=function() end}, imgui = imgui,
        json = {load_file = function() return {} end}, log = {error = function() end},
        Vector2f={new=function(x,y) return {x=x,y=y} end},
    }, {__index = _G})
    env._G = env
    assert(loadfile("tools/cfn_replay_capture/CFN_ReplayCapture.lua", "t", env))()
    local draw = f.draw
    function f.draw() draw(); eq(f.depth, 0) end
    return f
end

test("handoff completion runs even when no live review window can draw",function()
    local f=fixture(); f.frame(); eq(f.handoff_busy,false)
    f.navigation.active=true; f.frame(); eq(f.handoff_busy,true)
    f.navigation.active=false; f.controls.awaiting={}; f.frame(); eq(f.handoff_busy,true)
    f.controls.awaiting=nil; f.frame(); eq(f.handoff_busy,false)
end)

test("statistics remain drawable with bottom review hidden and opening never sends input",function()
    local f=fixture();f.state.alive=true;f.review.visible=false;f.popups.visible=true
    f.frame();eq(f.statistics_drawn,1);eq(#f.requested,0)
    f.popups.visible=false;f.frame();eq(f.statistics_drawn,1)
    f.popups.visible=true;f.state.alive=false;f.frame();eq(f.statistics_drawn,1)
end)

test("both medium buttons dispatch distinct actions", function()
    local f = fixture(); f.click = "中步前进"; f.draw(); eq(f.requested[1], "medium_forward")
    f.click = "中步后退"; f.draw(); eq(f.requested[2], "medium_back")
end)
test("frame input starts same-round navigator without direct control", function()
    local f = fixture(); f.input = 1234; f.click = "定位到此帧"; f.draw()
    eq(f.target, 1234); eq(#f.requested, 0)
end)
test("cancel button reaches navigator", function()
    local f = fixture(); f.click = "取消定位"; f.draw(); eq(f.cancelled, true)
end)
test("drawing a collapsed panel leaves cancellation and completion to navigator", function()
    local f = fixture(); f.navigation.active, f.navigation.started = true, true
    f.collapsed = true; f.draw(); eq(f.cancelled, nil); eq(#f.requested, 0)
end)
test("clock preview remains available with player information switched off", function()
    local f = fixture(); f.live_off = true; f.draw(); eq(f.previews, 2)
end)
test("navigation setup failure leaves ordinary control available", function()
    local f = fixture(true); f.click = "中步前进"; f.draw(); eq(f.requested[1], "medium_forward")
    eq(f.buttons["定位到此帧"], nil)
end)

test("text frame input preserves edits across draws and accepts zero", function()
    local f = fixture(); f.input = " 1234 "; f.draw()
    f.input = nil; f.click = "定位到此帧"; f.draw(); eq(f.target, 1234)
    f.input = "0"; f.draw(); eq(f.target, 0)
end)

test("invalid text never reuses the previous target or truncates a fraction", function()
    for _, value in ipairs({"", " ", "-1", "1.5", "1e3", "0x10", "abc", "12帧"}) do
        local f = fixture(); f.input = "1000"; f.click = "定位到此帧"; f.draw(); eq(f.target, 1000)
        f.input = value; f.draw(); eq(f.target, nil); eq(#f.requested, 0)
    end
end)
test("navigation uses the user-selected fixed fastest profile without trial selectors", function()
    local f = fixture(); f.input = "1000"; f.click = "定位到此帧"
    f.draw(); eq(f.stable_frames,1); eq(f.press_ms,45)
    eq(f.combos["定位速度"],nil); eq(f.combos["按键时长"],nil)
end)
test("current elapsed time remains but historical comparison panel is removed", function()
    local f = fixture(); f.navigation.elapsed, f.navigation.steps = 1.25, 14
    f.navigation.history = {{stable_frames=1, start_frame=191, target=1000, seconds=1.25, presses=14, status="reached"}}
    f.draw(); assert(table.concat(f.texts, "\n"):find("1.25秒", 1, true))
    eq(f.trees["最近定位结果"],nil)
end)
test("obsolete selector values cannot override the fixed profile", function()
    local f = fixture(); f.input = "1000"; f.click = "定位到此帧"; f.speed = 3
    for i=1,4 do
        f.press = i; f.draw(); eq(f.press_ms,45); eq(f.stable_frames,1)
    end
end)
test("match analysis button and round-labelled candidate selection use isolated controller", function()
    local f=fixture(); f.click="分析整场录像"; f.draw(); eq(f.analysis_started,true)
    f.analysis.items={{round=1,frame=500,defender=1,frames=5,kind="five_plus_punish_candidate"}}
    f.analysis.status="ready"
    f.click="第2局  500帧  1P防守后  5帧以上 / 待核对##cfn_candidate_1"; f.draw()
    eq(f.located,f.analysis.items[1]); eq(#f.requested,0)
    f.click="停止分析"; f.draw(); eq(f.analysis_cancelled,true)
end)
test("native speed result has no keyboard key and renders without error",function()
    local f=fixture(); f.controls.last_result={before={round=0,frame=191},after={round=0,frame=191},
        before_speed=1,after_speed=8,source="native_speed"}
    f.draw(); assert(table.concat(f.texts,"\n"):find("速度：1.0倍 → 8.0倍",1,true))
    eq(f.combos["手动记录标记（不调速）"],true)
end)
test("match summary never merges frame ranges from different rounds",function()
    local f=fixture(); f.analysis.status="ready"; f.analysis.reason="replay_end"
    f.analysis.capture={samples={1,2,3}}; f.analysis.saved=true
    f.analysis.review={coverage_ok=false,rounds={{round=0,first_frame=192,last_frame=3412,finish_frame=3412},
        {round=1,first_frame=1,last_frame=50}}}
    f.draw(); local text=table.concat(f.texts,"\n")
    assert(text:find("第1局：192～3412帧",1,true)); assert(text:find("第2局：1～50帧",1,true))
    assert(text:find("未通过完整性检查",1,true)); eq(f.buttons["分析本局录像"],nil)
end)
test("candidate panel reports a stopped navigator rather than silently ignoring helper failure",function()
    local texts={}
    assert(loadfile("tools/cfn_replay_capture/review_panel.lua"))().new()({tree_node=function() return true end,tree_pop=function() end,
        button=function() return false end,same_line=function() end,text=function(s) texts[#texts+1]=s end},
        {status="ready",items={}},{},{status="stopped",reason="keyboard_unavailable"},1,45,
        {keyboard_unavailable="按键控制暂不可用"})
    assert(table.concat(texts,"\n"):find("定位已停止：按键控制暂不可用",1,true))
end)
test("load saved analysis is a separate read-only button",function()
    local f=fixture(); f.click="读取上次分析"; f.draw()
    eq(f.saved_loaded,true); eq(f.analysis_started,nil); eq(#f.requested,0)
end)
print(count .. " CFN UI tests passed")
