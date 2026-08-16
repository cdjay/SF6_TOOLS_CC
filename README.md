# SF6 Combo Community（SF6CC）

🌐 语言

- **简体中文**
- [English](README.en.md)

> 让街霸训练更简单，让社区共同成长。

SF6 Combo Community（SF6CC）是一个面向 **Street Fighter 6** 的开源训练平台。

项目基于 **WTT（Wael Training Tools）** 持续发展，在保持兼容性的基础上，专注于改善训练体验、本地化支持、社区协作以及长期可维护性。

我们的目标不仅仅是开发一个训练 MOD，而是建立一套能够长期维护、持续成长的《街霸6》训练生态。

---

# 为什么选择 SF6CC？

《街霸6》的学习门槛并不低。

新玩家通常需要：

* 阅读大量术语
* 查找各种连段
* 手动录入训练内容
* 观看大量视频
* 反复验证是否练习正确

SF6CC 希望把这些流程变得更加简单。

我们的目标是：

> **让街霸训练像下载地图一样简单。**

---

# 功能特色

## 更好的训练体验

* 完整中文本地化
* 更符合中文玩家习惯的 UI
* 更清晰的训练流程
* 更低的学习成本

---

## 更完善的训练功能

目前已经包含：

* 连段训练（Combo Trials）
* Hit Confirm Training
* Distance Viewer
* Script Manager
* Combo 数据管理
* JSON 数据驱动

并持续扩展新的训练模式。

---

## 社区驱动

任何玩家都可以参与建设：

* 分享连段
* 提交训练数据
* 修正数据错误
* 提交 Bug
* 编写教程
* 提交 Pull Request

我们希望建立真正由社区共同维护的训练平台。

---

## 永久免费

SF6CC 将永久免费。

项目坚持：

* 开源
* 社区共建
* 不售卖训练内容
* 不提供作弊功能
* 不影响游戏公平性

---

# 快速开始

安装方式将在后续版本持续完善。

目前推荐：

1. 安装 REFramework
2. 下载 SF6CC
3. 按照安装说明复制到游戏目录
4. 启动游戏开始训练

未来将提供：

* 一键安装
* 自动更新
* 本地客户端
* 社区内容同步

---

## 📚 项目文档

- [文档入口与当前权威](docs/README.md)
- [当前架构](ARCHITECTURE.zh-CN.md)
- [AC+BCM 语义核心](docs/AC_BCM_SEMANTIC_CORE.zh-CN.md)
- [测试策略](docs/TESTING_STRATEGY.md)
- [当前限制](docs/KNOWN_LIMITATIONS.md)
- [AI 开发规范](AGENTS.zh-CN.md)
- [贡献指南](CONTRIBUTING.zh-CN.md)

English entry: [README.en.md](README.en.md)

如果你使用 AI 编程工具（Codex、Claude Code、Gemini CLI、Cursor、Windsurf 等），建议首先阅读 [AGENTS.zh-CN.md](AGENTS.zh-CN.md)。

开发者可从干净 worktree 运行下面的 executable test inventory 入口。它只是
正式离线门禁的一部分；作出发布结论前，必须继续执行
[测试策略](docs/TESTING_STRATEGY.md) 中的 corpus、determinism、mutation 与
oracle 完整命令。

```powershell
python tools\repository_test_audit.py --repo-root . --audit-date (Get-Date -Format yyyy-MM-dd) --run-tests --output (Join-Path $env:TEMP 'sf6cc-repository-test-audit.json')
```

---

# 项目架构

整个生态保持解耦设计。

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

各部分职责：

* **WTT**：训练框架
* **SF6CC**：训练增强、本地化、UI、数据规范
* **SF6CM**：社区平台、网站、Metadata、下载管理

SF6CC 与 SF6CM 仅通过 JSON 数据交换，不直接依赖彼此。

---

# 当前状态

当前 Runtime / 架构基线：

* Production authority：Legacy
* M5 / MoveResolver：仅 Shadow
* Frozen V2：保持不变
* Human Review：179 批仍需人工审查
* Real-game Smoke：仍需完成
* Legacy OFF：阻塞

当前项目已提供：

* ✅ 中文本地化
* ✅ UI 优化
* ✅ 连段训练增强
* ✅ Hit Confirm Training
* ✅ Distance Viewer
* ✅ Script Manager
* ✅ Combo 数据管理
* ✅ JSON 数据标准
* ✅ AI 开发规范
* ✅ 架构文档

项目仍在持续开发中。

---

# 项目路线图

未来将重点建设：

* 社区内容管理
* 自动安装与更新
* Replay 分析
* AI 辅助训练
* 更多训练模式
* 全球统一 JSON 数据规范

详细规划请参阅：

[ROADMAP.zh-CN.md](ROADMAP.zh-CN.md)

---

# 如何参与

欢迎任何形式的贡献：

* Lua 开发
* UI / UX
* 多语言支持
* Combo 数据整理
* 文档
* Bug 修复
* 测试反馈

提交代码前，请阅读：

[CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md)

---

# 致谢

SF6CC 基于 **[WTT（Wael Training Tools / SF6_Tools）](https://github.com/Wael3rd/SF6_Tools)** 持续发展，并保留原始项目的 MIT 版权声明与许可条款。

感谢 **Wael3rd** 为 Street Fighter 6 社区打造优秀的训练框架。

我们希望：

* 尽可能将通用能力贡献回 WTT；
* 在此基础上持续改善中文社区体验；
* 与全球社区共同推动统一的数据规范和开放的训练生态。

---

# License

请参阅：

* [LICENSE](LICENSE)
* [LICENSE_NOTES.md](LICENSE_NOTES.md)
* [CREDITS.md](CREDITS.md)

---

> **SF6CC 不只是一个训练 MOD。**
>
> **我们希望建立一个能够持续维护、开放协作、面向未来的街霸训练生态。**
