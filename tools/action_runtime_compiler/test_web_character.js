"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const webCharacter = require("./web_character_core.js");

const iconRoot = path.resolve(__dirname, "../../images/buttonsAndArrows");
for (const [token, filename] of Object.entries(webCharacter.ICON_ASSETS)) {
    assert.strictEqual(fs.existsSync(path.join(iconRoot, filename)), true,
        `missing icon asset for ${token}: ${filename}`);
}

function tokenValues(display, options) {
    return webCharacter.tokenizeCommand(display, options).map(token =>
        token.type === "icon" ? token.value : `text:${token.value}`);
}

assert.deepStrictEqual(tokenValues("236+HP"), ["2", "3", "6", "plus", "hp"]);
assert.deepStrictEqual(tokenValues("j.214+K"), ["text:[空中]", "2", "1", "4", "plus", "k"]);
assert.deepStrictEqual(tokenValues("LP+LK"), ["throw"]);
assert.deepStrictEqual(tokenValues("HP+HK"), ["di"]);
assert.deepStrictEqual(tokenValues("MP+MK (PARRY)"), ["parry"]);
assert.deepStrictEqual(tokenValues("720+P"), ["360", "360", "plus", "p"]);
assert.deepStrictEqual(tokenValues(">MP"), ["followup", "mp"]);
assert.deepStrictEqual(tokenValues("236", { mirror: true }), ["2", "1", "4"]);
assert.deepStrictEqual(tokenValues("SP + 强", { modern: true }), ["modern_sp", "modern_h"]);

const commandSource = {
    "100": {
        classic_command: { display: "236+HP", inputs: ["236+HP"] },
        simple_command: { display: "SP", inputs: ["SP"] },
        motion_command: { display: "236 + 强", inputs: ["236 + 强"] },
        control_support: "classic_modern"
    },
    "101": {
        classic_command: { display: ">6+HP", inputs: [">6+HP"] },
        simple_command: { display: "6 + SP", inputs: ["6 + SP"] },
        motion_command: null,
        relation: { type: "followup", source_action_id: 100 },
        control_support: "classic_modern"
    },
    "102": {
        classic_command: { display: "5LP", inputs: ["5LP"] },
        simple_command: null,
        motion_command: null,
        control_support: "classic_only"
    },
    "200": {
        classic_command: { display: "214214+P", inputs: ["214214+P"] },
        simple_command: { display: "> 中", inputs: ["> 中"] },
        motion_command: null,
        control_support: "classic_modern",
        ownership: "assist_combo"
    },
    _meta: {
        schema: "xt.command_display.v1", character: "Test", fighter_id: 99,
        generated_at: "2026-07-23T00:00:00.000Z"
    }
};

const officialSnapshot = {
    "100": {
        classic_display: "236 + HP", modern_display: "SP/236 + 強",
        move_name: "强测试波", official_web_id: "302"
    },
    "101": {
        classic_display: "6 + HP", modern_display: "6 + SP",
        move_name: "测试派生", official_web_id: "302"
    },
    "200": {
        classic_display: "21424 | 24214 + LP | MP | HP",
        modern_display: "4 + 强 + SP/214214 + 中",
        move_name: "SA2 测试波（Lv1）", official_web_id: "402"
    },
    _meta: {
        schema: "xt.modern_display.v1", character: "Test", fighter_id: 99,
        updated_at: "2026-07-23"
    },
    _official_frame: [
        {
            triggerId: "55", actionId: "100", webId: "302", skill: "强测试波",
            name: "TEST_FB", type: "SPECIAL", command: "236 ＋ HP", command_modern: "SP/236＋強",
            attribute: "上・弾", damage: "※700", combo_correct: ["始动补正20%"],
            drive_gauge_gain_hit: "1000", drive_gauge_gain_parry: "5000",
            drive_gauge_lose_dguard: "-2500", drive_gauge_lose_punish: "-3000",
            sa_gauge_gain: "600", cancel: "CRITICAL_Lv3", web_cancel: "SA3",
            startup_frame: "12", active_frame: "4-6", recovery_frame: "35", frame: "47",
            block_frame: "-9", hit_frame: "-2", note: ["测试备注"], translation: "Test note"
        },
        {
            triggerId: "56", actionId: "999", webId: "302", skill: "测试派生",
            name: "TEST_FOLLOW", type: "UNIQUE", command: "6 ＋ HP", command_modern: "6＋SP",
            damage: "800", startup_frame: "8", active_frame: "8-10", recovery_frame: "20"
        },
        {
            triggerId: "70", actionId: "700", webId: "400", skill: "未绑定招式",
            name: "UNBOUND", type: "SPECIAL", command: "214 ＋ LK",
            command_modern: "4＋SP/214＋弱/6＋SP/236＋强",
            damage: "900", startup_frame: "10", active_frame: null, recovery_frame: null
        },
        {
            triggerId: "80", actionId: "200", webId: "402", skill: "SA2 测试波（Lv1）",
            name: "(SA2_TEST)", type: "SA", command: "21424 | 24214 ＋ LP | MP | HP",
            command_modern: "4＋强＋SP/214214＋中", note: ["ボタンをホールドする事で性能変化"],
            translation: "Hold down the button to change the properties of this move."
        },
        {
            triggerId: "81", actionId: "200", webId: "403", skill: "SA2 测试波（Lv2）",
            name: "(SA2_TEST)", type: "SA", command: "21425 | 24214 ＋ LP | MP | HP",
            command_modern: "4＋强＋SP/214214＋中", note: ["ボタンをホールドする事で性能変化"],
            translation: "Hold down the button to change the properties of this move."
        },
        {
            triggerId: "82", actionId: "200", webId: "404", skill: "SA2 测试波（Lv3）",
            name: "(SA2_TEST)", type: "SA", command: "21426 | 24214 ＋ LP | MP | HP",
            command_modern: "4＋强＋SP/214214＋中", note: ["ボタンをホールドする事で性能変化"],
            translation: "Hold down the button to change the properties of this move."
        }
    ]
};

const output = webCharacter.buildWebCharacter(commandSource, {
    commandSourceSha256: "command-hash",
    officialSnapshot,
    officialSha256: "official-hash"
});
assert.deepStrictEqual(webCharacter.validateWebCharacter(output, commandSource),
    { action_count: 4, move_count: 6 });
assert.strictEqual(output._meta.schema, "xt.character.web.v1");
assert.strictEqual(output._meta.command_source_sha256, "command-hash");
assert.strictEqual(output._meta.frame_source_sha256, "official-hash");
assert.strictEqual(output.actions["101"].modern.simple.display, "SP > 6 + SP");
assert.strictEqual(output.actions["100"].move_id, "web:302:1");
assert.strictEqual(output.actions["101"].move_id, "web:302:2");
assert.strictEqual(output.actions["102"].move_id, null);
assert.deepStrictEqual(output.moves["web:302:1"].action_ids, [100]);
assert.strictEqual(output.moves["web:302:1"].command.source, "action");
assert.strictEqual(output.moves["web:302:1"].frames.startup.value, 12);
assert.strictEqual(output.moves["web:302:1"].frames.active.raw, "4-6");
assert.strictEqual(output.moves["web:302:1"].frames.active.value, null);
assert.strictEqual(output.moves["web:302:1"].damage.raw, "※700");
assert.strictEqual(output.moves["web:302:1"].damage.value, null);
assert.strictEqual(output.moves["web:400:1"].command.source, "official_fallback");
assert.strictEqual(output.moves["web:400:1"].command.fallback.modern.simple.display, "4 + SP/6 + SP");
assert.strictEqual(output.moves["web:400:1"].command.fallback.modern.motion.display, "214 + 弱/236 + 强");
assert.deepStrictEqual(output.moves["web:400:1"].command.fallback.modern.variants.map(item => item.display),
    ["4 + SP", "214 + 弱", "6 + SP", "236 + 强"]);
assert.strictEqual(output.actions["200"].modern.simple.display, "> 中");
for (const moveId of ["web:402:1", "web:403:1", "web:404:1"]) {
    const move = output.moves[moveId];
    assert.strictEqual(move.command.source, "official_fallback");
    assert.strictEqual(move.command.fallback.classic.display, "214214+P");
    assert.strictEqual(move.command.fallback.modern.simple.display, "4 + 强 + SP");
    assert.strictEqual(move.command.fallback.modern.motion.display, "214214 + 中");
    assert.strictEqual(move.official_command.classic, "214214+P");
}
assert.deepStrictEqual(output.moves["web:402:1"].action_ids, [200]);
assert.strictEqual(output._audit.duplicate_official_web_id_count, 1);
assert.strictEqual(output._audit.unresolved_move_binding_count, 0);
assert.deepStrictEqual(webCharacter.buildWebCharacter(commandSource, {
    commandSourceSha256: "command-hash", officialSnapshot, officialSha256: "official-hash"
}), output);

const formalRoot = path.resolve(__dirname, "../../data/TrainingComboTrials_data/command_display");
for (const name of fs.readdirSync(formalRoot).filter(name => name.endsWith(".json"))) {
    const commandTable = JSON.parse(fs.readFileSync(path.join(formalRoot, name), "utf8"));
    const webTable = webCharacter.buildWebCharacter(commandTable);
    const validated = webCharacter.validateWebCharacter(webTable, commandTable);
    assert.strictEqual(validated.action_count,
        Object.keys(commandTable).filter(key => /^\d+$/.test(key)).length);
    assert.strictEqual(validated.move_count, 0);
}

console.log("web character tests passed");
