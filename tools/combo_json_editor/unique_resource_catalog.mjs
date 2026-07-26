const stateOptions = Object.freeze([
    { value: 0, zh: "关闭", en: "Off" },
    { value: 1, zh: "开启", en: "On" }
]);

function stock(id, zh, en, max, allowInfinite = false, options = {}) {
    return {
        id,
        zh,
        en,
        kind: "stock",
        min: 0,
        max,
        allowInfinite,
        displayOffset: options.displayOffset || 0,
        infiniteDisabled: options.infiniteDisabled === true
    };
}

function state(id, zh, en) {
    return { id, zh, en, kind: "state", min: 0, max: 1 };
}

export const UNIQUE_RESOURCE_CATALOG = Object.freeze({
    1: [state("timer_0_001", "电刃炼气", "Denjin Charge")],
    3: [stock("stock_0_003", "手里剑炸弹", "Shuriken Bomb Stock", 2, true)],
    5: [stock("stock_0_005", "奖牌等级", "Medal Level", 4, false, { displayOffset: 1 })],
    12: [stock("stock_0_012", "风缠", "Windclad Stock", 3, true)],
    15: [
        state("timer_0_015", "雷兽", "Lightning Beast"),
        stock("stock_0_015", "小布兰卡炸弹", "Blanka-chan Doll Stock", 3, true)
    ],
    16: [
        state("timer_0_016", "风水引擎", "Feng Shui Engine"),
        stock("stock_0_016", "风破储备", "Fuha Stock", 3, true)
    ],
    18: [state("timer_0_018", "固体拳套", "Solid Puncher")],
    20: [stock("stock_0_020", "相扑魂", "Sumo Spirit", 1, true)],
    21: [
        state("timer_0_021", "魔身状态", "Devil Install"),
        stock("stock_0_021", "醉酒等级", "Drink Level", 4)
    ],
    28: [
        stock("stock_0_028", "刃焰", "Flame Stock", 5, true, {
            // The current MOD deliberately rejects JSON value 7 for Mai.
            // Keep the requested Infinite option visible, but prevent emitting
            // a value that playback cannot currently restore.
            infiniteDisabled: true
        })
    ],
    30: [state("timer_0_030", "限制解除", "Limit Break")],
    32: [stock("stock_0_032", "太阳纹章", "Sun Crest", 4, true)]
});

export function resourceDefinitionsForFighter(fighterId) {
    return UNIQUE_RESOURCE_CATALOG[Number(fighterId)] || [];
}

export function resourceOptions(resource) {
    if (!resource) return [];
    if (resource.kind === "state") return stateOptions.map(option => ({ ...option, disabled: false }));

    const out = [];
    for (let value = resource.min; value <= resource.max; value += 1) {
        const displayValue = value + (resource.displayOffset || 0);
        out.push({
            value,
            zh: String(displayValue),
            en: resource.displayOffset ? `Level ${displayValue}` : String(displayValue),
            disabled: false
        });
    }
    if (resource.allowInfinite) {
        out.push({
            value: 7,
            zh: "无限",
            en: resource.infiniteDisabled ? "Infinite · Unsupported by current MOD" : "Infinite",
            disabled: resource.infiniteDisabled === true
        });
    }
    return out;
}

export function splitUniqueResourceValues(fighterId, unique) {
    const source = unique && typeof unique === "object" && !Array.isArray(unique) ? unique : {};
    const knownIds = new Set(resourceDefinitionsForFighter(fighterId).map(resource => resource.id));
    const known = {};
    const unknown = {};
    for (const [key, value] of Object.entries(source)) {
        if (knownIds.has(key)) known[key] = value;
        else unknown[key] = value;
    }
    return { known, unknown };
}

export function mergeUniqueResourceValues(known, unknown) {
    const out = {};
    for (const source of [unknown, known]) {
        if (!source || typeof source !== "object" || Array.isArray(source)) continue;
        for (const [key, value] of Object.entries(source)) {
            if (value !== undefined && value !== null && value !== "") out[key] = value;
        }
    }
    return out;
}
