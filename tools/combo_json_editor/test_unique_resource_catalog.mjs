import assert from "node:assert/strict";
import {
    mergeUniqueResourceValues,
    resourceDefinitionsForFighter,
    resourceOptions,
    splitUniqueResourceValues,
    UNIQUE_RESOURCE_CATALOG
} from "./unique_resource_catalog.mjs";

const expected = {
    1: ["timer_0_001"],
    3: ["stock_0_003"],
    5: ["stock_0_005"],
    12: ["stock_0_012"],
    15: ["timer_0_015", "stock_0_015"],
    16: ["timer_0_016", "stock_0_016"],
    18: ["timer_0_018"],
    20: ["stock_0_020"],
    21: ["timer_0_021", "stock_0_021"],
    28: ["stock_0_028"],
    30: ["timer_0_030"],
    32: ["stock_0_032"]
};

assert.deepEqual(
    Object.fromEntries(Object.entries(UNIQUE_RESOURCE_CATALOG).map(([id, resources]) => [
        id,
        resources.map(resource => resource.id)
    ])),
    expected
);

assert.deepEqual(resourceOptions(resourceDefinitionsForFighter(1)[0]).map(option => option.value), [0, 1]);
assert.equal(resourceDefinitionsForFighter(1)[0].zh, "电刃炼气");
assert.deepEqual(
    resourceOptions(resourceDefinitionsForFighter(1)[0]).map(option => option.zh),
    ["关闭", "开启"]
);
assert.deepEqual(resourceOptions(resourceDefinitionsForFighter(16)[1]).map(option => option.value), [0, 1, 2, 3, 7]);
for (const fighterId of [15, 16, 21]) {
    assert.equal(resourceDefinitionsForFighter(fighterId).length, 2);
}
assert.deepEqual(
    resourceOptions(resourceDefinitionsForFighter(5)[0]).map(option => option.en),
    ["Level 1", "Level 2", "Level 3", "Level 4", "Level 5"]
);
const maiInfinite = resourceOptions(resourceDefinitionsForFighter(28)[0]).find(option => option.value === 7);
assert.equal(resourceDefinitionsForFighter(28)[0].zh, "刃焰");
assert.deepEqual(
    resourceOptions(resourceDefinitionsForFighter(28)[0]).map(option => option.value),
    [0, 1, 2, 3, 4, 5, 7]
);
assert.equal(maiInfinite.disabled, true);

const split = splitUniqueResourceValues(16, { timer_0_016: 1, stock_0_016: 3, future_field: 9 });
assert.deepEqual(split.known, { timer_0_016: 1, stock_0_016: 3 });
assert.deepEqual(split.unknown, { future_field: 9 });
assert.deepEqual(
    mergeUniqueResourceValues({ timer_0_016: 2 }, split.unknown),
    { future_field: 9, timer_0_016: 2 }
);

console.log("unique_resource_catalog tests passed");
