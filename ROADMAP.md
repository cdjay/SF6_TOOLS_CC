# ROADMAP.md

Language: [简体中文](ROADMAP.zh-CN.md)

Status: `DESIGN`

## Documentation

* [README](README.en.md)
* [Vision](VISION.md)
* **Roadmap**
* [Architecture](ARCHITECTURE.md)
* [AI Development Guide](AGENTS.md)
* [Contributing](CONTRIBUTING.md)

---

# SF6CC Roadmap

This document describes the long-term direction of the SF6CC project.

Rather than defining fixed release schedules, this roadmap explains our vision, development priorities, and long-term goals.

Our priority is to build a sustainable, maintainable, community-driven training ecosystem.

---

# Vision

SF6CC aims to become a complete training platform for Street Fighter 6.

Our goals are to:

* Make training more accessible.
* Improve the overall learning experience.
* Build a sustainable community.
* Encourage collaboration.
* Keep compatibility with WTT whenever practical.
* Promote knowledge sharing through standardized data.

Our objective is not simply to add more features, but to build a platform that can continue evolving for many years.

---

# Problems We Want to Solve

The current fighting game community still faces several challenges:

* Combo notation is difficult for beginners.
* Training resources are scattered.
* Learning paths are unclear.
* Community content is difficult to share.
* Different tools use different data formats.
* Valuable training content is difficult to maintain.

SF6CC aims to improve these areas over time.

---

# Current Stage (v0.x)

The current development phase focuses on building a solid foundation.

Key objectives include:

* Stabilize the architecture
* Improve the user interface
* Improve localization
* Standardize JSON data
* Improve documentation
* Improve maintainability
* Improve code quality

A stable foundation is more important than adding features quickly.

---

# Phase 1 – Better Training Tools

Primary focus:

* Combo Trials
* Hit Confirm Training
* Distance Viewer
* Script Manager
* Combo management
* Localization
* Better default configuration

The goal is to make SF6CC a complete and user-friendly training toolkit.

---

# Phase 2 – Community Integration

SF6CM is an independent project.

Its responsibilities include:

* Community platform
* Website
* Metadata
* Search
* Downloads
* User accounts
* Content sharing

SF6CC and SF6CM should remain completely decoupled.

The only communication interface between them is standardized JSON.

This allows the Lua framework to continue working independently, even without online services.

---

# Phase 3 – Standardized Data

One of the long-term goals is to establish a common data format.

Examples include:

* Combo data
* Character data
* Metadata
* Exception rules

The long-term vision is that different community websites can share the same JSON format while remaining operationally independent.

Each community may have its own:

* Website
* Database
* User system
* UI

while still sharing compatible training data.

---

# Phase 4 – Intelligent Training

Future research may include:

* Replay analysis
* Match analysis
* AI-assisted practice
* Intelligent combo recommendations
* Personalized training plans
* Learning progress tracking

AI should help players learn more efficiently, rather than replacing practice itself.

---

# Relationship with WTT

SF6CC is not intended to compete with WTT.

Whenever possible, improvements that benefit the broader community should remain compatible with upstream.

Examples include:

* Localization
* Bug fixes
* UI improvements
* Shared utilities
* Reusable components

Community-specific features, however, can continue evolving independently.

---

# Long-Term Ecosystem

```text
                WTT Core
                     │
       ┌─────────────┴─────────────┐
       │                           │
     SF6CC                Other Community Editions
       │                           │
       └─────────────┬─────────────┘
                     │
          Shared JSON Specification
                     │
       ┌─────────────┴─────────────┐
       │                           │
      SF6CM              Other Community Platforms
```

The long-term objective is to establish:

* One shared training framework.
* Multiple community-driven editions.
* One common JSON specification.
* Independent community platforms.

This encourages collaboration while allowing each community to evolve according to its own needs.

---

# Community

SF6CC will always remain free to use.

Future project support is expected to come from:

* Community sponsorship
* GitHub Sponsors
* Donations
* Educational content
* Community partnerships

The training tools themselves will remain freely available.

---

# Contributing

Everyone is welcome to contribute.

Examples include:

* Lua development
* UI/UX improvements
* Localization
* Combo data
* Character data
* Documentation
* Testing
* Bug reports
* New ideas

Every contribution helps improve the Street Fighter community.

---

# Final Goal

Our goal is not simply to create a larger mod.

Our goal is to build a long-term training ecosystem for the Street Fighter community.

We hope that players from different regions will eventually be able to share training content through a common data standard, while allowing each community to maintain its own platform and identity.

Together, we hope to build an open, sustainable, and collaborative future for Street Fighter training.
