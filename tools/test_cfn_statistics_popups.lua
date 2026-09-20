package.path="autorun/?.lua;tools/cfn_replay_capture/?.lua;"..package.path
for _,name in ipairs({"statistics","statistics_charts","presentation"}) do
    package.loaded["func/CFNReplayCapture/"..name]=require(name)
end
local UI={buttons={},style=0}
function UI.push_style_color() UI.style=UI.style+1 end
function UI.pop_style_color(n) UI.style=UI.style-n end
function UI.button(label) return UI.buttons[label] or false end
imgui=UI
local Popups=require("statistics_popups")
local w=Popups.new()
assert(not w:any_visible())
w:open(1,0);w:open(2,1);w:open(3,2)
assert(w:any_visible() and w.windows[1].visible and w.windows[2].visible and w.windows[3].visible)
assert(w.windows[1].round==0 and w.windows[2].round==1 and w.windows[3].round==2)
w.windows[1].view=4;w:open(2,0)
assert(w.windows[1].view==4 and w.windows[1].round==0)
w:close(1);assert(w.windows[2].visible and w.windows[3].visible)
for _,screen in ipairs({{1280,720},{1920,1080},{2560,1440},{800,600}}) do
    for id=1,3 do
        local r=Popups.layout(screen[1],screen[2],id)
        assert(r.x>=0 and r.y>=0 and r.x+r.w<=screen[1] and r.y+r.h<=screen[2])
    end
end
local n=0
for _,side in ipairs({1,2,3}) do
    local sides=Popups.sides(side);n=n+#sides
end
assert(n==4)
-- Display-only dependency: importing this module never loads training hooks.
assert(not package.loaded["func/SharedHooks"])
assert(not package.loaded["func/Training_SessionRecap"])
print("CFN independent statistics window state, responsive placement and hook-free reuse passed")
