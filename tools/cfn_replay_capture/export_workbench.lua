-- Developer-only export using the exact runtime analyzers. Not a runtime dependency.
package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Schema=require("schema")
package.loaded["func/CFNReplayCapture/schema"]=Schema
local Config,Context,Rules=require("rule_config"),require("rule_context"),require("damage_rules")
local json=require("tools/training_record_bank/vendor/dkjson")
local function read(path)
    local file=assert(io.open(path,"rb"));local text=file:read("*a");file:close()
    local value,_,err=json.decode(text);assert(value,err);return value
end
local input=assert(arg[1],"capture path required")
local output=assert(arg[2],"output path required")
local capture=read(input)
assert(capture.schema==Schema.version and capture.metadata.version==Config.build,"unsupported capture")
assert(#capture.columns==#Schema.columns)
for i,v in ipairs(Schema.columns) do assert(capture.columns[i]==v,"schema mismatch") end
local config=arg[3] and read(arg[3]) or Config.defaults()
local engine=assert(Config.compile(config))
local rules=Rules.with_settings(engine.document.settings)
local damage=assert(require("damage_review").new(Schema,capture.metadata,rules))
local guard=assert(require("guard_review").new(Schema,capture.metadata,rules,engine.document.settings))
local match=assert(require("match_review").new(Schema,capture.metadata,require("candidates")))
for _,row in ipairs(capture.samples) do damage:add(row);guard:add(row);match:add(row) end
local windows=match:finish(capture.stop_reason=="replay_end")
local ds,gs=damage:finish(),guard:finish(windows)
assert(not damage.error and not guard.error and not match.error,damage.error or guard.error or match.error)
local context=Context.new(capture,Schema,Rules)
Context.apply(engine,context,ds,"damage");Context.apply(engine,context,gs,"guard")
local packet=require("workbench").build({status="ready",capture=capture,damage_items=ds,guard_items=gs,
 rule_engine=engine,rule_name=engine.document.name},Schema,Context,Rules)
setmetatable(packet.events,{__jsontype="array"})
setmetatable(packet.config.rules,{__jsontype="array"})
local file=assert(io.open(output,"wb"));assert(file:write(assert(json.encode(packet))));file:close()
print(string.format("Exported %d samples and %d events",#capture.samples,#packet.events))
