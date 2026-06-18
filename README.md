# SF6 REFramework 训练工具包

这是一个基于 REFramework 的 Street Fighter 6 训练工具包。它不是单一插件，而是一组放在 `autorun`、`data`、`plugins`、`guides` 等目录中的训练功能集合。

## 功能组成

主动训练功能：

- **Script Manager**：顶部菜单和训练模式总开关
- **Combo Trials**：自定义连段 Trial
- **Hit Confirm**：确认训练

辅助显示和被动功能：

- **Distance Viewer**：距离显示和区域提示
- **Sheldon's Boxes**：碰撞框、受击框、打击框显示

## 快速开始

1. 确认 SF6 已安装 REFramework，并且本目录位于游戏的 `reframework` 目录下
2. 启动游戏并进入训练模式
3. 按 `Insert` 打开 REFramework 菜单
4. 在训练工具顶部菜单中切换功能：
   - 确认训练
   - 连段训练
5. 需要自定义连段时，把 Trial JSON 放入对应角色目录

如果 REFramework 已生效但菜单呼不出来，可以尝试：

- 按 `Insert`
- 按 `Fn + Insert`
- 检查键盘是否有 `Ins` 组合键
- 查看 `reframework` 配置中是否改过菜单快捷键

## 指南索引

| 文档 | 内容 |
| --- | --- |
| [00_GettingStarted.md](guides/00_GettingStarted.md) | 安装、启用和基础操作 |
| [01_DistanceViewer.md](guides/01_DistanceViewer.md) | 距离显示工具 |
| [02_Training_ScriptManager.md](guides/02_Training_ScriptManager.md) | 顶部菜单和模式切换 |
| [03_CustomComboTrials.md](guides/03_CustomComboTrials.md) | 自定义连段 Trial |
| [04_HitConfirm.md](guides/04_HitConfirm.md) | 确认训练 |

## 目录说明

| 目录 | 说明 |
| --- | --- |
| `autorun/` | REFramework 自动加载的 Lua 脚本 |
| `autorun/func/` | 各训练工具的主要 Lua 模块 |
| `data/` | 插件数据、Trial JSON、配置和统计文件 |
| `fonts/` | UI 字体文件 |
| `guides/` | 中文使用指南 |
| `images/` | UI 或说明图片资源 |
| `plugins/` | REFramework 插件 DLL |

## Combo Trial 数据位置

自定义 Trial 通常放在：

```text
data/TrainingComboTrials_data/CustomCombos/[角色名]/
```

例如英格丽德的 Trial 放在：

```text
data/TrainingComboTrials_data/CustomCombos/Ingrid/
```

进入游戏后：

1. 切换到训练模式
2. 打开训练工具 UI
3. 切到 **连段 Trial**
4. 在文件选择中选中对应 Trial
5. 点击开始或使用对应快捷键加载

## 处理记录

- Akuma `Akuma_COMBO_6814_D6_SA3.json` 和 `Akuma_COMBO_7064_D6_SA3.json`：完整连段演示/复现会卡在最后 `623+LP`，但单独录制 `623+LP -> SA3` 可以通过。原因是完整连段里 `>6+P -> 623+LP -> SA3` 的上一动作 combo count 校验过严，命中/取消采样不稳定时会阻止步骤推进。已将末段 `>6+P` 和 `623+LP` 标记为 `is_projectile_hit: true`，复用现有逻辑跳过上一动作严格连段数校验。

## 架构说明

项目结构、Trial JSON 读取位置、Schema、HUD 绘制、输入验证和状态机说明见：

[ARCHITECTURE.md](ARCHITECTURE.md)

## 中文化说明

当前文档和主要 UI 已按中文使用习惯整理。中文 UI 依赖 `fonts/` 目录中的微软雅黑字体文件；如果游戏内中文显示为 `???`，优先检查字体文件是否存在，以及 Lua 中是否成功加载字体。
