import fs from "node:fs";
import { performance } from "node:perf_hooks";
import path from "node:path";

function percentile(values, ratio) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * ratio))];
}

function round(value) {
  return Math.round(value * 1000) / 1000;
}

export function buildLookupIndex(runtime) {
  const index = new Map();
  let moves = 0;
  let memberships = 0;
  for (const character of runtime.characters ?? []) {
    const actions = new Map();
    for (const move of character.moves ?? []) {
      moves += 1;
      for (const membership of move.memberships ?? []) {
        memberships += 1;
        const bucket = actions.get(membership.action_id) ?? [];
        bucket.push(move.current_move_uid);
        actions.set(membership.action_id, bucket);
      }
    }
    index.set(character.fighter_id, actions);
  }
  return { index, moves, memberships };
}

export function benchmarkCurrentMoveGraph(filename, options = {}) {
  const iterations = Number(options.iterations ?? 7);
  const lookupIterations = Number(options.lookupIterations ?? 1_000_000);
  if (!Number.isSafeInteger(iterations) || iterations < 2
    || !Number.isSafeInteger(lookupIterations) || lookupIterations < 1) {
    throw new Error("Invalid benchmark iteration count");
  }

  const resolved = path.resolve(filename);
  const readTimes = [];
  const parseTimes = [];
  let raw;
  let runtime;
  for (let index = 0; index < iterations; index += 1) {
    const readStart = performance.now();
    raw = fs.readFileSync(resolved, "utf8");
    readTimes.push(performance.now() - readStart);
    const parseStart = performance.now();
    runtime = JSON.parse(raw);
    parseTimes.push(performance.now() - parseStart);
  }
  if (runtime.schema !== "sf6acbcm.runtime-current.v1"
    || runtime.authority !== "current_semantic_candidate_only") {
    throw new Error("Unsupported current Move graph artifact");
  }

  const beforeIndex = process.memoryUsage().heapUsed;
  const indexStart = performance.now();
  const built = buildLookupIndex(runtime);
  const indexMs = performance.now() - indexStart;
  const afterIndex = process.memoryUsage().heapUsed;
  const lookupKeys = [];
  for (const [fighterId, actions] of built.index) {
    for (const actionId of actions.keys()) lookupKeys.push([fighterId, actionId]);
  }
  lookupKeys.sort((left, right) => left[0] - right[0] || left[1] - right[1]);

  let hits = 0;
  const lookupStart = performance.now();
  for (let index = 0; index < lookupIterations; index += 1) {
    const key = lookupKeys[index % lookupKeys.length];
    if (built.index.get(key[0])?.get(key[1]) != null) hits += 1;
  }
  const lookupMs = performance.now() - lookupStart;
  return {
    schema: "sf6cc.current-move-graph-offline-benchmark.v1",
    authority: "OFFLINE_ESTIMATE",
    limitations: [
      "Node.js V8 is not the REFramework Lua runtime.",
      "Heap delta is an allocation estimate, not retained in-game memory.",
      "No game hooks, UI consumers, or real-time frame budget are exercised."
    ],
    environment: { runtime: process.release.name, version: process.version, platform: process.platform, arch: process.arch },
    artifact: { file: resolved, bytes: Buffer.byteLength(raw), characters: runtime.characters?.length ?? 0, moves: built.moves, memberships: built.memberships },
    read_ms: { iterations, median: round(percentile(readTimes, 0.5)), p95: round(percentile(readTimes, 0.95)) },
    parse_ms: { iterations, median: round(percentile(parseTimes, 0.5)), p95: round(percentile(parseTimes, 0.95)) },
    index: { build_ms: round(indexMs), action_keys: lookupKeys.length, heap_delta_bytes: Math.max(0, afterIndex - beforeIndex) },
    lookup: { iterations: lookupIterations, hits, total_ms: round(lookupMs), nanoseconds_per_lookup: round((lookupMs * 1_000_000) / lookupIterations), complexity: "expected O(1) Map lookup plus candidate list access" }
  };
}

function cliArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value == null) throw new Error("Arguments must be --name value pairs");
    result[key.slice(2)] = value;
  }
  return result;
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname.replace(/^\/(.:)/, "$1"))) {
  const args = cliArgs(process.argv.slice(2));
  if (!args.artifact) throw new Error("Missing --artifact");
  const report = benchmarkCurrentMoveGraph(args.artifact, {
    iterations: args.iterations == null ? undefined : Number(args.iterations),
    lookupIterations: args.lookups == null ? undefined : Number(args.lookups)
  });
  const output = `${JSON.stringify(report, null, 2)}\n`;
  if (args.out) fs.writeFileSync(path.resolve(args.out), output);
  else process.stdout.write(output);
}
