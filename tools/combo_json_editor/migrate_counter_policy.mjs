#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import {
    normalizeCounterPolicyDocument,
    serializeComboJson
} from "./combo_json_core.mjs";

function parseArguments(argv) {
    const options = {
        root: "",
        report: "",
        write: false
    };
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--root") options.root = argv[++index] ?? "";
        else if (arg === "--report") options.report = argv[++index] ?? "";
        else if (arg === "--write") options.write = true;
        else if (arg === "--dry-run") options.write = false;
        else throw new Error(`未知参数 (unknown argument): ${arg}`);
    }
    if (!options.root) throw new Error("缺少 --root <CustomCombos目录>");
    return options;
}

function listJsonFiles(root) {
    const files = [];
    const visit = directory => {
        for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
            const fullPath = path.join(directory, entry.name);
            if (entry.isDirectory()) visit(fullPath);
            else if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) files.push(fullPath);
        }
    };
    visit(root);
    return files.sort((left, right) => left.localeCompare(right, "en"));
}

function countDistribution(target, value) {
    const key = String(value);
    target[key] = (target[key] ?? 0) + 1;
}

function inspectBefore(document) {
    const first = document[0] ?? {};
    const meta = first._xt_meta ?? {};
    const environment = meta.environment ?? {};
    return {
        environmentCounter: environment.dummy_counter_type,
        metaCounter: meta.dummy_counter_type,
        firstCounter: first.dummy_counter_type,
        summaryHitType: first.combo_stats?.hit_type,
        stepCounterCount: document.filter(step => step?.counter_type !== undefined).length,
        motionTaggedCount: document.filter(step => (
            /确反康|打康|PUNISH[\s_-]*COUNTER|COUNTER[\s_-]*HIT|\b(?:PC|CH)\b/i
                .test(String(step?.motion ?? ""))
        )).length,
        contactCount: document.filter(step => step?.has_contact === true).length
    };
}

function makeReport(root, write) {
    return {
        schema: "sf6cc.counter-policy-migration.v1",
        root,
        mode: write ? "write" : "dry-run",
        files: 0,
        changedFiles: 0,
        policyChanges: 0,
        ambiguousFiles: [],
        invalidFiles: [],
        sourceDistribution: {},
        targetDistribution: {},
        removedStepCounterFields: 0,
        strippedMotionTags: 0,
        addedContactMarkers: 0,
        changedRelativePaths: []
    };
}

function main() {
    const options = parseArguments(process.argv.slice(2));
    const root = path.resolve(options.root);
    if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
        throw new Error(`目录不存在 (directory not found): ${root}`);
    }

    const report = makeReport(root, options.write);
    const pending = [];
    for (const filePath of listJsonFiles(root)) {
        report.files += 1;
        const relativePath = path.relative(root, filePath);
        let document;
        try {
            document = JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
        } catch (error) {
            report.invalidFiles.push({ path: relativePath, error: error.message });
            continue;
        }

        const before = inspectBefore(document);
        let migrated;
        try {
            migrated = normalizeCounterPolicyDocument(document, {
                recoverLegacyZero: true
            });
        } catch (error) {
            report.invalidFiles.push({ path: relativePath, error: error.message });
            continue;
        }
        if (migrated.ambiguous) {
            report.ambiguousFiles.push({
                path: relativePath,
                evidence: migrated.evidence
            });
            continue;
        }

        const after = inspectBefore(migrated.document);
        const serialized = serializeComboJson(migrated.document);
        const originalSerialized = serializeComboJson(document);
        countDistribution(report.sourceDistribution, migrated.source);
        countDistribution(report.targetDistribution, migrated.counterType);
        report.removedStepCounterFields += before.stepCounterCount - after.stepCounterCount;
        report.strippedMotionTags += before.motionTaggedCount - after.motionTaggedCount;
        report.addedContactMarkers += Math.max(0, after.contactCount - before.contactCount);
        if (Number(before.environmentCounter) !== migrated.counterType) report.policyChanges += 1;
        if (serialized !== originalSerialized) {
            report.changedFiles += 1;
            report.changedRelativePaths.push(relativePath);
            pending.push({ filePath, serialized });
        }
    }

    if (report.invalidFiles.length > 0 || report.ambiguousFiles.length > 0) {
        report.status = "blocked";
    } else {
        report.status = "ready";
    }

    if (options.write) {
        if (report.status !== "ready") {
            throw new Error(
                `迁移被阻止：无效 ${report.invalidFiles.length}，歧义 ${report.ambiguousFiles.length}`
            );
        }
        for (const item of pending) fs.writeFileSync(item.filePath, item.serialized, "utf8");
        report.status = "written";
    }

    if (options.report) {
        const reportPath = path.resolve(options.report);
        fs.mkdirSync(path.dirname(reportPath), { recursive: true });
        fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
    }
    process.stdout.write(`${JSON.stringify({
        status: report.status,
        mode: report.mode,
        files: report.files,
        changedFiles: report.changedFiles,
        policyChanges: report.policyChanges,
        targetDistribution: report.targetDistribution,
        removedStepCounterFields: report.removedStepCounterFields,
        strippedMotionTags: report.strippedMotionTags,
        addedContactMarkers: report.addedContactMarkers,
        invalidFiles: report.invalidFiles.length,
        ambiguousFiles: report.ambiguousFiles.length,
        report: options.report ? path.resolve(options.report) : null
    }, null, 2)}\n`);
}

try {
    main();
} catch (error) {
    process.stderr.write(`${error.stack ?? error.message}\n`);
    process.exitCode = 1;
}
