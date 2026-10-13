#!/usr/bin/env node
"use strict";

// Read-only evidence audit. Locator pairing and exact-graph candidates never
// approve Move identity or become runtime exceptions.
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const archive = require("./archive_builder.js");
const bcm = require("../bcm_catalog_builder/bcm_catalog_core.js");
const groups = require("./trigger_group_core.js");
const transport = require("./web_handoff_builder.js");
const builder = require("./lastjson_builder.js");
const rosterCore = require("../fighter_roster.js");

const aliasField = name => /^p\d{2}_/.test(name);
const index = source => new Map((source.objects || []).map(object => [object.object_id, object]));
function vocabulary(source) {
    const types = new Map();
    for (const object of source.objects || []) {
        if (!types.has(object.object_type)) types.set(object.object_type, new Set());
        for (const field of object.fields || []) if (!aliasField(field.name)) types.get(object.object_type).add(field.name);
    }
    return types;
}
function sharedVocabulary(before, after) {
    const old = vocabulary(before), next = vocabulary(after);
    return new Map([...old].map(([type, fields]) => [type,
        new Set([...fields].filter(field => next.get(type)?.has(field)))]));
}
function projection(objects, allowed, neutral = false) {
    function value(item, seen) {
        if (item?.kind === "ref") return object(item.object_id, seen);
        if (Array.isArray(item)) return item.map(entry => value(entry, seen));
        if (!item || typeof item !== "object") return item;
        return Object.fromEntries(Object.keys(item).sort().filter(key => key !== "object_id")
            .map(key => [key, value(item[key], seen)]));
    }
    function object(id, seen = new Set()) {
        if (seen.has(id)) return { cycle: true };
        const current = objects.get(id);
        if (!current) throw new Error(`Unresolved graph ref: ${id}`);
        const descendants = new Set([...seen, id]);
        const output = { type: current.object_type };
        const fields = (current.fields || [])
            .filter(field => !aliasField(field.name) && (!allowed || allowed.get(current.object_type)?.has(field.name))
                && !(neutral && ["Action", "ActionID"].includes(field.name)))
            .sort((a, b) => a.name.localeCompare(b.name))
            .map(field => [field.name, value(field.value, descendants)]);
        if (fields.length) output.fields = Object.fromEntries(fields);
        if (current.items?.length) output.items = [...current.items].sort((a, b) => Number(a.index) - Number(b.index))
            .map(item => ({ index: item.index, value: value(item.value, descendants) }));
        return output;
    }
    return object;
}
function acRecords(source) {
    return new Map((source.records || []).map(record => [
        JSON.stringify([record.source_scope, record.resource_index, record.style_index, record.native_action_id]), record
    ]));
}
function keysFor(rootId, objects, project) {
    const root = objects.get(rootId);
    const keys = (root.fields || []).find(field => field.name === "Keys");
    const pending = keys?.value?.kind === "ref" ? [keys.value.object_id] : [];
    const visited = new Set(), result = {};
    while (pending.length) {
        const id = pending.pop();
        if (visited.has(id)) continue;
        visited.add(id);
        const current = objects.get(id);
        if (!current) throw new Error(`Unresolved key ref: ${id}`);
        if (/\.[^.]*Key$/.test(current.object_type)) {
            (result[current.object_type] ||= []).push(project(id));
            continue;
        }
        const refs = [...(current.fields || []), ...(current.items || [])]
            .filter(item => item.value?.kind === "ref").map(item => item.value.object_id);
        pending.push(...refs.reverse());
    }
    return result;
}
function multisetDiff(before, after) {
    const remaining = after.map(value => ({ encoded: JSON.stringify(value), value }));
    const removed = [];
    for (const value of before) {
        const found = remaining.findIndex(item => item.encoded === JSON.stringify(value));
        if (found < 0) removed.push(value);
        else remaining.splice(found, 1);
    }
    return { removed, added: remaining.map(item => item.value) };
}
function scalarGraph(node) {
    if (!node || typeof node !== "object") return node;
    if (Object.hasOwn(node, "value") && Object.hasOwn(node, "kind") && node.kind !== "ref") return node.value ?? null;
    if (Array.isArray(node)) return node.map(scalarGraph);
    return Object.fromEntries(Object.entries(node).map(([key, value]) => [key, scalarGraph(value)]));
}
function compareAc(before, after) {
    const allowed = sharedVocabulary(before, after), oldObjects = index(before), newObjects = index(after);
    const oldProject = projection(oldObjects, allowed), newProject = projection(newObjects, allowed);
    const oldFull = projection(oldObjects, null), newFull = projection(newObjects, null);
    const oldTypes = vocabulary(before), newTypes = vocabulary(after);
    const oldRecords = acRecords(before), newRecords = acRecords(after);
    const changes = [], rawFrameDeltas = [], incomparableKeys = [];
    for (const [locator, next] of newRecords) {
        const previous = oldRecords.get(locator);
        if (!previous) { changes.push({ locator, action_id: next.native_action_id, scope: next.source_scope,
            added_locator: true, snapshot: scalarGraph(newFull(next.action_ref.object_id)), auto_approved: false }); continue; }
        const old = oldProject(previous.action_ref.object_id), current = newProject(next.action_ref.object_id);
        const oldFields = { ...old.fields }, newFields = { ...current.fields };
        delete oldFields.Keys; delete newFields.Keys;
        const fields = transport.deltas(scalarGraph(oldFields), scalarGraph(newFields));
        const oldKeys = keysFor(previous.action_ref.object_id, oldObjects, oldProject);
        const newKeys = keysFor(next.action_ref.object_id, newObjects, newProject);
        const keys = {};
        for (const type of [...new Set([...Object.keys(oldKeys), ...Object.keys(newKeys)])].sort()) {
            if (!oldTypes.has(type) || !newTypes.has(type)) {
                incomparableKeys.push({ locator, action_id: next.native_action_id, scope: next.source_scope, type,
                    before_count: (oldKeys[type] || []).length, after_count: (newKeys[type] || []).length,
                    basis: "object_type_absent_in_one_capture_not_confirmed_gameplay_addition",
                    before: scalarGraph(keysFor(previous.action_ref.object_id, oldObjects, oldFull)[type] || []),
                    after: scalarGraph(keysFor(next.action_ref.object_id, newObjects, newFull)[type] || []) });
                continue;
            }
            const difference = multisetDiff(oldKeys[type] || [], newKeys[type] || []);
            if (difference.removed.length || difference.added.length) keys[type] = scalarGraph(difference);
        }
        if (fields.length || Object.keys(keys).length) {
            changes.push({ locator, action_id: next.native_action_id, scope: next.source_scope, fields, keys,
                identity_status: "same_locator_not_identity", auto_approved: false });
            for (const field of fields.filter(field => /^Frame$|^ActionFrame\./.test(field.path))) {
                rawFrameDeltas.push({ action_id: next.native_action_id, scope: next.source_scope, ...field });
            }
        }
    }
    for (const [locator, previous] of oldRecords) if (!newRecords.has(locator)) changes.push({ locator,
        action_id: previous.native_action_id, scope: previous.source_scope, removed_locator: true,
        snapshot: scalarGraph(oldFull(previous.action_ref.object_id)), auto_approved: false });
    // ID-neutral exact graph equality is a review candidate, not identity.
    const oldNeutral = projection(oldObjects, allowed, true), nextNeutral = projection(newObjects, allowed, true);
    const digest = graph => crypto.createHash("sha256").update(JSON.stringify(graph)).digest("hex");
    const signatures = new Map();
    for (const next of after.records || []) {
        const signature = digest(nextNeutral(next.action_ref.object_id));
        const key = `${next.source_scope}:${next.style_index}:${signature}`;
        (signatures.get(key) || signatures.set(key, []).get(key)).push(next.native_action_id);
    }
    const candidates = [];
    for (const change of changes.filter(item => item.fields || item.removed_locator)) {
        const previous = oldRecords.get(change.locator);
        const signature = digest(oldNeutral(previous.action_ref.object_id));
        const matches = signatures.get(`${previous.source_scope}:${previous.style_index}:${signature}`) || [];
        const otherIds = [...new Set(matches)].filter(id => id !== previous.native_action_id);
        if (otherIds.length) candidates.push({ source_scope: previous.source_scope, old_action_id: previous.native_action_id,
            new_action_id_candidates: otherIds, auto_approved: false, basis: "exact_shared_field_graph_ignoring_ActionID_and_branch_Action" });
    }
    return { changes, raw_frame_deltas: rawFrameDeltas, identity_candidates: candidates, incomparable_keys: incomparableKeys };
}
function compareBcm(before, after) {
    const allowed = sharedVocabulary(before, after), oldProject = projection(index(before), allowed), newProject = projection(index(after), allowed);
    const records = source => new Map(source.triggers.map(record => [`${record.native_action_id}:${record.trigger_index}`, record]));
    const old = records(before), next = records(after), changes = [];
    for (const key of [...new Set([...old.keys(), ...next.keys()])].sort()) {
        const previous = old.get(key), current = next.get(key);
        if (!previous || !current) changes.push({ key, action_id: (current || previous).native_action_id,
            status: previous ? "removed_locator" : "added_locator", auto_approved: false,
            snapshot: scalarGraph(projection(index(previous ? before : after), null)((current || previous).trigger_ref.object_id)) });
        else {
            const fields = transport.deltas(scalarGraph(oldProject(previous.trigger_ref.object_id)), scalarGraph(newProject(current.trigger_ref.object_id)));
            if (fields.length) changes.push({ key, action_id: current.native_action_id, fields, auto_approved: false });
        }
    }
    return changes;
}
function comparePermissions(oldAc, oldBcm, newAc, newBcm) {
    const old = groups.buildRelations(oldAc, oldBcm), next = groups.buildRelations(newAc, newBcm);
    const coverage = { before_keyed: old.keyed, after_keyed: next.keyed,
        before_complete: old.complete, after_complete: next.complete,
        before_missing_groups: old.missing_groups, after_missing_groups: next.missing_groups };
    if (!(old.keyed && next.keyed && old.complete && next.complete)) return { coverage, comparable: false, changes: [] };
    const edges = relations => [...relations.enables].flatMap(([source, targets]) => [...targets].flatMap(([target, conditions]) =>
        [...conditions].sort().map(condition => ({ source, target, condition }))));
    return { coverage, comparable: true, ...multisetDiff(edges(old), edges(next)) };
}
function read(file) { return bcm.parseSourceText(fs.readFileSync(file, "utf8")); }
function loadPair(root, version, fighter) {
    const dir = path.join(root, version);
    const matches = archive.scanDumpDirectory(dir).pairs.filter(pair => builder.filenameFighterId(pair.stem) === fighter.id);
    if (matches.length !== 1) throw new Error(`Missing or duplicate raw fighter: ${version}/${fighter.key}`);
    const pair = matches[0];
    const acFile = path.join(dir, pair.ac), bcmFile = path.join(dir, pair.bcm);
    const ac = read(acFile), source = read(bcmFile);
    if (Number(ac.fighter_id) !== fighter.id || Number(source.fighter_id) !== fighter.id || ac.truncated || source.truncated
        || ac.hard_gate_passed === false || source.hard_gate_passed === false) throw new Error(`Invalid raw pair: ${fighter.key}`);
    return { ac, bcm: source, files: { ac: acFile, bcm: bcmFile } };
}
const fieldLabels = {
    "frames.startup.raw": "发生帧", "frames.active.raw": "攻击持续", "frames.recovery.raw": "收招帧",
    "frames.total.raw": "总帧", "frames.on_block.raw": "防御硬直差", "frames.on_hit.raw": "击中硬直差",
    "damage.raw": "伤害", "gauges.drive_gain_on_hit.raw": "击中斗气增加", "gauges.drive_gain_on_parry.raw": "招架斗气增加",
    "gauges.drive_loss_on_block.raw": "防御斗气变化", "gauges.drive_loss_on_punish.raw": "确反康斗气变化",
    "gauges.super_gain.raw": "能量增加", "official_command.modern": "官网现代指令说明",
    "official_command.classic": "官网经典指令说明", "cancel.display": "官网取消说明"
};
const keyLabels = {
    BranchKey: "条件转接", DynamicTriggerKey: "动态转接", TriggerKey: "取消许可",
    MotionKey: "动画片段", LockKey: "联动/锁定参数（未确认实战影响）", SteerKey: "运动参数",
    PushCollisionKey: "推挤框", DamageCollisionKey: "受击判定框", AttackCollisionKey: "攻击判定框",
    SEKey: "音效", PlaceKey: "位置参数", EventKey: "事件", StatusKey: "状态", SwitchKey: "状态开关"
};
function label(webData, id) {
    const action = webData?.actions[id], move = action && webData.moves[action.move_id];
    return move?.name || action?.classic?.display || `内部动作 ${id}`;
}
function markdown(report) {
    const lines = ["# 8.03 → 10.13 逐角色数据变化", "", "## 阅读边界", "",
        "- 以下列的是两份采集数据之间可观察的差异，不等于完整官方平衡补丁说明。",
        "- 动作与输入关系只使用 AC/BCM。帧数表、伤害、斗气和备注单独注明官网来源。",
        "- 8.03 缺少继承帧窗口和准确取消组键：不能把新增采集字段算成新技能或新取消。",
        "- AC/BCM 导出不含完整攻击伤害表；现有旧角色官网伤害字段未发现变化，不能据此保证所有隐藏伤害/判定参数未改。",
        "- 同编号不代表同招式；精确图相似只生成复核候选，绝不批准迁移。",
        "- SF6ACBCM 查询返回 NOT_FOUND：2026-10-13 尚未进入 ready 索引，本报告只能保留原始证据与候选。",
        "- 所有嵌套可比字段已核对；新增字段、窗口不可比、未使用的联动参数和数组片段重排不能直接认定为平衡变化。",
        "- 10.09 → 10.13 仅用于同采集能力下的补充核对，不替代 8.03 基线或证明补丁日期。", ""];
    for (const entry of report.characters) {
        lines.push(`## ${entry.name_zh} (${entry.character})`, "");
        if (entry.new_character) {
            lines.push(`新增角色，8.03 无对应数据。当前出招表 ${entry.current_moves.length} 行、指令动作 ${entry.current_action_count} 项。`, "",
                "| 招式 | 经典指令 | 发生 | 持续 | 收招 | 防御差 | 伤害 |", "|---|---|---|---|---|---|---|");
            for (const move of entry.current_moves) {
                const action = entry.current_web.actions[move.command.action_id];
                const command = action?.classic?.display || move.command.fallback?.classic?.display || "—";
                lines.push(`| ${move.name} | ${command} | ${move.frames.startup.raw ?? "—"} | ${move.frames.active.raw ?? "—"} | ${move.frames.recovery.raw ?? "—"} | ${move.frames.on_block.raw ?? "—"} | ${move.damage.raw ?? "—"} |`);
            }
            lines.push("", "新角色完整取消许可与动作关系见该角色 JSON；不存在旧版变化幅度。", ""); continue;
        }
        const ac = entry.ac.changes.filter(item => item.scope === "character");
        const hasChanges = entry.web.moves.length || entry.web.commands.length || ac.length || entry.bcm.length;
        lines.push(hasChanges ? "以下列出已观察差异；伤害字段没有发现前后变化。" : "在可比字段内未发现角色差异；伤害字段未发现变化。", "");
        if (entry.web.moves.length) {
            lines.push("### 官网资料前后值", "", "| 招式 | 项目 | 8.03 | 10.13 |", "|---|---|---|---|");
            for (const change of entry.web.moves) for (const field of change.fields) {
                if (field.path.endsWith(".value")) continue;
                const escape = value => String(value ?? "未列出").replaceAll("|", "\\|").replaceAll("\n", " / ");
                lines.push(`| ${escape(change.after_name || change.before_name)} | ${fieldLabels[field.path] || field.path} | ${escape(field.before)} | ${escape(field.after)} |`);
            }
            lines.push("");
        }
        if (entry.web.commands.length) {
            lines.push("### 已生成指令显示变化", "");
            for (const change of entry.web.commands) for (const field of change.fields.filter(field => field.path.endsWith(".display"))) {
                lines.push(`- 动作 ${change.action_id}，${field.path}：${field.before} → ${field.after}。这不是独立的跨版本招式身份依据。`);
            }
            lines.push("");
        }
        if (entry.bcm.length) {
            lines.push("### BCM 输入与条件", "");
            for (const change of entry.bcm) {
                lines.push(`- ${label(entry.current_web, change.action_id)}（${change.key}）：${change.status || "原始字段变化"}。`);
                for (const field of change.fields || []) lines.push(`  - ${field.path}：${JSON.stringify(field.before)} → ${JSON.stringify(field.after)}。`);
            }
            lines.push("");
        }
        if (ac.length) {
            lines.push("### AC 连接、运动及其他嵌套参数", "");
            for (const change of ac) {
                lines.push(`#### ${label(entry.current_web, change.action_id)}（${change.action_id}）`, "");
                if (change.added_locator || change.removed_locator) lines.push(`- ${change.added_locator ? "新增" : "移除"}采集定位项；不是直接认定新增/删除招式。`);
                for (const field of change.fields || []) lines.push(`- ${field.path}：${JSON.stringify(field.before)} → ${JSON.stringify(field.after)}。`);
                for (const [type, difference] of Object.entries(change.keys || {})) {
                    const shortType = type.split(".").pop();
                    lines.push(`- ${keyLabels[shortType] || shortType}：旧片段 ${difference.removed.length} 项，新片段 ${difference.added.length} 项（多重集合比较，避免插入后序号错位）。`);
                    if (["BranchKey", "TriggerKey", "DynamicTriggerKey"].includes(shortType)) {
                        for (const side of ["removed", "added"]) for (const item of difference[side]) {
                            const fields = item.fields || {};
                            lines.push(`  - ${side === "removed" ? "旧" : "新"}：${JSON.stringify(fields)}。`);
                        }
                    } else lines.push(`  - 全部前后嵌套参数见 ${entry.character}.json 的 ac.changes；未推断未使用参数的效果。`);
                }
                lines.push("");
            }
        }
        if (entry.ac.identity_candidates.length) {
            lines.push("### 阶段迁移复核候选", "");
            for (const candidate of entry.ac.identity_candidates.filter(item => item.source_scope === "character")) {
                lines.push(`- 旧 ${candidate.old_action_id} → 新 ${candidate.new_action_id_candidates.join(" / ")}：忽略编号后，可比对象图完全相同；仅候选，未批准身份对应。`);
            }
            lines.push("", "因此同编号总帧的改变不自动计为招式总帧调整。", "");
        }
        const incomparable = entry.ac.incomparable_keys.filter(item => item.scope === "character");
        if (incomparable.length) {
            const types = [...new Set(incomparable.map(item => item.type))];
            lines.push("### 单侧采集到的节点类型", "",
                `涉及 ${incomparable.length} 个动作定位项：${types.join("、")}。旧新采集中只有一侧存在该类型，无法区分导出能力变化与真实新增节点；不计入已确认改动。`,
                `完整节点与帧窗口见 ${entry.character}.json 的 ac.incomparable_keys。`, "");
        }
        const permissions = entry.cancel_permissions;
        lines.push(`取消组核对：8.03 → 10.13 ${permissions.primary.comparable ? "可比" : "不可完整比较（旧采集未保留真实字典键）"}。`, "");
        if (permissions.supplemental.comparable) {
            const supplemental = permissions.supplemental;
            lines.push(`10.09 → 10.13 补充许可：移除 ${supplemental.removed.length} 条，新增 ${supplemental.added.length} 条。这是原生许可，不证明攻击命中后必然构成连段。`, "");
            if (supplemental.removed.length || supplemental.added.length) {
                lines.push(`完整来源动作、目标动作和条件见 ${entry.character}.json 的 cancel_permissions.supplemental。`, "");
            }
        }
    }
    lines.push("## 全局采集差异", "", "- 全角色继承帧窗口/动态分支父类字段现在能读到，不是全角色同时新增了取消。",
        "- 共有动作新增定位项单独保存在各角色 JSON 的 ac.changes 中，不当作角色新技能。",
        "- p00_* 等参数别名重复反映同一内存，本报告不重复计数；原始导出仍保留。",
        "- 各角色原始 AC/BCM 来源、官网来源及字段明细均写入配套 JSON。", "");
    return `${lines.join("\n")}\n`;
}
function run(args) {
    const bundle = path.resolve(args["--bundle"]), output = path.resolve(args["--output"]);
    if (fs.existsSync(output)) throw new Error(`Report output exists: ${output}`);
    fs.mkdirSync(output, { recursive: true });
    const acRoot = path.join(__dirname, "acbcm");
    const report = { schema: "sf6cc.observed-build-changes.v1", old_version: "2026-08-03", new_version: "2026-10-13",
        supplemental_version: "2026-10-09", auto_approved: false, characters: [] };
    for (const fighter of rosterCore.loadRoster().fighters) {
        const currentWeb = read(path.join(bundle, "characters/2026-10-13", `${fighter.key}.json`));
        const isNew = !fs.existsSync(path.join(bundle, "characters/2026-08-03", `${fighter.key}.json`));
        const entry = { character: fighter.key, fighter_id: fighter.id, name_zh: fighter.name_zh,
            new_character: isNew, current_web: currentWeb, current_action_count: currentWeb._meta.action_count,
            sources: { official: [path.join(bundle, "official/2026-08-03", `${fighter.key}.json`), path.join(bundle, "official/2026-10-13", `${fighter.key}.json`)] } };
        if (isNew) {
            entry.current_moves = currentWeb.move_order.map(id => currentWeb.moves[id]);
            const next = loadPair(acRoot, "2026-10-13", fighter);
            entry.sources.raw = next.files;
            entry.current_ac = transport.nativeFacts(next.ac, { version: "2026-10-13", fighter_id: fighter.id });
            entry.current_bcm = transport.bcmFacts(next.bcm);
            const permissions = groups.buildRelations(next.ac, next.bcm);
            entry.cancel_permissions = { current_only: true, keyed: permissions.keyed, complete: permissions.complete,
                missing_groups: permissions.missing_groups, edges: [...permissions.enables].flatMap(([source, targets]) =>
                    [...targets].flatMap(([target, conditions]) => [...conditions].map(condition => ({ source, target, condition })))) };
        } else {
            const old = loadPair(acRoot, "2026-08-03", fighter), next = loadPair(acRoot, "2026-10-13", fighter);
            const supplemental = loadPair(acRoot, "2026-10-09", fighter);
            entry.sources.raw = { before: old.files, after: next.files, supplemental: supplemental.files };
            entry.ac = compareAc(old.ac, next.ac);
            entry.bcm = compareBcm(old.bcm, next.bcm);
            entry.web = transport.compareWeb(read(path.join(bundle, "characters/2026-08-03", `${fighter.key}.json`)), currentWeb);
            entry.cancel_permissions = { primary: comparePermissions(old.ac, old.bcm, next.ac, next.bcm),
                supplemental: comparePermissions(supplemental.ac, supplemental.bcm, next.ac, next.bcm) };
        }
        fs.writeFileSync(path.join(output, `${fighter.key}.json`), `${JSON.stringify(entry, null, 2)}\n`);
        report.characters.push(entry);
        console.log(`${fighter.key}: ${isNew ? "new" : `AC ${entry.ac.changes.filter(item => item.scope === "character").length}, BCM ${entry.bcm.length}, OFF ${entry.web.moves.length}`}`);
    }
    fs.writeFileSync(path.join(output, "REPORT.md"), markdown(report));
    console.log(`Complete: ${output}`);
}
if (require.main === module) {
    try { run(builder.argsOf(process.argv.slice(2))); }
    catch (error) { console.error(error.stack); process.exitCode = 1; }
}
module.exports = { sharedVocabulary, projection, multisetDiff, compareAc, compareBcm, comparePermissions, markdown,
    index, keysFor, scalarGraph };
