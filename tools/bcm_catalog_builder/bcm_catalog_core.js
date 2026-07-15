(function (root, factory) {
    const api = factory();
    if (typeof module === "object" && module.exports) module.exports = api;
    root.SF6CCBcmCatalog = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
    "use strict";

    const OUTPUT_SCHEMA = "sf6cc.bcm-catalog.v1";
    const PROFILE_NAMES = ["norm", "easy", "sprt", "supr"];
    const DIR_MAP = {
        0: "5", 1: "8", 2: "2", 4: "4", 5: "7",
        6: "1", 8: "6", 9: "9", 10: "3", 15: "*"
    };
    const BUTTONS = [
        [16, "LP"], [32, "MP"], [64, "HP"],
        [128, "LK"], [256, "MK"], [512, "HK"]
    ];

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
        return String(raw || "")
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
            const direction = DIR_MAP[lowBits(mask, 0xF)] || "5";
            if (Number(chargeFields.id || 0) > 0) hasCharge = true;
            inputs.push({
                direction,
                raw_mask: mask,
                frames: Number(inputFields.frame_num || 0),
                type: Number(inputFields.type || 0),
                charge_id: Number(chargeFields.id || 0),
                charge_release: chargeFields.is_release === true
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

    function buildCatalog(source, options) {
        options = options || {};
        if (!source || !Array.isArray(source.objects)) throw new Error("这不是包含 objects 的完整 BCM 对象图。");
        if (!Array.isArray(source.triggers)) throw new Error("这不是包含 triggers 的完整 BCM 对象图。");

        const warnings = [];
        if (source.truncated) warnings.push("源文件标记为 truncated，输出不能视为完整基础表。");
        if (source.hard_gate_passed === false) warnings.push("源文件 hard_gate_passed=false。");
        const objects = buildObjectIndex(source);
        const commandTable = decodeCommandTable(source, objects, warnings);
        const actions = {};
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
        return {
            schema: OUTPUT_SCHEMA,
            generated_at: options.generatedAt || new Date().toISOString(),
            source: {
                schema: source.schema || null,
                character: source.character || "Unknown",
                fighter_id: Number(source.fighter_id ?? -1),
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
                warning_count: warnings.length
            },
            warnings,
            commands: commandTable,
            actions: sortedActions
        };
    }

    function buildRuntimeCatalog(catalog) {
        if (!catalog || catalog.schema !== OUTPUT_SCHEMA) throw new Error("只能从 sf6cc.bcm-catalog.v1 生成运行时基础表。");
        const actions = {};
        for (const [id, action] of Object.entries(catalog.actions || {})) {
            if (typeof action.classic_display === "string" && action.classic_display !== "") {
                actions[id] = action.classic_display;
            }
        }
        return {
            schema: "sf6cc.bcm-runtime.v1",
            generated_at: catalog.generated_at,
            character: catalog.source.character,
            fighter_id: catalog.source.fighter_id,
            source_schema: catalog.source.schema,
            source_sha256: catalog.source.sha256,
            policy: "classic:norm>sprt; behavior:exceptions",
            actions
        };
    }

    return {
        OUTPUT_SCHEMA,
        PROFILE_NAMES,
        parseSourceText,
        buildCatalog,
        buildRuntimeCatalog,
        decodeButtons,
        normalizeMotion
    };
});
