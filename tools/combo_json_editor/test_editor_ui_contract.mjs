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
    "dummyGuard",
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
// 眩晕 / 姿态仅记录、改了也无效，已从表单隐藏
for (const id of ["p1Stunned", "p2Stunned", "p1Stance", "p2Stance"]) {
    assert.doesNotMatch(html, new RegExp(`id="${id}"`), `${id} must be hidden from the form`);
}
for (const id of selectIds.filter(id => !/^p[12]FighterId$/.test(id))) {
    assert.match(app, new RegExp(`\\["${id}",\\s*"`), `${id} must be enhanced into choice boxes`);
}

assert.match(html, /虚损 \(burnout\)/);
assert.match(html, /木人动作 \(dummy action\)/);
assert.match(html, /站立 \(stand\)/);
assert.match(html, /蹲下 \(crouch\)/);
assert.match(html, /跳跃 \(jump\)/);
assert.match(html, /原地 \(vertical\)/);
assert.match(html, /前跳 \(front\)/);
assert.match(html, /后跳 \(back\)/);
assert.match(html, /随机 \(random\)/);
assert.match(html, /id="p1Unique" class="unique-resource-list"/);
assert.match(html, /id="p2Unique" class="unique-resource-list"/);
assert.doesNotMatch(html, /特殊资源 JSON/);
assert.match(app, /enhanceChoiceSelect\(select, "resource"\)/);
assert.match(app, /collectDummyEnvironment\(\)/);
assert.match(app, /preflightCheck\(\)/);

console.log("editor UI contract tests passed");
