-- Real entry, Library and Panel with fake engine/recording IO; not live-game evidence.
package.path="autorun/?.lua;"..package.path
local fixture=require("tools.fixtures.native_recording_runtime")
local Runtime=require("SF6CCTrainingLibrary/NativeRecordingRuntime")
local Library=require("SF6CCTrainingLibrary/Library")
local f=fixture({native_capacity=80,menu_structs=true})
f.manager.fields._IsSaveReq=false
f.ctx.fighter_name="Mai"
local counts={scans=0,exports=0,imports=0,saves=0,autoload=0}
local in_callback,clicked,panel_open=false,nil,false
local names={}
local records={
    get_context=function() return f.ctx end,
    list_configs=function() counts.scans=counts.scans+1; return {{path="configs/mai.json",filename="mai.json"}} end,
    read_config_metadata=function() return {title="Mai test",fighter_id=28,fighter_name="Mai",record_slots=80} end,
    reset_slot_names=function() names={} end,
    get_slot_name=function(slot) return names[slot] or "" end,
    get_record_capacity=function() return f.fighter.fields.RecordSlots:get_size() end,
}
local function assert_job()
    assert(in_callback and f.ctx.menu_closed and f.ctx.busy==false,"native IO escaped closed-menu update")
end
records.export_new=function() assert_job(); counts.exports=counts.exports+1; return true,"exported","configs/mai.json" end
records.save_current=function() assert_job(); counts.saves=counts.saves+1; return true,"saved","configs/mai.json" end
records.begin_import=function(path)
    assert_job(); counts.imports=counts.imports+1; names[9]="Mai test slot9"
    return true,"imported",path,nil,{kind="import",written=80,cleared=0,reversals=30,apply_state="applied"}
end
local library=Library.new(records,function() return f.ctx end,{
    load=function() return {["28"]="configs/mai.json"} end,save=function() return true end})
local real_autoload=library.autoload
library.autoload=function(...) counts.autoload=counts.autoload+1; return real_autoload(...) end
local State={}
local api=setmetatable({},{__index=f.api})
api.get_managed_singleton=function(kind)
    assert(kind=="app.storage.SaveManager"); return {call=function() return false end}
end
local modules={
    ["SF6CCTrainingLibrary/State"]=State,["SF6CCTrainingLibrary/Records"]=records,
    ["SF6CCTrainingLibrary/Library"]={shared=function() return library end,runtime_context=function() return f.ctx end},
    ["SF6CCTrainingLibrary/NativeRecordingRuntime"]=Runtime,
}
local noop=function() end
local update,draw,reset
local logs,errors={},{}
local env=setmetatable({},{__index=_G}); env._G=env
env.sdk=api; env.thread=f.threads
env.log={info=function(v) logs[#logs+1]=v end,error=function(v) errors[#errors+1]=v end}
env.imgui={text=noop,text_colored=noop,same_line=noop,tree_pop=noop,
    combo=function() return false,library.selected end,small_button=function() return false end,
    button=function(label) return label==clicked end,
    tree_node=function(label) return panel_open and label=="木人库（独立插件）" end}
env.re={on_pre_application_entry=function(name,fn) assert(name=="LateUpdateBehavior" and not update); update=fn end,
    on_draw_ui=function(fn) assert(not draw); draw=fn end,on_script_reset=function(fn) assert(not reset); reset=fn end}
env.require=function(name)
    if modules[name] then return modules[name] end
    assert(name=="SF6CCTrainingLibrary/Panel","unexpected editor/root/legacy dependency: "..name)
    modules[name]=assert(loadfile("autorun/"..name..".lua","t",env))()
    return modules[name]
end
local entry=assert(loadfile("autorun/SF6CC_TrainingLibrary.lua","t",env))
entry(); entry()
assert(counts.scans==0 and f.native_work.allocations==0,"startup read configurations or allocated native data")
local function tick(n)
    for _=1,n or 1 do in_callback=true; update(); in_callback=false end
end
tick(225)
assert(State.runtime.state()=="active" and counts.autoload==0 and counts.imports==0 and counts.scans==0)
assert(library.status:find("80",1,true),"runtime status did not reach the shared panel")
local bank=f.fighter.fields.RecordSlots
panel_open=true; f.ctx.menu_closed=false; clicked="导出配置"; draw(); clicked=nil
assert(library.has_pending() and counts.exports==0,"drawing executed a configuration job")
tick(5); assert(counts.exports==0,"open native menu did not defer export")
f.ctx.menu_closed=true; tick()
assert(counts.exports==1 and not library.has_pending() and f.fighter.fields.RecordSlots==bank)
for _,pair in ipairs({{"导入配置","imports"},{"保存当前配置","saves"}}) do
    clicked=pair[1]; draw(); clicked=nil
    assert(counts[pair[2]]==0)
    tick(); assert(counts[pair[2]]==1)
end
assert(library.slot_name(9)=="Mai test slot9","imported names not shared with native display")
local scans=counts.scans
for _=1,100 do draw() end
assert(counts.scans==scans,"panel redraw rescanned configuration files")
assert(library.request("save"))
f.call("Release",f.manager.id,0); f.ctx.allowed=false; tick(45)
assert(not library.has_pending() and counts.saves==1 and State.runtime.state()=="unloaded")
f.ctx.allowed=true; tick(225)
assert(State.runtime.state()=="active" and counts.imports==1 and counts.autoload==0)
assert(library.slot_name(9)=="","previous session names leaked into new session")
assert(#errors==0,table.concat(errors,"\n"))
assert(library.request("save"))
reset(); tick(2)
assert(not library.has_pending() and counts.saves==1 and State.runtime.state()=="stopped")
assert(#errors==1 and errors[1]:find("脚本已停止",1,true),table.concat(errors,"\n"))
print("PASS manual-library entry: no autoload, shared status/names, closed-menu queue, import/save/export, cached panel, exit cancellation, reentry, Reset abandonment (fake SDK)")
