package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Schema,Candidates,Review=require("schema"),require("candidates"),require("match_review")
local ix=Schema.index
local count=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local function fixture(rounds)
    return assert(Review.new(Schema,{version=20004000,frame_meter_profile="native_cursor_cell_v1",replay_id="TEST",round_count=rounds},Candidates))
end
local function row(round,f)
    local r={}; for i in ipairs(Schema.columns) do r[i]=0 end
    local function set(n,v) r[ix[n]]=v end
    set("round",round); set("battle_round",round); set("replay_frame",f); set("stage_frame",f)
    set("fight_st",4); set("play_timer",99); set("play_timer_ms",59); set("display_prev_frame",f)
    for side=1,2 do
        local p="p"..side.."."
        set(p.."vital_new",10000); set(p.."display_meter_size",80)
        set(p.."display_meter_index",f%80); set(p.."action_frame_raw",f*65536)
    end
    return r
end
local function feed(d,round,n)
    for f=100,104+n do
        local r=row(round,f)
        if f==101 or f==102 then r[ix["p1.act_st"]]=27; r[ix["p1.guard_time"]]=103-f end
        if f>=103 and f<103+n then r[ix["p2.display_meter_type"]]=8 end
        if f==104+n then r[ix["p2.vital_new"]]=0 end
        d:add(r)
    end
end
test("two three and five rounds use actual metadata and keep candidates separated",function()
    for _,n in ipairs({2,3,5}) do
        local d=fixture(n)
        for round=0,n-1 do feed(d,round,round%2==0 and 4 or 5) end
        local items=d:finish(true); eq(#items,n); eq(#d.rounds,n); eq(d.coverage_ok,true); eq(d.full_replay_verified,false)
        for i,item in ipairs(items) do eq(item.round,i-1); eq(item.frame,103) end
    end
end)
test("same frame numbers in different rounds cannot conflict",function()
    local d=fixture(2); feed(d,0,4); feed(d,1,5); d:finish(true)
    eq(d.error,nil); eq(#d.items,2); eq(d.items[2].kind,"five_plus_punish_candidate")
end)
test("unmatched transition clocks are excluded and cannot join windows",function()
    local d=fixture(2); feed(d,0,4)
    local r=row(0,110); r[ix.battle_round]=1; d:add(r)
    feed(d,1,5); d:finish(true); eq(d.transition_samples,1); eq(#d.items,2); eq(d.error,nil)
end)
test("missing round or missing finish cannot become complete on result signal",function()
    local d=fixture(3); feed(d,0,4); feed(d,2,5); d:finish(true); eq(d.coverage_ok,false)
    local b=fixture(1); b:add(row(0,191)); b:add(row(0,192)); b:finish(true); eq(b.coverage_ok,false)
end)
test("partial stop never reports complete even all known rounds are present",function()
    local d=fixture(1); feed(d,0,4); d:finish(false); eq(d.coverage_ok,false); eq(d.playback_finished,false)
end)
test("gaps invalidate coverage and do not interpolate evidence",function()
    local d=fixture(1); d:add(row(0,90)); feed(d,0,5); d:finish(true); eq(d.coverage_ok,false); eq(d.gaps,1)
end)
test("round rewind invalidates the result rather than merging a second pass",function()
    local d=fixture(2); feed(d,0,4); feed(d,1,5); d:add(row(0,200)); d:finish(true)
    eq(d.error,"rewound_capture"); eq(#d.items,0); eq(d.coverage_ok,false)
end)
test("same-round conflicting samples invalidate results",function()
    local d=fixture(1); d:add(row(0,100)); local r=row(0,100); r[ix["p1.x_raw"]]=1; d:add(r)
    d:finish(true); eq(d.error,"conflicting_samples"); eq(#d.items,0)
end)
test("post-KO frozen samples do not manufacture candidate conflicts",function()
    local d=fixture(1); feed(d,0,4); local r=row(0,108); r[ix["p2.vital_new"]]=0; r[ix.fight_st]=5
    d:add(r); d:finish(true); eq(d.error,nil); eq(#d.items,1); eq(d.rounds[1].finish_frame,108)
end)
test("unsupported build does not produce an empty successful report",function()
    local d,reason=Review.new(Schema,{version=0},Candidates); eq(d,nil); eq(reason,"unsupported_analysis")
end)
print(count.." CFN match review tests passed")
