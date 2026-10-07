package.path="autorun/?.lua;"..package.path
local Messages=require("SF6CCTrainingLibrary/LibraryMessages")
local cases={
    {true,"已清空 80 个录像栏位和 30 个反击栏位。自动备份：data/private.json。reversal setters applied","录像和反击已清空"},
    {true,"已保存：很长很长的自定义名称.json","配置已保存"},
    {true,"已导出：很长很长的自定义名称.json","配置已导出"},
    {true,"已导入 80 个录像栏位，清空 20 个，恢复 30 项反击设置；已初始化 4 个空栏位；已应用","配置已导入"},
    {false,"已导入 80 个录像栏位，清空 20 个，恢复 30 项反击设置；即时应用失败，请查看日志及自动备份","配置已读取，但未完全生效"},
    {true,"已导入 80 个录像栏位；未启用即时应用","配置已读取，尚未立即生效"},
    {true,"已清空 80 个录像栏位。自动备份：data/private.json。ForceApply 失败：native exception","清空尚未完全生效，请检查栏位"},
    {false,"配置已保存，但列表刷新失败，请手动刷新","配置已保存，请刷新列表"},
    {false,"配置已导出，但列表刷新失败，请手动刷新","配置已导出，请刷新列表"},
    {false,"配置名称已保存，但列表刷新失败，请手动刷新","名称已保存，请刷新配置列表"},
    {true,"已刷新，共 256 个配置","配置列表已刷新"},
    {false,"配置列表刷新失败","配置列表刷新失败，请稍后再试"},
    {false,"请先选择配置","请先选择训练配置"},
    {false,"请先停止录制、播放或连段训练","请先停止录制、播放或连段训练"},
    {false,"仅可在离线训练场、角色数据就绪后操作","请进入离线训练场，稍候再试"},
    {true,"已排队，关闭游戏暂停菜单后执行","关闭暂停菜单后执行"},
    {false,"上一次操作尚未完成，请稍候","上一次操作尚未完成，请稍候"},
    {false,"角色不匹配：配置 ID 28，当前 P2 ID 26，禁止导入","角色不符，请选择对应的训练配置"},
    {false,"配置缺少有效角色 ID，禁止导入","配置缺少角色信息，无法导入"},
    {false,"无法确认当前 P2 角色，禁止导入","陪练角色未就绪，暂时无法导入"},
    {false,"配置并非 P2 木人数据，禁止导入","这不是陪练配置，无法导入"},
    {false,"此配置超过8栏位，无法导入；原文件未修改","此配置超过8栏位，无法导入"},
    {false,"此配置超过8栏位，无法覆盖；原文件未修改","此配置超过8栏位，无法覆盖"},
    {true,"正在初始化 80 个空录像栏位，请稍候","正在准备录像栏位，请稍候"},
    {false,"环境改变，操作已取消","训练状态已改变，操作已取消"},
    {true,"Backup saved: data/private.json","备份已保存"},
    {true,"Restored from data/private.json. Imported 80, ForceApply OK","已恢复备份"},
    {true,"Restored from data/private.json. Imported 80, ForceApply failed: exception","配置已读取，但未完全生效"},
    {true,"Restored from data/private.json. ForceApply skipped","配置已读取，尚未立即生效"},
    {false,"No backup found. Tried: data/private.json","暂无可恢复的备份"},
    {false,"Backup saved but latest marker failed: data/private.json","备份已保存，恢复时请核对是哪份"},
    {true,"栏位名称已修改；请导出配置以保留","栏位说明已修改，请保存或另存配置"},
    {false,"名称最多15个字符，不能含控制符、标记或花括号","名称最多15字，请勿使用特殊符号"},
    {false,"配置名称不能为空，文件未修改","请输入配置名称"},
    {true,"配置名称未变化","配置名称未改变"},
    {true,"配置名称已保存","配置名称已修改"},
    {true,"已取消编辑，文件未修改","已取消改名"},
    {false,"请按游戏返回键关闭弹窗，名称未保存","名称未保存，请按返回关闭输入框"},
    {false,"清空未完成，请查看日志及自动备份","清空未完成，请检查录像和反击"},
    {false,"清空已取消：自动备份失败：private.json","已取消清空，栏位未改变"},
    {false,"导入未完成，请检查文件、角色和录像状态；详细原因见日志","导入未完成，请检查当前配置"},
    {false,"保存未完成，请检查文件、角色和录像状态；详细原因见日志","保存未完成，请检查当前配置"},
    {false,"导出未完成，请检查文件、角色和录像状态；详细原因见日志","导出未完成，请检查当前配置"},
    {false,"Refresh failed: exception at private.json","列表刷新失败，请稍后再试"},
    {false,"System.Exception at private.json","操作未完成"},
    {true,"Unknown new progress: private.json","状态已更新"},
    {false,"已保存：private.json","操作未完成"},
    {false,"已清空 80 个录像栏位。private.json","操作未完成"},
}
for index,case in ipairs(cases) do
    local actual=Messages.format(case[2],case[1])
    assert(actual==case[3]:gsub("导出","另存"),index..": "..actual)
    assert(utf8.len(""..actual)<=26,"message too long: "..actual)
    assert(not actual:find("[A-Za-z/\\<>]"),"raw identifiers escaped: "..actual)
    for _,word in ipairs({"文件","日志","原生","初始化","模块","索引","重置脚本","序列化"}) do
        assert(not actual:find(word,1,true),"developer wording escaped: "..actual)
    end
end
assert(Messages.format(nil,false)=="操作未完成")
assert(Messages.format({},true)=="状态已更新")
assert(Messages.format("配置已导入，请核对录像栏位及播放效果",true,"压制测试（2）")=="压制测试（2） 配置已导入")
assert(Messages.format("已保存：private.json",true,"压制测试")=="压制测试 配置已保存")
assert(Messages.format("已导出：private.json",true,"压制测试")=="压制测试 配置已另存")
assert(Messages.format("配置名称已保存",true,"压制测试")=="压制测试 配置名称已修改")
for _,title in ipairs({string.rep("压",100).."（12）",string.rep("A",100),string.rep("😀",50)}) do
    local result=Messages.format("已保存：private.json",true,title)
    assert(utf8.len(result)<=Messages.MAX_LENGTH and result:match("配置已保存$"))
    if title:find("（12）",1,true) then assert(result:find("…（12）",1,true)) end
end
for _,title in ipairs({"file.json","data/test","C:\\test","\255"}) do
    assert(Messages.format("已保存：private.json",true,title)=="配置已保存")
end
assert(Messages.format("已保存：private.json",true,"<color FF0000>测试</color>\n{}")=="测试 配置已保存")
assert(Messages.format("已导入 80 个录像栏位；即时应用失败",false,"测试")=="配置已读取，但未完全生效")
print("PASS library messages: "..#cases.." concise outcomes, partial failures and no raw details")
