"use strict";

const assert = require("assert");
const tool = require("./hold_window_report.js");

const ref = id => ({ kind: "ref", object_id: id });
const num = value => ({ kind: "number", value });

function branch(id, fields) {
    return { object_id: id, object_type: "CharacterAsset.BranchKey",
        fields: Object.entries(fields).map(([name, value]) => ({ name, value: num(value) })) };
}

// Action 900 (50 frames): hold LP, classic window 24-49, modern window 24-49.
function ac(withWindows) {
    const window = withWindows ? { _StartFrame: 24, _EndFrame: 49 } : {};
    return {
        records: [{ native_action_id: 900, source_scope: "character", action_ref: ref(1) }],
        objects: [
            { object_id: 1, object_type: "FAB.ACTION", fields: [
                { name: "Frame", value: num(50) }, { name: "Keys", value: ref(2) }] },
            { object_id: 2, object_type: "List", items: [{ value: ref(3) }] },
            { object_id: 3, object_type: "List", items: [{ value: ref(4) }, { value: ref(5) }, { value: ref(6) }] },
            branch(4, { Type: 20, Action: 906, Param00: 0, Param01: 16, Param03: 1, ...window }),
            branch(5, { Type: 20, Action: 906, Param00: 0, Param01: 128, Param03: 2, ...window }),
            branch(6, { Type: 0, Action: 916, Param00: 0, Param01: 0, Param03: 0 })
        ]
    };
}

assert.deepStrictEqual(tool.frameWindow({ fields: [
    { name: "<StartFrame>k__BackingField", value: num(3) }, { name: "EndFrame", value: num(9) }] }), { start: 3, end: 9 });
assert.strictEqual(tool.frameWindow({ fields: [{ name: "Type", value: num(20) }] }), null);

const complete = tool.actionRoots(ac(true));
const keys = tool.holdKeys(complete, 900);
assert.strictEqual(keys.length, 2, "only Type 20 keys");
assert.deepStrictEqual(keys.map(key => [key.profile, key.button_mask]), [[1, 16], [2, 128]]);
assert.deepStrictEqual(keys[0].window, { start: 24, end: 49 });
assert.strictEqual(tool.classify({ charge_min: 24, charge_max: 49 }, keys, 50), "consistent");
assert.strictEqual(tool.classify({ charge_min: 10, charge_max: 49 }, keys, 50), "inconsistent");
assert.strictEqual(tool.classify({}, keys, 50), "no_threshold");
assert.strictEqual(tool.classify({ charge_min: 24 }, [], 50), "no_type20");

const legacy = tool.actionRoots(ac(false));
assert.strictEqual(tool.classify({ charge_min: 24, charge_max: 49 }, tool.holdKeys(legacy, 900), 50),
    "frame_window_missing", "dumps without inherited fields must not be guessed");

const markdown = tool.markdown({ version: "2026-10-13", fighters: [{ character: "Akuma", rows: [{
    action_id: 900, charge_min: 24, charge_max: 49, action_frame: 50, verdict: "consistent", keys }] }] });
assert(markdown.includes("consistent 1") && markdown.includes("T20→906(键16,档1,24-49)"));

console.log("hold window report tests passed");
