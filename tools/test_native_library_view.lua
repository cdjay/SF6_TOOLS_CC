package.path="autorun/?.lua;"..package.path
local View=require("SF6CCTrainingLibrary/NativeLibraryView")
local pending=false
local lib={entries={},revision=1,selected=1}
for i=1,256 do lib.entries[i]={path="config/"..i,label="不知火舞[配置"..i.."]",metadata={fighter_id=28,source_player="P2"}} end
lib.selection=function() return lib.entries[lib.selected] end
lib.selection_label=function(i) local e=lib.entries[i or lib.selected]; return e and e.label or "暂无配置" end
lib.selection_details=function() return {character="不知火舞",slots="有效录像 6/80",saved="今天"} end
lib.has_pending=function() return pending end
lib.select=function(i) if pending or not lib.entries[i] then return false end; lib.selected=i; return true end
local v=View.new(lib)
v.set_context({allowed=true,fighter_id=28})
assert(#v.rows()==13 and v.command(1)=="open")
assert(v.command(3)=="save" and v.command(4)=="export" and v.command(7)=="clear")
local first_clear=v.activate(7)
assert(first_clear.redraw and not first_clear.notice and not first_clear.operation,"first clear confirmation must only update its row")
assert(v.rows()[7].text=="【再次确认清空】清空所有栏位")
assert(v.activate(7).operation=="clear")
assert(v.rows()[7].text=="清空所有栏位")
assert(not v.activate(7).operation,"successful confirmation must be consumed")
v.cancel_confirmation(); assert(not v.activate(7).operation,"cancel must discard clear confirmation")
v.activate(4); assert(not v.activate(7).operation,"another action must discard clear confirmation")
v.closed(); assert(not v.activate(7).operation,"closing must discard clear confirmation")
pending=true; assert(not v.activate(7).operation); pending=false
assert(not v.activate(7).operation,"busy state must discard clear confirmation")
v.cancel_confirmation(); assert(v.rows()[7].text=="清空所有栏位")
assert(v.rows()[1].text=="切换配置【当前："..lib.selection_label().."】")
assert(v.rows()[4].text=="另存当前配置" and v.rows()[7].text=="清空所有栏位")
assert(v.rows()[5].text=="修改当前配置名称" and v.rows()[6].text=="修改栏位说明")
assert(v.command(5)==nil and v.command(6)==nil,"unavailable editors must not execute")
assert(v.rows()[2].kind==4 and v.rows()[8].kind==4 and v.rows()[2].text=="" and v.rows()[8].readonly)
assert(v.rows()[9].text=="<color A8DEFF>配置信息</color>")
for i=9,12 do assert(v.rows()[i].text:match("^<color A8DEFF>.*</color>$")) end
for _,row in ipairs(v.rows()) do assert(row.command~="backup" and row.command~="restore" and row.command~="refresh" and row.command~="reload") end
assert(v.activate(1).redraw)
for i,row in ipairs(v.rows()) do assert(row.kind==(i==10 and 1 or 0),"catalog must restore its native row variants") end
assert(v.rows()[10].text=="页码" and v.rows()[11].text=="" and v.command(10)=="page")
assert(v.paging().count==32 and v.paging().index==0 and v.paging().label=="1 / 32")
assert(v.rows()[12].command=="refresh")
for p=1,32 do
    local rows=v.rows(); assert(#rows==13)
    for i=2,9 do assert(rows[i].index==(p-1)*8+i-1) end
    if p<32 then assert(v.set_page(p)) end
end
assert(v.command(11)==nil and v.activate(11).operation==nil)
assert(v.activate(9).redraw and lib.selected==256)
assert(v.rows()[9].text:find("再次确认导入",1,true))
assert(v.activate(9).operation=="import")
assert(v.activate(9).redraw,"completion must consume armed confirmation")
assert(v.set_page(30)); assert(not v.rows()[9].text:find("再次确认",1,true))
v.activate(13); v.activate(1)
assert(v.activate(2).redraw and v.activate(3).redraw)
assert(v.activate(2).operation==nil,"different row imported on first confirmation")
lib.select(3)
assert(v.activate(2).operation==nil,"external selection reused old confirmation")
v.closed(); v.activate(1)
assert(v.activate(2).operation==nil,"menu close reused old confirmation")
lib.revision=2
table.remove(lib.entries,1)
local r=v.activate(2)
assert(r.notice=="配置列表已变化，请重新选择" and r.redraw and not r.operation)
assert(v.activate(2).redraw and v.activate(2).operation=="import")
pending=true
assert(v.activate(3).notice and not v.activate(3).operation)
pending=false
assert(v.activate(12).operation=="refresh")
lib.entries={}; lib.selected=1; lib.revision=3
v.closed(); v.activate(1)
assert(v.rows()[2].text=="<color A8DEFF>当前角色暂无配置</color>" and v.command(2)==nil and v.command(12)=="refresh")
assert(v.paging()==nil and v.rows()[10].text=="" and v.command(10)==nil)
assert(v.activate(13).redraw and v.command(1)=="open")
lib.entries={
    {path="bison",label="维嘉",metadata={fighter_id=26}},
    {path="mai-a",label="舞 A",metadata={fighter_id="28",source_player="P2"}},
    {path="missing",label="未知",metadata={}},
    {path="mai-p1",label="舞 P1",metadata={fighter_id=28,source_player="P1"}},
    {path="mai-b",label="舞 B",metadata={fighter_id=28}},
}
lib.selected=1; lib.revision=4
lib.options={reject_fighter_mismatch=false}
v.closed()
assert(v.rows()[1].text=="切换配置【当前：未选择配置】" and v.command(3)==nil)
v.activate(1)
assert(v.rows()[2].text=="舞 A" and v.rows()[3].text=="舞 B" and v.command(4)==nil)
assert(v.paging()==nil and not v.set_page(1),"single-page catalog must not expose arrows")
assert(v.activate(3).redraw and lib.selected==5,"filtered row must select original catalog index")
assert(v.activate(3).operation=="import")
v.closed(); v.activate(1); v.activate(2)
v.set_context({allowed=true,fighter_id=26})
assert(v.command(1)=="open","character change must discard old list and confirmation")
v.activate(1)
assert(v.rows()[2].text=="维嘉" and v.command(3)==nil)
assert(v.activate(2).redraw and lib.selected==1 and v.activate(2).operation=="import")
for _,ctx in ipairs({{allowed=true,error=true,fighter_id=28},{allowed=false,fighter_id=28},{allowed=true}}) do
    v.set_context(ctx); v.closed(); v.activate(1)
    assert(v.command(2)==nil and v.rows()[2].text=="<color A8DEFF>当前角色暂无配置</color>")
end
v.set_context({allowed=true,fighter_id=28}); v.activate(1); v.activate(2)
lib.entries[2].metadata.fighter_id=26
assert(v.activate(2).notice and not v.rows()[2].text:find("舞 A",1,true),"mismatched live entry reused confirmation")
local available=false
local editing=View.new(lib,function() return available end)
editing.set_context({allowed=true,fighter_id=28}); lib.selected=5
assert(editing.command(5)==nil)
available=true
assert(editing.command(5)=="rename" and editing.activate(5).operation=="rename")
assert(editing.command(6)==nil,"missing slot capability must disable the browser")
pending=true; assert(editing.activate(5).notice and not editing.activate(5).operation); pending=false
lib.selected=1; assert(editing.command(5)==nil,"foreign-character configuration is not editable here")
local capacity,names,editable,reads=80,{[1]="压制",[9]="截空",[80]="反击"},true,0
lib.slot_capacity=function() reads=reads+1; return capacity end
lib.slot_name=function(i) return names[i] or "" end
lib.can_edit_slot_names=function() return editable end
local frame_reads=0
local live_frames={}
for i=1,80 do live_frames[i]=0 end
live_frames[1]=55; live_frames[2]=167; live_frames[9]=262; live_frames[80]=118
lib.record_frames=function()
    frame_reads=frame_reads+1
    local result={}; for i=1,capacity do result[i]=live_frames[i] end
    return {fighter_id=28,frames=result}
end
local context={allowed=true,fighter_id=28,session=1,data="a"}
editing.set_context(context)
local before=reads
local before_frames=frame_reads
assert(editing.command(6)=="open_slots" and editing.activate(6).redraw)
assert(editing.pager_row()==1 and editing.command(1)=="page" and editing.rows()[1].text=="页码")
assert(editing.command(10)=="back" and editing.rows()[10].text=="返回")
for i=11,13 do assert(editing.rows()[i].text=="" and editing.command(i)==nil) end
assert(editing.rows()[2].text=="栏位1：压制（55帧）")
assert(editing.rows()[3].text=="栏位2：栏位2（167帧）")
assert(editing.rows()[4].text=="<color 999999>栏位3：栏位3（ - ）</color>")
assert(not editing.rows()[4].readonly and editing.activate(4).slot==3,"gray empty slot must remain editable")
local selected=lib.selected
for p=1,10 do
    local rows=editing.rows()
    assert(#rows==13 and rows[12].readonly and not rows[12].command)
    for i=2,9 do
        local r=editing.activate(i)
        assert(r.operation=="slot_name" and r.slot==(p-1)*8+i-1 and not r.redraw)
        assert(rows[i].index==r.slot and rows[i].kind==0)
    end
    if p==2 then assert(rows[2].text=="栏位9：截空（262帧）") end
    if p<10 then assert(editing.set_page(p)) end
end
assert(editing.rows()[9].text=="栏位80：反击（118帧）" and editing.command(11)==nil)
assert(reads==before and lib.selected==selected,"navigation queried native capacity or changed configuration")
assert(frame_reads==before_frames,"navigation read native frames instead of the captured snapshot")
pending=true; assert(editing.activate(9).notice and not editing.activate(9).operation); pending=false
available=false; assert(editing.command(9)==nil); available=true
editable=false; assert(editing.command(9)==nil); editable=true
assert(editing.set_page(8) and editing.rows()[2].index==65)
for _,invalid in ipairs({-1,10,0.5,"1"}) do assert(not editing.set_page(invalid)) end
pending=true; assert(not editing.set_page(0)); pending=false
assert(editing.activate(10).redraw and editing.command(6)=="open_slots" and editing.pager_row()==10)
lib.entries={}; lib.selected=1
assert(editing.activate(6).redraw,"unsaved recordings must still be editable")
names[1]="新压制"; editing.closed(); editing.set_context(context); editing.activate(6)
assert(editing.rows()[2].text=="栏位1：新压制（55帧）","reopen failed to capture edited name")
live_frames[1]=170
assert(editing.rows()[2].text=="栏位1：新压制（55帧）","open list read mutable live frames")
editing.closed(); editing.set_context(context); editing.activate(6)
assert(editing.rows()[2].text=="栏位1：新压制（170帧）","new unsaved recording was not captured on reopen")
live_frames[1]=0
editing.closed(); editing.set_context(context); editing.activate(6)
assert(editing.rows()[2].text=="<color 999999>栏位1：新压制（ - ）</color>","empty slot must retain its editable name")
assert(not editing.rows()[2].readonly and editing.activate(2).slot==1)
live_frames[1]=55
editing.closed(); editing.set_context(context); editing.activate(6)
assert(editing.rows()[2].text=="栏位1：新压制（55帧）","recording an empty slot must remove its gray text")
local read_frames=lib.record_frames
for _,failure in ipairs({"error","foreign","capacity","invalid"}) do
    lib.record_frames=function()
        if failure=="error" then error("frames unavailable") end
        local snapshot=read_frames()
        if failure=="foreign" then snapshot.fighter_id=26
        elseif failure=="capacity" then table.remove(snapshot.frames)
        else snapshot.frames[1]=-1 end
        return snapshot
    end
    editing.closed(); editing.set_context(context); editing.activate(6)
    assert(editing.rows()[2].text=="栏位1：新压制（帧数暂不可用）")
    assert(editing.activate(2).slot==1,"frame read failure must not disable name editing")
end
lib.record_frames=read_frames
capacity=9; editing.set_context(context)
assert(editing.command(6)=="open_slots","capacity change must invalidate old page")
editing.activate(6); assert(editing.set_page(1))
assert(editing.activate(2).slot==9 and editing.command(3)==nil and editing.command(11)==nil)
capacity=8; editing.closed(); editing.set_context(context); editing.activate(6)
assert(editing.rows()[1].text=="页码 1 / 1" and editing.rows()[1].readonly and editing.paging()==nil)
assert(editing.command(11)==nil and editing.activate(9).slot==8)
context.session=2; editing.set_context(context)
assert(editing.command(1)=="open","new training session retained slot list")
for _,n in ipairs({0,81,8.5,"80"}) do
    capacity=n; editing.set_context(context); assert(editing.command(6)==nil)
end
lib.slot_capacity=function() error("capacity unavailable") end
editing.set_context(context); assert(editing.command(6)==nil and editing.command(4)=="export")
capacity=80; lib.slot_capacity=function() return capacity end
context.allowed=false; editing.set_context(context); assert(editing.command(6)==nil)
print("PASS native library view: fixed rows, 256 configs, double confirm, stale/empty/busy lists and requested layout")
