import assert from "node:assert/strict";
import fs from "node:fs";

const html = fs.readFileSync(new URL("./index.html", import.meta.url), "utf8");
const app = fs.readFileSync(new URL("./app.mjs", import.meta.url), "utf8");
const styles = fs.readFileSync(new URL("./styles.css", import.meta.url), "utf8");

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML ids must be unique");

assert.doesNotMatch(html, /id="saveAllChanges"/, "save-all must remain a global header action");
assert.match(html, /id="saveAll" disabled>保存全部修改 \(Save all changes\)<\/button>/);
assert.match(app, /保存全部修改 · \$\{changedCount\}/);
assert.match(html, /id="refreshDirectory" disabled>刷新目录 \(Refresh directory\)<\/button>/);
assert.match(app, /indexedDB\.open\(DIRECTORY_HANDLE_DB, 1\)/);
assert.match(app, /objectStore\(DIRECTORY_HANDLE_STORE\)\.put\(handle, LAST_DIRECTORY_KEY\)/);
assert.match(app, /async function refreshDirectory/);
assert.match(app, /await loadDirectoryHandle\(handle, selectedPath\)/);
assert.match(app, /\$\("refreshDirectory"\)\.onclick = \(\) => refreshDirectory\(\)/);
assert.match(app, /restoreRememberedDirectory\(\);\s*$/);
for (const id of ["upgradeCurrent", "applyCurrent", "saveCurrent", "downloadCurrent"]) {
    assert.match(
        html,
        new RegExp(`id="currentComboActions"[\\s\\S]*?id="${id}"`),
        `${id} must live inside the current combo action card`
    );
}
for (const id of [
    "currentComboTitle",
    "currentComboCharacter",
    "currentComboAuthor",
    "currentComboControl",
    "currentComboLanguage",
    "currentComboCategory",
    "currentComboRating"
]) {
    assert.match(html, new RegExp(`id="${id}"`), `${id} must appear in the combo summary card`);
    assert.match(app, new RegExp(`\\$\\("${id}"\\)`), `${id} must be populated from the selected combo`);
}
assert.match(
    app,
    /\$\("scenePlayerStack"\)\.append\([\s\S]*?\$\("currentComboActions"\)/,
    "single-combo actions must follow the dummy player card"
);

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
assert.match(
    guardBlock,
    /value="0">不格挡[\s\S]*value="3">格挡全部[\s\S]*value="5">计数格挡[\s\S]*value="2">第2段后格挡[\s\S]*value="4">随机格挡/,
    "guard options must follow the native menu order"
);
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
assert.match(
    app,
    /const driveReversalEnabled = guardOptionsEnabled\s*&&\s*!\["", "0"\]\.includes/,
    "drive reversal delay/count must stay disabled when guard is none"
);
assert.match(app, /values\.dummy_guard_only_type = parseOptionalNumber\("dummyGuardSwitchMode"\)/);
assert.match(app, /values\.dummy_drive_parry_type = parseOptionalNumber\("dummyGuardKind"\)/);
assert.doesNotMatch(app, /values\.dummy_guard_switching\s*=/, "the internal guard bool must be preserved");
assert.doesNotMatch(app, /\bfillDefault\b/, "dummy menu state must consistently use the fillDefaults flag");
assert.match(html, /T 详细设置：随机打康权重/);
assert.doesNotMatch(html, /T 详细设置：斗气招架/);
assert.match(html, /T 详细设置：斗气反攻随机权重/);
const driveReversalBlock = html.match(/<select id="dummyDriveReversalType">([\s\S]*?)<\/select>/)[1];
assert.match(
    driveReversalBlock,
    /value="0">不执行[\s\S]*value="1">格挡发动[\s\S]*value="2">起身发动[\s\S]*value="3">随机/,
    "drive reversal options must follow the native menu order"
);
const wakeupBlock = html.match(/<select id="dummyWakeupType">([\s\S]*?)<\/select>/)[1];
assert.match(
    wakeupBlock,
    /value="0">原地受身[\s\S]*value="1">后退受身[\s\S]*value="2">随机/,
    "wakeup options must follow the native menu order"
);
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

// 场景资源按游戏 HUD 表达：生命槽可点击并可手输，斗气 / SA 只保留格子交互。
for (const side of ["p1", "p2"]) {
    assert.match(
        html,
        new RegExp(`id="${side}HpGauge" class="resource-segments hp-segments gauge-track" role="group"`),
        `${side} HP must expose a segmented clickable gauge`
    );
    assert.match(
        html,
        new RegExp(`id="${side}Hp" type="number" min="0" max="11000"`),
        `${side} HP must retain direct numeric entry`
    );
    for (const resource of ["Drive", "Super"]) {
        assert.match(
            html,
            new RegExp(`id="${side}${resource}" type="hidden"`),
            `${side} ${resource} must be stored without a manual number input`
        );
        assert.doesNotMatch(
            html,
            new RegExp(`id="${side}${resource}" type="number"`),
            `${side} ${resource} must not expose manual numeric entry`
        );
    }
}
assert.match(html, /生命槽 <small>\(HP gauge · hp\)<\/small>/);
assert.match(html, /斗气槽 <small>\(Drive gauge · drive\)<\/small>/);
assert.match(html, /超级必杀槽 <small>\(Super Art gauge · super\)<\/small>/);
for (const side of ["p1", "p2"]) {
    assert.match(
        html,
        new RegExp(
            `<div class="field-row gauge-field drive-gauge-field">[\\s\\S]*?id="${side}DriveQuick"[\\s\\S]*?class="drive-burnout-field row-field"[\\s\\S]*?id="${side}Burnout"[\\s\\S]*?<\\/div>`
        ),
        `${side} burnout must be contained inside the Drive gauge frame`
    );
}
assert.match(styles, /\.drive-burnout-field\s*\{[\s\S]*?grid-column:\s*1 \/ -1/);
assert.match(app, /const HP_GAUGE_MAX = 11000/);
assert.match(app, /const HP_GAUGE_LOW = 2000/);
assert.match(app, /const HP_GAUGE_SEGMENTS = 10/);
assert.match(app, /function hpGaugeMaxForSide/);
assert.match(app, /snapshot_gauges\?\.\[role\]\?\.max_hp/);
assert.match(app, /renderHealthGauge\(side\)/);
assert.match(app, /length: HP_GAUGE_SEGMENTS/, "HP gauge must render ten segments");
assert.match(app, /track\.className = "gauge-track"/, "Drive and Super segments must share one connected track");
assert.match(app, /track\.append\(\.\.\.segments\)/, "connected tracks must contain every clickable segment");
assert.match(app, /renderSegmentGauge\(side, "Drive", 6\)/);
assert.match(app, /renderSegmentGauge\(side, "Super", 3\)/);
assert.match(app, /current === value \? value - 1 : value/, "clicking the last filled segment must allow zero");
assert.match(app, /syncHealthGauge/, "manual HP entry must update its visual gauge");
assert.match(styles, /\.hp-segments\.is-low/);
assert.match(styles, /\.drive-segments \{ --gauge-fill:/);
assert.match(app, /resource === "Drive"[\s\S]*?classList\.toggle\(\s*"is-burnout"/);
assert.match(app, /Burnout`\)\.value === "true"/, "Drive burnout styling must follow the side's burnout field");
assert.match(styles, /\.drive-segments\.is-burnout\s*\{[\s\S]*?--gauge-fill:\s*#c7ced8/);
assert.doesNotMatch(
    styles,
    /\.drive-segments\.is-burnout\s*\{[^}]*--gauge-empty:/s,
    "burnout must recolor only filled Drive segments and preserve visible empty slots"
);
assert.match(styles, /--gauge-empty:\s*#485365/, "unfilled gauge tracks must use a visible gray");
assert.match(styles, /\.gauge-track\s*\{[\s\S]*?grid-template-columns:\s*repeat\(var\(--gauge-segment-count\)/);
assert.match(styles, /\.gauge-track \.gauge-segment \+ \.gauge-segment/);
assert.match(styles, /--resource-gauge-height:\s*0\.875rem/);
assert.match(
    styles,
    /\.hp-segments\.gauge-track::after\s*\{[\s\S]*?left:\s*20%;[\s\S]*?border-bottom:\s*6px solid var\(--sf6-warning\)/,
    "HP must show an upward yellow marker below the boundary between segments two and three"
);
assert.match(
    styles,
    /\.health-gauge-control,\s*\.drive-segments,\s*\.super-segments\s*\{[\s\S]*?grid-template-columns:\s*minmax\(108px, 1fr\) var\(--resource-gauge-value-width\)/,
    "HP, Drive, and Super must share exactly the same track and value columns"
);
assert.match(styles, /\.gauge-track\s*\{[\s\S]*?clip-path:\s*none/s, "resource tracks must be rectangular");
assert.match(
    styles,
    /\.resource-segments \.gauge-segment,[\s\S]*?border-radius:\s*0;[\s\S]*?clip-path:\s*none/s,
    "each clickable resource segment must also be rectangular"
);
assert.doesNotMatch(styles, /--resource-gauge-slant/, "slanted resource tracks must not return");
assert.match(styles, /font:\s*var\(--sf6-font-heavy\) 1\.0625rem\/1/);

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
