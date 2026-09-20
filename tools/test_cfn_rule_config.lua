package.path="tools/cfn_replay_capture/?.lua;"..package.path
package.loaded["func/CFNReplayCapture/schema"]=require("schema")
local R=require("rule_config")
local J=require("tools/training_record_bank/vendor/dkjson")
if arg[1]=="--json" then
 local requests=assert(J.decode(io.read("*a")))
 local out={}
 for _,r in ipairs(requests) do
  local valid=R.validate(r.document)
  local value=valid and R.matches(r.document.rules[1].when,r.context or {})
  out[#out+1]={valid=valid,result=value==nil and "unknown" or value}
 end
 print(assert(J.encode(out)));return
end
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local doc=R.defaults();eq(R.validate(doc),true)
local file=assert(io.open("tools/cfn_replay_capture/profiles/system-default.json","rb"))
local system=assert(J.decode(file:read("*a")));file:close()
assert(R.validate(system));eq(system.include_system,true);eq(#system.rules,0)
assert(R.equal(system.settings,doc.settings));eq(assert(R.compile(system)):includes({priority="P0",human_review={}}),true)
doc.include_system=false;eq(R.validate(doc),true)
local strict=assert(R.compile(doc));eq(strict:includes({}),false)
eq(strict:includes({human_review={},priority="P0"}),false)
eq(strict:includes({custom_rule={id="matched"}}),true)
doc.include_system="false";eq(R.validate(doc),false)
doc.include_system=nil;eq(R.validate(doc),true);eq(assert(R.compile(doc)):includes({}),true)
doc.rules={{id="test",title="待回看",enabled=true,scope="damage",priority="P2",when={all={{field="damage",op="ge",value=1000},{field="punish",op="eq",value=true}}}}}
local engine=assert(R.compile(doc))
eq(engine:match("damage",{damage=1200,punish=true}).id,"test")
eq(engine:match("guard",{damage=1200,punish=true}),nil)
eq(engine:match("damage",{damage=1200}),nil)
doc.rules[1].when.all[1].value=2000
eq(engine:match("damage",{damage=1200,punish=true}).id,"test")
eq(R.matches({["not"]={field="punish",op="eq",value=true}},{}),nil)
eq(R.matches({field="damage",op="missing"},{}),true)
eq(R.matches({any={{field="damage",op="missing"},{field="punish",op="eq",value=true}}},{}),true)
eq(R.matches({all={{field="damage",op="ge",value=1000},{field="punish",op="eq",value=true}}},{damage=1}),false)
doc.rules[1].priority="P0";eq(R.validate(doc),false);doc.rules[1].priority="P1"
doc.rules[1].when={field="execute",op="eq",value="code"};eq(R.validate(doc),false)
doc.rules[1].when={field="damage",op="ge",value=1/0};eq(R.validate(doc),false)
doc.rules[1].when={all={}};eq(R.validate(doc),false)
doc.rules[1].when={field="damage",op="ge",value=1}
for _=1,8 do doc.rules[1].when={["not"]=doc.rules[1].when} end;eq(R.validate(doc),false)
doc=R.defaults();doc.settings.guard_frames=31;eq(R.validate(doc),false)
local base=require("damage_rules")
local facts={receiver=1,source_observed=2,frame=100,previous_state=29,flags={counter=true},guard_end=84}
eq(base.classify(facts).rule,"attack_counter")
eq(base.with_settings({guard_frames=20}).classify(facts).rule,"guard_button_counter")
assert(#R.fields==294)
print("CFN bounded rules, unknown truth values, immutable snapshots and threshold configuration passed")
