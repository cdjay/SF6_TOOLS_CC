package.path="tools/cfn_replay_capture/?.lua;"..package.path
local Charts,Stats,Schema=require("statistics_charts"),require("statistics"),require("schema")
package.loaded["func/CFNReplayCapture/statistics_charts"]=Charts
package.loaded["func/CFNReplayCapture/statistics"]=Stats
package.loaded["func/CFNReplayCapture/presentation"]=require("presentation")
local Window=require("statistics_window")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function vec(x,y) return {x=x,y=y} end
local function ui_fixture(width)
    local f={canvas=nil,primitives=0,click=false,hover=false,mouse=vec(0,0),texts={},tables=0,y=10,lines={},colors={},windows=0,style=0,buttons={}}
    local d={}
    local function point(v)
        assert(type(v.x)=="number" and v.x==v.x and type(v.y)=="number" and v.y==v.y)
        local c=assert(f.canvas)
        assert(v.x>=c.x-.01 and v.x<=c.x+c.w+.01,"horizontal canvas overflow")
        assert(v.y>=c.y-.01 and v.y<=c.y+c.h+.01,"vertical canvas overflow")
    end
    function d:add_line(a,b,color) point(a);point(b);f.primitives=f.primitives+1;f.lines[#f.lines+1]={a=a,b=b,color=color};f.colors[color]=true end
    function d:add_rect_filled(a,b,color) point(a);point(b);assert(a.x<=b.x and a.y<=b.y);f.primitives=f.primitives+1;f.colors[color]=true end
    function d:add_circle_filled(a,r) point(vec(a.x-r,a.y-r));point(vec(a.x+r,a.y+r));f.primitives=f.primitives+1 end
    function d:add_triangle_filled(a,b,c) point(a);point(b);point(c);f.primitives=f.primitives+1 end
    local function text_size(text)
        local n=0;for _,cp in utf8.codes(text) do n=n+(cp>127 and 18 or 9) end
        return vec(n,18)
    end
    function d:add_text(pos,_,text) point(pos);local size=text_size(text);point(vec(pos.x+size.x,pos.y+size.y));f.primitives=f.primitives+1 end
    local ui={
        get_cursor_screen_pos=function() return vec(10,f.y) end,
        invisible_button=function(id,size) f.canvas={x=10,y=f.y,w=size.x,h=size.y};f.y=f.y+size.y+4;return f.click end,
        get_window_draw_list=function() return d end,is_item_hovered=function() return f.hover end,
        get_mouse=function() return f.mouse end,set_tooltip=function(t) f.tooltip=t end,calc_text_size=text_size,
        text=function(t) f.texts[#f.texts+1]=t;f.y=f.y+22 end,
        begin_table=function() f.tables=f.tables+1;return true end,end_table=function() f.tables=f.tables-1 end,
        table_setup_column=function() end,table_next_row=function() end,table_set_column_index=function() end,table_header=function() end,
        combo=function(_,current) return false,current end,push_item_width=function() end,pop_item_width=function() end,
        button=function(label) return f.buttons[label] or false end,same_line=function() end,
        push_style_color=function() f.style=f.style+1 end,pop_style_color=function(n) f.style=f.style-n;assert(f.style>=0) end,
        set_next_window_size=function(size) f.size=size end,set_next_window_pos=function(pos) f.pos=pos end,
        begin_window=function(title) f.title=title;f.windows=f.windows+1;return true,true end,
        end_window=function() f.windows=f.windows-1;assert(f.windows>=0) end,
    }
    return ui,f
end
for _,width in ipairs({456,616,696}) do
    local ui,f=ui_fixture(width)
    Charts.bars(ui,"bars",{{label="较长的受伤原因名称用于验证文字边界",value=123,display="123"},{label="unknown",value=0}},width,vec)
    Charts.histogram(ui,"hist",{1,40,9,5,3,0},{"<500","500-999","1000-1999","2000-2999","3000-4999","5000+"},width,vec)
    Charts.boxplot(ui,"box",Stats.distribution({100,200,900,2000}),width,vec)
    Charts.boxplot(ui,"empty",{},width,vec)
    Charts.radar(ui,"radar",{{label="前走",value=.5},{label="后走",value=.2},{label="空中"},{label="出招",value=1},{label="防御",value=0},{label="蓝防",value=.9}},width,vec)
    local y=f.y
    f.click=true;f.hover=true;f.mouse=vec(52+(width-54)/2,y+30)
    eq(Charts.timeline(ui,"line",{{first=191,last=220,first_value=100,value=70,min=60,max=100},{first=230,last=260,first_value=50,value=40,min=40,max=50,connected=false}},width,152,191,291,220,vec),241)
    assert(f.primitives>60)
    f.hover=false;f.click=false
    Charts.paired_bars(ui,"paired",{{label="前走",values={20,45},displays={"20%","45%"}},{label="未知",values={nil,0}}},{1,2},width,vec,100)
    Charts.paired_boxplot(ui,"paired_boxes",{Stats.distribution({0,20,55,60}),Stats.distribution({100,2000})},{1,2},width,vec)
    Charts.paired_boxplot(ui,"empty_boxes",{{},{}},{1,2},width,vec)
    Charts.paired_radar(ui,"paired_radar",{{label="前走",values={20,40}},{label="后走",values={50,10}},{label="空中",values={0,100}},{label="出招",values={10,30}},{label="防御",values={nil,0}},{label="蓝防",values={20,30}}},{1,2},width,vec)
    f.y=10;f.lines={};f.hover=true;f.click=true;f.mouse=vec(52+(width-54)/2,55)
    local series={{{first=191,last=220,first_value=100,value=70,min=60,max=100},{first=260,last=291,first_value=50,value=40,min=40,max=50,connected=false}},
        {{first=191,last=291,first_value=40,value=70,min=40,max=90}}}
    eq(Charts.paired_timeline(ui,"paired_lines",series,{1,2},width,176,191,291,220,vec),241)
    assert(f.colors[Charts.players[1]] and f.colors[Charts.players[2]])
    assert(f.tooltip:find("1P 无记录",1,true) and f.tooltip:find("2P 40.0%～90.0%",1,true))
    local player_lines=0
    for _,line in ipairs(f.lines) do if line.color==Charts.players[1] then player_lines=player_lines+1 end end
    eq(player_lines,2) -- Only intra-cell lines; do not bridge the missing interval.
    f.hover=false;Charts.paired_timeline(ui,"empty_lines",{{},{}},{1,2},width,176,nil,nil,nil,vec)
end
local s=assert(Stats.new(Schema,{version=20004000,replay_id="TEST",players={{fighter_id=21},{fighter_id=32}}}))
for round=0,2 do for frame=191,193 do
    local row={};for i in ipairs(Schema.columns) do row[i]=false end
    local values={round=round,battle_round=round,replay_frame=frame,stage_frame=frame,fight_st=4,play_timer=99,play_timer_ms=250-frame}
    for side=1,2 do for k,v in pairs({vital_new=10000,vital_max=10000,focus_new=50000,focus_max=60000,mSuperGauge=0,mSuperGaugeMax=30000,act_st=0,y_raw=0,x_raw=side*6553600,pl_input_new=0,facing_right=side-1}) do values["p"..side.."."..k]=v end end
    for k,v in pairs(values) do row[Schema.index[k]]=v end;s:add(row)
end end
s:finish({}, {},false)
for view=2,5 do for mode=1,4 do for _,scope in ipairs({-1,0}) do
    local ui,f=ui_fixture(696);local w=Window.new();w.behavior=mode;w.damage=mode%2+1;w.resource=mode%3+1
    local round;if scope~=-1 then round=scope end
    w:draw(ui,s,view,round,2,696,vec,{round=function() end,item=function() end,frame=function() end},{round=0,frame=192})
    eq(f.tables,0)
    if view==2 then assert(table.concat(f.texts," "):find("未知",1,true)) end
end end end
if arg[1] then
    local file=assert(io.open(arg[1],"rb"));local raw=file:read("*a");file:close()
    local capture=assert(require("tools/training_record_bank/vendor/dkjson").decode(raw))
    local schema={columns=capture.columns,index={}}
    for i,name in ipairs(capture.columns) do schema.index[name]=i end
    local review=assert(require("damage_review").new(schema,capture.metadata,require("damage_rules")))
    s=assert(Stats.new(schema,capture.metadata))
    for _,row in ipairs(capture.samples) do review:add(row);s:add(row) end
    review:finish();s:finish(review.items,{},false)
    assert(not s.error and not review.error)
    print(string.format("Real capture: %d rows, %d accepted, %d groups, %d actual HP loss",#capture.samples,s.all.frames,#review.items,s.all.players[1].damage_received+s.all.players[2].damage_received))
end
for _,screen in ipairs({{1280,720},{1920,1080},{2560,1440},{800,600}}) do
    local ui,f=ui_fixture(600)
    package.loaded["func/UIKit"]=assert(loadfile("autorun/func/UIKit.lua","t",{imgui=ui}))()
    local Popup=dofile("tools/cfn_replay_capture/statistics_popups.lua")
    local manager=Popup.new()
    for id=1,3 do manager:open(id,0) end
    for view=1,4 do for mode=1,5 do for _,round in ipairs({-1,0}) do
        for _,w in ipairs(manager.windows) do
            w.view=view;w.behavior=mode;w.states=mode%2+1;w.overview=mode%2+1;w.damage=mode%2+1;w.resource=mode%3+1
            w.round=round>=0 and round or nil
        end
        manager:draw(ui,s,screen[1],screen[2],vec,{round=0,frame=192},{frame=function() error("unexpected seek") end,item=function() error("unexpected seek") end})
        eq(f.tables,0);eq(f.windows,0);eq(f.style,0)
        assert(f.pos.x>=0 and f.pos.y>=0 and f.pos.x+f.size.x<=screen[1] and f.pos.y+f.size.y<=screen[2])
    end end end
    f.buttons["关闭##statistics1"]=true
    manager:draw(ui,nil,screen[1],screen[2],vec,nil,{})
    eq(manager.windows[1].visible,false);eq(manager.windows[2].visible,true);eq(manager.windows[3].visible,true)
    f.buttons={};f.buttons["1P统计##open_stats"]=true;manager:buttons(ui,2)
    eq(manager.windows[1].visible,true);eq(manager.windows[1].round,2);eq(f.style,0)
    -- Failed content must not leave an open native window or table behind.
    for _,w in ipairs(manager.windows) do w.visible=false end
    manager:open(1,0);manager.windows[1].view=1
    ui.table_setup_column=function() error("test draw failure") end
    local ok=pcall(manager.draw,manager,ui,s,screen[1],screen[2],vec,nil,{})
    eq(ok,false);eq(f.windows,0);eq(f.tables,0);eq(f.style,0);eq(manager.windows[1].visible,false)
end
print("CFN statistics UI bindings, chart geometry at three widths, missing data and all views passed")
