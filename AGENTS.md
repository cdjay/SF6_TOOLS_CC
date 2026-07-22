# AGENTS.md

Language: [简体中文](AGENTS.zh-CN.md)

## Documentation

* [README](README.en.md)
* [Vision](VISION.md)
* [Roadmap](ROADMAP.md)
* [Architecture](ARCHITECTURE.md)
* **AI Development Guide**
* [Contributing](CONTRIBUTING.md)

---

# SF6CC AI Development Guide

This document defines how AI coding assistants should work in this repository.

It applies to Codex, Claude Code, Gemini CLI, Cursor, Windsurf and any future AI development tools.

---

# Project Overview

SF6CC is a community-enhanced fork of WTT (SF6 Tools).

The project focuses on improving the Street Fighter 6 training experience while remaining compatible with the upstream project whenever practical.

The long-term goals are:

* Better UI/UX
* Better localization
* Better combo training
* Better learning experience
* Better community integration
* Clean architecture
* Long-term maintainability

This repository contains the Lua framework only.

SF6CM (Community Manager) is a separate project.

The Lua project and SF6CM communicate only through JSON data.

There must be no direct dependency between them.

---

# Repository Philosophy

This repository represents the REFramework folder contents.

Everything inside this repository should be installable into the game's REFramework directory.

Release packages are generated from this repository.

Do not treat this repository as an application project.

It is a framework + data project.

---

# Working Rules

Always work inside this repository.

Do not assume sibling directories exist.

Do not modify external projects unless explicitly requested.

Temporary Git worktrees may exist.

Only use temporary worktrees when specifically instructed.

Normal development always happens on the main development branch.

---

# Codex Memory: Local Paths

Use these fixed local paths when the task needs them. Do not ask for them again unless the user says they changed.

* Character JSON backup path: `D:\CP\SF6CC\reframework\release\tester_packages`
* Workspace: `D:\CP\SF6CC\reframework`
* Game REFramework path: `D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework`
* Release packaging output path: `D:\CP\SF6CC\reframework\release`
* Optional game release output path: `D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\release`

The backup path is local working storage. Do not treat files there as source files or release artifacts to commit unless the user explicitly requests it.

When creating release packages, write package output to the repository release path above by default. Use the game release output path only when the user explicitly passes it as `-OutputDir`.

---

# Release Packaging Rule

Use the checked-in packaging program instead of manually assembling release files.

Manual command:

```powershell
tools\package_release.bat -Version <version> -Force
```

Version rules:

* Every release package must explicitly pass the intended target version with `-Version`.
* Do not use "latest package" as a release target. Do not infer a release version from `sf6cm_manifest.json`, Lua UI text, folder names, zip names, Git tags, or previous artifacts.
* The current release target is `0.99`. Future release versions must be chosen explicitly; do not infer them from existing artifacts or manifests.
* `0.9a` is the online stable release and must be treated as immutable. Normal release packaging must not rebuild or overwrite `0.9a`.
* Rebuilding an immutable stable release requires an explicit special override and must be done from the corresponding tag, commit, or isolated worktree, never silently from the current development `HEAD`.

Default behavior:

* Output goes under the repository `release/` directory by default: `D:\CP\SF6CC\reframework\release\<version>`.
* The game release directory is only an explicit optional target, for example `-OutputDir "D:\Program Files (x86)\Steam\steamapps\common\Street Fighter 6\reframework\release"`.
* Do not treat the game release directory as the default publishing directory.
* The script creates `XiaoTun_SF6_TrainingMOD_v<version>.zip`, `XiaoTun_SF6_TrainingMOD_v<version>_runtime.zip`, unpacked folders for both packages, and `sf6cm_manifest_v<version>.json`.
* The command-line `-Version`, output folder, zip file names, and generated manifest version must all match.
* If the version output directory or target package files already exist, packaging fails by default.
* `-Force` may overwrite an existing version output only after backing it up to `release\backups\<version>_<timestamp>\`.
* `-DryRun` must show the planned version, branch, commit, output directory, source manifest version, package file names, existing artifacts, and overwrite status without generating package files.
* The standard package contains `dinput8.dll` and `reframework\`.
* The runtime package additionally contains `re2_fw_config.txt`.
* `dinput8.dll` and `re2_fw_config.txt` are copied from the local Street Fighter 6 game root.
* `reframework\` contents are copied from Git-tracked files under `autorun`, `data`, `fonts`, `images`, and `plugins`.
* New package-source files must be tracked by Git before packaging; untracked files under those package-source directories make the script fail.
* Runtime state, ignored files, repository `release/`, old ZIPs, dumps, and temporary build output must not be included.

If the user asks to package a release and does not need Codex to run it, provide the command above. If Codex is explicitly asked to package, run this script rather than doing manual copy or ZIP steps.

---

# Git Workflow

Default development branch:

master

Temporary branches:

feature/*
bugfix/*
refactor/*
release/*
review/*
import/*

origin = personal fork

upstream = Wael3rd/SF6_Tools

Never push directly to upstream.

Commit messages must be written in Chinese.

Commit messages should include a clear subject and detailed body explaining:

* what changed
* why it changed
* important runtime, release or compatibility impact

---

# Development Priorities

When making decisions, follow this priority order:

1. Maintainability
2. Clean architecture
3. User experience
4. Localization
5. Upstream compatibility
6. Performance
7. New features

Never sacrifice maintainability for short-term convenience.

---

# Architecture Principles

Prefer modular design.

Avoid duplicated code.

Prefer reusable utility functions.

Prefer data-driven logic over hardcoded behavior.

Separate:

* UI
* Logic
* Data
* Runtime state

Avoid coupling unrelated systems.

---

# Configuration Philosophy

Not every Config file is user configuration.

Many Config files define product defaults.

Examples include:

* default fonts
* default UI
* default layouts
* default colors
* default enabled modules
* default training behavior

These files are part of the product.

Do not remove or ignore Config files simply because they contain "Config".

Evaluate their purpose first.

---

# Runtime Files

Runtime-generated files must never be committed.

Examples:

* WebState
* WebBridge
* TrayState
* heartbeat
* LastFail.json
* sync_signal.json
* replay slot data
* temporary cache
* generated logs

These should be generated locally.

---

# Release Artifacts

Do not commit:

* release packages
* runtime folders
* ZIP files
* temporary build output

Publish releases using GitHub Releases or external storage.

---

# Research Data

Large research dumps are not source code.

Do not commit:

* dump files
* extracted game data
* temporary analysis files

If required, store them outside the repository.

---

# Combo Data

Combo JSON files are product assets.

Exception databases are product assets.

Character data is product data.

These should be version controlled.

---

# Localization

Localization should always support multiple languages.

Avoid hardcoded text.

Prefer language resources whenever practical.

UI changes for different regions are acceptable if they improve usability.

---

# Community

SF6CM is an independent project.

This repository should not directly depend on:

* website
* database
* backend services

Only shared JSON specifications should be considered common interfaces.

---

# AI Expectations

Before making large changes:

Explain the architecture impact.

Before deleting files:

Determine whether they are:

* source
* product defaults
* runtime
* generated
* release artifacts

Never assume deletion is correct.

Before committing:

Verify that runtime files are excluded.

Verify that release artifacts are excluded.

Verify that product defaults remain intact.

---

# Long-Term Vision

The ecosystem consists of three independent layers:

WTT Core

↓

SF6CC

↓

SF6CM

WTT provides the shared training framework.

SF6CC enhances the user experience and localization.

SF6CM provides community features and online content.

Each layer should remain as independent as possible while sharing common data formats.

The goal is to build a sustainable, maintainable, community-driven project that can continue evolving for many years.
