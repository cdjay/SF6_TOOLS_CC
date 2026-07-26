import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import {
    COMBO_JSON_EDITOR,
    mechanismProjection,
    migrateComboDocument,
    parseComboJson,
    serializeComboJson,
    validateComboDocument
} from "./combo_json_core.mjs";

function parseArgs(argv) {
    const options = {
        inPlace: false,
        expectedCount: null,
        root: null,
        backupDir: null,
        report: null,
        timestamp: new Date().toISOString(),
        versionProfile: {}
    };
    for (let index = 0; index < argv.length; index += 1) {
        const arg = argv[index];
        if (arg === "--in-place") options.inPlace = true;
        else if (arg === "--root") options.root = argv[++index];
        else if (arg === "--backup-dir") options.backupDir = argv[++index];
        else if (arg === "--report") options.report = argv[++index];
        else if (arg === "--timestamp") options.timestamp = argv[++index];
        else if (arg === "--expected-count") options.expectedCount = Number(argv[++index]);
        else if (arg === "--game-id") options.versionProfile.gameId = argv[++index];
        else if (arg === "--game-version") options.versionProfile.gameVersion = argv[++index];
        else if (arg === "--recorder-id") options.versionProfile.recorderId = argv[++index];
        else if (arg === "--recorder-version") options.versionProfile.recorderVersion = argv[++index];
        else if (arg === "--framework-id") options.versionProfile.frameworkId = argv[++index];
        else if (arg === "--framework-version") options.versionProfile.frameworkVersion = argv[++index];
        else if (arg === "--language") {
            options.metadataProfile = options.metadataProfile || {};
            options.metadataProfile.language = argv[++index];
        }
        else if (arg === "--control-mode") {
            options.metadataProfile = options.metadataProfile || {};
            options.metadataProfile.controlMode = argv[++index];
        }
        else if (arg === "--help" || arg === "-h") options.help = true;
        else throw new Error(`未知参数：${arg}`);
    }
    return options;
}

function usage() {
    return [
        "用法：",
        "  node tools/combo_json_editor/batch_migrate.mjs --root <目录>",
        "  node tools/combo_json_editor/batch_migrate.mjs --root <目录> --in-place",
        "       --backup-dir <备份目录> --report <报告.json> [--expected-count 996]",
        "       --game-version <版本> --recorder-id <ID> --recorder-version <版本>",
        "       --framework-id <ID> --framework-version <版本>",
        "       [--language zh-CN] [--control-mode classic|modern|unknown]",
        "",
        "默认只预检。--in-place 必须同时提供仓库外备份目录和报告路径。"
    ].join("\n");
}

function listJsonFiles(root) {
    const out = [];
    function walk(current) {
        for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
            const fullPath = path.join(current, entry.name);
            if (entry.isDirectory()) walk(fullPath);
            else if (entry.isFile() && entry.name.toLowerCase().endsWith(".json")) out.push(fullPath);
        }
    }
    walk(root);
    return out.sort((left, right) => left.localeCompare(right, "en"));
}

function sha256(value) {
    return crypto.createHash("sha256").update(value).digest("hex");
}

function stableJson(value) {
    if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
    if (value && typeof value === "object") {
        return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
    }
    return JSON.stringify(value);
}

function ensureOutsideRoot(root, target, label) {
    const relative = path.relative(root, target);
    if (relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative))) {
        throw new Error(`${label} 不能位于待迁移目录内部：${target}`);
    }
}

function prepare(root, files, timestamp, versionProfile, metadataProfile) {
    return files.map(filePath => {
        const relativePath = path.relative(root, filePath);
        const beforeText = fs.readFileSync(filePath, "utf8");
        const before = parseComboJson(beforeText, relativePath);
        const migration = migrateComboDocument(before, {
            relativePath,
            timestamp,
            versionProfile,
            metadataProfile
        });
        const afterText = serializeComboJson(migration.document);
        const mechanismBefore = stableJson(mechanismProjection(before));
        const mechanismAfter = stableJson(mechanismProjection(migration.document));
        if (mechanismBefore !== mechanismAfter) {
            throw new Error(`${relativePath}: 迁移触碰了机制字段`);
        }
        return {
            filePath,
            relativePath,
            beforeText,
            afterText,
            sourceSchema: migration.sourceSchema,
            targetSchema: migration.targetSchema,
            changes: migration.changes,
            warnings: migration.warnings,
            beforeSha256: sha256(beforeText),
            afterSha256: sha256(afterText),
            mechanismSha256: sha256(mechanismBefore),
            stepCount: before.length
        };
    });
}

function copyBackups(items, backupDir) {
    for (const item of items) {
        const target = path.join(backupDir, item.relativePath);
        fs.mkdirSync(path.dirname(target), { recursive: true });
        fs.writeFileSync(target, item.beforeText, "utf8");
    }
}

function restoreBackups(items) {
    for (const item of items) fs.writeFileSync(item.filePath, item.beforeText, "utf8");
}

function buildReport(root, backupDir, timestamp, versionProfile, metadataProfile, items, mode) {
    const sourceSchemas = {};
    let warningCount = 0;
    for (const item of items) {
        const key = String(item.sourceSchema);
        sourceSchemas[key] = (sourceSchemas[key] || 0) + 1;
        warningCount += item.warnings.length;
    }
    return {
        schema: "sf6cc.combo_json_migration_report.v1",
        tool: { id: COMBO_JSON_EDITOR.id, version: COMBO_JSON_EDITOR.version },
        timestamp,
        mode,
        root,
        backup_dir: backupDir || null,
        target: {
            meta_schema: COMBO_JSON_EDITOR.metaSchema,
            json_id: COMBO_JSON_EDITOR.jsonId,
            json_version: COMBO_JSON_EDITOR.jsonVersion,
            versions: versionProfile,
            metadata: metadataProfile || {}
        },
        counts: {
            files: items.length,
            steps: items.reduce((sum, item) => sum + item.stepCount, 0),
            warnings: warningCount,
            source_schemas: sourceSchemas
        },
        invariants: {
            all_json_valid: true,
            mechanism_fields_unchanged: true,
            file_count_unchanged: true,
            step_count_unchanged: true
        },
        files: items.map(item => ({
            path: item.relativePath.replace(/\\/g, "/"),
            source_schema: item.sourceSchema,
            target_schema: item.targetSchema,
            steps: item.stepCount,
            before_sha256: item.beforeSha256,
            after_sha256: item.afterSha256,
            mechanism_sha256: item.mechanismSha256,
            changed_paths: item.changes,
            warnings: item.warnings
        }))
    };
}

function main() {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
        console.log(usage());
        return;
    }
    if (!options.root) throw new Error("缺少 --root");

    const root = path.resolve(options.root);
    if (!fs.statSync(root).isDirectory()) throw new Error(`不是目录：${root}`);
    const files = listJsonFiles(root);
    if (options.expectedCount !== null && files.length !== options.expectedCount) {
        throw new Error(`文件数不符：期望 ${options.expectedCount}，实际 ${files.length}`);
    }
    if (files.length === 0) throw new Error("没有找到 JSON 文件");

    const items = prepare(root, files, options.timestamp, options.versionProfile, options.metadataProfile);
    const report = buildReport(
        root,
        options.backupDir ? path.resolve(options.backupDir) : null,
        options.timestamp,
        options.versionProfile,
        options.metadataProfile,
        items,
        options.inPlace ? "in_place" : "dry_run"
    );

    if (!options.inPlace) {
        console.log(JSON.stringify(report.counts, null, 2));
        console.log("预检完成；未写入文件。");
        return;
    }

    if (!options.backupDir || !options.report) {
        throw new Error("--in-place 必须提供 --backup-dir 和 --report");
    }
    const backupDir = path.resolve(options.backupDir);
    const reportPath = path.resolve(options.report);
    ensureOutsideRoot(root, backupDir, "备份目录");
    ensureOutsideRoot(root, reportPath, "报告路径");
    if (fs.existsSync(backupDir)) throw new Error(`备份目录已存在：${backupDir}`);
    if (fs.existsSync(reportPath)) throw new Error(`报告已存在：${reportPath}`);

    fs.mkdirSync(backupDir, { recursive: true });
    copyBackups(items, backupDir);
    try {
        for (const item of items) fs.writeFileSync(item.filePath, item.afterText, "utf8");

        const postFiles = listJsonFiles(root);
        if (postFiles.length !== files.length) throw new Error("写入后文件数量发生变化");
        for (const item of items) {
            const afterText = fs.readFileSync(item.filePath, "utf8");
            const after = parseComboJson(afterText, item.relativePath);
            const validation = validateComboDocument(after);
            if (!validation.valid) throw new Error(`${item.relativePath}: 写入后校验失败`);
            if (sha256(afterText) !== item.afterSha256) throw new Error(`${item.relativePath}: 写入后哈希不符`);
            const postMechanism = sha256(stableJson(mechanismProjection(after)));
            if (postMechanism !== item.mechanismSha256) throw new Error(`${item.relativePath}: 机制字段发生变化`);
        }
    } catch (error) {
        restoreBackups(items);
        throw new Error(`迁移失败，已从事务备份恢复：${error.message}`);
    }

    fs.mkdirSync(path.dirname(reportPath), { recursive: true });
    fs.writeFileSync(reportPath, serializeComboJson(report), "utf8");
    console.log(JSON.stringify(report.counts, null, 2));
    console.log(`原地迁移完成：${root}`);
    console.log(`事务备份：${backupDir}`);
    console.log(`迁移报告：${reportPath}`);
}

try {
    main();
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
