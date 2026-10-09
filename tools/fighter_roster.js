"use strict";

// Node access to the single fighter roster (data/SF6CC/fighters.json), the
// same file the runtime reads through autorun/func/FighterRoster.lua.

const fs = require("fs");
const path = require("path");

const ROSTER_PATH = path.resolve(__dirname, "../data/SF6CC/fighters.json");
const SCHEMA = "sf6cc.fighter_roster.v1";
const MAX_FIGHTER_ID = 59;
const OFFICIAL_FRAME_URL = "https://www.streetfighter.com/6/zh-hant/character/%s/frame";

function nonEmpty(value) {
    return typeof value === "string" && value.trim() !== "";
}

function validateRoster(document, source = ROSTER_PATH) {
    if (!document || document.schema !== SCHEMA || !Array.isArray(document.fighters)
        || document.fighters.length === 0) {
        throw new Error(`${source} 不是有效的角色名单（${SCHEMA}）。`);
    }
    const byId = new Map();
    const byKey = new Map();
    for (const entry of document.fighters) {
        const id = Number(entry && entry.id);
        const key = entry && entry.key;
        if (!Number.isInteger(id) || id < 1 || id > MAX_FIGHTER_ID) {
            throw new Error(`${source} 含无效 fighter id: ${entry && entry.id}`);
        }
        if (typeof key !== "string" || !/^[A-Za-z][A-Za-z0-9_]*$/.test(key)) {
            throw new Error(`${source} fighter ${id} 的 key 无效: ${key}`);
        }
        if (!nonEmpty(entry.name_en) || !nonEmpty(entry.name_zh)) {
            throw new Error(`${source} fighter ${key} 缺少显示名。`);
        }
        if (byId.has(id) || byKey.has(key.toLowerCase())) {
            throw new Error(`${source} fighter id 或 key 重复: ${key}`);
        }
        if (entry.official_slug !== undefined && !nonEmpty(entry.official_slug)) {
            throw new Error(`${source} fighter ${key} 的 official_slug 无效。`);
        }
        const fighter = Object.freeze({
            id,
            key,
            name_en: entry.name_en,
            name_zh: entry.name_zh,
            official_slug: entry.official_slug || null,
            aliases: Object.freeze([...(entry.aliases || [])])
        });
        byId.set(id, fighter);
        byKey.set(key.toLowerCase(), fighter);
    }
    const fighters = [...byId.values()].sort((left, right) => left.id - right.id);
    return Object.freeze({
        fighters: Object.freeze(fighters),
        byId: id => byId.get(Number(id)) || null,
        byKey: key => byKey.get(String(key || "").toLowerCase()) || null
    });
}

function loadRoster(file = ROSTER_PATH) {
    return validateRoster(JSON.parse(fs.readFileSync(file, "utf8")), file);
}

// The official snapshot and lastjson tools use one registry entry per key:
// { fighter_id, official_name, url }.
function officialRegistry(roster = loadRoster()) {
    const registry = {};
    for (const fighter of roster.fighters) {
        registry[fighter.key] = {
            fighter_id: fighter.id,
            official_name: fighter.official_slug,
            url: fighter.official_slug ? OFFICIAL_FRAME_URL.replace("%s", fighter.official_slug) : null
        };
    }
    return registry;
}

module.exports = { ROSTER_PATH, SCHEMA, MAX_FIGHTER_ID, validateRoster, loadRoster, officialRegistry };
