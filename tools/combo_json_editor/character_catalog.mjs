export const CHARACTER_CATALOG = Object.freeze([
    { fighterId: 1, folder: "Ryu", en: "Ryu", zh: "隆" },
    { fighterId: 2, folder: "Luke", en: "Luke", zh: "卢克" },
    { fighterId: 3, folder: "Kimberly", en: "Kimberly", zh: "金伯莉" },
    { fighterId: 4, folder: "ChunLi", en: "Chun-Li", zh: "春丽" },
    { fighterId: 5, folder: "Manon", en: "Manon", zh: "曼侬" },
    { fighterId: 6, folder: "Zangief", en: "Zangief", zh: "桑吉尔夫" },
    { fighterId: 7, folder: "JP", en: "JP", zh: "JP" },
    { fighterId: 8, folder: "Dhalsim", en: "Dhalsim", zh: "达尔西姆" },
    { fighterId: 9, folder: "Cammy", en: "Cammy", zh: "嘉米" },
    { fighterId: 10, folder: "Ken", en: "Ken", zh: "肯" },
    { fighterId: 11, folder: "DeeJay", en: "Dee Jay", zh: "迪杰" },
    { fighterId: 12, folder: "Lily", en: "Lily", zh: "莉莉" },
    { fighterId: 13, folder: "AKI", en: "A.K.I.", zh: "阿鬼" },
    { fighterId: 14, folder: "Rashid", en: "Rashid", zh: "拉希德" },
    { fighterId: 15, folder: "Blanka", en: "Blanka", zh: "布兰卡" },
    { fighterId: 16, folder: "Juri", en: "Juri", zh: "韩蛛俐" },
    { fighterId: 17, folder: "Marisa", en: "Marisa", zh: "玛丽莎" },
    { fighterId: 18, folder: "Guile", en: "Guile", zh: "古烈" },
    { fighterId: 19, folder: "Ed", en: "Ed", zh: "爱德" },
    { fighterId: 20, folder: "EHonda", en: "E. Honda", zh: "本田" },
    { fighterId: 21, folder: "Jamie", en: "Jamie", zh: "杰米" },
    { fighterId: 22, folder: "Akuma", en: "Akuma", zh: "豪鬼" },
    { fighterId: 25, folder: "Sagat", en: "Sagat", zh: "沙加特" },
    { fighterId: 26, folder: "MBison", en: "M. Bison", zh: "维加" },
    { fighterId: 27, folder: "Terry", en: "Terry", zh: "特瑞" },
    { fighterId: 28, folder: "Mai", en: "Mai Shiranui", zh: "不知火舞" },
    { fighterId: 29, folder: "Elena", en: "Elena", zh: "艾莲娜" },
    { fighterId: 30, folder: "CViper", en: "C. Viper", zh: "深红毒蛇" },
    { fighterId: 31, folder: "Alex", en: "Alex", zh: "亚历克斯" },
    { fighterId: 32, folder: "Ingrid", en: "Ingrid", zh: "英格丽德" }
]);

const BY_FOLDER = new Map(CHARACTER_CATALOG.map(character => [character.folder.toLowerCase(), character]));
const BY_ID = new Map(CHARACTER_CATALOG.map(character => [character.fighterId, character]));

export function characterByFolder(folder) {
    return BY_FOLDER.get(String(folder || "").toLowerCase()) || null;
}

export function characterByFighterId(fighterId) {
    const id = Number(fighterId);
    return Number.isFinite(id) ? BY_ID.get(id) || null : null;
}

export function folderFromPath(relativePath) {
    return String(relativePath || "").replace(/\\/g, "/").split("/").filter(Boolean)[0] || "";
}

export function characterLabel(character, count = null) {
    if (!character) return "未识别角色 (Unknown fighter)";
    const suffix = count === null ? "" : ` · ${count}`;
    return `ID ${character.fighterId} · ${character.zh} (${character.en}) · [${character.folder}]${suffix}`;
}
