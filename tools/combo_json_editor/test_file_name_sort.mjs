import assert from "node:assert/strict";
import { compareFileNames, isFailMarkedFile, naturalNameSegments } from "./file_name_sort.mjs";

function assertOrder(names, expected) {
    const sorted = [...names].sort(compareFileNames);
    assert.deepEqual(sorted, expected, `sort order mismatch: ${JSON.stringify(sorted)}`);
}

/* 数字段自然升序：combo2 < combo10 */
assertOrder(["combo10.json", "combo2.json", "combo1.json"], ["combo1.json", "combo2.json", "combo10.json"]);

/* 数值相同，位数少者优先：2.json < 02.json */
assertOrder(["02.json", "2.json", "1.json"], ["1.json", "2.json", "02.json"]);

/* 不区分大小写 */
assertOrder(["B.json", "a.json", "C.json"], ["a.json", "B.json", "C.json"]);
assert.equal(compareFileNames("Combo1.json", "combo1.json"), 0, "case-insensitive equality");

/* 前缀时较短者优先 */
assertOrder(["combo2.json", "combo.json"], ["combo.json", "combo2.json"]);
assertOrder(["abc.json", "ab.json"], ["ab.json", "abc.json"]);

/* 文本段 Lua 字符串顺序；数字与文本混排按字节序（'2' < 'b'） */
assertOrder(["ab.json", "a2.json"], ["a2.json", "ab.json"]);

/* 目录、标题、内容不参与排序：仅文件名 */
assertOrder(
    ["Ryu_COMBO_214_MP.json", "Ryu_COMBO_214_MP_3454.json"],
    ["Ryu_COMBO_214_MP.json", "Ryu_COMBO_214_MP_3454.json"]
);

/* 大数字不溢出 */
assert.ok(compareFileNames("combo99999999999999999999.json", "combo100000000000000000000.json") < 0);

/* 分段正确性 */
assert.deepEqual(
    naturalNameSegments("AKI_COMBO_02.json").map(part => part.raw),
    ["aki_combo_", "02", ".json"]
);

/* _FAIL_ 区分大小写 */
assert.ok(isFailMarkedFile("AKI_COMBO_FAIL_01.json"));
assert.ok(isFailMarkedFile("x_FAIL_y.json"));
assert.ok(!isFailMarkedFile("x_fail_y.json"));
assert.ok(!isFailMarkedFile("normal.json"));

console.log("file name sort tests passed");
