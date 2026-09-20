package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Stats,Schema=require("statistics"),require("schema")
local function eq(a,b) assert(a==b or type(a)=="number" and type(b)=="number" and math.abs(a-b)<1e-8,tostring(a).." ~= "..tostring(b)) end
if arg[1]=="--capture" then
    local Json=require("tools/training_record_bank/vendor/dkjson")
    local f=assert(io.open(arg[2],"rb")); local capture=assert(Json.decode(f:read("a"))); f:close()
    local schema={columns=capture.columns,index={}}; for i,k in ipairs(schema.columns) do schema.index[k]=i end
    local s=assert(Stats.new(schema,capture.metadata)); local d=assert(require("damage_review").new(schema,capture.metadata,require("damage_rules")))
    local started=os.clock()
    for _,row in ipairs(capture.samples) do s:add(row);d:add(row) end
    local items=d:finish();assert(not d.error,d.error)
    s:finish(items,items,capture.stop_reason=="replay_end"); assert(not s.error,s.error)
    local rounds={}; for _,r in ipairs(s.rounds) do rounds[#rounds+1]={round=r.round+1,frames=r.frames,first=r.first_frame,last=r.last_frame,ending=r.ending} end
    local players={}
    for side,p in ipairs(s.all.players) do
        players[side]={received=p.damage_received,dealt=p.damage_dealt,segments=p.segments,signals=p.signals,behavior=p.behavior,
            loss_distribution=p.loss_distribution,resources=p.resources,direction_entropy=p.direction_entropy}
    end
    print(assert(Json.encode({frames=s.all.frames,duplicates=s.duplicates,gaps=s.gaps,transitions=s.transitions,
        excluded_after_end=s.excluded_after_end,rounds=rounds,players=players,seconds=os.clock()-started})))
    return
end
local function row(frame,round)
    local r={}
    for i in ipairs(Schema.columns) do r[i]=0 end
    local values={round=round or 0,battle_round=round or 0,replay_frame=frame,stage_frame=frame,fight_st=4,play_timer=99,play_timer_ms=60-frame%60}
    for side=1,2 do
        local p="p"..side.."."
        values[p.."vital_new"],values[p.."vital_max"]=10000,10000
        values[p.."focus_new"],values[p.."focus_max"]=60000,60000
        values[p.."mSuperGaugeMax"],values[p.."act_st"]=30000,0
        values[p.."facing_right"]=side==1 and 1 or 0
        values[p.."x_raw"]=side==1 and 0 or 100*65536
    end
    for k,v in pairs(values) do r[Schema.index[k]]=v end
    return r
end
local meta={version=20004000,replay_id="TEST",players={{},{}}}
local s=assert(Stats.new(Schema,meta))
local a,b,c=row(191),row(192),row(193)
a[Schema.index["p1.act_st"]]=8; a[Schema.index["p1.pl_input_new"]]=8
b[Schema.index["p1.act_st"]]=29; b[Schema.index["p1.focus_new"]]=50000
c[Schema.index["p1.act_st"]]=29; c[Schema.index["p1.focus_new"]]=51000
b[Schema.index["p2.hit_st"]]=0x8100; b[Schema.index["p2.vital_new"]]=9700
c[Schema.index["p2.hit_st"]]=0x8100; c[Schema.index["p2.vital_new"]]=9700
s:add(a);s:add(b);s:add(c);s:add(c)
s:finish({}, {},false)
eq(s.all.frames,3);eq(s.duplicates,1);eq(s.all.players[1].behavior.forward,1)
eq(s.all.players[1].behavior.attack,2);eq(s.all.players[1].entries.attack,1)
eq(s.all.players[2].signals.punish,1);eq(s.all.players[2].signals.hit,1)
eq(s.all.players[1].resources.drive.drop,10000/60000*100)
eq(s.all.players[1].resources.drive.gain,1000/60000*100)
eq(s:nearest_frame(0,192),192);eq(s:nearest_frame(1,192),nil)
local d=Stats.distribution({1,2,3,4});eq(d.mean,2.5);eq(d.median,2.5);eq(d.p90,4);eq(d.q1,1.75);eq(d.q3,3.25)
eq(Stats.distribution({}).mean,nil);eq(Stats.distribution({5}).sd,0)
local gap=assert(Stats.new(Schema,meta));gap:add(a);gap:add(c);gap:finish({}, {},false)
eq(gap.gaps,1);eq(gap.all.players[1].entries.attack,nil);eq(gap.all.players[1].resources.drive.drop,0)
local ko=assert(Stats.new(Schema,meta));local dying=row(192);dying[Schema.index["p2.vital_new"]]=0
ko:add(row(191));ko:add(dying);ko:add(row(193));ko:add(row(191,1));ko:finish({}, {},false)
eq(ko.all.frames,3);eq(ko.by_round[0].frames,2);eq(ko.by_round[0].ending,"p2_zero")
local missing=assert(Stats.new(Schema,meta));a=row(191);a[Schema.index["p1.focus_new"]]=false
missing:add(a);missing:finish({}, {},false);eq(missing.all.players[1].resources.drive.frames,0)
local bad=assert(Stats.new(Schema,meta));a=row(191);b=row(191);b[Schema.index["p1.vital_new"]]=9
bad:add(a);bad:add(b);assert(bad.error)
local multi=assert(Stats.new(Schema,meta));multi:add(row(191));multi:add(row(192));multi:add(row(191,1))
multi:finish({{id=1,round=0,frame=192,review_frame=191,receiver=2,damage=300,classification={rule="attack_counter",title="counter"},facts={source_observed=1}}}, {}, false)
eq(multi.all.players[1].damage_dealt,300);eq(multi.all.players[2].damage_received,300)
eq(multi.by_round[0].players[2].loss_distribution.max,300);eq(multi.by_round[1].players[2].loss_distribution.max,nil)
eq(multi.all.players[2].damage_bins[1],1)
assert(not Stats.new(Schema,{version=1}))
local unavailable=assert(Stats.new(Schema,meta))
a=row(191);b=row(192)
for _,r in ipairs({a,b}) do r[Schema.index["p1.hit_st"]]=false; r[Schema.index["p1.focus_new"]]=false end
a[Schema.index["p1.act_st"]]=false; b[Schema.index["p1.act_st"]]=29
unavailable:add(a);unavailable:add(b);unavailable:finish({}, {},false)
eq(unavailable.all.players[1].signal_frames,0);eq(unavailable.all.players[1].entries.attack,nil)
eq(unavailable.all.players[1].behavior.unknown,1);eq(unavailable.all.players[1].resources.drive.delta_frames,nil)
local flow=assert(Stats.new(Schema,meta))
a=row(191);b=row(191);c=row(192)
b[Schema.index.fight_st]=5;c[Schema.index["p1.focus_new"]]=0
flow:add(a);flow:add(b);flow:add(c);flow:finish({}, {},false)
eq(flow.all.players[1].resources.drive.delta_frames,nil)
local intro=assert(Stats.new(Schema,meta))
for frame=1,4 do
    local r=row(frame);r[Schema.index.play_timer_ms]=frame<3 and 60 or 62-frame
    intro:add(r)
end
intro:finish({}, {},false)
eq(intro:nearest_frame(0,1),3)
eq(unavailable:nearest_frame(0,1),192)
print("CFN statistics distributions, continuity, grouping, resource deltas and round boundaries passed")
