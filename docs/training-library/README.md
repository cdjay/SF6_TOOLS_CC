# 独立木人库技术说明

Status: `CURRENT`

## 当前状态（原生8栏位）

`codex/native-eight-slots` 从1.1.17建立，1.1.18起随完整包发布。运行入口改用只读的 `NativeEightRuntime`，
不加载 `NativeRecordingRuntime`，不替换录像数组、录制/播放菜单行或反击选择列表容量。
木人库顶层菜单、配置操作队列及栏位说明编辑仍保留。超过8槽的旧配置可见、可改配置名称，
但不可导入或用8槽快照覆盖。

2026-10-09 实机验收通过：冷启动进场、切换P2、匹配回场均不导入配置，录制/播放列表显示说明，
改名后列表同步更新；标签 `training-library-v1.1.18-native8`。旧80栏恢复与反击列表名称尚未单独实机确认。

进入训练场不再自动导入（2026-10-09，用户决定）：原生8槽的录像、反击及训练设置由游戏自己
持久保存，重新导入只会用文件覆盖玩家未保存的修改。会话开始时 `Library.restore_names`
只把当前选中项切回该P2记忆的配置；栏位说明不在游戏数据里，由 `Records` 按P2角色保存在内存，
整个Lua会话内跨场景保留（`select_fighter_annotations` 返回 same/cached/new），仅在该角色本次
首次出现（new）时由 `load_config_annotations` 从记忆的8栏配置读取说明，不触碰录像。
离开训练场只取消排队任务，不再清空栏位说明。

录制、播放和反击列表中的“编号 - 说明”显示由 `NativeSlotNames` 恢复（2026-10-09）：
它复用 `NativeRecordingNames` 与 `NativeReversalRecordings`（`expand=false`，栏位上限8，
不安装反击选择列表扩容钩子），只替换交给 `hGUI.setTextMessage` 的格式字符串，替换文字
使用永久缓存字符串。原生行按父页 `_FuncType`（录制107/播放108）与行 `_FuncType`（118/131）
及 `_SlotID` 识别；钩子在首次有活动会话且菜单关闭的更新中安装一次，失败即整体停用、不重试。
运行时上下文由 `NativeEightRuntime.context()` 提供，钩子内不重复读取训练数据。

若游戏从旧存档恢复了某个角色的80槽录像，木人库标签仍会在关闭菜单后安装，
该角色的配置列表仅供查看，保存、导入、清空及改名均禁用，首页第7行改为“恢复为原生8栏位”。
用户两次确认后，`Records.restore_native_bank` 用一个持有永久引用的8元素数组替换当前P2的
`RecordSlots`：第1～8栏保留原 SlotData 对象，第9栏以后丢弃；`Type == 4` 且
`SkillIndex >= 8` 的录像反击按清空规则重置，最后 ForceApply。不导出备份（用户要求）。
执行前要求录像器 `_gData` 的 `ReqType` 与 `State` 均为0（与旧扩容会话的空闲判断一致）；
随机播放旧数组可能使 `_gData.SlotID` 停在第9栏以后，而 `ChangeRecordSlot` 不检查范围，
因此越界的当前栏位改为0。恢复不导入任何配置；运行时从不自动缩减旧数组。

扩展到8栏以上已暂缓（2026-10-09 用户决定）。功能底线与已知引擎限制见
[KNOWN_LIMITATIONS](../KNOWN_LIMITATIONS.md)；9月80栏位方案的过程记录见
[开发与验收记录](DEVELOPMENT_HISTORY.md) 和 [归档日志](../archive/training-library/KNOWN_LIMITATIONS_LOG_2026-09.md)。

### 原生对象所有权（2026-10-08 崩溃分析后的硬约束）

10/8 崩溃转储证实：旧版扩容在场景切换时新建的菜单行被引擎在仍被引用时销毁，随后
`UpdateVM` 的循环引用回收访问已销毁对象而闪退。REFramework 的 Lua 引用按地址记账、
`add_ref` 去重，旧包装缓存或稍后的回收会释放属于同址新对象的引用；
`create_instance_global` 内部先加引用、压入 Lua 再释放，命中过期缓存时新对象出生即被释放。
因此本分支规定：

- 交给游戏结构引用的对象一律经 `NativeOwnership` 本地创建并加一份永久引用，从不由 Lua 释放；
  禁止 `create_*_global`、显式 `release()` 以及“一个给原生、一个给 Lua”的 `add_ref`。
- 标签页页面及13行每个 Lua 状态只建一次，训练 UI 重建后复用；同一会话内根菜单被游戏替换时停止。
- 钩子返回的文字使用按内容缓存的永久字符串（上限2048条，超出时返回帧内临时字符串）。
- 录像输入按 REArrayBase 布局（维度0x18、元素数0x1C、数据自0x20）直接读写，头部不符时回退装箱路径。

用户文档位于仓库根目录 [木人库使用说明](../../木人库使用说明.md)，随独立包放入 `reframework/`。
本目录面向维护者；[开发与验收记录](DEVELOPMENT_HISTORY.md) 只作为历史证据。
实际限制以 [KNOWN_LIMITATIONS](../KNOWN_LIMITATIONS.md) 为准，离线检查依据 [TESTING_STRATEGY](../TESTING_STRATEGY.md)。

## 范围与入口

- 这是独立的原生木人库插件，不依赖旧 `TrainingComboTrials_v1.0.lua` 或 SF6CM。
- 发布入口为 `autorun/SF6CC_TrainingLibrary.lua`，私有依赖为 `autorun/SF6CCTrainingLibrary/`。
- 发布包含延后初始化的游戏内木人库入口，不只是 ImGui 管理面板。
- 入口只组装 State、Library、NativeEightRuntime、Panel、NativeLibraryTab 和 NativeSlotNames，不承载角色动作语义。
- 依赖 REFramework 的 Lua/SDK 能力；本插件没有调用 REFramework.NET 或 MCP。开发机的 .NET/MCP 文件不属于发布依赖。

## 模块职责

| 模块 | 职责 |
| --- | --- |
| Context / State | 离线训练场边界（含匹配期间的 online 暂停）、共享运行状态与操作入口 |
| NativeEightRuntime | 原生8槽会话观察、按P2恢复选中配置与栏位说明，不替换录像数组 |
| NativeSlotNames | 原生录制/播放/反击列表的“编号 - 说明”显示（仅替换文字） |
| NativeOwnership | 交给游戏引用的对象与钩子文字的永久引用 |
| NativeRecordingPager | 页码提交协议，供 NativeLibraryPager 复用 |
| NativeRecordingNames | 原生录制/播放列表的名称解析，供 NativeSlotNames 使用 |
| NativeReversalRecordings | 三类反击录像选择及名称解析（`expand=false`，上限8） |
| Records / TrainingRecordImport | 配置读写、陪练格挡设置、录像及反击内容转换、导入与清空、按P2保存栏位说明 |
| Library | 当前选中配置、按角色记忆、统一操作队列；进场只恢复选中项与说明，不导入 |
| NativeLibraryTab / View / Pager | 木人库顶层标签、纯Lua页面状态及原生页码适配 |
| NativeNoteEditor / TrainingConfigNotes | 游戏输入框、配置标题与栏位说明修改 |
| NativeTicker / NativeLibraryFeedback / LibraryMessages | 游戏消息、操作结果精简与显示名称 |
| Panel | 保留的REFramework管理和排查面板，不作为日常必需入口 |
| 已停用：NativeRecordingRuntime / Session / Menu / Seed、NativeSaveCompletion、NativeMenu、NativeRecordingNamePage | 80栏位扩容的会话、菜单与存档替换；源码与测试保留，入口不加载 |

## 运行边界

只在确认离线训练、当前角色就绪、菜单关闭、录像空闲及保存空闲后挂载或处理配置。
配置修改通过共享队列执行。原生按钮接受操作后采用游戏原有关闭菜单返回值，不在点击回调直接导入录像。
进入训练场不导入任何配置；按P2记忆只用于恢复选中项和首次出现时的栏位说明，不把菜单绘制变成重复读取。

`Context.training_state()` 区分三种状态：`training` 可以操作；`online` 表示训练场结构完好、
只有网络对局规则为线上模式；nil 表示不在离线训练场。2026-10-09 实机日志证实：在训练场里
搜索排位赛时，`BattleRule.GameMode` 每次匹配尝试会在14与0之间切换约1秒，FlowMap 仍为3。
旧实现把每次切换当作离开训练场，结束会话后又重新接管并自动导入，配置提示每7～15秒弹出一次。
现在 `online` 只暂停：不执行队列任务，但不结束会话、不取消已排队操作，
名称输入框保持打开，消息提示照常显示。训练场结构性条件失效（对战场景、录像控制对象变化等）才算离开。

读取 `FighterDataList` 等 List 前先检查 `get_Count`：场景加载时P2已确定而列表仍为空，
越界的 `get_Item` 会在游戏内抛出 ArgumentOutOfRangeException，REFramework 随后在游戏线程上
执行引擎的异常清理；旧实现在每次进入训练场时每帧触发两次，持续约半秒。

Reset不保证正在显示的原生对象可立即重新创建；训练场内脚本重载在原生8栏位版本上未经验收，
发布文件更新仍采用关闭游戏后的冷启动。80栏位方案的扩展栏位、重新挂载及重载恢复记录已移入
[开发与验收记录](DEVELOPMENT_HISTORY.md)。

## 菜单契约

木人库在反击设置后，保留固定13个自有行对象，内页导航不重建数组、不主动调用整页刷新。
首页为切换配置、分割线、保存、另存、配置改名、栏位说明、清空、分割线和只读信息。

配置内页维持8项/页及第10行原生页码；栏位内页为首行页码、第2～9行栏位、第10行返回，尾部空行不可聚焦。
切换TEXT/SPIN样式不等于完成输入初始化，必须对实际页码行调用已验证的 `InitSpinBox(Int32)`。
页码变动复用 NativeRecordingPager 的已提交Index协议，不借用临时选项查询当最终选择。

栏位名称与帧数在闭菜单更新时捕获快照。只读 `IsValid/Frame`，不读取输入缓冲、不导出整个配置。
灰色空栏可提前编辑名称；未知长度不能误判为空栏。

原生录制、播放及反击名称替换采用“<PLUNUM> - 备注”（不加外括号），保留原生编号格式参数、
空说明回退及用户输入转义。只改显示字符串，不改annotations；栏位编辑列表的帧数布局不变。

顶层切换使用受当前会话、菜单实例、索引及自有根节点限制的 `ChangeTabIndex(Int32)` 前置钩子，
恢复自有行数据并取消确认，原生调用照常执行，不主动刷新。相同顶层索引更新不重置内页。

导入与清空都需要两次确认。清空首次只在原行增加“【再次确认清空】”，不发送操作队列或ticker；
第二次才提交原有clear操作。离开菜单或执行其他操作取消清空确认。
这层确认仅针对游戏菜单；旧管理面板的清空操作没有随本轮改变。

## 配置与名称

配置目录：`data/SF6CC_TrainingConfigs/configs/`。角色最后选择保存在 `last_selected.json`。
这些都是运行数据，不提交Git；仅在独立打包时按明确规则从游戏区复制已保存的配置。
用户未保存的当前录像不会被打包。

配置列表按当前P2过滤，标题格式使用中文括号，同名显示增加稳定编号。
配置改名只更新title并刷新目录，不改文件路径、录像或其他配置。
栏位说明属于当前运行快照，需要用户保存或另存才持久化。
选择配置与成功导入是两个状态：第一次确认只选中，第二次才提交导入；保存始终针对当前选中配置。

`settings.dummy.guard_fields` 只保存经过验证的陪练格挡字段：`GuardType`、`GuardWeight`、
`GuardCount`、`IsGuardSwitching` 和 `GuardOnlyType`。导入旧版 `sf6cc.training_setup.v2`
配置时，如果没有该对象，必须保留游戏当前格挡设置，不能补写默认值。训练模式临时接管格挡时，
使用同一字段读取器保存进入前状态，并在关闭模式、离开训练场、进入回放或脚本重载时尝试恢复。

## 发布方式

使用 `tools/package_release.ps1 -TrainingLibraryOnly`，不手工拼装ZIP。
追加 `-ExcludeDll` 可生成 `_NoDLL` 独立包，需要使用者预先安装兼容REFramework。
完整SF6CC包从1.1.15起同时包含齿轮快捷设置、新木人库及用户说明；打包时排除旧
`autorun/SF6CC_DynamicRecords.lua` 自动入口，旧组件单独打包能力保留。
覆盖升级不会自动删除用户目录里的旧入口，包内安装说明要求先移走该文件。
完整包不复制游戏区的私人录像、最后选择记录或视频演示配置。
网站发布用完整包的根目录只允许 `dinput8.dll`、`re2_fw_config.txt` 和 `reframework/`；
安装说明放在 `reframework/安装说明.txt`。打包前检查此路径约束，避免上传被拒绝（HTTP 422）。
2026-09-19修正未发布成功的1.1.15完整包：只移动安装说明位置，不修改游戏脚本；
以网站实际归档检查代码离线复现旧包拒绝，并验证修正后的标准包和runtime包。
ZIP 条目路径必须用 `/` 分隔且不能有空文件。2026-10-09 首次上传1.1.18被拒，原因是
`tools\package_release.bat` 调用的 Windows PowerShell 5.1 `Compress-Archive` 写入了 `\`；
打包脚本已改为自行写入条目，并在打包后核对条目名与内容哈希。
版本唯一来源是 `data/SF6CC/version.json`；先明确升级并提交版本及发布来源，再打包。
默认输出到 `release/<version>/`。组件包包含REFramework DLL、独立入口及所有私有Lua模块、用户说明、
配置编辑页面、版本信息、许可说明、当前已保存配置和最后选择记录。
不带技术开发史、探针、MCP、日志、历史备份、旧MOD、临时输出或未保存游戏状态。

包内 `package_manifest.json` 记录源提交、版本、各文件SHA256及配置数量。
打包后检查解压目录依赖闭包、入口加载、配置合法性、清单哈希和ZIP目录，不能只看ZIP创建成功。
## 验收边界

2026-10-09 实机（e8d0338 部署版本）：木人库菜单、录制/播放列表“编号 - 说明”、进场与匹配回场不导入、
切换P2静默切换配置、改名后列表更新、保存/另存/改名，以及搜索对战期间暂停均已确认。
尚未实机确认：旧80栏恢复为原生8栏位、1P切换、反击选择列表与总览名称、训练场内脚本重载。
“正式版ZIP”指可独立安装的发布产物，不等于扩大这些验收结论。
