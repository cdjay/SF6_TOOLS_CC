package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Schema=require("schema");package.loaded["func/CFNReplayCapture/schema"]=Schema
local Config,Context,Rules,Assess=require("rule_config"),require("rule_context"),require("damage_rules"),require("review_assessments")
local function row(frame)
 local r={};for i in ipairs(Schema.columns) do r[i]=false end
 for k,v in pairs({round=0,battle_round=0,replay_frame=frame,stage_frame=frame,fight_st=4,["p1.vital_new"]=7000,["p1.vital_max"]=10000,["p1.x_raw"]=65536,["p2.x_raw"]=655360,["p1.pl_input_new"]=4,["p1.facing_right"]=1}) do r[Schema.index[k]]=v end
 return r
end
local capture={metadata={version=20004000,players={{fighter_id=21,control_mode=1},{fighter_id=32,control_mode=0}}},samples={row(100),row(101)}}
local item={id=1,round=0,frame=101,last_frame=105,receiver=1,damage=1000,facts={source_observed=2,flags={punish=true},attack_start_observed=true},classification={rule="attack_punished",title="旧标题",level="observed"}}
local ctx=Context.new(capture,Schema,Rules)(item,"damage")
assert(ctx.distance==9 and ctx["self.current.health_pct"]==70 and ctx["self.previous.back"]==true and ctx["self.current.drive_pct"]==nil)
assert(ctx.contact_seen==false and ctx.native_advantage==nil and ctx.round==1 and ctx.duration==5)
local doc=Config.defaults();doc.rules={{id="test",title="用户规则",enabled=true,scope="damage",priority="P1",when={field="damage",op="ge",value=1000}}}
Context.apply(assert(Config.compile(doc)),Context.new(capture,Schema,Rules),{item},"damage")
assert(item.damage==1000 and item.classification.title=="用户规则" and item.classification.level=="inferred")
local assessed=Assess.build({item},capture,{},nil,Schema);assert(assessed[1].priority=="P1" and not assessed[1].human_review)
capture.samples={row(99),row(101)};ctx=Context.new(capture,Schema,Rules)(item,"damage");assert(ctx["self.previous.health_pct"]==nil)
local g={round=0,frame=101,receiver=1,damage=0,complete=true,response={reason="new_reaction"}}
ctx=Context.new(capture,Schema,Rules)(g,"guard");assert(ctx.response_observed==nil)
if arg[1] then
 local file=assert(io.open(arg[1],"rb"));local raw=file:read("*a");file:close()
 local input=assert(require("tools/training_record_bank/vendor/dkjson").decode(raw))
 local schema={columns=input.columns,index={}};for i,name in ipairs(input.columns) do schema.index[name]=i end
 local Review=require("damage_review");local original=assert(Review.new(schema,input.metadata,Rules))
 local configured=assert(Review.new(schema,input.metadata,Rules.with_settings(Config.defaults().settings)))
 for _,r in ipairs(input.samples) do original:add(r);configured:add(r) end
 original:finish();configured:finish();assert(not original.error and not configured.error)
 assert(#original.items==#configured.items)
 for i,a in ipairs(original.items) do local b=configured.items[i];assert(a.damage==b.damage and a.classification.rule==b.classification.rule and a.review_frame==b.review_frame) end
 local context=Context.new(input,schema,Rules)
 local profile=Config.defaults();profile.rules={{id="all_damage",title="自定义复核",enabled=true,scope="damage",priority="P2",when={field="damage",op="gt",value=0}}}
 Context.apply(assert(Config.compile(profile)),context,configured.items,"damage")
 local total=0;for i,item in ipairs(configured.items) do assert(item.custom_rule and item.damage==original.items[i].damage);total=total+item.damage end
 print(string.format("Capture defaults/custom parity: %d groups, %d HP loss unchanged",#configured.items,total))
end
print("CFN custom evidence contexts preserve gaps, unknown resources, damage totals and confirmation boundaries")
