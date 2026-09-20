-- Native ImGui charts. Geometry is contained in an explicit canvas, not a game hook.
local M={accent=0xffb7c851,text=0xffe3e5e9,muted=0xff9ca2ac,grid=0xff505058,background=0xff27272d}
local function fit(ui,text,width)
    while #text>0 and ui.calc_text_size(text).x>width do text=text:sub(1,(utf8.offset(text,-1) or 1)-1) end
    return text
end
local function canvas(ui,id,width,height,vec)
    local o=ui.get_cursor_screen_pos()
    local click=ui.invisible_button(id,vec(width,height),0)
    local d=ui.get_window_draw_list()
    d:add_rect_filled(o,vec(o.x+width,o.y+height),M.background,0,0)
    return d,o,click,ui.is_item_hovered()
end
local function text(d,ui,vec,x,y,value,color,width)
    d:add_text(vec(x,y),color or M.text,fit(ui,value,width or 1000))
end
function M.bars(ui,id,rows,width,vec)
    local h=math.max(1,#rows)*25+8
    local d,o,click,hover=canvas(ui,id,width,h,vec)
    local label=math.min(220,width*.43); local left=o.x+label; local available=width-label-96
    local maximum=0; for _,r in ipairs(rows) do maximum=math.max(maximum,r.value or 0) end
    local selected
    for i,r in ipairs(rows) do
        local y=o.y+4+(i-1)*25
        text(d,ui,vec,o.x+8,y,r.label,M.text,label-16)
        local extent=maximum>0 and math.max(0,r.value or 0)/maximum*available or 0
        d:add_rect_filled(vec(left,y+3),vec(left+extent,y+19),M.accent,0,0)
        text(d,ui,vec,o.x+width-88,y,r.display or tostring(r.value or 0),M.text,84)
        if hover then
            local mouse=ui.get_mouse()
            if mouse.y>=y and mouse.y<y+25 then
                if r.tooltip then ui.set_tooltip(r.tooltip) end
                if click then selected=i end
            end
        end
    end
    return selected
end
function M.histogram(ui,id,values,labels,width,vec)
    local height=174; local d,o=canvas(ui,id,width,height,vec)
    local left,bottom=o.x+12,o.y+138; local top=o.y+28; local step=(width-24)/#labels
    local maximum=1; for _,v in pairs(values) do maximum=math.max(maximum,v) end
    for i,label in ipairs(labels) do
        local value=values[i] or 0; local x=left+(i-1)*step
        local y=bottom-value/maximum*(bottom-top)
        d:add_rect_filled(vec(x+4,y),vec(x+step-4,bottom),M.accent,0,0)
        text(d,ui,vec,x+4,math.max(o.y+4,y-22),tostring(value),M.text,step-8)
        text(d,ui,vec,x+4,bottom+7,label,M.muted,step-8)
    end
    d:add_line(vec(left,bottom),vec(o.x+width-12,bottom),M.grid,1)
end
function M.boxplot(ui,id,distribution,width,vec)
    local d,o=canvas(ui,id,width,46,vec)
    if not distribution.max then text(d,ui,vec,o.x+8,o.y+12,"暂无分布",M.muted,width-16); return end
    local max=math.max(1,distribution.max); local y=o.y+23
    local function x(v) return o.x+16+v/max*(width-32) end
    d:add_line(vec(x(distribution.min),y),vec(x(distribution.max),y),M.muted,2)
    for _,v in ipairs({distribution.min,distribution.max}) do d:add_line(vec(x(v),y-10),vec(x(v),y+10),M.text,2) end
    d:add_rect_filled(vec(x(distribution.q1),y-14),vec(x(distribution.q3),y+14),0xff78734e,0,0)
    d:add_line(vec(x(distribution.median),y-14),vec(x(distribution.median),y+14),M.accent,3)
end
function M.radar(ui,id,axes,width,vec)
    local d,o=canvas(ui,id,width,230,vec)
    local center=vec(o.x+width/2,o.y+115); local radius=73
    local function point(i,r)
        local angle=-math.pi/2+(i-1)*math.pi/3
        return vec(center.x+math.cos(angle)*r,center.y+math.sin(angle)*r)
    end
    for ring=1,4 do
        for i=1,6 do d:add_line(point(i,radius*ring/4),point(i%6+1,radius*ring/4),M.grid,1) end
    end
    local complete=true; for _,a in ipairs(axes) do if a.value==nil then complete=false end end
    for i,a in ipairs(axes) do
        d:add_line(center,point(i,radius),M.grid,1)
        local p=point(i,radius+24)
        local label=a.label.." "..(a.value and string.format("%.1f%%",a.value*100) or "未知")
        local size=ui.calc_text_size(label)
        text(d,ui,vec,math.max(o.x+4,math.min(p.x-size.x/2,o.x+width-size.x-4)),p.y-9,label,M.text,width-8)
        if a.value then
            local value=point(i,radius*math.max(0,math.min(1,a.value)))
            d:add_circle_filled(value,3,M.accent,12)
            local next=axes[i%6+1]
            if next.value then
                local endpoint=point(i%6+1,radius*math.max(0,math.min(1,next.value)))
                d:add_line(value,endpoint,M.accent,2)
                if complete then d:add_triangle_filled(center,value,endpoint,0x33b7c851) end
            end
        end
    end
    if ui.is_item_hovered() then ui.set_tooltip("从中心向外依次为0%、25%、50%、75%、100%；未知项不连线。") end
end
function M.timeline(ui,id,cells,width,height,first,last,current,vec)
    local d,o,click,hover=canvas(ui,id,width,height,vec)
    local left,right,top,bottom=o.x+42,o.x+width-12,o.y+12,o.y+height-28
    if not first or not last or #cells==0 then text(d,ui,vec,left,top,"没有可用曲线",M.muted,width-54); return end
    local function x(f) return left+(f-first)/math.max(1,last-first)*(right-left) end
    local function y(v) return bottom-math.max(0,math.min(100,v))/100*(bottom-top) end
    for _,v in ipairs({0,50,100}) do
        d:add_line(vec(left,y(v)),vec(right,y(v)),M.grid,1)
        text(d,ui,vec,o.x+4,y(v)-8,tostring(v),M.muted,35)
    end
    local prev
    for _,cell in ipairs(cells) do
        local cx=x((cell.first+cell.last)/2)
        d:add_line(vec(cx,y(cell.min)),vec(cx,y(cell.max)),0xff71917a,2)
        if prev and cell.connected then d:add_line(vec(x(prev.last),y(prev.value)),vec(x(cell.first),y(cell.first_value)),M.accent,1.5) end
        d:add_line(vec(x(cell.first),y(cell.first_value)),vec(x(cell.last),y(cell.value)),M.accent,1.5)
        prev=cell
    end
    if current and current>=first and current<=last then d:add_line(vec(x(current),top),vec(x(current),bottom),0xff6cd7f1,1) end
    text(d,ui,vec,left,bottom+6,tostring(first).."F",M.muted,100)
    text(d,ui,vec,right-90,bottom+6,tostring(last).."F",M.muted,90)
    if hover then
        local m=ui.get_mouse()
        local frame=math.floor(first+math.max(0,math.min(1,(m.x-left)/(right-left)))*(last-first)+.5)
        ui.set_tooltip("第"..frame.."帧；曲线按原始记录定位")
        if click and m.x>=left and m.x<=right and m.y>=top and m.y<=bottom then return frame end
    end
end
-- Every player keeps the same color and scale, including when shown alone.
M.players={0xffffaa00,0xff00a5ff}
function M.paired_bars(ui,id,rows,sides,width,vec,maximum)
    local height=math.max(1,#rows)*40+8
    local d,o,_,hover=canvas(ui,id,width,height,vec)
    local label=math.min(156,width*.32)
    local left,right=o.x+label,o.x+width-76
    if not maximum then
        maximum=1
        for _,row in ipairs(rows) do for _,side in ipairs(sides) do maximum=math.max(maximum,row.values[side] or 0) end end
    end
    for i,row in ipairs(rows) do
        local y=o.y+4+(i-1)*40
        text(d,ui,vec,o.x+6,y+8,row.label,M.text,label-12)
        for j,side in ipairs(sides) do
            local v=row.values[side];local cy=y+(j-1)*20
            if v then d:add_rect_filled(vec(left,cy+3),vec(left+math.max(0,math.min(1,v/maximum))*(right-left),cy+16),M.players[side],0,0) end
            text(d,ui,vec,right+5,cy,row.displays and row.displays[side] or (v and tostring(v) or "未知"),M.players[side],70)
        end
        if hover then
            local mouse=ui.get_mouse()
            if mouse.y>=y and mouse.y<y+40 then ui.set_tooltip(row.tooltip or row.label) end
        end
    end
end
function M.paired_boxplot(ui,id,distributions,sides,width,vec)
    local d,o,_,hover=canvas(ui,id,width,100,vec)
    local maximum=1
    for _,side in ipairs(sides) do maximum=math.max(maximum,distributions[side].max or 0) end
    local function x(v) return o.x+48+v/maximum*(width-70) end
    for j,side in ipairs(sides) do
        local q=distributions[side];local y=o.y+24+(j-1)*40;local color=M.players[side]
        text(d,ui,vec,o.x+4,y-9,side.."P",color,40)
        if q.max then
            d:add_line(vec(x(q.min),y),vec(x(q.max),y),color,1)
            d:add_rect_filled(vec(x(q.q1),y-10),vec(x(q.q3),y+10),(color & 0xffffff)|0x66000000,0,0)
            for _,v in ipairs({q.min,q.max,q.median}) do d:add_line(vec(x(v),y-12),vec(x(v),y+12),color,2) end
        else text(d,ui,vec,x(0),y-9,"暂无受伤段",M.muted,width-70) end
    end
    if hover then
        local lines={"双方共用伤害刻度：0～"..maximum.."。箱体：中间50%；中线：中位数；两端：最小、最大。"}
        for _,side in ipairs(sides) do
            local q=distributions[side]
            lines[#lines+1]=side.."P "..(q.max and string.format("最小 %.0f / 下四分位 %.1f / 中位 %.1f / 上四分位 %.1f / 最大 %.0f",q.min,q.q1,q.median,q.q3,q.max) or "暂无受伤段")
        end
        ui.set_tooltip(table.concat(lines,"\n"))
    end
end
function M.paired_radar(ui,id,axes,sides,width,vec)
    local d,o,_,hover=canvas(ui,id,width,240,vec)
    local center=vec(o.x+width/2,o.y+120);local radius=76
    local function point(i,r)
        local a=-math.pi/2+(i-1)*math.pi/3
        return vec(center.x+math.cos(a)*r,center.y+math.sin(a)*r)
    end
    for ring=1,4 do for i=1,6 do d:add_line(point(i,radius*ring/4),point(i%6+1,radius*ring/4),M.grid,1) end end
    for i,axis in ipairs(axes) do
        d:add_line(center,point(i,radius),M.grid,1)
        local p=point(i,radius+24);local size=ui.calc_text_size(axis.label)
        text(d,ui,vec,p.x-size.x/2,p.y-9,axis.label,M.text,width-8)
    end
    for _,side in ipairs(sides) do for i,axis in ipairs(axes) do
        local v=axis.values[side];local next_value=axes[i%6+1].values[side]
        if v then
            local p=point(i,radius*math.max(0,math.min(100,v))/100)
            d:add_circle_filled(p,3, M.players[side],12)
            if next_value then d:add_line(p,point(i%6+1,radius*math.max(0,math.min(100,next_value))/100),M.players[side],2) end
        end
    end end
    if hover then
        local lines={"0%～100%，每圈25%；行为时间占比，不是能力评分。"}
        for _,axis in ipairs(axes) do
            local values={axis.label}
            for _,side in ipairs(sides) do values[#values+1]=side.."P "..(axis.values[side] and string.format("%.1f%%",axis.values[side]) or "未知") end
            lines[#lines+1]=table.concat(values," / ")
        end
        ui.set_tooltip(table.concat(lines,"\n"))
    end
end
function M.paired_timeline(ui,id,series,sides,width,height,first,last,current,vec)
    local d,o,click,hover=canvas(ui,id,width,height,vec)
    local left,right,top,bottom=o.x+42,o.x+width-12,o.y+14,o.y+height-30
    if not first or not last then text(d,ui,vec,left,top,"没有可用曲线",M.muted,width-54);return end
    local function x(f) return left+math.max(0,math.min(1,(f-first)/math.max(1,last-first)))*(right-left) end
    local function y(v) return bottom-math.max(0,math.min(100,v))/100*(bottom-top) end
    for _,v in ipairs({0,25,50,75,100}) do
        d:add_line(vec(left,y(v)),vec(right,y(v)),M.grid,1)
        text(d,ui,vec,o.x+4,y(v)-8,tostring(v),M.muted,35)
    end
    for _,side in ipairs(sides) do
        local previous;local color=M.players[side]
        for _,cell in ipairs(series[side] or {}) do
            local cx=x((cell.first+cell.last)/2)
            d:add_line(vec(cx,y(cell.min)),vec(cx,y(cell.max)),(color & 0xffffff)|0x88000000,2)
            if previous and cell.connected then
                d:add_line(vec(x(previous.last),y(previous.value)),vec(x(cell.first),y(cell.first_value)),color,2)
            end
            d:add_line(vec(x(cell.first),y(cell.first_value)),vec(x(cell.last),y(cell.value)),color,2)
            previous=cell
        end
        if #(series[side] or {})==0 then text(d,ui,vec,left+8,top+(side-1)*22,side.."P 未读取",color,width-70) end
    end
    if current and current>=first and current<=last then d:add_line(vec(x(current),top),vec(x(current),bottom),M.text,1) end
    text(d,ui,vec,left,bottom+7,tostring(first).."F",M.muted,100)
    text(d,ui,vec,right-90,bottom+7,tostring(last).."F",M.muted,90)
    if hover then
        local mouse=ui.get_mouse()
        local frame=math.floor(first+math.max(0,math.min(1,(mouse.x-left)/(right-left)))*(last-first)+.5)
        local lines={"第"..frame.."帧（30帧内范围）"}
        for _,side in ipairs(sides) do
            local selected
            for _,cell in ipairs(series[side] or {}) do if frame>=cell.first and frame<=cell.last then selected=cell;break end end
            lines[#lines+1]=side.."P "..(selected and string.format("%.1f%%～%.1f%%",selected.min,selected.max) or "无记录")
        end
        ui.set_tooltip(table.concat(lines,"\n"))
        if click and mouse.x>=left and mouse.x<=right and mouse.y>=top and mouse.y<=bottom then return frame end
    end
end
return M
