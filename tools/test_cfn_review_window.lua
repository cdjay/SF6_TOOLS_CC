package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Model,Window=require("review_model"),require("review_window")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function fixture(stats,popups)
    local f={texts={},click=nil,located={},holds=0,windows=0,tables=0,headers={},selects={},buttons={}}
    local model,w=Model.new()
    w=Window.new(model,stats,require("guard_window").new(),popups)
    local a={status="ready",damage_items={},capture={metadata={replay_id="A",round_count=3}},
        damage_review={rounds={{round=0},{round=1},{round=2}},by_round={[0]={},[1]={},[2]={}}}}
    for round=0,2 do for i=1,24 do
        a.damage_items[#a.damage_items+1]={id=round*24+i,round=round,frame=500+i,review_frame=480+i,
            priority=i%2==0 and "P2" or "P3",receiver=i<=12 and 1 or 2,damage=i*100,
            native_advantage=i%2==0 and {value=-i,frame=480+i} or nil,
            classification={title="出招被对手抢先打断",level="observed"}}
    end end
    function a:start() f.started=true; return true end
    function a:load_saved() f.loaded=true end
    function a:cancel() f.cancelled=true end
    function a:locate_review(item,stable,press) f.located[#f.located+1]=item; eq(stable,1); eq(press,45); return true end
    local c={clock={position={round=0,frame=600},replay_id="A",render_tick=10},snapshot={paused=true}}
    local n={active=false,cancel=function() f.cancelled=true end}
    local rn={start=function(_,target) f.round_target=target; return true end,cancel=function() f.round_cancelled=true end}
    local state={render_tick=10}
    local ui={set_next_window_size=function(size) f.size=size end,set_next_window_pos=function(pos) f.pos=pos end,
        begin_window=function(_,_,flags) assert(flags & (1<<5)~=0); assert(flags & (1<<6)~=0, "height must follow contents"); assert(flags & (1<<3)~=0, "no window scrollbar"); f.windows=f.windows+1; return true end,
        end_window=function() f.windows=f.windows-1 end,text=function(v) f.texts[#f.texts+1]=v end,
        same_line=function() end,push_item_width=function() end,pop_item_width=function() end,
        combo=function(label,index,names) f.names=names; return f.selects[label]~=nil,f.selects[label] or index end,
        button=function(label) f.buttons[label]=true; return f.click==label end,
        begin_table=function(_,columns,flags) eq(columns,5); eq(flags & (1<<25),0); f.tables=f.tables+1; return true end,
        end_table=function() f.tables=f.tables-1 end,table_setup_column=function() end,
        table_setup_scroll_freeze=function() end,table_next_row=function() end,
        table_set_column_index=function() end,table_header=function(v) f.headers[v]=true end,
        table_get_sort_specs=function() return f.specs end,
        menu_item=function(label,_,_,enabled)
            f.menu[#f.menu+1]={label=label,enabled=enabled}
            return f.click and label:match("##.*$")==f.click
        end,is_item_hovered=function() return false end,set_tooltip=function() end}
    function f:draw(sw,sh)
        self.menu,self.texts={},{}
        w:draw(ui,a,c,n,state,{},sw or 1280,sh or 720,function(x,y) return {x=x,y=y} end,
            function() self.holds=self.holds+1 end,rn)
        eq(self.windows,0); eq(self.tables,0)
    end
    f.w,f.model,f.a,f.c,f.n,f.state,f.rn=w,model,a,c,n,state,rn
    f.ui=ui
    return f
end
local x,y=Window.surface_size({get_display_size=function() return {x=1280,y=720} end}); eq(x,1280); eq(y,720)
x,y=Window.surface_size({get_display_size=function() return 1920,1080 end}); eq(x,1920); eq(y,1080)
local f=fixture(); f:draw(); eq(f.model.selected,0); eq(#f.model.items,12); eq(#f.menu,12)
for _,name in ipairs({"发生帧","问题级别","问题描述","伤害","硬直差"}) do assert(f.headers[name]) end
eq(f.headers["跳转"],nil); eq(f.headers["回看起点"],nil); eq(f.buttons["收起##review"],nil); eq(f.buttons[">##review_page"],nil)
f.click="##review_12"; f:draw(); eq(#f.located,1); eq(f.holds,1); eq(f.located[1].id,12)
f.click=nil; f.c.clock.local_side=2; f:draw(); eq(f.model.player,2); eq(f.model.items[1].id,13)
f.selects["##review_player"]=1; f:draw(); eq(f.model.player,1)
f.selects={}; f:draw(); eq(f.model.player,1)
f.selects["##review_priority"]=4; f:draw(); eq(#f.model.items,6)
for _,item in ipairs(f.model.items) do eq(item.priority,"P2") end
f.selects={}; f.specs={specs_dirty=true,get_specs=function() return {{column_index=3,sort_direction=2}} end}
f:draw(); eq(f.model.items[1].damage,1200); eq(f.specs.specs_dirty,false)
f.specs={specs_dirty=true,get_specs=function() return {{column_index=4,sort_direction=1}} end}
f:draw(); eq(f.model.items[1].native_advantage.value,-12)
f.specs={specs_dirty=true,get_specs=function() return {{column_index=0,sort_direction=1}} end}
f:draw(); eq(f.model.items[1].frame,502)
f.specs={specs_dirty=true,get_specs=function() return {{column_index=0,sort_direction=2}} end}
f:draw(); eq(f.model.items[1].frame,512)
f.selects["##review_priority"]=1; f.selects["##review_round"]=2; f:draw()
eq(#f.model.items,12); eq(f.model.selected,1)
for _,cell in ipairs(f.menu) do eq(cell.enabled,false) end
f.click="前往该局"; f:draw(); eq(f.round_target,1)
f.selects={}; f.click=nil; f.c.clock.position.round=1; f:draw(); eq(f.model.selected,1); eq(f.model.player,1)
f.c.clock.replay_id="B"; f:draw(); eq(#f.model.items,0); eq(f.model.player,2)
for _,blocked in ipairs({"paused","active","owner","speed_restore"}) do
    f=fixture(); if blocked=="paused" then f.c.snapshot.paused=false elseif blocked=="active" then f.a.active=true else f.c[blocked]={} end
    f.click="##review_1"; f:draw(); eq(#f.located,0); eq(f.holds,0)
end
f=fixture(); f.click="采集整场事实"; f:draw(); eq(f.started,true); eq(f.holds,1)
f=fixture(); f.click="读取已保存事实##review"; f:draw(); eq(f.loaded,true); eq(f.holds,0)
f=fixture(); f.n.active=true; f.n.status="close_overlay"; f:draw()
assert(table.concat(f.texts," "):find("正在交还按键控制",1,true))
for _,size in ipairs({{1280,720},{1920,1080},{2560,1440}}) do
    f=fixture(); f:draw(size[1],size[2]); assert(f.pos.x>=0 and f.pos.y>=0)
    assert(f.pos.x<=size[1] and f.pos.y<=size[2]); assert(f.size.x<=720); eq(f.size.y,0)
end
f=fixture(); f.state.render_tick=13; f:draw(); eq(f.size,nil)
local drawn={}
local stats={draw=function(_,ui,report,view,round,side,width,vec,callbacks)
    drawn={view=view,round=round,side=side,callbacks=callbacks}
end}
f=fixture(stats);f.selects["##review_view"]=2;f:draw();eq(drawn.round,0);eq(drawn.side,1)
f.selects={["##review_round"]=1};f:draw();eq(drawn.round,nil);eq(f.w.stats_all,true)
f.click="前往该局";f:draw();eq(f.round_target,nil)
f.click=nil;drawn.callbacks.round(2);f.selects={};f:draw();eq(drawn.round,2);eq(f.w.stats_all,false)
f.selects={["##review_view"]=1};f:draw();eq(f.model.selected,2);eq(#f.menu,12)
f.selects={["##review_view"]=3,["##review_player"]=2};f:draw();eq(drawn.side,2)
drawn.callbacks.item(f.a.damage_items[25]);eq(#f.located,0)
f.selects={};drawn.callbacks.round(0);f:draw();drawn.callbacks.item(f.a.damage_items[13]);eq(#f.located,1);eq(f.holds,1)
f=fixture(stats);f.selects={["##review_view"]=6};f.a.guard_items={
    {id=1,round=0,receiver=1,frame=200,guard_end=220,review_frame=215,candidate=true,native_advantage={value=-6,frame=215},response={frame=221,delay=1}},
    {id=2,round=0,receiver=1,frame=300,guard_end=320,review_frame=300,candidate=false,response={reason="limit"}},
    {id=3,round=0,receiver=2,frame=400,guard_end=420,candidate=true},
    {id=4,round=1,receiver=1,frame=500,guard_end=520,candidate=true}}
function f.a:locate_guard(item) f.guard_located=item;return true end
f:draw();eq(#f.menu,2);assert(f.headers["防御结束"]);assert(f.headers["机会线索"])
f.selects={["##guard_filter"]=2};f:draw();eq(#f.menu,1)
package.loaded["func/CFNReplayCapture/schema"]=require("schema")
local Config=require("rule_config");local strict=Config.defaults();strict.include_system=false
f.a.rule_engine=assert(Config.compile(strict));f:draw();eq(#f.menu,0)
f.selects={["##guard_filter"]=1};f:draw();eq(#f.menu,2)
assert(table.concat(f.texts," "):find("未匹配启用规则",1,true))
f.a.guard_items[1].custom_rule={id="matched"};f.selects={["##guard_filter"]=2};f:draw();eq(#f.menu,1)
f.a.rule_engine=nil
f.click="##guard_1";f:draw();eq(f.guard_located.frame,200);eq(f.holds,1)
f.click=nil;f.selects={["##guard_filter"]=1};f.specs={specs_dirty=true,get_specs=function() return {{column_index=0,sort_direction=2}} end}
f:draw();assert(f.menu[1].label:find("300",1,true))
f.guard_located=nil;f.selects={["##review_round"]=2};f.click="##guard_4";f:draw();eq(f.guard_located,nil)
f.click="前往该局";f:draw();eq(f.round_target,1)
f=fixture();f.a.damage_items[1].native_snapshot={value=29,frame=501}
f.ui.is_item_hovered=function() return true end;local tips={};f.ui.set_tooltip=function(s) tips[#tips+1]=s end
f:draw();assert(table.concat(f.texts," "):find("未关联",1,true));assert(table.concat(tips," "):find("+29",1,true))
local popup_round
f=fixture(nil,{buttons=function(_,ui,round) popup_round=round end})
f:draw();eq(popup_round,0);eq(f.w.view,1);eq(#f.menu,12)
f.selects={["##review_view"]=2};f:draw();eq(f.w.view,6)
f.selects={["##review_view"]=1};f:draw();eq(f.w.view,1);eq(#f.menu,12)
f.a.rule_engine=assert(Config.compile(strict));f:draw();eq(#f.menu,0)
assert(table.concat(f.texts," "):find("当前配置尚未启用问题规则",1,true))
print("CFN compact review window, filters, sort, all rows and round request tests passed")
