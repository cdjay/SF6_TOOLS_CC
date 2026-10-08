# VISION.md

Language: [简体中文](VISION.zh-CN.md)

Status: `DESIGN`

## Documentation

* [README](README.en.md)
* **Vision**
* [Roadmap](ROADMAP.md)
* [Architecture](ARCHITECTURE.md)
* [AI Development Guide](AGENTS.md)
* [Contributing](CONTRIBUTING.md)

---

# SF6CC Vision

> **Building an open and sustainable training ecosystem for Street Fighter 6.**

---

# Why SF6CC Exists

SF6CC was never created simply to add more features to an existing training mod.

Its purpose is much larger.

We believe that learning Street Fighter should be easier, training should be more efficient, and community knowledge should be easier to share.

The project exists to reduce the learning barrier and help players improve together.

---

# Our Belief

Knowledge should be shared.

Training data should be reusable.

Communities should collaborate rather than duplicate work.

Open standards are more valuable than closed platforms.

Long-term maintainability is more important than rapid feature growth.

---

# One Shared Core

Our long-term vision is not to replace WTT.

Instead, we hope to contribute improvements back whenever they are useful for everyone.

```text
                WTT Core
                    │
      ┌─────────────┴─────────────┐
      │                           │
   SF6CC                     Other Community Editions
```

WTT should remain the shared training framework.

Community editions can focus on the needs of their own players while remaining compatible whenever practical.

---

# Independent Communities

Different communities have different needs.

Different languages.

Different UI preferences.

Different teaching styles.

Different workflows.

Those differences should be respected.

Each community should be free to build its own platform while sharing common technologies whenever possible.

---

# Shared Data

One of the most important long-term goals is a shared JSON specification.

```text
Combo Data
        │
Metadata
        │
Character Data
        │
Exception Rules
```

Communities should be able to exchange training content without needing identical websites or databases.

Platforms may differ.

Data should remain compatible.

---

# SF6CM

SF6CM is intentionally developed as an independent project.

Its responsibilities include:

* Community
* Search
* Sharing
* Downloads
* Metadata
* User content

The Lua framework should never depend directly on the website.

The website should never dictate how the Lua framework works.

JSON is the only shared interface.

---

# Open Collaboration

We believe collaboration creates better software.

Ideas should be discussed openly.

Architecture decisions should be documented.

General improvements should benefit everyone whenever possible.

Community-specific innovations are also valuable.

Both approaches can coexist.

---

# Free Forever

SF6CC will always remain free.

Players should never have to pay to access training features.

If the project receives support, it should come from the community rather than restricting functionality.

---

# Long-Term Sustainability

A successful project is not measured by how many features it has.

It is measured by:

* How easy it is to maintain.
* How easy it is to contribute.
* How easy it is to understand.
* How long it continues to evolve.

Every architectural decision should support those goals.

---

# Looking Forward

We hope that one day players from different regions will be able to:

* Share combo data.
* Share training ideas.
* Share knowledge.
* Learn from one another.

Not because they use the same website,

but because they share the same open standards.

---

# Our Goal

Our goal is not to build the biggest Street Fighter mod.

Our goal is to build a training ecosystem that can continue growing long after any individual contributor has moved on.

An ecosystem where:

* WTT provides the foundation.
* SF6CC improves the training experience.
* SF6CM connects the community.
* Open standards enable collaboration.

Together, these projects can help make Street Fighter training more accessible for everyone.
