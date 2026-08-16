# ARCHITECTURE.zh-CN.md

语言：[English](ARCHITECTURE.md)

状态：`CURRENT`

## 当前运行基线

- Action 语义生产权威：`Legacy`。
- M5 / `MoveResolver`：仅 Shadow 诊断。
- Frozen Combo V2：保持不变。
- Legacy OFF：阻塞。
- 人工语义审查与实机 Smoke：仍然必须完成。

下文的统一 Resolver 图是已批准的目标架构，不表示生产权威已经切换。

## 文档导航

* [项目首页](README.md)
* [项目愿景](VISION.zh-CN.md)
* [项目发展规划](ROADMAP.zh-CN.md)
* **架构设计**
* [AI 开发规范](AGENTS.zh-CN.md)
* [AC+BCM 语义核心](docs/AC_BCM_SEMANTIC_CORE.zh-CN.md)
* [贡献指南](CONTRIBUTING.zh-CN.md)

---

# SF6CC 架构设计（中文版）

## 文档目的

本文档用于说明 SF6CC 的整体架构设计。

它回答三个问题：

1. 为什么要这样设计？
2. 各个模块分别负责什么？
3. 后续新增功能应该放在哪里？

本文档既面向开发者，也面向 AI 编程助手（Codex、Claude Code、Gemini CLI 等）。

---

# 整体架构

整个生态由四层组成：

```text
Street Fighter 6
        │
        ▼
  REFramework
        │
        ▼
      WTT Core
        │
        ▼
       SF6CC
        │
        ▼
       SF6CM
```

各层职责如下：

**Street Fighter 6**

游戏本体。

负责游戏逻辑。

---

**REFramework**

提供 Lua 脚本运行环境。

提供 Hook、UI、绘图、事件等基础能力。

---

**WTT Core**

提供训练框架。

例如：

* Hook
* 绘图
* Script Loader
* 基础 UI
* 通用工具

所有对全球玩家都有价值的能力，应尽量保持与 WTT 兼容。

---

**SF6CC**

在 WTT 基础上提供增强功能。

主要负责：

* 中文化
* UI 优化
* 用户体验
* 连段训练
* 新训练模式
* 默认配置
* 数据规范

SF6CC 不负责网站。

---

**SF6CM**

SF6 Community Manager。

属于独立项目。

负责：

* 社区
* 网站
* 数据库
* 分享
* 搜索
* 下载
* 排名
* 用户系统

SF6CM 永远不要直接依赖 Lua。

Lua 也不要直接依赖网站。

双方只通过 JSON 进行数据交换。

---

# 仓库结构

```text
autorun/
    Lua 入口

autorun/func/
    公共模块

data/
    产品默认配置
    Combo 数据
    Exception 数据
    Character 数据

fonts/
    默认字体

images/
    图片资源

plugins/
    REFramework 插件

docs/
    项目文档
```

所有目录都应职责单一。

不要把不同类型的数据混在一起。

---

# 四层架构

## 第一层：UI

负责：

* ImGui
* Window
* 菜单
* HUD
* 图标
* 字体
* 用户交互

UI 不应该包含复杂业务逻辑。

---

## 第二层：Logic

负责：

* 连段解析
* 判定
* 训练流程
* 状态计算
* 输入解析

这一层应该尽量做到：

可测试

可复用

与 UI 解耦。

---

## 第三层：Data

负责：

* Combo JSON
* Character Data
* Exception Rules
* 默认配置

数据层不保存运行状态。

Lua 尽可能读取数据，而不是硬编码。

优先：

Data Driven（数据驱动）

而不是：

Hard Code（硬编码）。

---

## 第四层：Runtime

运行过程中生成。

例如：

* WebState
* WebBridge
* LastFail
* Replay
* Sync Signal
* Cache

这些文件禁止提交。

必须由程序自动生成。

---

# Config 设计原则

本项目中的 Config 分为两类。

## 产品默认配置（Product Config）

属于产品的一部分。

例如：

* 默认字体
* 默认窗口布局
* 默认按钮位置
* 默认颜色
* 默认模块启用状态
* 默认训练规则

这些文件必须进入 Git。

它们定义的是：

**产品体验。**

---

## 用户运行配置（Runtime Config）

例如：

* 当前窗口位置
* 最近打开内容
* Session
* 当前角色
* 最近 Trial

这些属于用户数据。

禁止提交。

---

# 数据驱动

本项目优先采用：

**Lua 描述逻辑。**

**JSON 描述内容。**

例如：

角色数据

↓

JSON

Combo

↓

JSON

Exception

↓

JSON

不要把角色数据写死在 Lua 中。

这样：

新增角色

新增连段

新增规则

都不需要修改 Lua。

---

# 模块化

每个模块只负责一件事情。

例如：

TrainingComboTrials

↓

只负责连段训练。

DistanceViewer

↓

只负责距离分析。

TrainingHitConfirm

↓

只负责确认训练。

模块之间不要互相调用内部实现。

公共能力应抽取到公共模块。

---

# 连段动作数据架构

目标架构不允许录制、检测、显示、审计分别维护角色动作语义。当前生产实现仍是 Legacy；AC+BCM 图与 Resolver 只用于 Shadow 对比和审查。

```text
当前版本 AC + BCM
        │
        ▼
xt.character_move_graph.v1
        │
        ▼
Lua MoveResolver
   ┌────┼────┬────┐
   ▼    ▼    ▼    ▼
 录制  检测  显示  审计
```

AC 负责 Action 全集和结构关系；BCM 负责实际输入入口、profile、触发条件和资源条件；OFF 只能作为名称或人工复核资料。

Action ID 不是跨版本主键。业务主键是 Move，Action 只是当前版本的绑定。旧版本 Combo 通过离线 AC+BCM 比对升级，不通过运行时永久映射解决。

显示 override 只能是诊断或极少数经证据确认的投影规则，不能改变录制和检测语义。Exception 也不能承载生成器本应识别的动作或指令。

---

# 主入口与模块边界

`autorun/TrainingComboTrials_v1.0.lua` 当前仍是较大的组合根和流程容器。现有提取工作冻结在当前安全基线；后续改动必须保持行为，并把新业务逻辑放入模块。长期方向仍是：

1. 冻结当前行为并建立 characterization tests；
2. 先把现有动作编译、检测、审计和训练环境流程搬入模块；
3. 用 MoveResolver 替换分散的 Action/指令解释；
4. 逐步删除旧兼容层和角色补丁；
5. 最后让入口只保留 Hook、生命周期、上下文和编排。

任何新业务逻辑都不得继续堆入入口文件。详细的数据契约、例外边界和迁移顺序见 [AC+BCM 语义核心](docs/AC_BCM_SEMANTIC_CORE.zh-CN.md)。

---

# 与 WTT 的关系

SF6CC 不是 WTT 的竞争项目。

SF6CC 希望：

尽可能把通用能力贡献回 WTT。

例如：

* 多语言
* UI 改进
* Bug 修复
* 公共组件
* 工具函数

而：

社区功能

网站

数据库

客户端

保持独立。

---

# 与 SF6CM 的关系

SF6CM 是社区平台。

负责：

发现内容

↓

下载 JSON

↓

管理 Metadata

↓

分享

↓

评分

↓

搜索

SF6CC 只负责：

读取 JSON。

这样：

即使网站关闭，

Lua 仍然可以正常运行。

保持完全解耦。

---

# 长期目标

未来希望形成如下生态：

```text
            WTT Core
                │
      ┌─────────┴─────────┐
      │                   │
      ▼                   ▼
    SF6CC             其它地区增强版
      │
      ▼
     SF6CM
```

WTT 负责全球共享的训练框架。

SF6CC 负责中文社区体验优化。

SF6CM 负责社区生态。

未来所有社区都可以共享统一的数据格式（JSON），在保持各自网站、数据库和社区独立的前提下，实现全球内容互通。

我们的目标不是做一个越来越复杂的 Mod，而是建立一个能够持续维护、方便协作、面向未来的街霸训练生态。
