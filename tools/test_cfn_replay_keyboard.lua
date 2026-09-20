package.path = "tools/cfn_replay_capture/?.lua;" .. package.path
local Bindings, Keyboard, Sampler = require("keybindings"), require("keyboard"), require("sampler")
local count = 0
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function test(name, fn) fn(); count = count + 1; print("PASS " .. name) end
test("standalone review hands input back before any keyboard request", function()
    local main,review=false,true
    local k=Keyboard.new({reframework={is_drawing_ui=function() return main end},
        review_input_blocked=function() return review end})
    eq(k:overlay_open(),true)
    review=false; eq(k:overlay_open(),false)
    main=true; eq(k:overlay_open(),true)
end)
test("accepted review handoff closes overlay once and waits for key release",function()
    local main,now,writes=true,100,0
    local files={["cfn-keyboard-ready.json"]={token="t",protocol=1,updated_at=100,hide_overlay=true}}
    local k=Keyboard.new({reframework={is_drawing_ui=function() return main end},time=function() return now end,
        date=function() return "test" end,json={load_file=function(path) return files[path] end,
        dump_file=function(path,value) writes=writes+1; files[path]=value; return true end}})
    eq(k:hide_overlay(),true); eq(writes,1); eq(files["cfn-keyboard-request.json"].action,"hide_overlay")
    eq(files["cfn-keyboard-request.json"].key,nil); eq(k:hide_overlay(),false)
    main=false; eq(k:overlay_open(),true)
    local r=k.hide_request; files["cfn-keyboard-response.json"]={token="t",id=r.id,status="sent"}
    eq(k:overlay_open(),false); eq(k.hide_request,nil)
    eq(k:hide_overlay(),true); eq(writes,1)
    main=true; files["cfn-keyboard-ready.json"].hide_overlay=nil
    eq(k:hide_overlay(),false); eq(writes,1); eq(k.hide_error,"keyboard_unavailable")
    files["cfn-keyboard-ready.json"].hide_overlay=true
    eq(k:hide_overlay(),true); now=104; eq(k:overlay_open(),true); eq(k.hide_error,"expired"); eq(writes,2)
end)
local function binding_fixture()
    local f = { properties = { KeyboardKey = 67, KeyboardKey2 = 0, KeyboardFunctionKeyRequired = false }, calls = {} }
    local function object(properties)
        return { get_type_definition = function() return {
            get_field = function(_, name) return not f.getters and properties[name] ~= nil end,
            get_method = function(_, name) return f.getters and properties[name:sub(5)] ~= nil end,
        } end, get_field = function(_, name) return properties[name] end,
            call = function(_, name) return properties[name:sub(5)] end }
    end
    local input = { get_method = function(_, signature)
        -- TDB prototypes use comma + space; RETypeDefinition::get_method matches exactly.
        local signatures = {
            ["GetSettingParam(app.InputAssign.Digital.Id)"] = true,
            ["GetKeyboardMousePlayerIndex()"] = true,
            ["GetPlayerDeviceIndex(System.Int32)"] = true,
            ["GetConfigParam(app.InputAssign.Digital.ConfigId, System.Int32)"] = true,
        }
        if not signatures[signature] then return nil end
        return { call = function(_, receiver, ...)
            eq(receiver, nil); f.calls[#f.calls + 1] = { signature, ... }
            if signature == "GetSettingParam(app.InputAssign.Digital.Id)" then return object({ConfigId = 404}) end
            if signature == "GetKeyboardMousePlayerIndex()" then return 1 end
            if signature == "GetPlayerDeviceIndex(System.Int32)" then return 2 end
            if signature == "GetConfigParam(app.InputAssign.Digital.ConfigId, System.Int32)" then return object(f.properties) end
            error("Unexpected input API")
        end }
    end }
    local sdk = { find_type_definition = function(name)
        if f.missing then return nil end
        if name == "app.InputManager" then return input end
        eq(name, "app.esports.ReplayUICtrl.EActiveShortcutType")
        return { get_field = function(_, shortcut)
            f.shortcut = shortcut; return { get_data = function() return 71 end }
        end }
    end }
    f.ui = { get_field = function(_, name)
        eq(name, "_ShortCutActionDict")
        return { call = function(_, method, value)
            eq(method, "get_Item"); eq(value, 71); return object({InputId = 303})
        end }
    end }
    f.resolver = Bindings.new(sdk)
    return f
end
test("game shortcut resolves current configured key and device", function()
    local f = binding_fixture(); local b = assert(f.resolver:resolve(f.ui, "forward"))
    eq(b.key, 67); eq(b.source, "game"); eq(b.input_id, 303); eq(f.shortcut, "ROLL_FORWARD")
    eq(f.calls[1][2], 303); eq(f.calls[3][2], 1); eq(f.calls[4][2], 404); eq(f.calls[4][3], 2)
end)
test("remapping is read again for each command", function()
    local f = binding_fixture(); eq(f.resolver:resolve(f.ui, "forward").key, 67)
    f.properties.KeyboardKey = 75; eq(f.resolver:resolve(f.ui, "forward").key, 75)
end)

test("medium actions resolve game fast-forward and rewind shortcuts", function()
    for action, shortcut in pairs({medium_forward = "FAST_FORWARD", medium_back = "REWIND"}) do
        local f = binding_fixture(); f.properties.KeyboardKey = 69
        eq(f.resolver:resolve(f.ui, action).key, 69); eq(f.shortcut, shortcut)
        f.properties.KeyboardKey = 81
        eq(f.resolver:resolve(f.ui, action).key, 81)
    end
end)
test("property getters and second-only keyboard bindings are supported", function()
    local f = binding_fixture(); f.getters = true
    f.properties.KeyboardKey, f.properties.KeyboardKey2 = 0, 90
    eq(f.resolver:resolve(f.ui, "rewind").key, 90)
end)
test("missing game metadata does not guess defaults", function()
    local f = binding_fixture(); f.missing = true
    local b, reason, detail = f.resolver:resolve(f.ui, "forward")
    eq(b, nil); eq(reason, "key_unavailable"); assert(type(detail) == "string")
end)
test("ambiguous bindings modifiers and mouse keys fail closed", function()
    for _, spec in ipairs({ {KeyboardKey2 = 90}, {KeyboardFunctionKeyRequired = true}, {KeyboardKey = 1} }) do
        local f = binding_fixture(); for k, v in pairs(spec) do f.properties[k] = v end
        eq(f.resolver:resolve(f.ui, "forward"), nil)
    end
end)
test("manual key wins without querying unavailable game metadata", function()
    local f = binding_fixture(); f.missing = true; f.resolver.overrides.forward = " k "
    local b = assert(f.resolver:resolve(f.ui, "forward")); eq(b.key, 75); eq(b.source, "manual")
    eq(#f.calls, 0)
end)
test("invalid manual key never falls back silently", function()
    local f = binding_fixture(); f.resolver.overrides.forward = "CTRL+C"
    eq(f.resolver:resolve(f.ui, "forward"), nil); eq(#f.calls, 0)
end)
test("supported keys are bounded and explicit", function()
    eq(Bindings.parse("F24"), 0x87); eq(Bindings.parse("LEFT"), 0x25)
    eq(Bindings.parse("F25"), nil); eq(Bindings.parse(""), nil)
    for _, key in ipairs({1, 0x10, 0x11, 0x12, 0x3a, 0x40, 0x5b, 0x88, 67.5}) do eq(Bindings.allowed(key), false) end
    eq(Bindings.allowed(67), true); eq(Bindings.allowed(90), true)
end)
local function transport_fixture()
    local f = { now=1000, files = { ["cfn-keyboard-ready.json"] = {protocol = 1, token = "current", updated_at=1000} }, writes = {} }
    f.k = Keyboard.new({ date = function() return "20260920" end, time=function() return f.now end,
        reframework = { is_drawing_ui = function() return f.overlay or false end },
        json = { load_file = function(name) return f.files[name] end,
            dump_file = function(name, value)
                f.writes[#f.writes + 1] = name
                if f.fail then return false end
                f.files[name] = value; return true
            end } })
    return f
end
test("transport requires current helper handshake", function()
    local f = transport_fixture(); f.files["cfn-keyboard-ready.json"] = nil
    local request, reason = f.k:send(67); eq(request, nil); eq(reason, "keyboard_unavailable"); eq(#f.writes, 0)
end)
test("each request is unique and writes only once", function()
    local f = transport_fixture(); local a = assert(f.k:send(67)); local b = assert(f.k:send(90))
    assert(a.id ~= b.id); eq(a.token, "current"); eq(b.key, 90); eq(#f.writes, 2)
    f.k:poll(b); f.k:poll(b); eq(#f.writes, 2)
end)
test("stale and mismatched acknowledgements are ignored", function()
    local f = transport_fixture(); local r = assert(f.k:send(67))
    f.files["cfn-keyboard-response.json"] = {token = "old", id = r.id, status = "sent"}; eq(f.k:poll(r), nil)
    f.files["cfn-keyboard-response.json"] = {token = r.token, id = "old", status = "sent"}; eq(f.k:poll(r), nil)
    f.files["cfn-keyboard-response.json"] = {token = r.token, id = r.id, status = "focus_lost"}; eq(f.k:poll(r), "focus_lost")
end)
test("failed write returns no ticket", function()
    local f = transport_fixture(); f.fail = true
    local r, reason = f.k:send(67); eq(r, nil); eq(reason, "send_failed")
end)
test("cancellation identifies only its own request", function()
    local f = transport_fixture(); local r = assert(f.k:send(67)); f.k:cancel(r)
    local cancel = f.files["cfn-keyboard-cancel.json"]; eq(cancel.token, r.token); eq(cancel.id, r.id)
end)
test("overlay state comes from framework getter", function()
    local f = transport_fixture(); eq(f.k:overlay_open(), false); f.overlay = true; eq(f.k:overlay_open(), true)
end)
local sampler = Sampler.new({find_type_definition = function() return {get_field = function() return {} end} end})
local function position(rounds, frame)
    local n = 0
    return sampler:position({replay = {call = function(_, method)
        if method == "get_ReplayTime" then return frame end
        n = n + 1; return rounds[n]
    end}})
end
test("position uses replay clocks and zero based round", function()
    local p = position({0, 0}, 1813); eq(p.round, 0); eq(p.frame, 1813)
end)
test("round change during position read is rejected", function() eq(position({0, 1}, 1813), nil) end)
test("invalid position never becomes zero", function()
    for _, frame in ipairs({-1, 1.5, math.huge, false}) do eq(position({0, 0}, frame), nil) end
    eq(position({-1, -1}, 10), nil); eq(position({0, 0}, nil), nil)
end)
test("position read exceptions remain unavailable", function()
    eq(sampler:position({replay = {call = function() error("gone") end}}), nil)
end)
test("manual default retains original45ms press with healthy helper", function()
    local f = transport_fixture(); eq(f.k:send(67).press_ms, 45)
end)
test("experimental press duration requires explicit helper capability", function()
    local f = transport_fixture(); local r, reason = f.k:send(67, 30)
    eq(r, nil); eq(reason, "press_unavailable"); eq(#f.writes, 0)
    f.files["cfn-keyboard-ready.json"].press_ms_options = {45,30,20,12}
    for _, ms in ipairs({45,30,20,12}) do eq(f.k:send(67, ms).press_ms, ms) end
end)
test("press duration is bounded before any transport write", function()
    local f = transport_fixture()
    for _, ms in ipairs({0, -1, 1, 13, 1000, 20.5, "20"}) do
        eq(f.k:send(67, ms), nil)
    end
    eq(#f.writes, 0)
end)
test("receipt must acknowledge the requested experimental press duration", function()
    local f = transport_fixture(); f.files["cfn-keyboard-ready.json"].press_ms_options = {20}
    local r = assert(f.k:send(67, 20))
    f.files["cfn-keyboard-response.json"] = {token=r.token, id=r.id, status="sent", press_ms=45}
    eq(f.k:poll(r), "press_unavailable")
    f.files["cfn-keyboard-response.json"].press_ms = 20
    f.files["cfn-keyboard-response.json"].held_ms = 21.7
    local status, detail = f.k:poll(r); eq(status, "sent"); eq(detail.held_ms, 21.7)
end)
test("dead helper heartbeat refuses commands without writing a request",function()
    for _,stamp in ipairs({993,1002,false,"1000",0/0}) do
        local f=transport_fixture(); f.files["cfn-keyboard-ready.json"].updated_at=stamp
        local r,reason=f.k:send(67); eq(r,nil); eq(reason,"keyboard_unavailable"); eq(#f.writes,0)
    end
    local f=transport_fixture(); f.files["cfn-keyboard-ready.json"].updated_at=nil
    eq(f.k:send(67),nil); eq(#f.writes,0)
end)
test("helper death or restart while awaiting reply fails without retrying",function()
    for _,mode in ipairs({"dead","restart"}) do
        local f=transport_fixture(); local r=assert(f.k:send(67))
        if mode=="dead" then f.now=1008 else f.files["cfn-keyboard-ready.json"].token="new" end
        eq(f.k:poll(r),"keyboard_unavailable"); eq(#f.writes,1)
    end
end)
test("a confirmed release remains valid even after heartbeat disappears",function()
    local f=transport_fixture(); local r=assert(f.k:send(67))
    f.files["cfn-keyboard-response.json"]={token=r.token,id=r.id,status="sent",press_ms=45}
    f.files["cfn-keyboard-ready.json"]=nil
    eq(f.k:poll(r),"sent")
end)
test("owned handoff restores overlay once after work and key release",function()
    local f=transport_fixture(); f.overlay=true
    f.files["cfn-keyboard-ready.json"].hide_overlay=true
    f.files["cfn-keyboard-ready.json"].restore_overlay=true
    assert(f.k:hide_overlay())
    local r=f.files["cfn-keyboard-request.json"]
    f.k:update_handoff(false); eq(#f.writes,1)
    f.overlay=false
    f.files["cfn-keyboard-response.json"]={token=r.token,id=r.id,status="sent"}
    f.k:update_handoff(true); eq(#f.writes,1)
    f.k:update_handoff(false)
    local restore=f.files["cfn-keyboard-request.json"]; eq(restore.action,"show_overlay")
    f.k:update_handoff(false); eq(#f.writes,2)
    f.overlay=true
    f.files["cfn-keyboard-response.json"]={token=restore.token,id=restore.id,status="sent"}
    f.k:update_handoff(false); f.k:update_handoff(false); eq(#f.writes,2)
end)
test("manual reopening and initially hidden UI are never toggled",function()
    local f=transport_fixture(); assert(f.k:hide_overlay()); f.k:update_handoff(false); eq(#f.writes,0)
    f.overlay=true; f.files["cfn-keyboard-ready.json"].hide_overlay=true
    f.files["cfn-keyboard-ready.json"].restore_overlay=true
    assert(f.k:hide_overlay()); local r=f.files["cfn-keyboard-request.json"]
    f.files["cfn-keyboard-response.json"]={token=r.token,id=r.id,status="sent"}
    f.k:update_handoff(false); eq(#f.writes,1)
end)
test("reset and failed hide do not reopen menus later",function()
    for _,reset in ipairs({false,true}) do
        local f=transport_fixture(); f.overlay=true
        f.files["cfn-keyboard-ready.json"].hide_overlay=true
        f.files["cfn-keyboard-ready.json"].restore_overlay=true
        assert(f.k:hide_overlay()); local r=f.files["cfn-keyboard-request.json"]
        if reset then f.k:cancel_handoff() else f.files["cfn-keyboard-response.json"]={token=r.token,id=r.id,status="focus_lost"} end
        f.overlay=false; f.k:update_handoff(false)
        eq(#f.writes,reset and 2 or 1)
    end
end)
test("restoration waits for final gameplay release and does not retry a failed show",function()
    local f=transport_fixture(); f.overlay=true
    f.files["cfn-keyboard-ready.json"].hide_overlay=true
    f.files["cfn-keyboard-ready.json"].restore_overlay=true
    assert(f.k:hide_overlay()); local h=f.k.hide_request; f.overlay=false
    f.files["cfn-keyboard-response.json"]={token=h.token,id=h.id,status="sent"}
    f.k:update_handoff(true)
    local r=assert(f.k:send(67))
    f.k:update_handoff(false); eq(#f.writes,2)
    f.files["cfn-keyboard-response.json"]={token=r.token,id=r.id,status="cancelled"}
    f.k:update_handoff(false); eq(#f.writes,3)
    local restore=f.k.restore_request
    f.files["cfn-keyboard-response.json"]={token=restore.token,id=restore.id,status="focus_lost"}
    f.k:update_handoff(false); f.k:update_handoff(false); eq(#f.writes,3); eq(f.k.restore_error,"focus_lost")
end)
test("next no-op navigation does not wait for a previous request overwritten by hide",function()
    local f=transport_fixture(); f.k:send(67); f.overlay=true
    f.files["cfn-keyboard-ready.json"].hide_overlay=true
    f.files["cfn-keyboard-ready.json"].restore_overlay=true
    assert(f.k:hide_overlay()); local h=f.k.hide_request; f.overlay=false
    f.files["cfn-keyboard-response.json"]={token=h.token,id=h.id,status="sent"}
    f.k:update_handoff(false); eq(f.k.restore_request.action,"show_overlay")
end)
print(count .. " CFN keyboard tests passed")
