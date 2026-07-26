# AGENTS.zh-CN.md

语言：[English](AGENTS.md)

## 文档导航

* [项目首页](README.md)
* [项目愿景](VISION.zh-CN.md)
* [项目发展规划](ROADMAP.zh-CN.md)
* [架构设计](ARCHITECTURE.zh-CN.md)
* **AI 开发规范**
* [贡献指南](CONTRIBUTING.zh-CN.md)

---

# SF6CC AI 开发规范（中文版）

本文档定义了 AI 编程助手（Codex、Claude Code、Gemini CLI、Cursor、Windsurf 等）参与 SF6CC 项目开发时必须遵循的规范。

本文档也是项目的设计原则说明。

---

# 项目定位

SF6CC 是基于 WTT（SF6 Tools）发展而来的社区增强版本。

我们的目标不是简单地修改脚本，而是打造一套长期维护、易于扩展、易于学习的《街霸6》训练生态。

项目重点包括：

* 更好的训练体验
* 更好的 UI/UX
* 更好的本地化
* 更低的学习门槛
* 更丰富的社区内容
* 更高的代码质量
* 更好的长期可维护性

---

# 项目边界

本仓库只负责 **REFramework Lua 部分**。

SF6CM（社区平台）是独立项目。

职责划分如下：

SF6CC：

* Lua
* UI
* 数据解析
* 连段训练
* JSON 数据

SF6CM：

* 社区
* 网站
* 数据库
* 搜索
* 分享
* 下载
* 用户系统

两者只能通过 JSON 数据交换，不允许直接依赖。

---

# 仓库定位

本仓库代表的是 **REFramework 目录本身**。

也就是说：

仓库中的内容，应当能够直接作为游戏 `reframework` 文件夹中的内容进行安装。

本仓库不是完整的软件项目。

它是：

> Lua Framework + 数据资源

---

# 开发原则

除非有明确理由，否则：

优先保持：

* 模块化
* 可维护性
* 与 WTT 的兼容性

不要为了快速实现功能而破坏整体架构。

---

# Codex 记忆：本地固定路径

需要以下路径时，直接使用，不要重复询问，除非用户明确说明路径已变更。

* 角色 JSON 备份地址：`D:\CP\SF6CC\reframework\release\tester_packages`
* 工作区：`D:\CP\SF6CC\reframework`
* 游戏区：`D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework`
* Release 打包输出地址：`D:\CP\SF6CC\reframework\release`
* 可选游戏区 Release 输出地址：`D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\release`

备份地址属于本地工作存储。除非用户明确要求，不要把其中的文件视为源码或应提交的发布产物。

执行 Release 打包时，默认输出到上面的仓库 Release 路径。只有用户显式传入 `-OutputDir` 时，才使用游戏区 Release 输出路径。

---

# Release 打包规则

使用仓库内置打包程序，不要手工拼装 Release 文件。

手动打包命令：

```powershell
tools\bump_version.bat -Part Patch
tools\package_release.bat -Force
```

版本规则：

* `data/SF6CC/version.json` 是 Lua 运行时代码与 Release 打包器唯一的产品版本来源。
* 未来版本必须通过 `tools\bump_version.bat -Part Major|Minor|Patch` 或 `-Version <语义化版本>` 明确选择；检查并提交版本文件后再打包。
* 打包器读取统一产品版本。可选的 `-Version` 参数只用于一致性断言，必须与统一版本相同。
* 不要从 `sf6cm_manifest.json`、Lua 菜单文本、目录名、ZIP 名、Git Tag 或旧产物推断版本。
* 在线稳定版 `0.9a` 不可变；普通打包不得重建或覆盖 `0.9a`。

默认行为：

* 默认输出到仓库 `release/` 目录：`D:\CP\SF6CC\reframework\release`。
* 游戏区 Release 目录只是显式可选目标，例如 `-OutputDir "D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\release"`。
* 不要把游戏区 Release 目录当作默认发布目录。
* 脚本生成 `XiaoTun_SF6_TrainingMOD_v<版本号>.zip`、`XiaoTun_SF6_TrainingMOD_v<版本号>_runtime.zip`、两份解压目录，以及 `sf6cm_manifest_v<版本号>.json`。
* 统一产品版本、可选的命令行 `-Version` 断言、输出目录、ZIP 文件名和生成的 Manifest 版本必须一致。
* 普通包包含 `dinput8.dll` 和 `reframework\`。
* runtime 包额外包含 `re2_fw_config.txt`。
* `dinput8.dll` 和 `re2_fw_config.txt` 从本机《Street Fighter 6》游戏根目录复制。
* `reframework\` 内容来自仓库中 `autorun`、`data`、`fonts`、`images`、`plugins` 下的 Git 跟踪文件。
* 新增的打包源文件必须先纳入 Git 跟踪；如果这些打包源目录下存在未跟踪文件，脚本会直接失败。
* 不得包含运行时状态、ignored 文件、仓库内 `release/`、旧 ZIP、Dump 或临时打包输出。

如果用户只是需要自己打包，直接提供上面的命令。如果用户明确要求 Codex 执行打包，只运行该脚本，不要手工复制或压缩文件。

---

# Git 工作流

默认开发分支：

master

临时分支：

* feature/*
* bugfix/*
* refactor/*
* review/*
* import/*
* release/*

origin：

个人 Fork

upstream：

Wael3rd/SF6_Tools

不要直接向 upstream 推送。

提交信息必须使用中文。

提交信息应包含清晰的标题和详细说明，说明：

* 修改了什么
* 为什么修改
* 对运行时、发布包或兼容性的关键影响

---

# 决策优先级

所有开发决策遵循以下优先级：

1. 可维护性
2. 架构清晰
3. 用户体验
4. 本地化支持
5. 与 WTT 保持兼容
6. 性能
7. 新功能

如果两种方案功能相同，应优先选择结构更简单、更容易维护的方案。

---

# 架构原则

项目应尽量保持解耦。

建议分为四层：

UI

↓

逻辑

↓

数据

↓

运行时

各层职责明确，不相互混杂。

避免：

* UI 写业务逻辑
* Lua 写死角色数据
* 模块之间互相依赖

优先：

数据驱动（Data Driven）

而不是：

大量 if/else。

---

# Config 文件原则

不要认为所有 Config 都属于用户配置。

本项目存在两类 Config。

## 产品默认配置（应提交）

例如：

* 默认字体
* 默认窗口布局
* 默认颜色
* 默认模块启用状态
* 默认训练参数

这些属于产品体验，应纳入 Git 管理。

---

## 用户运行配置（不要提交）

例如：

* 当前窗口位置
* 当前角色
* 当前 Trial
* 最近打开内容
* 临时状态
* Session 数据

这些属于运行时数据，应本地生成。

---

# Runtime 文件

以下类型文件禁止提交：

* WebState
* WebBridge
* TrayState
* heartbeat
* LastFail.json
* sync_signal.json
* Replay Slot
* Cache
* Log
* 临时生成文件

运行时数据只能在本地生成。

---

# Release 文件

禁止提交：

* release/
* runtime/
* ZIP
* 临时打包文件

正式发布统一使用 GitHub Releases 或其它发布平台。

---

# Research 数据

研究数据不是源码。

例如：

* Dump
* 游戏解析数据
* Raw Methods
* 临时分析结果

这些应放在仓库之外，或加入 `.gitignore`。

---

# Combo 数据

以下属于正式项目资源，应纳入版本管理：

* Combo JSON
* Character Data
* Exception Rules
* Product Config

不要误删。

---

# 本地化

所有新增 UI 应优先考虑多语言。

避免硬编码字符串。

尽可能使用语言资源文件。

允许不同地区根据使用习惯调整默认布局和 UI。

---

# AI 修改规范

修改任何内容前，请先判断：

这个文件属于：

* 源码
* 产品默认资源
* 用户运行数据
* 调试文件
* 发布文件

不要仅根据文件名判断是否删除。

---

提交前必须确认：

* Runtime 文件未提交
* Release 文件未提交
* Dump 未提交
* 产品默认 Config 未误删
* JSON 数据完整

---

# 长期愿景

整个生态由三个独立层组成：

WTT Core

↓

SF6CC

↓

SF6CM

WTT 提供基础训练框架。

SF6CC 提供更好的训练体验、更好的 UI、更好的本地化。

SF6CM 提供社区平台、搜索、分享、评分以及在线内容。

未来希望：

**一个共享的 WTT Core。**

**一个持续演进的 SF6CC。**

**一个独立发展的 SF6CM 社区平台。**

三者保持解耦，通过统一的数据格式进行协作。

我们的目标不是做一个功能越来越多的 Mod，而是建立一个能够长期维护、持续发展的街霸训练生态。
