import assert from "node:assert/strict";
import fs from "node:fs";
import {
    CHARACTER_CATALOG,
    characterByFighterId,
    characterByFolder,
    characterLabel,
    folderFromPath
} from "./character_catalog.mjs";

const source = JSON.parse(fs.readFileSync(
    new URL("../modern_display_builder/characters.json", import.meta.url),
    "utf8"
));

assert.equal(CHARACTER_CATALOG.length, 30);
assert.equal(new Set(CHARACTER_CATALOG.map(item => item.fighterId)).size, CHARACTER_CATALOG.length);
assert.equal(new Set(CHARACTER_CATALOG.map(item => item.folder.toLowerCase())).size, CHARACTER_CATALOG.length);

for (const item of CHARACTER_CATALOG) {
    assert.equal(source[item.folder].fighter_id, item.fighterId, `${item.folder} fighter_id`);
    assert.equal(characterByFolder(item.folder), item);
    assert.equal(characterByFighterId(item.fighterId), item);
    assert.ok(item.en && item.zh);
}

assert.equal(folderFromPath("AKI/file.json"), "AKI");
assert.equal(folderFromPath("AKI\\file.json"), "AKI");
assert.match(characterLabel(characterByFolder("AKI"), 28), /ID 13.*阿鬼.*A\.K\.I\..*\[AKI\].*28/);

console.log("character_catalog tests passed");
