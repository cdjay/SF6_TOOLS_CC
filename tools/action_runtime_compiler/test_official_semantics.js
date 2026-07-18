"use strict";

const assert = require("assert");
const core = require("./official_semantics_core.js");

const payload = [
    { language: "en", control_type: "classic", sections: [{ title: "Special", rows: [["Move A\n236 + L"]] }] },
    { language: "en", control_type: "modern", source_url: "https://example.test", sections: [{ title: "Special", rows: [["Move A\nSP"]] }] }
];
const result = core.buildOfficialSemantics("Luke", "LUKE.json", payload, { sourceSha256: "abc", generatedAt: "2026-05-28T00:00:00Z" });
assert.strictEqual(result._meta.source_format, "paired_official_table_dump");
assert.strictEqual(result._meta.updated_at, "2026-05-28");
assert.strictEqual(result._semantic_rows[0].classic_display, "236 + L");
assert.strictEqual(result._semantic_rows[0].modern_display, "SP");
assert.strictEqual(core.OFFICIAL_DUMP_FILENAMES.MBison, "VEGA.json");
console.log("official semantics tests passed");
