import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const script = path.join(
    path.dirname(fileURLToPath(import.meta.url)),
    "fill_dummy_menu_defaults.mjs"
);
const root = await fs.mkdtemp(path.join(os.tmpdir(), "sf6cc-fill-defaults-"));
const lily = path.join(root, "Lily");

function combo(overrides = {}) {
    return [{
        id: 855,
        motion: "DI",
        recorded_by: 0,
        has_contact: false,
        _xt_meta: { environment: {} },
        ...overrides
    }];
}

async function write(name, document) {
    const target = path.join(lily, name);
    await fs.writeFile(target, `${JSON.stringify(document, null, 2)}\n`, "utf8");
    return target;
}

try {
    await fs.mkdir(lily, { recursive: true });
    const hitPath = await write("hit_stun.json", combo({
        has_piyo: true,
        piyo_frame: 149,
        has_hit: true,
        has_contact: true
    }));
    const blockedPath = await write("blocked_stun.json", combo({
        has_piyo: true,
        piyo_frame: 116,
        has_hit: false
    }));
    const ordinaryPath = await write("ordinary_di.json", combo());

    const run = spawnSync(process.execPath, [
        script,
        "--root",
        root,
        "--write",
        "--expected-count",
        "3"
    ], {
        cwd: path.dirname(script),
        encoding: "utf8"
    });
    assert.equal(run.status, 0, `${run.stdout}\n${run.stderr}`);

    const hit = JSON.parse(await fs.readFile(hitPath, "utf8"))[0];
    assert.equal(hit.scene_state.players.p2.resources.drive, 0);
    assert.equal(hit.scene_state.players.p2.status.burnout, true);
    assert.equal(hit.dummy_guard_type, 2);
    assert.equal(hit._xt_meta.dummy_guard_type, 2);
    assert.equal(hit._xt_meta.environment.dummy_guard_type, 2);

    const blocked = JSON.parse(await fs.readFile(blockedPath, "utf8"))[0];
    assert.equal(blocked.scene_state.players.p2.resources.drive, 0);
    assert.equal(blocked.scene_state.players.p2.status.burnout, true);
    assert.equal(blocked.dummy_guard_type, 3);
    assert.equal(blocked._xt_meta.dummy_guard_type, 3);
    assert.equal(blocked._xt_meta.environment.dummy_guard_type, 3);

    const ordinary = JSON.parse(await fs.readFile(ordinaryPath, "utf8"))[0];
    assert.equal(ordinary.scene_state.players.p2.resources.drive, 60000);
    assert.equal(ordinary.scene_state.players.p2.status.burnout, false);
    assert.equal(ordinary.dummy_guard_type, 2);

    console.log("fill dummy menu defaults tests passed");
} finally {
    await fs.rm(root, { recursive: true, force: true });
}
