import assert from "node:assert/strict";
import fs from "node:fs";

const html = fs.readFileSync(new URL("./index.html", import.meta.url), "utf8");
const app = fs.readFileSync(new URL("./app.mjs", import.meta.url), "utf8");

const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, "HTML ids must be unique");

const staticAppReferences = [...app.matchAll(/\$\("([A-Za-z0-9_-]+)"\)/g)].map(match => match[1]);
for (const id of new Set(staticAppReferences)) {
    assert.ok(ids.includes(id), `missing HTML element #${id}`);
}

const selectIds = [
    "statusFilter",
    "rating",
    "dummyAction",
    "dummyJumpKind",
    "dummyGuardType",
    "p1FighterId",
    "p2FighterId",
    "p1Burnout",
    "p2Burnout"
];
for (const id of selectIds) {
    assert.match(html, new RegExp(`<select id="${id}"`), `${id} must be a single-choice select`);
}
// fighter_id 必须是原生下拉框，不得再增强为选项块
for (const id of ["p1FighterId", "p2FighterId"]) {
    assert.doesNotMatch(app, new RegExp(`\\["${id}",`), `${id} must stay a native select`);
}
// 木人四字段由“木人动作”自动派生，不再提供独立控件
for (const id of ["dummyStance", "dummyActionType", "dummyJumpType", "requiresDummyCrouch"]) {
    assert.doesNotMatch(html, new RegExp(`id="${id}"`), `${id} must be derived, not a standalone control`);
}
assert.doesNotMatch(html, /id="dummyGuard"/, "legacy dummy_guard alias must not be editable");
// 眩晕 / 姿态仅记录、改了也无效，已从表单隐藏
for (const id of ["p1Stunned", "p2Stunned", "p1Stance", "p2Stance"]) {
    assert.doesNotMatch(html, new RegExp(`id="${id}"`), `${id} must be hidden from the form`);
}
for (const id of selectIds.filter(id => !/^p[12]FighterId$/.test(id))) {
    assert.match(app, new RegExp(`\\["${id}",\\s*"`), `${id} must be enhanced into choice boxes`);
}
// 无“清空”选项的控件：未记录时取默认值（否 / 站立 / 不防御）
for (const id of ["p1Burnout", "p2Burnout", "dummyAction", "dummyGuardType"]) {
    const block = html.match(new RegExp(`<select id="${id}">([\\s\\S]*?)</select>`))[1];
    assert.doesNotMatch(block, /<option value=""/, `${id} must not offer a clear/empty option`);
}
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
assert.match(html, /木人动作 \(dummy action\)/);
assert.match(html, /站立 \(stand\)/);
assert.match(html, /蹲下 \(crouch\)/);
assert.match(html, /跳跃 \(jump\)/);
assert.match(html, /原地 \(vertical\)/);
assert.match(html, /前跳 \(front\)/);
assert.match(html, /后跳 \(back\)/);
assert.match(html, /随机 \(random\)/);
assert.match(html, /value="2">第2段后格挡 \(2 · after_first_hit\)/);
assert.doesNotMatch(html, /value="1">(?:首击后防御|第2段后格挡)/);
assert.match(html, /id="p1Unique" class="unique-resource-list"/);
assert.match(html, /id="p2Unique" class="unique-resource-list"/);
// 环境页为左右分列：特殊资源在各自栏目内重点展示，木人设置挂在木人侧栏目
assert.match(html, /resource-field unique-focus/);
assert.match(html, /id="dummyEnvBlock"/);
assert.match(html, /id="p1DummySlot"/);
assert.match(html, /id="p2DummySlot"/);
assert.match(app, /DummySlot`\)\.append/, "dummy settings block must be mounted into the dummy-side column");
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

console.log("editor UI contract tests passed");
