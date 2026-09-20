package.path = "tools/cfn_replay_capture/?.lua;" .. package.path
local Schema = require("schema")
local Sessions = require("session")
local Sampler = require("sampler")
local Runtime = require("runtime")
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
    print("PASS " .. name)
end
local function eq(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local metadata = { replay_id = "TEST", version = 1 }
local function values(frame, round, tick)
    return { round = round or 0, replay_frame = frame, stage_frame = frame,
        battle_round = round or 0, thread_id = 17, render_tick = tick or frame }
end

test("eight updates per render are retained", function()
    local s = Sessions.new(Schema)
    for frame = 0, 799 do assert(s:add(metadata, values(frame, 0, math.floor(frame / 8)))) end
    eq(#s.samples, 800); eq(s.render_tick_max_samples, 8); eq(next(s.issue_counts), nil)
    eq(s.full_replay_verified, false)
end)
test("pause duplicates retain potentially different states", function()
    local s = Sessions.new(Schema)
    local v = values(10); v["p1.vital_new"] = 100
    s:add(metadata, v); v["p1.vital_new"] = 99; s:add(metadata, v)
    eq(s.duplicate_clocks, 1); eq(#s.samples, 2)
    eq(s.samples[1][Schema.index["p1.vital_new"]], 100)
end)
test("clocks remain independent", function()
    local s = Sessions.new(Schema)
    local v = values(10); v.stage_frame = 20; v.display_prev_frame = 15
    s:add(metadata, v)
    eq(s.samples[1][Schema.index.stage_frame], 20)
    eq(s.samples[1][Schema.index.display_prev_frame], 15)
end)
test("gap detection does not synthesize rows", function()
    local s = Sessions.new(Schema)
    s:add(metadata, values(0)); s:add(metadata, values(8))
    eq(#s.samples, 2); eq(s.issue_counts.replay_clock_gap, 1); eq(s.issue_counts.stage_clock_gap, 1)
end)
test("rewinds and round gaps are explicit", function()
    local s = Sessions.new(Schema)
    s:add(metadata, values(10)); s:add(metadata, values(9)); s:add(metadata, values(0, 1)); s:add(metadata, values(0, 3))
    eq(s.issue_counts.rewind_or_reset, 1); eq(s.issue_counts.round_gap, 1)
end)
test("round transition is not a negative frame gap", function()
    local s = Sessions.new(Schema)
    s:add(metadata, values(999)); s:add(metadata, values(0, 1))
    eq(next(s.issue_counts), nil)
end)
test("partial start is identified without claiming completeness", function()
    local s = Sessions.new(Schema)
    s:add(metadata, values(250, 2)); s:stop("manual")
    local out = s:export()
    eq(out.first_clock.round, 2); eq(out.first_clock.replay_frame, 250)
    eq(out.full_replay_verified, false); eq(out.sample_count, 1); eq(out.add, nil)
end)
test("missing optional values keep dense rows", function()
    local s = Sessions.new(Schema); s:add(metadata, values(1))
    eq(#s.samples[1], #Schema.columns); eq(s.missing_columns["p2.action_id"], 1)
    eq(s.samples[1][Schema.index["p2.action_id"]], false)
end)
test("invalid required clocks stop", function()
    for _, bad in ipairs({ false, -1, 0.5, "1", math.huge, 0/0 }) do
        local s = Sessions.new(Schema); local v = values(0); v.stage_frame = bad
        eq(s:add(metadata, v), false); eq(s:is_active(), false); eq(#s.samples, 0)
    end
end)
test("capacity preserves rows and refuses overflow", function()
    local s = Sessions.new(Schema, { limit = 2 })
    s:add(metadata, values(0)); s:add(metadata, values(1)); s:add(metadata, values(2))
    eq(#s.samples, 2); eq(s.stop_reason, "capacity")
end)
test("replay identity cannot mix", function()
    local s = Sessions.new(Schema); s:add(metadata, values(0))
    s:add({ replay_id = "OTHER" }, values(1))
    eq(#s.samples, 1); eq(s.stop_reason, "replay_changed")
end)
test("sequential thread handoff is retained without a false error", function()
    local s = Sessions.new(Schema); s:add(metadata, values(0))
    local v = values(1); v.thread_id = 18; s:add(metadata, v)
    eq(#s.samples, 2); eq(s:is_active(), true)
    eq(s.thread_transition_count, 1); eq(next(s.issue_counts), nil)
end)
test("issue details bounded, counts exact", function()
    local s = Sessions.new(Schema)
    for i = 1, 1000 do s:issue("test", i) end
    eq(#s.issues, 64); eq(s.issue_counts.test, 1000)
end)
test("active export disallowed", function()
    eq(pcall(function() Sessions.new(Schema):export() end), false)
end)
test("export JSON roundtrip preserves raw numbers and missing markers", function()
    local Json = require("tools/training_record_bank/vendor/dkjson")
    local s = Sessions.new(Schema)
    local v = values(1); v["p1.hit_st"] = 2147483648; v["p2.action_frame_raw"] = 808277
    s:add(metadata, v); s:stop("manual")
    local bytes = assert(Json.encode(s:export()))
    local out, _, err = Json.decode(bytes)
    assert(not err); eq(out.samples[1][Schema.index["p1.hit_st"]], 2147483648)
    eq(out.samples[1][Schema.index["p2.action_frame_raw"]], 808277)
    eq(out.samples[1][Schema.index.display_stun_frame], false)
end)

local function native(fields, methods, address)
    local o = { data = fields or {}, methods = methods or {}, address = address or 1 }
    function o:get_field(name) return self.data[name] end
    function o:call(name, ...) return assert(self.methods[name], "unexpected call: " .. name)(...) end
    function o:get_address() return self.address end
    return o
end
local function array(items)
    return { get_element = function(_, index) return items[index + 1] end,
        get_size = function() return #items end }
end
local function fixed(n) return native({ v = n }) end
local function fixture()
    local c = { frame = 1, flow_id = 10 }
    local function player(address)
        local fields = {}
        for _, key in ipairs(Schema.player_columns) do fields[key] = 10 end
        fields.rl_dir = false
        fields.pos = native({ x = fixed(65536), y = fixed(0), z = fixed(-65536) })
        fields.mpActParam = native({ ActionPart = native({ _Engine = native({}, {
            get_ActionID = function() return 42 end, get_ActionFrame = function() return fixed(32768) end,
        }) }) })
        fields.damage_pl_add = nil
        return native(fields, nil, address)
    end
    c.players = { player(111), player(222) }
    c.players[2].data.damage_pl_add = c.players[1]
    local team = native({ mSuperGauge = 10, mSuperGaugeMax = 30000, mSingleDamage = 50, mComboDamage = 50, mComboCount = 1 })
    c.game = native({ stage_timer = 1, fight_st = 2 })
    c.round = native({ RoundNo = 0, play_timer = 99, play_timer_ms = 0 })
    local statics = { Player = native({ mcPlayer = array(c.players) }), Team = native({ mcTeam = array({ team, team }) }), Game = c.game, Round = c.round }
    local replay = native({}, { get_Replay = function() return true end, get_ReplayRound = function() return 0 end, get_ReplayTime = function() return c.frame end })
    local np = native({ player = native({ fighter_id = "test", short_id = 1 }), character_id = 21,
        playing_character_id = 21, battle_input_type = 1, league_rank = 36, league_point = 25000, master_rating = 1500 })
    local item = native({ ReplayID = "TEST", ReplayData = native({ ReplayInfo = native({ Version = 123, RoundNum = 3, StageId = 1, RandomSeed = 55 }) }),
        ReplayInfo = native({ player1_info = np, player2_info = np }) })
    c.manager = native({ _CurrentReplayID = 0, _ReplayList = native({ _items = array({ item }), _size = 1 }),
        ["<BattleCore_>k__BackingField"] = native({ m_BRControl = native({ _BattleReplay = replay }) }) })
    local gtype = { get_field = function(_, name) return { get_data = function() return statics[name] end } end }
    c.api = { find_type_definition = function(name) eq(name, "gBattle"); return gtype end,
        get_managed_singleton = function(name)
            if name == "app.bFlowManager" then return native({ m_flow_work = native({ _FlowMap = native({ _ID = c.flow_id }) }) }) end
            if name == "app.BattleReplayDataManager" then return c.manager end
            if name == "app.training.TrainingManager" then return c.tm end
            error("unexpected singleton " .. name)
        end }
    return c
end
test("native replay list index zero resolves the CFN string identity", function()
    local c = fixture(); c.manager.data._CurrentReplayID = 0
    local s = Sampler.new(c.api)
    local context = s:context()
    assert(context, "valid replay is incorrectly treated as unavailable")
    eq(context.replay_id, "TEST")
    eq(context.version, 123)
    eq(s:metadata(context).replay_id, "TEST")
end)
test("training replay without a proven CFN identity must not borrow previous analysis", function()
    local c = fixture(); c.manager.data.IsTrainingReplay = true
    local item = c.manager.data._ReplayList.data._items:get_element(0)
    item.data.ReplayID = nil; item.data.ReplayInfo.data.replay_id = ""
    local s = Sampler.new(c.api)
    eq(s:context(), nil)
end)

test("local player defaults require unique live signed-in CFN identity",function()
    local c=fixture(); local s=Sampler.new(c.api); local context=s:context()
    local network=context.replaying_data.data.ReplayInfo
    local id,online=2,true
    network.data.player2_info=native({player=native({short_id=2})})
    local singleton=c.api.get_managed_singleton
    c.api.get_managed_singleton=function(name)
        if name=="app.LoginManager" then return {call=function(_,m)
            if m=="get_IsLogin" then return online end
            eq(m,"get_ShortId"); return id
        end} end
        return singleton(name)
    end
    eq(s:local_side(context),2); id=1; eq(s:local_side(context),1)
    id=99; eq(s:local_side(context),nil); id=0; eq(s:local_side(context),nil)
    id=2; online=false; eq(s:local_side(context),nil)
    online=true; network.data.player1_info=network.data.player2_info; eq(s:local_side(context),nil)
end)

test("selected index chooses metadata even when public IDs are duplicated", function()
    local c = fixture(); local list = c.manager.data._ReplayList
    local first = list.data._items:get_element(0)
    local second = native({ ReplayID = "TEST", ReplayInfo = first.data.ReplayInfo,
        ReplayData = native({ ReplayInfo = native({ Version = 456, RoundNum = 2 }) }) })
    list.data._items = array({ first, second }); list.data._size = 2
    c.manager.data._CurrentReplayID = 1
    local s = Sampler.new(c.api); local context = s:context()
    eq(context.replay_list_index, 1); eq(s:metadata(context).version, 456); eq(context.version, 456)
end)

test("live replay identity version never falls back to old metadata", function()
    local c=fixture(); local s=Sampler.new(c.api)
    eq(s:context().version,123)
    local item=c.manager.data._ReplayList.data._items:get_element(0)
    for _,value in ipairs({456,false,-1,1.5}) do
        item.data.ReplayData.data.ReplayInfo.data.Version=value
        eq(s:context().version,value==456 and 456 or nil)
    end
    item.data.ReplayData=nil
    eq(s:context().version,nil); eq(s:context().replay_id,"TEST")
end)

test("invalid or transitioning replay selection never dereferences out of bounds", function()
    local c = fixture(); local s = Sampler.new(c.api)
    local list = c.manager.data._ReplayList
    local original = list.data._items.get_element
    list.data._items.get_element = function() error("must not access invalid selection") end
    for _, index in ipairs({ false, -1, 0.5, 1, "TEST" }) do
        c.manager.data._CurrentReplayID = index; eq(s:context(), nil)
    end
    c.manager.data._CurrentReplayID = 0
    list.data._size = 2; eq(s:context(), nil)
    list.data._size = 0; eq(s:context(), nil)
    list.data._size = 1; list.data._items.get_element = original
    list.data._items:get_element(0).data.ReplayID = ""; eq(s:context(), nil)
    list.data._items = nil; eq(s:context(), nil)
end)
test("selection metadata cannot silently change within one sample", function()
    local c = fixture(); local s = Sampler.new(c.api); local context = s:context()
    context.replaying_data.data.ReplayID = "OTHER"
    eq(pcall(function() s:metadata(context) end), false)
end)
test("sampler reads scalars including zero and false-facing", function()
    local c = fixture(); local s = Sampler.new(c.api); local context = s:context()
    local meta = s:metadata(context); eq(meta.version, 123); eq(meta.players[1].control_mode, 1)
    local row = s:sample(context, 1, 17, 1)
    eq(row["p1.x_raw"], 65536); eq(row["p1.action_frame_raw"], 32768)
    eq(row["p1.facing_right"], 0); eq(row["p2.damage_source"], 1)
    eq(row["p1.damage_source"], 0); eq(row.display_prev_frame, nil)
end)
test("recovery evidence preserves signed counters and false boolean", function()
    local c = fixture(); local s = Sampler.new(c.api)
    c.players[1].data.guard_time = -1
    c.players[1].data.damage_time = 0
    c.players[1].data.pose_st = 2
    c.players[1].data.free_to_move = false
    c.players[2].data.free_to_move = true
    local context = s:context()
    eq(s:metadata(context).recovery_fields_profile, "raw_player_recovery_v1")
    local row = s:sample(context, 1, 17, 1)
    eq(row["p1.guard_time"], -1); eq(row["p1.damage_time"], 0)
    eq(row["p1.pose_st"], 2); eq(row["p1.free_to_move"], 0); eq(row["p2.free_to_move"], 1)
end)

test("unavailable recovery evidence stays missing without losing core sample", function()
    for _, invalid in ipairs({ "absent", "wrong_type", "read_error" }) do
        local c = fixture(); local s = Sampler.new(c.api)
        c.players[1].data.guard_time = nil
        c.players[1].data.damage_time = 0.5
        c.players[1].data.free_to_move = invalid == "wrong_type" and 1 or nil
        if invalid == "read_error" then
            local original = c.players[1].get_field
            c.players[1].get_field = function(self, name)
                if name == "guard_time" or name == "free_to_move" then error("unavailable") end
                return original(self, name)
            end
        end
        local row = s:sample(s:context(), 1, 17, 1)
        eq(row["p1.vital_new"], 10); eq(row["p1.guard_time"], nil)
        eq(row["p1.damage_time"], nil); eq(row["p1.free_to_move"], nil)
        local session = Sessions.new(Schema)
        assert(session:add(s:metadata(s:context()), row))
        session:stop("manual")
        local exported = session:export()
        eq(exported.samples[1][Schema.index["p1.free_to_move"]], false)
        eq(exported.samples[1][Schema.index["p1.guard_time"]], false)
    end
end)

local function engine_of(c, side)
    return c.players[side].data.mpActParam.data.ActionPart.data._Engine
end

local function engine_param()
    return native({ id = 42, frame = fixed(32768), frame_num = fixed(43 * 65536),
        margin_start_frame = fixed(35 * 65536 + 32768), speed = fixed(65536),
        state_flags = 4294967295, battle_version = 20004000, loop_count = 0, style_index = -1 })
end

test("engine evidence reads fields without extra native methods or rounded frames", function()
    local c = fixture(); engine_of(c, 1).data.mParam = engine_param()
    local s = Sampler.new(c.api); local context = s:context()
    eq(s:metadata(context).engine_fields_profile, "raw_engine_param_v1")
    local row = s:sample(context, 1, 17, 1)
    eq(row["p1.engine_action_id"], 42); eq(row["p1.engine_action_frame_raw"], 32768)
    eq(row["p1.engine_frame_num_raw"], 2818048); eq(row["p1.engine_margin_start_raw"], 2326528)
    eq(row["p1.engine_speed_raw"], 65536); eq(row["p1.engine_state_flags"], 4294967295)
    eq(row["p1.engine_battle_version"], 20004000); eq(row["p1.engine_loop_count"], 0)
    eq(row["p1.engine_style_index"], -1); eq(row["p2.engine_action_id"], nil)
end)

test("absent engine evidence exports unavailable, not a zero recovery time", function()
    local c = fixture(); local s = Sampler.new(c.api); local context = s:context()
    local row = s:sample(context, 1, 17, 1)
    local session = Sessions.new(Schema); assert(session:add(s:metadata(context), row)); session:stop("manual")
    local out = session:export()
    for _, name in ipairs(Schema.player_columns) do
        if name:match("^engine_") then eq(out.samples[1][Schema.index["p1." .. name]], false) end
    end
    eq(row["p1.action_id"], 42)
end)

test("engine evidence exception discards the block but not the core or other player", function()
    local c = fixture(); local param = engine_param()
    param.get_field = function(self, name)
        if name == "state_flags" then error("native field unavailable") end
        return self.data[name]
    end
    engine_of(c, 1).data.mParam = param; engine_of(c, 2).data.mParam = engine_param()
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row["p1.action_id"], 42); eq(row["p1.engine_action_id"], nil)
    eq(row["p1.engine_margin_start_raw"], nil); eq(row["p2.engine_margin_start_raw"], 2326528)
end)

test("engine evidence never carries values from an earlier sample", function()
    local c = fixture(); local engine = engine_of(c, 1)
    engine.data.mParam = engine_param(); local s = Sampler.new(c.api)
    eq(s:sample(s:context(), 1, 17, 1)["p1.engine_action_id"], 42)
    engine.data.mParam = nil
    eq(s:sample(s:context(), 2, 17, 1)["p1.engine_action_id"], nil)
    local replacement = engine_param(); replacement.data.id = 99
    replacement.data.margin_start_frame = fixed(0); engine.data.mParam = replacement
    local row = s:sample(s:context(), 3, 17, 1)
    eq(row["p1.engine_action_id"], 99); eq(row["p1.action_id"], 42)
    eq(row["p1.engine_margin_start_raw"], 0)
end)

test("invalid engine scalars remain unavailable while valid evidence survives", function()
    local c = fixture(); local param = engine_param(); engine_of(c, 1).data.mParam = param
    param.data.frame_num = fixed(0.5); param.data.margin_start_frame = fixed(math.huge)
    param.data.loop_count = 0.5; param.data.state_flags = 9007199254740992
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row["p1.engine_frame_num_raw"], nil); eq(row["p1.engine_margin_start_raw"], nil)
    eq(row["p1.engine_loop_count"], nil); eq(row["p1.engine_state_flags"], nil)
    eq(row["p1.engine_speed_raw"], 65536)
end)

test("sampler reacquires players and metadata on each request", function()
    local c = fixture(); local s = Sampler.new(c.api)
    s:sample(s:context(), 1, 17, 1)
    c.players[1] = fixture().players[1]; c.players[1].data.vital_new = 55
    eq(s:sample(s:context(), 2, 17, 1)["p1.vital_new"], 55)
    c.manager.data._ReplayList.data._items:get_element(0).data.ReplayID = "OTHER"
    eq(s:context().replay_id, "OTHER")
end)
test("sampler refuses non-replay flow", function()
    local c = fixture(); local s = Sampler.new(c.api)
    for _, flow in ipairs({ 0, 4, 14, 15, 16 }) do c.flow_id = flow; eq(s:context(), nil) end
end)
test("core field failure is not silently zero-filled", function()
    local c = fixture(); local s = Sampler.new(c.api); c.players[1].data.vital_new = nil
    eq(pcall(function() s:sample(s:context(), 1, 17, 1) end), false)
end)
test("display failure does not discard battle data", function()
    local c = fixture(); c.tm = native({}, { get_DisplayFunc = function() error("not ready") end })
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row["p1.vital_new"], 10); eq(row.display_prev_frame, nil)
end)
test("display clock is preserved; unsafe int64 sentinel is absent", function()
    local c = fixture()
    local pd = native({ currentFrame = 44, prevActionFrame = 3, atkFrameMarginFrame = math.maxinteger, hitID = 2 })
    c.tm = native({}, { get_DisplayFunc = function()
        return native({ _gData = native({ PrevFrame = 44, StunFrame = -6, AtkSide = 0,
            FMCurrentFrame = 45, FMStartFrame = 1, FMStopFrame = 44, PlayerDatas = array({ pd, pd }) }) })
    end })
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row.display_prev_frame, 44); eq(row.stage_frame, 1); eq(row.display_stun_frame, -6)
    eq(row["p1.display_atk_margin"], nil)
end)

local function meter_fixture()
    local c = fixture()
    local pd = {}
    for side = 1, 2 do
        local cells = {}
        for i = 1, 80 do
            cells[i] = native({ FrameType = i == 35 and (side == 1 and 10 or 13) or 8,
                IsEmpty = false, IsChanged = false, IsEnd = false, IsNotAdd = false, IsNotWhole = false })
        end
        pd[side] = native({ currentFrame = 34, frameMeterDataList = array(cells) })
    end
    c.meter_players = pd
    c.meter_data = native({ PrevFrame = 2092, FMCurrentFrame = 34, FMStartFrame = 1819,
        FMStopFrame = 239, FMActive = 3, StunFrame = -11, AtkSide = 0, PlayerDatas = array(pd) })
    c.tm = native({}, { get_DisplayFunc = function() return native({ _gData = c.meter_data }) end })
    return c
end

test("meter sample uses the native cursor, not the battle frame or an empty separator", function()
    local c = meter_fixture(); local s = Sampler.new(c.api)
    for _, p in ipairs(c.meter_players) do
        local cells = p.data.frameMeterDataList; local get = cells.get_element
        cells.get_element = function(self, index) eq(index, 34); return get(self, index) end
    end
    local row = s:sample(s:context(), 1, 17, 1)
    eq(s:metadata(s:context()).frame_meter_profile, "native_cursor_cell_v1")
    eq(row["p1.display_meter_type"], 10); eq(row["p2.display_meter_type"], 13)
    eq(row["p1.display_meter_index"], 34); eq(row["p1.display_meter_size"], 80)
    eq(row["p1.display_meter_empty"], 0); eq(row["p1.display_meter_changed"], 0)
    eq(row["p1.display_meter_end"], 0); eq(row["p1.display_meter_not_add"], 0)
    eq(row["p1.display_meter_not_whole"], 0)
    eq(row.display_prev_frame, 2092); eq(row.replay_frame, 1); eq(row.meter_active, 3)
end)

test("meter preserves empty and unknown-type evidence without calling it actionable", function()
    local c = meter_fixture(); local cell = c.meter_players[1].data.frameMeterDataList:get_element(34)
    cell.data.FrameType = 777
    for _, n in ipairs({ "IsEmpty", "IsChanged", "IsEnd", "IsNotAdd", "IsNotWhole" }) do cell.data[n] = true end
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row["p1.display_meter_type"], 777); eq(row["p1.display_meter_empty"], 1)
    eq(row["p1.display_meter_changed"], 1); eq(row["p1.display_meter_end"], 1)
    eq(row["p1.display_meter_not_add"], 1); eq(row["p1.display_meter_not_whole"], 1)
end)

test("meter cursor is bounds checked without modulo guessing", function()
    for _, index in ipairs({ -1, 80, 0.5, false }) do
        local c = meter_fixture(); local p = c.meter_players[1]; p.data.currentFrame = index
        p.data.frameMeterDataList.get_element = function() error("out of bounds read") end
        local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
        eq(row["p1.display_meter_size"], 80); eq(row["p1.display_meter_type"], nil)
        eq(row["p2.display_meter_type"], 13)
    end
end)

test("unknown meter capacity is reported but not read", function()
    local c = meter_fixture(); local cells = c.meter_players[1].data.frameMeterDataList
    cells.get_size = function() return 81 end
    cells.get_element = function() error("unverified array layout") end
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row["p1.display_meter_size"], 81); eq(row["p1.display_meter_type"], nil)
end)

test("meter boolean absence or numeric substitutes never become false", function()
    for _, invalid in ipairs({ "absent", 0, 1 }) do
        local c = meter_fixture(); local cell = c.meter_players[1].data.frameMeterDataList:get_element(34)
        if invalid == "absent" then cell.data.IsEmpty = nil else cell.data.IsEmpty = invalid end
        local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
        eq(row["p1.display_meter_type"], nil); eq(row["p1.display_meter_empty"], nil)
        eq(row["p2.display_meter_type"], 13); eq(row["p1.action_id"], 42)
    end
end)

test("meter read error preserves old display fields, core state and other player's cell", function()
    local c = meter_fixture(); c.meter_players[1].data.frameMeterDataList.get_element = function() error("unavailable") end
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row["p1.display_meter_type"], nil); eq(row["p2.display_meter_type"], 13)
    eq(row["p1.display_current_frame"], 34); eq(row.display_prev_frame, 2092)
    eq(row["p1.vital_new"], 10)
end)

test("a moving cursor or display clock discards the affected cell evidence", function()
    local c = meter_fixture(); local p = c.meter_players[1]; local get = p.get_field; local count = 0
    p.get_field = function(self, name)
        if name == "currentFrame" then count = count + 1; if count >= 3 then return 35 end end
        return get(self, name)
    end
    local s = Sampler.new(c.api); local row = s:sample(s:context(), 1, 17, 1)
    eq(row["p1.display_meter_type"], nil); eq(row["p2.display_meter_type"], 13)
    local b = meter_fixture(); local reads = 0; local original = b.meter_data.get_field
    b.meter_data.get_field = function(self, name)
        if name == "PrevFrame" then reads = reads + 1; return reads == 1 and 2092 or 2093 end
        return original(self, name)
    end
    local t = Sampler.new(b.api); local out = t:sample(t:context(), 1, 17, 1)
    eq(out["p1.display_meter_type"], nil); eq(out["p2.display_meter_type"], nil)
    eq(out.display_prev_frame, 2092); eq(out["p1.action_id"], 42)
end)

test("missing meter data never reuses a previous cell", function()
    local c = meter_fixture(); local s = Sampler.new(c.api)
    eq(s:sample(s:context(), 1, 17, 1)["p1.display_meter_type"], 10)
    c.meter_players[1].data.frameMeterDataList = nil
    local row = s:sample(s:context(), 2, 17, 1)
    eq(row["p1.display_meter_type"], nil)
    local session = Sessions.new(Schema); assert(session:add(s:metadata(s:context()), row)); session:stop("manual")
    eq(session:export().samples[1][Schema.index["p1.display_meter_type"]], false)
end)

local function runtime_fixture()
    local f = { storage = {}, tid = 17, reads = 0, writes = 0, paths = {}, reports = {}, frame = 0 }
    local sampler = {
        context = function() f.reads = f.reads + 1; if f.no_context then return nil end; return { replay_id = f.replay_id or "TEST" } end,
        metadata = function() return metadata end,
        sample = function(_, _, tick, tid)
            if f.throw then error("read failed") end
            if f.during_sample then f.during_sample() end
            local v = values(f.frame, 0, tick); v.thread_id = tid
            if f.edit_sample then f.edit_sample(v) end
            return v
        end,
    }
    local sdk = {
        find_type_definition = function() return { get_method = function() return "method" end } end,
        hook = function(_, pre, post) f.pre, f.post = pre, post end,
        to_int64 = function(value) return value end,
    }
    local re = { on_frame = function(fn) f.render = fn end, on_script_reset = function(fn) f.reset = fn end }
    f.state = Runtime.attach({ schema = Schema, sessions = Sessions, sampler = sampler, sdk = sdk, re = re,
        thread = { get_hook_storage = function() return f.storage end, get_id = function() return f.tid end },
        json = { dump_file = function(path, out, indent)
            f.indent = indent
            f.writes = f.writes + 1; f.paths[#f.paths + 1] = path; f.out = out; return not f.write_fail
        end }, fs = { glob = function() return f.paths end }, date = function() return "TEST" end,
        report = function(msg) f.reports[#f.reports + 1] = msg end })
    function f:tick(result) self.pre(); eq(self.post(result or 1), result or 1); self.frame = self.frame + 1 end
    return f
end
test("hook dormant until requested; original result preserved", function()
    local f = runtime_fixture(); f:tick(123); eq(f.reads, 0); eq(f.writes, 0)
    f.state:start("8x"); f:tick(0); eq(#f.state.session.samples, 1)
end)

test("control window permits idle but rejects every open native update", function()
    local f = runtime_fixture()
    eq(f.state:can_dispatch_control(17), true); eq(f.state:can_dispatch_control(nil), false)
    f.pre(); eq(f.state:can_dispatch_control(17), false)
    eq(f.state:can_dispatch_control(18), false)
    f.post(1); eq(f.state:can_dispatch_control(18), true)
    f.reset(); eq(f.state:can_dispatch_control(17), false)
end)

test("control window stays closed during post reads and recovers after errors", function()
    local f = runtime_fixture(); f.state:request_preview()
    f.during_sample = function()
        eq(f.state.post_in_flight, 1); eq(f.state:can_dispatch_control(f.tid), false)
        error("read failed inside control-window check")
    end
    f:tick(); eq(f.state.post_in_flight, 0); eq(f.state.in_flight, 0)
    eq(f.state.preview_failed, true); eq(f.state:can_dispatch_control(f.tid), true)
end)

test("post read guard balances on missing context and reset", function()
    local f = runtime_fixture(); f.state:request_preview(); f.no_context = true
    f:tick(); eq(f.state.post_in_flight, 0)
    f.pre(); f.reset(); f.post(1); eq(f.state.post_in_flight, 0)
    eq(f.state:can_dispatch_control(f.tid), false)
end)
test("runtime captures eight updates between rendered frames without IO", function()
    local f = runtime_fixture(); f.state:start("8x")
    for _ = 1, 10 do f.render(); for _ = 1, 8 do f:tick() end end
    eq(#f.state.session.samples, 80); eq(f.state.session.render_tick_max_samples, 8); eq(f.writes, 0)
end)
test("start is refused while a prior update is still open", function()
    local f = runtime_fixture(); f.state:start("1x"); f.pre(); f.state:stop(); f.state:start("8x")
    eq(f.post(3), 3); eq(f.reads, 0)
    eq(f.state.session.requested_speed, "1x"); eq(f.state:start("8x"), true)
end)
test("reset disables callbacks without accessing native objects", function()
    local f = runtime_fixture(); f.state:start("1x"); f.pre(); f.reset(); eq(f.post(7), 7)
    f:tick(); eq(f.reads, 0); eq(f.state:start("1x"), false)
end)
test("non-overlapping cross-thread calls continue sampling", function()
    local f = runtime_fixture(); f.state:start("1x"); f:tick(); f.tid = 18; f:tick()
    eq(f.reads, 2); eq(#f.state.session.samples, 2)
    eq(f.state.session.thread_transition_count, 1); eq(f.state.session:is_active(), true)
end)
test("99 captured updates survive a later sequential thread handoff", function()
    local f = runtime_fixture(); f.state:start("1x"); f.tid = 131252
    for _ = 1, 99 do f.render(); f:tick() end
    f.tid = 22; f.render(); f:tick()
    eq(#f.state.session.samples, 100); eq(f.state.session.thread_transition_count, 1)
    eq(next(f.state.session.issue_counts), nil); eq(f.state.in_flight, 0)
end)
test("overlapping updates stop before reading game objects", function()
    for _, second_tid in ipairs({ 17, 18 }) do
        local f = runtime_fixture(); f.state:start("1x")
        f.pre(); local first = f.storage
        f.storage = {}; f.tid = second_tid; f.pre()
        eq(f.state.session.stop_reason, "overlapping_update"); eq(f.reads, 0)
        eq(f.post(9), 9)
        f.storage = first; f.tid = 17; eq(f.post(5), 5)
        eq(f.reads, 0); eq(f.state.in_flight, 0)
    end
end)
test("pre and post thread mismatch still stops", function()
    local f = runtime_fixture(); f.state:start("1x"); f.pre(); f.tid = 18
    eq(f.post(11), 11); eq(f.state.session.stop_reason, "callback_thread_mismatch")
    eq(f.reads, 0); eq(f.state.in_flight, 0)
end)
test("inactive callbacks are tracked but do not read game objects", function()
    local f = runtime_fixture(); f.pre()
    eq(f.state:start("1x"), false); eq(f.post(21), 21)
    eq(f.reads, 0); eq(f.state.in_flight, 0); eq(f.state:start("1x"), true)
end)
test("unpaired post is rejected without game reads", function()
    local f = runtime_fixture(); f.state:start("1x")
    eq(f.post(51), 51); eq(f.state.session.stop_reason, "unpaired_callback")
    eq(f.reads, 0); eq(f.state.in_flight, 0)
end)
test("overlap during sampling discards the in-progress row", function()
    local f = runtime_fixture(); f.state:start("1x")
    f.during_sample = function()
        local first = f.storage
        f.storage = {}; f.pre(); eq(f.post(1), 1)
        f.storage = first
    end
    f:tick()
    eq(#f.state.session.samples, 0); eq(f.state.session.stop_reason, "overlapping_update")
    eq(f.state.in_flight, 0)
    f.state:stop(); eq(f.state.status, "overlapping_update")
end)
test("read exception preserves return and stops once", function()
    local f = runtime_fixture(); f.state:start("1x"); f.throw = true; f:tick(25); f:tick()
    eq(f.state.session.stop_reason, "read_error"); eq(#f.reports, 1); eq(f.state.in_flight, 0)
end)
test("context loss or replay change cannot mix sessions", function()
    for _, change in ipairs({ "no_context", "replay_id" }) do
        local f = runtime_fixture(); f.state:start("1x"); f:tick()
        f[change] = change == "no_context" and true or "OTHER"; f:tick()
        eq(#f.state.session.samples, 1); eq(f.state.session:is_active(), false)
    end
end)
test("export only after stop; no overwrite; unsaved restart refused", function()
    local f = runtime_fixture(); f.state:start("1x"); f:tick()
    eq(f.state:save(), false); eq(f.writes, 0); f.state:stop()
    eq(f.state:start("8x"), false); eq(f.state:save(), true)
    eq(f.state:save(), true); assert(f.paths[1] ~= f.paths[2])
    eq(f.paths[1], "cfn-capture-TEST-TEST.json"); eq(f.indent, 2)
    eq(f.out.sample_count, 1); eq(f.state:start("8x"), true)
end)
test("failed export retains data", function()
    local f = runtime_fixture(); f.state:start("1x"); f:tick(); f.state:stop(); f.write_fail = true
    eq(f.state:save(), false); eq(#f.state.session.samples, 1); eq(f.state.exported, false)
end)
test("preview is opt-in, limited to once per render and does not create a capture", function()
    local f = runtime_fixture(); f.state:request_preview()
    for _ = 1, 8 do f:tick() end
    eq(f.reads, 1); eq(f.state.session, nil); eq(f.state.latest.values.replay_frame, 0); eq(f.writes, 0)
    f.render(); f:tick(); eq(f.reads, 2)
    for _ = 1, 4 do f.render() end
    f:tick(); eq(f.reads, 2)
end)
test("preview reuses recording reads and never loses accelerated samples", function()
    local f = runtime_fixture(); f.state:request_preview(); f.state:start("8x")
    for _ = 1, 8 do f:tick() end
    eq(f.reads, 8); eq(#f.state.session.samples, 8); eq(f.state.latest.values.replay_frame, 7)
end)
test("leaving replay clears preview and read failures latch without retry spam", function()
    local f = runtime_fixture(); f.state:request_preview(); f:tick(); f.render(); f.no_context = true; f:tick()
    eq(f.state.latest, nil); eq(f.state.preview_status, "outside")
    f.no_context, f.throw = false, true; f.render(); f.state:request_preview(); f:tick()
    local reads = f.reads
    f.render(); f.state:request_preview(); f:tick(); eq(f.reads, reads); eq(#f.reports, 1)
end)
test("reset clears the preview without extra native reads", function()
    local f = runtime_fixture(); f.state:request_preview(); f:tick(); f.reset(); f.state:request_preview(); f:tick()
    eq(f.state.latest, nil); eq(f.reads, 1)
end)
test("preview overlap discards partial snapshot", function()
    local f = runtime_fixture(); f.state:request_preview()
    f.during_sample = function()
        local old = f.storage; f.storage = {}; f.pre(); f.post(1); f.storage = old
    end
    f:tick(); eq(f.state.latest, nil); eq(f.state.preview_failed, true); eq(f.state.in_flight, 0)
end)
test("pending native control prevents new recording", function()
    local f = runtime_fixture(); f.state.control_block = true
    eq(f.state:start("1x"), false); eq(f.state.session, nil)
end)
local Presentation = require("presentation")
test("presentation distinguishes sides modes facing and missing values", function()
    local view = Presentation.lines({ metadata = { replay_id = "TEST", round_count = 3, players = {
        { fighter_id = 21, control_mode = 1 }, { fighter_id = 32, control_mode = 0 } } },
        values = { round = 0, battle_round = 0, replay_frame = 192,
            ["p1.facing_right"] = 1, ["p2.facing_right"] = 0, ["p1.vital_new"] = 0, ["p1.vital_max"] = 10000 } })
    assert(view.players[1][1]:find("杰米") and view.players[1][1]:find("现代") and view.players[1][1]:find("朝右"))
    assert(view.players[2][1]:find("英格丽德") and view.players[2][1]:find("经典") and view.players[2][1]:find("朝左"))
    assert(view.players[1][3]:find("0 / 10000")); assert(view.players[2][3]:find("未知"))
    assert(view.summary[2]:find("读取时第 1 局"))
end)

test("stored player snapshot never labels its old clocks as current", function()
    local view = Presentation.lines({metadata = {players = {}},
        values = {round = 0, battle_round = 0, replay_frame = 790, stage_frame = 790}})
    eq(view.summary[3], "读取时录像帧：790")
    assert(view.summary[4]:find("读取时战斗第 1 局"))
    for _, line in ipairs(view.summary) do assert(not line:find("当前")) end
end)
test("presentation keeps unknown identities and asynchronous round transition explicit", function()
    local view = Presentation.lines({ metadata = { players = { { fighter_id = 999, control_mode = 7 }, {} } },
        values = { round = 0, battle_round = 1 } })
    assert(view.players[1][1]:find("未知角色 999")); assert(view.summary[5]:find("尚未同步"))
end)
test("only current control owner may arm scoped capture under control lock",function()
    local f=runtime_fixture(); local owner={}
    f.state.control_block, f.state.control_owner=true,owner
    eq(f.state:start("8x",{round_scope=0,stop_at_finish=true},{}),false)
    eq(f.state:start("8x",{round_scope=0,stop_at_finish=true},owner),true)
    eq(f.state.session.round_scope,0); eq(f.state.session.stop_at_finish,true)
end)
test("native per-update guard stops at knockout before remaining accelerated updates",function()
    local f=runtime_fixture()
    f.edit_sample=function(v)
        v["p1.vital_new"]=10000; v["p2.vital_new"]=f.frame>=2 and 0 or 10000
        v.play_timer,v.play_timer_ms=50,59
    end
    f.state:start("8x",{round_scope=0,stop_at_finish=true})
    for _=1,8 do f:tick() end
    eq(#f.state.session.samples,3); eq(f.state.status,"knockout"); eq(f.writes,0)
end)
test("native capture drops first next-round sample and exposes boundary stop",function()
    local f=runtime_fixture()
    f.edit_sample=function(v)
        v["p1.vital_new"],v["p2.vital_new"],v.play_timer,v.play_timer_ms=10000,10000,50,59
        if f.frame>0 then v.round=1; v.battle_round=1 end
    end
    f.state:start("8x",{round_scope=0,stop_at_finish=true}); f:tick(); f:tick()
    eq(#f.state.session.samples,1); eq(f.state.status,"round_boundary"); eq(f.writes,0)
end)
test("whole-match capture retains later rounds and uses explicit bounded capacity",function()
    local f=runtime_fixture()
    f.edit_sample=function(v)
        v["p1.vital_new"],v["p2.vital_new"],v.play_timer,v.play_timer_ms=10000,0,0,0
        if f.frame>0 then v.round=1; v.battle_round=1 end
    end
    eq(f.state:start("8x",{limit=120000}),true)
    f:tick(); f:tick(); eq(#f.state.session.samples,2); eq(f.state.session:is_active(),true)
    eq(f.state.session.sample_limit,120000); eq(f.writes,0)
end)
test("ended replay identity stays readable without reopening live sampling",function()
    local f=fixture(); local s=Sampler.new(f.api)
    local replay=s:context().replay
    replay.methods.get_Replay=function() return false end
    eq(s:context(),nil); eq(s:identity().replay_id,"TEST")
    f.manager.data._CurrentReplayID=99; eq(s:identity(),nil)
end)
test("owned end handoff retains raw data then times out even without more battle callbacks",function()
    local f=runtime_fixture(); local owner={}; f.state.control_owner=owner
    f.state:start("8x",{wait_for_end=true},owner); f:tick()
    f.no_context=true; f:tick(); eq(f.state.session:is_active(),true); eq(#f.state.session.samples,1)
    for _=1,119 do f.render() end; eq(f.state.session:is_active(),true)
    f.render(); eq(f.state.session.stop_reason,"left_replay"); eq(#f.state.session.samples,1)
    eq(f.state:save(),true); eq(f.writes,1)
end)
test("native end can stop within grace and next replay never replaces the saved session",function()
    local f=runtime_fixture(); local owner={}; f.state.control_owner=owner
    f.state:start("8x",{wait_for_end=true},owner); f:tick(); local session=f.state.session
    f.no_context=true; f:tick(); f.render(); session:stop("replay_end")
    eq(f.state:save(),true)
    f.no_context=false; f.frame=191; f:tick(); f.render()
    eq(f.state.session,session); eq(session.stop_reason,"replay_end"); eq(#session.samples,1); eq(f.writes,1)
end)
test("manual capture cannot opt into analysis end grace",function()
    local f=runtime_fixture(); f.state:start("8x",{wait_for_end=true}); f:tick()
    f.no_context=true; f:tick(); eq(f.state.session.stop_reason,"left_replay")
end)
print(string.format("%d CFN capture tests passed", passed))
