"use strict";

const assert = require("assert");
const modern = require("./modern_display_core.js");

function profile(enabled, notation, flags, cond, inputs) {
    return {
        enabled,
        notation,
        ok_key_flags: flags,
        ok_key_cond_flags: cond || 16416,
        command: { inputs: inputs || [] }
    };
}

const runtime = {
    character: "Akuma",
    fighter_id: 22,
    action_ids: [480, 600, 605, 606, 611, 617, 618, 619, 640, 715, 716, 717, 718, 739, 740, 850, 855, 903, 904, 975, 979, 1075, 1076, 1231, 1240, 1241],
    actions: { "480": "Normal", "600": "LP", "605": "MP", "606": ">MP", "611": "LK", "617": "HK", "618": "EXTRA", "619": "EXTRA2", "640": "2+MK", "715": "Throw", "716": "2+THROW", "717": "4+THROW", "718": "8THROW", "739": "DRC", "740": "RAW DR", "850": "6+DI", "855": "DI", "903": "236+HP", "904": "236+PP", "975": "214+LP", "1075": "6+KKK", "1076": "4+KK", "1231": "5565+HP", "1240": "6646+HP", "1241": "6646+HP" },
    aliases: { "979": "903" },
    sources: { ac_sha256: "ac", bcm_sha256: "bcm" },
    validation: { rules: { "739": { system_action: "drc" }, "740": { system_action: "raw_dr" } } },
    evidence: { ac_derived_commands: [
        { action_id: 716, source_action_id: 715, display: "2+THROW" },
        { action_id: 717, source_action_id: 715, display: "4+THROW" },
        { action_id: 718, source_action_id: 715, display: "8THROW" }
    ] }
};
const catalog = {
    actions: {
        "480": { triggers: [{ trigger_index: 30, profiles: {
            sprt: profile(true, "Normal", 0), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 10, focus_consume: 5000 } }] },
        "600": { triggers: [{ trigger_index: 1, profiles: {
            sprt: profile(true, "LP", 16), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: {} }] },
        "605": { triggers: [{ trigger_index: 2, profiles: {
            sprt: profile(false, "Normal", 0), easy: profile(false, "Normal", 0), supr: profile(true, "Normal", 2147483648)
        }, conditions: {} }] },
        "640": { triggers: [{ trigger_index: 21, profiles: {
            sprt: profile(true, "2+LK", 128), easy: profile(false, "Normal", 0), supr: profile(true, "LK", 128)
        }, conditions: { function_id: 1, cond_owner_state_flags: 0 } }] },
        "606": { triggers: [{ trigger_index: 3, profiles: {
            sprt: profile(true, "LK", 128), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: { turn_around: 2 } }] },
        "715": { triggers: [{ trigger_index: 31, profiles: {
            sprt: profile(true, "Throw", 144, 16480), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 1 } }] },
        "739": { triggers: [{ trigger_index: 32, profiles: {
            sprt: profile(true, "66", 8, 1025), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 13 } }] },
        "740": { triggers: [{ trigger_index: 33, profiles: {
            sprt: profile(true, "66", 8, 17473), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 13 } }] },
        "903": { triggers: [{ trigger_index: 4, profiles: {
            sprt: profile(true, "236+MK", 256, 81952), easy: profile(true, "MP", 32), supr: profile(true, "Normal", 8192)
        }, conditions: { function_id: 2, focus_consume: 0 } }] },
        "904": { triggers: [{ trigger_index: 5, profiles: {
            sprt: profile(true, "236+LP+LK+MK", 400, 82016), easy: profile(true, "MP", 32), supr: profile(true, "Normal", 8192)
        }, conditions: { function_id: 2, focus_consume: 20000 } }] },
        "975": { triggers: [{ trigger_index: 6, profiles: {
            sprt: profile(false, "Normal", 0), easy: profile(false, "Normal", 0), supr: profile(true, "Normal", 2147483648)
        }, conditions: { function_id: 2, focus_consume: 0 } }] },
        "1075": { triggers: [{ trigger_index: 1075, profiles: {
            sprt: profile(true, "6+KKK", 896, 128), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 2 } }] },
        "1076": { triggers: [{ trigger_index: 1076, profiles: {
            sprt: profile(true, "4+KK", 384, 64), easy: profile(false, "Normal", 0), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 2 } }] },
        "1231": { triggers: [{ trigger_index: 138, profiles: {
            sprt: profile(true, "555+MK", 256, 16416, [
                { direction: "5", raw_mask: 16 },
                { direction: "5", raw_mask: 16 },
                { direction: "5", raw_mask: 128 }
            ]),
            easy: profile(false, "Normal", 0),
            supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 3 } }] },
        "1240": { triggers: [{ trigger_index: 1240, profiles: {
            sprt: profile(true, "6646+HP", 256), easy: profile(true, "*+HP", 288), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 3 } }] },
        "1241": { triggers: [{ trigger_index: 1241, profiles: {
            sprt: profile(true, "6646+HP", 256), easy: profile(true, "*+HP", 288), supr: profile(false, "Normal", 0)
        }, conditions: { function_id: 3 } }] }
    }
};
const supplement = {
    "605": { source: "ac_bcm+community_sample", routes: [{
        display: "AUTO + 中", source: "community_sample",
        reason: "Verified same-display route.", note: "Same display keeps one UI route."
    }] },
    "611": { source: "community_sample", modern_display: "AUTO + 弱", note: "Verified light AUTO route." },
    "618": { source: "ac_bcm+community_sample", note: "entry fallback", routes: [{
        display: "AUTO + 中", source: "community_sample",
        note: "Verified supplemental note.", evidence: "lower-priority supplemental evidence"
    }] },
    "619": { source: "ac_bcm+community_sample", note: "entry fallback", routes: [{
        display: "AUTO + 弱", source: "community_sample", evidence: "Verified supplemental evidence."
    }] },
    "617": { source: "ac_bcm+community_sample", note: "entry fallback", routes: [{
        display: "AUTO + 强", source: "community_sample",
        reason: "Verified heavy AUTO route.", note: "lower-priority note", evidence: "lower-priority evidence"
    }] },
    "600": { source: "capcom_official", modern_display: "错误官网值" }
};
const output = modern.buildModernDisplay({}, catalog, runtime, supplement, { generatedAt: "test" });
assert.strictEqual(output._meta.generated_from, "ac_bcm");
assert.strictEqual(output["600"].modern_display, "弱");
assert.strictEqual(output["605"].modern_display, "AUTO + 中");
assert.strictEqual(output["611"].modern_display, "AUTO + 弱");
assert.strictEqual(output["640"].modern_display, "2 + 中");
assert.strictEqual(output["606"].modern_display, "> 中");
assert.strictEqual(output["617"].modern_display, "AUTO + 强");
assert.strictEqual(output["480"].modern_display, "DP");
assert.strictEqual(output["715"].modern_display, "THROW");
assert.strictEqual(output["716"].modern_display, "2 + THROW");
assert.strictEqual(output["717"].modern_display, "4 + THROW");
assert.strictEqual(output["718"].modern_display, "8 + THROW");
assert.strictEqual(output["739"].modern_display, "DRC");
assert.strictEqual(output["740"].modern_display, "RAW DR");
assert.strictEqual(output["850"].modern_display, "6 + DI");
assert.strictEqual(output["855"].modern_display, "DI");
assert.strictEqual(output["903"].modern_display, "SP/236 + 强");
assert.strictEqual(output["904"].modern_display, "AUTO + SP/236 + 攻击二つ");
assert.strictEqual(output["975"].modern_display, "AUTO + 中");
assert.strictEqual(output["979"].modern_display, output["903"].modern_display);
assert.strictEqual(output["1075"].modern_display, "6 + 弱 + 中 + 强");
assert.strictEqual(output["1076"].modern_display, "4 + 攻击二つ");
assert.strictEqual(output["1231"].modern_display, "弱 > 弱 > 中 > 强");
assert.strictEqual(output["1231"].routes[0].source, "bcm_profile");
assert.strictEqual(output["1240"].modern_display, "SP + 强/6646 + 强");
assert.strictEqual(output["1241"].modern_display, "SP + 强/6646 + 强");
assert.strictEqual(output["611"].routes.find(route => route.source === "community_sample").reason,
    "Verified light AUTO route.");
assert.strictEqual(output["611"].routes.find(route => route.source === "community_sample").note,
    "Verified light AUTO route.");
assert.strictEqual(output["618"].routes.find(route => route.source === "community_sample").reason,
    "Verified supplemental note.");
assert.strictEqual(output["618"].routes.find(route => route.source === "community_sample").note,
    "Verified supplemental note.");
assert.strictEqual(output["618"].routes.find(route => route.source === "community_sample").evidence,
    "lower-priority supplemental evidence");
assert.strictEqual(output["619"].routes.find(route => route.source === "community_sample").reason,
    "Verified supplemental evidence.");
assert.strictEqual(output["619"].routes.find(route => route.source === "community_sample").note,
    "Verified supplemental evidence.");
assert.strictEqual(output["619"].routes.find(route => route.source === "community_sample").evidence,
    "Verified supplemental evidence.");
assert.strictEqual(output["617"].routes.find(route => route.source === "community_sample").reason,
    "Verified heavy AUTO route.");
assert.strictEqual(output["617"].routes.find(route => route.source === "community_sample").note,
    "lower-priority note");
assert.strictEqual(output["605"].modern_display, "AUTO + 中");
assert.strictEqual(output["605"].routes.length, 1);
assert.strictEqual(output["605"].routes[0].source, "bcm_profile");
assert.strictEqual(output["605"].routes[0].verification.source, "community_sample");
assert.strictEqual(output["605"].routes[0].verification.reason, "Verified same-display route.");
assert.strictEqual(output["605"].routes[0].verification.note, "Same display keeps one UI route.");
assert.strictEqual(output["605"].source, "ac_bcm+community_sample");
for (const entry of Object.values(output).filter(value => value && Array.isArray(value.routes))) {
    for (const route of entry.routes) {
        assert.strictEqual(/\+\s*\+/.test(route.display), false);
        assert.strictEqual(route.display.includes("攻击三つ"), false);
        assert.strictEqual(route.display.includes("*"), false);
        if (route.source === "community_sample") {
            assert.strictEqual(typeof route.reason, "string");
            assert.strictEqual(typeof route.note, "string");
        }
        if (route.verification && route.verification.source === "community_sample") {
            assert.strictEqual(typeof route.verification.reason, "string");
            assert.strictEqual(typeof route.verification.note, "string");
        }
    }
}
assert.strictEqual(JSON.stringify(output).includes("错误官网值"), false);
const rebuilt = modern.buildModernDisplay({}, catalog, runtime, output, { generatedAt: "test-2" });
assert.strictEqual(rebuilt["617"].modern_display, "AUTO + 强");
assert.strictEqual(rebuilt["605"].routes.length, 1);
assert.strictEqual(rebuilt["605"].routes[0].source, "bcm_profile");
assert.deepStrictEqual(rebuilt["605"].routes[0].verification, output["605"].routes[0].verification);
for (const invalidDisplay of ["4 + + SP", "攻击三つ", "* + SP"]) {
    assert.throws(() => modern.buildModernDisplay({}, catalog, runtime, {
        "617": { source: "community_sample", modern_display: invalidDisplay, note: "invalid test route" }
    }, { generatedAt: "invalid" }), /非法 Modern 显示 token/);
}
assert.throws(() => modern.buildModernDisplay({}, catalog, runtime, {
    "617": { source: "community_sample", modern_display: "AUTO + 强" }
}, { generatedAt: "missing-reason" }), /缺少 reason\/note/);
console.log("Modern display compiler tests passed.");
