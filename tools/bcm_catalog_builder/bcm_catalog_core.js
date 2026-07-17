(function (root, factory) {
    const api = factory();
    if (typeof module === "object" && module.exports) module.exports = api;
    root.SF6CCBcmCatalog = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
    "use strict";

    const OUTPUT_SCHEMA = "sf6cc.bcm-catalog.v1";
    const PROFILE_NAMES = ["norm", "easy", "sprt", "supr"];
    const FIGHTER_NAMES = {
        1: "Ryu", 2: "Luke", 3: "Kimberly", 4: "ChunLi", 5: "Manon", 6: "Zangief",
        7: "JP", 8: "Dhalsim", 9: "Cammy", 10: "Ken", 11: "DeeJay", 12: "Lily",
        13: "AKI", 14: "Rashid", 15: "Blanka", 16: "Juri", 17: "Marisa", 18: "Guile",
        19: "Ed", 20: "EHonda", 21: "Jamie", 22: "Akuma", 25: "Sagat", 26: "MBison",
        27: "Terry", 28: "Mai", 29: "Elena", 30: "CViper", 31: "Alex", 32: "Ingrid"
    };
    const DIR_MAP = {
        0: "5", 1: "8", 2: "2", 4: "4", 5: "7",
        6: "1", 8: "6", 9: "9", 10: "3", 15: "*"
    };
    const BUTTONS = [
        [16, "LP"], [32, "MP"], [64, "HP"],
        [128, "LK"], [256, "MK"], [512, "HK"]
    ];
    const ASSIST_COMBO_STRENGTHS = ["弱", "强", "中"];
    const ASSIST_COMBO_STRENGTH_BLOCK = 80;
    const ASSIST_COMBO_RECIPE_LENGTH = 10;

    function parseSourceText(text) {
        text = String(text || "").replace(/^\uFEFF/, "");
        let output = "", inString = false, escaped = false;
        for (let index = 0; index < text.length;) {
            const char = text[index];
            if (inString) {
                output += char;
                if (escaped) escaped = false;
                else if (char === "\\") escaped = true;
                else if (char === '"') inString = false;
                index += 1;
                continue;
            }
            if (char === '"') {
                inString = true; output += char; index += 1; continue;
            }
            if (char === "-" || (char >= "0" && char <= "9")) {
                let end = index + 1;
                while (end < text.length && /[0-9eE+\-.]/.test(text[end])) end += 1;
                const token = text.slice(index, end);
                if (/^-?\d{16,}$/.test(token) && (BigInt(token) > BigInt(Number.MAX_SAFE_INTEGER) || BigInt(token) < BigInt(Number.MIN_SAFE_INTEGER))) {
                    output += `"${token}"`;
                } else output += token;
                index = end;
                continue;
            }
            output += char; index += 1;
        }
        return JSON.parse(output);
    }

    function lowBits(value, mask) {
        if (typeof value === "string" && /^-?\d+$/.test(value)) return Number(BigInt(value) & BigInt(mask));
        return Number(value || 0) & mask;
    }

    function valueOf(value) {
        if (!value || typeof value !== "object") return value;
        if (Object.prototype.hasOwnProperty.call(value, "value")) return value.value;
        if (Object.prototype.hasOwnProperty.call(value, "object_id")) return value.object_id;
        return null;
    }

    function fieldsOf(object) {
        const result = {};
        for (const field of (object && object.fields) || []) {
            result[field.name] = valueOf(field.value);
        }
        return result;
    }

    function refId(value) {
        return value && value.kind === "ref" ? value.object_id : null;
    }

    function collectionRefs(object) {
        return ((object && object.items) || []).map(item => refId(item.value));
    }

    function decodeButtons(mask, conditionMask) {
        const buttonCount = ((Number(conditionMask || 0) >> 6) & 3) + 1;
        mask = Number(mask || 0);
        if (mask === 144) return "Throw";
        if (mask === 288) return "Parry";
        if (mask === 576) return "DI";
        if (mask === 112) return buttonCount === 3 ? "PPP" : (buttonCount === 2 ? "PP" : "P");
        if (mask === 896) return buttonCount === 3 ? "KKK" : (buttonCount === 2 ? "KK" : "K");
        return BUTTONS.filter(([bit]) => (mask & bit) !== 0).map(([, name]) => name).join("+");
    }

    function normalizeMotion(raw) {
        let normalized = String(raw || "");
        // BCM stores repeated taps with the neutral frames between them
        // (for example 5,2,5,2).  The player-facing notation is 22, 66 or 44.
        if (/^(?:5?([124689]))(?:5?\1)+$/.test(normalized)) {
            normalized = normalized.replace(/5/g, "");
        }
        return normalized
            .replace(/23626/g, "236236")
            .replace(/21424/g, "214214")
            .replace(/626/g, "623")
            .replace(/424/g, "421")
            .replace(/6314/g, "63214")
            .replace(/4136/g, "41236");
    }

    function formatChargeMotion(notation) {
        const opposite = { 6: "4", 8: "2", 4: "6", 2: "8", 9: "1", 3: "7" };
        if (notation.length === 2 && opposite[notation[1]]) return `[${opposite[notation[1]]}]${notation[1]}`;
        return notation;
    }

    function buildObjectIndex(source) {
        const objects = new Map();
        for (const object of source.objects || []) objects.set(object.object_id, object);
        return objects;
    }

    function decodeCommand(commandObject, objects, commandNo, variantIndex) {
        if (!commandObject) return null;
        const fields = fieldsOf(commandObject);
        const inputArray = objects.get(fields.inputs);
        const refs = collectionRefs(inputArray);
        const inputCount = Math.max(0, Number(fields.input_num || 0));
        const inputs = [];
        let hasCharge = Number(fields.charge_bit || 0) !== 0;

        for (const inputRef of refs.slice(0, inputCount)) {
            const input = objects.get(inputRef);
            const inputFields = fieldsOf(input);
            const normalFields = fieldsOf(objects.get(inputFields.normal));
            const chargeFields = fieldsOf(objects.get(inputFields.charge));
            const mask = Number(normalFields.ok_key_flags || 0);
            const inputType = Number(inputFields.type || 0);
            const chargeId = Number(chargeFields.id || 0);
            const chargeRelease = chargeFields.is_release === true;
            // Full-circle commands are stored as one exact 0x40001 release-style
            // input. Treating its low direction nibble alone as an ordinary 8
            // turns the 360 motion into a misleading 8.
            const fullCircle = inputType === 2 && mask === 0x40001
                && chargeId === 1 && chargeRelease;
            // Double full-circle commands use a second exact release-style
            // signature. Its low nibble is neutral, so generic direction
            // decoding would incorrectly expose N/5 instead of 720.
            const doubleFullCircle = inputType === 2 && mask === 0x70000
                && chargeId === 0 && chargeRelease;
            const direction = doubleFullCircle ? "720"
                : (fullCircle ? "360" : (DIR_MAP[lowBits(mask, 0xF)] || "5"));
            // charge.id mirrors the direction on ordinary inputs as well; it
            // is not sufficient evidence of a charge command.  Real charge
            // steps are identified by the command bit or charge input type.
            if (inputType === 1 || chargeRelease) hasCharge = true;
            inputs.push({
                direction,
                raw_mask: mask,
                frames: Number(inputFields.frame_num || 0),
                type: inputType,
                charge_id: chargeId,
                charge_release: chargeRelease
            });
        }

        let motion = normalizeMotion(inputs.map(input => input.direction).join(""));
        if (hasCharge) motion = formatChargeMotion(motion);
        return {
            command_no: commandNo,
            variant_index: variantIndex,
            notation: motion,
            input_count: inputCount,
            max_frame: Number(fields.max_frame || 0),
            total_frame: Number(fields.total_frame || -1),
            charge_bit: Number(fields.charge_bit || 0),
            inputs
        };
    }

    function decodeCommandTable(source, objects, warnings) {
        const rootId = refId(source.command_root_ref);
        const root = objects.get(rootId);
        if (!root) throw new Error("找不到 command_root_ref 指向的 BCM 指令根对象。");
        const table = {};
        for (const item of root.items || []) {
            const commandNo = Number(item.index);
            const array = objects.get(refId(item.value));
            if (!array) continue;
            const variants = [];
            for (const child of array.items || []) {
                const command = decodeCommand(objects.get(refId(child.value)), objects, commandNo, Number(child.index));
                if (command) variants.push(command);
            }
            if (variants.length) table[String(commandNo)] = variants;
        }
        if (!Object.keys(table).length) warnings.push("BCM 指令根没有生成任何有效指令。");
        return table;
    }

    function getCommandVariant(profileFields, commandTable, objects) {
        const commandNo = Number(profileFields.command_no ?? -1);
        const variantIndex = Number(profileFields.command_index ?? 0);
        const fromRoot = commandTable[String(commandNo)];
        // BCM.TRIGGER.CMD.command_index is not an index into BCM.COMMAND[]. In live
        // REFramework data the existing decoder intentionally takes the first
        // command variant for a command_no. Keep every variant in `commands`, but
        // resolve display notation with the same stable rule.
        if (commandNo >= 0 && fromRoot && fromRoot[0]) return fromRoot[0];

        const pointerObject = objects.get(profileFields.command_ptr);
        if (!pointerObject) return null;
        const refs = collectionRefs(pointerObject);
        const command = objects.get(refs[0]);
        return decodeCommand(command, objects, commandNo, 0);
    }

    function decodeProfile(name, triggerFields, objects, commandTable, isAir) {
        const profile = objects.get(triggerFields[name]);
        const fields = fieldsOf(profile);
        const disabled = triggerFields[`${name}_NG`] === true;
        const command = getCommandVariant(fields, commandTable, objects);
        const button = decodeButtons(fields.ok_key_flags, fields.ok_key_cond_flags);
        let direction = "";
        const dcDirection = lowBits(fields.dc_exc_flags, 0xF);
        const okDirection = lowBits(fields.ok_key_flags, 0xF);
        if (dcDirection !== 0 && dcDirection !== 5) direction = DIR_MAP[dcDirection] || "";
        else if (okDirection !== 0 && okDirection !== 5 && okDirection !== 15) direction = DIR_MAP[okDirection] || "";

        const motion = command && command.notation ? command.notation : direction;
        const body = motion ? `${motion}${button ? `+${button}` : ""}` : (button || "Normal");
        return {
            enabled: !disabled,
            notation: `${isAir ? "j." : ""}${body}`,
            command_no: Number(fields.command_no ?? -1),
            command_index: Number(fields.command_index ?? 0),
            ok_key_flags: Number(fields.ok_key_flags || 0),
            ok_key_cond_flags: Number(fields.ok_key_cond_flags || 0),
            dc_exc_flags: Number(fields.dc_exc_flags || 0),
            ng_key_flags: Number(fields.ng_key_flags || 0),
            preceding_time: Number(fields.preceding_time || 0),
            button,
            command
        };
    }

    function selectClassicProfile(triggerFields, profiles) {
        if (profiles.norm && profiles.norm.enabled) return "norm";
        if (triggerFields.use_sprt === true && profiles.sprt && profiles.sprt.enabled) return "sprt";
        return null;
    }

    function compactConditions(triggerFields) {
        const names = [
            "action_dir", "action_status_sub", "atck_type_bit", "category_flags", "combo_inst",
            "command_group_id", "cond_air_jump_count", "cond_atk_limit", "cond_jump_cmd_count",
            "cond_limit_shot_num", "cond_master_id", "cond_owner_state_flags", "cond_param_id",
            "cond_param_ope", "cond_param_value", "cond_range", "cond_range_param",
            "cond_vital_ope", "cond_vital_ratio", "fightstyle_flags", "focus_consume", "focus_need",
            "function_id", "gauge_consume", "gauge_need", "kind_level", "kind_sub",
            "limit_shot_category", "option_flags", "turn_around", "use_sprt", "use_super",
            "vital_consume", "vital_need"
        ];
        const result = {};
        for (const name of names) {
            if (Object.prototype.hasOwnProperty.call(triggerFields, name)) result[name] = triggerFields[name];
        }
        return result;
    }

    function decodeAssistComboRecipes(source, objects, triggerActionMap, warnings) {
        const arrays = (source.objects || []).filter(object =>
            object.object_type === "CharacterAsset.AssistComboRecipeData.ComboData[,,]");
        if (!arrays.length) return [];
        if (arrays.length !== 1 || !Array.isArray(arrays[0].items)
            || arrays[0].items.length !== ASSIST_COMBO_STRENGTHS.length * ASSIST_COMBO_STRENGTH_BLOCK) {
            warnings.push("AssistComboRecipeData 不是受支持的固定 3x8x10 结构，已跳过辅助连段解码。");
            return [];
        }
        const rows = [];
        for (const item of arrays[0].items) {
            const flatIndex = Number(item.index);
            const combo = objects.get(refId(item.value));
            if (!combo || !Number.isInteger(flatIndex) || flatIndex < 0
                || flatIndex >= ASSIST_COMBO_STRENGTHS.length * ASSIST_COMBO_STRENGTH_BLOCK) continue;
            const fields = fieldsOf(combo);
            const triggerId = Number(fields.TriggerID);
            const actionId = triggerActionMap.get(triggerId);
            if (!Number.isFinite(triggerId) || triggerId < 0 || !Number.isFinite(actionId)) continue;
            const strengthIndex = Math.floor(flatIndex / ASSIST_COMBO_STRENGTH_BLOCK);
            if (strengthIndex < 0 || strengthIndex >= ASSIST_COMBO_STRENGTHS.length) continue;
            const withinStrength = flatIndex % ASSIST_COMBO_STRENGTH_BLOCK;
            const recipeIndex = Math.floor(withinStrength / ASSIST_COMBO_RECIPE_LENGTH);
            const stepIndex = withinStrength % ASSIST_COMBO_RECIPE_LENGTH;
            const wt = objects.get(Number(fields.WTComboData));
            const wtFields = fieldsOf(wt);
            rows.push({
                action_id: actionId,
                trigger_id: triggerId,
                array_index: flatIndex,
                assist_strength: ASSIST_COMBO_STRENGTHS[strengthIndex],
                strength_index: strengthIndex,
                recipe_index: recipeIndex,
                step_index: stepIndex,
                input_stage: stepIndex === 0 ? "first" : "repeat",
                is_end_at_normal: fields.IsEndAtNormal === true,
                delay: Number(fields.Delay || 0),
                next_input_delay: Number(fields.NextInputDelay ?? -1),
                next_input_limit: Number(fields.NextInputLimit ?? -1),
                condition_flag: fields.ConditionFlag == null ? null : fields.ConditionFlag,
                wt_action_trigger: Number(wtFields.WTFighterActionTrigger || 0),
                wt_action_strength: Number(wtFields.WTFighterActionStrength || 0),
                wt_action_is_air: wtFields.WTFighterActionIsAir === true
            });
        }
        rows.sort((left, right) => left.array_index - right.array_index);
        return rows;
    }

    function buildCatalog(source, options) {
        options = options || {};
        if (!source || !Array.isArray(source.objects)) throw new Error("这不是包含 objects 的完整 BCM 对象图。");
        if (!Array.isArray(source.triggers)) throw new Error("这不是包含 triggers 的完整 BCM 对象图。");

        const warnings = [];
        const fighterId = Number(source.fighter_id ?? -1);
        const resolvedCharacter = options.characterName || FIGHTER_NAMES[fighterId] || source.character || "Unknown";
        if (source.character && resolvedCharacter !== source.character) {
            warnings.push(`源角色名 ${source.character} 已按 fighter_id=${fighterId} 规范化为 ${resolvedCharacter}。`);
        }
        if (source.truncated) warnings.push("源文件标记为 truncated，输出不能视为完整基础表。");
        if (source.hard_gate_passed === false) warnings.push("源文件 hard_gate_passed=false。");
        const objects = buildObjectIndex(source);
        const commandTable = decodeCommandTable(source, objects, warnings);
        const actions = {};
        const triggerActionMap = new Map();
        let decodedTriggerCount = 0;

        for (const descriptor of source.triggers) {
            const trigger = objects.get(refId(descriptor.trigger_ref));
            if (!trigger) {
                warnings.push(`trigger_index=${descriptor.trigger_index} 缺少对象。`);
                continue;
            }
            const fields = fieldsOf(trigger);
            const actionId = Number(fields.action_id ?? descriptor.native_action_id);
            if (!Number.isFinite(actionId)) continue;
            triggerActionMap.set(Number(descriptor.trigger_index), actionId);
            const isAir = Number(fields.cond_owner_state_flags || 0) === 4 ||
                (lowBits(fields.category_flags, 0x40000000) !== 0);
            const profiles = {};
            for (const name of PROFILE_NAMES) profiles[name] = decodeProfile(name, fields, objects, commandTable, isAir);
            const classicProfile = selectClassicProfile(fields, profiles);
            const entry = {
                trigger_index: Number(descriptor.trigger_index),
                classic_profile: classicProfile,
                classic_display: classicProfile ? profiles[classicProfile].notation : null,
                profiles,
                conditions: compactConditions(fields)
            };
            const key = String(actionId);
            if (!actions[key]) actions[key] = { action_id: actionId, classic_display: null, triggers: [] };
            actions[key].triggers.push(entry);
            if (!actions[key].classic_display && entry.classic_display) actions[key].classic_display = entry.classic_display;
            decodedTriggerCount += 1;
        }

        const sortedActions = {};
        for (const key of Object.keys(actions).sort((a, b) => Number(a) - Number(b))) sortedActions[key] = actions[key];
        const commandVariantCount = Object.values(commandTable).reduce((sum, variants) => sum + variants.length, 0);
        const assistComboRecipes = decodeAssistComboRecipes(source, objects, triggerActionMap, warnings);
        return {
            schema: OUTPUT_SCHEMA,
            generated_at: options.generatedAt || new Date().toISOString(),
            source: {
                schema: source.schema || null,
                character: resolvedCharacter,
                capture_character: source.character || null,
                fighter_id: fighterId,
                object_count: (source.objects || []).length,
                trigger_count: (source.triggers || []).length,
                control_mode_label: source.control_mode_label || null,
                capture_profile: source.capture_profile || null,
                sha256: options.sourceSha256 || null,
                complete: !source.truncated && source.hard_gate_passed !== false
            },
            policy: {
                classic_profile_order: ["norm", "sprt"],
                modern_profile_order: null,
                note: "现代模式选择规则尚未推断；四套 profile 原样保留供后续编译。"
            },
            stats: {
                action_count: Object.keys(sortedActions).length,
                decoded_trigger_count: decodedTriggerCount,
                command_count: Object.keys(commandTable).length,
                command_variant_count: commandVariantCount,
                assist_combo_recipe_step_count: assistComboRecipes.length,
                warning_count: warnings.length
            },
            warnings,
            commands: commandTable,
            assist_combo_recipes: assistComboRecipes,
            actions: sortedActions
        };
    }

    function buildRuntimeCatalog(catalog) {
        if (!catalog || catalog.schema !== OUTPUT_SCHEMA) throw new Error("只能从 sf6cc.bcm-catalog.v1 生成运行时基础表。");
        const actions = {};
        for (const [id, action] of Object.entries(catalog.actions || {})) {
            if (typeof action.classic_display === "string" && action.classic_display !== "") {
                // Drive Rush actions have the same physical 66 input as
                // ordinary movement. BCM exposes their semantic category and
                // Focus cost, so decode them by evidence instead of hardcoded
                // action IDs (which are character/build dependent).
                const triggers = Array.isArray(action.triggers) ? action.triggers : [];
                const isDrc = triggers.some(trigger =>
                    Number(trigger.conditions && trigger.conditions.category_flags) === 0x100000
                    && Number(trigger.conditions && trigger.conditions.function_id) === 13
                    && Number(trigger.conditions && trigger.conditions.focus_consume) === 30000);
                const isRawDr = triggers.some(trigger =>
                    Number(trigger.conditions && trigger.conditions.category_flags) === 0x200000
                    && Number(trigger.conditions && trigger.conditions.function_id) === 13
                    && Number(trigger.conditions && trigger.conditions.focus_consume) === 5000);
                // A trigger supplying a classic command with turn_around=2
                // is a Target Combo follow-up. Honda and Ingrid dumps both
                // match this marker, including Ingrid's aerial HK > HK.
                const isTargetCombo = triggers.some(trigger =>
                    trigger.classic_display === action.classic_display
                    && Number(trigger.conditions && trigger.conditions.turn_around) === 2);
                const display = isTargetCombo && !action.classic_display.startsWith(">")
                    ? `>${action.classic_display}` : action.classic_display;
                actions[id] = isDrc ? "DRC" : (isRawDr ? "RAW DR" : display);
            }
        }
        return {
            schema: "sf6cc.bcm-runtime.v1",
            character: catalog.source.character,
            fighter_id: catalog.source.fighter_id,
            source_schema: catalog.source.schema,
            source_sha256: catalog.source.sha256,
            policy: "classic:norm>sprt; system:drive-rush-from-bcm; behavior:exceptions",
            actions
        };
    }

    const AC_DERIVED_SIGNATURE_FIELDS = [
        "ActionFrame", "Category", "Combo", "Frame", "Projectile", "State"
    ];

    function stableGraphValue(value, objects, seen) {
        if (!value || typeof value !== "object") return value;
        if (value.kind === "ref") {
            const id = value.object_id;
            if (seen.has(id)) return ["cycle"];
            return stableGraphObject(objects.get(id), objects, new Set([...seen, id]));
        }
        if (Array.isArray(value)) return value.map(item => stableGraphValue(item, objects, seen));
        const out = {};
        for (const key of Object.keys(value).sort()) out[key] = stableGraphValue(value[key], objects, seen);
        return out;
    }

    function stableGraphObject(object, objects, seen) {
        if (!object) return null;
        const out = { type: object.object_type || "" };
        if (Array.isArray(object.fields)) {
            out.fields = object.fields
                .slice()
                .sort((left, right) => String(left.name).localeCompare(String(right.name)))
                .map(field => [field.name, stableGraphValue(field.value, objects, seen)]);
        }
        if (Array.isArray(object.items)) {
            out.items = object.items.map(item => [item.index, stableGraphValue(item.value, objects, seen)]);
        }
        return out;
    }

    function buildAcDerivedAliases(actionSource, actionSet, bcmActions, actions, aliases) {
        if (!Array.isArray(actionSource.records) || !Array.isArray(actionSource.objects)) return 0;

        const objects = new Map(actionSource.objects.map(object => [object.object_id, object]));
        const actionsById = new Map();
        for (const record of actionSource.records) {
            if (!record || record.source_scope !== "character") continue;
            const actionId = Number(record.native_action_id);
            const actionRef = record.action_ref;
            if (!Number.isFinite(actionId) || !actionRef || actionRef.kind !== "ref") continue;
            const action = objects.get(actionRef.object_id);
            if (!action || !Array.isArray(action.fields)) continue;
            actionsById.set(String(actionId), action);
        }

        const actionSignature = action => {
            const fields = new Map(action.fields.map(field => [field.name, field.value]));
            return JSON.stringify(AC_DERIVED_SIGNATURE_FIELDS.map(name => [
                name,
                stableGraphValue(fields.get(name), objects, new Set([action.object_id]))
            ]));
        };
        const getDerivedTargets = action => {
            const fields = new Map(action.fields.map(field => [field.name, field.value]));
            const roots = [];
            const keys = fields.get("Keys");
            if (keys && keys.kind === "ref") roots.push(keys.object_id);
            const visited = new Set();
            const targets = new Map();
            const visitValue = value => {
                if (!value || typeof value !== "object") return;
                if (value.kind === "ref") visitObject(value.object_id);
            };
            const visitObject = objectId => {
                if (visited.has(objectId)) return;
                visited.add(objectId);
                const object = objects.get(objectId);
                if (!object) return;
                if (object.object_type === "CharacterAsset.BranchKey") {
                    const branch = fieldsOf(object);
                    // Types 29 and 35 replace an action with a runtime
                    // variant. Type 29 is the game's explicit conditional
                    // replacement (including resource-level variants), so it
                    // inherits the source command even when its frame data is
                    // different. Type 35 remains guarded by the structural
                    // fingerprint check below.
                    if ((Number(branch.Type) === 29 || Number(branch.Type) === 35)
                        && Number.isFinite(Number(branch.Action))) {
                        const targetId = String(Number(branch.Action));
                        if (!targets.has(targetId)) targets.set(targetId, new Set());
                        targets.get(targetId).add(Number(branch.Type));
                    }
                }
                for (const field of object.fields || []) visitValue(field.value);
                for (const item of object.items || []) visitValue(item.value);
            };
            for (const root of roots) visitObject(root);
            return targets;
        };

        let derivedAliasCount = 0;
        for (const [baseId, baseAction] of actionsById) {
            if (!Object.prototype.hasOwnProperty.call(bcmActions, baseId)) continue;
            const baseSignature = actionSignature(baseAction);
            for (const [derivedId, branchTypes] of getDerivedTargets(baseAction)) {
                const derivedAction = actionsById.get(derivedId);
                if (!derivedAction || !actionSet.has(derivedId) || actions[derivedId] || aliases[derivedId]) continue;
                const explicitType29Replacement = branchTypes.has(29);
                if (!explicitType29Replacement && actionSignature(derivedAction) !== baseSignature) continue;
                aliases[derivedId] = baseId;
                derivedAliasCount += 1;
            }
        }
        return derivedAliasCount;
    }

    function buildActionRuntimeCatalog(actionSource, bcmCatalog, exceptionTable, options) {
        options = options || {};
        exceptionTable = exceptionTable || {};
        if (!actionSource || !actionSource.unique_action_ids_by_scope || !Array.isArray(actionSource.unique_action_ids_by_scope.character)) {
            throw new Error("这不是包含 character Action ID 全集的完整 AC 对象图。");
        }
        if (!bcmCatalog || bcmCatalog.schema !== OUTPUT_SCHEMA) throw new Error("需要先生成 sf6cc.bcm-catalog.v1 审查简表。");

        const fighterId = Number(actionSource.fighter_id ?? -1);
        if (fighterId !== Number(bcmCatalog.source.fighter_id)) throw new Error("AC 与 BCM 的 fighter_id 不一致。");
        const character = options.characterName || FIGHTER_NAMES[fighterId] || bcmCatalog.source.character || actionSource.character || "Unknown";
        const actionIdSet = new Set(actionSource.unique_action_ids_by_scope.character.map(Number).filter(Number.isFinite));
        const actionIds = [...actionIdSet].sort((a, b) => a - b);
        const actionSet = new Set(actionIds.map(String));
        const bcmRuntime = buildRuntimeCatalog(bcmCatalog);
        const actions = { ...bcmRuntime.actions };
        const aliases = {};

        for (const [id, rule] of Object.entries(exceptionTable)) {
            if (!actionSet.has(String(id)) || !rule || typeof rule !== "object") continue;
            if (!actions[id] && typeof rule.override_name === "string" && rule.override_name !== "") {
                actions[id] = rule.override_name;
            }
        }

        for (const [targetId, rule] of Object.entries(exceptionTable)) {
            if (!rule || typeof rule.absorb_ids !== "string" || rule.absorb_ids === "") continue;
            const targetDisplay = (typeof rule.override_name === "string" && rule.override_name !== "")
                ? rule.override_name : actions[targetId];
            if (!targetDisplay) continue;
            for (const token of rule.absorb_ids.split(",")) {
                const aliasId = String(Number(token.trim()));
                if (aliasId === "NaN" || !actionSet.has(aliasId) || actions[aliasId]) continue;
                aliases[aliasId] = String(targetId);
            }
        }

        // Replacement branches directly name the runtime replacement action.
        const acDerivedAliasCount = buildAcDerivedAliases(
            actionSource, actionSet, bcmRuntime.actions, actions, aliases);

        const sortedActions = {}, sortedAliases = {};
        for (const id of Object.keys(actions).sort((a, b) => Number(a) - Number(b))) sortedActions[id] = actions[id];
        for (const id of Object.keys(aliases).sort((a, b) => Number(a) - Number(b))) sortedAliases[id] = aliases[id];
        return {
            schema: "sf6cc.action-runtime.v1",
            character,
            fighter_id: fighterId,
            policy: "universe:ac; commands:bcm; aliases:exceptions+ac-derived",
            sources: {
                ac_schema: actionSource.schema || null,
                ac_sha256: options.actionSourceSha256 || null,
                bcm_schema: bcmCatalog.source.schema,
                bcm_sha256: bcmCatalog.source.sha256
            },
            action_ids: actionIds,
            actions: sortedActions,
            aliases: sortedAliases,
            coverage: {
                ac_derived_alias_count: acDerivedAliasCount
            }
        };
    }

    return {
        OUTPUT_SCHEMA,
        PROFILE_NAMES,
        FIGHTER_NAMES,
        parseSourceText,
        buildCatalog,
        buildRuntimeCatalog,
        buildActionRuntimeCatalog,
        decodeButtons,
        normalizeMotion
    };
});
