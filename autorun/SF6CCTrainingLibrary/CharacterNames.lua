-- Display names only; never change fighter IDs or file metadata.
local names = {
    Ryu = "隆", Luke = "卢克", Kimberly = "金伯利", ["Chun-Li"] = "春丽",
    Manon = "曼侬", Zangief = "桑吉尔夫", Dhalsim = "达尔西姆", Cammy = "嘉米",
    Ken = "肯", ["Dee Jay"] = "迪杰", Lily = "莉莉", ["A.K.I"] = "阿鬼",
    ["A.K.I."] = "阿鬼", Rashid = "拉希德", Blanka = "布兰卡", Juri = "蛛俐",
    Marisa = "玛丽莎", Guile = "古烈", Ed = "爱德", ["E.Honda"] = "本田",
    ["E. Honda"] = "本田", Jamie = "杰米", Akuma = "豪鬼", ["M.Bison"] = "维嘉",
    ["M. Bison"] = "维嘉", Terry = "特瑞", Sagat = "沙加特", Mai = "不知火舞",
    Elena = "艾莲娜", Viper = "毒蛇", Ingrid = "英格丽德", Alex = "阿莱克斯",
    Yasmine = "亚思敏", Arjun = "阿俊",
}
return function(name)
    if type(name) ~= "string" or name:match("^%s*$") then return "未知角色" end
    name = name:gsub("[%c<>]", " "):match("^%s*(.-)%s*$")
    return names[name] and (names[name] .. " " .. name) or name
end
