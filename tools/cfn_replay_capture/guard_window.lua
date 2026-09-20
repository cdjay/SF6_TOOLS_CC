local M={}
local fixed,stretch=1<<4,1<<3
function M.new()
    local w={filter=1,descending=false,column=0}
    function w:draw(ui,analysis,model,controls,busy,handoff,vec)
        if not model.matching or analysis.status~="ready" then ui.text("请先分析录像或读取上次分析");return end
        if analysis.guard_error then ui.text("防御记录不完整，暂时无法列出");return end
        ui.push_item_width(138)
        local changed,value=ui.combo("##guard_filter",self.filter,{"全部防御","机会待核对"})
        ui.pop_item_width()
        if changed then self.filter=value end
        local items={}
        for _,item in ipairs(analysis.guard_items or {}) do
            if item.round==model.selected and item.receiver==model.player and (self.filter==1 or item.candidate
                and (not analysis.rule_engine or analysis.rule_engine:includes(item))) then items[#items+1]=item end
        end
        ui.same_line();ui.text(string.format("%d段防御 · 点击记录回看",#items))
        ui.text("硬直差保留原生正负，所属方待核对；连续压制可能合为一段。")
        if #items==0 then ui.text("没有符合筛选的防御记录");return end
        local opened=false
        local ok,err=pcall(function()
            if not ui.begin_table("##CFNGuardTable",5,(1<<3)|(1<<6)|(1<<7)|(1<<9),vec(0,0)) then return end
            opened=true
            for _,col in ipairs({{"发生帧",fixed,62},{"防御结束",fixed,70},{"硬直差",fixed,90},{"后续行动",stretch,1},{"机会线索",fixed,170}}) do
                ui.table_setup_column(col[1],col[2],col[3])
            end
            ui.table_next_row(1)
            for n,name in ipairs({"发生帧","防御结束","硬直差","后续行动","机会线索"}) do ui.table_set_column_index(n-1);ui.table_header(name) end
            local specs=ui.table_get_sort_specs()
            if specs and specs.specs_dirty then
                local sort=specs:get_specs()[1]
                if sort then self.column,self.descending=sort.column_index,sort.sort_direction==2 end
                specs.specs_dirty=false
            end
            local function key(i)
                if self.column==1 then return i.guard_end end
                if self.column==2 then return i.native_advantage and i.native_advantage.value end
                if self.column==3 then return i.response and i.response.frame end
                if self.column==4 then return i.window and i.window.frames end
                return i.frame
            end
            table.sort(items,function(a,b)
                local x,y=key(a),key(b)
                if x==y then return a.frame==b.frame and a.id<b.id or a.frame<b.frame end
                if x==nil then return false end;if y==nil then return true end
                if self.descending then return x>y end;return x<y
            end)
            for _,item in ipairs(items) do
                ui.table_next_row();ui.table_set_column_index(0)
                local enabled=not busy and not controls.speed_restore and model:can_locate(analysis,controls,item)
                if ui.menu_item(tostring(item.frame).."##guard_"..item.id,"",false,enabled) and enabled then
                    if analysis:locate_guard(item) then handoff();busy=true end
                end
                ui.table_set_column_index(1);ui.text(item.guard_end and tostring(item.guard_end) or "未录完")
                ui.table_set_column_index(2)
                local native=item.native_advantage
                ui.text(native and string.format("原生 %+d",native.value) or item.native_snapshot and "未关联" or "未读取")
                if ui.is_item_hovered() then
                    ui.set_tooltip(native and string.format("%d帧读数更新；不自动判给1P或2P，不代表一定打得到。",native.frame)
                        or item.native_snapshot and string.format("读到%+d，但未见完整防御段内刷新，不能当作本次硬直差。",item.native_snapshot.value)
                        or "没有同步读数。")
                end
                ui.table_set_column_index(3)
                local r=item.response or {}
                ui.text(r.frame and string.format("%d帧出招（间隔%d帧）",r.frame,r.delay)
                    or r.reason=="limit" and tostring(item.response_limit or 30).."帧内未见出招" or r.reason=="new_reaction" and "再次防御或受击" or "后续未录全")
                ui.table_set_column_index(4)
                ui.text(analysis.rule_engine and not analysis.rule_engine:includes(item) and "未匹配启用规则" or item.custom_title or (item.window and string.format("对手仍在收招 %s%d帧",item.window.lower_bound and "≥" or "",item.window.frames)
                    or item.candidate and "差值≥"..tostring(item.advantage_min or 4).."，归属待核对" or "暂未识别机会"))
                if ui.is_item_hovered() then ui.set_tooltip("仅列出值得回看的线索；未确认距离、无敌、招式发生或漏确反。") end
            end
        end)
        if opened then ui.end_table() end
        if not ok then error(err) end
    end
    return w
end
return M
