local Speed=dofile("tools/cfn_replay_capture/replay_speed.lua")
local names={"0_5","0_6","0_7","0_8","0_9","1_0","1_1","1_2","1_3","1_4","1_5","2_0","4_0","8_0"}
local ids={}; for i,name in ipairs(names) do ids[tonumber((name:gsub("_",".")))]=i-1 end
local M=Speed.new({find_type_definition=function() return {get_field=function(_,name)
    local id=ids[tonumber((name:gsub("Speed_",""):gsub("_",".")))]
    return id and {get_data=function() return id end}
end} end})
local count=0
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn(); count=count+1; print("PASS "..name) end
local function fixture(values)
    local f={calls={}}
    f.ui={get_field=function(_,name)
        if name=="_CurretSpeed" then return f.index end
        eq(name,"_ReplaySpeeds")
        return {get_size=function() return #values end,get_element=function(_,i)
            return {get_field=function(_,field) eq(field,"Speed"); return ids[values[i+1]] end,
                call=function(_,method) eq(method,"GetSpeedValue"); return 0.5 end} end}
        end,
        call=function(_,method,index,remember)
            f.calls[#f.calls+1]={method,index,remember}
            if method=="CanChangedSpeed(System.Int32)" then return not f.reject end
            eq(method,"ChangeSpeed(System.Int32, System.Boolean)"); eq(remember,true)
        end}
    return f
end
test("native speed list determines index not hardcoded multiplier or number of presses",function()
    for _,values in ipairs({{0.5,1,1.1,1.2,1.5,2,4,8},{8,1},{1,8}}) do
        local f=fixture(values); eq(M.set(f.ui,8),true); eq(#f.calls,2)
        eq(values[f.calls[2][2]+1],8)
    end
end)
test("live current eight is read correctly and needs no native write",function()
    local f=fixture({0.5,0.8,1,1.1,1.2,2,4,8}); f.index=7
    eq(M.read(f.ui),8); eq(M.set(f.ui,8),true); eq(#f.calls,0)
end)
test("unknown duplicate and invalid speed refuse writes",function()
    for _,values in ipairs({{1,2,4},{1,8,8}}) do local f=fixture(values); eq(M.set(f.ui,8),false); eq(#f.calls,0) end
    for _,target in ipairs({0,9,-1,"8",0/0,math.huge}) do local f=fixture({1,8}); eq(M.set(f.ui,target),false); eq(#f.calls,0) end
end)
test("native refusal never calls ChangeSpeed",function()
    local f=fixture({1,8}); f.reject=true
    local ok,reason=M.set(f.ui,8); eq(ok,false); eq(reason,"speed_change_denied"); eq(#f.calls,1)
end)
test("missing ambiguous unknown and invalid indices do not masquerade as half speed",function()
    local f=fixture({1,2,4}); local ok,reason=M.set(f.ui,8)
    eq(ok,false); eq(reason,"speed_target_missing")
    f=fixture({8,8}); ok,reason=M.set(f.ui,8); eq(ok,false); eq(reason,"speed_ambiguous")
    f=fixture({9}); f.index=0; eq(M.read(f.ui),nil)
    for _,index in ipairs({-1,0.5,10}) do f.index=index; eq(M.read(f.ui),nil) end
end)
test("float tolerance cannot promote 7.9 to eight",function()
    eq(M.matches(7.9999995,8),true); eq(M.matches(7.9,8),false); eq(M.matches(nil,8),false)
end)
test("live value-type speed getter cannot hide the eight-times enum entry",function()
    local f=fixture({0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5})
    local original=f.ui.get_field
    local ids={0,3,5,6,7,11,12,13}
    f.ui.get_field=function(self,name)
        if name=="_CurretSpeed" then return 2 end
        local array=original(self,name)
        local element=array.get_element
        array.get_element=function(self,i)
            local item=element(self,i)
            item.get_field=function(_,field) eq(field,"Speed"); return ids[i+1] end
            return item
        end
        return array
    end
    eq(M.set(f.ui,8),true)
    eq(f.calls[2][2],7)
end)
print(count.." CFN native speed tests passed")
