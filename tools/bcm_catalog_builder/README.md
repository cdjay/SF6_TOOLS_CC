# BCM 简表生成器

这个工具把 SF6CR 导出的完整 BCM 对象图转换成适合审查和 MOD 读取的版本化简表。

## 使用方式

直接打开 `index.html`，把 `*-bcm-full-*.json` 拖入页面。转换完全在浏览器本地完成，不上传文件。页面可以筛选 Action ID、比较 `norm/easy/sprt/supr`，并导出两种结果：

- 审查简表：保留四套 profile、触发条件、指令变体和转换诊断。
- MOD 基础表：仅保留运行时需要的 `Action ID → 经典指令`，由 exceptions 继续覆盖行为与显示例外。

命令行等价用法：

```powershell
node tools\bcm_catalog_builder\build_catalog.js <完整BCM.json> <BCM简表.json> [角色规范名]
```

请把临时输出写到仓库外。只有经过验证、供 MOD 使用的角色简表才应放入 `data/TrainingComboTrials_data/bcm_catalog/` 并纳入版本控制。

## 输出边界

- `classic_display` 使用与当前 MOD 相同的 `norm → sprt` 选择顺序。
- 四套 profile 和所有指令变体都会保留。
- 工具不会仅凭导出文件的 `control_mode_label` 猜测现代模式映射。完整 classic/modern 对象图可能完全相同；现代 profile 选择策略需要单独验证。
- BCM 提供基础指令，现有 exceptions 继续负责吸收动作、蓄力窗口、前置动作忽略、强制匹配等行为例外。
- 页面使用无损整数预处理；BCM 的 64 位条件 flags 会以十进制字符串保留，避免浏览器把它们四舍五入。
- 两种输出都会记录原始完整 BCM 文件的 SHA-256，用于确认基础表来源和发现过期转换结果。
- 证据集把角色写成 `Fab` 时，生成器会用 `fighter_id` 转换成 MOD 使用的规范角色名（例如 20 → `EHonda`）；可选命令行参数仍可显式覆盖。

## 测试

```powershell
node tools\bcm_catalog_builder\test_bcm_catalog.js
```
