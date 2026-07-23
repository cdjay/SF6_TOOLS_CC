# AC + BCM + OFF Modern 指令生成工具

这套工具把游戏 dump 的 AC/BCM 与 Capcom 官网数据分开版本化，再为每个 AC/BCM 版本一次生成30个角色的统一指令表。

核心原则：

- 游戏 Action ID 和动作关系只认 AC+BCM；
- 官网 OFF 只提供招式名称、Classic/Modern 玩家语义，官网 Action ID 不能直接当游戏 Action ID；
- 每个日期目录是独立版本，不混用其他日期的原始数据；
- `lastjson` 必须一次成功生成30个角色，任何缺失或 hard audit 失败都不覆盖旧结果。

## 1. 最终目录

两个数据根目录直接位于本工具目录，不再放进 `html`：

```text
tools/action_runtime_compiler/
├─ acbcm/
│  ├─ 2026-05-28/
│  │  ├─ f001-fab-action-catalog-full-classic.json
│  │  ├─ f001-fab-bcm-full-classic.json
│  │  ├─ ...共30组...
│  │  ├─ lastjson/
│  │  │  ├─ Ryu.json
│  │  │  ├─ Luke.json
│  │  │  └─ ...正好30个角色JSON...
│  │  ├─ lastjson_web/
│  │  │  ├─ Ryu.json
│  │  │  ├─ Luke.json
│  │  │  └─ ...正好30个网页角色资料JSON...
│  │  └─ lastjson-manifest.json
│  └─ <下一个日期>/
├─ off/
│  ├─ 2026-05-28/
│  │  ├─ Ryu.official.generated.json
│  │  ├─ ...共30个官网快照...
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

Fighter ID 对应关系：

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

程序只请求一次 Capcom frame 页面和公共 frame 数据模块，从模块中解析30个角色，写入：

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
- `manifest.json`：30角色文件、Fighter ID 和快照哈希。

抓取或解析任一角色失败时，本次不会用半套数据覆盖目标版本。

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

生成条件：

1. 该版本必须有30组完整 AC+BCM；
2. `off` 下必须有同日期的30角色官网快照；
3. Fighter ID 不能缺失或重复；
4. AC、BCM和文件名 Fighter ID 必须一致；
5. 每个角色 AC+BCM 编译必须有效；
6. 统一指令输出 hard audit 必须通过；
7. 所有现代指令必须拥有经典投影，`classic_projection_pending_count` 必须为零；
8. 游戏与网页暂存目录都必须正好得到30个角色 JSON。

全部通过后才同时替换旧 `lastjson` 与 `lastjson_web`；若中途失败，两套旧结果都保持不变。

同一次生成还会更新 `acbcm/<版本>/lastjson_web/*.json`。网页文件使用
`xt.character.web.v1`，保留按 Action ID 查询的 `actions`，并从同版本 OFF 快照增加按招式记录查询的
`moves`、`move_order`、帧数、伤害、取消属性和量表字段。连段起手与角色资料页共享同一个 Action
指令投影，不需要网站再次解析指令文本。

`lastjson` 与 `lastjson_web` 必须同时正好生成30个角色；任一生成、校验或目录替换失败时，两套旧
结果都会保留。

`lastjson-manifest.json` 放在版本目录根部，不混入 `lastjson`，因此 `lastjson` 内始终正好30个可全选复制的角色文件。manifest 记录每个角色的输入文件、输出哈希、Action 数和相对覆盖前结果的新增/删除/变化 ID。

## 5. 官网文件名与角色名

新版抓取器直接以 SF6CC 规范角色名保存，例如：

```text
off/2026-05-28/Ingrid.official.generated.json
off/2026-05-28/EHonda.official.generated.json
off/2026-05-28/MBison.official.generated.json
```

官网 slug、规范角色名、Fighter ID 和 URL 的唯一清单位于：

```text
tools/modern_display_builder/characters.json
```

新增角色时必须先在该清单加入 `fighter_id`、`official_name` 和 `url`，并同步 AC/BCM 的 `FIGHTER_NAMES`。两个 BAT 都会检查角色数量和 Fighter ID 唯一性。

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
- 修改正式 `data/TrainingComboTrials_data/command_display`；
- 修改游戏区；
- 把官网 Action ID 当游戏 Action ID；
- 在缺少角色时输出残缺的 `lastjson`。

## 7. 统一指令表 v1

`xt.command_display.v1` 基于同一份 AC ActionGraph 输出经典与现代指令投影：

- `classic_command`：经典输入，来源顺序为 `norm → sprt`；
- `simple_command`：简化输入；同一招的等价方向保存在 `inputs` 中；
- `motion_command`：搓招输入；
- `relation`：派生动作通过 `type: followup` 和 `source_action_id` 引用前置动作。

运行时读取三个指令槽，并根据派生关系生成 `>`；`/` 只用于分隔完整的简化路线与搓招路线，
不再表示动作阶段。

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
