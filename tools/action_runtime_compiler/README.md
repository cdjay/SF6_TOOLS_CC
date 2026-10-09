# AC + BCM + OFF Modern 指令生成工具

这套工具把游戏 dump 的 AC/BCM 与 Capcom 官网数据分开版本化，再为每个 AC/BCM 版本一次生成角色清单中的全部统一指令表（当前 31 个角色）。

核心原则：

- 游戏 Action ID 和动作关系只认 AC+BCM；
- 官网 OFF 只提供招式名称、Classic/Modern 玩家语义，官网 Action ID 不能直接当游戏 Action ID；
- 每个日期目录是独立版本，不混用其他日期的原始数据；
- `lastjson` 必须一次成功生成角色清单中的全部角色，任何缺失或 hard audit 失败都不覆盖旧结果。

## 1. 最终目录

两个数据根目录直接位于本工具目录，不再放进 `html`：

```text
tools/action_runtime_compiler/
├─ acbcm/
│  ├─ 2026-05-28/
│  │  ├─ f001-fab-action-catalog-full-classic.json
│  │  ├─ f001-fab-bcm-full-classic.json
│  │  ├─ ...与角色清单等量的完整配对...
│  │  ├─ lastjson/
│  │  │  ├─ Ryu.json
│  │  │  ├─ Luke.json
│  │  │  └─ ...正好与角色清单等量的角色JSON...
│  │  ├─ lastjson_web/
│  │  │  ├─ Ryu.json
│  │  │  ├─ Luke.json
│  │  │  └─ ...正好与角色清单等量的网页角色资料JSON...
│  │  └─ lastjson-manifest.json
│  └─ <下一个日期>/
├─ off/
│  ├─ 2026-05-28/
│  │  ├─ Ryu.official.generated.json
│  │  ├─ ...与角色清单等量的官网快照...
│  │  ├─ manifest.json
│  │  ├─ differences.json
│  │  └─ differences.md
│  └─ <下一个日期>/
├─ 1_fetch_official_and_diff.bat
└─ 2_build_lastjson.bat
```

`acbcm/`、`off/` 是本地研究数据，已由 `.gitignore` 排除，不提交大型 dump 和抓取快照。生成程序、BAT、规则和测试才进入 Git。

版本目录推荐统一使用 `YYYY-MM-DD`。工具兼容旧的 `YYYY.M.D`，并会按同一天匹配，但新建目录应使用横线格式。

## 2. AC/BCM 文件名和角色对应

游戏单角色实际输出示例：

```text
f032-fab-action-catalog-full-classic.json
f032-fab-bcm-full-classic.json
```

- 两个文件的 stem 必须完全相同，本例为 `f032`；
- `f0` 表示 dump 时没有取得角色名，不参与角色识别；
- 末尾两位 `32` 是 Fighter ID，是配对和角色识别的唯一键；
- 工具还会读取 AC、BCM 内部的 `fighter_id`，并检查三者一致；
- 同一 Fighter ID 重复、AC/BCM 不成对或文件名ID不一致都会终止生成。

Fighter ID 对应关系（以 `data/SF6CC/fighters.json` 为准）：

| ID | 角色 | ID | 角色 | ID | 角色 |
| ---: | --- | ---: | --- | ---: | --- |
| 01 | Ryu | 02 | Luke | 03 | Kimberly |
| 04 | ChunLi | 05 | Manon | 06 | Zangief |
| 07 | JP | 08 | Dhalsim | 09 | Cammy |
| 10 | Ken | 11 | DeeJay | 12 | Lily |
| 13 | AKI | 14 | Rashid | 15 | Blanka |
| 16 | Juri | 17 | Marisa | 18 | Guile |
| 19 | Ed | 20 | EHonda | 21 | Jamie |
| 22 | Akuma | 25 | Sagat | 26 | MBison |
| 27 | Terry | 28 | Mai | 29 | Elena |
| 30 | CViper | 31 | Alex | 32 | Ingrid |
| 33 | Yasmine |  |  |  |  |

旧的中文前缀文件名（如 `英格丽德32-...`）仍可读取，方便迁移；新 dump 不需要人工改名。

## 3. BAT 1：获取官网数据并对比

双击：

```text
1_fetch_official_and_diff.bat
```

默认版本规则：

1. 若 `acbcm` 已有日期目录，使用最新日期；
2. 若还没有 AC/BCM 版本，使用当天日期。

也可从命令行显式指定版本：

```powershell
tools\action_runtime_compiler\1_fetch_official_and_diff.bat 2026-05-28
```

程序只请求一次 Capcom frame 页面和公共 frame 数据模块，从模块中解析角色清单中的全部角色，写入：

```text
off/<版本>/<Character>.official.generated.json
```

每个角色快照同时保留：

- 完整官网 frame 行 `_official_frame`；
- 以官网 Action ID 为距离提示、由 Classic ↔ Modern 命令形成的候选条目；
- 不带 Action ID 的 `_official_semantic_rows` 审计副本；
- Fighter ID、官网 URL、资源 URL和资源 SHA-256。

官网 Action ID 只作候选距离提示；最终必须同时匹配当前 BCM Classic 指令身份，不能单凭官网 ID 绑定。完全丢弃 ID 也不安全，因为多个当前动作可能共享同一 Classic 身份。`_official_semantic_rows` 仅供快照审计，不参与运行时绑定。

### 差异基准

- 同版本目录已存在：与本次覆盖前的同版本快照比较；
- 同版本首次抓取：与之前最近的日期版本比较；
- 没有历史版本：记录为首次基线。

输出：

- `differences.md`：适合直接阅读，列出变化角色、增加/删除/变化 Action ID 和字段路径；
- `differences.json`：完整机器可读差异，包含字段修改前后值；
- `manifest.json`：全部角色文件、Fighter ID 和快照哈希。

抓取或解析任一角色失败时，本次不会用半套数据覆盖目标版本。

新角色发售当天官网往往还没有帧数据。此时加 `--allow-missing`：缺数据的角色被跳过并写进
`manifest.json` 的 `missing_characters`，其余角色照常保存：

```powershell
tools\action_runtime_compiler\1_fetch_official_and_diff.bat 2026-10-13 --allow-missing
```

## 4. BAT 2：按 AC/BCM 版本生成 lastjson

双击：

```text
2_build_lastjson.bat
```

默认扫描 `acbcm` 下所有日期目录，并为每个目录生成自己的：

```text
acbcm/<版本>/lastjson/*.json
```

也可只生成指定版本：

```powershell
tools\action_runtime_compiler\2_build_lastjson.bat 2026-05-28
```

生成条件（全量模式）：

1. 该版本必须有与角色清单等量的完整 AC+BCM；
2. `off` 下必须有同日期的全部角色官网快照（加 `--allow-missing-official` 时可缺，见下）；
3. Fighter ID 不能缺失或重复；
4. AC、BCM和文件名 Fighter ID 必须一致；
5. 每个角色 AC+BCM 编译必须有效；
6. 统一指令输出 hard audit 必须通过；
7. 所有现代指令必须拥有经典投影，`classic_projection_pending_count` 必须为零；
8. 游戏与网页暂存目录都必须正好得到与角色清单等量的 JSON。

全部通过后才同时替换旧 `lastjson` 与 `lastjson_web`；若中途失败，两套旧结果都保持不变。

同一次生成还会更新 `acbcm/<版本>/lastjson_web/*.json`。网页文件使用
`xt.character.web.v1`，保留按 Action ID 查询的 `actions`，并从同版本 OFF 快照增加按招式记录查询的
`moves`、`move_order`、帧数、伤害、取消属性和量表字段。连段起手与角色资料页共享同一个 Action
指令投影，不需要网站再次解析指令文本。

`lastjson` 与 `lastjson_web` 必须同时正好生成角色清单中的全部角色；任一生成、校验或目录替换失败时，两套旧
结果都会保留。

### 可选参数

| 参数 | 作用 |
| --- | --- |
| `--allow-missing-official` | 某角色（或整个版本）没有官网快照时按纯 AC+BCM 生成，`generated_from` 为 `ac_bcm`，manifest 记 `official_status: unavailable`。官网数据每角色只贡献 0–3 条现代 AUTO 连显示消歧，Classic 指令与动作关系不受影响。 |
| `--characters Arjun,Ryu` | 增量模式：只读取并重写这些角色的 `lastjson`/`lastjson_web`，其它角色文件不动，manifest 合并更新。只在其它角色确认未变化时使用；版本更新后优先全量重导。 |
| `--output-dir <目录>` | 把 `lastjson`、`lastjson_web` 与 manifest 写到别处（试跑、对比），不覆盖版本目录。 |

```powershell
tools\action_runtime_compiler\2_build_lastjson.bat 2026-10-13 --allow-missing-official
node tools\action_runtime_compiler\lastjson_builder.js --version 2026-10-13 --characters Arjun --allow-missing-official
```

## 4.1 BAT 3：部署到运行时目录

`data/TrainingComboTrials_data/command_display` 不手改、不逐个复制，只从一个生成版本整体部署：

```powershell
tools\action_runtime_compiler\3_deploy_command_display.bat 2026-10-13
tools\action_runtime_compiler\3_deploy_command_display.bat 2026-10-13 --check
```

部署前先对每个文件跑与生成器相同的 hard audit，全部通过才写入；只覆盖内容变化的文件，任一写入失败会恢复已写入的文件。
`--check` 只比较不写入，正式数据与生成结果不一致时退出码为 1（换行差异不算）。`--characters` 可只部署指定角色。

部署默认目标时还会运行 `build_generated_semantics.js`，从指令表的 AC+BCM 关系重建
`data/TrainingComboTrials_data/generated_semantics`（Type 29 变体吸收与 force 等检测规则，见
`docs/AC_BCM_SEMANTIC_CORE.zh-CN.md` 7.3）；`--check` 同时检查生成语义是否过期。人工例外中定义或
`_generated_semantics.withhold` 保留的 Action 不会生成。单独运行：

```powershell
node tools\action_runtime_compiler\build_generated_semantics.js
node tools\action_runtime_compiler\build_generated_semantics.js --check
```

生成器会在每个指令表 `_meta.bcm_trigger_fingerprint` 写入 BCM 触发器指纹（全部触发器 action_id 排序后的
FNV-1a 哈希，`bcm_fingerprint.js`）。游戏运行时 `ComboTrials/DataBuildGuard.lua` 用同一算法计算当前角色的指纹，
不一致或缺少指令表时在训练场提示一次，提醒重新导出和生成。

## 4.2 版本对比

游戏更新后，先比较新旧 dump，再决定旧角色的例外、显示覆盖和已存连段是否需要离线迁移：

```powershell
node tools\action_runtime_compiler\compare_acbcm_versions.js --old 2026-08-03 --new 2026-10-13 --out diff.md --json diff.json
```

报告按角色列出：BCM 指纹变化、删除的 Action、同 ID 结构变化（BranchKey 类型与 TriggerKey 组不同）、仅帧数变化
（平衡调整，ID 未移动）、新增 Action，以及按结构签名唯一匹配到的新 ID（如 EHonda `944→948`），并列出
`exceptions`、`command_display_overrides`、`action_compatibility` 中引用了受影响 ID 的条目和建议的新 ID。


官网帧数据模块可能把等级蓄力招式的内部候选编码放在 `command` 字段。网页生成器不会直接渲染
该编码：同一内部招式、同一 Action 提示且备注明确按住按钮的等级组，Classic 使用 AC+BCM 的
已验证 Action 指令，Modern 使用官网独立招式语义。Action 索引仍保留原有连段或 assist-combo
投影，避免角色资料页修正影响连段步骤。

`lastjson-manifest.json` 放在版本目录根部，不混入 `lastjson`，因此 `lastjson` 内始终只有角色清单中的正式角色文件。manifest 记录每个角色的输入文件、输出哈希、Action 数和相对覆盖前结果的新增/删除/变化 ID。

## 4.3 原生取消/后续技关系（触发组）

AC 动作的 TriggerKey 在帧窗口内开启 BCM 触发组，触发组的位图选中若干 BCM 触发器，每个触发器启动一个 Action：
这就是游戏自己的“哪个动作之后可以接哪个动作”表（取消、目押、后续技）。`trigger_group_core.js` 解码这条链，
`trigger_group_report.js` 统计它能解释多少人工 `optional_parent_ids` 与指令表中的后续技关系：

```powershell
node tools\action_runtime_compiler\trigger_group_report.js --version 2026-10-13 --out tg.md
```

2026-08-03 及更早的 dump 由旧导出器生成，键号 ≥ Count 的触发组全部丢失，报告标为“触发组不完整”。用当前
`tools/acbcm_exporter` 重新导出后，这条链才能完整覆盖；报告结果用于决定把哪些人工后续技规则改由生成器提供。
目前生成器尚未消费触发组关系。

## 5. 官网文件名与角色名

新版抓取器直接以 SF6CC 规范角色名保存，例如：

```text
off/2026-05-28/Ingrid.official.generated.json
off/2026-05-28/EHonda.official.generated.json
off/2026-05-28/MBison.official.generated.json
```

Fighter ID、规范角色名（`key`）、中英文显示名和官网 slug 的唯一清单是运行时与工具共用的：

```text
data/SF6CC/fighters.json
```

官网 URL 由 `official_slug` 拼出（`https://www.streetfighter.com/6/zh-hant/character/<slug>/frame`）。
新增角色时只在该清单加一行；`tools/bcm_catalog_builder` 浏览器页的 `FIGHTER_NAMES` 与连段编辑器的
角色目录由测试强制与清单一致。两个 BAT 和打包脚本都会检查角色数量和 Fighter ID 唯一性。

## 6. 数据链

```text
AC（动作与派生关系）
        +
BCM（Action owner、trigger、norm/easy/sprt/supr）
        +
OFF（官网 Classic ↔ Modern 玩家语义）
        +
已验证 community 语义（仅数据源确实缺失时）
        ↓
acbcm/<版本>/lastjson/<Character>.json
```

生成器不会：

- 修改用户录制的连段 JSON；
- 修改正式 `data/TrainingComboTrials_data/command_display`（只有 BAT 3 部署脚本会写入）；
- 修改游戏区；
- 把官网 Action ID 当游戏 Action ID；
- 在缺少角色时输出残缺的 `lastjson`。

## 7. 统一指令表 v1

`xt.command_display.v1` 基于同一份 AC ActionGraph 输出经典与现代指令投影：

- `classic_command`：经典输入，来源顺序为 `norm → sprt`；
- `simple_command`：简化输入；同一招的等价方向保存在 `inputs` 中；
- `motion_command`：搓招输入；
- Function 3 只有 Classic `norm` 直连证据时，保留 `projection_scope: classic_only` 路线用于严格验证，但不生成 Modern 指令槽；
- Function 1 只有 Classic `norm` 直连证据时使用同一条 Classic-only 验证规则；若 Action 同时出现在 Assist Combo recipe，Classic `norm` 与 Modern Assist route 并存，二者互不替代；
- Function 2 在两类直接 BCM 证据下保留 Classic-only 验证路线：空中单一拳脚必须让 `norm`、按钮掩码、攻击类型位与 Classic 身份全部精确一致；地面命令必须拥有非空 BCM command 输入序列、攻击键与完全一致的 `norm`/Classic 身份，且没有可见 Modern 路线。无真实 command 的方向、移动与内部状态不使用该回退；
- 无独立 BCM owner 的执行阶段只有在 AC 图满足精确零参数 Type 2+4 终止结构、同核心结构的 Type 2 三段阶段链、多个直接 BCM owner 汇入同一零参数 Type 13 终止节点、多个直接空中普通技 owner 经 `Type 13 / Param00=1` 汇入同一落地阶段并经 `Type 20 / Param01=2` 退出，或唯一 Type 36 阶段经零参数 Type 13 退出到终止节点时，才标记为内部阶段并隐藏；落地阶段的额外来源只接受无 BCM owner 的精确 Type 5/54 配对；Action ID 仍保留给检测和 V2 事实层；
- 无独立 BCM owner 的 Type 20 终止节点只有在与父 Action 核心结构一致，且 AC 完整列出弱/中/强三档拳选择时，才继承父 Action 的同一指令投影；
- 无独立 BCM owner 的 Type 20 动作阶段还可在 AC 精确包含六条按键/阶段分支、父 Action 唯一 Type 0 同级出口、子 Action 唯一 Type 5 退出，并且父 Action 有直接 BCM、子 Action 无 BCM 时继承父指令；该规则只认完整结构，不依赖角色名、Fighter ID 或 Action ID；
- 同时拥有直接 BCM 部署命令、且由多个同结构 BCM owner 通过精确 `Type 20 + Attr 288` 延迟关系汇入的 Action，标记为 `contextual_dual_role`；独立部署时正常显示，同组命中动作之后再次发生时强制另起一行，不修改 Action/V2/检测/回放；
- `relation`：派生动作通过 `type: followup` 和 `source_action_id` 引用前置动作。
- `type37_followup_execution_phase`：仅投影官网已确认派生动作的精确
  `Type 37 + Attr 64` 一对一执行阶段，保留实战实际发生的 Action ID。
- `type63_strength_variant`：仅在 Classic/Modern 分支目标唯一且强度参数成对一致时，
  从同一输入族的直接 BCM 路线继承方向与续招上下文；中/强目标保持独立 Action ID，
  不建立 Action 等价组。
- `assist_combo_chains`：从 `assist_combo_recipes` 按强度重建的 AUTO连 表，
  每个位置保留同一 recipe 步骤出现的全部 Action ID（例如有量表与无量表在终段
  分支到不同超必杀）。运行时只在 AUTO连 模式把连续步进折叠成
  `AUTO + [强>强>强]` 形式；链可提前中断，未出现的后缀不显示。

运行时读取三个指令槽，并根据派生关系生成 `>`；`/` 只用于分隔完整的简化路线与搓招路线，
不再表示动作阶段。现代指令显示支持 简化/搓招/AUTO连 三种单选的解析方式：简化与搓招
只改变同一表的不同指令槽，AUTO连 额外把按住 AUTO 的 assist-combo 关系链折叠为单个
`AUTO + [...]` 输入。

每个 Action ID 必须显式携带以上三个槽；控制方式确实不可用时写 `null`。生成验证会拒绝
缺槽、结构无效或审计计数不一致的输出。简化/搓招的显示回退只发生在运行时，不伪造源数据。

正式文件位于 `data/TrainingComboTrials_data/command_display`。三种显示都只读取统一角色表；角色 exception 仅处理蓄力、吸收、
强制识别、忽略帧等检测行为，不再覆盖指令文本。

## 8. 测试

```powershell
python tools/modern_display_builder/test_official_snapshot_tool.py
node tools/action_runtime_compiler/test_lastjson_builder.js
node tools/action_runtime_compiler/test_official_semantics.js
node tools/action_runtime_compiler/test_compiler.js
node tools/action_runtime_compiler/test_archive_builder.js
node tools/action_runtime_compiler/test_command_display.js
node tools/action_runtime_compiler/test_web_character.js
node tools/bcm_catalog_builder/test_bcm_catalog.js
```

完整真实版本验证：

```powershell
python tools/modern_display_builder/official_snapshot_tool.py --version 2026-05-28
node tools/action_runtime_compiler/lastjson_builder.js --version 2026-05-28
```
