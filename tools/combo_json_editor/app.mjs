import {
    applyMetadataEdits,
    COMBO_JSON_EDITOR,
    metadataModel,
    migrateComboDocument,
    parseComboJson,
    serializeComboJson,
    validateComboDocument
} from "./combo_json_core.mjs";
import {
    CHARACTER_CATALOG,
    characterByFolder,
    characterLabel,
    folderFromPath
} from "./character_catalog.mjs";
import {
    mergeUniqueResourceValues,
    resourceDefinitionsForFighter,
    resourceOptions,
    splitUniqueResourceValues
} from "./unique_resource_catalog.mjs";
import { compareFileNames, isFailMarkedFile } from "./file_name_sort.mjs";

const $ = id => document.getElementById(id);
const state = {
    records: [],
    selected: null,
    rootHandle: null,
    rootName: "",
    filter: "",
    status: "all",
    characterFolder: "all"
};
let toastTimer = null;

/* 训练菜单的默认状态以游戏“陪练设置”页面为准。
   空字符串不属于默认值，而是明确标记为“未记录”。 */
const DUMMY_MENU_SELECT_IDS = Object.freeze([
    "dummyControl",
    "dummyAction",
    "dummyCounterType",
    "dummyGuardType",
    "dummyGuardCount",
    "dummyGuardSwitchMode",
    "dummyGuardKind",
    "dummyDriveReversalType",
    "dummyDriveReversalDelay",
    "dummyDriveReversalCount",
    "dummyThrowEscapeType",
    "dummyWakeupType"
]);
const DUMMY_MENU_NUMBER_IDS = Object.freeze([
    "dummyCounterWeightNormal",
    "dummyCounterWeightCounter",
    "dummyCounterWeightPunish",
    "dummyDriveReversalWeightNone",
    "dummyDriveReversalWeightGuard",
    "dummyDriveReversalWeightWakeup"
]);
const DUMMY_MENU_VISUAL_IDS = Object.freeze([
    ...DUMMY_MENU_SELECT_IDS,
    ...DUMMY_MENU_NUMBER_IDS
]);
const DUMMY_MENU_DEFAULTS = Object.freeze({
    dummyControl: "dummy",
    dummyAction: "0",
    dummyCounterType: "0",
    dummyCounterWeightNormal: "1",
    dummyCounterWeightCounter: "1",
    dummyCounterWeightPunish: "1",
    dummyGuardType: "0",
    dummyGuardCount: "10",
    dummyGuardSwitchMode: "0",
    dummyGuardKind: "0",
    dummyDriveReversalType: "0",
    dummyDriveReversalDelay: "0",
    dummyDriveReversalCount: "1",
    dummyDriveReversalWeightNone: "1",
    dummyDriveReversalWeightGuard: "1",
    dummyDriveReversalWeightWakeup: "1",
    dummyThrowEscapeType: "0",
    dummyWakeupType: "0"
});

function toast(message, isError = false) {
    const node = $("toast");
    node.textContent = message;
    node.className = isError ? "show error" : "show";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { node.className = ""; }, 3200);
}

function normalizePath(value) {
    return String(value || "").replace(/\\/g, "/");
}

function schemaNumber(record) {
    return Number(record.document?.[0]?._xt_meta?.schema);
}

function isLegacy(record) {
    return schemaNumber(record) !== COMBO_JSON_EDITOR.metaSchema
        || record.document?.[0]?._xt_meta?.versions?.json?.version !== COMBO_JSON_EDITOR.jsonVersion;
}

function recordSearchText(record) {
    const meta = record.document?.[0]?._xt_meta || {};
    const character = recordCharacter(record);
    return [
        record.path,
        meta.character,
        meta.title,
        meta.author,
        meta.note,
        character?.fighterId,
        character?.en,
        character?.zh
    ].join("\n").toLowerCase();
}

function recordFolder(record) {
    const directFolder = record.path.includes("/") ? folderFromPath(record.path) : "";
    if (directFolder) return directFolder;
    const metaCharacter = record.document?.[0]?._xt_meta?.character;
    return characterByFolder(metaCharacter)?.folder || String(metaCharacter || "未识别 (Unknown)");
}

function recordCharacter(record) {
    return characterByFolder(recordFolder(record))
        || characterByFolder(record.document?.[0]?._xt_meta?.character);
}

function updateSummary() {
    $("fileCount").textContent = state.records.length;
    $("legacyCount").textContent = state.records.filter(isLegacy).length;
    $("changedCount").textContent = state.records.filter(record => record.changed).length;
    $("errorCount").textContent = state.records.filter(record => record.error).length;
    $("rootLabel").textContent = state.rootName || "文件选择模式 (File selection mode)";
    const hasRecords = state.records.length > 0;
    $("upgradeAll").disabled = !hasRecords;
    $("batchVersions").disabled = !hasRecords;
    $("exportAll").disabled = !state.records.some(record => record.changed);
    $("saveAll").disabled = !state.rootHandle || !state.records.some(record => record.changed);
}

function filteredRecords() {
    /* 排序在载入时完成；筛选（含未来的经典/现代筛选）只过滤、不改变剩余项目顺序。
       文件名含区分大小写 _FAIL_ 的、以及无效或无法加载的 JSON 不进入列表。 */
    return state.records.filter(record => {
        if (isFailMarkedFile(record.name)) return false;
        if (record.error || !record.document) return false;
        if (state.filter && !recordSearchText(record).includes(state.filter)) return false;
        if (state.characterFolder !== "all" && recordFolder(record) !== state.characterFolder) return false;
        if (state.status === "legacy" && !isLegacy(record)) return false;
        if (state.status === "changed" && !record.changed) return false;
        if (state.status === "warning" && !(record.error || record.warnings.length)) return false;
        return true;
    });
}

function renderFileList() {
    const list = $("fileList");
    const records = filteredRecords();
    if (!records.length) {
        list.innerHTML = `<div class="empty">${state.records.length ? "没有符合筛选条件的文件 (No matching files)" : "打开 CustomCombos 目录开始审核 (Open the directory to begin)"}</div>`;
        return;
    }
    list.replaceChildren(...records.map(record => {
        const button = document.createElement("button");
        button.className = `file-row${state.selected === record ? " active" : ""}`;
        const stateClass = record.error ? "warning" : record.changed ? "changed" : isLegacy(record) ? "legacy" : "";
        const meta = record.document?.[0]?._xt_meta || {};
        const character = recordCharacter(record);
        const folder = recordFolder(record);
        const characterText = character
            ? `ID ${character.fighterId} · ${character.zh} (${character.en}) · [${folder}]`
            : `${meta.character || "未识别 (Unknown)"} · [${folder}]`;
        button.innerHTML = `
            <span class="name">${escapeHtml(meta.title || record.name)}</span>
            <span class="dot ${stateClass}"></span>
            <span class="detail">${escapeHtml(characterText)} · ${escapeHtml(meta.author || "无作者 (No author)")} · ${escapeHtml(record.path)}</span>
        `;
        button.onclick = () => selectRecord(record);
        return button;
    }));
}

function populateCharacterFilter() {
    const select = $("characterFilter");
    const previous = state.characterFolder;
    const counts = new Map();
    for (const record of state.records) {
        const folder = recordFolder(record);
        counts.set(folder, (counts.get(folder) || 0) + 1);
    }
    const folders = [...counts.keys()].sort((left, right) => {
        const leftCharacter = characterByFolder(left);
        const rightCharacter = characterByFolder(right);
        if (leftCharacter && rightCharacter) return leftCharacter.fighterId - rightCharacter.fighterId;
        if (leftCharacter) return -1;
        if (rightCharacter) return 1;
        return left.localeCompare(right, "en");
    });
    const options = [new Option(`全部角色文件夹 (All character folders) · ${state.records.length}`, "all")];
    for (const folder of folders) {
        const character = characterByFolder(folder);
        options.push(new Option(
            character ? characterLabel(character, counts.get(folder)) : `[${folder}] · 未识别 (Unknown) · ${counts.get(folder)}`,
            folder
        ));
    }
    select.replaceChildren(...options);
    state.characterFolder = folders.includes(previous) ? previous : "all";
    select.value = state.characterFolder;
}

function populateFighterSelect(id) {
    const select = $(id);
    const options = [new Option("未记录 (Not recorded)", "")];
    for (const character of CHARACTER_CATALOG) {
        options.push(new Option(
            `${character.zh} (${character.en}) · ID ${character.fighterId}`,
            String(character.fighterId)
        ));
    }
    select.replaceChildren(...options);
}

function renderChoiceBoxes(select) {
    const group = select._choiceGroup;
    if (!group) return;
    if (select._starMode) {
        renderRatingStars(select, group);
        return;
    }
    const selectedValue = select.value;
    const buttons = [...select.options].map(option => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "choice-box";
        /* 空值选项统一显示为 ✕（清空），避免“未记录 (Not recorded)”中英文撑宽布局 */
        if (option.value === "") {
            button.textContent = "✕";
            button.classList.add("clear");
            button.title = `清空 (Clear)：${option.textContent}`;
        } else {
            button.textContent = option.textContent;
        }
        button.disabled = option.disabled;
        button.dataset.value = option.value;
        const selected = option.value === selectedValue;
        button.classList.toggle("selected", selected);
        button.setAttribute("role", "radio");
        button.setAttribute("aria-checked", String(selected));
        button.onclick = event => {
            event.preventDefault();
            if (option.disabled) return;
            select.value = option.value;
            renderChoiceBoxes(select);
            select.dispatchEvent(new Event("change", { bubbles: true }));
        };
        return button;
    });
    group.replaceChildren(...buttons);
    if (group.classList.contains("fighter")) {
        const selectedButton = group.querySelector(".choice-box.selected");
        requestAnimationFrame(() => selectedButton?.scrollIntoView({ block: "nearest" }));
    }
}

function enhanceChoiceSelect(select, variant = "compact") {
    if (!select || select._choiceGroup) {
        if (select?._choiceGroup) renderChoiceBoxes(select);
        return;
    }
    const group = document.createElement("div");
    group.className = `choice-boxes ${variant}`;
    group.setAttribute("role", "radiogroup");
    select.hidden = true;
    select.insertAdjacentElement("afterend", group);
    select._choiceGroup = group;
    renderChoiceBoxes(select);
}

function populateNumericSelect(id, minimum, maximum, format = value => String(value)) {
    const select = $(id);
    const options = [new Option("未记录 (Not recorded)", "")];
    for (let value = minimum; value <= maximum; value += 1) {
        options.push(new Option(format(value), String(value)));
    }
    select.replaceChildren(...options);
}

function enhanceStepperControl(control, move, numeric = false) {
    if (!control || control._stepperButtons) return;
    const wrapper = document.createElement("div");
    wrapper.className = `select-stepper${numeric ? " numeric-stepper" : ""}`;
    const previous = document.createElement("button");
    const next = document.createElement("button");
    previous.type = next.type = "button";
    previous.textContent = "‹";
    next.textContent = "›";
    previous.title = numeric ? "减少数值 (Decrease value)" : "上一个选项 (Previous option)";
    next.title = numeric ? "增加数值 (Increase value)" : "下一个选项 (Next option)";
    control.insertAdjacentElement("beforebegin", wrapper);
    wrapper.append(previous, control, next);
    control._stepperButtons = [previous, next];
    previous.onclick = event => { event.preventDefault(); move(-1); };
    next.onclick = event => { event.preventDefault(); move(1); };
}

function enhanceStepperSelect(select) {
    if (!select || select._stepperButtons) return;
    const move = direction => {
        const options = [...select.options].filter(option => !option.disabled);
        if (!options.length || select.disabled) return;
        let index = options.findIndex(option => option.value === select.value);
        if (index < 0) index = 0;
        index = (index + direction + options.length) % options.length;
        select.value = options[index].value;
        select.dispatchEvent(new Event("change", { bubbles: true }));
    };
    enhanceStepperControl(select, move);
}

function enhanceNumericStepper(input) {
    if (!input || input._stepperButtons) return;
    const move = direction => {
        if (input.disabled) return;
        const minimum = input.min === "" ? Number.NEGATIVE_INFINITY : Number(input.min);
        const maximum = input.max === "" ? Number.POSITIVE_INFINITY : Number(input.max);
        const step = input.step === "" || input.step === "any" ? 1 : Number(input.step);
        let value = input.value.trim() === "" ? minimum : Number(input.value);
        if (!Number.isFinite(value)) value = 0;
        if (value === Number.NEGATIVE_INFINITY) value = 0;
        value = Math.min(maximum, Math.max(minimum, value + direction * step));
        input.value = String(value);
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
    };
    enhanceStepperControl(input, move, true);
}

/* 评分星级控件：0-5 星，再次点击当前星数清零，支持清除回“未记录”。
   数据仍读写隐藏的 #rating select，业务回填/保存路径不变。 */
function renderRatingStars(select, group) {
    const value = select.value;
    const current = value === "" ? -1 : Math.max(0, Math.min(5, Number(value) || 0));
    const parts = [];
    for (let star = 1; star <= 5; star++) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = `star${star <= current ? " filled" : ""}`;
        button.textContent = "★";
        button.title = `${star} 星 (${star} stars)`;
        button.setAttribute("role", "radio");
        button.setAttribute("aria-checked", String(star === current));
        button.onclick = event => {
            event.preventDefault();
            select.value = String(current === star ? 0 : star);
            renderChoiceBoxes(select);
            select.dispatchEvent(new Event("change", { bubbles: true }));
        };
        parts.push(button);
    }
    const label = document.createElement("span");
    label.className = "rating-value";
    label.textContent = current < 0 ? "未记录 (Not recorded)" : `${current} 星`;
    parts.push(label);
    if (current >= 0) {
        const clear = document.createElement("button");
        clear.type = "button";
        clear.className = "rating-clear";
        clear.textContent = "清除 (Clear)";
        clear.onclick = event => {
            event.preventDefault();
            select.value = "";
            renderChoiceBoxes(select);
            select.dispatchEvent(new Event("change", { bubbles: true }));
        };
        parts.push(clear);
    }
    group.replaceChildren(...parts);
}

function enhanceStarRating(select) {
    if (!select) return;
    if (select._choiceGroup) {
        renderChoiceBoxes(select);
        return;
    }
    const group = document.createElement("div");
    group.className = "choice-boxes rating-stars";
    group.setAttribute("role", "radiogroup");
    select.hidden = true;
    select.insertAdjacentElement("afterend", group);
    select._choiceGroup = group;
    select._starMode = true;
    renderChoiceBoxes(select);
}

function escapeHtml(value) {
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
}

async function loadRecord(file, relativePath, fileHandle = null) {
    const text = await file.text();
    const pathValue = normalizePath(relativePath || file.webkitRelativePath || file.name);
    try {
        const document = parseComboJson(text, pathValue);
        const validation = validateComboDocument(document);
        return {
            name: file.name,
            path: pathValue,
            document,
            originalText: text,
            changed: false,
            error: null,
            warnings: validation.warnings,
            fileHandle
        };
    } catch (error) {
        return {
            name: file.name,
            path: pathValue,
            document: null,
            originalText: text,
            changed: false,
            error: error.message,
            warnings: [],
            fileHandle
        };
    }
}

async function walkDirectory(handle, prefix = "") {
    const records = [];
    for await (const [name, entry] of handle.entries()) {
        const relativePath = prefix ? `${prefix}/${name}` : name;
        if (entry.kind === "directory") {
            records.push(...await walkDirectory(entry, relativePath));
        } else if (entry.kind === "file" && name.toLowerCase().endsWith(".json")) {
            records.push(await loadRecord(await entry.getFile(), relativePath, entry));
        }
    }
    return records;
}

async function openDirectory() {
    if (!window.showDirectoryPicker) {
        toast("当前浏览器不支持目录原地写入，请使用 Chrome/Edge 或文件模式 (Directory write is unsupported).", true);
        return;
    }
    try {
        const handle = await window.showDirectoryPicker({ mode: "readwrite" });
        const records = await walkDirectory(handle);
        records.sort((left, right) => compareFileNames(left.name, right.name));
        state.records = records;
        state.rootHandle = handle;
        state.rootName = handle.name;
        state.selected = records.find(record => !record.error) || null;
        finishLoad();
    } catch (error) {
        if (error.name !== "AbortError") toast(error.message, true);
    }
}

async function openFiles(files) {
    const records = [];
    for (const file of files) {
        records.push(await loadRecord(file, file.webkitRelativePath || file.name));
    }
    records.sort((left, right) => compareFileNames(left.name, right.name));
    state.records = records;
    state.rootHandle = null;
    state.rootName = "文件选择模式 (File selection mode; save by download)";
    state.selected = records.find(record => !record.error) || null;
    finishLoad();
}

function finishLoad() {
    populateCharacterFilter();
    updateSummary();
    renderFileList();
    if (state.selected) {
        $("welcome").hidden = true;
        $("editor").hidden = false;
        renderSelected();
    } else {
        $("welcome").hidden = false;
        $("editor").hidden = true;
    }
    const failures = state.records.filter(record => record.error).length;
    toast(`已载入 ${state.records.length} 个 JSON (Loaded)${failures ? `，${failures} 个异常 (errors)` : ""}`, failures > 0);
}

function selectRecord(record) {
    if (record.error) {
        toast(record.error, true);
        return;
    }
    state.selected = record;
    renderFileList();
    renderSelected();
}

function setValue(id, value) {
    $(id).value = value === undefined || value === null ? "" : String(value);
}

function triState(value) {
    return value === true ? "true" : value === false ? "false" : "";
}

function displayJson(value) {
    return value && typeof value === "object" && Object.keys(value).length
        ? JSON.stringify(value, null, 2)
        : "";
}

function resourceOptionLabel(option) {
    return option.zh === option.en
        ? option.zh
        : `${option.zh} (${option.en})`;
}

function renderUniqueResourceEditor(prefix, fighterId, unique) {
    const container = $(`${prefix}Unique`);
    const unknownWrap = $(`${prefix}UniqueUnknownWrap`);
    const unknownInput = $(`${prefix}UniqueUnknown`);
    const definitions = resourceDefinitionsForFighter(fighterId);
    const { known, unknown } = splitUniqueResourceValues(fighterId, unique);
    const fragment = document.createDocumentFragment();

    if (!definitions.length) {
        const empty = document.createElement("div");
        empty.className = "resource-empty";
        empty.textContent = "该角色暂无可编辑特殊资源 (No editable unique resources)";
        fragment.append(empty);
    }

    for (const resource of definitions) {
        const label = document.createElement("label");
        label.className = "resource-control";
        const title = document.createElement("span");
        title.textContent = `${resource.zh} (${resource.en})`;
        const select = document.createElement("select");
        select.dataset.resourceId = resource.id;
        /* 开关类资源（如电刃炼气）没有“清空”：未记录时默认关闭 (Off) */
        const isState = resource.kind === "state";
        if (!isState) select.append(new Option("未记录 (Not recorded)", ""));
        for (const option of resourceOptions(resource)) {
            const node = new Option(resourceOptionLabel(option), String(option.value));
            node.disabled = option.disabled === true;
            select.add(node);
        }
        const current = known[resource.id];
        if (current !== undefined && ![...select.options].some(option => option.value === String(current))) {
            select.add(new Option(`未知值 ${current} (Unknown value)`, String(current)));
        }
        select.value = current === undefined || current === null ? (isState ? "0" : "") : String(current);
        select.addEventListener("change", () => syncSharedUniqueResources(prefix, resource.id));
        label.append(title, select);
        if (isState) label.classList.add("state-row");
        enhanceChoiceSelect(select, "resource");
        fragment.append(label);
    }

    container.replaceChildren(fragment);
    const unknownText = displayJson(unknown);
    unknownInput.value = unknownText;
    unknownWrap.hidden = !unknownText;
}

function findUniqueResourceSelect(prefix, resourceId) {
    return [...$(`${prefix}Unique`).querySelectorAll("[data-resource-id]")]
        .find(select => select.dataset.resourceId === resourceId) || null;
}

function syncSharedUniqueResources(sourcePrefix, resourceId = null) {
    const targetPrefix = sourcePrefix === "p1" ? "p2" : "p1";
    if ($(`${sourcePrefix}FighterId`).value !== $(`${targetPrefix}FighterId`).value) return;

    const sourceSelects = [...$(`${sourcePrefix}Unique`).querySelectorAll("[data-resource-id]")];
    for (const source of sourceSelects) {
        if (resourceId !== null && source.dataset.resourceId !== resourceId) continue;
        const target = findUniqueResourceSelect(targetPrefix, source.dataset.resourceId);
        if (!target) continue;
        target.value = source.value;
        renderChoiceBoxes(target);
    }
}

function parseJsonObject(id) {
    const text = $(id).value.trim();
    if (!text) return {};
    const value = JSON.parse(text);
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        throw new Error(`${id} 必须是 JSON 对象 (must be a JSON object)`);
    }
    return value;
}

function collectUnique(prefix) {
    const known = {};
    for (const select of $(`${prefix}Unique`).querySelectorAll("[data-resource-id]")) {
        if (select.value !== "") known[select.dataset.resourceId] = Number(select.value);
    }
    const unknown = parseJsonObject(`${prefix}UniqueUnknown`);
    const merged = mergeUniqueResourceValues(known, unknown);
    return Object.keys(merged).length ? merged : null;
}

function changeFighter(prefix) {
    try {
        const unique = collectUnique(prefix);
        renderUniqueResourceEditor(prefix, $(`${prefix}FighterId`).value, unique);
        syncSharedUniqueResources(attackerSide());
    } catch (error) {
        toast(`无法切换角色 (Cannot change fighter): ${error.message}`, true);
    }
}

function setControlDisabled(id, disabled) {
    const control = $(id);
    if (!control) return;
    control.disabled = disabled;
    control.closest(".dummy-menu-row")?.classList.toggle("is-disabled", disabled);
    if (control._stepperButtons) {
        for (const button of control._stepperButtons) button.disabled = disabled;
    }
}

function dummyMenuVisualState(control) {
    if (control.value === "") return "unrecorded";
    return control.value === DUMMY_MENU_DEFAULTS[control.id] ? "default" : "modified";
}

function setVisualState(element, visualState) {
    if (!element) return;
    for (const stateName of ["default", "modified", "unrecorded"]) {
        element.classList.toggle(`is-${stateName}`, visualState === stateName);
    }
}

function updateDummyMenuVisualState() {
    for (const id of DUMMY_MENU_VISUAL_IDS) {
        const control = $(id);
        if (!control) continue;
        const visualState = dummyMenuVisualState(control);
        const field = control.closest(".dummy-menu-row") || control.closest("label");
        field?.classList.add("dummy-setting");
        setVisualState(field, visualState);
        setVisualState(control.closest(".select-stepper"), visualState);
    }

    for (const details of document.querySelectorAll(".dummy-detail")) {
        const states = [...details.querySelectorAll("select, input")].map(dummyMenuVisualState);
        const visualState = states.includes("modified")
            ? "modified"
            : states.length && states.every(value => value === "unrecorded")
                ? "unrecorded"
                : "default";
        setVisualState(details, visualState);
    }
}

function syncDummyMenuState(fillDefaults = false) {
    $("dummyControl").value = "dummy";
    setControlDisabled("dummyControl", true);
    if (fillDefaults && $("dummyAction").value === "") $("dummyAction").value = "0";
    const action = $("dummyAction").value;
    if (fillDefaults && action === "2" && $("dummyJumpKind").value === "") {
        $("dummyJumpKind").value = "0";
    }

    const guardType = $("dummyGuardType").value;
    const countGuardEnabled = guardType === "5";
    const guardOptionsEnabled = ["2", "3", "4", "5"].includes(guardType);
    $("dummyGuardCountRow").hidden = !countGuardEnabled;
    $("dummyGuardSwitchModeRow").hidden = !guardOptionsEnabled;
    $("dummyGuardKindRow").hidden = !guardOptionsEnabled;
    setControlDisabled("dummyGuardCount", !countGuardEnabled);
    setControlDisabled("dummyGuardSwitchMode", !guardOptionsEnabled);
    setControlDisabled("dummyGuardKind", !guardOptionsEnabled);
    if (countGuardEnabled && fillDefaults && $("dummyGuardCount").value.trim() === "") {
        $("dummyGuardCount").value = "1";
    }
    if (guardOptionsEnabled && fillDefaults) {
        if ($("dummyGuardSwitchMode").value === "") $("dummyGuardSwitchMode").value = "0";
        if ($("dummyGuardKind").value === "") $("dummyGuardKind").value = "0";
    }

    const driveReversalEnabled = !["", "0"].includes($("dummyDriveReversalType").value);
    setControlDisabled("dummyDriveReversalDelay", !driveReversalEnabled);
    setControlDisabled("dummyDriveReversalCount", !driveReversalEnabled);
    if (fillDefaults && driveReversalEnabled) {
        if ($("dummyDriveReversalDelay").value === "") $("dummyDriveReversalDelay").value = "0";
        if ($("dummyDriveReversalCount").value === "") $("dummyDriveReversalCount").value = "1";
    }

    $("dummyCounterDetails").hidden = $("dummyCounterType").value !== "3";
    $("dummyDriveReversalDetails").hidden = $("dummyDriveReversalType").value !== "3";
    if (fillDefaults && $("dummyCounterType").value === "3") {
        for (const id of [
            "dummyCounterWeightNormal",
            "dummyCounterWeightCounter",
            "dummyCounterWeightPunish"
        ]) {
            if ($(id).value === "") $(id).value = "1";
        }
    }
    if (fillDefaults && $("dummyDriveReversalType").value === "3") {
        for (const id of [
            "dummyDriveReversalWeightNone",
            "dummyDriveReversalWeightGuard",
            "dummyDriveReversalWeightWakeup"
        ]) {
            if ($(id).value === "") $(id).value = "1";
        }
    }
    updateDummyMenuVisualState();
}

/* recorded_by: 0 = P1 录制 / 1 = P2 录制；录制方即连段角色（攻击方），另一方为木人。 */
function attackerSide() {
    const first = state.selected?.document?.[0] || {};
    const recordedBy = Number(first.scene_state?.recorded_by ?? first.recorded_by ?? 0);
    return recordedBy === 1 ? "p2" : "p1";
}

function sideLabel(side) {
    return side === attackerSide() ? "连段角色" : "木人";
}

/* 斗气 / 必杀量表：JSON 存储 = 格数 × 10000；界面按格数显示。
   旧版数据可能直接按格数记录（≤6 且非 10000 整数倍），按格数原样显示以便自动修复。 */
function gaugeToBars(value) {
    if (value === undefined || value === null || value === "") return "";
    const number = Number(value);
    if (!Number.isFinite(number)) return "";
    if (number % 10000 !== 0 && number > 0 && number <= 6) return String(number);
    return String(number / 10000);
}

function getScenePlayer(model, side) {
    return model.scene_state?.players?.[side] || {};
}

function renderSelected() {
    const record = state.selected;
    if (!record) return;
    const model = metadataModel(record.document);
    const meta = record.document[0]._xt_meta || {};
    $("currentPath").textContent = record.path;
    $("title").value = model.title;
    $("author").value = model.author;
    $("character").value = model.character;
    setSelectValue("language", model.language, "und");
    setSelectValue("controlMode", model.control_mode, "unknown");
    $("category").value = model.category;
    setSelectValue("rating", model.rating, "");
    $("createdAt").value = model.created_at;
    $("updatedAt").value = model.updated_at;
    $("tags").value = model.tags.join(", ");
    $("note").value = model.note;
    const comboStats = record.document[0]?.combo_stats || {};
    $("resultDamage").textContent = comboStats.damage ?? "未记录 (Not recorded)";
    $("resultDriveUsed").textContent = gaugeToBars(comboStats.drive_used)
        || "未记录 (Not recorded)";
    $("resultSuperUsed").textContent = gaugeToBars(comboStats.super_used)
        || (comboStats.super_used === 0 ? "0" : "未记录 (Not recorded)");
    $("resultHitType").textContent = comboStats.hit_type ?? "未记录 (Not recorded)";
    $("metaSchema").textContent = String(meta.schema ?? "缺失 (missing)");
    $("jsonVersion").textContent = meta.versions?.json?.version || "缺失 (missing)";
    $("recorderVersion").textContent = [
        meta.versions?.recorder?.id,
        meta.versions?.recorder?.version
    ].filter(Boolean).join("/") || "未知 (unknown)";
    $("frameworkVersion").textContent = [
        meta.versions?.framework?.id,
        meta.versions?.framework?.version
    ].filter(Boolean).join("/") || "未知 (unknown)";

    const env = model.environment || {};
    const envActionType = env.dummy_action_type ?? meta.dummy_action_type;
    const envStance = env.dummy_stance ?? meta.dummy_stance;
    let dummyAction = "0";
    if (envActionType !== undefined && envActionType !== null && envActionType !== "") {
        const actionNumber = Number(envActionType);
        if ([0, 1, 2].includes(actionNumber)) dummyAction = String(actionNumber);
    } else {
        const stanceText = String(envStance || "").toLowerCase();
        dummyAction = {
            stand: "0", standing: "0",
            crouch: "1", crouching: "1",
            jump: "2", jumping: "2", airborne: "2"
        }[stanceText] || "0";
    }
    setSelectValue("dummyControl", "dummy", "dummy");
    setSelectValue("dummyAction", dummyAction, "0");
    setValue("dummyJumpKind", env.dummy_jump_type ?? meta.dummy_jump_type ?? 0);
    setSelectValue("dummyCounterType", env.dummy_counter_type ?? meta.dummy_counter_type, "");
    setValue("dummyCounterWeightNormal", env.dummy_counter_weight_normal ?? meta.dummy_counter_weight_normal);
    setValue("dummyCounterWeightCounter", env.dummy_counter_weight_counter ?? meta.dummy_counter_weight_counter);
    setValue("dummyCounterWeightPunish", env.dummy_counter_weight_punish ?? meta.dummy_counter_weight_punish);
    setSelectValue("dummyGuardType", env.dummy_guard_type ?? meta.dummy_guard_type, "");
    setSelectValue("dummyGuardCount", env.dummy_guard_count ?? meta.dummy_guard_count, "");
    setSelectValue("dummyGuardSwitchMode", env.dummy_guard_only_type ?? meta.dummy_guard_only_type, "");
    setSelectValue("dummyGuardKind", env.dummy_drive_parry_type ?? meta.dummy_drive_parry_type, "");
    setSelectValue("dummyDriveReversalType", env.dummy_drive_reversal_type ?? meta.dummy_drive_reversal_type, "");
    setSelectValue("dummyDriveReversalDelay", env.dummy_drive_reversal_delay ?? meta.dummy_drive_reversal_delay, "");
    setSelectValue("dummyDriveReversalCount", env.dummy_drive_reversal_count ?? meta.dummy_drive_reversal_count, "");
    setValue("dummyDriveReversalWeightNone", env.dummy_drive_reversal_weight_none ?? meta.dummy_drive_reversal_weight_none);
    setValue("dummyDriveReversalWeightGuard", env.dummy_drive_reversal_weight_guard ?? meta.dummy_drive_reversal_weight_guard);
    setValue("dummyDriveReversalWeightWakeup", env.dummy_drive_reversal_weight_wakeup ?? meta.dummy_drive_reversal_weight_wakeup);
    setSelectValue("dummyThrowEscapeType", env.dummy_throw_escape_type ?? meta.dummy_throw_escape_type, "");
    setSelectValue("dummyWakeupType", env.dummy_wakeup_type ?? meta.dummy_wakeup_type, "");
    syncDummyMenuState();

    $("p1SideLabel").textContent = `${sideLabel("p1")} (P1)`;
    $("p2SideLabel").textContent = `${sideLabel("p2")} (P2)`;
    /* 左栏固定按“连段角色 → 木人”排列；右栏独立展示训练菜单。 */
    const comboSide = attackerSide();
    const dummySide = comboSide === "p1" ? "p2" : "p1";
    $("scenePlayerStack").append(
        $(`${comboSide}ScenePanel`),
        $(`${dummySide}ScenePanel`)
    );

    for (const side of ["p1", "p2"]) {
        const prefix = side;
        const player = getScenePlayer(model, side);
        setSelectValue(`${prefix}FighterId`, player.fighter_id, "");
        setValue(`${prefix}Hp`, player.resources?.hp);
        setValue(`${prefix}Drive`, gaugeToBars(player.resources?.drive));
        setValue(`${prefix}Super`, gaugeToBars(player.resources?.super));
        // 虚损双侧均可编辑（1P 虚损运行时有效），无“清空”：未记录时默认“否”；
        // 眩晕 / 姿态仅记录，已从表单隐藏并保留 JSON 原值
        setSelectValue(`${prefix}Burnout`, triState(player.status?.burnout), "false");
        renderUniqueResourceEditor(prefix, player.fighter_id, player.unique);
    }
    // UniqueData is shared when both sides use the same fighter. Prefer the
    // recorded combo actor when a legacy file contains conflicting values.
    syncSharedUniqueResources(attackerSide());
    /* 连段角色（录制方）的角色由 JSON 固定，不允许在编辑器中更改；木人侧可换角色 */
    const attacker = attackerSide();
    for (const side of ["p1", "p2"]) {
        $(`${side}FighterId`).disabled = side === attacker;
    }
    renderStepNotes(model.step_notes);
    renderMechanism(record.document);
    $("rawJson").textContent = serializeComboJson(record.document);
    renderCurrentStatus();
}

function setSelectValue(id, value, fallback) {
    const select = $(id);
    /* 空串同样视为未记录：无“清空”选项的控件（木人动作/防御/虚损/开关资源）会落到默认值 */
    const text = value === undefined || value === null || value === "" ? fallback : String(value);
    if (![...select.options].some(option => option.value === text) && text !== "") {
        const option = new Option(text, text);
        select.add(option);
    }
    select.value = text;
    renderChoiceBoxes(select);
}

function renderCurrentStatus() {
    const record = state.selected;
    const badges = [];
    badges.push(`<span class="badge ${isLegacy(record) ? "warn" : "ok"}">${isLegacy(record) ? "待升级 (Upgrade required)" : "规范 (schema) 2"}</span>`);
    badges.push(`<span class="badge">${record.document.length} 步 (steps)</span>`);
    const scene = record.document[0].scene_state;
    if (scene) badges.push(`<span class="badge">${escapeHtml(scene.schema || "scene")}</span>`);
    if (record.changed) badges.push(`<span class="badge changed">未保存修改 (Unsaved)</span>`);
    for (const warning of record.warnings.slice(0, 3)) {
        badges.push(`<span class="badge warn" title="${escapeHtml(warning)}">警告 (Warning)</span>`);
    }
    $("currentStatus").innerHTML = badges.join("");
}

function renderStepNotes(notes) {
    const fragment = document.createDocumentFragment();
    const steps = state.selected.document;
    notes.forEach((note, index) => {
        const row = document.createElement("label");
        row.className = "step-note";
        row.innerHTML = `<span class="index">#${index + 1}</span><code>${escapeHtml(steps[index]?.motion || "")}</code>`;
        const input = document.createElement("input");
        input.value = note;
        input.dataset.stepNote = String(index);
        row.append(input);
        fragment.append(row);
    });
    $("stepNotes").replaceChildren(fragment);
    $("stepCount").textContent = `${notes.length} 个步骤 (steps)`;
}

function renderMechanism(document) {
    const totalDamage = document[0]?.combo_stats?.damage;
    $("mechanismSummary").textContent = totalDamage === undefined || totalDamage === null
        ? "总伤害 (Total damage)：未记录"
        : `总伤害 (Total damage)：${totalDamage}`;
    $("mechanismRows").innerHTML = document.map((step, index) => `
        <tr>
            <td>${index + 1}</td>
            <td>${escapeHtml(step.id ?? "")}</td>
            <td>${escapeHtml(step.motion ?? "")}</td>
            <td>${escapeHtml(step.delay_from_prev ?? "")}</td>
            <td>${escapeHtml(step.expected_combo ?? "")}</td>
            <td>${escapeHtml(step.damage_at_step ?? "")}</td>
            <td>${escapeHtml(step.expected_hp ?? "")}</td>
            <td>${escapeHtml(step.counter_type ?? "")}</td>
            <td>${escapeHtml(step.group_id ?? "")}</td>
        </tr>
    `).join("");
}

function parseOptionalNumber(id) {
    const text = $(id).value.trim();
    if (text === "") return "";
    const value = Number(text);
    if (!Number.isFinite(value)) throw new Error(`${id} 不是有效数字 (not a valid number)`);
    return value;
}

function parseTriState(id) {
    const value = $(id).value;
    if (value === "") return "";
    return value === "true";
}

function collectSide(prefix) {
    const resources = {
        hp: parseOptionalNumber(`${prefix}Hp`),
        drive: parseOptionalNumber(`${prefix}Drive`),
        super: parseOptionalNumber(`${prefix}Super`)
    };
    // 界面按格显示，写入 JSON 时换算为 ×10000
    if (resources.drive !== "") resources.drive *= 10000;
    if (resources.super !== "") resources.super *= 10000;
    // 虚损双侧采集；眩晕 / 姿态不采集（表单已隐藏，保留 JSON 原值）
    const status = { burnout: parseTriState(`${prefix}Burnout`) };
    return {
        fighter_id: parseOptionalNumber(`${prefix}FighterId`),
        resources,
        status,
        unique: collectUnique(prefix)
    };
}

/* 编辑器只公开原生陪练的站 / 蹲 / 跳；玩家控制、CPU、播放录制均不属于连段环境编辑范围。 */
function collectDummyEnvironment() {
    const action = $("dummyAction").value;
    const values = {
        dummy_stance: "",
        dummy_action_type: "",
        dummy_jump_type: "",
        requires_dummy_crouch: ""
    };
    if (action === "0") {
        values.dummy_stance = "stand";
        values.dummy_action_type = 0;
        values.dummy_jump_type = 0;
        values.requires_dummy_crouch = false;
    } else if (action === "1") {
        values.dummy_stance = "crouch";
        values.dummy_action_type = 1;
        values.dummy_jump_type = 0;
        values.requires_dummy_crouch = true;
    } else if (action === "2") {
        values.dummy_stance = "jump";
        values.dummy_action_type = 2;
        values.dummy_jump_type = parseOptionalNumber("dummyJumpKind");
        values.requires_dummy_crouch = false;
    }

    values.dummy_counter_type = parseOptionalNumber("dummyCounterType");
    values.dummy_counter_weight_normal = parseOptionalNumber("dummyCounterWeightNormal");
    values.dummy_counter_weight_counter = parseOptionalNumber("dummyCounterWeightCounter");
    values.dummy_counter_weight_punish = parseOptionalNumber("dummyCounterWeightPunish");
    values.dummy_guard_type = parseOptionalNumber("dummyGuardType");
    values.dummy_guard_count = values.dummy_guard_type === 5
        ? parseOptionalNumber("dummyGuardCount")
        : "";
    /* 游戏菜单“格挡切换”对应 GuardOnlyType；“格挡种类”对应 DefenseSystem.DP_Type。
       IsGuardSwitching 是录制得到的底层布尔状态，编辑器不再误作枚举覆盖。 */
    values.dummy_guard_only_type = parseOptionalNumber("dummyGuardSwitchMode");
    values.dummy_drive_parry_type = parseOptionalNumber("dummyGuardKind");
    values.dummy_drive_reversal_type = parseOptionalNumber("dummyDriveReversalType");
    values.dummy_drive_reversal_delay = parseOptionalNumber("dummyDriveReversalDelay");
    values.dummy_drive_reversal_count = parseOptionalNumber("dummyDriveReversalCount");
    values.dummy_drive_reversal_weight_none = parseOptionalNumber("dummyDriveReversalWeightNone");
    values.dummy_drive_reversal_weight_guard = parseOptionalNumber("dummyDriveReversalWeightGuard");
    values.dummy_drive_reversal_weight_wakeup = parseOptionalNumber("dummyDriveReversalWeightWakeup");
    values.dummy_throw_escape_type = parseOptionalNumber("dummyThrowEscapeType");
    values.dummy_wakeup_type = parseOptionalNumber("dummyWakeupType");
    return values;
}

function hasSceneValues(side) {
    return side.fighter_id !== ""
        || Object.values(side.resources).some(value => value !== "")
        || Object.values(side.status).some(value => value !== "")
        || side.unique !== null;
}

function collectEdits() {
    const p1 = collectSide("p1");
    const p2 = collectSide("p2");
    const edits = {
        title: $("title").value,
        author: $("author").value,
        character: $("character").value,
        language: $("language").value,
        control_mode: $("controlMode").value,
        category: $("category").value,
        rating: $("rating").value,
        created_at: $("createdAt").value,
        tags: $("tags").value,
        note: $("note").value,
        step_notes: [...document.querySelectorAll("[data-step-note]")].map(input => input.value),
        environment: collectDummyEnvironment()
    };
    if (state.selected.document[0].scene_state || hasSceneValues(p1) || hasSceneValues(p2)) {
        edits.scene = {
            recorded_by: state.selected.document[0].scene_state?.recorded_by
                ?? state.selected.document[0].recorded_by
                ?? 0
        };
        if (state.selected.document[0].scene_state?.players?.p1 || hasSceneValues(p1)) edits.scene.p1 = p1;
        if (state.selected.document[0].scene_state?.players?.p2 || hasSceneValues(p2)) edits.scene.p2 = p2;
    }
    return edits;
}

function applyCurrentForm() {
    const record = state.selected;
    if (!record) return false;
    try {
        record.document = applyMetadataEdits(record.document, collectEdits());
        record.changed = serializeComboJson(record.document) !== record.originalText;
        record.warnings = validateComboDocument(record.document).warnings;
        renderSelected();
        renderFileList();
        updateSummary();
        toast("表单修改已应用到工作副本 (Applied to working copy)");
        return true;
    } catch (error) {
        toast(`无法应用 (Cannot apply): ${error.message}`, true);
        return false;
    }
}

function upgradeRecord(record, timestamp) {
    const migration = migrateComboDocument(record.document, {
        relativePath: record.path,
        timestamp
    });
    record.document = migration.document;
    record.changed = serializeComboJson(record.document) !== record.originalText;
    record.warnings = validateComboDocument(record.document).warnings;
}

function upgradeCurrent() {
    if (!state.selected) return;
    try {
        upgradeRecord(state.selected, new Date().toISOString());
        renderSelected();
        renderFileList();
        updateSummary();
        toast("当前文件已升级到 JSON v2 工作副本 (Upgraded)");
    } catch (error) {
        toast(error.message, true);
    }
}

function upgradeAll() {
    const timestamp = new Date().toISOString();
    let count = 0;
    try {
        for (const record of state.records) {
            if (record.error) continue;
            const wasChanged = record.changed;
            upgradeRecord(record, timestamp);
            if (!wasChanged && record.changed) count += 1;
        }
        renderFileList();
        updateSummary();
        if (state.selected) renderSelected();
        toast(`已升级 ${count} 个文件的工作副本 (Upgraded)`);
    } catch (error) {
        toast(error.message, true);
    }
}

function applyBatchVersions() {
    const scope = $("batchScope").value === "filtered" ? filteredRecords() : state.records;
    const profile = {
        gameId: $("batchGameId").value.trim(),
        gameVersion: $("batchGameVersion").value.trim(),
        recorderId: $("batchRecorderId").value.trim(),
        recorderVersion: $("batchRecorderVersion").value.trim(),
        frameworkId: $("batchFrameworkId").value.trim(),
        frameworkVersion: $("batchFrameworkVersion").value.trim()
    };
    const timestamp = new Date().toISOString();
    const metadataProfile = {};
    if ($("batchLanguageEnabled").checked) metadataProfile.language = $("batchLanguage").value;
    if ($("batchControlEnabled").checked) metadataProfile.controlMode = $("batchControlMode").value;
    let count = 0;
    try {
        for (const record of scope) {
            if (record.error) continue;
            record.document = migrateComboDocument(record.document, {
                relativePath: record.path,
                timestamp,
                versionProfile: profile,
                metadataProfile
            }).document;
            record.changed = serializeComboJson(record.document) !== record.originalText;
            record.warnings = validateComboDocument(record.document).warnings;
            count += 1;
        }
        $("batchDialog").close();
        renderFileList();
        updateSummary();
        if (state.selected) renderSelected();
        toast(`已对 ${count} 个文件应用安全批量字段 (Batch edit applied)`);
    } catch (error) {
        toast(error.message, true);
    }
}

async function writeRecord(record) {
    if (!record.fileHandle) throw new Error("当前记录没有可写文件句柄 (No writable file handle)");
    const writable = await record.fileHandle.createWritable();
    await writable.write(serializeComboJson(record.document));
    await writable.close();
    record.originalText = serializeComboJson(record.document);
    record.changed = false;
}

/* 保存前检查：数值单位错误 / 不受支持的状态 */
function preflightCheck() {
    const issues = [];
    for (const side of ["p1", "p2"]) {
        const label = `${sideLabel(side)} (${side.toUpperCase()})`;
        const hp = parseOptionalNumber(`${side}Hp`);
        if (hp !== "" && (hp < 0 || hp > 10000)) {
            issues.push(`${label} 生命 ${hp} 超出 0–10000 范围（数值单位错误）`);
        }
        const drive = parseOptionalNumber(`${side}Drive`);
        if (drive !== "" && (drive < 0 || drive > 6)) {
            issues.push(`${label} 斗气 ${drive} 格超出 0–6 格范围（数值单位错误）`);
        }
        const burnout = $(`${side}Burnout`).value;
        if (drive === 0 && burnout === "false") {
            issues.push(`${label} 斗气为 0 格但虚损为否，这是游戏中无法保持的矛盾状态；斗气写入后会立即重新虚损`);
        }
        const sa = parseOptionalNumber(`${side}Super`);
        if (sa !== "" && (sa < 0 || sa > 3)) {
            issues.push(`${label} 必杀技量表 ${sa} 格超出 0–3 格范围（数值单位错误）`);
        }
    }
    if ($("dummyGuardType").value === "5") {
        const guardCount = parseOptionalNumber("dummyGuardCount");
        if (guardCount === "" || guardCount < 1 || guardCount > 30) {
            issues.push("计数格挡需要 1–30 的格挡计数 (dummy_guard_count)");
        }
    }
    const model = metadataModel(state.selected.document);
    for (const side of ["p1", "p2"]) {
        const player = model.scene_state?.players?.[side];
        const label = `${sideLabel(side)} (${side.toUpperCase()})`;
        for (const [field, name, max] of [["drive", "斗气", 6], ["super", "必杀技量表", 3]]) {
            const raw = player?.resources?.[field];
            if (raw === undefined || raw === null || raw === "") continue;
            const number = Number(raw);
            if (Number.isFinite(number) && number % 10000 !== 0) {
                issues.push(`${label} ${name}记录值 ${raw} 不是 10000 的整数倍（数值单位错误），已按旧版格数（≤${max}）显示，保存时将自动换算 ×10000`);
            }
        }
        if (player?.status?.stunned === true) {
            issues.push(`${label} 眩晕为仅记录状态，该字段会写入JSON，但当前SF6CC运行时不会应用（不受支持的状态）`);
        }
    }
    return issues;
}

async function saveCurrent() {
    if (!state.selected) return;
    let issues;
    try {
        issues = preflightCheck();
    } catch (error) {
        toast(`保存前检查失败 (Preflight failed): ${error.message}`, true);
        return;
    }
    if (issues.length && !confirm(
        `保存前检查发现 ${issues.length} 个问题 (Preflight issues):\n\n• ${issues.join("\n• ")}\n\n仍要继续保存吗？ (Save anyway?)`
    )) return;
    if (!applyCurrentForm()) return;
    if (!state.selected.fileHandle) {
        downloadRecord(state.selected);
        return;
    }
    try {
        await writeRecord(state.selected);
        renderSelected();
        renderFileList();
        updateSummary();
        toast("当前文件已原地保存 (Saved in place)");
    } catch (error) {
        toast(`保存失败 (Save failed): ${error.message}`, true);
    }
}

async function saveAll() {
    if (!state.rootHandle) return;
    const changed = state.records.filter(record => record.changed && record.fileHandle);
    if (!changed.length) return;
    if (!confirm(`将原地覆盖 ${changed.length} 个 JSON。确定继续？ (Overwrite ${changed.length} JSON files in place?)`)) return;
    try {
        for (const record of changed) await writeRecord(record);
        renderFileList();
        updateSummary();
        if (state.selected) renderSelected();
        toast(`已原地保存 ${changed.length} 个文件 (Saved in place)`);
    } catch (error) {
        toast(`批量保存中断 (Batch save stopped): ${error.message}`, true);
    }
}

function downloadRecord(record) {
    const blob = new Blob([serializeComboJson(record.document)], { type: "application/json;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = record.name;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
}

async function getOrCreateDirectory(root, segments) {
    let current = root;
    for (const segment of segments) current = await current.getDirectoryHandle(segment, { create: true });
    return current;
}

async function exportAll() {
    if (!window.showDirectoryPicker) {
        toast("当前浏览器不支持目录导出，请逐个下载 (Directory export is unsupported).", true);
        return;
    }
    const changed = state.records.filter(record => record.changed && !record.error);
    if (!changed.length) return;
    try {
        const target = await window.showDirectoryPicker({ mode: "readwrite" });
        for (const record of changed) {
            const parts = record.path.split("/");
            const fileName = parts.pop();
            const directory = await getOrCreateDirectory(target, parts);
            const handle = await directory.getFileHandle(fileName, { create: true });
            const writable = await handle.createWritable();
            await writable.write(serializeComboJson(record.document));
            await writable.close();
        }
        toast(`已导出 ${changed.length} 个修改文件 (Exported)`);
    } catch (error) {
        if (error.name !== "AbortError") toast(error.message, true);
    }
}

$("openDirectory").onclick = openDirectory;
$("openFiles").onclick = () => $("fileInput").click();
$("fileInput").onchange = () => openFiles($("fileInput").files);
$("search").oninput = event => { state.filter = event.target.value.trim().toLowerCase(); renderFileList(); };
$("characterFilter").onchange = event => { state.characterFolder = event.target.value; renderFileList(); };
$("statusFilter").onchange = event => { state.status = event.target.value; renderFileList(); };
$("upgradeCurrent").onclick = upgradeCurrent;
$("upgradeAll").onclick = upgradeAll;
$("batchVersions").onclick = () => $("batchDialog").showModal();
$("applyBatchVersions").onclick = applyBatchVersions;
$("applyCurrent").onclick = applyCurrentForm;
$("saveCurrent").onclick = saveCurrent;
$("saveAll").onclick = saveAll;
$("downloadCurrent").onclick = () => state.selected && downloadRecord(state.selected);
$("exportAll").onclick = exportAll;
$("copyJson").onclick = async () => {
    if (!state.selected) return;
    await navigator.clipboard.writeText(serializeComboJson(state.selected.document));
    toast("JSON 已复制 (Copied)");
};

populateFighterSelect("p1FighterId");
populateFighterSelect("p2FighterId");
populateNumericSelect("dummyGuardCount", 1, 30, value => `${value} 次 (${value} times)`);
populateNumericSelect("dummyDriveReversalDelay", 0, 99, value => `${value} 帧 (${value} frames)`);
populateNumericSelect("dummyDriveReversalCount", 1, 30, value => `${value} 次 (${value} times)`);
for (const [id, variant] of [
    ["statusFilter", "compact"],
    ["rating", "stars"],
    ["p1Burnout", "compact"],
    ["p2Burnout", "compact"],
    ["batchScope", "compact"],
    ["batchLanguage", "compact"],
    ["batchControlMode", "compact"]
]) {
    if (variant === "stars") enhanceStarRating($(id));
    else enhanceChoiceSelect($(id), variant);
}
for (const id of DUMMY_MENU_SELECT_IDS) {
    enhanceStepperSelect($(id));
    $(id).addEventListener("change", updateDummyMenuVisualState);
}
for (const id of DUMMY_MENU_NUMBER_IDS) {
    enhanceNumericStepper($(id));
    $(id).addEventListener("input", updateDummyMenuVisualState);
    $(id).addEventListener("change", updateDummyMenuVisualState);
}
$("p1FighterId").addEventListener("change", () => changeFighter("p1"));
$("p2FighterId").addEventListener("change", () => changeFighter("p2"));
for (const id of [
    "dummyAction",
    "dummyCounterType",
    "dummyGuardType",
    "dummyDriveReversalType"
]) {
    $(id).addEventListener("change", () => syncDummyMenuState(true));
}
/* 虚损与斗气双向联动：是 = 0 格，否 = 6 格。 */
for (const side of ["p1", "p2"]) {
    $(`${side}Burnout`).addEventListener("change", () => {
        $(`${side}Drive`).value = $(`${side}Burnout`).value === "true" ? "0" : "6";
    });
}

/* 数值快捷按钮：点击直接写入对应数值输入框（仍走既有表单应用/保存路径）。
   生命按 SF6 满血 10000 计算百分比档位。 */
function renderQuickSets(containerId, inputId, sets) {
    const container = $(containerId);
    const input = $(inputId);
    if (!container || !input) return;
    container.replaceChildren(...sets.map(([label, value]) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "quick-set";
        button.textContent = label;
        button.onclick = event => {
            event.preventDefault();
            input.value = String(value);
            input.dispatchEvent(new Event("input", { bubbles: true }));
            input.dispatchEvent(new Event("change", { bubbles: true }));
        };
        return button;
    }));
}
for (const side of ["p1", "p2"]) {
    renderQuickSets(`${side}HpQuick`, `${side}Hp`, [["20%", 2000], ["100%", 10000]]);
    renderQuickSets(`${side}DriveQuick`, `${side}Drive`, [1, 2, 3, 4, 5, 6].map(n => [String(n), n]));
    renderQuickSets(`${side}SuperQuick`, `${side}Super`, [1, 2, 3].map(n => [String(n), n]));
}

for (const button of document.querySelectorAll(".tabs button")) {
    button.onclick = () => {
        document.querySelectorAll(".tabs button").forEach(node => node.classList.toggle("active", node === button));
        document.querySelectorAll(".tab-panel").forEach(panel => panel.classList.toggle("active", panel.dataset.panel === button.dataset.tab));
    };
}
