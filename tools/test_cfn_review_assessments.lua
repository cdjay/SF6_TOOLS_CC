package.path="tools/cfn_replay_capture/?.lua;"..package.path
local M=require("review_assessments")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
if arg[1]=="--capture" then
    local json=require("tools/training_record_bank/vendor/dkjson")
    local function read(path) local f=assert(io.open(path,"rb")); local s=f:read("a"); f:close(); return assert(json.decode(s)) end
    local capture,doc=read(arg[2]),read(arg[3])
    local schema={columns=capture.columns,index={}}
    for i,n in ipairs(schema.columns) do schema.index[n]=i end
    local review=assert(require("damage_review").new(schema,capture.metadata,require("damage_rules")))
    for _,row in ipairs(capture.samples) do review:add(row) end
    local original=review:finish(); assert(not review.error)
    local out,err=M.build(original,capture,review,doc,schema); assert(not err,err)
    local before,after,levels,confirmed=0,0,{},{}
    for _,item in ipairs(original) do before=before+item.damage end
    for _,item in ipairs(out) do
        after=after+item.damage; levels[item.priority]=(levels[item.priority] or 0)+1
        if item.human_review then confirmed[#confirmed+1]={round=item.round+1,frame=item.frame,target=item.review_frame,player=item.receiver,priority=item.priority,damage=item.damage} end
    end
    eq(after,before); eq(#out,#original+#doc.opportunities); eq(#confirmed,#doc.items+#doc.opportunities)
    print(assert(json.encode({original=#original,items=#out,damage=after,levels=levels,confirmed=confirmed})))
    return
end
local capture={metadata={replay_id="TEST",version=20004000,players={{fighter_id=1,control_mode=0},{fighter_id=2,control_mode=1}}},
    samples={{0,0,100,100,1000,1000,0},{0,0,101,101,1000,700,-6},{0,0,102,102,1000,700,-6}}}
local schema={index={round=1,battle_round=2,replay_frame=3,stage_frame=4,["p1.vital_new"]=5,["p2.vital_new"]=6,display_stun_frame=7}}
local review={by_round={[0]={first_frame=100,last_frame=102}}}
local item={id=1,round=0,frame=101,receiver=2,damage=300,review_frame=100,classification={rule="attack_counter",title="counter",level="observed"},facts={flags={counter=true}}}
local doc={replay_id="TEST",build=20004000,players=capture.metadata.players,items={
    {round=1,frame=101,receiver=2,source="user_verified",priority="P0",first_damage=300,title="confirmed",review_from=100}},opportunities={
    {round=1,frame=102,receiver=1,source="user_verified",priority="P0",title="missed",review_from=101,
        checks={{frame=102,field="p1.vital_new",value=1000},{frame=101,field="display_stun_frame",value=-6}},native_value=-6}}}
local out,err=M.build({item},capture,review,doc,schema)
eq(err,nil); eq(#out,2); eq(out[1].priority,"P0"); eq(out[1].damage,300); eq(item.classification.title,"counter")
eq(out[2].damage,0); eq(out[2].receiver,1); eq(out[2].review_frame,101); eq(out[2].native_advantage.value,-6)
eq(out[1].automatic_priority,"P1"); eq(out[1].human_review.source,"user_verified")
local auto=M.build({item},capture,review,nil,schema); eq(auto[1].priority,"P1")
doc.build=1; out,err=M.build({item},capture,review,doc,schema); eq(#out,1); eq(out[1].priority,"P1"); assert(err)
doc.build=20004000; doc.items[1].first_damage=301
out,err=M.build({item},capture,review,doc,schema); eq(#out,1); assert(err)
doc.items[1].first_damage=300; doc.opportunities[1].checks[1].value=999
out,err=M.build({item},capture,review,doc,schema); eq(#out,1); assert(err)
doc.opportunities[1].checks[1].value=1000; doc.items[1].review_from=99
out,err=M.build({item},capture,review,doc,schema); eq(#out,1); assert(err)
item.classification.level="inferred"; eq(M.build({item},capture,review,nil,schema)[1].priority,"P3")
item.classification.level="observed"; item.facts.flags={}; eq(M.build({item},capture,review,nil,schema)[1].priority,"P2")
print("CFN review grading, confirmed missed opportunity, identity and evidence guards passed")
