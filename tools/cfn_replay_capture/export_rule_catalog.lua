package.path="tools/cfn_replay_capture/?.lua;"..package.path
package.loaded["func/CFNReplayCapture/schema"]=require("schema")
local rules=require("rule_config")
local json=require("tools/training_record_bank/vendor/dkjson")
local defaults=rules.defaults();setmetatable(defaults.rules,{__jsontype="array"})
local schema=require("schema")
print(assert(json.encode({schema=rules.schema,build=rules.build,fields=rules.fields,settings=rules.settings,builtins=rules.builtins,defaults=defaults,
 capture_schema=schema.version,columns=schema.columns})))
