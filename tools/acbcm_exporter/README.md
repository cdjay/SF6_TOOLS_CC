# AC/BCM 导出器

Status: `CURRENT`

`SF6CC_ACBCM_Exporter.lua` 从游戏内存一次性导出当前 P1 角色的原生动作数据：

- AC：`gBattle.Resource.Data[0].FAB.StyleDict[*].ActionList`（角色）与 `Data[6]`（通用），
  即全部 Action、BranchKey（自动/输入分支、阶段、派生）与 TriggerKey（取消/后续技窗口）；
- BCM：`gBattle.Command.mpBCMResource[0]` 与 `mUserEngine[0].GetTrigger()`，
  即输入指令、四套 profile、触发条件、触发组、蓄力定义与 AUTO 连配方。

导出器只读、不注册每帧回调、不解释数据；解释全部在 `tools/action_runtime_compiler` 生成器中完成。
脚本来自 SF6CR-evidence 的 `SF6CR_ExportFullEvidence.lua`，并修正了两处数据丢失：

- 字典：`Dictionary<int, …>` 现在按内部条目导出全部键（条目 `index == key`），只读到字典内部的已用槽位数
  （`_count`，读不到时用 Count），输出标记 `dictionary_encoding = "int-keyed-entries.v2"`，字典节点记录
  `used_slots`。旧导出用 `get_Item(0..Count-1)` 按键查找，键号 ≥ Count 的触发组、指令、蓄力定义会全部丢失
  （2026-08-03 的 31 个角色每人丢 7–39 个触发组）。2026-10-09 第一版修复（标记 `int-keyed-entries`）
  还会多导出触发组字典未使用的空槽（键 0、标志全 0，每角色 41–48 个）；消费端对这种导出只取
  槽位序号小于 Count 的条目，游戏数据加载后没有删除，这样正好是全部真实条目。
- 帧窗口：各种 Key 的起止帧属于原生基类 `via.fighter.ActionKey`（中间还有 `CharacterAsset.ActionBase`），
  这两个基类没有反射字段，第一版沿父类链读字段也读不到。v2 对这两个基类读取无参数、返回基本类型的
  属性 getter，作为字段写入（`source = "property"`、`declared_in`），并在 `base_type_catalog` 列出它们的
  全部字段和方法；输出标记 `inherited_fields = "game-namespaces.v2"`。长按阈值（T20 窗口）与取消窗口
  （TriggerKey 窗口）都依赖这些帧数。

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

2026-10-13 的全角色导出已确认 Arjun 的 fighter ID 是 34（以导出文件中的 ID 为准）。
开始生成前，先把成对的原始文件保存到独立的本地备份目录，检查 JSON 可解析、
文件名 ID 与内容一致、两份导出均为 v2、`hard_gate_passed=true`、无截断；
记录来源、版本、文件大小与 SHA-256，并核对备份字节一致。备份属于本地研究数据，
不进 Git，也不进发布包。10.13 的备份在 `release/tester_packages/acbcm-2026-10-13_*/`，
官网快照单独放在其 `official/` 子目录。

1. 按上节导出全部角色（含 Arjun），复制到
   `tools/action_runtime_compiler/acbcm/2026-10-13/`。
2. 在 `data/SF6CC/fighters.json` 加一行：

   ```json
   { "id": 34, "key": "Arjun", "name_en": "Arjun", "name_zh": "阿俊", "official_slug": "arjun" }
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

   31 个角色的 v2 导出约 2.6 GB，全量生成约 4–5 分钟（生成器逐角色读取导出，默认内存即可）。
   2026-10-10 用当时的游戏数据完整预演过一遍：30 个角色与部署版本一致，Zangief 多一条辅助操作触发器。

5. 比较新旧版本，确认旧角色的 Action ID 是否变化：

   ```powershell
   node tools\action_runtime_compiler\compare_acbcm_versions.js --old 2026-08-03 --new 2026-10-13
   ```

   报告列出每个角色新增/删除的 Action、指令换了 Action ID 的招式，以及受影响的例外、显示覆盖和兼容映射。
   该比较只检查动作帧数、分支类型和触发组形态，不能单独证明全部输入条件或跨版本身份。
   有变化时核对例外和已存连段；报告的候选 ID 不得自动当作迁移批准。
   也要与最近的同版导出器基线比较（10.13 对比 10.09），区分游戏更新与导出器修正。
   旧版兼容映射不能直接延期，旧连段应离线迁移；冻结测试样本保留原样。

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

`hold.md` 里全部是 `frame_window_missing` 说明导出没有帧窗口：导出标记不是
`inherited_fields = "game-namespaces.v2"` 时需要用本目录的导出器重导；是 v2 仍然缺失时，
看导出文件的 `base_type_catalog` 里 `via.fighter.ActionKey` 有哪些方法，再确定读取方式。

运行时会用 BCM 触发器指纹核对指令表与当前游戏数据；不一致或缺少指令表时，训练场会提示，
提醒重新导出和生成。

## 探测游戏内出招表的数据源

训练场的出招表（必杀、SA、特殊技、投、通用、辅助连段，子项是派生）是游戏自己的招式名、分类和派生层级。
找到它的数据源后，可以替换生成器目前仍在读取的官网数据。`SF6CC_CommandList_Probe.lua` 只读探测：

1. 训练场里打开出招表并停在该界面。
2. ScriptRunner 运行本目录的 `SF6CC_CommandList_Probe.lua`。
3. 输出 `reframework/data/SF6CC_ACBCM/commandlist-probe.json`：`app.UICommandListWindow`、
   `app.UIPartsCommandListSkillPanel` 的字段/方法/父类，类型库可用时还会列出所有名字含 commandlist/skilllist/
   movelist 的类型，以及当前打开窗口的有限深度对象图（深度 6、最多 30000 个对象）。

探测不注册钩子、不写回游戏。把输出文件交给开发者即可确定下一步的读取方式。

## 采集动作切换的引擎标志

剩下的大部分手写 force / ignore / absorb_ids 规则，纠正的是运行时"这个动作算不算玩家的一步"的判断，
它在每次动作切换时读取三个引擎值：`mParam.state_flags`、`KeyInput.Action`、`Branch.BranchType`。
`SF6CC_Transition_Probe.lua` 只读地记录这些值，用来把它们和 AC+BCM 的进入方式对上，从而推导这些规则：

1. 训练场 P1 选要研究的角色，ScriptRunner 运行本目录的 `SF6CC_Transition_Probe.lua`。
2. 把该角色的招式做一遍：必杀（含 OD）、派生和后续技、长按、投（含后投）、目押/TC、SA、DR、DI。
3. 再运行一次同一个文件暂停记录（REFramework 菜单里也有开关和"Save now"）。
4. 输出追加到 `reframework/data/SF6CC_ACBCM/transitions-fNNN.jsonl`，一次切换一行。

采集脚本不改游戏数据，只在每帧读取 P1 的动作状态。分析见
`tools/action_runtime_compiler/transition_report.js`。

## 测试

```powershell
lua tools/test_acbcm_exporter.lua
lua tools/test_commandlist_probe.lua
lua tools/test_transition_probe.lua
```

离线测试用假 SDK 验证字典按键导出（含键号 ≥ Count 与已删除条目）和继承字段导出（帧窗口来自基类，
不越过 `System.*`/引擎基类）。真实导出必须在游戏内执行。
