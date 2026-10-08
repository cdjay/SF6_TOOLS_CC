# CONTRIBUTING.md

Language: [简体中文](CONTRIBUTING.zh-CN.md)

Status: `CURRENT`

## Documentation

* [README](README.en.md)
* [Vision](VISION.md)
* [Roadmap](ROADMAP.md)
* [Architecture](ARCHITECTURE.md)
* [AI Development Guide](AGENTS.md)
* **Contributing**

---

# Contributing to SF6CC

Thank you for your interest in contributing to SF6CC.

SF6CC is a community-driven enhancement of WTT (SF6 Tools). Our goal is to improve the Street Fighter 6 training experience while maintaining a clean architecture and remaining compatible with upstream whenever practical.

---

# Before You Start

Please read the following documents first:

* [README](README.en.md)
* [AI Development Guide](AGENTS.md)
* [Architecture](ARCHITECTURE.md)

These documents describe the project's philosophy, architecture, and development guidelines.

---

# Development Philosophy

When contributing, please follow these principles:

* Prefer maintainable solutions.
* Prefer modular designs.
* Avoid unnecessary complexity.
* Keep unrelated changes in separate commits.
* Preserve compatibility with upstream whenever practical.

Not every improvement needs to be merged into WTT, but changes that benefit all users should remain mergeable.

---

# Repository Structure

Typical project areas include:

* Lua modules
* Training logic
* UI
* Localization
* Combo data
* Documentation

Please keep changes focused on a single area whenever possible.

---

# Branch Naming

The default development branch is `master`. Recommended temporary branch
names, as defined in [AGENTS.md](AGENTS.md):

feature/<name>

bugfix/<name>

refactor/<name>

release/<name>

review/<name>

import/<name>

---

# Commit Messages

Commit messages must be written in Chinese, as required by [AGENTS.md](AGENTS.md).
Use a short subject with a type prefix, followed by a body that explains what
changed, why it changed, and any runtime, release or compatibility impact.

Subject examples:

功能：木人库可将旧80栏录像恢复为原生8栏位

修复：训练场内搜索对战时木人库反复自动导入

优化：录像输入导入导出改为直接读写原生缓冲区

重构：拆分连段训练指令解析模块

文档：归档木人库80栏位调试日志

---

# Pull Requests

Before opening a Pull Request:

* Explain why the change is needed.
* Describe the implementation.
* Mention compatibility impacts.
* Include screenshots for UI changes when appropriate.

Large architectural changes should be discussed before implementation.

---

# Configuration Files

Please do not assume every Config file is user configuration.

Many Config files define product defaults such as:

* fonts
* layouts
* colors
* enabled modules

Only runtime-generated files should be excluded from version control.

---

# Runtime Files

Never commit runtime-generated files.

Examples include:

* WebState
* WebBridge
* LastFail.json
* sync_signal.json
* Replay data
* Cache
* Logs

---

# Release Files

Do not commit:

* ZIP packages
* release output
* runtime folders
* temporary build artifacts

Use GitHub Releases for distribution.

---

# Community Contributions

Contributions are welcome in many forms:

* Lua improvements
* UI/UX
* Localization
* Combo data
* Documentation
* Bug reports
* Performance improvements

Constructive discussions are always appreciated.

---

# Thank You

Thank you for helping make SF6CC better for the Street Fighter community.


AI-generated contributions are welcome, but contributors are responsible for reviewing and testing all generated code before submission.
