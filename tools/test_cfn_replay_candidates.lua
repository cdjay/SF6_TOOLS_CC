package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Schema, Candidates, Sessions = require("schema"), require("candidates"), require("session")
local count=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local meta={version=20004000,replay_id="TEST",frame_meter_profile="native_cursor_cell_v1"}
local function row(f)
    local v={round=0,battle_round=0,replay_frame=f,stage_frame=f,display_prev_frame=f,meter_start_frame=0,
        fight_st=4,render_tick=f,thread_id=1,play_timer=99,play_timer_ms=59}
    for side=1,2 do
        local p="p"..side.."."
        for _, n in ipairs(Schema.player_columns) do v[p..n]=0 end
        v[p.."vital_new"],v[p.."act_st"],v[p.."display_meter_size"]=10000,0,80
        v[p.."display_meter_index"]=f%80
        v[p.."action_frame_raw"]=f*65536
        v[p.."x_raw"]=side*65536*70
    end
    return v
end
local function dense(v)
    local r={}; for i,n in ipairs(Schema.columns) do r[i]=v[n]==nil and false or v[n] end; return r
end
local function fixture(n,side)
    side=side or 1
    local rows={}
    for f=100,103+n do
        local r=row(f)
        if f==101 or f==102 then r["p"..side..".act_st"]=27; r["p"..side..".guard_time"]=103-f end
        if f>=103 and f<103+n then r["p"..(3-side)..".display_meter_type"]=8 end
        rows[#rows+1]=r
    end
    return rows
end
local function inspect(rows)
    local d=assert(Candidates.new(Schema,meta,0))
    for _,v in ipairs(rows) do d:add(dense(v)) end
    d:finish("capture_end"); return d
end
test("only exact four and five-plus become distinct candidates for both sides",function()
    for side=1,2 do
        for n=1,8 do
            local d=inspect(fixture(n,side)); eq(#d.items,n>=4 and 1 or 0)
            if n>=4 then local w=d.items[1]; eq(w.frame,103); eq(w.frames,n); eq(w.defender,side)
                eq(w.kind,n==4 and "four_frame_boundary" or "five_plus_punish_candidate"); eq(w.reach_verified,false) end
        end
    end
end)
test("held blue excluded flags unknown cells and missing data cannot fill a window",function()
    for _,field in ipairs({"display_meter_empty","display_meter_not_add","display_meter_not_whole",
        "display_meter_index","display_meter_type","display_meter_size"}) do
        local rows=fixture(5)
        rows[6]["p2."..field]=false
        eq(#inspect(rows).items,0)
    end
    local rows=fixture(5); rows[6]["p2.display_meter_index"]=rows[5]["p2.display_meter_index"]
    eq(#inspect(rows).items,0)
end)
test("frame gaps reset table and changed opponent action cut evidence",function()
    for _,change in ipairs({function(r) r[6].replay_frame=999 end,
        function(r) r[6].meter_start_frame=100 end,
        function(r) r[6]["p2.action_id"]=1 end,
        function(r) r[6].fight_st=5 end,
        function(r) r[6]["p1.hit_stop"]=1 end,
        function(r) r[6]["p1.vital_new"]=9000 end,
        function(r) r[4]["p1.act_st"]=27 end,
        function(r) r[4]["p1.y_raw"]=65536 end}) do
        local rows=fixture(5); change(rows); eq(#inspect(rows).items,0)
    end
end)
test("partial guard start and still-guard zero counter cannot imply actionability",function()
    local rows=fixture(5); table.remove(rows,1); eq(#inspect(rows).items,0)
    rows=fixture(5); rows[4]["p1.act_st"]=27; eq(#inspect(rows).items,0)
end)
test("four truncated cells are not exact four but five remain a lower-bound candidate",function()
    local rows=fixture(4); table.remove(rows); eq(#inspect(rows).items,0)
    rows=fixture(5); table.remove(rows); local d=inspect(rows); eq(#d.items,1); eq(d.items[1].lower_bound,true)
end)
test("identical duplicate ignored conflicting duplicate invalidates report",function()
    local rows=fixture(5); table.insert(rows,6,rows[5]); eq(#inspect(rows).items,1)
    local d=inspect(fixture(5)); eq(#d.items,1)
    rows=fixture(5); local copy={}; for k,v in pairs(rows[5]) do copy[k]=v end
    copy["p2.display_meter_type"]=0; table.insert(rows,6,copy)
    d=inspect(rows); eq(#d.items,0); eq(d.reason,"conflicting_samples")
end)
test("unsupported builds rejected no action ids are treated as move semantics",function()
    eq(Candidates.new(Schema,{version=1},0),nil)
    local rows=fixture(5)
    for _,r in ipairs(rows) do r["p2.action_id"]=54321 end
    eq(#inspect(rows).items,1)
end)
test("round capture stops exactly on KO and never adds another round",function()
    local s=Sessions.new(Schema,{round_scope=0,stop_at_finish=true})
    eq(s:add(meta,row(100)),true)
    local ko=row(101); ko["p2.vital_new"]=0
    eq(s:add(meta,ko),true); eq(s.stop_reason,"knockout"); eq(#s.samples,2)
    eq(s:add(meta,row(102)),false); eq(#s.samples,2)
    s=Sessions.new(Schema,{round_scope=0,stop_at_finish=true}); s:add(meta,row(100))
    local next_round=row(0); next_round.round=1; next_round.battle_round=1
    eq(s:add(meta,next_round),false); eq(s.stop_reason,"round_boundary"); eq(#s.samples,1)
end)
test("timer requires both components zero and missing finish state stops",function()
    local s=Sessions.new(Schema,{round_scope=0,stop_at_finish=true})
    local r=row(100); r.play_timer=0; r.play_timer_ms=1; s:add(meta,r); eq(s:is_active(),true)
    r=row(101); r.play_timer=0; r.play_timer_ms=0; s:add(meta,r); eq(s.stop_reason,"time_up")
    s=Sessions.new(Schema,{round_scope=0,stop_at_finish=true}); r=row(100); r.play_timer=nil
    s:add(meta,r); eq(s.stop_reason,"missing_finish_state")
end)
test("unscoped manual recording still permits multiple rounds",function()
    local s=Sessions.new(Schema); s:add(meta,row(100)); local r=row(0); r.round=1; r.battle_round=1
    eq(s:add(meta,r),true); eq(s:is_active(),true); eq(#s.samples,2)
end)
print(count.." CFN candidate tests passed")
