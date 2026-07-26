export const COMBO_JSON_EDITOR = Object.freeze({
    id: "sf6cc.combo-json-editor",
    version: "1.0.0",
    metaSchema: 2,
    jsonId: "xt.combo_trial",
    jsonVersion: "2.0.0",
    sceneV1: "xt.combo_trial.scene.v1",
    sceneV2: "xt.combo_trial.scene.v2",
    environmentV1: "xt.training_environment.v1"
});

const CANONICAL_META_KEYS = [
    "schema",
    "title",
    "author",
    "note",
    "tags",
    "step_notes",
    "language",
    "control_mode",
    "created_at",
    "updated_at",
    "versions",
    "environment"
];

const DUMMY_FIELDS = [
    "dummy_action_type",
    "dummy_jump_type",
    "dummy_guard_type",
    "dummy_stance"
];

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function deepClone(value) {
    if (typeof structuredClone === "function") return structuredClone(value);
    return JSON.parse(JSON.stringify(value));
}

export function parseComboJson(text, sourceName = "JSON") {
    let value;
    try {
        value = JSON.parse(String(text).replace(/^\uFEFF/, ""));
    } catch (error) {
        throw new Error(`${sourceName}: JSON 解析失败 (parse failed): ${error.message}`);
    }

    const validation = validateComboDocument(value);
    if (!validation.valid) {
        throw new Error(`${sourceName}: ${validation.errors.join("；")}`);
    }
    return value;
}

export function serializeComboJson(document) {
    return `${JSON.stringify(document, null, 2)}\n`;
}

export function validateComboDocument(document) {
    const errors = [];
    const warnings = [];

    if (!Array.isArray(document) || document.length === 0) {
        errors.push("根节点必须是非空步骤数组 (root must be a non-empty step array)");
        return { valid: false, errors, warnings };
    }

    document.forEach((step, index) => {
        const label = `步骤 (step) ${index + 1}`;
        if (!isObject(step)) {
            errors.push(`${label} 必须是对象 (must be an object)`);
            return;
        }
        if (!Number.isFinite(Number(step.id))) warnings.push(`${label} 缺少有效 id (missing valid id)`);
        if (typeof step.motion !== "string") warnings.push(`${label} 缺少 motion (missing motion)`);
        if (!Number.isFinite(Number(step.delay_from_prev))) warnings.push(`${label} 缺少 delay_from_prev (missing delay_from_prev)`);
    });

    const first = document[0];
    if (!isObject(first._xt_meta)) {
        warnings.push("步骤 1 缺少 _xt_meta (step 1 is missing _xt_meta)");
    } else {
        const meta = first._xt_meta;
        const schema = Number(meta.schema);
        if (!Number.isFinite(schema)) warnings.push(`无法识别元数据 schema (unrecognized metadata schema): ${String(meta.schema)}`);
        if (Array.isArray(meta.step_notes) && meta.step_notes.length !== document.length) {
            warnings.push(`step_notes 数量 ${meta.step_notes.length} 与步骤数量 ${document.length} 不一致 (count mismatch)`);
        }
        if (meta.versions !== undefined && !isObject(meta.versions)) {
            warnings.push("versions 应为对象 (must be an object)");
        }
    }

    if (first.scene_state !== undefined) {
        if (!isObject(first.scene_state)) {
            errors.push("scene_state 必须是对象 (must be an object)");
        } else if (first.scene_state.players !== undefined && !isObject(first.scene_state.players)) {
            errors.push("scene_state.players 必须是对象 (must be an object)");
        }
    }

    return { valid: errors.length === 0, errors, warnings };
}

function normalizeText(value) {
    return value === null || value === undefined ? "" : String(value);
}

function normalizeTags(value) {
    const values = Array.isArray(value)
        ? value
        : typeof value === "string"
            ? value.split(/[,，\n]/)
            : [];
    const seen = new Set();
    const out = [];
    for (const item of values) {
        const text = normalizeText(item).trim();
        if (text === "" || seen.has(text)) continue;
        seen.add(text);
        out.push(text);
    }
    return out;
}

function normalizeStepNotes(value, stepCount) {
    let notes = [];
    let overflow = [];
    if (Array.isArray(value)) {
        notes = value.map(normalizeText);
    } else if (isObject(value)) {
        for (let index = 1; index <= stepCount; index += 1) {
            notes.push(normalizeText(value[index] ?? value[String(index)]));
        }
    }

    if (notes.length > stepCount) {
        overflow = notes.slice(stepCount);
        notes = notes.slice(0, stepCount);
    }
    while (notes.length < stepCount) notes.push("");
    return { notes, overflow };
}

function normalizeControlMode(meta) {
    const raw = normalizeText(
        meta.control_mode
        ?? meta.control_type
        ?? meta.timeline_input_profile
    ).trim().toLowerCase();
    if (raw === "classic" || raw === "modern") return raw;
    return "unknown";
}

function normalizeDeclaredControlMode(value) {
    const mode = normalizeText(value).trim().toLowerCase();
    if (mode === "classic" || mode === "modern" || mode === "unknown") return mode;
    return "";
}

function normalizeTimestamp(value) {
    if (typeof value !== "string") return undefined;
    const text = value.trim();
    if (text === "") return undefined;
    if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(text)) {
        return text.replace(" ", "T");
    }
    return text;
}

function normalizeVersionRef(value, fallbackId) {
    if (isObject(value)) {
        const out = { ...value };
        if (!normalizeText(out.id).trim() && fallbackId) out.id = fallbackId;
        if (out.version !== undefined) out.version = normalizeText(out.version).trim();
        return out;
    }
    if (typeof value === "string" || typeof value === "number") {
        return { id: fallbackId, version: String(value) };
    }
    return { id: fallbackId };
}

function normalizeVersions(value, profile = {}) {
    const source = isObject(value) ? value : {};
    const out = {};
    for (const [key, versionRef] of Object.entries(source)) {
        out[key] = isObject(versionRef) ? { ...versionRef } : versionRef;
    }
    out.game = normalizeVersionRef(source.game, "sf6");
    out.recorder = normalizeVersionRef(source.recorder, "unknown");
    if (normalizeText(profile.gameId).trim()) out.game.id = normalizeText(profile.gameId).trim();
    if (normalizeText(profile.gameVersion).trim()) out.game.version = normalizeText(profile.gameVersion).trim();
    if (normalizeText(profile.recorderId).trim()) out.recorder.id = normalizeText(profile.recorderId).trim();
    if (normalizeText(profile.recorderVersion).trim()) {
        out.recorder.version = normalizeText(profile.recorderVersion).trim();
    }
    if (isObject(source.framework)
        || normalizeText(profile.frameworkId).trim()
        || normalizeText(profile.frameworkVersion).trim()) {
        out.framework = normalizeVersionRef(source.framework, "reframework");
        if (normalizeText(profile.frameworkId).trim()) {
            out.framework.id = normalizeText(profile.frameworkId).trim();
        }
        if (normalizeText(profile.frameworkVersion).trim()) {
            out.framework.version = normalizeText(profile.frameworkVersion).trim();
        }
    }
    out.json = {
        ...normalizeVersionRef(source.json, COMBO_JSON_EDITOR.jsonId),
        id: COMBO_JSON_EDITOR.jsonId,
        version: COMBO_JSON_EDITOR.jsonVersion
    };
    out.editor = {
        id: COMBO_JSON_EDITOR.id,
        version: COMBO_JSON_EDITOR.version
    };
    return out;
}

function inferCharacterFromPath(relativePath) {
    if (typeof relativePath !== "string") return "";
    const first = relativePath.replace(/\\/g, "/").split("/").filter(Boolean)[0];
    return first || "";
}

function namedDummyGuardType(value) {
    const text = String(value ?? "").trim().toLowerCase();
    if (["none", "no", "off"].includes(text)) return 0;
    if (["after_first_hit", "after-first-hit", "after first hit"].includes(text)) return 2;
    if (["all", "guard_all", "full"].includes(text)) return 3;
    if (text === "random") return 4;
    return null;
}

function normalizeDummyGuardType(value) {
    const number = Number(value);
    return Number.isFinite(number) && Math.floor(number) === 1 ? 2 : value;
}

function collectEnvironment(meta, first = null) {
    let environment = isObject(meta.environment) ? deepClone(meta.environment) : null;
    for (const field of DUMMY_FIELDS) {
        const value = meta[field] !== undefined ? meta[field] : first?.[field];
        if (value === undefined) continue;
        if (!environment) environment = {};
        if (environment[field] === undefined) environment[field] = value;
    }
    const legacyGuard = environment?.dummy_guard ?? meta.dummy_guard ?? first?.dummy_guard;
    if (!environment && legacyGuard !== undefined) environment = {};
    if (environment) {
        if (environment.dummy_guard_type === undefined) {
            const guardType = namedDummyGuardType(legacyGuard);
            if (guardType !== null) environment.dummy_guard_type = guardType;
        } else {
            environment.dummy_guard_type = normalizeDummyGuardType(environment.dummy_guard_type);
        }
        delete environment.dummy_guard;
    }
    return environment;
}

function diffPaths(before, after, prefix = "") {
    if (Object.is(before, after)) return [];
    if (Array.isArray(before) && Array.isArray(after)) {
        const paths = [];
        const length = Math.max(before.length, after.length);
        for (let index = 0; index < length; index += 1) {
            paths.push(...diffPaths(before[index], after[index], `${prefix}[${index}]`));
        }
        return paths;
    }
    if (isObject(before) && isObject(after)) {
        const paths = [];
        const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
        for (const key of keys) {
            paths.push(...diffPaths(before[key], after[key], prefix ? `${prefix}.${key}` : key));
        }
        return paths;
    }
    return [prefix || "$"];
}

export function migrateComboDocument(document, options = {}) {
    const validation = validateComboDocument(document);
    if (!validation.valid) throw new Error(validation.errors.join("；"));

    const out = deepClone(document);
    const first = out[0];
    const oldMeta = isObject(first._xt_meta) ? first._xt_meta : {};
    const sourceSchema = oldMeta.schema ?? null;
    const timestamp = normalizeText(options.timestamp).trim() || new Date().toISOString();
    const normalizedNotes = normalizeStepNotes(oldMeta.step_notes, out.length);
    const canonical = {
        schema: COMBO_JSON_EDITOR.metaSchema,
        title: normalizeText(oldMeta.title),
        author: normalizeText(oldMeta.author),
        note: normalizeText(oldMeta.note),
        tags: normalizeTags(oldMeta.tags),
        step_notes: normalizedNotes.notes,
        language: normalizeText(options.metadataProfile?.language).trim()
            || normalizeText(oldMeta.language).trim()
            || "und",
        control_mode: normalizeDeclaredControlMode(options.metadataProfile?.controlMode)
            || normalizeControlMode(oldMeta)
    };

    const createdAt = normalizeTimestamp(oldMeta.created_at);
    const updatedAt = normalizeTimestamp(oldMeta.updated_at) || timestamp;
    if (createdAt) canonical.created_at = createdAt;
    canonical.updated_at = updatedAt;
    canonical.versions = normalizeVersions(oldMeta.versions, options.versionProfile);

    const environment = collectEnvironment(oldMeta, first);
    if (environment) canonical.environment = environment;

    for (const [key, value] of Object.entries(oldMeta)) {
        if (CANONICAL_META_KEYS.includes(key) || key === "dummy_guard") continue;
        canonical[key] = deepClone(value);
    }
    if (canonical.dummy_guard_type !== undefined) {
        canonical.dummy_guard_type = normalizeDummyGuardType(canonical.dummy_guard_type);
    }
    if (first.dummy_guard_type !== undefined) {
        first.dummy_guard_type = normalizeDummyGuardType(first.dummy_guard_type);
    }

    if (!normalizeText(canonical.character).trim()) {
        const character = inferCharacterFromPath(options.relativePath);
        if (character) canonical.character = character;
    }
    if (normalizedNotes.overflow.some(note => note !== "")) {
        canonical.legacy_extra_step_notes = normalizedNotes.overflow;
    }

    first._xt_meta = canonical;
    const postValidation = validateComboDocument(out);
    if (!postValidation.valid) throw new Error(postValidation.errors.join("；"));

    return {
        document: out,
        sourceSchema,
        targetSchema: COMBO_JSON_EDITOR.metaSchema,
        changes: diffPaths(oldMeta, canonical, "_xt_meta"),
        warnings: postValidation.warnings,
        sourceWarnings: validation.warnings
    };
}

export function mechanismProjection(document) {
    const out = deepClone(document);
    if (isObject(out[0])) delete out[0]._xt_meta;
    return out;
}

export function metadataModel(document) {
    const first = document[0];
    const meta = isObject(first._xt_meta) ? first._xt_meta : {};
    const environment = collectEnvironment(meta, first) || {};
    return {
        schema: meta.schema,
        title: normalizeText(meta.title),
        author: normalizeText(meta.author),
        note: normalizeText(meta.note),
        tags: normalizeTags(meta.tags),
        step_notes: normalizeStepNotes(meta.step_notes, document.length).notes,
        language: normalizeText(meta.language).trim() || "und",
        control_mode: normalizeControlMode(meta),
        character: normalizeText(meta.character),
        category: normalizeText(meta.category),
        rating: meta.rating ?? "",
        created_at: normalizeText(meta.created_at),
        updated_at: normalizeText(meta.updated_at),
        environment,
        scene_state: isObject(first.scene_state) ? deepClone(first.scene_state) : null,
        snapshot_gauges: isObject(first.snapshot_gauges) ? deepClone(first.snapshot_gauges) : null
    };
}

function assignOptional(target, key, value) {
    if (value === undefined || value === null || value === "") {
        delete target[key];
    } else {
        target[key] = value;
    }
}

function normalizeOptionalNumber(value) {
    if (value === undefined || value === null || String(value).trim() === "") return null;
    const number = Number(value);
    if (!Number.isFinite(number)) throw new Error(`无效数字 (invalid number): ${String(value)}`);
    return number;
}

export function applyMetadataEdits(document, edits, options = {}) {
    const migrated = migrateComboDocument(document, options).document;
    const out = deepClone(migrated);
    const first = out[0];
    const meta = first._xt_meta;

    for (const field of ["title", "author", "note", "language", "control_mode", "character", "category"]) {
        if (edits[field] !== undefined) meta[field] = normalizeText(edits[field]);
    }
    if (edits.tags !== undefined) meta.tags = normalizeTags(edits.tags);
    if (edits.rating !== undefined) assignOptional(meta, "rating", normalizeOptionalNumber(edits.rating));
    if (edits.created_at !== undefined) assignOptional(meta, "created_at", normalizeTimestamp(edits.created_at));
    if (edits.updated_at !== undefined) {
        assignOptional(meta, "updated_at", normalizeTimestamp(edits.updated_at));
    } else {
        meta.updated_at = normalizeText(options.timestamp).trim() || new Date().toISOString();
    }
    if (edits.step_notes !== undefined) {
        meta.step_notes = normalizeStepNotes(edits.step_notes, out.length).notes;
    }

    if (isObject(edits.environment)) updateEnvironmentInPlace(out, edits.environment);
    if (isObject(edits.scene)) updateSceneInPlace(out, edits.scene);
    if (isObject(edits.snapshot)) updateSnapshotInPlace(out, edits.snapshot);

    return out;
}

export function applyVersionProfile(document, profile, options = {}) {
    const migrated = migrateComboDocument(document, {
        ...options,
        versionProfile: profile
    }).document;
    migrated[0]._xt_meta.versions = normalizeVersions(
        migrated[0]._xt_meta.versions,
        profile
    );
    return migrated;
}

function updateEnvironmentInPlace(document, values) {
    const first = document[0];
    const meta = first._xt_meta;
    const environment = isObject(meta.environment) ? meta.environment : {};
    delete environment.dummy_guard;
    delete meta.dummy_guard;
    delete first.dummy_guard;

    const normalizedValues = { ...values };
    if (!("dummy_guard_type" in normalizedValues) && "dummy_guard" in normalizedValues) {
        normalizedValues.dummy_guard_type = namedDummyGuardType(normalizedValues.dummy_guard);
    }
    let hasValue = Object.keys(environment).length > 0;

    for (const field of DUMMY_FIELDS) {
        if (!(field in normalizedValues)) continue;
        let value = normalizedValues[field];
        if (field.endsWith("_type")) value = normalizeOptionalNumber(value);
        if (field === "dummy_guard_type") value = normalizeDummyGuardType(value);
        assignOptional(environment, field, value);
        assignOptional(meta, field, value);
        assignOptional(first, field, value);
        if (value !== null && value !== "") hasValue = true;
    }

    if ("requires_dummy_crouch" in values) {
        const value = values.requires_dummy_crouch;
        if (value === null || value === "") {
            delete meta.requires_dummy_crouch;
            delete first.requires_dummy_crouch;
        } else {
            meta.requires_dummy_crouch = value === true;
            first.requires_dummy_crouch = value === true;
            hasValue = true;
        }
    }

    if (hasValue && Object.keys(environment).length > 0) {
        if (!environment.schema) environment.schema = COMBO_JSON_EDITOR.environmentV1;
        meta.environment = environment;
    } else {
        delete meta.environment;
    }
}

function ensureScenePlayer(scene, side) {
    if (!isObject(scene.players)) scene.players = {};
    if (!isObject(scene.players[side])) scene.players[side] = {};
    return scene.players[side];
}

function updateScenePlayerInPlace(scene, side, values) {
    if (!isObject(values)) return false;
    const player = ensureScenePlayer(scene, side);
    let promotesV2 = false;
    if ("fighter_id" in values) assignOptional(player, "fighter_id", normalizeOptionalNumber(values.fighter_id));

    if (isObject(values.resources)) {
        const resources = isObject(player.resources) ? player.resources : {};
        for (const field of ["hp", "drive", "super"]) {
            if (!(field in values.resources)) continue;
            assignOptional(resources, field, normalizeOptionalNumber(values.resources[field]));
        }
        if (Object.keys(resources).length > 0) {
            player.resources = resources;
            promotesV2 = true;
        } else {
            delete player.resources;
        }
    }

    if (isObject(values.status)) {
        const status = isObject(player.status) ? player.status : {};
        for (const field of ["burnout", "stunned"]) {
            if (!(field in values.status)) continue;
            const value = values.status[field];
            assignOptional(status, field, value === "" || value === null ? null : value === true);
        }
        if ("stance" in values.status) assignOptional(status, "stance", values.status.stance);
        if (Object.keys(status).length > 0) {
            player.status = status;
            promotesV2 = true;
        } else {
            delete player.status;
        }
    }

    if ("unique" in values) {
        if (values.unique === null || Object.keys(values.unique).length === 0) delete player.unique;
        else player.unique = deepClone(values.unique);
    }
    return promotesV2;
}

function updateSceneInPlace(document, values) {
    const first = document[0];
    const scene = isObject(first.scene_state)
        ? first.scene_state
        : {
            schema: COMBO_JSON_EDITOR.sceneV1,
            capture_mode: "portable",
            recorded_by: Number(first.recorded_by) || 0,
            players: {}
        };
    let promotesV2 = false;
    for (const side of ["p1", "p2"]) {
        if (isObject(values[side])) promotesV2 = updateScenePlayerInPlace(scene, side, values[side]) || promotesV2;
    }
    if ("recorded_by" in values) scene.recorded_by = normalizeOptionalNumber(values.recorded_by) ?? 0;
    if (promotesV2) scene.schema = COMBO_JSON_EDITOR.sceneV2;
    first.scene_state = scene;
}

function updateSnapshotRoleInPlace(snapshot, role, values) {
    if (!isObject(values)) return;
    const target = isObject(snapshot[role]) ? snapshot[role] : {};
    for (const field of ["current_hp", "max_hp", "heal_hp"]) {
        if (!(field in values)) continue;
        assignOptional(target, field, normalizeOptionalNumber(values[field]));
    }
    if (Object.keys(target).length > 0) snapshot[role] = target;
    else delete snapshot[role];
}

function updateSnapshotInPlace(document, values) {
    const first = document[0];
    const snapshot = isObject(first.snapshot_gauges) ? first.snapshot_gauges : {};
    for (const role of ["attacker", "victim"]) {
        if (isObject(values[role])) updateSnapshotRoleInPlace(snapshot, role, values[role]);
    }
    if (Object.keys(snapshot).length > 0) first.snapshot_gauges = snapshot;
    else delete first.snapshot_gauges;
}
