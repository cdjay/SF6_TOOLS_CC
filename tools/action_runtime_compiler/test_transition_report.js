"use strict";

const assert = require("assert");
const tool = require("./transition_report.js");

const branch = (source, target, type, window, params = [0, 0, 0, 0, 0, 0]) =>
    ({ source, target, type, params, window, attr: 0, action_frame: 0, trigger_id: -1, dynamic: false });
const model = {
    actions: new Map([
        [715, { id: 715, branches: [branch(715, 717, 63, { start: 0, end: 2 }, [0, 4, 1, 0, 0, 0])] }],
        [900, { id: 900, branches: [branch(900, 901, 0, { start: 40, end: 41 }), branch(900, 905, 20, { start: 9, end: 18 })] }]
    ]),
    bcmActions: new Map([[715, { triggers: [{ classic_display: "Throw" }] }], [900, { triggers: [{ classic_display: "236+P" }] }]])
};

assert.strictEqual(tool.engineStep({ flags: 0 }), true);
assert.strictEqual(tool.engineStep({ flags: 16, code: 715, branch: 0x2000003F }), true);
assert.strictEqual(tool.engineStep({ flags: 16, code: 0, branch: 0x2000003F }), false);
assert.strictEqual(tool.engineStep({ flags: 16, code: 0, branch: 0x20000014, input: 16 }), true);
assert.strictEqual(tool.engineStep({ flags: 16, code: 0, branch: 0x20000014, input: 0 }), false);

assert.deepStrictEqual(tool.branchBits(8192), [13]);
assert.deepStrictEqual(tool.branchBits(140739635838976), [31, 47], "exact beyond 2^32");
assert.deepStrictEqual(tool.branchBits(0), []);
assert.strictEqual(tool.mechanism(model, { prev: 715, prev_frame: 1, act: 717 }), "T63");
assert.strictEqual(tool.mechanism(model, { prev: 900, prev_frame: 12, act: 905 }), "T20/p0=0");
assert.strictEqual(tool.mechanism(model, { prev: 17, prev_frame: 3, act: 900 }), "bcm");
assert.strictEqual(tool.mechanism(model, { prev: 17, prev_frame: 3, act: 999 }), "unexplained");

const records = [
    { prev: 1, act: 715, flags: 0, code: 715, branch: 0 },
    { prev: 715, prev_frame: 1, act: 717, flags: 16, code: 0, branch: 0x2000003F },
    { prev: 715, prev_frame: 1, act: 717, flags: 16, code: 0, branch: 0x2000003F },
    { prev: 900, prev_frame: 40, act: 901, flags: 16, code: 900, branch: 0 }
];
const result = tool.analyze(model, records, { 717: { force: true }, 901: { ignore: true }, 902: { force: true } });
assert.deepStrictEqual(result.by_mechanism.T63, { total: 2, engine_step: 0, branch_types: { "T0+T1+T2+T3+T4+T5+T29": 2 } });
const verdicts = Object.fromEntries(result.corrections.map(item => [item.action_id, item.verdict]));
assert.deepStrictEqual(verdicts, { 717: "needed", 901: "redundant", 902: "not_observed" },
    "the engine never counts 717, so its force is needed; 901 is never a step, so its ignore is redundant");
assert(tool.markdown({ character: "Ryu", transitions: 4, ...result }).includes("| T63 | 2 | 0 |"));

console.log("transition report tests passed");
