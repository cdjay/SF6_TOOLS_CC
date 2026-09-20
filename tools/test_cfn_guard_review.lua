package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Schema,Guard,Rules=require("schema"),require("guard_review"),require("damage_rules")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local meta={version=20004000,replay_id="TEST"}
local function row(frame,guard,value)
    local r={}; for i in ipairs(Schema.columns) do r[i]=0 end
    for n,v in pairs({round=0,battle_round=0,fight_st=2,replay_frame=frame,stage_frame=frame,
        display_prev_frame=frame,display_stun_frame=value,["p1.vital_new"]=10000,["p2.vital_new"]=10000,
        ["p2.act_st"]=guard and 27 or 0,["p2.guard_time"]=guard and 197-frame or 0}) do r[Schema.index[n]]=v end
    return r
end
local function run(mode)
    local d=assert(Guard.new(Schema,meta,Rules))
    for f=191,230 do
        local r=row(f,f>=192 and f<=196,f>=194 and -6 or 0)
        if mode=="same" then r[Schema.index.display_stun_frame]=-6 end
        if mode=="stale" and f==194 then r[Schema.index.display_prev_frame]=0 end
        if f>=198 then r[Schema.index["p2.act_st"]]=29 end
        if mode~="gap" or f~=194 then d:add(r) end
        if mode=="duplicate" then d:add(r) end
    end
    d:finish({{round=0,frame=197,defender=2,frames=6,lower_bound=false}})
    return d
end
local d=run(); eq(#d.items,1)
local i=d.items[1]; eq(i.frame,192); eq(i.guard_end,197); eq(i.native_advantage.value,-6)
eq(i.native_advantage.frame,194); eq(i.native_advantage.sign_basis_verified,false)
eq(i.response.frame,198); eq(i.response.delay,1); eq(i.window.frames,6); eq(i.candidate,true)
eq(i.damage,0); eq(i.receiver,2); eq(i.review_frame,194); eq(i.verdict,nil)
eq(#run("duplicate").items,1)
for _,mode in ipairs({"same","stale","gap"}) do
    local x=run(mode)
    for _,v in ipairs(x.items) do eq(v.native_advantage,nil) end
end
d=assert(Guard.new(Schema,meta,Rules));d:add(row(192,true,-6));d:add(row(193,true,-6));d:finish({})
eq(d.items[1].complete,false);eq(d.items[1].native_advantage,nil);eq(d.items[1].candidate,false)
d=assert(Guard.new(Schema,meta,Rules));local a=row(191,false,0);d:add(a)
local b=row(191,false,1);d:add(b);d:finish({});eq(d.error,"conflicting_samples");eq(#d.items,0)
assert(not Guard.new(Schema,{version=1},Rules))
d=assert(Guard.new(Schema,meta,Rules));a=row(191,true,0);d:add(a)
b=row(191,true,0);b[Schema.index.fight_st]=5;d:add(b);d:finish({})
eq(d.error,nil);eq(d.items[1].complete,false)
if arg[1]=="--json" then
    local Json=require("tools/training_record_bank/vendor/dkjson")
    local c=assert(Json.decode(io.read("*a")));local schema={columns=c.columns,index={}}
    for n,v in ipairs(c.columns) do schema.index[v]=n end
    local g=assert(Guard.new(schema,c.metadata,Rules))
    local match=assert(require("match_review").new(schema,c.metadata,require("candidates")))
    for _,r in ipairs(c.samples) do g:add(r);match:add(r) end
    g:finish(match:finish(c.stop_reason=="replay_end")); print(assert(Json.encode({items=g.items,error=g.error,rounds=g.rounds}))); return
end
print("CFN guard ledger, association, response and opportunity tests passed")
