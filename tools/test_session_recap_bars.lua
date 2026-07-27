local draw_calls = 0
package.preload["func/ImGuiCanvas"] = function()
    local function draw() draw_calls = draw_calls + 1; return true end
    return {
        surface_size = function() return 1920, 1080 end,
        fill_rect = draw,
        outline_rect = draw,
        line = draw,
        text = draw,
        Font = {
            new = function()
                return {
                    measure = function(_, text)
                        return #tostring(text) * 10, 18
                    end,
                }
            end,
        },
    }
end
package.preload["func/SharedHooks"] = function() return {} end

_G.safe_load_json = function() return nil end
re = { on_frame = function() end }
imgui = {
    get_mouse = function() return { x = -1, y = -1 } end,
}
sdk = {}

local Recap = dofile("autorun/func/Training_SessionRecap.lua")
assert(Recap.show_bars("空统计", {}, {}) == false,
    "bar panel must reject an empty dataset")
assert(Recap.is_visible() == false,
    "rejected bar data must not open the panel")

local opened = Recap.show_bars("资源组合平均伤害", {
    {
        label = "1斗气 + SA3",
        line1 = "1斗气",
        line2 = "SA3",
        value = 3456.5,
        samples = 2,
    },
}, {
    x_label = "资源组合",
    y_label = "平均伤害",
})
assert(opened == true and Recap.is_visible() == true,
    "valid bar data must open the shared recap panel")
_G._session_recap_queue = true
Recap.imgui_draw()
assert(_G.SessionRecapVisible == true and draw_calls > 0,
    "shared recap renderer must draw custom bar data")

Recap.hide()
assert(Recap.is_visible() == false,
    "shared recap panel must still close normally")

print("session recap bar tests passed")
