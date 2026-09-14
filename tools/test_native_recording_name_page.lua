package.path="autorun/?.lua;"..package.path
local Page=require("SF6CCTrainingLibrary/NativeRecordingNamePage")
local serial,requests,capacity=0,{},80
local function make(_,title,enabled,children,guide,readonly)
    serial=serial+1
    local o={id=serial,title=title,readonly=readonly}
    function o:get_address() return self.id end
    function o:set_field(k,v) self[k]=v end
    return o
end
local library={slot_capacity=function() return capacity end,slot_name=function(i) return "name"..i end,
    has_pending=function() return false end}
local page=Page.new(make,function(a) return a end,library,{request=function(i) requests[#requests+1]=i; return true end})
local root=page.open()
for p=1,10 do
    assert(#root._ChildData==12)
    assert(root._ChildData[2].title():find("name"..((p-1)*8+1),1,true))
    assert(not page.active(root._ChildData[1],root))
    assert(page.active(root._ChildData[10],root)==(p>1))
    assert(page.active(root._ChildData[11],root)==(p<10))
    if p<10 then assert(page.handle(root._ChildData[11],root)); root=page.current() end
end
local last=root._ChildData[9]
local yes,close=page.handle(last,root)
assert(yes and close and requests[1]==80 and page.current()==nil)
root=page.open(); yes,close=page.handle(root._ChildData[2],root)
assert(yes and close and requests[2]==1,"first eight slots must be renameable")
capacity=8; root=page.open(); assert(not page.active(root._ChildData[11],root))
assert(not page.owns(last,root))
assert(page.handle(root._ChildData[12],root) and page.current()==nil)
print("PASS name picker: eighty fixed names, ten bounded pages, protected ownership and back")
