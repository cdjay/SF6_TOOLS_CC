"use strict";

const fs = require("fs");
const path = require("path");

const OFFICIAL_DUMP_FILENAMES = Object.freeze({
    AKI: "A.K.I.json", Akuma: "GOUKI.json", Alex: "ALEX.json", Blanka: "BLANKA.json",
    CViper: "C.VIPER.json", Cammy: "CAMMY.json", ChunLi: "CHUN-LI.json", DeeJay: "DEE JAY.json",
    Dhalsim: "DHALSIM.json", EHonda: "E.HONDA.json", Ed: "ED.json", Elena: "ELENA.json",
    Guile: "GUILE.json", Ingrid: "INGRID.json", JP: "JP.json", Jamie: "JAMIE.json",
    Juri: "JURI.json", Ken: "KEN.json", Kimberly: "KIMBERLY.json", Lily: "LILY.json",
    Luke: "LUKE.json", MBison: "VEGA.json", Mai: "MAI.json", Manon: "MANON.json",
    Marisa: "MARISA.json", Rashid: "RASHID.json", Ryu: "RYU.json", Sagat: "SAGAT.json",
    Terry: "TERRY.json", Zangief: "ZANGIEF.json"
});

function normalizeCommand(value) {
    if (value === null || value === undefined) return null;
    let text = String(value).trim();
    if (!text) return null;
    const replacements = new Map([
        ["＋", "+"], ["＞", ">"], ["／", "/"], ["　", " "], ["\r", " "], ["\n", " "],
        ["（前ジャンプ中に）", "空中 "], ["（垂直ジャンプ中に）", "空中 "], ["（後ろジャンプ中に）", "空中 "],
        ["（ジャンプ中に）", "空中 "], ["(前ジャンプ中に)", "空中 "], ["(垂直ジャンプ中に)", "空中 "],
        ["(後ろジャンプ中に)", "空中 "], ["(ジャンプ中に)", "空中 "], ["(During a jump)", "空中 "],
        ["(during a jump)", "空中 "], ["(跳跃期间)", "空中 "]
    ]);
    for (const [from, to] of replacements) text = text.split(from).join(to);
    return text.replace(/\s+/g, " ").replace(/\s*([+>])\s*/g, " $1 ")
        .replace(/\s*\/\s*/g, "/").replace(/\s+/g, " ").trim() || null;
}

function normalizeModernCommand(value) {
    const text = normalizeCommand(value);
    if (!text) return null;
    return normalizeCommand(text.replace(/\bL\b/g, "弱").replace(/\bM\b/g, "中").replace(/\bH\b/g, "强"));
}

function splitMoveCell(value) {
    const lines = String(value || "").split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    return lines.length < 2 ? [null, null] : [lines[0], lines.slice(1).join(" ")];
}

function buildOfficialSemantics(character, sourceFilename, payload, options = {}) {
    if (!Array.isArray(payload)) throw new Error("OFF 官网表根节点必须是采集记录数组。");
    const captures = payload.filter(item => item && typeof item === "object");
    const language = captures.some(item => item.language === "en") ? "en" : "zh";
    const classic = captures.find(item => item.language === language && item.control_type === "classic");
    const modern = captures.find(item => item.language === language && item.control_type === "modern");
    if (!classic || !modern) throw new Error(`OFF 官网表缺少配对的 ${language} Classic/Modern 记录。`);
    const classicRows = new Map();
    for (const section of classic.sections || []) for (const row of section.rows || []) {
        if (!Array.isArray(row) || !row.length) continue;
        const [moveName, command] = splitMoveCell(row[0]);
        if (moveName && command) classicRows.set(moveName, normalizeCommand(command));
    }
    const semanticRows = [];
    for (const [sectionIndex, section] of (modern.sections || []).entries()) {
        for (const [rowIndex, row] of (section.rows || []).entries()) {
            if (!Array.isArray(row) || !row.length) continue;
            const [moveName, modernCommand] = splitMoveCell(row[0]);
            const classicDisplay = classicRows.get(moveName);
            const modernDisplay = normalizeModernCommand(modernCommand);
            if (!moveName || !classicDisplay || !modernDisplay) continue;
            semanticRows.push({
                semantic_row_id: `${sectionIndex}:${rowIndex}`,
                classic_display: classicDisplay,
                modern_display: modernDisplay,
                control_support: "classic_modern",
                source: "capcom_official_dump",
                move_name: moveName,
                category: section.title || section.name || "",
                official_web_id: null,
                note: "Generated from paired Capcom official Classic/Modern table captures without Action IDs."
            });
        }
    }
    return {
        _meta: {
            schema: "xt.modern_display.v1", character, generated_from: "capcom_official",
            source_url: modern.source_url || "", source_chunk: `local:${sourceFilename}`,
            source_format: "paired_official_table_dump", source_sha256: options.sourceSha256 || null,
            updated_at: String(options.generatedAt || new Date().toISOString()).slice(0, 10),
            description: `Official ${character} modern semantics generated from paired Capcom tables.`
        },
        _semantic_rows: semanticRows
    };
}

function findOfficialDump(directory, character) {
    const name = OFFICIAL_DUMP_FILENAMES[character];
    if (!name) return null;
    const filename = path.join(path.resolve(directory), name);
    return fs.existsSync(filename) && fs.statSync(filename).isFile() ? filename : null;
}

module.exports = { OFFICIAL_DUMP_FILENAMES, normalizeCommand, buildOfficialSemantics, findOfficialDump };
