# SF6 Combo Community (SF6CC)

🌐 Language

- **English**
- [简体中文](README.md)

> A community-driven training framework for Street Fighter 6.

SF6 Combo Community (SF6CC) is an open-source training framework built on top of **WTT (Wael Training Tools)**.

The project focuses on improving the overall training experience through better UI/UX, localization, data-driven design, and long-term maintainability.

Rather than being just another training mod, SF6CC aims to build a sustainable training ecosystem for the Street Fighter community.

---

# Why SF6CC?

Learning Street Fighter is challenging.

Players often need to:

* Learn complex combo notation
* Search through scattered resources
* Manually recreate training setups
* Watch long tutorial videos
* Verify whether their practice is correct

SF6CC aims to simplify this workflow.

Our goal is to make training more accessible, efficient, and enjoyable.

---

# Features

## Better Training Experience

* Improved UI/UX
* Localization support
* Cleaner workflows
* Lower learning barrier

---

## Training Modules

Current modules include:

* Combo Trials
* Hit Confirm Training
* Distance Viewer
* Script Manager
* JSON-based combo management

More training modules will continue to be added over time.

---

## Community Driven

Everyone is welcome to contribute.

Examples include:

* Combo data
* Lua improvements
* UI/UX
* Localization
* Documentation
* Bug reports
* Testing

Community contributions are a core part of this project.

---

## Free Forever

SF6CC will always remain free to use.

The project is committed to:

* Open source development
* Community collaboration
* Fair play
* Long-term sustainability

Training features will never be locked behind a paywall.

---

# Getting Started

Installation instructions will continue to improve.

The current workflow is:

1. Install REFramework
2. Download SF6CC
3. Copy the files into your Street Fighter 6 installation
4. Launch the game

Future releases will provide:

* Easier installation
* Automatic updates
* Local client support
* Community synchronization

---

## 📚 Documentation

- [Documentation Index And Current Authority](docs/README.md)
- [Current Architecture](ARCHITECTURE.md)
- [AC+BCM Semantic Core](docs/AC_BCM_SEMANTIC_CORE.md)
- [Testing Strategy](docs/TESTING_STRATEGY.md)
- [Known Limitations](docs/KNOWN_LIMITATIONS.md)
- [AI Development Guide](AGENTS.md)
- [Contributing](CONTRIBUTING.md)

Chinese entry: [README.md](README.md)

If you are using AI coding assistants such as Codex, Claude Code, Gemini CLI, Cursor or Windsurf, please start with [AGENTS.md](AGENTS.md).

Developers can run the current offline gate from a clean worktree:

```powershell
python tools\repository_test_audit.py --repo-root . --audit-date (Get-Date -Format yyyy-MM-dd) --run-tests --output (Join-Path $env:TEMP 'sf6cc-repository-test-audit.json')
```

---

# Architecture

The project follows a layered architecture.

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

Responsibilities:

* **WTT** — Shared training framework
* **SF6CC** — Training enhancements, localization, UI and data standards
* **SF6CM** — Community platform, metadata, downloads and online services

SF6CC and SF6CM remain fully decoupled and communicate only through standardized JSON data.

---

# Current Status

Current Runtime and architecture baseline:

* Production authority: Legacy
* M5 / MoveResolver: shadow only
* Frozen V2: unchanged
* Human review: 179 batches remain
* Real-game smoke: required
* Legacy OFF: blocked

Current project capabilities include:

* ✅ Localization improvements
* ✅ UI enhancements
* ✅ Combo Trials
* ✅ Hit Confirm Training
* ✅ Distance Viewer
* ✅ Script Manager
* ✅ JSON-based data structure
* ✅ AI development guidelines
* ✅ Architecture documentation

The project is actively under development.

---

# Roadmap

Future development focuses on:

* Community integration
* Automatic installation
* Replay analysis
* AI-assisted training
* Additional training modules
* Shared JSON specification

See [ROADMAP.md](ROADMAP.md) for more details.

---

# Contributing

Contributions are always welcome.

Whether you are interested in:

* Lua development
* UI/UX
* Localization
* Combo data
* Documentation
* Testing
* Bug fixes

please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a Pull Request.

---

# Acknowledgements

SF6CC is built upon the excellent foundation provided by **[WTT (Wael Training Tools / SF6_Tools)](https://github.com/Wael3rd/SF6_Tools)** and preserves the original MIT copyright notice and license terms.

Special thanks to **Wael3rd** for creating and maintaining the project.

Our goal is to contribute general improvements back to WTT whenever practical while continuing to improve the experience for our own community.

---

# License

Please refer to:

* [LICENSE](LICENSE)
* [LICENSE_NOTES.md](LICENSE_NOTES.md)
* [CREDITS.md](CREDITS.md)

---

> **SF6CC is more than a training mod.**

> **Our goal is to build an open, maintainable, and community-driven training ecosystem for Street Fighter 6.**
