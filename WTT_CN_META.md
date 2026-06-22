# 连段训练中文元数据

## `_xt_meta` 字段

小吞街霸6训练 MOD 在保存连段训练 JSON 时，会把展示和管理用的中文元数据写入 `sequence[1]._xt_meta`：

```json
{
  "_xt_meta": {
    "title": "板边全资源最大伤害",
    "note": "PC起手，6气3超",
    "author": "佚名",
    "tags": ["板边", "最大伤害", "全资源"],
    "created_at": "2026-06-21 18:30:00",
    "schema": 1
  }
}
```

字段含义：

- `title`：训练名称，保存时必填。
- `note`：备注，可为空。
- `author`：作者，默认读取 `TrainingComboTrials_data/XT_Settings.json` 的 `default_author`。
- `tags`：标签数组，保存窗口中用逗号分隔输入。
- `created_at`：保存时间。
- `schema`：元数据结构版本，当前为 `1`。

## 为什么写入 `sequence[1]`

连段训练 JSON 的主体是一个数组，每一项对应一个动作步骤。`sequence[1]` 是读取、显示、统计和保存流程中天然会访问的第一步，已有的起始位置、录制者、统计信息等全局连段信息也集中在这里。

因此 `_xt_meta` 放在 `sequence[1]`：

- 不改变 JSON 顶层结构，兼容旧读取逻辑。
- 不影响动作步骤数组的顺序和验证。
- 管理器读取时只需要打开 JSON 并检查第一项。

## 与 `_wtt_cn_meta` 的兼容关系

读取列表显示时按以下优先级取标题：

1. `sequence[1]._xt_meta.title`
2. `sequence[1]._wtt_cn_meta.title`
3. 文件名

`_wtt_cn_meta` 作为旧中文元数据字段保留兼容。新保存的文件使用 `_xt_meta`。

## 旧 JSON 回退规则

旧 JSON 没有 `_xt_meta` 时仍可正常加载和训练。元数据只用于列表显示、文件名和外部管理，不参与以下逻辑：

- 动作 ID 匹配
- `current_step` 推进
- `delay_from_prev` 验证
- `expected_combo` 验证
- hold / charge 验证
- timeline 播放
- `combo_stats` 计算

如果 JSON 损坏、缺少第一项或缺少元数据字段，列表显示会回退到文件名。

## 文件名与中文标题

保存时仍保留基础文件名规则：

```text
<角色>_COMBO_<起手>_<伤害>_D<Drive>_SA<SA>.json
```

如果训练名称只包含 ASCII 安全字符，会追加到文件名末尾。中文训练名称不直接写入文件名，避免 REFramework/Lua 路径编码在 Windows 资源管理器中显示乱码。中文名称以 `_xt_meta.title` 为准，游戏内列表和网页管理器应优先读取该字段显示。

## 中文输入方式

REFramework 的 ImGui 输入框通常不接 Windows 输入法组合输入，因此游戏内输入框只作为复制粘贴兜底。需要先运行一次 `TrainingComboTrials_data/XT_MetaInput.bat`，它会在后台常驻并监听保存请求：

- 输入窗口使用系统输入法，可以直接输入中文。
- 输入窗口读取 `XT_SaveMetaRequest.json` 获取本次保存请求和默认作者。
- 点击保存后写入 `XT_SaveMetaBridge.json`，Lua 轮询该文件并执行保存。
- 点击取消或关闭窗口会通知 Lua 取消本次待保存状态。

## 网页管理器读取方式

网页管理器扫描 `TrainingComboTrials_data/CustomCombos/<角色>/` 下的 JSON 后，可以按以下方式读取标题：

1. 解析 JSON 为数组。
2. 读取 `sequence[0]._xt_meta.title`。
3. 如果不存在，读取 `sequence[0]._wtt_cn_meta.title`。
4. 如果仍不存在，显示文件名。

网页管理器写入或更新连段库后，可以更新 `TrialHub/sync_signal.json` 的 `version` 或 `time`。游戏内脚本会每 1 到 2 秒检查一次该信号：空闲时刷新连段列表，训练中只提示“训练库已更新”。
