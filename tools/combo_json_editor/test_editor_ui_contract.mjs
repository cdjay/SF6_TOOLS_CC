import assert from "node:assert/strict";
import fs from "node:fs";

const html = fs.readFileSync(new URL("./index.html", import.meta.url), "utf8");
const app = fs.readFileSync(new URL("./app.mjs", import.meta.url), "utf8");
const styles = fs.readFileSync(new URL("./styles.css", import.meta.url), "utf8");

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML ids must be unique");

const staticAppReferences = [...app.matchAll(/\$\("([A-Za-z0-9_-]+)"\)/g)].map(match => match[1]);
for (const id of new Set(staticAppReferences)) {
    assert.ok(ids.includes(id), `missing HTML element #${id}`);
}

const selectIds = [
    "statusFilter",
    "rating",
    "dummyControl",
    "dummyAction",
    "dummyCounterType",
    "dummyGuardType",
    "dummyGuardCount",
    "dummyGuardSwitchMode",
    "dummyGuardKind",
    "dummyDriveReversalType",
    "dummyDriveReversalDelay",
    "dummyDriveReversalCount",
    "dummyThrowEscapeType",
    "dummyWakeupType",
    "p1FighterId",
    "p2FighterId",
    "p1Burnout",
    "p2Burnout"
];
for (const id of selectIds) {
    assert.match(html, new RegExp(`<select id="${id}"`), `${id} must be a single-choice select`);
}
const numericWeightIds = [
    "dummyCounterWeightNormal",
    "dummyCounterWeightCounter",
    "dummyCounterWeightPunish",
    "dummyDriveReversalWeightNone",
    "dummyDriveReversalWeightGuard",
    "dummyDriveReversalWeightWakeup"
];
for (const id of numericWeightIds) {
    assert.match(
        html,
        new RegExp(`<input id="${id}" type="number"`),
        `${id} must support direct numeric entry`
    );
    assert.doesNotMatch(html, new RegExp(`<select id="${id}"`), `${id} must not be a dropdown`);
}
// fighter_id 必须是原生下拉框，不得再增强为选项块
for (const id of ["p1FighterId", "p2FighterId"]) {
    assert.doesNotMatch(app, new RegExp(`\\["${id}",`), `${id} must stay a native select`);
}
// 原始字段由陪练菜单镜像自动派生，不再提供重复的裸字段控件
for (const id of ["dummyStance", "dummyActionType", "dummyJumpType", "requiresDummyCrouch"]) {
    assert.doesNotMatch(html, new RegExp(`id="${id}"`), `${id} must be derived, not a standalone control`);
}
assert.doesNotMatch(html, /id="dummyGuard"/, "legacy dummy_guard alias must not be editable");
// 眩晕 / 姿态仅记录、改了也无效，已从表单隐藏
for (const id of ["p1Stunned", "p2Stunned", "p1Stance", "p2Stance"]) {
    assert.doesNotMatch(html, new RegExp(`id="${id}"`), `${id} must be hidden from the form`);
}
for (const id of ["statusFilter", "rating", "p1Burnout", "p2Burnout"]) {
    assert.match(app, new RegExp(`\\["${id}",\\s*"`), `${id} must be enhanced into choice boxes`);
}
// 枚举保留原生下拉框并提供左右箭头，随机权重改为可直接输入的数值步进器。
for (const id of selectIds.filter(id => id.startsWith("dummy"))) {
    assert.match(app, new RegExp(`"${id}"`), `${id} must be wired`);
}
for (const id of numericWeightIds) {
    assert.match(app, new RegExp(`"${id}"`), `${id} must be wired`);
}
assert.match(app, /enhanceStepperSelect/);
assert.match(app, /enhanceNumericStepper/);
assert.match(app, /numeric-stepper/);
assert.match(styles, /\.numeric-stepper input/);
assert.match(html, /id="dummyCounterDetails" class="dummy-detail numeric-detail"/);
assert.match(html, /id="dummyDriveReversalDetails" class="dummy-detail numeric-detail"/);
assert.match(styles, /\.dummy-detail\.numeric-detail \{ margin-left: 0; \}/);
assert.match(html, /<select id="dummyControl" disabled>[\s\S]*?<option value="dummy" selected>陪练/);
assert.doesNotMatch(html, /玩家控制 \(player control\)|CPU \(CPU\)|播放录制 \(play recording\)/);
assert.doesNotMatch(html, /跳跃方向 \(jump type\)|CPU 等级 \(CPU level\)/);
assert.match(html, /<input id="dummyJumpKind" type="hidden" value="0">/);
const guardBlock = html.match(/<select id="dummyGuardType">([\s\S]*?)<\/select>/)[1];
assert.match(guardBlock, /<option value="">未记录/);
assert.doesNotMatch(app, /\["dummyGuard",/, "dead dummyGuard enhancement entry must be removed");
assert.match(app, /Burnout`\)\.addEventListener\("change"/, "burnout must update the drive gauge");
assert.match(
    app,
    /Burnout`\)\.value === "true" \? "0" : "6"/,
    "burnout=true must set drive to 0 and burnout=false must set it to 6"
);
assert.match(app, /FighterId`\)\.disabled = side === attacker/, "attacker fighter select must be locked");
assert.match(app, /state-row/, "state resources must render as a single row");

assert.match(html, /虚损 \(burnout\)/);
assert.match(html, /陪练的动作 \(dummy action\)/);
assert.match(html, /站立 \(stand\)/);
assert.match(html, /蹲下 \(crouch\)/);
assert.match(html, /跳跃 \(jump\)/);
assert.match(html, /随机 \(random\)/);
assert.match(html, /value="2">第2段后格挡 \(2 · after_first_hit\)/);
assert.doesNotMatch(html, /value="1">(?:首击后防御|第2段后格挡)/);
assert.match(html, /value="5">计数格挡 \(5 · count\)/);
assert.match(html, /id="dummyGuardCountRow" class="dummy-menu-row"/);
assert.match(html, /id="dummyGuardCount"/);
assert.match(html, /id="dummyGuardSwitchMode"[\s\S]*value="0">执行 \(execute\)/);
assert.match(html, /value="1">仅站立格挡 \(standing guard only\)/);
assert.match(html, /value="2">仅蹲下格挡 \(crouching guard only\)/);
assert.match(html, /id="dummyGuardKind"[\s\S]*value="0">格挡 \(guard\)/);
assert.match(html, /value="1">斗气招架 \(drive parry\)/);
assert.match(html, /value="2">完美招架 \(perfect parry\)/);
assert.match(app, /populateNumericSelect\("dummyGuardCount", 1, 30/);
assert.match(app, /countGuardEnabled && fillDefaults && \$\("dummyGuardCount"\)/, "count guard must default to one count when first enabled");
assert.match(app, /dummyGuardCountRow"\)\.hidden = !countGuardEnabled/);
assert.match(app, /dummyGuardSwitchModeRow"\)\.hidden = !guardOptionsEnabled/);
assert.match(app, /dummyGuardKindRow"\)\.hidden = !guardOptionsEnabled/);
assert.match(app, /values\.dummy_guard_only_type = parseOptionalNumber\("dummyGuardSwitchMode"\)/);
assert.match(app, /values\.dummy_drive_parry_type = parseOptionalNumber\("dummyGuardKind"\)/);
assert.doesNotMatch(app, /values\.dummy_guard_switching\s*=/, "the internal guard bool must be preserved");
assert.doesNotMatch(app, /\bfillDefault\b/, "dummy menu state must consistently use the fillDefaults flag");
assert.match(html, /T 详细设置：随机打康权重/);
assert.doesNotMatch(html, /T 详细设置：斗气招架/);
assert.match(html, /T 详细设置：斗气反攻随机权重/);
assert.match(html, /id="p1Unique" class="unique-resource-list"/);
assert.match(html, /id="p2Unique" class="unique-resource-list"/);
// 环境页左栏按“连段角色 → 木人”堆叠，右栏独立展示木人训练菜单
assert.match(html, /resource-field unique-focus/);
assert.match(html, /id="dummyEnvBlock"/);
for (const id of ["scenePlayerStack", "p1ScenePanel", "p2ScenePanel", "dummyMenuPanel"]) {
    assert.match(html, new RegExp(`id="${id}"`), `${id} must support the split environment layout`);
}
assert.doesNotMatch(html, /id="p[12]DummySlot"/, "dummy menu must not remain nested in a player panel");
assert.match(
    app,
    /scenePlayerStack"\)\.append\([\s\S]*ScenePanel/,
    "player panels must be ordered as combo character then dummy"
);
assert.match(html, /角色特殊资源为共享设置/);
assert.doesNotMatch(html, /特殊资源 JSON/);
assert.match(app, /enhanceChoiceSelect\(select, "resource"\)/);
assert.match(app, /syncSharedUniqueResources\(prefix, resource\.id\)/);
assert.match(app, /syncSharedUniqueResources\(attackerSide\(\)\)/);
assert.match(app, /collectDummyEnvironment\(\)/);
assert.match(app, /preflightCheck\(\)/);
assert.match(html, /id="mechanismSummary"/);
assert.match(html, /累计伤害 \(damage_at_step\)/);
assert.match(app, /combo_stats\?\.damage/);
assert.match(app, /step\.damage_at_step/);
for (const id of ["resultDamage", "resultDriveUsed", "resultSuperUsed", "resultHitType"]) {
    assert.match(html, new RegExp(`id="${id}"`), `${id} must be visible in metadata`);
}
assert.match(app, /comboStats\.damage/);

// 视觉状态：P1 / P2 / 菜单分色，非默认高亮，未记录置灰。
assert.match(app, /const DUMMY_MENU_DEFAULTS = Object\.freeze/);
assert.match(app, /dummyGuardCount:\s*"10"/, "guard count 10 must be treated as the game default");
assert.match(app, /dummyDriveReversalDelay:\s*"0"/, "drive reversal delay 0 must be the default");
assert.match(app, /dummyDriveReversalCount:\s*"1"/, "drive reversal count 1 must be the default");
assert.match(app, /function updateDummyMenuVisualState/);
assert.match(app, /return "unrecorded"/);
assert.match(app, /\? "default" : "modified"/);
assert.match(html, /class="dummy-state-legend"/);
for (const selector of ["#p1ScenePanel", "#p2ScenePanel", "#dummyMenuPanel"]) {
    assert.match(styles, new RegExp(selector.replace("#", "\\#")), `${selector} must have a visual theme`);
}
assert.match(styles, /--sf6-setting-modified:\s*#ff9f2f/);
assert.match(styles, /\.select-stepper\.is-modified select/);
assert.match(styles, /\.select-stepper\.is-unrecorded select/);
assert.match(
    styles,
    /\.dummy-env\s*\{[\s\S]*?border:\s*0;/,
    "dummy menu content must not create a second outer border"
);

console.log("editor UI contract tests passed");
