package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Schema=require("schema");package.loaded["func/CFNReplayCapture/schema"]=Schema
local Config,Context,Rules,Evaluation=require("rule_config"),require("rule_context"),require("damage_rules"),require("rule_evaluation")
local json=require("tools/training_record_bank/vendor/dkjson")
if arg[1]=="--contexts" then
    local doc=assert(json.decode(io.read("*a")))
    local context=Context.new(doc.capture,Schema,Rules);local result={}
    for _,item in ipairs(doc.items) do result[#result+1]=context(item,nil) end
    print(assert(json.encode(result)));return
end
local f={receiver=1,frame=200,source_observed=2,current_state=32,previous_state=29,previous_y=0,
    guard_end=180,wakeup_last_frame=185,flags={counter=true}}
local item={id=1,receiver=1,round=0,frame=200,last_frame=200,damage=200,facts=f,classification=Rules.classify(f)}
local g={id=1,receiver=1,round=0,frame=150,last_frame=180,guard_end=181,damage=0,
    response={frame=230,delay=49,through=230,reason="attack_observed"},native_advantage={value=5}}
local capture={metadata={replay_id="TEST",version=Config.build,players={}},samples={}}
local eval=Evaluation.new(capture,{item},{g},Schema,Rules,Context)
local config=Config.defaults();local ds,gs=eval:evaluate(assert(Config.compile(config)))
assert(ds[1].classification.rule=="attack_counter" and gs[1].response.reason=="limit")
config.settings.guard_frames=25;config.settings.response_frames=60;config.settings.advantage_min=6
ds,gs=eval:evaluate(assert(Config.compile(config)))
assert(ds[1].classification.rule=="guard_button_counter" and gs[1].response.delay==49 and not gs[1].candidate)
assert(g.response.delay==49 and item.classification.rule=="attack_counter")
local packet=require("workbench").build({status="ready",capture=capture,damage_items=ds,guard_items=gs,rule_engine=assert(Config.compile(config)),fact_cache=eval},Schema,Context,Rules)
assert(packet.capture.samples==capture.samples and #packet.events==2 and packet.events[1].kind=="guard")
assert(packet.events[2].context.base_rule=="guard_button_counter")
if arg[1] then
    local file=assert(io.open(arg[1],"rb"));local input=assert(json.decode(file:read("*a")));file:close()
    local config=Config.defaults();local dr=require("damage_review");local gr=require("guard_review")
    local d=assert(dr.new(Schema,input.metadata,Rules));local g=assert(gr.new(Schema,input.metadata,Rules,config.settings))
    local full=assert(gr.new(Schema,input.metadata,Rules,{response_frames=120,advantage_min=4}))
    local match=assert(require("match_review").new(Schema,input.metadata,require("candidates")))
    for _,row in ipairs(input.samples) do d:add(row);g:add(row);full:add(row);match:add(row) end
    local windows=match:finish(input.stop_reason=="replay_end")
    local ds=d:finish();local expected=g:finish(windows);local cache=Evaluation.new(input,ds,full:finish(windows),Schema,Rules,Context)
    local actual_damage,actual=cache:evaluate(assert(Config.compile(config)))
    assert(#expected==#actual and #ds==#actual_damage)
    for i,e in ipairs(expected) do local a=actual[i];assert(Config.equal(e.response,a.response));assert(e.candidate==a.candidate) end
    for i,e in ipairs(ds) do assert(Config.equal(e.classification,actual_damage[i].classification) and e.damage==actual_damage[i].damage) end
    print(string.format("Actual capture cache parity: %d damage / %d guard events",#ds,#expected))
end
print("PASS immutable event facts, bounded rule projection and offline evidence transport")
