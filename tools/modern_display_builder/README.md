# 官网指令语义快照工具

本目录只负责从 Capcom 官网数据生成 Classic/Modern 语义候选快照。官网 Action ID 不是游戏
Action ID，快照不能直接作为运行时角色表。

30 角色正式生成流程：

```powershell
tools\action_runtime_compiler\1_fetch_official_and_diff.bat 2026-05-28
tools\action_runtime_compiler\2_build_lastjson.bat 2026-05-28
```

第一步写入版本化 `off/<版本>` 快照；第二步把 AC、BCM 与官网语义统一编译为
`xt.command_display.v1`，正式数据位于：

```text
data/TrainingComboTrials_data/command_display/<Character>.json
```

单角色抓取工具 `extract_modern_display.py` 仅用于研究候选，输出仍采用
`xt.modern_display.v1` 官网语义 schema，不得直接复制到正式目录。

测试：

```powershell
python tools/modern_display_builder/test_official_snapshot_tool.py
```
