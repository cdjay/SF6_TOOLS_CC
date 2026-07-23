# Merge Assessment for Wael / 给 Wael 的合并评估

Last checked: 2026-07-23

Baselines:

- SF6CC: `origin/master` at `6be373d` (`merge: 将SF6CC主线切换为纯ImGui渲染`)
- WTT: `upstream/main` at `c8a87ef` (`docs: convergence handover to cdjay (bilingual EN/中文)`)

---

## English

### Position

I do not think this is the right moment to return both projects to one `main` branch.

The better path is to keep both branches running as A/B implementations, freeze the shared JSON contracts, and move new work into a shared board so we avoid duplicated effort. Individual Lua modules should become shared only after their boundaries are extracted, tested, and accepted by both sides.

In other words: shared contract first, shared modules second, one main branch only after the core is actually decoupled.

### Source-level facts

| Area | SF6CC (`origin/master`) | WTT (`upstream/main`) | Merge impact |
|---|---|---|---|
| Git history | No merge base with `upstream/main`. | No merge base with `origin/master`. | A normal merge is not available. `--allow-unrelated-histories` is required, which means Git cannot reason about the shared ancestry of the files. |
| Forced merge result | `git merge-tree --allow-unrelated-histories` reports add/add conflicts in `README.md` and `docs/COMBO_JSON_SPEC.md`. | Same. | Only two textual conflicts appear immediately, but that is misleading: the real conflict is repository structure and ownership boundaries. |
| Repository model | The repository itself represents the game's `reframework` folder. Top-level package sources include `autorun`, `data`, `fonts`, `images`, `plugins`, `tools`, and `sf6cm_manifest.json`. | The repository is a distribution/project root with nested `reframework/`, root `dinput8.dll`, `roadmap/`, `tests/`, and handover docs. | Direct merge would mix two package models. Taking WTT's tree would delete or relocate SF6CC docs, tools and manifest; taking SF6CC's tree would require moving WTT's nested `reframework/*` content by hand. |
| Release system | Uses checked-in packaging scripts under `tools/package_release.bat` and `tools/package_release.ps1`; package sources must be Git-tracked. | WTT keeps `dinput8.dll` and nested `reframework/` in the project tree. | Release rules are incompatible. A merge before normalizing the release model risks producing wrong packages. |
| ComboTrials main script | `autorun/TrainingComboTrials_v1.0.lua`, 9234 lines. | `reframework/autorun/TrainingComboTrials_v1.0.lua`, 6017 lines. | Same product area, different implementation. A file-level merge would be a rewrite, not a normal integration. |
| UI/rendering path | SF6CC current main is pure ImGui-oriented and includes `autorun/func/ComboTrials_ImGui.lua` plus `ComboTrials_UI.lua`. | WTT uses `reframework/autorun/func/ComboTrials_D2D.lua`, `ComboTrials_UI.lua`, `ModernDisplay.lua`, `OpenableDropdown.lua`, and `i18n.lua`. | UI should remain A/B tested until a smaller shared core and per-language UI adapters exist. |
| Shared validator modules | `Validator.lua` is effectively aligned. SF6CC also has `ActionRestartDetector.lua` and `Telemetry.lua`. | `Validator.lua` is effectively aligned. WTT adds `BcmCatalog.lua` and does not carry SF6CC's `ActionRestartDetector.lua` / `Telemetry.lua`. | Some modules are good candidates for shared core, but the surrounding runtime differs. |
| Action matching and character rules | `ActionMatcher.lua` and `CharacterRules.lua` exist, with SF6CC-specific behavior and call paths. | Same module names exist, but WTT has additional BCM catalog wiring. | These should be compared module by module, not merged through the whole repository. |
| BCM/action catalog | SF6CC currently has no `data/TrainingComboTrials_data/bcm_catalog` directory in `origin/master`. | WTT has 30 `bcm_catalog/*.json` files using `sf6cc.action-runtime.v2` plus `BcmCatalog.lua`. | The data may be useful to import, but the loader/runtime decision must be made explicitly on SF6CC's side. |
| Modern command data | SF6CC has 30 JSON files under `data/TrainingComboTrials_data/command_display`. | WTT has 30 JSON files under `reframework/data/TrainingComboTrials_data/modern_display`. | The data purpose overlaps, but the directory name and resolver path differ. Treat this as contract alignment, not direct file replacement. |
| Exceptions data | Both sides have 32 exception JSON files. | Both sides have 32 exception JSON files. | Counts match, but content changed heavily. These need data review and regression tests before choosing one side. |
| JSON spec | `docs/COMBO_JSON_SPEC.md` exists and differs by only a few lines. | `docs/COMBO_JSON_SPEC.md` exists and differs by only a few lines. | This is the closest shared contract. It should be frozen first and used as the bridge between both projects. |
| DEMO playback | SF6CC has `raw_inputs`, timeline fallback, `CTStunDemoRuntime`, and an explicit control-mode mismatch fallback through `CTJsonInterop.warn_control_mode_mismatch`. | WTT has raw-input primary playback and timeline fallback, but does not carry SF6CC's control-mode mismatch fallback path. | Same JSON fields, different runtime policy. This should be A/B tested with the same combo files. |
| Same-action continuation | SF6CC keeps `is_same_action_continuation_step` and `ct_try_skip_unreported_same_action_pressure_step`. | WTT does not have these functions and relies on combo count plus the timeline normalizer. | This is a real technical fork. It should not be deleted without regression cases proving WTT's path covers the same failures. |
| DynamicRecords / RSM | SF6CC has `SF6CC_DynamicRecords.lua`, `DynamicRecords.lua`, and related editor/docs. | WTT keeps DynamicRecords and also has `SF6_RecordingSlotManager.lua` plus RSM data. | Feature overlap exists, but they are not the same system. This needs a product decision, not a merge conflict resolution. |
| SF6CM boundary | SF6CC keeps `sf6cm_manifest.json` and documents JSON-only interaction with SF6CM. | WTT does not carry the SF6CM manifest. | SF6CM compatibility is SF6CC-specific and should not be forced into WTT core. |

### What would happen if we merge now

If we merge the repositories now, one of three things happens:

1. We accept a mixed tree that contains two repository models at once. That would make release packaging, file ownership and runtime paths ambiguous.
2. We choose one tree as dominant. That would overwrite or delete working systems from the other side, including SF6CC's ImGui path, release scripts, manifest, telemetry/editor work, or WTT's nested package layout and additional modes.
3. We start a large manual migration. That is not a merge; it is a refactor project with high regression risk.

None of these gives us a reliable shared core today.

### Recommended collaboration model

The practical model is:

- Keep SF6CC and WTT as separate A/B implementations for now.
- Freeze `COMBO_JSON_SPEC.md` as the shared contract.
- Put new features on a shared board before implementation, with owner, affected Lua modules, affected JSON fields, tests and current status.
- Import improvements selectively by module or data contract, not by whole-branch merge.
- Promote a module into shared core only after it has a stable API, regression tests and a clear owner.

### Candidate order for future convergence

| Candidate | Recommendation |
|---|---|
| `COMBO_JSON_SPEC.md` | Freeze immediately as the shared contract. |
| `Validator.lua` | Good shared-core candidate because it is already effectively aligned. |
| BCM catalog data + loader | Useful, but import only after SF6CC decides whether to adopt `BcmCatalog.lua` and `sf6cc.action-runtime.v2` as runtime dependencies. |
| Modern command data | Align schema and resolver behavior first; do not blindly replace `command_display` with `modern_display`. |
| Exceptions | Review data diffs by character and test known combo cases. |
| DEMO playback policy | A/B test raw replay, timeline fallback and control-mode mismatch behavior with identical combo JSON. |
| Same-action continuation | Keep both approaches until regression tests prove one implementation covers both failure modes. |
| DynamicRecords / RSM | Treat as a product-level decision. The overlap is real, but the systems are not equivalent. |
| Full repository merge | Defer until shared core modules are extracted and the release/package model is unified. |

---

## 中文

### 立场

我认为现在还不是把两个项目重新合回同一个 `main` 分支的时机。

更合适的路径是：两个分支继续作为 A/B 实现并行运行，先冻结共享 JSON 契约；新功能进入共同看板，避免重复开发；单个 Lua 模块只有在边界被拆出、测试稳定、双方都接受之后，才进入共享模块。

换句话说：先统一数据契约，再统一模块，最后才考虑统一主线。统一 `main` 应该是解耦完成后的结果，而不是解耦前的手段。

### 源码层面的事实

| 领域 | SF6CC (`origin/master`) | WTT (`upstream/main`) | 合并影响 |
|---|---|---|---|
| Git 历史 | 与 `upstream/main` 没有共同 merge base。 | 与 `origin/master` 没有共同 merge base。 | 普通 merge 不成立，必须使用 `--allow-unrelated-histories`。这意味着 Git 无法基于共同祖先判断文件演进。 |
| 强行合并结果 | `git merge-tree --allow-unrelated-histories` 直接报告 `README.md` 和 `docs/COMBO_JSON_SPEC.md` 两个 add/add 冲突。 | 相同。 | 表面冲突只有两个，但这具有误导性；真正冲突是仓库结构和所有权边界。 |
| 仓库模型 | 仓库本身代表游戏的 `reframework` 文件夹。顶层包源包括 `autorun`、`data`、`fonts`、`images`、`plugins`、`tools`、`sf6cm_manifest.json`。 | 仓库是发布/项目根目录，内部再嵌套 `reframework/`，根目录还有 `dinput8.dll`、`roadmap/`、`tests/` 和交接文档。 | 直接合并会混合两套发布模型。采用 WTT 树会删除或搬移 SF6CC 文档、工具和 manifest；采用 SF6CC 树则需要手工搬移 WTT 的 `reframework/*`。 |
| 发布系统 | 使用仓库内 `tools/package_release.bat` 和 `tools/package_release.ps1`；包源文件必须被 Git 跟踪。 | WTT 将 `dinput8.dll` 和嵌套的 `reframework/` 放在项目树内。 | 发布规则不兼容。先合并再整理发布模型，容易产出错误包。 |
| ComboTrials 主脚本 | `autorun/TrainingComboTrials_v1.0.lua`，9234 行。 | `reframework/autorun/TrainingComboTrials_v1.0.lua`，6017 行。 | 同一产品领域，不同实现。文件级合并会变成重写，而不是常规整合。 |
| UI / 渲染路径 | SF6CC 当前主线已切到偏纯 ImGui 路径，包含 `autorun/func/ComboTrials_ImGui.lua` 和 `ComboTrials_UI.lua`。 | WTT 使用 `reframework/autorun/func/ComboTrials_D2D.lua`、`ComboTrials_UI.lua`、`ModernDisplay.lua`、`OpenableDropdown.lua`、`i18n.lua`。 | UI 应继续 A/B 测试，直到存在更小的共享 core 和独立语言/UI adapter。 |
| 共享 Validator 模块 | `Validator.lua` 基本已对齐。SF6CC 额外有 `ActionRestartDetector.lua` 和 `Telemetry.lua`。 | `Validator.lua` 基本已对齐。WTT 额外有 `BcmCatalog.lua`，但没有 SF6CC 的 `ActionRestartDetector.lua` / `Telemetry.lua`。 | 部分模块适合成为共享 core，但外围 runtime 已不同。 |
| 动作匹配与角色规则 | 存在 `ActionMatcher.lua` 和 `CharacterRules.lua`，保留 SF6CC 自己的行为和调用路径。 | 同名模块存在，但 WTT 增加了 BCM catalog 接线。 | 应逐模块比较和移植，而不是整仓 merge。 |
| BCM/action catalog | SF6CC 当前 `origin/master` 没有 `data/TrainingComboTrials_data/bcm_catalog` 目录。 | WTT 有 30 个 `bcm_catalog/*.json`，使用 `sf6cc.action-runtime.v2`，并有 `BcmCatalog.lua`。 | 这些数据可能值得导入，但 SF6CC 需要先明确是否采用 `BcmCatalog.lua` 和 v2 catalog 作为运行时依赖。 |
| 现代指令数据 | SF6CC 有 30 个 `data/TrainingComboTrials_data/command_display` JSON。 | WTT 有 30 个 `reframework/data/TrainingComboTrials_data/modern_display` JSON。 | 功能目标重叠，但目录名和解析路径不同。应视为契约对齐，不应直接互相覆盖。 |
| exceptions 数据 | 两边都有 32 个 exception JSON。 | 两边都有 32 个 exception JSON。 | 数量一致，但内容差异很大。需要逐角色数据审查和回归测试。 |
| JSON spec | `docs/COMBO_JSON_SPEC.md` 存在，只和 WTT 相差少数几行。 | `docs/COMBO_JSON_SPEC.md` 存在，只和 SF6CC 相差少数几行。 | 这是最接近统一的共享契约，应该优先冻结。 |
| DEMO 回放 | SF6CC 有 `raw_inputs`、timeline fallback、`CTStunDemoRuntime`，并通过 `CTJsonInterop.warn_control_mode_mismatch` 保留操作模式不匹配时的 fallback。 | WTT 以 raw input 为主路径，timeline fallback，但没有 SF6CC 这条 control-mode mismatch fallback。 | JSON 字段相同，但运行策略不同。应使用同一批 combo JSON 做 A/B 测试。 |
| 同动作连续判定 | SF6CC 保留 `is_same_action_continuation_step` 和 `ct_try_skip_unreported_same_action_pressure_step`。 | WTT 没有这两个函数，依赖 combo count 加 timeline normalizer。 | 这是实质性技术分叉。没有回归用例证明前，不应直接删除 SF6CC 实现。 |
| DynamicRecords / RSM | SF6CC 有 `SF6CC_DynamicRecords.lua`、`DynamicRecords.lua` 和相关编辑器/文档。 | WTT 保留 DynamicRecords，同时有 `SF6_RecordingSlotManager.lua` 和 RSM 数据。 | 功能重叠存在，但不是同一个系统。这里需要产品决策，不是解决 merge conflict 就能完成。 |
| SF6CM 边界 | SF6CC 保留 `sf6cm_manifest.json`，并文档化只通过 JSON 与 SF6CM 交互。 | WTT 不携带 SF6CM manifest。 | SF6CM 兼容属于 SF6CC 特有边界，不应强制进入 WTT core。 |

### 如果现在合并会发生什么

如果现在合并两个仓库，只会出现三种结果之一：

1. 接受一个混合树，同时存在两套仓库模型。发布打包、文件归属和运行路径都会变得模糊。
2. 选择其中一棵树作为主导。这会覆盖或删除另一边正在工作的系统，例如 SF6CC 的 ImGui 路径、发布脚本、manifest、telemetry/editor 工作，或者 WTT 的嵌套发布结构和新增训练模式。
3. 开始一次大型手工迁移。这已经不是 merge，而是高风险重构项目。

这些方案都不能在今天得到可靠的共享 core。

### 推荐合作方式

现实可行的合作方式是：

- SF6CC 和 WTT 继续作为两个 A/B 实现并行运行。
- 优先冻结 `COMBO_JSON_SPEC.md`，把它作为共享契约。
- 新功能进入共同看板，记录 owner、受影响 Lua 模块、受影响 JSON 字段、测试用例和当前状态。
- 按模块或数据契约选择性导入改动，不做整分支合并。
- 只有当一个模块具备稳定 API、回归测试和明确 owner 后，才提升为 shared core。

### 后续收敛顺序建议

| 候选项 | 建议 |
|---|---|
| `COMBO_JSON_SPEC.md` | 立即冻结为共享契约。 |
| `Validator.lua` | 适合作为 shared core 候选，因为当前已经基本对齐。 |
| BCM catalog 数据 + loader | 有价值，但 SF6CC 应先决定是否采用 `BcmCatalog.lua` 和 `sf6cc.action-runtime.v2` 作为运行时依赖。 |
| 现代指令数据 | 先对齐 schema 和 resolver 行为；不要直接用 `modern_display` 替换 `command_display`。 |
| Exceptions | 按角色审查 diff，并用已知 combo case 做测试。 |
| DEMO 回放策略 | 用相同 combo JSON A/B 测试 raw replay、timeline fallback 和 control-mode mismatch 行为。 |
| 同动作连续判定 | 保留两种实现，直到回归测试证明其中一种覆盖全部失败模式。 |
| DynamicRecords / RSM | 作为产品级决策处理。功能确有重叠，但系统并不等价。 |
| 整仓合并 | 延后到 shared core 模块已拆出、发布/打包模型已统一之后。 |
