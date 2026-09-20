package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Saved,Schema=require("saved_capture"),require("schema")
local count=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local function capture(id)
    local columns,row={},{}
    for i,name in ipairs(Schema.columns) do columns[i]=name; row[i]=false end
    for _,name in ipairs({"round","battle_round","replay_frame","stage_frame","thread_id","render_tick"}) do row[Schema.index[name]]=1 end
    return {schema=Schema.version,columns=columns,metadata={replay_id=id,version=20004000},samples={row},sample_count=1,
        state="stopped",stop_reason="left_replay"}
end
local function fixture(files)
    local f={reads={}}
    f.deps={fs={glob=function() local t={}; for name in pairs(files) do t[#t+1]=name end; return t end},
        json={load_file=function(name) f.reads[#f.reads+1]=name; local value=files[name]; if value=="error" then error("broken") end; return value end}}
    function f:run(id)
        local l=Saved.new(self.deps,Schema,id)
        for _=1,1000 do if l:step() then return l end end
        error("loader did not finish")
    end
    return f
end
test("reload selects current replay and preserves incomplete status",function()
    local c=capture("CURRENT")
    local f=fixture({["cfn-capture-20260920-032052.json"]=c,["cfn-capture-20260920-040000.json"]=capture("OTHER")})
    local l=f:run("CURRENT"); eq(l.capture,c); eq(l.capture.stop_reason,"left_replay"); eq(l.error,nil)
end)
test("numbered saves sort numerically after same timestamp base",function()
    local files={}
    for _,suffix in ipairs({"","-2","-10"}) do files["cfn-capture-20260920-032052"..suffix..".json"]=capture("CURRENT") end
    local l=fixture(files):run("CURRENT"); eq(l.path,"cfn-capture-20260920-032052-10.json")
end)
test("unrelated and unsafe names cannot be loaded",function()
    local f=fixture({["../secrets.json"]=capture("CURRENT"),["other.json"]=capture("CURRENT")})
    local l=f:run("CURRENT"); eq(l.error,"saved_missing"); eq(#f.reads,0)
end)
test("invalid matching record cannot replace previous analysis or silently pick older",function()
    for _,mode in ipairs({"schema","columns","empty","count","value","clock","active"}) do
        local c=capture("CURRENT")
        if mode=="schema" then c.schema="OLD" elseif mode=="columns" then c.columns[1]="bad"
        elseif mode=="empty" then c.samples={} elseif mode=="count" then c.sample_count=2
        elseif mode=="value" then c.samples[1][1]={} elseif mode=="clock" then c.samples[1][1]=-1
        else c.state="capturing" end
        local f=fixture({["cfn-capture-20260920-032052.json"]=c,["cfn-capture-20260920-025555.json"]=capture("CURRENT")})
        local l=f:run("CURRENT"); eq(l.capture,nil); eq(l.error,"saved_invalid"); eq(#f.reads,1)
    end
end)
test("unreadable files report failure rather than claiming no recording",function()
    local l=fixture({["cfn-capture-20260920-032052.json"]="error"}):run("CURRENT")
    eq(l.error,"saved_read_failed")
end)
test("ID names coexist with legacy names and choose the latest matching replay",function()
    local c=capture("CURRENT")
    local f=fixture({["cfn-capture-20260920-032052.json"]=capture("CURRENT"),
        ["cfn-capture-CURRENT-20260920-032052-10.json"]=c,
        ["cfn-capture-OTHER-20260921-040000.json"]=capture("OTHER")})
    local l=f:run("CURRENT");eq(l.capture,c);eq(l.path,"cfn-capture-CURRENT-20260920-032052-10.json")
    eq(#f.reads,1)
end)
test("filename ID never replaces the identity check inside the file",function()
    local l=fixture({["cfn-capture-CURRENT-20260920-032052.json"]=capture("OTHER")}):run("CURRENT")
    eq(l.capture,nil);eq(l.error,"saved_missing")
end)
print(count.." CFN saved-record tests passed")
