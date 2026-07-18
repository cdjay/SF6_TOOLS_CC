# AC + BCM + OFF 角色指令生成器

本工具把三类证据合并为 SF6CC 使用的角色检测表与 Modern 指令显示表：

- **AC**：游戏 Action Catalog 完整对象图，定义角色实际存在的 Action ID 及动作关系；
- **BCM**：游戏 Command/Trigger 完整对象图，定义 Action ID 对应的 classic、easy、sprt、supr 指令入口；
- **OFF**：Capcom 官网 Classic/Modern 出招表，提供招式名称和玩家可见语义。

Action ID 的最终归属以游戏 dump 的 AC+BCM 为准。OFF 不能单独决定游戏 Action ID；生成器会用当前 BCM 指令身份绑定官网语义，并保留来源、哈希和路线证据。

## 1. 推荐目录与版本规则

每次游戏更新后创建一个日期目录，目录名直接作为版本。例如：

```text
D:\CP\SF6CR-evidence\AC+BCM+OFF\
└─ 2026.5.28\
   ├─ 卢克02-fab-action-catalog-full-classic.json
   ├─ 卢克02-fab-bcm-full-classic.json
   ├─ LUKE.json
   ├─ 本田20-fab-action-catalog-full-classic.json
   ├─ 本田20-fab-bcm-full-classic.json
   ├─ E.HONDA.json
   └─ ...
```

网页中的“Dump 目录”选择这个日期目录，“本次版本”填写同一个目录名 `2026.5.28`。不要把多个日期的文件混在同一目录。

构建后，本地版本归档位于：

```text
tools/action_runtime_compiler/html/
├─ acbcm/2026.5.28/  # 原始 AC+BCM、SHA-256、manifest
├─ off/2026.5.28/    # 本次使用的 OFF 原始表和规范语义快照
├─ char/2026.5.28/   # runtime、exceptions、modern、报告与版本差异
├─ latest/            # 最新内部 runtime
├─ latest_exceptions/ # 可同步的角色检测表
└─ latest_modern/     # 可同步的 Modern 显示表
```

日期目录就是版本边界。新版本默认与最近一个包含该角色的历史目录比较；也可以在网页选择指定基准版本。同版本重复构建允许覆盖本次选择的角色，未选择角色保持不变，差异基准为覆盖前内容。

## 2. 文件名对应关系

### AC 与 BCM

AC 与 BCM 必须具有完全相同的 `<stem>`，只允许结尾不同：

```text
<stem>-fab-action-catalog-full-classic.json
<stem>-fab-bcm-full-classic.json
```

例如：

```text
卢克02-fab-action-catalog-full-classic.json
卢克02-fab-bcm-full-classic.json
```

工具先按 stem 配对，再读取 `fighter_id` 得到规范角色名 `Luke`。归档后的 `manifest.json` 是最终文件对应关系，不依赖中文文件名前缀进行角色判断。

### OFF 官网表

OFF 原始 JSON 使用官网/采集器文件名；编译输出使用 SF6CC 规范角色名。当前对应如下：

| 规范角色名 | OFF 原始文件 | 规范语义/最终表前缀 |
| --- | --- | --- |
| AKI | `A.K.I.json` | `AKI` |
| Akuma | `GOUKI.json` | `Akuma` |
| Alex | `ALEX.json` | `Alex` |
| Blanka | `BLANKA.json` | `Blanka` |
| CViper | `C.VIPER.json` | `CViper` |
| Cammy | `CAMMY.json` | `Cammy` |
| ChunLi | `CHUN-LI.json` | `ChunLi` |
| DeeJay | `DEE JAY.json` | `DeeJay` |
| Dhalsim | `DHALSIM.json` | `Dhalsim` |
| EHonda | `E.HONDA.json` | `EHonda` |
| Ed | `ED.json` | `Ed` |
| Elena | `ELENA.json` | `Elena` |
| Guile | `GUILE.json` | `Guile` |
| Ingrid | `INGRID.json` | `Ingrid` |
| JP | `JP.json` | `JP` |
| Jamie | `JAMIE.json` | `Jamie` |
| Juri | `JURI.json` | `Juri` |
| Ken | `KEN.json` | `Ken` |
| Kimberly | `KIMBERLY.json` | `Kimberly` |
| Lily | `LILY.json` | `Lily` |
| Luke | `LUKE.json` | `Luke` |
| MBison | `VEGA.json` | `MBison` |
| Mai | `MAI.json` | `Mai` |
| Manon | `MANON.json` | `Manon` |
| Marisa | `MARISA.json` | `Marisa` |
| Rashid | `RASHID.json` | `Rashid` |
| Ryu | `RYU.json` | `Ryu` |
| Sagat | `SAGAT.json` | `Sagat` |
| Terry | `TERRY.json` | `Terry` |
| Zangief | `ZANGIEF.json` | `Zangief` |

若日期目录包含该角色的 OFF 原始文件，网页构建会自动解析并使用它，同时保存：

```text
off/<版本>/<Character>.official.raw.json
off/<版本>/<Character>.official.generated.json
```

若日期目录没有 OFF 原始文件，工具回退到仓库内已审核的：

```text
tools/modern_display_builder/out/<Character>.official.generated.json
```

回退文件同样会被快照到 `off/<版本>`，因此历史版本仍可复现。原始 OFF 只有招式表行时，生成文件使用 `_semantic_rows`；不要把官网行号当成 Action ID。

## 3. 可视化一键构建

双击：

```text
tools\action_runtime_compiler\start_html_builder.bat
```

本地服务只监听 `127.0.0.1:8765`。操作顺序：

1. 在“Dump 目录”填写日期目录绝对路径；
2. “本次版本”填写日期目录名；
3. 点击“扫描目录”，确认每个角色的 AC/BCM 成对；
4. 选择要更新的角色；
5. 可选指定历史对比版本；
6. 点击“编译并归档”；
7. 检查角色状态和差异；只有 `valid` 角色会更新 latest 目录。

同版本可分多次追加角色，也可重新选择角色覆盖。Windows 同版本覆盖使用原子临时文件；不会删除未选择角色。

## 4. AC / BCM / OFF 预览页

同一网页下方的“AC / BCM / OFF 数据预览”用于只读排查：

1. 选择归档版本；
2. 选择角色；
3. 点击“加载预览”；
4. 在四个标签间切换：
   - **AC 动作**：Action ID、scope、帧信息、Action 对象引用和字段 JSON；
   - **BCM 指令**：每个 Action ID/trigger 的 norm、easy、sprt、supr、按键 flags 和条件；
   - **OFF 官网语义**：招式名、分类、Classic/Modern 官网显示；
   - **最终 Modern**：最终 Action ID、显示、route owner、profile、来源和置信度。
5. 使用搜索框按 Action ID、`SP`、`AUTO`、profile、招式名或来源字段过滤。

预览接口不会把完整的数十 MB 对象图直接发送到浏览器；服务端先解析为只读表格摘要。展开 JSON 可以查看该行的引用、条件或路线证据。

## 5. 生成链与输出

```text
AC Action ID/关系
        +
BCM trigger/profile/command
        +
OFF Classic↔Modern 玩家语义
        ↓
版本化 runtime + exceptions + modern_display + audit + diff
```

主要输出：

- `char/<版本>/<Character>.json`：内部 action runtime；
- `char/<版本>/<Character>.exceptions.json`：兼容现有 Lua 的角色检测表；
- `char/<版本>/<Character>.modern-display.json`：带 route provenance 的 Modern 显示表；
- `char/<版本>/<Character>.report.json`：编译诊断；
- `char/<版本>/<Character>.compatibility.json`：旧检测表兼容审计；
- `char/<版本>/<Character>.diff.json`：相对基准版本的角色差异；
- `char/<版本>/differences.json`：本次版本汇总差异；
- `acbcm/<版本>/manifest.json`：中文 stem、规范角色名、fighter ID、AC/BCM 文件与哈希；
- `off/<版本>/manifest.json`：OFF 原始/语义快照与哈希。

差异包括 AC/BCM 源哈希、Action ID、显示、别名、TC、检测规则和 Modern 映射的新增、删除、变化。

## 6. OFF 单独更新

通常日期目录中的 OFF 会由网页自动转换。需要单独从官网下载或转换时使用：

```powershell
python tools/modern_display_builder/extract_modern_display.py `
  --character Ingrid `
  --official-dump "D:\CP\SF6CR-evidence\AC+BCM+OFF\2026.5.28\INGRID.json" `
  --output tools/modern_display_builder/out/Ingrid.official.generated.json
```

也可使用 `--url` 从 Capcom frame 页面读取，或用 `--html` 读取保存的页面/JS chunk。详细说明见 `tools/modern_display_builder/README.md`。

## 7. 命令行单角色编译

```powershell
node tools/action_runtime_compiler/compile.js `
  --ac <完整AC.json> `
  --bcm <完整BCM.json> `
  --output <角色简表.json> `
  --report <编译报告.json> `
  [--exceptions <可选人工例外表.json>] `
  [--character <规范角色名>]
```

命令行入口适合开发和回归；日常版本归档应使用网页，避免漏掉 manifest、OFF 快照和版本差异。

## 8. 同步与边界

- `latest_exceptions` 可复制到游戏 `data/TrainingComboTrials_data/exceptions`；
- `latest_modern` 可复制到游戏 `data/TrainingComboTrials_data/modern_display`；
- 归档目录被 `.gitignore` 排除，不提交大型 dump；
- `tools/modern_display_builder/out` 是小型、可审查的官网语义输入，可提交；
- 工具不会修改用户录制的连段 JSON；
- 未通过 hard gate、截断、角色不匹配或兼容审计的角色不会更新 latest。

## 9. 测试

```powershell
node tools/action_runtime_compiler/test_official_semantics.js
node tools/action_runtime_compiler/test_preview_builder.js
node tools/action_runtime_compiler/test_compiler.js
node tools/action_runtime_compiler/test_archive_builder.js
node tools/action_runtime_compiler/test_modern_display.js
node tools/bcm_catalog_builder/test_bcm_catalog.js

node tools/action_runtime_compiler/verify_known_samples.js `
  --evidence-dir "D:\CP\SF6CR-evidence\AC+BCM+OFF"
```

最后一条使用外部研究 dump 做已知样本回归，只读数据，不把研究文件写入仓库。
