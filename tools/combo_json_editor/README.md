# SF6CC 连段 JSON 元数据编辑器

本工具离线编辑连段 JSON 的元数据和初始环境。浏览器不会上传文件。

## 启动

双击 `start_editor.bat`，或者运行：

```powershell
node tools\combo_json_editor\server.mjs
```

然后打开 <http://127.0.0.1:8776>。

推荐使用 Chrome 或 Edge 的“打开目录”，这样可以在确认后原地保存。普通“打开文件”模式不会获得写权限，只能下载编辑结果。

## 可编辑范围

- `_xt_meta`：标题、作者、说明、标签、步骤备注、语言、控制模式、分类、评分和时间。
- `_xt_meta.environment`：木人姿态、动作、跳跃和防御设置。
- `scene_state`：双方角色、生命槽、斗气槽、超级必杀槽、状态和角色特殊资源。生命槽可点击 10 格槽体或手动输入 0–11000；斗气槽与超级必杀槽分别通过 6 格、3 格槽体设定。
- 角色菜单：以文件夹为筛选边界，通过 Fighter ID 显示中英文角色名，避免把场景中的对手 ID 误当成连段角色。
- 字段和固定选项：中文名称在前，括号中显示对应的英文字段或枚举值；角色、姿态、控制模式、状态等固定值直接显示为单选框体，无需展开下拉菜单。
- 角色特殊资源：按 Fighter ID 显示语义化控件，例如“电刃炼气 (Denjin Charge)”开/关、“刃焰 (Flame Stock)”库存；布兰卡、韩蛛俐和杰米会同时显示两项资源。双方为同一角色时，训练模式共享同一个 `UniqueData` 资源键，两侧控件会自动同步。未知扩展资源保留在单独的 JSON 区域。
- 安全批量编辑：可统一写入游戏、MOD/录制器、REFramework、JSON 格式版本，以及明确确认过的语言和控制模式。

动作 ID、指令、延迟、连击数、`timeline`、`raw_inputs` 等机制字段只读。
作者、角色、创建时间、资源和木人状态不提供全库批量覆盖。

## 批量迁移

默认命令只预检：

```powershell
node tools\combo_json_editor\batch_migrate.mjs --root "<CustomCombos目录>"
```

原地迁移必须提供独立事务备份和报告：

```powershell
node tools\combo_json_editor\batch_migrate.mjs `
  --root "<CustomCombos目录>" `
  --in-place `
  --backup-dir "<备份目录>" `
  --report "<迁移报告.json>" `
  --game-id sf6 `
  --game-version 2026-05-28 `
  --recorder-id sf6cc `
  --recorder-version 1.0.0 `
  --framework-id reframework `
  --framework-version 1.5.9.1 `
  --language zh-CN `
  --control-mode classic `
  --expected-count 996
```

批量迁移只修改 `_xt_meta`。脚本会在写入前验证全部文件、备份全部原件，并逐文件比较机制投影；任何写入或复检失败都会恢复本次事务备份。

维护期若要只补齐木人菜单与双方初始场景中的空值，可先预演：

```powershell
node tools\combo_json_editor\fill_dummy_menu_defaults.mjs `
  --root "<CustomCombos目录>" `
  --expected-count 996
```

确认后增加 `--write` 原地写入。该工具不覆盖已有非空值；格挡空值按合集约定写为“第2段后格挡”，双方空资源写为生命槽 10000、斗气槽 6 格、超级必杀槽 3 格、虚损关闭，角色特殊资源按 Fighter ID 写入标准状态。工具不创建磁盘备份，因此只应用于已经独立备份的维护副本。

## 迁移原则

- `_xt_meta.schema` 升级为 `2`，JSON 版本写为 `xt.combo_trial/2.0.0`。
- 原录制器或游戏版本无法确认时写 `unknown` 或省略版本，不伪造来源。
- 缺失语言写 `und`，缺失控制模式写 `unknown`。
- `tags` 和 `step_notes` 补成规范数组；已有内容原样保留。
- 旧 `scene.v1` 保留不变。只有人工录入 v2 资源或状态时，编辑器才会把该场景提升为 `scene.v2`。
- 未知扩展字段和旧版兼容字段全部保留。

## 测试

```powershell
node tools\combo_json_editor\test_combo_json_core.mjs
node tools\combo_json_editor\test_character_catalog.mjs
node tools\combo_json_editor\test_unique_resource_catalog.mjs
node tools\combo_json_editor\test_editor_ui_contract.mjs
```
