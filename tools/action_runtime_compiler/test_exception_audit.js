"use strict";

const assert = require("assert");
const audit = require("./exception_derivation_audit.js");

function branch(source, target, type, params = [0, 0, 0, 0, 0, 0]) {
    return { source, target, type, attr: 0, action_frame: 0, params, trigger_id: -1, window: null, dynamic: false };
}

// 715 (throw, BCM) -T63-> 717 (back throw, inherited); 900 (special, BCM)
// -T0-> 901 (phase); 901 -T13-> 902; 950 -T20 release-> 951.
const actions = new Map([
    [715, { id: 715, branches: [branch(715, 717, 63, [0, 4, 1, 0, 0, 0])], triggerKeys: [] }],
    [717, { id: 717, branches: [], triggerKeys: [] }],
    [900, { id: 900, branches: [branch(900, 901, 0)], triggerKeys: [] }],
    [901, { id: 901, branches: [branch(901, 902, 13)], triggerKeys: [] }],
    [902, { id: 902, branches: [], triggerKeys: [] }],
    [950, { id: 950, branches: [branch(950, 951, 20)], triggerKeys: [] }],
    [951, { id: 951, branches: [], triggerKeys: [] }]
]);
const incoming = new Map();
for (const action of actions.values()) for (const item of action.branches) {
    if (!incoming.has(item.target)) incoming.set(item.target, []);
    incoming.get(item.target).push(item);
}
const classic = display => ({ triggers: [{ classic_display: display }] });
const model = {
    actions, incoming, common: { actions: new Map(), incoming: new Map() },
    bcmActions: new Map([[715, classic("Throw")], [900, classic("236+P")], [950, classic("214+K")]]),
    groups: { enables: new Map() }, keyed_groups: true, frame_windows: true
};

assert.strictEqual(audit.branchKind(branch(1, 2, 20, [1, 16, 0, 0, 0, 0])), "T20/p0=1");
assert.strictEqual(audit.incomingSignature(model, "character", 717), "T63");
assert.strictEqual(audit.incomingSignature(model, "character", 715), "bcm|noinc");
assert.strictEqual(audit.pairSignature(model, "character", 900, 901), "T0");
assert.strictEqual(audit.pairSignature(model, "character", 900, 902), "2hop:T0>T13");
assert.strictEqual(audit.pairSignature(model, "character", 901, 900), "rev:T0");
assert.strictEqual(audit.pairSignature(model, "character", 717, 951), "none");
assert.deepStrictEqual(audit.facetItems({ id: 717, rule: { force: true, absorb_ids: "718,719" } }, "character")
    .map(item => `${item.facet}:${item.other ?? ""}`), ["force:", "absorb:718", "absorb:719"]);

const scores = {};
audit.scoreCandidates(scores, "Ryu", model,
    { 717: { force: true }, 900: { absorb_ids: "901" }, 951: { ignore_prev_id: 950 } },
    {},
    { 717: { ownership: "inherited" }, 715: { ownership: "direct" }, 900: { ownership: "direct" } },
    { Ryu: { 715: 3 } });
const inherited = scores["force: ownership=inherited"];
assert.strictEqual(inherited.covered, 1);
assert.strictEqual(inherited.added, 0);
const direct = scores["force: ownership=direct"];
assert.strictEqual(direct.added, 2, "direct actions without force are additions");
assert.strictEqual(direct.added_in_corpus, 1, "715 occurs as a recorded step");
assert.strictEqual(scores["absorb: automatic phase of a BCM action"].covered, 1);
assert.strictEqual(scores["ignore_prev: Type 20 release continuation"].covered, 1);

console.log("exception derivation audit tests passed");
