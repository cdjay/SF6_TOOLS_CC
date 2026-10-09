# AC/BCM 导出器

Status: `CURRENT`

`SF6CC_ACBCM_Exporter.lua` 从游戏内存一次性导出当前 P1 角色的原生动作数据：

- AC：`gBattle.Resource.Data[0].FAB.StyleDict[*].ActionList`（角色）与 `Data[6]`（通用），
  即全部 Action、BranchKey（自动/输入分支、阶段、派生）与 TriggerKey（取消/后续技窗口）；
- BCM：`gBattle.Command.mpBCMResource[0]` 与 `mUserEngine[0].GetTrigger()`，
  即输入指令、四套 profile、触发条件、触发组、蓄力定义与 AUTO 连配方。

导出器只读、不注册每帧回调、不解释数据；解释全部在 `tools/action_runtime_compiler` 生成器中完成。
脚本来自 SF6CR-evidence 的 `SF6CR_ExportFullEvidence.lua`，并修正了两处数据丢失：

- 字典：`Dictionary<int, …>` 现在按内部条目导出全部键（条目 `index == key`，输出标记
  `dictionary_encoding = "int-keyed-entries"`）。旧导出用 `get_Item(0..Count-1)` 按键查找，
  键号 ≥ Count 的触发组、指令、蓄力定义会全部丢失（2026-08-03 的 31 个角色每人丢 7–39 个触发组）。
- 继承字段：反射 `get_fields()` 只返回类型自己声明的字段，旧导出因此丢掉了各种 Key 从
  `via.fighter.ActionKey` 继承的帧窗口（起止帧）。现在沿父类链读取游戏数据命名空间
  （`via.fighter.`、`CharacterAsset.`、`app.battle.`、`BCM.`）的基类字段，输出标记
  `inherited_fields = "game-namespaces.v1"`，类型目录的 `inherits` 记录父类链。长按阈值
  （T20 窗口）与取消窗口（TriggerKey 窗口）都依赖这些帧数。

## 导出一个角色

1. 游戏更新后先冷启动，确认 REFramework 正常加载。
2. 进入训练场，P1 选目标角色，操作方式切到**经典**。
3. 在 REFramework 菜单的 ScriptRunner 中点 **Run script**，选择本目录的 `SF6CC_ACBCM_Exporter.lua`。
4. 输出位于游戏目录 `reframework/data/SF6CC_ACBCM/`：

   ```text
   f034-fab-action-catalog-full-classic.json
   f034-fab-bcm-full-classic.json
   ```

   `f034` 的数字就是该角色的 fighter ID。REFramework 日志会写 `detected fighter_id=…` 和
   `hard_gate=true`；`hard_gate=false` 表示有截断，不能使用。
5. 换下一个角色重复。游戏版本更新后要导出**全部角色**，否则无法判断旧角色的 Action ID 是否变化。

导出文件很大（AC 每个 55–92 MB），属于本地研究数据，不进 Git，也不进发布包。

## 新角色发售当天（Day-0）流程

以 2026-10-13 为例，假设新角色 Arjun 的 fighter ID 是 34（以导出文件名为准）。

1. 按上节导出全部角色（含 Arjun），复制到
   `tools/action_runtime_compiler/acbcm/2026-10-13/`。
2. 在 `data/SF6CC/fighters.json` 加一行：

   ```json
   { "id": 34, "key": "Arjun", "name_en": "Arjun", "name_zh": "阿尔琼", "official_slug": "arjun" }
   ```

   同步加到 `tools/bcm_catalog_builder/bcm_catalog_core.js` 的 `FIGHTER_NAMES`、
   `tools/combo_json_editor/character_catalog.mjs`、木人库 `Records.lua` 与
   `autorun/func/DynamicRecords.lua` 的 `CHARACTER_NAMES` 及 `CharacterNames.lua`（漏一处，测试会指出）。
3. 抓官网数据，官网还没有新角色时跳过它：

   ```powershell
   tools\action_runtime_compiler\1_fetch_official_and_diff.bat 2026-10-13 --allow-missing
   ```

4. 生成全部角色指令表，缺官网数据的角色按纯 AC+BCM 生成：

   ```powershell
   tools\action_runtime_compiler\2_build_lastjson.bat 2026-10-13 --allow-missing-official
   ```

5. 比较新旧版本，确认旧角色的 Action ID 是否变化：

   ```powershell
   node tools\action_runtime_compiler\compare_acbcm_versions.js --old 2026-08-03 --new 2026-10-13
   ```

   报告列出每个角色新增/删除的 Action、指令换了 Action ID 的招式，以及受影响的例外、显示覆盖和兼容映射。
   旧角色没有变化时可直接部署；有变化的角色要先迁移它的例外和已存连段。

   再看新角色带来了哪些名单上从未出现过的结构（新机制），实机测试时重点覆盖这些招式：

   ```powershell
   node tools\action_runtime_compiler\novel_structure_report.js --version 2026-10-13 --characters Arjun --out novel.md
   ```
6. 部署并复核：

   ```powershell
   tools\action_runtime_compiler\3_deploy_command_display.bat 2026-10-13
   tools\action_runtime_compiler\3_deploy_command_display.bat 2026-10-13 --check
   ```

   部署会同时为新角色生成检测规则（`generated_semantics/Arjun.json`：AC 变体吸收与 force 等），
   新角色没有人工例外，全部规则来自 AC+BCM。

7. 把 `data/SF6CC/version.json` 的 `recording.game.version` 改为 `2026-10-13`，跑离线门禁
   （见 `docs/TESTING_STRATEGY.md`），实机冒烟后打包。

只想先让新角色可用、旧角色确认未变时，第 4、6 步可加 `--characters Arjun` 只处理新角色。

重新导出后可检查原生取消/后续技关系的覆盖（触发组完整性与人工后续技规则的解释率），
以及手写长按阈值与 AC Type 20 帧窗口是否一致：

```powershell
node tools\action_runtime_compiler\trigger_group_report.js --version 2026-10-13 --out tg.md
node tools\action_runtime_compiler\hold_window_report.js --version 2026-10-13 --out hold.md
```

`hold.md` 里全部是 `frame_window_missing` 说明导出没有带上继承字段（导出文件缺
`inherited_fields` 标记），需要用本目录的导出器重导。

运行时会用 BCM 触发器指纹核对指令表与当前游戏数据；不一致或缺少指令表时，训练场会提示，
提醒重新导出和生成。

## 测试

```powershell
lua tools/test_acbcm_exporter.lua
```

离线测试用假 SDK 验证字典按键导出（含键号 ≥ Count 与已删除条目）和继承字段导出（帧窗口来自基类，
不越过 `System.*`/引擎基类）。真实导出必须在游戏内执行。
