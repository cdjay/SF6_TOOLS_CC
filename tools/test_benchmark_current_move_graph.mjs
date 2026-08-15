import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { benchmarkCurrentMoveGraph, buildLookupIndex } from "./benchmark_current_move_graph.mjs";

const runtime = {
  schema: "sf6acbcm.runtime-current.v1",
  authority: "current_semantic_candidate_only",
  characters: [{
    fighter_id: 1,
    moves: [
      { current_move_uid: "move-a", memberships: [{ action_id: 600 }, { action_id: 601 }] },
      { current_move_uid: "move-b", memberships: [{ action_id: 600 }] }
    ]
  }]
};
const built = buildLookupIndex(runtime);
assert.equal(built.moves, 2);
assert.equal(built.memberships, 3);
assert.deepEqual(built.index.get(1).get(600), ["move-a", "move-b"]);

const root = fs.mkdtempSync(path.join(os.tmpdir(), "sf6cc-move-benchmark-"));
const filename = path.join(root, "runtime-current.v1.json");
fs.writeFileSync(filename, JSON.stringify(runtime));
const report = benchmarkCurrentMoveGraph(filename, { iterations: 2, lookupIterations: 100 });
assert.equal(report.authority, "OFFLINE_ESTIMATE");
assert.equal(report.artifact.moves, 2);
assert.equal(report.index.action_keys, 2);
assert.equal(report.lookup.hits, 100);
assert.equal(report.lookup.complexity.includes("O(1)"), true);

console.log("Current Move graph benchmark tests passed");
