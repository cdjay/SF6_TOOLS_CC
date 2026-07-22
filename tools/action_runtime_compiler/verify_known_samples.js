#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const compiler = require("./compiler_core.js");

function usage() {
    console.error("用法: node verify_known_samples.js --evidence-dir <包含本田、迪·杰与英格丽德完整AC+BCM的目录>");
}

function parseArgs(argv) {
    const result = {};
    for (let index = 0; index < argv.length; index += 1) {
        const key = argv[index];
        if (!key.startsWith("--") || index + 1 >= argv.length) throw new Error(`无效参数: ${key}`);
        result[key.slice(2)] = argv[++index];
    }
    return result;
}

function readJson(filename) {
    const text = fs.readFileSync(filename, "utf8").replace(/^\uFEFF/, "");
    return bcmCore.parseSourceText(text);
}

function compilePair(directory, stem) {
    const acPath = path.join(directory, `${stem}-fab-action-catalog-full-classic.json`);
    const bcmPath = path.join(directory, `${stem}-fab-bcm-full-classic.json`);
    const result = compiler.compile(readJson(acPath), readJson(bcmPath), {});
    assert.notStrictEqual(result.report.status, "invalid", `${stem} 编译结果无效`);
    return result.runtime;
}

function expectActions(runtime, expected) {
    for (const [id, display] of Object.entries(expected)) {
        assert.strictEqual(runtime.actions[id], display, `${runtime.character} Action ${id}`);
    }
}

function expectAliases(runtime, expected) {
    for (const [id, target] of Object.entries(expected)) {
        assert.strictEqual(runtime.aliases[id], String(target), `${runtime.character} Alias ${id}`);
    }
}

try {
    const args = parseArgs(process.argv.slice(2));
    if (!args["evidence-dir"]) throw new Error("缺少 --evidence-dir");
    const directory = path.resolve(args["evidence-dir"]);

    const honda = compilePair(directory, "本田20");
    expectActions(honda, {
        "500": "DRC", "501": "RAW DR", "610": "MK",
        "615": "2+LP", "616": "2+LP", "617": "2+LP",
        "626": "2+LK", "627": "2+LK", "628": "2+LK", "633": "2+MK",
        "652": "j.6+HP", "653": "j.4+HP", "717": "4+THROW", "972": ">2+HK"
    });
    expectAliases(honda, {
        "611": 610, "629": 626, "630": 627, "631": 628, "634": 633, "973": 972
    });
    expectActions(honda, {
        "667": ">MP", "670": ">3+HK", "959": ">P", "960": ">P",
        "961": ">2+P", "964": ">P", "966": ">P", "967": ">2+P"
    });

    const deeJay = compilePair(directory, "迪·杰11");
    expectActions(deeJay, { "1219": "LP", "1230": "LP" });
    assert.strictEqual(deeJay.validation.rules["1219"].target_combo_followup, false);
    assert.strictEqual(deeJay.validation.rules["1230"].target_combo_followup, false);
    assert.strictEqual(deeJay.validation.rules["1219"].followup_evidence, undefined);
    assert.strictEqual(deeJay.validation.rules["1230"].followup_evidence, undefined);

    const ingrid = compilePair(directory, "英格丽德32");
    expectActions(ingrid, {
        "739": "DRC", "740": "RAW DR", "606": ">MK",
        "656": ">j.HK", "671": ">HP", "675": ">HP"
    });
    assert.deepStrictEqual(ingrid.validation.rules["606"].optional_parent_ids, [605]);
    assert.deepStrictEqual(ingrid.validation.rules["656"].optional_parent_ids, [655]);
    assert.deepStrictEqual(ingrid.validation.rules["671"].optional_parent_ids, [670]);
    assert.deepStrictEqual(ingrid.validation.rules["675"].optional_parent_ids, [674]);
    assert.strictEqual(ingrid.validation.rules["1200"].is_holdable, true);
    assert.strictEqual(ingrid.validation.rules["1217"].is_holdable, true);
    assert.strictEqual(ingrid.validation.rules["1222"].is_holdable, true);
    assert.strictEqual(ingrid.validation.rules["1227"].is_holdable, true);
    assert.strictEqual(ingrid.aliases["1075"], "1074");
    assert.strictEqual(ingrid.aliases["1093"], "1091");
    expectActions(ingrid, {
        "1219": "214214+MP", "1224": "214214+LP", "1229": "214214+HP"
    });
    assert.strictEqual(ingrid.aliases["1219"], undefined);
    assert.strictEqual(ingrid.aliases["1224"], undefined);
    assert.strictEqual(ingrid.aliases["1229"], undefined);
    assert.deepStrictEqual(ingrid.validation.rules["1219"], {
        display: "214214+MP", display_source: "ac-hold-level-stage", force: true,
        branch_source_action_id: 1217, branch_type: 29
    });
    assert.deepStrictEqual(ingrid.validation.rules["1224"], {
        display: "214214+LP", display_source: "ac-hold-level-stage", force: true,
        branch_source_action_id: 1222, branch_type: 29
    });
    assert.deepStrictEqual(ingrid.validation.rules["1229"], {
        display: "214214+HP", display_source: "ac-hold-level-stage", force: true,
        branch_source_action_id: 1227, branch_type: 29
    });

    console.log(JSON.stringify({
        status: "passed",
        honda: { character: honda.character, coverage: honda.coverage },
        dee_jay: { character: deeJay.character, coverage: deeJay.coverage },
        ingrid: { character: ingrid.character, coverage: ingrid.coverage }
    }, null, 2));
} catch (error) {
    usage();
    console.error(error.message);
    process.exit(1);
}
