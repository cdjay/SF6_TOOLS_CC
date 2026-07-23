# 小吞MOD：训练配置管理

对应脚本：`SF6CC_DynamicRecords.lua`

## 1. 功能范围

本脚本管理《Street Fighter 6》训练模式中属于陪练方（固定为 P2）的完整训练配置：

- 8 个动态记录槽。
- 动态记录槽的有效状态、启用状态、帧数、随机权重和输入缓冲。
- 倒地反击、格挡反击、受伤恢复后的反击三组设置，每组 10 个槽位。
- 训练记录的产品设置字段。
- 配置名称、整体备注以及各槽位的 ImGui 覆盖说明。
- 导入前自动备份、清空前自动备份和最近备份恢复。

脚本不依赖网站、数据库或 SF6CM。网页与 Lua 只通过 JSON 文件交换数据。

## 2. 相关文件

| 用途 | 路径 |
| --- | --- |
| REFramework 菜单与 ImGui 绘制 | `autorun/SF6CC_DynamicRecords.lua` |
| 数据采集、校验、导入和备份 | `autorun/func/DynamicRecords.lua` |
| 单页面配置编辑器 | `data/SF6CC_TrainingConfigs/editor/SF6CC_TrainingConfigEditor.html` |
| 用户配置目录 | `data/SF6CC_TrainingConfigs/configs/` |
| 自动备份目录 | `data/SF6CC_TrainingConfigs/backups/` |
| 配置列表索引 | `data/SF6CC_TrainingConfigs/config_index.json` |
| 最近备份标记 | `data/SF6CC_TrainingConfigs/latest_backup.json` |

`config_index.json`、`latest_backup.json`、配置 JSON 和备份 JSON 都是运行时文件，不应提交到 Git。

## 3. REFramework 一级菜单

一级菜单名称为“小吞MOD: 训练配置管理”，显示：

- 当前角色 `[name]`。
- 训练配置列表。
- 列表选中项的配置名称。
- 列表下方的灰色实际文件名。
- “导出配置”“导入配置”“清空”三个按钮。
- “高级 / 调试”二级菜单。
- “具体配置请在网站上配置和保存”的提醒。

切换配置列表选项会直接导入对应 JSON。“导入配置”按钮可重新导入当前选中项。

列表名称按以下优先级产生：

1. JSON 根节点的 `title`。
2. 兼容旧文件时使用 `description`。
3. 使用“角色名 + 训练配置”。
4. 无法读取元数据时显示“未命名配置”。

列表只显示 `configs/` 中当前真实存在且可以解析的 JSON。历史索引中的失效路径会被忽略，并在刷新后从索引中移除。

## 4. JSON 格式

当前格式标识：

```json
{
  "schema": "sf6cc.training_setup.v2"
}
```

### 4.1 根节点

| 字段 | 说明 |
| --- | --- |
| `schema` | 固定为 `sf6cc.training_setup.v2`。 |
| `created_at` | 导出时间。 |
| `title` | 配置名称；显示在 REFramework 配置列表中。 |
| `description` | 整体备注；不作为已有 `title` 的替代名称。 |
| `fighter_id` | P2 角色 ID。 |
| `fighter_name` | P2 角色名称。 |
| `source_player` | 固定为 `P2`。 |
| `slots` | 8 个动态记录槽。 |
| `reversals` | 三组反击设置。 |
| `settings` | 训练记录相关产品设置字段。 |
| `annotations` | ImGui 覆盖说明及其动作绑定。 |

网页中的“配置名称”写入 `title`，“配置说明”写入 `description`。修改整体备注不会改变 REFramework 列表名称。

### 4.2 动态记录槽

`slots` 必须包含 8 项。每项包含：

| 字段 | 说明 |
| --- | --- |
| `slot` | 1 到 8 的槽位编号。 |
| `is_valid` | 槽位是否存在有效录像。 |
| `is_active` | 播放时是否启用。 |
| `frame` | 录像帧数。 |
| `weight` | 随机播放权重。 |
| `input_num` | 输入数据帧数。 |
| `input_buff` | 每帧输入值；这是录像本体，不能省略或有损压缩。 |
| `capacity` | 游戏缓冲区容量，用于诊断和兼容检查。 |
| `fields` | 录像槽对象的可序列化标量字段。 |
| `input_fields` | 输入对象的可序列化标量字段。 |

`is_active`、`frame`、`weight` 等规范字段会与 `fields` 中的原始字段同时保存。规范字段供网页和跨版本逻辑使用，原始字段用于尽可能完整地恢复游戏状态。

### 4.3 反击设置

`reversals` 包含：

- `down`：倒地反击。
- `guard`：格挡反击。
- `damage`：受伤恢复后的反击。

每组必须包含 10 项。主要字段包括：

| 字段 | 说明 |
| --- | --- |
| `slot` | 1 到 10 的槽位编号。 |
| `active` | 是否启用。 |
| `type` | 反击动作类型。`-1` 表示空槽。 |
| `skill_index` | 技能或动态记录槽索引。 |
| `delay_frame` | 延迟帧。 |
| `count` | 反击数量。 |
| `meaty_frame` | 压起身相关帧值。 |
| `fields` | 游戏对象的原始标量字段。 |

当 `type == 4` 时，`skill_index` 指向动态记录槽的零基索引。ImGui 覆盖说明可以继承该录像槽的说明。

### 4.4 产品设置

`settings.record` 保存：

- `record_setting_fields`：训练记录全局设置。
- `fighter_fields`：当前 P2 角色的训练记录设置。

这些字段不是普通用户偏好，而是恢复训练配置所需的产品状态，因此不能仅因为它们看起来重复就删除。

### 4.5 ImGui 覆盖说明

`annotations` 包含：

- `record_slots[8]`。
- `reversals.down[10]`。
- `reversals.guard[10]`。
- `reversals.damage[10]`。

每个说明项包含 `slot`、`text` 和可选的 `binding`。

录像绑定签名：

```text
record-v1:<frame>:<input_num>:<input_buff rolling hash>
```

反击绑定签名：

```text
reversal-v1:<type>:<skill_index>:<level>
```

动作改变并导致签名不匹配时，Lua 会隐藏旧说明，避免把旧动作名称绘制到新动作上。

## 5. 导出流程

1. 固定读取 P2 角色。
2. 采集 8 个动态记录槽及输入缓冲。
3. 采集三组共 30 个反击槽。
4. 采集训练记录设置。
5. 保留当前 annotations。
6. 生成默认 `title`。
7. 写入 `configs/角色_时间.json`。
8. 更新配置索引并选中新文件。

## 6. 导入流程

1. 读取并校验 schema、角色、槽位数量和字段类型。
2. 在修改游戏数据前自动备份当前完整配置。
3. 先建立完整写入计划；校验失败时不开始写入。
4. 恢复训练记录设置字段。
5. 恢复 8 个录像槽及输入缓冲。
6. 恢复三组反击设置。
7. 根据选项执行 `ForceApply`。
8. 载入 annotations。

默认拒绝把一个角色的配置导入另一个角色，避免技能索引和反击动作错配。

## 7. 清空与恢复

“清空”会先创建完整备份，然后：

- 清空 8 个录像槽。
- 将权重恢复为 1。
- 清空三组共 30 个反击槽。
- 清空当前 ImGui 覆盖说明。

备份失败时，清空操作会取消。高级菜单可恢复最近一次备份。

## 8. ImGui 绘制规则

- 只在原生训练暂停菜单打开时绘制。
- 动态记录仅在“播放”分页绘制；“录制”分页不绘制。
- 反击说明根据当前 `ReversalType` 选择 down、guard 或 damage。
- 坐标按屏幕宽高比例计算，不使用固定分辨率坐标。
- 当前文字纵向校正以 `5 / 1080 × 当前屏幕高度` 计算。
- 绑定失效或说明为空时不绘制。

## 9. JSON 体积与优化结论

当前实测完整配置：

- 美化后的 JSON 约 24–37 KB。
- 去除空白后的 JSON 约 11 KB。
- 示例中录像输入值共约 427 项。

技术上可以继续缩小：

- 不写空 annotations。
- 删除规范字段与原始字段之间的重复值。
- 删除 `capacity` 等诊断字段。
- 对 `input_buff` 使用游程编码或二进制编码。
- 改为紧凑 JSON。

当前不建议实施这些优化，原因如下：

1. 目前文件只有几十 KB，对磁盘、网页上传和解析性能没有实际压力。
2. `input_buff` 是录像本体，有损或自定义压缩会提高损坏和兼容风险。
3. 规范字段与原始字段的双层结构用于兼顾网页编辑、跨版本逻辑和游戏状态完整恢复。
4. 固定长度 annotations 让槽位索引稳定，简化 Lua、网页和未来 SF6CM 的共同接口。
5. 删除字段会要求升级 schema、编写迁移器并同时更新 Lua、网页和未来社区服务。
6. 美化空白只影响文件体积，不影响游戏运行性能。

因此，`sf6cc.training_setup.v2` 当前没有值得以兼容性为代价实施的有效优化。若未来配置规模显著增长，应建立 `v3` schema 和明确迁移流程，而不是直接改变 v2 的含义。

## 10. 兼容约束

- 不改变 `sf6cc.training_setup.v2` 已有字段的语义。
- 新字段应保持可选，旧 Lua 和旧网页应能忽略。
- 不改变 `slot` 的 1 基编号。
- 不改变反击 `skill_index` 的游戏原生索引含义。
- 不把 P1 自动推断为录像来源；训练配置固定属于 P2。
- 不提交运行时生成的配置、索引和备份文件。
- 改动 JSON 格式时必须同步检查 Lua 导入、网页下载和 ImGui 绑定。

## 11. 修改后检查清单

- Lua 语法检查通过。
- 导出后列表只出现真实存在的配置。
- 网页修改 `title` 后，REFramework 列表名称发生变化。
- 修改 `description` 不影响已有 `title`。
- 录像槽开关、权重、帧数和输入缓冲可完整恢复。
- 三组反击的开关、动作、数量和延迟可完整恢复。
- 空槽不会被误判为有效槽。
- 导入和清空前均生成备份。
- 动态记录“录制”分页不绘制 ImGui 覆盖说明。
- 说明绑定失效时不绘制旧文字。
