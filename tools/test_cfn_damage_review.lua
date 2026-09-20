package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Schema,Review,Rules=require("schema"),require("damage_review"),require("damage_rules")
local Json=require("tools/training_record_bank/vendor/dkjson")
if arg[1]=="--rules-json" then
    local output={}
    for _,f in ipairs(assert(Json.decode(io.read("*a"),1,nil))) do
        f.flags={}
        for _,name in ipairs(f.new_flags or {}) do f.flags[name]=true end
        f.active_seen=#(f.fresh_active_frames or {})>0
        f.contact_seen=f.contact_observed_during_attack
        local c=Rules.classify(f)
        output[#output+1]={rule=c.rule,level=c.level}
    end
    print(assert(Json.encode(output))); return
end
if arg[1]=="--json" then
    local capture=assert(Json.decode(io.read("*a")))
    local schema={columns=capture.columns,index={}}
    for i,n in ipairs(schema.columns) do schema.index[n]=i end
    local d=assert(Review.new(schema,capture.metadata,Rules))
    for _,r in ipairs(capture.samples) do d:add(r) end
    d:finish()
    print(assert(Json.encode({items=d.items,rounds=d.rounds,observations=d.observations,error=d.error})))
    return
end
local function row(frame,hp,count,damage)
    local r={}
    for i in ipairs(Schema.columns) do r[i]=0 end
    local v={round=0,battle_round=0,replay_frame=frame,stage_frame=frame,fight_st=2,
        ["p1.vital_new"]=hp,["p2.vital_new"]=10000,["p1.damage_source"]=2,
        ["p2.mComboCount"]=count,["p2.combo_cnt"]=count,["p2.mComboDamage"]=damage}
    for n,x in pairs(v) do r[Schema.index[n]]=x end
    return r
end
local meta={version=20004000,replay_id="TEST",frame_meter_profile="native_cursor_cell_v1"}
local function review(rows)
    local d=assert(Review.new(Schema,meta,Rules))
    for _,r in ipairs(rows) do d:add(r) end
    d:finish(); return d
end
local d=review({row(191,1000,0,0),row(192,700,1,300),row(193,0,2,1100)})
assert(#d.items==1 and d.items[1].damage==1000 and d.observations==2)
assert(d.items[1].review_frame==192 and d.items[1].frame==192)
assert(d.items[1].priority=="P3" and d.items[1].classification.rule=="unresolved")
d=review({row(191,1000,0,0),row(193,700,1,300)})
assert(#d.items==0, "cannot derive loss across a missing frame")
local a,b=row(191,1000,0,0),row(192,700,1,300)
b[Schema.index["p1.act_st"]]=27; b[Schema.index["p1.hit_st"]]=4
b[Schema.index["p2.mComboCount"]]=0; b[Schema.index["p2.combo_cnt"]]=0
d=review({a,b})
assert(d.items[1].classification.rule=="guard_damage")
local changed=row(192,650,1,300)
d=review({a,b,changed}); assert(d.error=="conflicting_samples" and #d.items==0)
local held=row(193,650,0,0); held[Schema.index["p1.hit_st"]]=4; held[Schema.index["p1.act_st"]]=27
d=review({a,b,held}); assert(d.items[2].classification.rule~="guard_damage", "held flag is not fresh contact")
assert(Rules.direction(4,1).back and Rules.direction(4,0).forward)
assert(Rules.direction(12,1)==nil)
assert(not Review.new(Schema,{version=1},Rules))
local function guard_case(mode)
    local rows={}
    for frame=191,200 do
        local r=row(frame,frame==200 and 700 or 1000,frame==200 and 1 or 0,frame==200 and 300 or 0)
        r[Schema.index.display_prev_frame]=frame
        r[Schema.index.display_stun_frame]=frame>=193 and (frame>=195 and -6 or -12) or 0
        if frame>=192 and frame<=196 then r[Schema.index["p1.act_st"]]=27; r[Schema.index["p1.guard_time"]]=197-frame end
        if mode=="stale" then r[Schema.index.display_stun_frame]=-6 end
        if mode=="lag" and frame==195 then r[Schema.index.display_prev_frame]=0 end
        if mode~="gap" or frame~=195 then rows[#rows+1]=r end
    end
    return review(rows)
end
d=guard_case(); assert(d.items[1].native_advantage.value==-6 and d.items[1].review_frame==195)
assert(d.items[1].native_advantage.sign_basis_verified==false)
for _,mode in ipairs({"stale","lag","gap"}) do
    d=guard_case(mode); assert(d.items[1].native_advantage==nil,mode.." must not claim native advantage")
end
-- A zero-loss native hit in a cinematic must not split the following damage.
local cut={row(191,1000,0,0),row(192,700,1,300),row(193,700,2,300),
    row(194,500,3,500),row(195,1,4,1100),row(196,0,4,1100)}
for i,r in ipairs(cut) do
    r[Schema.index["p1.act_st"]]=i>=3 and 38 or i==2 and 32 or 29
    r[Schema.index["p2.act_st"]]=i>=3 and 37 or 29
    r[Schema.index["p1.hit_st"]]=i==2 and 0x8100 or 0
    r[Schema.index.display_prev_frame]=r[Schema.index.stage_frame]
    r[Schema.index.display_stun_frame]=6
end
d=review(cut)
assert(#d.items==1,"cinematic native count-only transition split one damage sequence into multiple problems")
assert(d.items[1].damage==1000 and d.items[1].damage_observations==4,"damage must include the final delayed 1HP loss exactly once")
assert(d.items[1].classification.rule=="attack_punished")
assert(d.items[1].native_advantage==nil and d.items[1].native_snapshot.value==6,"unlinked display values must be preserved separately")
local ambiguous=Rules.classify({receiver=1,source_observed=2,previous_state=0,current_state=38,other_state=37,flags={}})
assert(ambiguous.level~="observed" and not ambiguous.title:find("抓",1,true),"paired cinematic states do not prove a throw")
print("CFN damage review and native context tests passed")
