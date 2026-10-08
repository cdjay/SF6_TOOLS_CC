-- Presentation-only adapter for the existing shared status channel. Never echo
-- backend text: it may contain paths, user titles or native exception details.
local M = {}
local exact = {
    ["就绪"] = "已就绪",
    ["请先选择配置"] = "请先选择训练配置",
    ["配置列表已变化，请重新选择"] = "配置列表已变化，请重新选择",
    ["暂时无法选择配置"] = "暂时无法选择配置",
    ["上一次操作尚未完成，请稍候"] = "上一次操作尚未完成，请稍候",
    ["请先停止录制、播放或连段训练"] = "请先停止录制、播放或连段训练",
    ["请先停止录制和播放"] = "请先停止录制和播放",
    ["仅可在离线训练场、角色数据就绪后操作"] = "请进入离线训练场，稍候再试",
    ["已排队，关闭游戏暂停菜单后执行"] = "关闭暂停菜单后执行",
    ["环境改变，操作已取消"] = "训练状态已改变，操作已取消",
    ["上次配置不存在或角色不匹配，未自动导入"] = "未能载入上次配置，请重新选择",
    ["配置列表刷新失败"] = "配置列表刷新失败，请稍后再试",
    ["配置超过 256 个，请先整理目录"] = "训练配置过多，暂时无法显示",
    ["无法确认当前 P2 角色，禁止导入"] = "陪练角色未就绪，暂时无法导入",
    ["配置缺少有效角色 ID，禁止导入"] = "配置缺少角色信息，无法导入",
    ["配置并非 P2 木人数据，禁止导入"] = "这不是陪练配置，无法导入",
    ["此配置超过8栏位，无法导入；原文件未修改"] = "此配置超过8栏位，无法导入",
    ["此配置超过8栏位，无法覆盖；原文件未修改"] = "此配置超过8栏位，无法覆盖",
    ["当前训练数据不是8栏位，请重启游戏"] = "当前训练数据不是8栏位，请重启游戏",
    ["当前录像超过8栏位，请先恢复为原生8栏位"] = "录像超过8栏，请先恢复为8栏位",
    ["当前录像已是原生8栏位"] = "录像已是原生8栏位",
    ["恢复未完成，请检查录像和反击设置"] = "恢复未完成，请检查录像和反击",
    ["名称编辑暂不可用，或有其他操作尚未完成"] = "暂时无法改名，请稍候",
    ["关闭暂停菜单后修改栏位名称；导出配置后保留"] = "请关闭暂停菜单，修改栏位名称",
    ["关闭暂停菜单后修改训练配置名称（最多15个字符）"] = "请关闭暂停菜单，修改配置名称",
    ["已取消编辑，文件未修改"] = "已取消改名",
    ["读取配置失败，未修改文件"] = "无法读取配置，名称未修改",
    ["未收到有效的确认结果，名称未保存"] = "未确认名称，改名未保存",
    ["请按游戏返回键关闭弹窗，名称未保存"] = "名称未保存，请按返回关闭输入框",
    ["名称编辑已停止，文件未修改，请正常关闭弹窗"] = "改名已停止，请关闭输入框",
    ["名称已确认，关闭弹窗后应用"] = "请关闭输入框，完成栏位改名",
    ["配置名称已确认，关闭弹窗后保存"] = "请关闭输入框，保存配置名称",
    ["栏位名称已修改；请导出配置以保留"] = "栏位说明已修改，请保存或另存配置",
    ["栏位改名失败，录像未修改"] = "栏位改名失败，录像未改变",
    ["配置名称未变化"] = "配置名称未改变",
    ["配置名称已保存"] = "配置名称已修改",
    ["配置已保存"] = "配置已保存",
    ["配置名称已保存，但列表刷新失败，请手动刷新"] = "名称已保存，请刷新配置列表",
    ["名称最多15个字符，不能含控制符、标记或花括号"] = "名称最多15字，请勿使用特殊符号",
    ["配置名称应为最多15个字符，且不能包含控制符或标记"] = "名称最多15字，请勿使用特殊符号",
    ["配置名称不能为空，文件未修改"] = "请输入配置名称",
    ["配置名称格式无效，未修改文件"] = "配置名称无法读取，未修改",
    ["配置编辑已结束"] = "本次改名已结束，请重新打开",
    ["配置不可读或格式不支持，未修改文件"] = "无法读取此配置，未修改",
    ["仅支持当前木人库配置目录中的文件"] = "此配置无法修改，请先导出一份",
    ["配置已被外部修改或删除，请刷新后重试"] = "配置已改变，请刷新后重试",
    ["备份期间配置发生变化，未覆盖原文件"] = "配置已改变，本次未保存",
    ["原文件备份失败，未保存配置"] = "无法保留原配置，本次未保存",
    ["配置保存失败，原文件已恢复"] = "保存失败，已保留原配置",
    ["配置名称保存失败，请检查原文件备份"] = "配置改名未完成，请检查原配置",
    ["清空未完成，请查看日志及自动备份"] = "清空未完成，请检查录像和反击",
    ["备份操作失败，请查看日志"] = "备份操作未完成",
    ["Refreshed"] = "列表已刷新",
    ["操作请求失败，详情见日志"] = "暂时无法执行此操作",
    ["操作请求失败，配置未修改，请稍后重试"] = "暂时无法执行此操作",
    ["保存请求失败，配置未修改，请稍后重试"] = "暂时无法保存配置",
}
local function contains(text, part) return text:find(part, 1, true) ~= nil end
local function starts(text, part) return text:sub(1, #part) == part end

local function format_status(value, ok)
    local text = type(value) == "string" and value or ""
    if exact[text] then return exact[text] end
    -- Partial writes can have a successful backend return value. Inspect these
    -- before any success prefix; never claim that the change is already active.
    if starts(text, "已导入 ") or starts(text, "Restored from data/") then
        if contains(text, "即时应用失败") or contains(text, "ForceApply failed") then
            return "配置已读取，但未完全生效"
        end
        if contains(text, "未启用即时应用") or contains(text, "ForceApply skipped") then
            return "配置已读取，尚未立即生效"
        end
    end
    if starts(text, "已清空") and contains(text, "ForceApply 失败") then
        return "清空尚未完全生效，请检查栏位"
    end
    if starts(text, "已恢复为原生8栏位") then
        if contains(text, "ForceApply 失败") then return "已恢复8栏，请检查录像是否生效" end
        if ok == true then return "已恢复为原生8栏位录像" end
    end
    for _, verb in ipairs({ "保存", "导出" }) do
        if starts(text, "配置已" .. verb .. "，但列表刷新失败") then
            return "配置已" .. verb .. "，请刷新列表"
        end
    end
    if starts(text, "角色不匹配：") then
        return ok == true and "配置与陪练角色不同" or "角色不符，请选择对应的训练配置"
    end
    if starts(text, "Refresh failed:") then return "列表刷新失败，请稍后再试" end
    if starts(text, "No backup found.") then return "暂无可恢复的备份" end
    if starts(text, "Backup saved but latest marker failed:") then return "备份已保存，恢复时请核对是哪份" end
    if starts(text, "配置保存失败，请从备份恢复：") then return "保存失败，请恢复之前的备份" end
    if starts(text, "配置已写入，但更新配置索引失败:") then return "配置已保存，请刷新配置列表" end
    if starts(text, "清空已取消") then return "已取消清空，栏位未改变" end
    if starts(text, "清空失败") then return "清空未完成，请检查录像和反击" end
    for _, verb in ipairs({ "导入", "保存", "导出" }) do
        if starts(text, verb .. "未完成，") then return verb .. "未完成，请检查当前配置" end
    end
    if ok == true then
        if starts(text, "已清空") then return "录像和反击已清空" end
        if starts(text, "已保存：") then return "配置已保存" end
        if starts(text, "已导出：") or starts(text, "已导出: data/") then return "配置已导出" end
        if starts(text, "已导入 ") or starts(text, "配置已导入，") then return "配置已导入" end
        if starts(text, "Restored from data/") then return "已恢复备份" end
        if starts(text, "Backup saved: data/") then return "备份已保存" end
        if starts(text, "已刷新，共 ") then return "配置列表已刷新" end
        if starts(text, "正在初始化 ") then return "正在准备录像栏位，请稍候" end
    end
    -- Unknown messages are not presumed to be completed operations, even when
    -- status_ok is true (waiting/progress also uses true).
    return ok == true and "状态已更新" or "操作未完成"
end
M.MAX_LENGTH=26
function M.format(value,ok,title)
    local message=format_status(value,ok):gsub("导出","另存")
    if message~="配置已导入" and message~="配置已保存" and message~="配置已另存"
        and message~="配置名称已修改" then return message end
    if type(title)~="string" then return message end
    title=title:gsub("<[^>]*>",""):gsub("[%c<>{}]"," "):gsub("%s+"," "):match("^%s*(.-)%s*$")
    if title:find("[/\\]") or title:lower():match("%.json%s*$") then return message end
    local valid,count=pcall(utf8.len,title)
    if not valid or not count or count==0 then return message end
    local limit=M.MAX_LENGTH-utf8.len(message)-1
    if count>limit then
        local suffix=title:match("(（%d+）)$") or ""
        local kept=limit-utf8.len(suffix)-1
        if kept<1 then suffix=""; kept=limit-1 end
        title=title:sub(1,utf8.offset(title,kept+1)-1).."…"..suffix
    end
    return title.." "..message
end
return M
