#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const compiler = require("./compiler_core.js");
const commandDisplay = require("./command_display_core.js");
const webCharacter = require("./web_character_core.js");

const TOOL_ROOT = __dirname;
const DEFAULT_ACBCM_ROOT = path.join(TOOL_ROOT, "acbcm");
const DEFAULT_OFF_ROOT = path.join(TOOL_ROOT, "off");
const COMMUNITY_ROOT = path.resolve(TOOL_ROOT, "../modern_display_builder/community");
const CHARACTER_MANIFEST = path.resolve(TOOL_ROOT, "../modern_display_builder/characters.json");
const ZERO_AUDIT_FIELDS = [
    "owner_missing_count", "no_evidence_count", "direct_overridden_count",
    "non_whitelist_propagation_count", "overlay_entry_count",
    "alias_propagation_count", "type17_route_count", "ac_automatic_transition_route_count",
    "replaces_profile_route_count"
];

function argsOf(argv) {
    const result = {};
    for (let index = 0; index < argv.length; index += 1) {
        const key = argv[index];
        if (!key.startsWith("--")) throw new Error(`未知参数: ${key}`);
        const value = argv[index + 1];
        if (!value || value.startsWith("--")) throw new Error(`参数 ${key} 缺少值。`);
        result[key] = value;
        index += 1;
    }
    return result;
}

function sha256(bytes) {
    return crypto.createHash("sha256").update(bytes).digest("hex");
}

function readSource(filename) {
    const bytes = fs.readFileSync(filename);
    return { sha256: sha256(bytes), value: bcmCore.parseSourceText(bytes.toString("utf8")) };
}

function readJson(filename) {
    return JSON.parse(fs.readFileSync(filename, "utf8"));
}

function writeJson(filename, value) {
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.writeFileSync(filename, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function normalizeVersion(value) {
    const match = String(value || "").trim().match(/^(\d{4})[.-](\d{1,2})[.-](\d{1,2})$/);
    if (!match) throw new Error(`版本目录不是 YYYY-MM-DD 或 YYYY.M.D: ${value}`);
    const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
    if (date.getUTCFullYear() !== Number(match[1]) || date.getUTCMonth() + 1 !== Number(match[2])
        || date.getUTCDate() !== Number(match[3])) throw new Error(`无效版本日期: ${value}`);
    return date.toISOString().slice(0, 10);
}

function versionDirectories(root) {
    if (!fs.existsSync(root)) return [];
    return fs.readdirSync(root, { withFileTypes: true })
        .filter(entry => entry.isDirectory() && !entry.name.startsWith("."))
        .map(entry => ({ name: entry.name, normalized: normalizeVersion(entry.name) }))
        .sort((left, right) => left.normalized.localeCompare(right.normalized));
}

function resolveOffDirectory(offRoot, version) {
    const normalized = normalizeVersion(version);
    const matches = versionDirectories(offRoot).filter(item => item.normalized === normalized);
    if (matches.length !== 1) {
        throw new Error(`OFF ${normalized} 必须正好存在一个对应目录，当前 ${matches.length} 个。请先运行官网抓取 BAT。`);
    }
    return path.join(offRoot, matches[0].name);
}

function filenameFighterId(stem) {
    const exact = String(stem).match(/^f0(\d{2})$/i);
    if (exact) return Number(exact[1]);
    const compatible = String(stem).match(/(\d{2})$/);
    return compatible ? Number(compatible[1]) : null;
}

function loadOfficial(offDirectory, character, fighterId) {
    const filename = path.join(offDirectory, `${character}.official.generated.json`);
    if (!fs.existsSync(filename)) throw new Error(`OFF 缺少角色 ${character}: ${filename}`);
    const source = readSource(filename);
    const meta = source.value && source.value._meta || {};
    if (meta.schema !== "xt.modern_display.v1" || meta.generated_from !== "capcom_official"
        || meta.character !== character || Number(meta.fighter_id) !== Number(fighterId)) {
        throw new Error(`OFF 文件契约或 Fighter ID 不匹配: ${filename}`);
    }
    return source;
}

function loadCommunity(character) {
    const filename = path.join(COMMUNITY_ROOT, `${character}.verified.json`);
    if (!fs.existsSync(filename)) return null;
    const source = readSource(filename);
    const meta = source.value && source.value._meta || {};
    if (meta.schema !== "xt.modern_display.community.v1"
        || meta.generated_from !== "verified_runtime_observation" || meta.character !== character) {
        throw new Error(`Community 文件契约不匹配: ${filename}`);
    }
    return source;
}

function validateOutput(output, character, fighterId) {
    const meta = output && output._meta || {};
    const supportedSchemas = new Set([commandDisplay.SCHEMA]);
    if (!supportedSchemas.has(meta.schema) || meta.character !== character
        || Number(meta.fighter_id) !== Number(fighterId)) {
        throw new Error(`${character} 指令输出 schema/角色/Fighter ID 不匹配。`);
    }
    const audit = meta.audit || {};
    for (const field of ZERO_AUDIT_FIELDS) {
        if (Number(audit[field] || 0) !== 0) throw new Error(`${character} hard audit 失败: ${field}=${audit[field]}`);
    }
    const count = Object.keys(output).filter(key => /^\d+$/.test(key)).length;
    if (!count) throw new Error(`${character} 指令输出没有任何 Action ID。`);
    if (meta.schema === commandDisplay.SCHEMA) {
        let classicCount = 0, modernCount = 0, sharedCount = 0;
        for (const [id, entry] of Object.entries(numericEntries(output))) {
            for (const slot of ["classic_command", "simple_command", "motion_command"]) {
                if (!Object.prototype.hasOwnProperty.call(entry, slot)) {
                    throw new Error(`${character} Action ${id} 缺少统一指令槽 ${slot}。`);
                }
                const command = entry[slot];
                const valid = command === null || (typeof command === "object"
                    && typeof command.display === "string" && command.display.trim() !== ""
                    && Array.isArray(command.inputs) && command.inputs.length > 0
                    && command.inputs.every(input => typeof input === "string" && input.trim() !== ""));
                if (!valid) throw new Error(`${character} Action ${id} ${slot} 契约无效。`);
            }
            const classic = entry && entry.classic_command;
            const hasClassic = classic && typeof classic.display === "string"
                && classic.display.trim() !== "" && Array.isArray(classic.inputs)
                && classic.inputs.length > 0 && classic.inputs.every(input =>
                    typeof input === "string" && input.trim() !== "");
            if (classic !== null && classic !== undefined && !hasClassic) {
                throw new Error(`${character} Action ${id} classic_command 契约无效。`);
            }
            const hasModern = Boolean(entry.simple_command || entry.motion_command);
            const expectedSupport = hasClassic && hasModern ? "classic_modern"
                : (hasClassic ? "classic_only" : "unknown");
            if (entry.control_support !== expectedSupport) {
                throw new Error(`${character} Action ${id} control_support 与指令槽不一致。`);
            }
            if (hasClassic) classicCount += 1;
            if (hasModern) modernCount += 1;
            if (hasClassic && hasModern) sharedCount += 1;
        }
        if (Number(audit.command_display_action_count) !== count
            || Number(audit.classic_command_action_count) !== classicCount
            || Number(audit.split_command_action_count) !== modernCount
            || Number(audit.shared_command_action_count) !== sharedCount
            || Number(audit.classic_projection_pending_count) !== modernCount - sharedCount) {
            throw new Error(`${character} 统一指令覆盖审计与实际条目不一致。`);
        }
        if (modernCount !== sharedCount || Number(audit.classic_projection_pending_count) !== 0) {
            throw new Error(`${character} 仍有现代指令缺少经典投影: ${modernCount - sharedCount}`);
        }
        const projectionRelations = Array.isArray(meta.classic_projection_relations)
            ? meta.classic_projection_relations : [];
        const projectionCount = Number(meta.classic_projection_relation_count);
        if (!Number.isInteger(projectionCount) || projectionCount !== projectionRelations.length
            || Number(audit.classic_projection_relation_count) !== projectionCount) {
            throw new Error(`${character} 经典投影关系审计不一致。`);
        }
        const projectionReasons = new Set([
            "ac_full_structure_unique_classic_projection",
            "ac_full_structure_bcm_condition_classic_projection",
            "ac_full_structure_assist_strength_classic_projection",
            "bcm_unique_condition_classic_projection"
        ]);
        for (const relation of projectionRelations) {
            if (!relation || !Number.isFinite(Number(relation.source_action_id))
                || !Number.isFinite(Number(relation.target_action_id))
                || Number(relation.source_action_id) === Number(relation.target_action_id)
                || typeof relation.classic_display !== "string" || relation.classic_display.trim() === ""
                || !projectionReasons.has(relation.reason)) {
                throw new Error(`${character} 经典投影关系契约无效。`);
            }
        }
    }
    return count;
}

function numericEntries(value) {
    return Object.fromEntries(Object.entries(value || {}).filter(([key]) => /^\d+$/.test(key)));
}

function mapDiff(before, after) {
    const left = numericEntries(before), right = numericEntries(after);
    const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort((a, b) => Number(a) - Number(b));
    const added = [], removed = [], changed = [];
    for (const key of keys) {
        if (!(key in left)) added.push(Number(key));
        else if (!(key in right)) removed.push(Number(key));
        else if (JSON.stringify(left[key]) !== JSON.stringify(right[key])) changed.push(Number(key));
    }
    return { added, removed, changed };
}

function copyFileAtomic(source, destination) {
    const temporary = `${destination}.${process.pid}.${Date.now()}.tmp`;
    fs.copyFileSync(source, temporary);
    try {
        try {
            fs.renameSync(temporary, destination);
        } catch (error) {
            if (!fs.existsSync(destination) || !["EPERM", "EEXIST", "ENOTEMPTY"].includes(error && error.code)) {
                throw error;
            }
            fs.copyFileSync(temporary, destination);
            fs.rmSync(temporary, { force: true });
        }
    } finally {
        if (fs.existsSync(temporary)) fs.rmSync(temporary, { force: true });
    }
}

function replaceDirectory(stage, target) {
    const parent = path.dirname(target);
    const backup = path.join(parent, `.lastjson-backup-${process.pid}-${Date.now()}`);
    let backedUp = false;
    let stageMoved = false;
    try {
        if (fs.existsSync(target)) {
            fs.renameSync(target, backup);
            backedUp = true;
        }
        fs.renameSync(stage, target);
        stageMoved = true;
        if (backedUp) {
            try {
                fs.rmSync(backup, { recursive: true, force: true });
            } catch (cleanupError) {
                console.warn(`警告: 新 lastjson 已生效，但旧备份暂时无法删除: ${backup} (${cleanupError.code || cleanupError.message})`);
            }
        }
    } catch (error) {
        if (stageMoved) return;
        if (!fs.existsSync(target) && backedUp && fs.existsSync(backup)) fs.renameSync(backup, target);
        if (error && error.code !== "EPERM") throw error;

        // Windows may reject directory rename even when every file is writable.
        // Fall back to a transactional file-level replacement.  A full backup
        // is kept until all staged files have been copied successfully.
        const fallbackBackup = `${backup}-copy`;
        const hadTarget = fs.existsSync(target);
        if (hadTarget) fs.cpSync(target, fallbackBackup, { recursive: true });
        else fs.mkdirSync(target, { recursive: true });
        try {
            const stagedNames = fs.readdirSync(stage).filter(name => name.endsWith(".json"));
            for (const name of stagedNames) copyFileAtomic(path.join(stage, name), path.join(target, name));
            const finalNames = fs.readdirSync(target).filter(name => name.endsWith(".json"));
            if (finalNames.length !== stagedNames.length
                || finalNames.some(name => !stagedNames.includes(name))) {
                throw new Error("Windows fallback 覆盖后的 lastjson 文件集合与暂存集合不一致。")
            }
        } catch (copyError) {
            if (hadTarget && fs.existsSync(fallbackBackup)) {
                fs.rmSync(target, { recursive: true, force: true });
                fs.cpSync(fallbackBackup, target, { recursive: true });
            } else if (!hadTarget && fs.existsSync(target)) {
                fs.rmSync(target, { recursive: true, force: true });
            }
            throw copyError;
        } finally {
            if (fs.existsSync(fallbackBackup)) {
                try {
                    fs.rmSync(fallbackBackup, { recursive: true, force: true });
                } catch (cleanupError) {
                    console.warn(`警告: fallback 备份暂时无法删除: ${fallbackBackup} (${cleanupError.code || cleanupError.message})`);
                }
            }
        }
    }
}

function replaceDirectorySet(items) {
    const stamp = `${process.pid}-${Date.now()}`;
    const prepared = items.map((item, index) => ({
        stage: path.resolve(item.stage),
        target: path.resolve(item.target),
        existed: fs.existsSync(item.target),
        backup: path.join(path.dirname(path.resolve(item.target)), `.lastjson-set-backup-${stamp}-${index}`)
    }));
    let replacementStarted = false;
    try {
        for (const item of prepared) {
            if (item.existed) fs.cpSync(item.target, item.backup, { recursive: true });
        }
        replacementStarted = true;
        for (const item of prepared) replaceDirectory(item.stage, item.target);
    } catch (error) {
        const restoreErrors = [];
        if (replacementStarted) for (const item of prepared) {
            try {
                if (item.existed && fs.existsSync(item.backup)) {
                    const restoreStage = `${item.backup}-restore`;
                    fs.cpSync(item.backup, restoreStage, { recursive: true });
                    replaceDirectory(restoreStage, item.target);
                } else if (!item.existed && fs.existsSync(item.target)) {
                    fs.rmSync(item.target, { recursive: true, force: true });
                }
            } catch (restoreError) {
                restoreErrors.push(`${item.target}: ${restoreError.message}`);
            }
        }
        if (restoreErrors.length) {
            throw new Error(`${error.message}；游戏/网页目录回滚失败：${restoreErrors.join("；")}`);
        }
        throw error;
    } finally {
        for (const item of prepared) {
            if (fs.existsSync(item.backup)) fs.rmSync(item.backup, { recursive: true, force: true });
            const restoreStage = `${item.backup}-restore`;
            if (fs.existsSync(restoreStage)) fs.rmSync(restoreStage, { recursive: true, force: true });
        }
    }
}

function buildVersion(options) {
    const versionDirectory = path.resolve(options.versionDirectory);
    const versionName = path.basename(versionDirectory);
    const normalizedVersion = normalizeVersion(versionName);
    const offDirectory = resolveOffDirectory(path.resolve(options.offRoot), versionName);
    const registry = readJson(CHARACTER_MANIFEST);
    const expected = new Map(Object.entries(registry).map(([character, entry]) =>
        [Number(entry.fighter_id), character]));
    if (expected.size !== 30) throw new Error(`角色清单不是30个唯一 Fighter ID: ${expected.size}`);

    const scan = archive.scanDumpDirectory(versionDirectory);
    if (scan.incomplete.length) {
        throw new Error(`${versionName} 有 ${scan.incomplete.length} 个 AC/BCM 文件未配对。`);
    }
    const pairsById = new Map();
    for (const pair of scan.pairs) {
        const ac = readSource(path.join(versionDirectory, pair.ac));
        const bcm = readSource(path.join(versionDirectory, pair.bcm));
        const fighterId = Number(ac.value.fighter_id);
        const filenameId = filenameFighterId(pair.stem);
        if (!expected.has(fighterId)) throw new Error(`${pair.stem} 的 fighter_id=${fighterId} 不在30角色清单。`);
        if (filenameId !== null && filenameId !== fighterId) {
            throw new Error(`${pair.stem} 文件名ID=${filenameId} 与 AC fighter_id=${fighterId} 不一致。`);
        }
        if (Number(bcm.value.fighter_id) !== fighterId) {
            throw new Error(`${pair.stem} 的 AC/BCM fighter_id 不一致。`);
        }
        if (pairsById.has(fighterId)) throw new Error(`Fighter ID ${fighterId} 存在重复 AC/BCM 配对。`);
        pairsById.set(fighterId, { pair, ac, bcm });
    }
    const missing = [...expected.keys()].filter(id => !pairsById.has(id));
    if (missing.length || pairsById.size !== 30) {
        throw new Error(`${versionName} 必须包含30角色完整配对；缺少 Fighter ID: ${missing.join(", ") || "无"}。`);
    }

    const target = path.join(versionDirectory, "lastjson");
    const webTarget = path.join(versionDirectory, "lastjson_web");
    const previous = new Map();
    if (fs.existsSync(target)) for (const character of expected.values()) {
        const filename = path.join(target, `${character}.json`);
        if (fs.existsSync(filename)) previous.set(character, readJson(filename));
    }
    const stageStamp = `${process.pid}-${Date.now()}`;
    const stage = path.join(versionDirectory, `.lastjson-stage-${stageStamp}`);
    const webStage = path.join(versionDirectory, `.lastjson-web-stage-${stageStamp}`);
    fs.mkdirSync(stage, { recursive: true });
    fs.mkdirSync(webStage, { recursive: true });
    const results = [];
    try {
        for (const fighterId of [...expected.keys()].sort((a, b) => a - b)) {
            const character = expected.get(fighterId);
            const { pair, ac, bcm } = pairsById.get(fighterId);
            const official = loadOfficial(offDirectory, character, fighterId);
            const community = loadCommunity(character);
            const options = {
                actionSourceSha256: ac.sha256,
                bcmSourceSha256: bcm.sha256,
                characterName: character,
                generatedAt: `${normalizedVersion}T00:00:00.000Z`,
                officialSemantics: official.value,
                officialSemanticsSha256: official.sha256,
                communitySemantics: community && community.value,
                communitySemanticsSha256: community && community.sha256
            };
            const catalog = bcmCore.buildCatalog(bcm.value, {
                characterName: character, sourceSha256: bcm.sha256,
                generatedAt: options.generatedAt
            });
            const compiled = compiler.compileFromCatalog(ac.value, catalog, {}, options);
            if (compiled.report.status === "invalid") throw new Error(`${character} AC+BCM 编译为 invalid。`);
            const output = commandDisplay.buildCommandDisplay(ac.value, catalog, compiled.runtime, {}, options);
            const actionCount = validateOutput(output, character, fighterId);
            const outputBytes = Buffer.from(`${JSON.stringify(output, null, 2)}\n`, "utf8");
            const webOutput = webCharacter.buildWebCharacter(output, {
                generatedAt: options.generatedAt,
                commandSourceSha256: sha256(outputBytes),
                officialSnapshot: official.value,
                officialSha256: official.sha256
            });
            const webCounts = webCharacter.validateWebCharacter(webOutput, output);
            const webOutputBytes = Buffer.from(`${JSON.stringify(webOutput, null, 2)}\n`, "utf8");
            writeJson(path.join(stage, `${character}.json`), output);
            writeJson(path.join(webStage, `${character}.json`), webOutput);
            const difference = mapDiff(previous.get(character), output);
            results.push({
                character, fighter_id: fighterId, stem: pair.stem,
                ac_file: pair.ac, bcm_file: pair.bcm,
                official_file: path.basename(path.join(offDirectory, `${character}.official.generated.json`)),
                output_file: `${character}.json`, action_count: actionCount,
                output_sha256: sha256(outputBytes),
                web_output_file: `${character}.json`,
                web_action_count: webCounts.action_count,
                web_move_count: webCounts.move_count,
                web_output_sha256: sha256(webOutputBytes),
                difference
            });
        }
        if (fs.readdirSync(stage).filter(name => name.endsWith(".json")).length !== 30) {
            throw new Error("暂存输出不是正好30个角色 JSON。")
        }
        if (fs.readdirSync(webStage).filter(name => name.endsWith(".json")).length !== 30) {
            throw new Error("网页暂存输出不是正好30个角色 JSON。")
        }
        replaceDirectorySet([
            { stage, target },
            { stage: webStage, target: webTarget }
        ]);
    } finally {
        if (fs.existsSync(stage)) fs.rmSync(stage, { recursive: true, force: true });
        if (fs.existsSync(webStage)) fs.rmSync(webStage, { recursive: true, force: true });
    }
    const manifest = {
        schema: "sf6cc.command-lastjson-manifest.v1",
        version: normalizedVersion,
        source_directory: versionDirectory,
        official_directory: offDirectory,
        character_count: results.length,
        command_schema: commandDisplay.SCHEMA,
        web_character_schema: webCharacter.SCHEMA,
        web_output_directory: webTarget,
        characters: results
    };
    writeJson(path.join(versionDirectory, "lastjson-manifest.json"), manifest);
    return { version: normalizedVersion, directory: versionDirectory, output: target,
        web_output: webTarget, results };
}

function run(argv) {
    const args = argsOf(argv);
    const acbcmRoot = path.resolve(args["--acbcm-root"] || DEFAULT_ACBCM_ROOT);
    const offRoot = path.resolve(args["--off-root"] || DEFAULT_OFF_ROOT);
    let versions = versionDirectories(acbcmRoot);
    if (args["--version"]) {
        const wanted = normalizeVersion(args["--version"]);
        versions = versions.filter(item => item.normalized === wanted);
        if (versions.length !== 1) throw new Error(`ACBCM ${wanted} 必须正好存在一个对应目录，当前 ${versions.length} 个。`);
    }
    if (!versions.length) throw new Error(`没有找到 ACBCM 版本目录: ${acbcmRoot}`);
    const outputs = [];
    for (const version of versions) {
        console.log(`\n[${version.name}] 开始生成 lastjson`);
        const result = buildVersion({
            versionDirectory: path.join(acbcmRoot, version.name), offRoot
        });
        outputs.push(result);
        const changed = result.results.filter(item => item.difference.added.length
            || item.difference.removed.length || item.difference.changed.length).length;
        console.log(`[${version.name}] 完成：30/30，变化角色 ${changed}，游戏输出 ${result.output}，网页输出 ${result.web_output}`);
    }
    console.log(`\n全部完成：${outputs.length} 个版本。`);
}

if (require.main === module) {
    try {
        run(process.argv.slice(2));
    } catch (error) {
        console.error(`错误: ${error.message}`);
        process.exitCode = 2;
    }
}

module.exports = {
    normalizeVersion, versionDirectories, filenameFighterId, mapDiff,
    resolveOffDirectory, validateOutput, replaceDirectory, replaceDirectorySet, buildVersion
};
