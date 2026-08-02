#!/usr/bin/env node

import { promises as fs } from "node:fs";
import path from "node:path";
import process from "node:process";
import {
    characterByFolder,
    folderFromPath
} from "./character_catalog.mjs";
import {
    normalizeCounterPolicyDocument,
    resolveCounterPolicy
} from "./combo_json_core.mjs";
import { resourceDefinitionsForFighter } from "./unique_resource_catalog.mjs";

const ENVIRONMENT_SCHEMA = "xt.training_environment.v1";
const SCENE_SCHEMA_V2 = "xt.combo_trial.scene.v2";
const SCENE_RESOURCE_DEFAULTS = Object.freeze({
    hp: 10000,
    drive: 60000,
    super: 30000
});

/*
 * These are the defaults exposed by the local metadata editor.  Guard is the
 * deliberate collection-wide exception requested for the maintained combo
 * library: old unrecorded guard settings become "after first hit" instead of
 * the game's "no guard" default.
 */
const MENU_DEFAULTS = Object.freeze({
    dummy_counter_type: 0,
    dummy_counter_weight_normal: 1,
    dummy_counter_weight_counter: 1,
    dummy_counter_weight_punish: 1,
    dummy_guard_type: 2,
    dummy_guard_count: 10,
    dummy_guard_only_type: 0,
    dummy_drive_parry_type: 0,
    dummy_drive_reversal_type: 0,
    dummy_drive_reversal_delay: 0,
    dummy_drive_reversal_count: 1,
    dummy_drive_reversal_weight_none: 1,
    dummy_drive_reversal_weight_guard: 1,
    dummy_drive_reversal_weight_wakeup: 1,
    dummy_throw_escape_type: 0,
    dummy_wakeup_type: 0
});

const ACTION_STANCES = Object.freeze({
    0: "stand",
    1: "crouch",
    2: "jump"
});

const STANCE_ACTIONS = Object.freeze({
    stand: 0,
    standing: 0,
    crouch: 1,
    crouching: 1,
    jump: 2,
    jumping: 2,
    airborne: 2
});

function usage() {
    return [
        "用法 (usage):",
        "  node fill_dummy_menu_defaults.mjs --root <CustomCombos目录> [--write] [--expected-count 996]",
        "",
        "默认仅预演；--write 原地写入，不创建备份。"
    ].join("\n");
}

function parseArgs(argv) {
    const options = {
        root: "",
        write: false,
        expectedCount: null
    };

    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--root") {
            options.root = argv[++index] || "";
        } else if (arg === "--write") {
            options.write = true;
        } else if (arg === "--expected-count") {
            const value = Number(argv[++index]);
            if (!Number.isInteger(value) || value < 1) {
                throw new Error("--expected-count 必须是正整数");
            }
            options.expectedCount = value;
        } else if (arg === "--help" || arg === "-h") {
            console.log(usage());
            process.exit(0);
        } else {
            throw new Error(`未知参数 (unknown argument): ${arg}`);
        }
    }

    if (!options.root) throw new Error("缺少 --root");
    return options;
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isEmpty(value) {
    return value === undefined
        || value === null
        || (typeof value === "string" && value.trim() === "");
}

function comparable(value) {
    if (typeof value === "number" || typeof value === "boolean") return String(value);
    if (typeof value === "string") {
        const text = value.trim();
        const number = Number(text);
        return text !== "" && Number.isFinite(number) ? String(number) : text.toLowerCase();
    }
    return JSON.stringify(value);
}

async function findJsonFiles(root) {
    const files = [];
    async function visit(directory) {
        const entries = await fs.readdir(directory, { withFileTypes: true });
        entries.sort((left, right) => left.name.localeCompare(right.name, "en"));
        for (const entry of entries) {
            const fullPath = path.join(directory, entry.name);
            if (entry.isDirectory()) {
                await visit(fullPath);
            } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) {
                files.push(fullPath);
            }
        }
    }
    await visit(root);
    return files;
}

function ensureContainers(document, relativePath) {
    if (!Array.isArray(document) || document.length === 0 || !isObject(document[0])) {
        throw new Error(`${relativePath}: 根节点必须是非空步骤数组`);
    }
    const first = document[0];
    if (!isObject(first._xt_meta)) {
        throw new Error(`${relativePath}: 缺少 _xt_meta，不能作为新规范 JSON 修改`);
    }
    const meta = first._xt_meta;
    if (!isObject(meta.environment)) {
        if (!isEmpty(meta.environment)) {
            throw new Error(`${relativePath}: _xt_meta.environment 不是对象`);
        }
        meta.environment = {};
    }
    return { first, meta, environment: meta.environment };
}

function locations(containers, field) {
    const { first, meta, environment } = containers;
    return [
        { name: "step", object: first, value: first[field] },
        { name: "meta", object: meta, value: meta[field] },
        { name: "environment", object: environment, value: environment[field] }
    ];
}

function existingValue(containers, field) {
    return locations(containers, field).find(location => !isEmpty(location.value))?.value;
}

function conflictingValues(containers, field) {
    const values = locations(containers, field)
        .filter(location => !isEmpty(location.value))
        .map(location => ({ location: location.name, value: location.value }));
    const distinct = new Set(values.map(entry => comparable(entry.value)));
    return distinct.size > 1 ? values : null;
}

function fillReplicas(containers, field, fallback, report) {
    const existing = existingValue(containers, field);
    const value = isEmpty(existing) ? fallback : existing;
    if (isEmpty(value)) return;

    for (const location of locations(containers, field)) {
        if (!isEmpty(location.value)) continue;
        location.object[field] = value;
        report.insertions[field] = (report.insertions[field] || 0) + 1;
        report.changed = true;
    }
}

function resolveAction(containers) {
    const actionValue = existingValue(containers, "dummy_action_type");
    const actionNumber = Number(actionValue);
    if (!isEmpty(actionValue) && Number.isInteger(actionNumber) && actionNumber in ACTION_STANCES) {
        return actionNumber;
    }

    const stanceValue = existingValue(containers, "dummy_stance");
    const stance = String(stanceValue ?? "").trim().toLowerCase();
    if (stance in STANCE_ACTIONS) return STANCE_ACTIONS[stance];

    const crouchValue = existingValue(containers, "requires_dummy_crouch");
    if (crouchValue === true || crouchValue === 1 || crouchValue === "1" || crouchValue === "true") {
        return 1;
    }
    return 0;
}

function fillAction(containers, report) {
    const action = resolveAction(containers);
    const stance = ACTION_STANCES[action];
    fillReplicas(containers, "dummy_action_type", action, report);
    fillReplicas(containers, "dummy_jump_type", 0, report);
    fillReplicas(containers, "dummy_stance", stance, report);

    const crouchValue = existingValue(containers, "requires_dummy_crouch");
    const resolvedCrouch = isEmpty(crouchValue) ? action === 1 : crouchValue;
    for (const location of [
        { object: containers.first, value: containers.first.requires_dummy_crouch },
        { object: containers.meta, value: containers.meta.requires_dummy_crouch }
    ]) {
        if (!isEmpty(location.value)) continue;
        location.object.requires_dummy_crouch = resolvedCrouch;
        report.insertions.requires_dummy_crouch =
            (report.insertions.requires_dummy_crouch || 0) + 1;
        report.changed = true;
    }
}

function markInsertion(report, field) {
    report.insertions[field] = (report.insertions[field] || 0) + 1;
    report.changed = true;
}

function fillEmpty(object, field, value, report, reportField) {
    if (!isEmpty(object[field])) return object[field];
    object[field] = value;
    markInsertion(report, reportField || field);
    return value;
}

function ensureScenePlayer(scene, side, report) {
    if (!isObject(scene.players)) {
        if (!isEmpty(scene.players)) {
            throw new Error(`scene_state.players 不是对象`);
        }
        scene.players = {};
        markInsertion(report, "scene_state.players");
    }
    if (!isObject(scene.players[side])) {
        if (!isEmpty(scene.players[side])) {
            throw new Error(`scene_state.players.${side} 不是对象`);
        }
        scene.players[side] = {};
        markInsertion(report, `scene_state.players.${side}`);
    }
    return scene.players[side];
}

function fillPlayerBasics(player, side, defaultFighterId, report, defaults = {}) {
    fillEmpty(player, "fighter_id", defaultFighterId, report, `${side}.fighter_id`);

    if (!isObject(player.resources)) {
        if (!isEmpty(player.resources)) {
            throw new Error(`scene_state.players.${side}.resources 不是对象`);
        }
        player.resources = {};
        markInsertion(report, `${side}.resources`);
    }
    const resourceDefaults = {
        ...SCENE_RESOURCE_DEFAULTS,
        ...(isObject(defaults.resources) ? defaults.resources : {})
    };
    for (const [field, value] of Object.entries(resourceDefaults)) {
        fillEmpty(player.resources, field, value, report, `${side}.resources.${field}`);
    }

    if (!isObject(player.status)) {
        if (!isEmpty(player.status)) {
            throw new Error(`scene_state.players.${side}.status 不是对象`);
        }
        player.status = {};
        markInsertion(report, `${side}.status`);
    }
    fillEmpty(
        player.status,
        "burnout",
        defaults.burnout ?? false,
        report,
        `${side}.status.burnout`
    );
}

function legacyOpeningWallStun(first, scene = null) {
    if (!isObject(first)
        || first.has_piyo !== true
        || !Number.isFinite(Number(first.piyo_frame))
        || Number(first.piyo_frame) <= 0
        || Number(first.recorded_by ?? scene?.recorded_by) !== 0
        || ![854, 855].includes(Number(first.id))
        || String(first.motion || "").trim().toUpperCase() !== "DI") {
        return null;
    }
    return {
        defenderSide: "p2",
        blocked: first.has_hit !== true
    };
}

function uniqueObject(player, side, report) {
    if (!isObject(player.unique)) {
        if (!isEmpty(player.unique)) {
            throw new Error(`scene_state.players.${side}.unique 不是对象`);
        }
        player.unique = {};
        markInsertion(report, `${side}.unique`);
    }
    return player.unique;
}

function fillIndependentUnique(player, side, report) {
    const definitions = resourceDefinitionsForFighter(player.fighter_id);
    if (!definitions.length) return;
    const unique = uniqueObject(player, side, report);
    for (const resource of definitions) {
        fillEmpty(unique, resource.id, 0, report, `${side}.unique.${resource.id}`);
    }
}

function fillSharedUnique(players, recordedBy, report) {
    const definitions = resourceDefinitionsForFighter(players.p1.fighter_id);
    if (!definitions.length) return;

    const actorSide = recordedBy === 1 ? "p2" : "p1";
    const dummySide = actorSide === "p1" ? "p2" : "p1";
    const actorUnique = isObject(players[actorSide].unique) ? players[actorSide].unique : null;
    const dummyUnique = isObject(players[dummySide].unique) ? players[dummySide].unique : null;

    for (const resource of definitions) {
        const actorValue = actorUnique?.[resource.id];
        const dummyValue = dummyUnique?.[resource.id];
        if (!isEmpty(actorValue)
            && !isEmpty(dummyValue)
            && comparable(actorValue) !== comparable(dummyValue)) {
            report.conflicts.push({
                field: `scene_state.shared_unique.${resource.id}`,
                values: [
                    { location: actorSide, value: actorValue },
                    { location: dummySide, value: dummyValue }
                ]
            });
        }
        const value = !isEmpty(actorValue)
            ? actorValue
            : !isEmpty(dummyValue)
                ? dummyValue
                : 0;
        const p1Unique = uniqueObject(players.p1, "p1", report);
        const p2Unique = uniqueObject(players.p2, "p2", report);
        fillEmpty(p1Unique, resource.id, value, report, `p1.unique.${resource.id}`);
        fillEmpty(p2Unique, resource.id, value, report, `p2.unique.${resource.id}`);
    }
}

function fillSceneDefaults(document, relativePath, report, wallStun) {
    const first = document[0];
    const folder = folderFromPath(relativePath);
    const folderCharacter = characterByFolder(folder);
    if (!folderCharacter) {
        throw new Error(`${relativePath}: 无法从文件夹识别默认 Fighter ID`);
    }

    if (!isObject(first.scene_state)) {
        if (!isEmpty(first.scene_state)) {
            throw new Error(`${relativePath}: scene_state 不是对象`);
        }
        first.scene_state = {};
        markInsertion(report, "scene_state");
    }
    const scene = first.scene_state;
    fillEmpty(scene, "capture_mode", "portable", report, "scene_state.capture_mode");
    const fallbackRecordedBy = Number(first.recorded_by) === 1 ? 1 : 0;
    const recordedByValue = fillEmpty(
        scene,
        "recorded_by",
        fallbackRecordedBy,
        report,
        "scene_state.recorded_by"
    );
    const recordedBy = Number(recordedByValue) === 1 ? 1 : 0;

    const p1 = ensureScenePlayer(scene, "p1", report);
    const p2 = ensureScenePlayer(scene, "p2", report);
    const burnoutDefaults = wallStun
        ? { resources: { drive: 0 }, burnout: true }
        : {};
    fillPlayerBasics(
        p1,
        "p1",
        folderCharacter.fighterId,
        report,
        wallStun?.defenderSide === "p1" ? burnoutDefaults : {}
    );
    fillPlayerBasics(
        p2,
        "p2",
        folderCharacter.fighterId,
        report,
        wallStun?.defenderSide === "p2" ? burnoutDefaults : {}
    );

    if (Number(p1.fighter_id) === Number(p2.fighter_id)) {
        fillSharedUnique({ p1, p2 }, recordedBy, report);
    } else {
        fillIndependentUnique(p1, "p1", report);
        fillIndependentUnique(p2, "p2", report);
    }

    if (scene.schema !== SCENE_SCHEMA_V2) {
        scene.schema = SCENE_SCHEMA_V2;
        markInsertion(report, "scene_state.schema");
    }
}

function mutateDocument(document, relativePath) {
    const report = { changed: false, insertions: {}, conflicts: [] };
    const counterResolution = resolveCounterPolicy(document, {
        recoverLegacyZero: true
    });
    if (counterResolution.ambiguous) {
        throw new Error(`${relativePath}: 打康菜单旧字段存在歧义`);
    }
    const beforeCounterNormalization = JSON.stringify(document);
    normalizeCounterPolicyDocument(document, {
        counterType: counterResolution.counterType,
        inPlace: true
    });
    if (JSON.stringify(document) !== beforeCounterNormalization) {
        report.insertions.counter_policy_normalized = 1;
        report.changed = true;
    }
    const containers = ensureContainers(document, relativePath);
    const wallStun = legacyOpeningWallStun(
        containers.first,
        isObject(containers.first.scene_state) ? containers.first.scene_state : null
    );

    for (const field of [
        "dummy_action_type",
        "dummy_jump_type",
        "dummy_stance",
        ...Object.keys(MENU_DEFAULTS)
    ]) {
        const conflict = conflictingValues(containers, field);
        if (conflict) report.conflicts.push({ field, values: conflict });
    }

    fillAction(containers, report);
    for (const [field, defaultValue] of Object.entries(MENU_DEFAULTS)) {
        const resolvedDefault = field === "dummy_guard_type" && wallStun?.blocked
            ? 3
            : defaultValue;
        fillReplicas(containers, field, resolvedDefault, report);
    }

    if (containers.environment.schema !== ENVIRONMENT_SCHEMA) {
        if (isEmpty(containers.environment.schema)) {
            containers.environment.schema = ENVIRONMENT_SCHEMA;
            report.insertions["environment.schema"] =
                (report.insertions["environment.schema"] || 0) + 1;
            report.changed = true;
        } else {
            report.conflicts.push({
                field: "environment.schema",
                values: [{ location: "environment", value: containers.environment.schema }]
            });
        }
    }
    fillSceneDefaults(document, relativePath, report, wallStun);
    return report;
}

function collectChangedPaths(before, after, prefix = "") {
    if (Object.is(before, after)) return [];
    if (Array.isArray(before) && Array.isArray(after)) {
        const paths = [];
        const length = Math.max(before.length, after.length);
        for (let index = 0; index < length; index += 1) {
            paths.push(...collectChangedPaths(
                before[index],
                after[index],
                `${prefix}[${index}]`
            ));
        }
        return paths;
    }
    if (isObject(before) && isObject(after)) {
        const paths = [];
        const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
        for (const key of keys) {
            paths.push(...collectChangedPaths(
                before[key],
                after[key],
                prefix ? `${prefix}.${key}` : key
            ));
        }
        return paths;
    }
    return [prefix || "$"];
}

function isAllowedPath(changedPath) {
    const fieldPattern = [
        "dummy_action_type",
        "dummy_jump_type",
        "dummy_stance",
        "requires_dummy_crouch",
        ...Object.keys(MENU_DEFAULTS)
    ].join("|");
    const menuPath = new RegExp(
        `^\\[0\\](?:\\.(${fieldPattern})|\\._xt_meta(?:\\.(${fieldPattern})|\\.environment(?:\\.schema|\\.(${fieldPattern}))))$`
    );
    if (menuPath.test(changedPath)) return true;
    if (changedPath === "[0]._xt_meta.environment") return true;
    return /^\[0\]\.scene_state(?:$|\.schema$|\.capture_mode$|\.recorded_by$|\.players(?:$|\.(?:p1|p2)(?:$|\.fighter_id$|\.resources(?:$|\.(?:hp|drive|super)$)|\.status(?:$|\.burnout$)|\.unique(?:$|\.(?:timer|stock)_0_\d+$))))$/.test(changedPath);
}

function mergeCounts(target, source) {
    for (const [key, value] of Object.entries(source)) {
        target[key] = (target[key] || 0) + value;
    }
}

function assertPreserved(beforeValue, afterValue, relativePath, field) {
    if (isEmpty(beforeValue)) return;
    if (JSON.stringify(beforeValue) !== JSON.stringify(afterValue)) {
        throw new Error(`${relativePath}: 已记录值被覆盖: ${field}`);
    }
}

function validateResult(before, after, relativePath) {
    if (before.length !== after.length) {
        throw new Error(`${relativePath}: 步骤数量发生变化`);
    }
    const unexpected = collectChangedPaths(before, after).filter(value => !isAllowedPath(value));
    if (unexpected.length) {
        throw new Error(`${relativePath}: 检测到非菜单字段变化: ${unexpected.join(", ")}`);
    }

    const beforeFirst = before[0];
    const afterFirst = after[0];
    const beforeMeta = isObject(beforeFirst._xt_meta) ? beforeFirst._xt_meta : {};
    const afterMeta = afterFirst._xt_meta;
    const beforeEnvironment = isObject(beforeMeta.environment) ? beforeMeta.environment : {};
    const afterEnvironment = afterMeta.environment;
    for (const field of [
        "dummy_action_type",
        "dummy_jump_type",
        "dummy_stance",
        ...Object.keys(MENU_DEFAULTS)
    ]) {
        for (const [location, beforeObject, afterObject] of [
            ["step", beforeFirst, afterFirst],
            ["meta", beforeMeta, afterMeta],
            ["environment", beforeEnvironment, afterEnvironment]
        ]) {
            assertPreserved(
                beforeObject[field],
                afterObject[field],
                relativePath,
                `${location}.${field}`
            );
        }
    }
    for (const [location, beforeObject, afterObject] of [
        ["step", beforeFirst, afterFirst],
        ["meta", beforeMeta, afterMeta]
    ]) {
        assertPreserved(
            beforeObject.requires_dummy_crouch,
            afterObject.requires_dummy_crouch,
            relativePath,
            `${location}.requires_dummy_crouch`
        );
    }
    assertPreserved(
        beforeEnvironment.schema,
        afterEnvironment.schema,
        relativePath,
        "environment.schema"
    );

    const beforeScene = isObject(beforeFirst.scene_state) ? beforeFirst.scene_state : {};
    const afterScene = afterFirst.scene_state;
    for (const field of ["capture_mode", "recorded_by"]) {
        assertPreserved(
            beforeScene[field],
            afterScene[field],
            relativePath,
            `scene_state.${field}`
        );
    }
    for (const side of ["p1", "p2"]) {
        const beforePlayer = isObject(beforeScene.players?.[side])
            ? beforeScene.players[side]
            : {};
        const afterPlayer = afterScene.players[side];
        assertPreserved(
            beforePlayer.fighter_id,
            afterPlayer.fighter_id,
            relativePath,
            `${side}.fighter_id`
        );
        for (const field of Object.keys(SCENE_RESOURCE_DEFAULTS)) {
            assertPreserved(
                beforePlayer.resources?.[field],
                afterPlayer.resources[field],
                relativePath,
                `${side}.resources.${field}`
            );
        }
        assertPreserved(
            beforePlayer.status?.burnout,
            afterPlayer.status.burnout,
            relativePath,
            `${side}.status.burnout`
        );
        if (isObject(beforePlayer.unique)) {
            for (const [field, value] of Object.entries(beforePlayer.unique)) {
                assertPreserved(
                    value,
                    afterPlayer.unique?.[field],
                    relativePath,
                    `${side}.unique.${field}`
                );
            }
        }
    }
}

async function readEntries(root, files) {
    const entries = [];
    for (const file of files) {
        const relativePath = path.relative(root, file).replace(/\\/g, "/");
        const originalText = await fs.readFile(file, "utf8");
        let before;
        try {
            before = JSON.parse(originalText.replace(/^\uFEFF/, ""));
        } catch (error) {
            throw new Error(`${relativePath}: JSON 解析失败: ${error.message}`);
        }
        const after = JSON.parse(JSON.stringify(before));
        const report = mutateDocument(after, relativePath);
        validateResult(before, after, relativePath);
        entries.push({
            file,
            relativePath,
            originalText,
            before,
            after,
            report,
            outputText: report.changed ? `${JSON.stringify(after, null, 2)}\n` : originalText
        });
    }
    return entries;
}

function validateFilledEntry(entry) {
    const { first, meta, environment } = ensureContainers(entry.after, entry.relativePath);
    for (const field of [
        "dummy_action_type",
        "dummy_jump_type",
        "dummy_stance",
        ...Object.keys(MENU_DEFAULTS)
    ]) {
        for (const [location, object] of [
            ["step", first],
            ["meta", meta],
            ["environment", environment]
        ]) {
            if (isEmpty(object[field])) {
                throw new Error(`${entry.relativePath}: ${location}.${field} 仍为空`);
            }
        }
    }
    if (isEmpty(first.requires_dummy_crouch) || isEmpty(meta.requires_dummy_crouch)) {
        throw new Error(`${entry.relativePath}: requires_dummy_crouch 仍为空`);
    }

    const scene = entry.after[0].scene_state;
    if (!isObject(scene) || scene.schema !== SCENE_SCHEMA_V2 || !isObject(scene.players)) {
        throw new Error(`${entry.relativePath}: scene_state 未补齐为 scene.v2`);
    }
    for (const side of ["p1", "p2"]) {
        const player = scene.players[side];
        if (!isObject(player) || isEmpty(player.fighter_id)) {
            throw new Error(`${entry.relativePath}: ${side}.fighter_id 仍为空`);
        }
        for (const field of Object.keys(SCENE_RESOURCE_DEFAULTS)) {
            if (isEmpty(player.resources?.[field])) {
                throw new Error(`${entry.relativePath}: ${side}.resources.${field} 仍为空`);
            }
        }
        if (isEmpty(player.status?.burnout)) {
            throw new Error(`${entry.relativePath}: ${side}.status.burnout 仍为空`);
        }
        for (const resource of resourceDefinitionsForFighter(player.fighter_id)) {
            if (isEmpty(player.unique?.[resource.id])) {
                throw new Error(`${entry.relativePath}: ${side}.unique.${resource.id} 仍为空`);
            }
        }
    }
}

async function writeWithRollback(entries) {
    const written = [];
    try {
        for (const entry of entries) {
            if (!entry.report.changed) continue;
            await fs.writeFile(entry.file, entry.outputText, "utf8");
            written.push(entry);
        }
        for (const entry of entries) {
            const text = await fs.readFile(entry.file, "utf8");
            const diskDocument = JSON.parse(text.replace(/^\uFEFF/, ""));
            if (JSON.stringify(diskDocument) !== JSON.stringify(entry.after)) {
                throw new Error(`${entry.relativePath}: 写入后内容不一致`);
            }
        }
    } catch (error) {
        const rollbackErrors = [];
        for (const entry of written.reverse()) {
            try {
                await fs.writeFile(entry.file, entry.originalText, "utf8");
            } catch (rollbackError) {
                rollbackErrors.push(`${entry.relativePath}: ${rollbackError.message}`);
            }
        }
        if (rollbackErrors.length) {
            throw new Error(`${error.message}\n回滚失败:\n${rollbackErrors.join("\n")}`);
        }
        throw new Error(`${error.message}\n已回滚本次已写入文件。`);
    }
}

function printSummary(entries, root, write) {
    const changed = entries.filter(entry => entry.report.changed);
    const insertions = {};
    const conflicts = [];
    for (const entry of entries) {
        mergeCounts(insertions, entry.report.insertions);
        if (entry.report.conflicts.length) {
            conflicts.push({
                file: entry.relativePath,
                conflicts: entry.report.conflicts
            });
        }
    }

    console.log(`模式: ${write ? "原地写入" : "只读预演"}`);
    console.log(`目录: ${root}`);
    console.log(`JSON: ${entries.length}`);
    console.log(`需修改: ${changed.length}`);
    console.log(`无需修改: ${entries.length - changed.length}`);
    console.log(`字段补写次数: ${Object.values(insertions).reduce((sum, value) => sum + value, 0)}`);
    for (const [field, count] of Object.entries(insertions).sort()) {
        console.log(`  ${field}: ${count}`);
    }
    console.log(`已有副本冲突: ${conflicts.length}`);
    for (const conflict of conflicts.slice(0, 10)) {
        console.log(`  ${conflict.file}: ${conflict.conflicts.map(value => value.field).join(", ")}`);
    }
    if (conflicts.length > 10) console.log(`  ...另有 ${conflicts.length - 10} 个文件`);
}

async function main() {
    const options = parseArgs(process.argv.slice(2));
    const root = path.resolve(options.root);
    const stat = await fs.stat(root);
    if (!stat.isDirectory()) throw new Error(`不是目录: ${root}`);

    const files = await findJsonFiles(root);
    if (options.expectedCount !== null && files.length !== options.expectedCount) {
        throw new Error(`文件数不符：预期 ${options.expectedCount}，实际 ${files.length}`);
    }

    const entries = await readEntries(root, files);
    for (const entry of entries) validateFilledEntry(entry);
    printSummary(entries, root, options.write);

    if (options.write) {
        await writeWithRollback(entries);
        console.log(`完成：已原地写入 ${entries.filter(entry => entry.report.changed).length} 个文件。`);
    } else {
        console.log("预演完成：未写入文件。");
    }
}

main().catch(error => {
    console.error(`失败: ${error.message}`);
    process.exitCode = 1;
});
