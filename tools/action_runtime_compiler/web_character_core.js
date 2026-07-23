"use strict";

const commandSemantics = require("./official_semantics_core.js");

const SCHEMA = "xt.character.web.v1";
const TOKEN_SCHEMA = "xt.command_tokens.v1";
const ICON_SET = "sf6cc.buttons_and_arrows.v1";

// Keep the exact checked-in filename casing. Website builds normally run on a
// case-sensitive filesystem even though the game runtime is Windows-only.
const ICON_ASSETS = Object.freeze({
    "1": "1.png", "2": "2.png", "3": "3.png", "4": "4.png", "5": "5.png",
    "6": "6.png", "7": "7.png", "8": "8.png", "9": "9.png",
    lp: "lp.png", mp: "mp.png", hp: "hp.png", lk: "lk.png", mk: "mk.png", hk: "hk.png",
    modern_l: "modern_l.png", modern_m: "modern_m.png", modern_h: "modern_h.png",
    modern_n: "modern_n.png", modern_sp: "modern_sp.png", modern_auto: "modern_auto.png",
    p: "P.png", k: "K.png", "360": "360.png",
    "4_hold": "4_HOLD.png", "2_hold": "2_HOLD.png", "6_hold": "6_HOLD.png",
    hcb: "HCB.png", hcf: "HCF.png", throw: "THROW.png",
    followup: "followup.png", validfollowup: "validfollowup.png",
    hold: "hold.png", plus: "PLUS.png", parry: "parry.png",
    dr: "dr.png", drc: "drc.png", rev: "rev.png", di: "di.png"
});

const BUTTON_TOKENS = new Set([
    "p", "k", "lp", "mp", "hp", "lk", "mk", "hk", "throw",
    "modern_l", "modern_m", "modern_h", "modern_n", "modern_sp", "modern_auto"
]);

function numericEntries(value) {
    return Object.fromEntries(Object.entries(value || {})
        .filter(([key]) => /^\d+$/.test(key))
        .sort(([left], [right]) => Number(left) - Number(right)));
}

function trim(value) {
    return String(value == null ? "" : value).trim();
}

function commandDisplay(command) {
    if (!command || typeof command !== "object" || !Array.isArray(command.inputs)
        || command.inputs.length === 0) return null;
    return trim(command.display) || null;
}

function localizeMotionText(value) {
    return String(value || "")
        .replace(/FULLY\s+DELAYED/g, "完全延迟").replace(/CANCEL\s+ACTION/g, "取消动作")
        .replace(/DO\s+NOTHING/g, "不操作").replace(/RUN\s+STOP/g, "急停")
        .replace(/1ST\s+HALF/g, "前半段").replace(/2ND\s+HALF/g, "后半段")
        .replace(/FLASH\s+KICK/g, "脚刀").replace(/SHUN\s+GOKU\s+SATSU/g, "瞬狱杀")
        .replace(/ENHANCED/g, "强化").replace(/PERFECT/g, "完美").replace(/INSTANT/g, "即时")
        .replace(/DELAYED/g, "延迟").replace(/FEINT/g, "假动作").replace(/CANCEL/g, "取消")
        .replace(/SLIDE/g, "滑步").replace(/UNKNOWN/g, "未知")
        .replace(/LVL\s*(\d+)/g, "等级 $1").replace(/LEVEL\s*(\d+)/g, "等级 $1")
        .replace(/(\d+)\s+MEDALS?/g, "$1 枚奖牌");
}

function replaceAsciiWord(value, word, replacement) {
    const expression = new RegExp(`(^|[^A-Z])${word}(?=$|[^A-Z])`, "g");
    return value.replace(expression, (_, prefix) => `${prefix}${replacement}`);
}

function replaceModernWord(value, word, token) {
    const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const expression = new RegExp(`(^|[\\s+{}/|])${escaped}(?=$|[\\s+{}/|])`, "g");
    return value.replace(expression, (_, prefix) => `${prefix}{${token}}`);
}

function protectMatches(value, expression, store, baseCodePoint) {
    return value.replace(expression, match => {
        const index = store.push(match) - 1;
        return String.fromCodePoint(baseCodePoint + index);
    });
}

function restoreMatches(value, store, baseCodePoint) {
    let output = value;
    for (let index = 0; index < store.length; index += 1) {
        output = output.split(String.fromCodePoint(baseCodePoint + index)).join(store[index]);
    }
    return output;
}

function mirrorNotation(value) {
    let output = String(value || "");
    const unresolved = [], parentheses = [], protectedMotions = [];
    output = protectMatches(output, /\[现代指令未识别\]|\[ID\s+\d+\s+未识别\]/g, unresolved, 0xE000);
    output = protectMatches(output, /\([^()]*\)/g, parentheses, 0xE100);
    output = protectMatches(output, /720|360|5252/g, protectedMotions, 0xE200);
    const swaps = { "1": "3", "3": "1", "4": "6", "6": "4", "7": "9", "9": "7" };
    output = output.replace(/\d/g, digit => swaps[digit] || digit);
    output = restoreMatches(output, protectedMotions, 0xE200);
    output = restoreMatches(output, parentheses, 0xE100);
    return restoreMatches(output, unresolved, 0xE000);
}

function tokenizeCommand(display, options = {}) {
    let value = String(display == null ? "" : display).toUpperCase().replace(/＋/g, "+");
    const actionId = Number(options.actionId);
    if (actionId === 1231 && (/SHUN\s+GOKU\s+SATSU/.test(value) || value.includes("瞬狱杀"))) {
        value = "LP,LP,6,LK,HP (瞬狱杀)";
    }
    value = value.replace(/J\./g, "[空中]").replace(/\[空中\]\s*/g, "[空中] ");
    if (options.mirror === true) value = mirrorNotation(value);

    const textBlocks = [];
    value = protectMatches(value, /\[现代指令未识别\]|\[ID\s+\d+\s+未识别\]/g, textBlocks, 0xE300);
    value = value.replace(/\(THROW\)/g, "{throw}").replace(/THROW/g, "{throw}")
        .replace(/LP\+LK/g, "{throw}").replace(/FORWARD DASH/g, "{6}{6}")
        .replace(/BACK DASH/g, "{4}{4}").replace(/5252/g, "{2}{2}")
        .replace(/720/g, "{double_circle}").replace(/MP\+MK \(PARRY\)/g, "{parry}")
        .replace(/\(PARRY_JUST_[LMH]\)|PARRY_JUST_[LMH]/g, "{parry}")
        .replace(/\(PARRY_HIT_[LMH]\)|PARRY_HIT_[LMH]/g, "{parry}")
        .replace(/\(PARRY\)|PARRY/g, "{parry}").replace(/\(DP\)/g, "{parry}");
    value = replaceAsciiWord(value, "DP", "{parry}");
    value = value.replace(/HP\+HK/g, "{di}").replace(/DI/g, "{di}")
        .replace(/\(REVERSAL\)|REVERSAL/g, "{rev}")
        .replace(/\(WHIFF\)/g, "(空挥)").replace(/WHIFF/g, "空挥")
        .replace(/DRIVE RUSH CANCEL/g, "{drc}").replace(/\(DRC\)|DRC/g, "{drc}")
        .replace(/RAW DR/g, "{dr}").replace(/DRIVE RUSH/g, "{dr}").replace(/\(DR\)/g, "{dr}")
        .replace(/,/g, "{seq}").replace(/\(>\)/g, "{followup}")
        .replace(/\(> (.*?)\)/g, "{followup} $1").replace(/>/g, "{followup}")
        .replace(/\(HOLD\)/g, "{hold}").replace(/\(HOLD (.*?)\)/g, "{hold} ($1)")
        .replace(/HOLD/g, "{hold}").replace(/FOLLOW-UP/g, "{followup}");
    value = localizeMotionText(value);
    if (options.modern === true) value = value.replace(/\+/g, "{plus}");
    value = value.replace(/63214/g, "{6}{3}{2}{1}{4}").replace(/41236/g, "{4}{1}{2}{3}{6}")
        .replace(/\[4\]/g, "{4_hold}").replace(/\[2\]/g, "{2_hold}").replace(/\[6\]/g, "{6_hold}")
        .replace(/360/g, "{360}").replace(/\{double_circle\}/g, "{360}{360}");

    value = value.replace(/\([^()]*\)/g, match => {
        textBlocks.push(match);
        return `{txt_${textBlocks.length - 1}}`;
    });
    value = restoreMatches(value, textBlocks, 0xE300)
        .replace(/\[现代指令未识别\]|\[ID\s+\d+\s+未识别\]/g, match => {
            textBlocks.push(match);
            return `{txt_${textBlocks.length - 1}}`;
        });

    for (const [word, replacement] of [
        ["PPP", "{p}{p}{p}"], ["PP", "{p}{p}"], ["KKK", "{k}{k}{k}"], ["KK", "{k}{k}"],
        ["LP", "{lp}"], ["MP", "{mp}"], ["HP", "{hp}"], ["LK", "{lk}"],
        ["MK", "{mk}"], ["HK", "{hk}"], ["P", "{p}"], ["K", "{k}"],
        ["MODERN_L", "{modern_l}"], ["MODERN_M", "{modern_m}"], ["MODERN_H", "{modern_h}"],
        ["MODERN_SP", "{modern_sp}"], ["MODERN_AUTO", "{modern_auto}"],
        ["AUTO", "{modern_auto}"], ["SP", "{modern_sp}"]
    ]) value = replaceAsciiWord(value, word, replacement);
    value = replaceModernWord(value, "弱", "modern_l");
    value = replaceModernWord(value, "中", "modern_m");
    value = replaceModernWord(value, "強", "modern_h");
    value = replaceModernWord(value, "强", "modern_h");
    value = replaceModernWord(value, "任意键", "modern_n");
    value = value.replace(/攻撃二つ|攻击二つ/g, "{modern_l}{modern_m}")
        .replace(/攻撃|攻击/g, "{modern_h}");

    const parsed = [];
    let currentText = "";
    const flushText = () => {
        const text = currentText.trim();
        if (text) parsed.push({ type: "text", value: text });
        currentText = "";
    };
    for (let index = 0; index < value.length;) {
        const character = value[index];
        if (character === "{") {
            const end = value.indexOf("}", index);
            if (end < 0) { index += 1; continue; }
            flushText();
            const token = value.slice(index + 1, end);
            if (token.startsWith("txt_")) {
                const text = textBlocks[Number(token.slice(4))];
                if (text) parsed.push({ type: "text", value: text });
            } else parsed.push({ type: "icon", value: token.toLowerCase() });
            index = end + 1;
        } else if (/\d/.test(character)) {
            flushText();
            if (character !== "0") parsed.push({ type: "icon", value: character });
            index += 1;
        } else if (character === "+") {
            flushText();
            index += 1;
        } else {
            currentText += character;
            index += 1;
        }
    }
    flushText();

    const tokens = [];
    let suppressPlus = false;
    for (let index = 0; index < parsed.length; index += 1) {
        const token = parsed[index];
        if (token.type === "icon" && token.value === "seq") { suppressPlus = true; continue; }
        const previous = tokens[tokens.length - 1], next = parsed[index + 1];
        const skipButtonSeparator = token.type === "icon" && token.value === "plus"
            && previous && previous.type === "icon" && BUTTON_TOKENS.has(previous.value)
            && next && next.type === "icon" && BUTTON_TOKENS.has(next.value);
        if (skipButtonSeparator) { suppressPlus = false; continue; }
        if (!suppressPlus && tokens.length > 0 && token.type === "icon" && BUTTON_TOKENS.has(token.value)
            && previous.type === "icon" && !BUTTON_TOKENS.has(previous.value)
            && !["plus", "followup", "validfollowup"].includes(previous.value)) {
            tokens.push({ type: "icon", value: "plus" });
        }
        tokens.push(token);
        suppressPlus = false;
    }
    for (const token of tokens) if (token.type === "icon"
        && !Object.prototype.hasOwnProperty.call(ICON_ASSETS, token.value)) {
        throw new Error(`网页指令包含未声明图标 token: ${token.value} (${display})`);
    }
    return tokens;
}

function resolveModernDisplay(entries, actionId, slot, stack = new Set()) {
    const key = String(actionId == null ? "" : actionId);
    const entry = entries[key];
    if (!entry || typeof entry !== "object" || entry.suppress_display === true) return null;
    const primary = slot === "motion" ? entry.motion_command : entry.simple_command;
    const fallback = slot === "motion" ? entry.simple_command : entry.motion_command;
    let local = commandDisplay(primary) || commandDisplay(fallback);
    if (!local) return null;
    const relation = entry.relation;
    if (!relation || relation.type !== "followup") return local;
    if (stack.has(key)) return null;
    local = local.replace(/^>\s*/, "");
    stack.add(key);
    const parent = resolveModernDisplay(entries, relation.source_action_id, slot, stack);
    stack.delete(key);
    return parent ? `${parent} > ${local}` : null;
}

function renderedCommand(display, options) {
    if (!display) return null;
    return {
        display,
        tokens: tokenizeCommand(display, options),
        mirrored_tokens: tokenizeCommand(display, { ...options, mirror: true })
    };
}

function normalizeOfficialDisplay(value) {
    return commandSemantics.normalizeCommand(value);
}

function normalizeOfficialModernDisplay(value) {
    const display = normalizeOfficialDisplay(value);
    return display && normalizeOfficialDisplay(display.replace(/\bL\b/g, "弱")
        .replace(/\bM\b/g, "中").replace(/\bH\b/g, "强"));
}

function buildCommandSet(classic, modern, actionId = null) {
    const segments = modern ? String(modern).split(/\s*\/\s*/).map(trim) : [];
    const routes = segments.filter(Boolean);
    let simple = routes[0] || null;
    let motion = routes.length > 1 ? routes[routes.length - 1] : simple;
    if (segments.length >= 4 && segments.length % 2 === 0 && segments.every(Boolean)) {
        simple = segments.filter((_, index) => index % 2 === 0).join("/");
        motion = segments.filter((_, index) => index % 2 === 1).join("/");
    }
    const all = modern || (simple && motion && simple !== motion ? `${simple}/${motion}` : (simple || motion));
    return {
        classic: renderedCommand(classic, { actionId, modern: false }),
        modern: {
            suppressed: false,
            simple: renderedCommand(simple, { actionId, modern: true }),
            motion: renderedCommand(motion, { actionId, modern: true }),
            all: renderedCommand(all, { actionId, modern: true }),
            variants: routes.map(route => renderedCommand(route, { actionId, modern: true }))
        }
    };
}

function scalarStat(value) {
    if (value === undefined || value === null || String(value).trim() === "") return { raw: null, value: null };
    const raw = String(value).trim();
    return { raw, value: /^[+-]?\d+(?:\.\d+)?$/.test(raw) ? Number(raw) : null };
}

function textArray(value) {
    if (Array.isArray(value)) return value.map(trim).filter(Boolean);
    const text = trim(value);
    return text ? [text] : [];
}

function officialId(value) {
    const result = trim(value);
    return /^\d+$/.test(result) ? result : null;
}

function buildMoves(snapshot) {
    const rows = snapshot && Array.isArray(snapshot._official_frame) ? snapshot._official_frame : [];
    const occurrences = new Map(), moves = {}, moveOrder = [], byWebId = new Map();
    for (let index = 0; index < rows.length; index += 1) {
        const row = rows[index] || {};
        const webId = officialId(row.webId), actionHint = officialId(row.actionId);
        // Capcom's frame module also contains internal helper/shortcut rows
        // without a public webId. They are useful to command compilation but
        // are not moves shown on the public character frame-data page.
        if (!webId) continue;
        const base = `web:${webId}`;
        const occurrence = (occurrences.get(base) || 0) + 1;
        occurrences.set(base, occurrence);
        const moveId = `${base}:${occurrence}`;
        const classic = normalizeOfficialDisplay(row.command);
        const modern = normalizeOfficialModernDisplay(row.command_modern);
        moves[moveId] = {
            official_web_id: webId,
            official_action_id_hint: actionHint,
            name: trim(row.skill) || null,
            internal_name: trim(row.name) || null,
            category: trim(row.type) || null,
            attribute: trim(row.attribute) || null,
            official_command: { classic, modern },
            command: {
                source: "official_fallback",
                action_id: null,
                fallback: buildCommandSet(classic, modern)
            },
            action_ids: [],
            frames: {
                startup: scalarStat(row.startup_frame),
                active: scalarStat(row.active_frame),
                recovery: scalarStat(row.recovery_frame),
                total: scalarStat(row.frame),
                on_block: scalarStat(row.block_frame),
                on_hit: scalarStat(row.hit_frame)
            },
            damage: scalarStat(row.damage),
            gauges: {
                drive_gain_on_hit: scalarStat(row.drive_gauge_gain_hit),
                drive_gain_on_parry: scalarStat(row.drive_gauge_gain_parry),
                drive_loss_on_block: scalarStat(row.drive_gauge_lose_dguard),
                drive_loss_on_punish: scalarStat(row.drive_gauge_lose_punish),
                super_gain: scalarStat(row.sa_gauge_gain)
            },
            cancel: { raw: trim(row.cancel) || null, display: trim(row.web_cancel) || null },
            combo_scaling: textArray(row.combo_correct),
            notes: textArray(row.note),
            translation: trim(row.translation) || null,
            source_row_index: index
        };
        moveOrder.push(moveId);
        if (!byWebId.has(webId)) byWebId.set(webId, []);
        byWebId.get(webId).push(moveId);
    }
    return { moves, moveOrder, byWebId };
}

function chooseMoveCandidate(candidateIds, moves, binding, actionId) {
    if (!candidateIds || candidateIds.length === 0) return null;
    if (candidateIds.length === 1) return candidateIds[0];
    const filters = [
        move => move.official_action_id_hint === String(actionId),
        move => move.name && trim(binding.move_name) === move.name,
        move => normalizeOfficialDisplay(move.official_command.classic)
            === normalizeOfficialDisplay(binding.classic_display)
    ];
    let candidates = candidateIds.map(id => ({ id, ...moves[id] }));
    for (const predicate of filters) {
        const matched = candidates.filter(predicate);
        if (matched.length === 1) return matched[0].id;
        if (matched.length > 1) candidates = matched;
    }
    return null;
}

function buildWebCharacter(commandSource, options = {}) {
    const sourceMeta = commandSource && commandSource._meta || {};
    if (sourceMeta.schema !== "xt.command_display.v1") {
        throw new Error(`网页角色生成器不支持指令源 schema: ${sourceMeta.schema || "missing"}`);
    }
    const officialSnapshot = options.officialSnapshot || null;
    const officialMeta = officialSnapshot && officialSnapshot._meta || null;
    if (officialMeta && (officialMeta.character !== sourceMeta.character
        || Number(officialMeta.fighter_id) !== Number(sourceMeta.fighter_id))) {
        throw new Error("网页角色生成器的指令表与 OFF 角色身份不一致。");
    }

    const entries = numericEntries(commandSource), actions = {};
    for (const [id, entry] of Object.entries(entries)) {
        const simple = resolveModernDisplay(entries, id, "simple");
        const motion = resolveModernDisplay(entries, id, "motion");
        const all = simple && motion && simple !== motion ? `${simple}/${motion}` : (simple || motion);
        actions[id] = {
            move_id: null,
            control_support: entry.control_support,
            relation: entry.relation && entry.relation.type === "followup" ? {
                type: "followup", source_action_id: Number(entry.relation.source_action_id)
            } : null,
            classic: renderedCommand(commandDisplay(entry.classic_command), {
                actionId: Number(id), modern: false
            }),
            modern: {
                suppressed: entry.suppress_display === true,
                simple: renderedCommand(simple, { actionId: Number(id), modern: true }),
                motion: renderedCommand(motion, { actionId: Number(id), modern: true }),
                all: renderedCommand(all, { actionId: Number(id), modern: true })
            }
        };
    }

    const { moves, moveOrder, byWebId } = buildMoves(officialSnapshot);
    const unresolvedBindings = [];
    for (const [actionId, binding] of Object.entries(numericEntries(officialSnapshot))) {
        if (!actions[actionId]) continue;
        const webId = officialId(binding.official_web_id);
        if (!webId) continue;
        const moveId = chooseMoveCandidate(byWebId.get(webId), moves, binding, actionId);
        if (!moveId) {
            unresolvedBindings.push({ action_id: Number(actionId), official_web_id: webId });
            continue;
        }
        if (actions[actionId].move_id && actions[actionId].move_id !== moveId) {
            unresolvedBindings.push({ action_id: Number(actionId), official_web_id: webId,
                reason: "multiple_move_bindings" });
            continue;
        }
        actions[actionId].move_id = moveId;
        if (!moves[moveId].action_ids.includes(Number(actionId))) moves[moveId].action_ids.push(Number(actionId));
    }
    for (const move of Object.values(moves)) {
        move.action_ids.sort((left, right) => left - right);
        if (move.action_ids.length > 0) {
            const actionId = move.action_ids[0];
            move.command = { source: "action", action_id: actionId, fallback: null };
        }
    }

    const duplicateOfficialWebIds = [...byWebId.entries()].filter(([, ids]) => ids.length > 1)
        .map(([officialWebId, moveIds]) => ({ official_web_id: officialWebId, move_ids: moveIds }));
    const linkedActions = Object.values(actions).filter(action => action.move_id !== null).length;
    const linkedMoves = Object.values(moves).filter(move => move.action_ids.length > 0).length;
    return {
        _meta: {
            schema: SCHEMA,
            token_schema: TOKEN_SCHEMA,
            icon_set: ICON_SET,
            character: sourceMeta.character,
            fighter_id: sourceMeta.fighter_id,
            generated_at: sourceMeta.generated_at || options.generatedAt || null,
            command_source_schema: sourceMeta.schema,
            command_source_sha256: options.commandSourceSha256 || null,
            frame_source_schema: officialMeta && officialMeta.schema || null,
            frame_source_sha256: options.officialSha256 || null,
            frame_source_updated_at: officialMeta && officialMeta.updated_at || null,
            action_count: Object.keys(actions).length,
            move_count: Object.keys(moves).length,
            linked_action_count: linkedActions,
            linked_move_count: linkedMoves,
            fallback_policy: {
                classic_action_missing: "use_combo_step_motion",
                modern_action_missing: "show_unresolved",
                move_action_missing: "use_official_fallback"
            }
        },
        _icons: { ...ICON_ASSETS },
        actions,
        moves,
        move_order: moveOrder,
        _audit: {
            unresolved_move_binding_count: unresolvedBindings.length,
            unresolved_move_bindings: unresolvedBindings,
            duplicate_official_web_id_count: duplicateOfficialWebIds.length,
            duplicate_official_web_ids: duplicateOfficialWebIds,
            actions_without_move_count: Object.keys(actions).length - linkedActions,
            moves_without_action_count: Object.keys(moves).length - linkedMoves
        }
    };
}

function validateRenderedCommand(command, context) {
    if (command === null) return;
    if (!command || typeof command.display !== "string" || !Array.isArray(command.tokens)
        || !Array.isArray(command.mirrored_tokens)) throw new Error(`${context} token 结构无效。`);
    for (const token of command.tokens.concat(command.mirrored_tokens)) {
        if (!token || !["icon", "text"].includes(token.type) || typeof token.value !== "string") {
            throw new Error(`${context} 包含无效 token。`);
        }
        if (token.type === "icon" && !Object.prototype.hasOwnProperty.call(ICON_ASSETS, token.value)) {
            throw new Error(`${context} 引用了未声明图标 ${token.value}。`);
        }
    }
}

function validateWebCharacter(output, commandSource) {
    const meta = output && output._meta || {};
    if (meta.schema !== SCHEMA || meta.token_schema !== TOKEN_SCHEMA || meta.icon_set !== ICON_SET) {
        throw new Error("网页角色输出 schema 或图标集不匹配。");
    }
    if (meta.character !== commandSource._meta.character
        || Number(meta.fighter_id) !== Number(commandSource._meta.fighter_id)) {
        throw new Error("网页角色输出身份与指令源不一致。");
    }
    const sourceIds = Object.keys(numericEntries(commandSource));
    if (!output.actions || Object.keys(output.actions).length !== sourceIds.length
        || Number(meta.action_count) !== sourceIds.length) throw new Error("网页角色 Action 数不一致。");
    for (const id of sourceIds) {
        const action = output.actions[id];
        if (!action || !action.modern || !Object.prototype.hasOwnProperty.call(action, "classic")) {
            throw new Error(`网页角色 Action ${id} 结构不完整。`);
        }
        for (const command of [action.classic, action.modern.simple, action.modern.motion, action.modern.all]) {
            validateRenderedCommand(command, `Action ${id}`);
        }
        if (action.move_id !== null && !output.moves[action.move_id]) {
            throw new Error(`网页角色 Action ${id} 引用了不存在的 move_id。`);
        }
    }
    const moveIds = Object.keys(output.moves || {});
    if (Number(meta.move_count) !== moveIds.length || !Array.isArray(output.move_order)
        || output.move_order.length !== moveIds.length || new Set(output.move_order).size !== moveIds.length
        || output.move_order.some(id => !output.moves[id])) throw new Error("网页角色 Move 清单不一致。");
    for (const id of moveIds) {
        const move = output.moves[id];
        if (!move || !Array.isArray(move.action_ids) || !move.frames || !move.damage || !move.command) {
            throw new Error(`网页角色 Move ${id} 结构不完整。`);
        }
        for (const actionId of move.action_ids) {
            if (!output.actions[String(actionId)] || output.actions[String(actionId)].move_id !== id) {
                throw new Error(`网页角色 Move ${id} 的 Action 反向引用无效。`);
            }
        }
        if (move.command.source === "action") {
            if (!output.actions[String(move.command.action_id)] || move.action_ids[0] !== move.command.action_id
                || move.command.fallback !== null) throw new Error(`网页角色 Move ${id} 指令引用无效。`);
        } else if (move.command.source === "official_fallback") {
            if (move.command.action_id !== null || !move.command.fallback) {
                throw new Error(`网页角色 Move ${id} 官网后备指令无效。`);
            }
            const fallback = move.command.fallback;
            for (const command of [fallback.classic, fallback.modern.simple,
                fallback.modern.motion, fallback.modern.all]) validateRenderedCommand(command, `Move ${id}`);
            if (!Array.isArray(fallback.modern.variants)) {
                throw new Error(`网页角色 Move ${id} 官网后备指令缺少 variants。`);
            }
            for (const command of fallback.modern.variants) validateRenderedCommand(command, `Move ${id}`);
        } else throw new Error(`网页角色 Move ${id} 指令来源无效。`);
    }
    return { action_count: sourceIds.length, move_count: moveIds.length };
}

module.exports = {
    SCHEMA, TOKEN_SCHEMA, ICON_SET, ICON_ASSETS,
    tokenizeCommand, mirrorNotation, resolveModernDisplay,
    buildWebCharacter, validateWebCharacter, scalarStat
};
