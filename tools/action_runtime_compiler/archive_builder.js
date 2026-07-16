"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");
const compiler = require("./compiler_core.js");
const modernDisplay = require("./modern_display_core.js");

const AC_SUFFIX = "-fab-action-catalog-full-classic.json";
const BCM_SUFFIX = "-fab-bcm-full-classic.json";
const DEFAULT_OUTPUT_ROOT = path.join(__dirname, "html");

function ensureDirectory(directory) {
    fs.mkdirSync(directory, { recursive: true });
}

function sha256(bytes) {
    return crypto.createHash("sha256").update(bytes).digest("hex");
}

function readSource(filename) {
    const bytes = fs.readFileSync(filename);
    return {
        bytes,
        sha256: sha256(bytes),
        value: bcmCore.parseSourceText(bytes.toString("utf8"))
    };
}

function writeJson(filename, value) {
    ensureDirectory(path.dirname(filename));
    fs.writeFileSync(filename, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function writeJsonAtomic(filename, value) {
    ensureDirectory(path.dirname(filename));
    const temporary = `${filename}.${process.pid}.${Date.now()}.tmp`;
    try {
        fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, "utf8");
        fs.renameSync(temporary, filename);
    } finally {
        if (fs.existsSync(temporary)) fs.rmSync(temporary, { force: true });
    }
}

function copyFileAtomic(source, destination) {
    ensureDirectory(path.dirname(destination));
    const temporary = `${destination}.${process.pid}.${Date.now()}.tmp`;
    try {
        fs.copyFileSync(source, temporary);
        fs.renameSync(temporary, destination);
    } finally {
        if (fs.existsSync(temporary)) fs.rmSync(temporary, { force: true });
    }
}

function assertDirectory(directory) {
    const resolved = path.resolve(directory || "");
    if (!fs.existsSync(resolved) || !fs.statSync(resolved).isDirectory()) {
        throw new Error(`dump 目录不存在或不是目录: ${resolved}`);
    }
    return resolved;
}

function scanDumpDirectory(directory) {
    const resolved = assertDirectory(directory);
    const names = fs.readdirSync(resolved).filter(name => name.toLowerCase().endsWith(".json"));
    const nameSet = new Set(names);
    const stems = new Set();
    for (const name of names) {
        if (name.endsWith(AC_SUFFIX)) stems.add(name.slice(0, -AC_SUFFIX.length));
        if (name.endsWith(BCM_SUFFIX)) stems.add(name.slice(0, -BCM_SUFFIX.length));
    }
    const pairs = [];
    const incomplete = [];
    for (const stem of [...stems].sort((left, right) => left.localeCompare(right, "zh-CN"))) {
        const ac = `${stem}${AC_SUFFIX}`;
        const bcm = `${stem}${BCM_SUFFIX}`;
        const missing = [];
        if (!nameSet.has(ac)) missing.push("AC");
        if (!nameSet.has(bcm)) missing.push("BCM");
        const entry = { stem, ac, bcm, missing };
        if (missing.length) incomplete.push(entry);
        else {
            const acStat = fs.statSync(path.join(resolved, ac));
            const bcmStat = fs.statSync(path.join(resolved, bcm));
            pairs.push({ ...entry, total_bytes: acStat.size + bcmStat.size });
        }
    }
    return { directory: resolved, pairs, incomplete };
}

function mapDiff(before, after) {
    before = before || {};
    after = after || {};
    const added = [], removed = [], changed = [];
    const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])]
        .sort((left, right) => Number(left) - Number(right));
    for (const key of keys) {
        const hasBefore = Object.prototype.hasOwnProperty.call(before, key);
        const hasAfter = Object.prototype.hasOwnProperty.call(after, key);
        if (!hasBefore) added.push({ action_id: Number(key), value: after[key] });
        else if (!hasAfter) removed.push({ action_id: Number(key), value: before[key] });
        else if (JSON.stringify(before[key]) !== JSON.stringify(after[key])) {
            changed.push({ action_id: Number(key), before: before[key], after: after[key] });
        }
    }
    return { added, removed, changed };
}

function setDiff(before, after) {
    const beforeSet = new Set((before || []).map(Number));
    const afterSet = new Set((after || []).map(Number));
    return {
        added: [...afterSet].filter(value => !beforeSet.has(value)).sort((a, b) => a - b),
        removed: [...beforeSet].filter(value => !afterSet.has(value)).sort((a, b) => a - b)
    };
}

function stringSetDiff(before, after) {
    const beforeSet = new Set(before || []);
    const afterSet = new Set(after || []);
    return {
        added: [...afterSet].filter(value => !beforeSet.has(value)).sort(),
        removed: [...beforeSet].filter(value => !afterSet.has(value)).sort()
    };
}

function systemActionMap(runtime) {
    const result = {};
    for (const [id, rule] of Object.entries(runtime && runtime.validation && runtime.validation.rules || {})) {
        if (rule && rule.system_action) result[id] = rule.system_action;
    }
    return result;
}

function diagnosticCodes(report) {
    return [...new Set((report && report.diagnostics || []).map(item => `${item.severity}:${item.code}`))].sort();
}

function diffRuntimes(previousRuntime, currentRuntime, previousReport, currentReport, metadata) {
    const baseline = !previousRuntime;
    const previousSources = previousRuntime && previousRuntime.sources || {};
    const currentSources = currentRuntime.sources || {};
    const actionIds = setDiff(previousRuntime && previousRuntime.action_ids, currentRuntime.action_ids);
    const actions = mapDiff(previousRuntime && previousRuntime.actions, currentRuntime.actions);
    const aliases = mapDiff(previousRuntime && previousRuntime.aliases, currentRuntime.aliases);
    const validation = mapDiff(
        previousRuntime && previousRuntime.validation && previousRuntime.validation.rules,
        currentRuntime.validation && currentRuntime.validation.rules);
    const systemActions = mapDiff(systemActionMap(previousRuntime), systemActionMap(currentRuntime));
    const targetCombos = setDiff(
        previousRuntime && previousRuntime.evidence && previousRuntime.evidence.target_combo_followup_action_ids,
        currentRuntime.evidence && currentRuntime.evidence.target_combo_followup_action_ids);
    const diagnostics = stringSetDiff(diagnosticCodes(previousReport), diagnosticCodes(currentReport));
    const summary = {
        ac_source_changed: !baseline && previousSources.ac_sha256 !== currentSources.ac_sha256,
        bcm_source_changed: !baseline && previousSources.bcm_sha256 !== currentSources.bcm_sha256,
        action_ids_added: actionIds.added.length,
        action_ids_removed: actionIds.removed.length,
        displays_added: actions.added.length,
        displays_removed: actions.removed.length,
        displays_changed: actions.changed.length,
        aliases_added: aliases.added.length,
        aliases_removed: aliases.removed.length,
        aliases_changed: aliases.changed.length,
        validation_added: validation.added.length,
        validation_removed: validation.removed.length,
        validation_changed: validation.changed.length,
        system_actions_changed: systemActions.added.length + systemActions.removed.length + systemActions.changed.length,
        target_combos_added: targetCombos.added.length,
        target_combos_removed: targetCombos.removed.length,
        diagnostic_codes_added: diagnostics.added.length,
        diagnostic_codes_removed: diagnostics.removed.length
    };
    return {
        schema: "sf6cc.action-runtime-version-diff.v1",
        character: currentRuntime.character,
        baseline,
        previous_version: metadata && metadata.previousVersion || null,
        comparison_mode: metadata && metadata.previousState || (baseline ? "baseline" : "archived-version"),
        current_version: metadata && metadata.currentVersion || null,
        source_hashes: {
            previous: previousRuntime && previousRuntime.sources || null,
            current: currentRuntime.sources || null
        },
        has_changes: !baseline && Object.values(summary).some(value => value === true || Number(value) > 0),
        summary,
        details: {
            action_ids: actionIds,
            displays: actions,
            aliases,
            validation,
            system_actions: systemActions,
            target_combo_followups: targetCombos,
            diagnostic_codes: diagnostics
        }
    };
}

function readJsonIfExists(filename) {
    if (!filename || !fs.existsSync(filename)) return null;
    return JSON.parse(fs.readFileSync(filename, "utf8").replace(/^\uFEFF/, ""));
}

function resolveWithin(directory, filename) {
    const root = path.resolve(directory);
    const resolved = path.resolve(root, filename);
    if (!resolved.startsWith(`${root}${path.sep}`)) throw new Error(`归档清单包含越界路径: ${filename}`);
    return resolved;
}

function listVersionManifests(outputRoot) {
    const charRoot = path.join(outputRoot, "char");
    if (!fs.existsSync(charRoot)) return [];
    const manifests = [];
    for (const version of fs.readdirSync(charRoot)) {
        const filename = path.join(charRoot, version, "manifest.json");
        try {
            const manifest = readJsonIfExists(filename);
            if (manifest) manifests.push({ version, filename, manifest });
        } catch (_error) {
            // A broken historical manifest is ignored here and remains visible on disk for manual inspection.
        }
    }
    return manifests.sort((left, right) =>
        String(right.manifest.updated_at || right.manifest.created_at || "")
            .localeCompare(String(left.manifest.updated_at || left.manifest.created_at || "")));
}

function findPrevious(outputRoot, character, requestedVersion, currentVersion) {
    const all = listVersionManifests(outputRoot);
    const manifests = requestedVersion
        ? all.filter(item => item.version === requestedVersion)
        : [
            ...all.filter(item => item.version === currentVersion),
            ...all.filter(item => item.version !== currentVersion)
        ];
    for (const item of manifests) {
        const entry = (item.manifest.characters || []).find(candidate => candidate.character === character);
        if (!entry) continue;
        const versionRoot = path.join(outputRoot, "char", item.version);
        const runtimeFile = resolveWithin(versionRoot, entry.runtime_file || `${character}.json`);
        const reportFile = resolveWithin(versionRoot, entry.report_file || `${character}.report.json`);
        const modernDisplayFile = resolveWithin(
            versionRoot, entry.modern_display_file || `${character}.modern-display.json`);
        const runtime = readJsonIfExists(runtimeFile);
        if (runtime) return {
            version: item.version,
            same_version: item.version === currentVersion,
            runtime,
            report: readJsonIfExists(reportFile),
            modern_display: readJsonIfExists(modernDisplayFile)
        };
    }
    return null;
}

function loadExceptions(character) {
    const filename = path.resolve(__dirname, "..", "..", "data", "TrainingComboTrials_data", "exceptions", `${character}.json`);
    return { filename, value: readJsonIfExists(filename) || {} };
}

function loadModernDisplaySupplement(character) {
    const filename = path.resolve(__dirname, "..", "..", "data", "TrainingComboTrials_data", "modern_display", `${character}.json`);
    return { filename, value: readJsonIfExists(filename) || {} };
}

function validateVersion(version) {
    const reserved = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i;
    if (typeof version !== "string" || version.length > 80
        || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(version) || reserved.test(version)) {
        throw new Error("版本必须以字母或数字开头，只能包含字母、数字、点、下划线和连字符，且不能使用 Windows 保留名。");
    }
    return version;
}

function validateCharacterFilename(character) {
    if (typeof character !== "string" || !/^[A-Za-z0-9_]+$/.test(character)) {
        throw new Error(`角色规范名不能作为安全文件名: ${character}`);
    }
    return character;
}

function ensureStorage(outputRoot) {
    for (const name of ["acbcm", "char", "latest", "latest_exceptions", "latest_modern"]) ensureDirectory(path.join(outputRoot, name));
}

function mergeEntries(existing, updates, keyOf, compare) {
    const updateKeys = new Set(updates.map(keyOf));
    return [
        ...(existing || []).filter(item => !updateKeys.has(keyOf(item))),
        ...updates
    ].sort(compare);
}

function buildArchive(options) {
    options = options || {};
    const outputRoot = path.resolve(options.outputRoot || DEFAULT_OUTPUT_ROOT);
    const version = validateVersion(options.version);
    const scan = scanDumpDirectory(options.dumpDirectory);
    ensureStorage(outputRoot);
    const rawFinal = path.join(outputRoot, "acbcm", version);
    const charFinal = path.join(outputRoot, "char", version);
    const rawExists = fs.existsSync(rawFinal);
    const charExists = fs.existsSync(charFinal);
    if (rawExists !== charExists) {
        throw new Error(`版本 ${version} 的 acbcm/char 归档不完整，请先人工检查后再构建。`);
    }
    const mergeExistingVersion = rawExists && charExists;
    const existingRawManifest = mergeExistingVersion
        ? readJsonIfExists(path.join(rawFinal, "manifest.json")) : null;
    const existingCharacterManifest = mergeExistingVersion
        ? readJsonIfExists(path.join(charFinal, "manifest.json")) : null;
    const existingDifferenceBundle = mergeExistingVersion
        ? readJsonIfExists(path.join(charFinal, "differences.json")) : null;
    if (mergeExistingVersion && (!existingRawManifest || !existingCharacterManifest)) {
        throw new Error(`版本 ${version} 缺少归档清单，请先人工检查后再覆盖。`);
    }
    const selected = options.stems && options.stems.length
        ? new Set(options.stems) : new Set(scan.pairs.map(pair => pair.stem));
    const pairs = scan.pairs.filter(pair => selected.has(pair.stem));
    const unknown = [...selected].filter(stem => !pairs.some(pair => pair.stem === stem));
    if (unknown.length) throw new Error(`未找到完整 AC+BCM 配对: ${unknown.join(", ")}`);
    if (!pairs.length) throw new Error("没有选中任何完整 AC+BCM 配对。");

    const updatedAt = new Date().toISOString();
    const createdAt = existingCharacterManifest && existingCharacterManifest.created_at
        || existingRawManifest && existingRawManifest.created_at || updatedAt;
    const stagingRoot = path.join(outputRoot, `.staging-${process.pid}-${Date.now()}`);
    const rawStage = path.join(stagingRoot, "acbcm");
    const charStage = path.join(stagingRoot, "char");
    if (!mergeExistingVersion) {
        ensureDirectory(rawStage);
        ensureDirectory(charStage);
    }
    const rawEntries = [], characterEntries = [], differences = [];
    const pendingWrites = [];
    const seenCharacters = new Set();

    try {
        for (const pair of pairs) {
            const acPath = path.join(scan.directory, pair.ac);
            const bcmPath = path.join(scan.directory, pair.bcm);
            const ac = readSource(acPath);
            const bcm = readSource(bcmPath);
            const fighterId = Number(ac.value.fighter_id ?? -1);
            const resolvedCharacter = validateCharacterFilename(
                bcmCore.FIGHTER_NAMES[fighterId] || ac.value.character || pair.stem);
            if (seenCharacters.has(resolvedCharacter)) {
                throw new Error(`多个输入配对解析为同一角色 ${resolvedCharacter}，已停止以避免覆盖。`);
            }
            seenCharacters.add(resolvedCharacter);
            const exceptionSource = loadExceptions(resolvedCharacter);
            const type13Compatibility = compiler.propagateType13SiblingCompatibility(
                ac.value, exceptionSource.value);
            const modernSupplement = loadModernDisplaySupplement(resolvedCharacter);
            const compileOptions = {
                actionSourceSha256: ac.sha256,
                bcmSourceSha256: bcm.sha256,
                characterName: resolvedCharacter
            };
            // Always compile the v2 runtime from AC+BCM alone. The existing
            // legacy table is then audited and reduced to the smallest
            // compatibility overlay needed to avoid detection regressions.
            const bcmCatalog = bcmCore.buildCatalog(bcm.value, {
                characterName: resolvedCharacter,
                sourceSha256: bcm.sha256,
                generatedAt: updatedAt
            });
            const result = compiler.compileFromCatalog(ac.value, bcmCatalog, {}, compileOptions);
            const generatedModernDisplay = modernDisplay.buildModernDisplay(
                ac.value, bcmCatalog, result.runtime, modernSupplement.value,
                { ...compileOptions, generatedAt: updatedAt });
            const pureGeneratedExceptions = compiler.buildLegacyExceptionTable(result.runtime);
            const compatibilityBefore = compiler.buildLegacyCompatibility(
                type13Compatibility.table, pureGeneratedExceptions, result.runtime.action_ids);
            const generatedExceptions = compiler.applyLegacyCompatibilityOverlay(
                pureGeneratedExceptions, compatibilityBefore.overlay);
            const compatibilityAfter = compiler.buildLegacyCompatibility(
                type13Compatibility.table, generatedExceptions, result.runtime.action_ids);
            const compatibility = {
                schema: "sf6cc.legacy-exception-compatibility.v1",
                character: result.runtime.character,
                reference_file: exceptionSource.filename,
                ac_type13_sibling_propagation: type13Compatibility.propagated,
                pure_ac_bcm: compatibilityBefore,
                final_output: compatibilityAfter,
                fallback_overlay: compatibilityBefore.overlay
            };
            result.report.compatibility = compatibility;
            result.runtime.coverage.compatibility_fallback_entry_count =
                compatibilityBefore.summary.fallback_entry_count;
            result.report.summary.compatibility_fallback_entry_count =
                compatibilityBefore.summary.fallback_entry_count;
            if (compatibilityBefore.summary.fallback_entry_count) result.report.diagnostics.push({
                severity: "info",
                code: "LEGACY_COMPATIBILITY_FALLBACK_APPLIED",
                entry_count: compatibilityBefore.summary.fallback_entry_count
            });
            if (compatibilityBefore.summary.stale_reference_action_count) result.report.diagnostics.push({
                severity: "info",
                code: "STALE_LEGACY_REFERENCE_ACTIONS",
                action_ids: compatibilityBefore.stale_reference_action_ids
            });
            if (compatibilityAfter.summary.fallback_entry_count) {
                result.report.diagnostics.push({
                    severity: "error",
                    code: "LEGACY_COMPATIBILITY_REGRESSION",
                    entry_count: compatibilityAfter.summary.fallback_entry_count
                });
                result.report.status = "invalid";
            }
            const previous = findPrevious(
                outputRoot, result.runtime.character, options.compareVersion || null, version);
            const difference = diffRuntimes(
                previous && previous.runtime, result.runtime,
                previous && previous.report, result.report,
                {
                    previousVersion: previous && previous.version,
                    previousState: previous && previous.same_version
                        ? "same-version-before-overwrite" : "archived-version",
                    currentVersion: version
                });
            const modernBefore = previous && previous.modern_display || {};
            const modernAfter = generatedModernDisplay;
            const modernDiff = mapDiff(
                Object.fromEntries(Object.entries(modernBefore).filter(([key]) => /^\d+$/.test(key))),
                Object.fromEntries(Object.entries(modernAfter).filter(([key]) => /^\d+$/.test(key))));
            difference.summary.modern_displays_added = modernDiff.added.length;
            difference.summary.modern_displays_removed = modernDiff.removed.length;
            difference.summary.modern_displays_changed = modernDiff.changed.length;
            difference.details.modern_displays = modernDiff;
            difference.has_changes = !difference.baseline && Object.values(difference.summary)
                .some(value => value === true || Number(value) > 0);

            pendingWrites.push({
                pair, acPath, bcmPath, runtime: result.runtime, report: result.report,
                generatedExceptions, generatedModernDisplay, compatibility, difference
            });
            differences.push(difference);
            rawEntries.push({
                stem: pair.stem,
                character: result.runtime.character,
                fighter_id: result.runtime.fighter_id,
                ac_file: pair.ac,
                bcm_file: pair.bcm,
                ac_sha256: ac.sha256,
                bcm_sha256: bcm.sha256,
                source_directory: scan.directory
            });
            characterEntries.push({
                stem: pair.stem,
                character: result.runtime.character,
                fighter_id: result.runtime.fighter_id,
                status: result.report.status,
                runtime_file: `${result.runtime.character}.json`,
                generated_exception_file: `${result.runtime.character}.exceptions.json`,
                modern_display_file: `${result.runtime.character}.modern-display.json`,
                compatibility_file: `${result.runtime.character}.compatibility.json`,
                report_file: `${result.runtime.character}.report.json`,
                diff_file: `${result.runtime.character}.diff.json`,
                compare_version: previous && previous.version || null,
                comparison_mode: previous && previous.same_version
                    ? "same-version-before-overwrite" : (previous ? "archived-version" : "baseline"),
                latest_updated: result.report.status === "valid",
                exception_file: exceptionSource.filename,
                coverage: result.runtime.coverage,
                compatibility: compatibilityBefore.summary,
                modern_display_action_count: Object.keys(generatedModernDisplay).filter(key => /^\d+$/.test(key)).length,
                difference: difference.summary
            });
        }

        const mergedRawEntries = mergeEntries(
            existingRawManifest && existingRawManifest.sources, rawEntries,
            item => item.stem,
            (left, right) => String(left.stem).localeCompare(String(right.stem), "zh-CN"));
        const mergedCharacterEntries = mergeEntries(
            existingCharacterManifest && existingCharacterManifest.characters, characterEntries,
            item => item.character,
            (left, right) => Number(left.fighter_id) - Number(right.fighter_id));
        const mergedDifferences = mergeEntries(
            existingDifferenceBundle && existingDifferenceBundle.differences, differences,
            item => item.character,
            (left, right) => String(left.character).localeCompare(String(right.character)));
        const common = {
            version,
            created_at: createdAt,
            updated_at: updatedAt,
            dump_directory: scan.directory
        };
        const rawManifest = {
            schema: "sf6cc.acbcm-archive-manifest.v1", ...common, sources: mergedRawEntries
        };
        const characterManifest = {
            schema: "sf6cc.action-runtime-archive-manifest.v1",
            ...common,
            compiler_rules_version: compiler.RULES_VERSION,
            use_exceptions: options.useExceptions === true,
            compare_version: options.compareVersion || null,
            characters: mergedCharacterEntries
        };
        const differenceBundle = {
            schema: "sf6cc.action-runtime-version-diff-bundle.v1",
            version,
            created_at: createdAt,
            updated_at: updatedAt,
            differences: mergedDifferences
        };

        const rawTarget = mergeExistingVersion ? rawFinal : rawStage;
        const charTarget = mergeExistingVersion ? charFinal : charStage;
        for (const pending of pendingWrites) {
            const copy = mergeExistingVersion ? copyFileAtomic : fs.copyFileSync;
            copy(pending.acPath, path.join(rawTarget, pending.pair.ac));
            copy(pending.bcmPath, path.join(rawTarget, pending.pair.bcm));
            const write = mergeExistingVersion ? writeJsonAtomic : writeJson;
            write(path.join(charTarget, `${pending.runtime.character}.json`), pending.runtime);
            write(path.join(charTarget, `${pending.runtime.character}.exceptions.json`), pending.generatedExceptions);
            write(path.join(charTarget, `${pending.runtime.character}.modern-display.json`), pending.generatedModernDisplay);
            write(path.join(charTarget, `${pending.runtime.character}.compatibility.json`), pending.compatibility);
            write(path.join(charTarget, `${pending.runtime.character}.report.json`), pending.report);
            write(path.join(charTarget, `${pending.runtime.character}.diff.json`), pending.difference);
        }
        const writeManifest = mergeExistingVersion ? writeJsonAtomic : writeJson;
        writeManifest(path.join(rawTarget, "manifest.json"), rawManifest);
        writeManifest(path.join(charTarget, "manifest.json"), characterManifest);
        writeManifest(path.join(charTarget, "differences.json"), differenceBundle);

        if (!mergeExistingVersion) {
            let rawMoved = false;
            try {
                fs.renameSync(rawStage, rawFinal);
                rawMoved = true;
                fs.renameSync(charStage, charFinal);
            } catch (error) {
                if (rawMoved && fs.existsSync(rawFinal) && !fs.existsSync(charFinal)) {
                    fs.rmSync(rawFinal, { recursive: true, force: true });
                }
                throw error;
            }
        }
        const latestRoot = path.join(outputRoot, "latest");
        const latestExceptionsRoot = path.join(outputRoot, "latest_exceptions");
        const latestModernRoot = path.join(outputRoot, "latest_modern");
        for (const pending of pendingWrites.filter(item => item.report.status === "valid")) {
            writeJsonAtomic(path.join(latestRoot, `${pending.runtime.character}.json`), pending.runtime);
            writeJsonAtomic(path.join(latestExceptionsRoot, `${pending.runtime.character}.json`), pending.generatedExceptions);
            writeJsonAtomic(path.join(latestModernRoot, `${pending.runtime.character}.json`), pending.generatedModernDisplay);
        }
        const latestManifestPath = path.join(outputRoot, "latest-manifest.json");
        const latestManifest = readJsonIfExists(latestManifestPath) || {
            schema: "sf6cc.action-runtime-latest-manifest.v1", characters: {}
        };
        latestManifest.updated_at = updatedAt;
        for (const entry of characterEntries.filter(item => item.latest_updated)) {
            latestManifest.characters[entry.character] = {
                version,
                fighter_id: entry.fighter_id,
                runtime_file: entry.runtime_file,
                modern_display_file: entry.modern_display_file,
                status: entry.status
            };
        }
        writeJsonAtomic(latestManifestPath, latestManifest);
        return {
            version,
            created_at: createdAt,
            updated_at: updatedAt,
            archive_mode: mergeExistingVersion ? "merged" : "created",
            output_root: outputRoot,
            raw_archive: rawFinal,
            character_archive: charFinal,
            latest: latestRoot,
            latest_exceptions: latestExceptionsRoot,
            latest_modern: latestModernRoot,
            characters: characterEntries,
            differences
        };
    } finally {
        if (fs.existsSync(stagingRoot)) fs.rmSync(stagingRoot, { recursive: true, force: true });
    }
}

module.exports = {
    AC_SUFFIX,
    BCM_SUFFIX,
    DEFAULT_OUTPUT_ROOT,
    scanDumpDirectory,
    diffRuntimes,
    listVersionManifests,
    ensureStorage,
    buildArchive
};
