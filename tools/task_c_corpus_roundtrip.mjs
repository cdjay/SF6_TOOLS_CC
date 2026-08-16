#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import {
    mechanismProjection,
    metadataModel,
    parseComboJson,
    serializeComboJson,
    validateComboDocument,
} from "./combo_json_editor/combo_json_core.mjs";


function parseArgs(argv) {
    const args = {};
    for (let index = 0; index < argv.length; index += 2) {
        args[argv[index]] = argv[index + 1];
    }
    if (!args["--output"]
        || (!args["--case-index"] && (!args["--manifest"] || !args["--corpus-root"]))) {
        throw new Error("Usage: node tools/task_c_corpus_roundtrip.mjs (--case-index <file> | --manifest <file> --corpus-root <dir>) --output <file>");
    }
    return args;
}


function canonical(value) {
    if (Array.isArray(value)) return value.map(canonical);
    if (value && typeof value === "object") {
        return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
    }
    return value;
}


function equal(left, right) {
    return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right));
}


function findManifestFile(corpusRoot, entry) {
    const characterRoot = path.join(corpusRoot, `${entry.character}_CustomCombos`);
    const matches = [];
    const visit = directory => {
        for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
            const filename = path.join(directory, item.name);
            if (item.isDirectory()) visit(filename);
            else if (item.name === entry.filename) matches.push(filename);
        }
    };
    if (fs.existsSync(characterRoot)) visit(characterRoot);
    if (matches.length !== 1) {
        throw new Error(`${entry.character}/${entry.filename}: expected one file, found ${matches.length}`);
    }
    return matches[0];
}


function main() {
    const args = parseArgs(process.argv.slice(2));
    const indexed = args["--case-index"]
        ? JSON.parse(fs.readFileSync(args["--case-index"], "utf8"))
        : null;
    const manifest = indexed || JSON.parse(fs.readFileSync(args["--manifest"], "utf8"));
    const cases = indexed
        ? indexed.cases
        : manifest.files.map(entry => ({
            ...entry,
            path: findManifestFile(args["--corpus-root"], entry),
        }));
    const results = [];
    const failures = [];
    const warningCases = [];
    const warnings = new Map();
    const started = Date.now();

    for (const entry of cases) {
        const filename = entry.path;
        const source = fs.readFileSync(filename, "utf8");
        const row = {
            character: entry.character,
            filename: entry.filename,
            path: filename,
            pass: false,
            warning_count: 0,
        };
        try {
            const first = parseComboJson(source, filename);
            const firstValidation = validateComboDocument(first);
            const serializedOnce = serializeComboJson(first);
            const second = parseComboJson(serializedOnce, `${filename}:roundtrip-1`);
            const serializedTwice = serializeComboJson(second);
            const third = parseComboJson(serializedTwice, `${filename}:roundtrip-2`);
            const exactObjectRoundtrip = equal(first, second) && equal(second, third);
            const mechanismRoundtrip = equal(
                mechanismProjection(first),
                mechanismProjection(third),
            );
            const metadataRoundtrip = equal(metadataModel(first), metadataModel(third));
            const deterministicSerialization = serializedOnce === serializedTwice;
            const validation = first.map((_, index) => index);
            row.pass = exactObjectRoundtrip
                && mechanismRoundtrip
                && metadataRoundtrip
                && deterministicSerialization;
            row.exact_object_roundtrip = exactObjectRoundtrip;
            row.mechanism_roundtrip = mechanismRoundtrip;
            row.metadata_roundtrip = metadataRoundtrip;
            row.deterministic_serialization = deterministicSerialization;
            row.step_count = validation.length;
            row.warning_count = firstValidation.warnings.length;
            row.warnings = firstValidation.warnings;
            if (row.warning_count > 0) warningCases.push({
                character: row.character,
                filename: row.filename,
                path: row.path,
                warnings: row.warnings,
            });
            if (!row.pass) failures.push(row);
        } catch (error) {
            row.error = String(error?.stack || error);
            failures.push(row);
        }
        results.push(row);
        warnings.set(entry.character, (warnings.get(entry.character) || 0) + row.warning_count);
    }

    const output = {
        schema: "sf6cc.task-c.corpus-roundtrip.v1",
        corpus_snapshot: manifest.snapshot_id,
        target_game_build: manifest.target_game_build || "mixed_or_unknown",
        files: results.length,
        passed: results.length - failures.length,
        failed: failures.length,
        duration_ms: Date.now() - started,
        assertions: {
            parse_with_production_editor_core: true,
            repeated_roundtrip: "load -> save -> load -> save -> load",
            exact_object_roundtrip: true,
            frozen_mechanism_projection_preserved: true,
            metadata_model_preserved: true,
            serialization_deterministic: true,
        },
        warning_counts_by_character: Object.fromEntries([...warnings.entries()].sort()),
        warning_cases: warningCases,
        failures,
    };
    fs.mkdirSync(path.dirname(args["--output"]), { recursive: true });
    fs.writeFileSync(args["--output"], `${JSON.stringify(output, null, 2)}\n`);
    process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
    if (failures.length > 0) process.exitCode = 1;
}


main();
