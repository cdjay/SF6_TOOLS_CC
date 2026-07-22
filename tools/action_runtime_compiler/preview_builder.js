"use strict";

const fs = require("fs");
const path = require("path");
const archive = require("./archive_builder.js");
const bcmCore = require("../bcm_catalog_builder/bcm_catalog_core.js");

const OFFICIAL_ROOT = path.resolve(__dirname, "../modern_display_builder/out");

function readJson(filename) {
    return bcmCore.parseSourceText(fs.readFileSync(filename, "utf8"));
}

function resolveChild(root, name) {
    const base = path.resolve(root);
    const target = path.resolve(base, name);
    if (target !== base && !target.startsWith(`${base}${path.sep}`)) throw new Error("路径超出归档目录。");
    return target;
}

function validateName(value, label) {
    if (typeof value !== "string" || !value || !/^[A-Za-z0-9_.-]+$/.test(value)) {
        throw new Error(`${label}不是安全的目录或文件名: ${value}`);
    }
    return value;
}

function loadManifest(outputRoot, version) {
    validateName(version, "版本");
    const directory = resolveChild(path.join(outputRoot, "acbcm"), version);
    const filename = resolveChild(directory, "manifest.json");
    if (!fs.existsSync(filename)) throw new Error(`版本归档不存在: ${version}`);
    const manifest = readJson(filename);
    if (manifest.version !== version || !Array.isArray(manifest.sources)) throw new Error(`版本清单损坏: ${filename}`);
    return { directory, filename, manifest };
}

function officialFile(character, officialRoot = OFFICIAL_ROOT) {
    validateName(character, "角色名");
    const filename = resolveChild(officialRoot, `${character}.official.generated.json`);
    return fs.existsSync(filename) ? filename : null;
}

function archivedOfficialFile(outputRoot, version, character) {
    const root = resolveChild(path.join(outputRoot, "off"), version);
    const filename = resolveChild(root, `${character}.official.generated.json`);
    return fs.existsSync(filename) ? filename : null;
}

function archivedOfficialRawFile(outputRoot, version, character) {
    const root = resolveChild(path.join(outputRoot, "off"), version);
    const filename = resolveChild(root, `${character}.official.raw.json`);
    return fs.existsSync(filename) ? filename : null;
}

function generatedCommandFile(outputRoot, version, character) {
    const root = resolveChild(path.join(outputRoot, "char"), version);
    const filename = resolveChild(root, `${character}.command-display.json`);
    return fs.existsSync(filename) ? filename : null;
}

function buildPreviewIndex(outputRoot, version, options = {}) {
    const loaded = loadManifest(outputRoot, version);
    const characters = loaded.manifest.sources.map(source => {
        const character = validateName(source.character, "角色名");
        return {
            stem: source.stem,
            character,
            fighter_id: source.fighter_id,
            ac_file: source.ac_file,
            bcm_file: source.bcm_file,
            official_file: (archivedOfficialFile(outputRoot, version, character)
                || officialFile(character, options.officialRoot)) && `${character}.official.generated.json`,
            command_file: generatedCommandFile(outputRoot, version, character) && `${character}.command-display.json`
        };
    }).sort((left, right) => left.character.localeCompare(right.character, "en"));
    return {
        version,
        created_at: loaded.manifest.created_at || null,
        updated_at: loaded.manifest.updated_at || null,
        raw_directory: loaded.directory,
        character_directory: resolveChild(path.join(outputRoot, "char"), version),
        official_directory: fs.existsSync(resolveChild(path.join(outputRoot, "off"), version))
            ? resolveChild(path.join(outputRoot, "off"), version)
            : path.resolve(options.officialRoot || OFFICIAL_ROOT),
        characters
    };
}

function scalarValue(value) {
    if (!value || typeof value !== "object") return value ?? null;
    if (Object.prototype.hasOwnProperty.call(value, "value")) return value.value;
    if (value.kind === "ref") return { ref: value.object_id };
    if (Array.isArray(value.values)) return value.values;
    return value.kind || null;
}

function fieldMap(object, objectMap) {
    const result = {};
    for (const field of object && object.fields || []) {
        const value = scalarValue(field.value);
        if (value && typeof value === "object" && Object.prototype.hasOwnProperty.call(value, "ref")) {
            value.type = objectMap.get(value.ref)?.object_type || null;
        }
        result[field.name] = value;
    }
    return result;
}

function buildAcRows(source) {
    const objectMap = new Map((source.objects || []).map(object => [object.object_id, object]));
    return (source.records || []).map(record => {
        const objectId = record.action_ref && record.action_ref.object_id;
        const action = objectMap.get(objectId);
        const fields = fieldMap(action, objectMap);
        const frameRef = fields.ActionFrame && fields.ActionFrame.ref;
        const frameFields = fieldMap(objectMap.get(frameRef), objectMap);
        const references = Object.entries(fields)
            .filter(([, value]) => value && typeof value === "object" && value.ref)
            .map(([name, value]) => `${name} -> ${value.type || "object"} #${value.ref}`);
        return {
            action_id: Number(record.native_action_id),
            source_scope: record.source_scope || "",
            style_index: record.style_index ?? null,
            resource_index: record.resource_index ?? null,
            object_id: objectId ?? null,
            object_type: action && action.object_type || null,
            frame: fields.Frame ?? null,
            main_frame: frameFields.MainFrame ?? null,
            follow_frame: frameFields.FollowFrame ?? null,
            margin_frame: frameFields.MarginFrame ?? null,
            references,
            details: { action_fields: fields, action_frame_fields: frameFields }
        };
    }).sort((left, right) => left.action_id - right.action_id || String(left.source_scope).localeCompare(String(right.source_scope)));
}

function compactProfile(profile) {
    if (!profile || !profile.enabled) return { enabled: false };
    return {
        enabled: true,
        notation: profile.notation || "Normal",
        button: profile.button || "",
        command_no: profile.command_no ?? null,
        command_index: profile.command_index ?? null,
        ok_key_flags: profile.ok_key_flags ?? null,
        ok_key_cond_flags: profile.ok_key_cond_flags ?? null,
        dc_exc_flags: profile.dc_exc_flags ?? null,
        ng_key_flags: profile.ng_key_flags ?? null,
        preceding_time: profile.preceding_time ?? null,
        command: profile.command || null
    };
}

function buildBcmRows(source, sourceEntry) {
    const catalog = bcmCore.buildCatalog(source, {
        sourceFilename: sourceEntry.bcm_file,
        sourceSha256: sourceEntry.bcm_sha256
    });
    const rows = [];
    for (const action of Object.values(catalog.actions || {})) {
        for (const trigger of action.triggers || []) {
            rows.push({
                action_id: Number(action.action_id),
                trigger_index: trigger.trigger_index,
                classic_display: trigger.classic_display || action.classic_display || "",
                classic_profile: trigger.classic_profile || null,
                norm: compactProfile(trigger.profiles && trigger.profiles.norm),
                easy: compactProfile(trigger.profiles && trigger.profiles.easy),
                sprt: compactProfile(trigger.profiles && trigger.profiles.sprt),
                supr: compactProfile(trigger.profiles && trigger.profiles.supr),
                conditions: trigger.conditions || {}
            });
        }
    }
    rows.sort((left, right) => left.action_id - right.action_id || left.trigger_index - right.trigger_index);
    return { rows, stats: catalog.stats, warnings: catalog.warnings || [] };
}

function buildOfficialRows(source) {
    if (!source) return [];
    const entries = Object.entries(source)
        .filter(([key, value]) => /^\d+$/.test(key) && value && typeof value === "object")
        .map(([key, value]) => ({
            key,
            official_action_id: value.official_web_id ?? (/^\d+$/.test(key) ? Number(key) : null),
            move_name: value.move_name || "",
            category: value.category || "",
            classic_display: value.classic_display || "",
            modern_display: value.modern_display ?? null,
            control_support: value.control_support || "",
            note: value.note || ""
        }));
    for (const value of source._semantic_rows || []) {
        if (!value || typeof value !== "object") continue;
        entries.push({
            key: value.semantic_row_id || `semantic:${entries.length}`,
            official_action_id: value.official_web_id ?? null,
            move_name: value.move_name || "",
            category: value.category || "",
            classic_display: value.classic_display || "",
            modern_display: value.modern_display ?? null,
            control_support: value.control_support || "",
            note: value.note || ""
        });
    }
    return entries.sort((left, right) => {
        const leftId = Number(left.official_action_id), rightId = Number(right.official_action_id);
        if (Number.isFinite(leftId) && Number.isFinite(rightId)) return leftId - rightId;
        if (Number.isFinite(leftId)) return -1;
        if (Number.isFinite(rightId)) return 1;
        return String(left.key).localeCompare(String(right.key));
    });
}

function buildCommandRows(source) {
    if (!source) return [];
    return Object.entries(source)
        .filter(([key, value]) => /^\d+$/.test(key) && value && typeof value === "object")
        .map(([key, value]) => ({
            action_id: Number(key),
            classic_command: value.classic_command?.display || "",
            simple_command: value.simple_command?.display || "",
            motion_command: value.motion_command?.display || "",
            ownership: value.ownership || "",
            source: value.source || "",
            routes: (value.routes || []).map(route => ({
                display: route.display || "",
                owner_action_id: route.owner_action_id ?? null,
                trigger_index: route.trigger_index ?? null,
                profile: route.profile || "",
                source: route.source || "",
                confidence: route.confidence || "",
                ac_relation_type: route.ac_relation_type ?? null,
                inherited_from_action_id: route.inherited_from_action_id ?? null
            }))
        }))
        .sort((left, right) => left.action_id - right.action_id);
}

function buildPreview(outputRoot, version, character, options = {}) {
    validateName(character, "角色名");
    const loaded = loadManifest(outputRoot, version);
    const sourceEntry = loaded.manifest.sources.find(source => source.character === character);
    if (!sourceEntry) throw new Error(`版本 ${version} 中没有角色 ${character}。`);
    const acFilename = resolveChild(loaded.directory, sourceEntry.ac_file);
    const bcmFilename = resolveChild(loaded.directory, sourceEntry.bcm_file);
    const offFilename = archivedOfficialFile(outputRoot, version, character)
        || officialFile(character, options.officialRoot);
    const commandFilename = generatedCommandFile(outputRoot, version, character);
    const acSource = readJson(acFilename);
    const bcmSource = readJson(bcmFilename);
    const offSource = offFilename ? readJson(offFilename) : null;
    const commandSource = commandFilename ? readJson(commandFilename) : null;
    const bcm = buildBcmRows(bcmSource, sourceEntry);
    const acRows = buildAcRows(acSource);
    const offRows = buildOfficialRows(offSource);
    const commandRows = buildCommandRows(commandSource);
    return {
        version,
        character,
        fighter_id: sourceEntry.fighter_id,
        stem: sourceEntry.stem,
        files: {
            ac: { name: sourceEntry.ac_file, path: acFilename, sha256: sourceEntry.ac_sha256 },
            bcm: { name: sourceEntry.bcm_file, path: bcmFilename, sha256: sourceEntry.bcm_sha256 },
            official: offFilename ? { name: path.basename(offFilename), path: offFilename, schema: offSource?._meta?.schema || null } : null,
            official_raw: archivedOfficialRawFile(outputRoot, version, character)
                ? { name: `${character}.official.raw.json`, path: archivedOfficialRawFile(outputRoot, version, character) } : null,
            command: commandFilename ? { name: path.basename(commandFilename), path: commandFilename, schema: commandSource?._meta?.schema || null } : null
        },
        counts: { ac: acRows.length, bcm: bcm.rows.length, official: offRows.length, command: commandRows.length },
        ac: { meta: { schema: acSource.schema, record_count: acSource.record_count, object_count: acSource.objects?.length || 0, truncated: acSource.truncated === true }, rows: acRows },
        bcm: { meta: { schema: bcmSource.schema, trigger_count: bcmSource.trigger_count, object_count: bcmSource.objects?.length || 0, truncated: bcmSource.truncated === true, stats: bcm.stats, warnings: bcm.warnings }, rows: bcm.rows },
        official: { meta: offSource?._meta || null, rows: offRows },
        command: { meta: commandSource?._meta || null, rows: commandRows }
    };
}

module.exports = { buildPreviewIndex, buildPreview, buildAcRows, buildBcmRows, buildOfficialRows, buildCommandRows };
