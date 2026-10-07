package.path="autorun/?.lua;"..package.path
local Feedback=require("SF6CCTrainingLibrary/NativeLibraryFeedback")
local messages,requests={},0
local pending=false
local library={status="就绪",status_ok=true,result_revision=0}
function library.has_pending() return pending end
function library.request()
    requests=requests+1
    library.status_ok=false; library.status="请先停止录制、播放或连段训练"
    return false
end
local ticker={enqueue=function(text) messages[#messages+1]=text; return true end,
    tick=function() end,clear=function() end}
local f=Feedback.new(library,ticker)
assert(not f.request("save") and #messages==1 and requests==1)
assert(messages[1]:find("停止录制",1,true))
f.tick(true); assert(#messages==1,"same failure repeated every frame")
assert(not f.request("save") and #messages==2,"repeat click must get feedback")
pending=true
assert(not f.request("save") and requests==2)
assert(messages[#messages]:find("尚未完成",1,true))
pending=false; library.status="已保存：测试.json"; library.status_ok=true
library.result_revision=1; f.tick(true)
assert(messages[#messages]:find("已保存",1,true))
local n=#messages
for _=1,120 do f.tick(true) end
assert(#messages==n)
library.result_revision=2; f.tick(true)
assert(#messages==n+1,"a later identical completion needs a new message")
f.tick(false); library.status="环境改变，操作已取消"; f.tick(false)
assert(#messages==n+1,"offline status emitted into another scene")
f.tick(true); assert(#messages==n+1,"stale exit status replayed on entry")
library.status="已清空 80 个录像栏位和 30 个反击栏位。自动备份：data/private.json。reversal setters applied"
local details={}
log={info=function(text) details[#details+1]=text end}
library.status_ok=true; library.result_revision=3; f.tick(true)
assert(messages[#messages]=="录像和反击已清空", "raw clear details leaked into the native message")
assert(details[1]:find(library.status,1,true),"full details missing from log")
log.info=function() error("log unavailable") end
library.result_revision=4; f.tick(true)
assert(messages[#messages]=="录像和反击已清空","logging failure suppressed feedback")
log=nil
local queued="已排队，关闭游戏暂停菜单后执行"
local function scenario(wait_text,done_text,expected,via_native)
    local messages,open,reads={},false,0
    local lib={status="就绪",status_ok=true,result_revision=0}
    lib.has_pending=function() return false end
    lib.request=function() lib.status=wait_text; return true end
    local f=Feedback.new(lib,{enqueue=function(text) messages[#messages+1]=text end,tick=function() end},
        {pause_open=function() reads=reads+1; return open end})
    local function request()
        local before=reads
        if via_native then assert(f.request("save")) else lib.request() end
        assert(reads==before,"menu callback queried native pause state")
    end
    request()
    for _=1,5 do f.tick(true) end
    assert(#messages==0,"closed pause menu got a close-menu instruction")
    lib.status=done_text; lib.result_revision=1; f.tick(true)
    assert(#messages==1 and messages[1]==expected)
    -- Native action returns the menu-close result before the next safe update.
    messages={}; open=true; request(); open=false
    f.tick(true); lib.status=done_text; lib.result_revision=2; f.tick(true)
    assert(#messages==1 and messages[1]==expected,"automatic close emitted redundant waiting")
    -- Native close animations may take arbitrarily many updates. A native
    -- accepted action must never instruct the user to perform its own close.
    messages={}; open=true; request()
    local before=reads
    for _=1,120 do f.tick(true) end
    local reminders=via_native and 0 or 1
    assert(#messages==reminders,"native auto-close emitted a premature close instruction")
    if via_native then assert(reads==before,"native auto-close polled for a manual reminder")
    else assert(messages[1]:find("关闭",1,true)) end
    lib.status_ok=false; lib.status="清空未完成，请查看日志及自动备份"; f.tick(true)
    assert(#messages==reminders+1 and messages[#messages]:find("未完成",1,true),"waiting hid a subsequent failure")
    messages={}; lib.status_ok=true; open=true; request()
    for _=1,120 do f.tick(true) end
    open=false; f.tick(true)
    lib.status=done_text; lib.result_revision=3; f.tick(true)
    assert(#messages==reminders+1 and messages[#messages]==expected,"slow close lost the final result")
    messages={}; lib.status_ok=true; open=nil; request()
    for _=1,5 do f.tick(true) end
    assert(#messages==0,"unknown pause state guessed open")
    open=true; f.tick(false); lib.status="就绪"; f.tick(false); f.tick(true)
    assert(#messages==0,"old reminder survived scene exit")
end
scenario(queued,"已保存：测试.json","配置已保存",true)
scenario(queued,"已保存：测试.json","配置已保存",false)
do
    local queue,open={},true
    local lib={status="就绪",status_ok=true,result_revision=0}
    local f=Feedback.new(lib,{
        enqueue=function(text) queue[#queue+1]=text end,
        discard=function(text)
            for i=#queue,1,-1 do if queue[i]==text then table.remove(queue,i) end end
        end,
        tick=function() end,
    },{pause_open=function() return open end})
    lib.status=queued; f.tick(true); f.tick(true)
    assert(#queue==1)
    open=false; f.tick(true)
    assert(#queue==0,"close reminder left waiting in a backed-up ticker queue")
    lib.status="已保存：测试.json"; f.tick(true)
    assert(#queue==1 and queue[1]=="配置已保存")
    lib.status=queued; open=true; f.tick(true); f.tick(true)
    assert(#queue==2)
    lib.status="保存未完成，请检查文件、角色和录像状态；详细原因见日志"
    lib.status_ok=false; f.tick(true)
    assert(#queue==2 and queue[2]:find("保存未完成",1,true),"completion did not replace unsent wait")
end
print("PASS native feedback: rejected/pending/repeated actions, completion, dedup and exit")
do
    local messages={}
    local lib={status="就绪",status_ok=true,result_revision=0}
    local f=Feedback.new(lib,{enqueue=function(text) messages[#messages+1]=text end,tick=function() end})
    lib.status="已导出：private.json"; lib.result_revision=1
    lib.result_configuration={revision=1,title="压制（2）",kind="export"}
    f.tick(true)
    assert(messages[1]=="压制（2） 配置已另存")
    lib.result_revision=2; lib.status="已保存：private.json"
    f.tick(true)
    assert(messages[2]=="配置已保存","old operation title leaked into a new completion")
    for _,message in ipairs(messages) do assert(not message:find("木人库：",1,true)) end
    lib.status="配置名称已确认，关闭弹窗后保存"; f.tick(true)
    assert(#messages==2,"ended input dialog got a close instruction")
    lib.result_revision=3; lib.status="配置名称已保存"
    lib.result_configuration={revision=3,kind="notes",title="新名"}; f.tick(true)
    assert(#messages==3 and messages[3]=="新名 配置名称已修改")
    lib.status="名称已确认，关闭弹窗后应用"; f.tick(true)
    assert(#messages==3,"ended slot dialog got a close instruction")
    lib.result_revision=4; lib.status="栏位名称已修改；请导出配置以保留"; f.tick(true)
    assert(#messages==4 and messages[4]=="栏位说明已修改，请保存或另存配置")
end
