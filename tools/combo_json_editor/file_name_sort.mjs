/* ==========================================================================
   连段训练 JSON 文件名自然排序
   规则：
   1. 默认顺序仅比较文件名；编辑器可另行调用 compareComboTitles 按 _xt_meta.title 排序。
   2. 文件名统一转小写，排序不区分大小写。
   3. 按“文本段 + 数字段”自然升序：combo2.json 排在 combo10.json 前。
   4. 数值相同时数字位数少者优先：2.json 排在 02.json 前。
   5. 文本段按 Lua 字符串（字节）顺序比较。
   6. 一方是另一方前缀时，较短文件名优先。
   7. 文件名包含区分大小写的 _FAIL_ 时不进入列表。
   本模块不依赖 DOM，可直接被 Node 测试引用。
   ========================================================================== */

export function naturalNameSegments(name) {
    const lower = String(name).toLowerCase();
    const parts = lower.match(/\d+|\D+/g) || [];
    return parts.map(part => (/^\d+$/.test(part)
        ? { kind: "num", value: BigInt(part), digits: part.length, raw: part }
        : { kind: "text", raw: part }));
}

/* 双指针逐字节推进：两侧同时为数字时读取完整数字段比较数值
   （数值相同则位数少者优先），其余位置按 Lua 字符串字节序逐字符比较；
   一方先耗尽即前缀，较短者优先。 */
export function compareFileNames(left, right) {
    const a = String(left).toLowerCase();
    const b = String(right).toLowerCase();
    const isDigit = char => char >= "0" && char <= "9";
    let i = 0;
    let j = 0;
    while (i < a.length && j < b.length) {
        if (isDigit(a[i]) && isDigit(b[j])) {
            let iEnd = i;
            let jEnd = j;
            while (iEnd < a.length && isDigit(a[iEnd])) iEnd += 1;
            while (jEnd < b.length && isDigit(b[jEnd])) jEnd += 1;
            const numA = BigInt(a.slice(i, iEnd));
            const numB = BigInt(b.slice(j, jEnd));
            if (numA !== numB) return numA < numB ? -1 : 1;
            const digitsA = iEnd - i;
            const digitsB = jEnd - j;
            if (digitsA !== digitsB) return digitsA - digitsB;
            i = iEnd;
            j = jEnd;
            continue;
        }
        if (a[i] !== b[j]) return a[i] < b[j] ? -1 : 1;
        i += 1;
        j += 1;
    }
    return (a.length - i) - (b.length - j);
}

const utf8Encoder = new TextEncoder();

function luaTrim(value) {
    return String(value).replace(/^[\t\n\v\f\r ]+|[\t\n\v\f\r ]+$/g, "");
}

export function comboRecordTitle(record) {
    const root = record?.document?.[0] || {};
    const title = typeof root?._xt_meta?.title === "string" ? luaTrim(root._xt_meta.title) : "";
    const legacyTitle = typeof root?._wtt_cn_meta?.title === "string"
        ? luaTrim(root._wtt_cn_meta.title)
        : "";
    return title || legacyTitle || String(record?.name || "").replace(/\.json$/i, "");
}

function luaAsciiLower(value) {
    return String(value).replace(/[A-Z]/g, char => String.fromCharCode(char.charCodeAt(0) + 32));
}

/* 对齐游戏 ComboTrials_UI.lua：
   Lua string.lower 只处理 ASCII，随后用 < / > 按 UTF-8 字节逐项比较。
   不使用 Intl.Collator，因此中文不按拼音、数字也不按自然数排序。 */
export function compareComboTitles(left, right, direction = 1) {
    const leftBytes = utf8Encoder.encode(luaAsciiLower(comboRecordTitle(left)));
    const rightBytes = utf8Encoder.encode(luaAsciiLower(comboRecordTitle(right)));
    const length = Math.min(leftBytes.length, rightBytes.length);
    for (let index = 0; index < length; index += 1) {
        if (leftBytes[index] === rightBytes[index]) continue;
        const result = leftBytes[index] < rightBytes[index] ? -1 : 1;
        return direction < 0 ? -result : result;
    }
    const result = leftBytes.length === rightBytes.length ? 0 : leftBytes.length < rightBytes.length ? -1 : 1;
    return direction < 0 ? -result : result;
}

/* 区分大小写：仅精确匹配 _FAIL_ */
export function isFailMarkedFile(name) {
    return String(name).includes("_FAIL_");
}
