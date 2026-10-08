# Recording Bank Draft

Status: `HISTORICAL` (offline draft for the retired 80-slot expansion; not a
native runtime feature). The 2026-09-14 lifecycle decision below was superseded
on 2026-10-09: the native-eight-slot library never imports on training entry.
See [Training Library](../../docs/training-library/README.md). The `vendor/`
JSON library remains in use by the CFN replay tools.

## Training-Only Lifecycle Decision (2026-09-14)

The user's revised scope separates saved MOD configuration templates from
temporary native training slots. On entering training, automatically reload the
last selected configuration for the matching P2 character. Loading replaces the
current bank; it does not merge native recordings. On leaving training or changing
character, unload the temporary bank without writing it back. No expansion may
remain active outside training. An explicit Save can update a MOD file, but no
exit/restart persistence of runtime edits or expanded native-save data is required.
Do not clear unrelated characters or bank0. Keep minimal protection against native
autosave accidentally serializing unsupported expanded structures.

The proposed all-character backup/save-roundtrip series is paused. Its read-only
scripts under exam were prepared but not deployed. This is not a new backup gate
the user must repeatedly run.

`manual_runtime.lua` implements the offline-tested command/lifecycle coordinator
over existing Session/Bank/codec/storage. Construction takes an optional remembered
fighter selection; successful manual loading updates it. The embedding UI may
provide its remembered selection. This module itself does not persist preferences
or prove cross-process recall, and named alternative profile selection is not yet
wired. No selection, or a different P2 character, means no automatic load.

Automatic load runs once per eligible training entry, after the context is idle.
A missing/corrupt configuration fails without preparing an empty native bank or
retrying disk I/O each frame. Manual unload suppresses reloading until the next
entry. Exit never saves/captures. Explicit Save stages a canonical runtime capture
without acknowledging it as saved, then uses the existing guarded storage path.
Staging retains the saved baseline and rejects foreign characters, reused or
regressing IDs and implicit reversal-reference changes.

### Native Adapter Contract (Integration Incomplete)

- `prepare(document, context)` validates a detached replacement and native-save
  isolation without live attachment. It returns an opaque lease table with
  `guard_ready=true` only when protection is actually ready; a fake adapter's
  boolean is not native evidence. Preparation owns cleanup if it fails before
  returning a lease.
- `attach(lease, context)` replaces only the captured P2 bank and relevant menu
  data on a permitted engine callback. Confirm with true; partial failures retain
  ownership until the coordinator invokes retirement.
- `retire(lease, currentContext, reason)` unloads native extensions without saving
  the MOD file. Validate live identity/thread before touching engine objects,
  including absent or different-character contexts. Unconfirmed retirement blocks
  further commands without automatic retries or blind release.
- `discard_prepared(lease, context)` safely releases an unattached candidate.
  Unconfirmed cleanup is blocked, not ignored.
- `capture(lease, context)` returns a canonical draft bank with stable IDs. Only
  explicit Save invokes this operation; empty native slots are not recordings.

Native menu wiring, allocation/capture, minimal save isolation and safe release
are still unfinished. The coordinator is NOT deployed. Render callbacks must
enqueue native work to an appropriate engine callback. Existing storage calls are
synchronous; production integration must defer disk work outside gameplay-critical
callbacks, including entry-triggered loading. Fake-adapter checks do not establish
native capacity or acceptance of the full in-game flow.

`native_array.lua` implements bounded Lua-SDK conversion for research:
at most nine slots, initialized UInt16 input buffers
and exact populated-input readback. It rejects unsupported file fields/reversal
references and UInt16 narrowing before allocation. It is not the full native
adapter above: guard_ready is deliberately false and no save hook exists. The
detached version passed the documented native preflight, but subsequent guarded
attach/detach methods have only fake-SDK coverage. Attach retains the original
fighter/array, checks identity and refuses a second mount of the same lease.
Close refuses attached/uncertain states. Detach accepts only the original or
installed bank; it never overwrites a third-party replacement. Disposal requires
separate permission that native consumers have stopped using the array.
See exam/native-training-library/LUA_RECORD_CONFIG_PREFLIGHT.md for the archived
fixture/code identity. That earlier native pass does NOT cover newer code.

`native_menu_mount.lua` consumes an owned nine-slot recording lease and prepares
both observed native pages (107/118 recording, 108/131 playback). It clones the
eighth row with SlotID=8, preserves non-slot rows and the import/export page,
validates both page layouts before allocation and never forces a view refresh.
Explicit attach binds recording data and both page child arrays. Retirement
restores pages then recordings; partial setter failures retain ownership for
retirement. External replacements or uncertain restoration latch failure without
blind retry/release. Close is separate from retirement because native views can
still cache restored-away rows. The module has no hooks or autorun entry point.

The constructor is `prepare(sdk, manager, recordingLease, fighterId, permit)`.
After calling it, retain either the returned lease or the third failed-lease
result; do not close its recording lease separately. A failed preparation can
contain uncertain native ownership and must not be dropped or automatically
retried. This differs from the final coordinator adapter contract above: a
runtime adapter must retain failed candidates itself before returning failure.

The permit is an **unimplemented integration requirement**, not a boolean to
enable for testing. It needs guard_ready plus allows(stage, owner, fighterId).
Menu stages use the TrainingManager; recording stages use the captured fighter.
It must certify offline training and the correct engine thread for preparation
and attachment; a working independent native-save return before any live write;
idle recorder/game-local state and safe selection indices before shrinking; and
completed native consumer/view release before disposal. Retirement may refer to
the retained old owner after native Release has cleared current _tData. A generic
`return true` callback is valid ONLY in fake-SDK tests, never a real permit.

There is currently no real permit provider, native save hook, game-local state
reset, hook/reset/reentry wiring, or runtime capture binding. Do not deploy these
modules as a playable feature or connect them to manual_runtime until those
requirements are implemented. All attach/retire tests remain simulations.
Research deployment copies are not release inputs or accepted live loading.

`native_save_projection.lua` adds the actual SDK-side independent snapshot builder,
but still does NOT install or authorize a save hook. It captures an eight-slot
baseline via native TrainingData.Duplicate. For a later save it duplicates current
data, validates per-bank identities/capacities and independent recording objects,
then changes only the copied current fighter's RecordSlots and the copied
SelectChildIndex. It never copies a whole donor FighterData or swaps a live field.
Unrelated settings come from the latest native duplicate. A failure returns the
retained baseline instead; those newer settings may not persist on that fallback,
so the future controller must retire rather than continue silently.

The research bound is one baseline plus at most two later projections, no
per-frame copies or unbounded save allocation. Native thread ID must match the
preparation thread. A returned snapshot is tracked by mark_returned and cannot be
released by close_unpublished; normal training exit is NOT proof that asynchronous
storage stopped using it. Failed native projection ownership is retained without
speculative release. No hook calls this module yet; guard_ready remains false.
Ten simulated cases validate its flow, not native Duplicate/publication/lifetime.
The read-only Lua lifecycle trace under exam is the next engine observation, not
another capacity or all-character backup/save-roundtrip test.

The 2026-09-14 Lua trace now confirms worker-thread native saves and release:
UpdateBehavior/script-reset thread 100048, Save 63060, SaveSaveData 54376,
Release 104180 in that process. SaveSaveData occurred AFTER Save POST and returned
live _tData. Therefore neither direct projection in the getter nor direct field
restoration in the Release hook is authorized. Queue release notifications to
the verified UpdateBehavior thread; prepare immutable save data there as well.
Do not release published snapshots at Save POST or assume Release POST proves
storage completion. Actual snapshot publication/async ownership remains a gate.
This supersedes any same-thread inference from the older C# pilot, not the known
native menu/array layout evidence. See the read-only trace document under exam.

`native_lifecycle.lua` implements the notification/retirement side of that
boundary. Its hook router leaves all arguments and returns unchanged; worker
callbacks only latch one of six fixed event flags for an opaque session token.
There is no unbounded event queue and late posts cannot target a new session
that reused the same manager address. Only tick on the captured UpdateBehavior
thread calls mount.retire/close. Save POST and SaveSaveData POST are explicitly
not completion fences and do not trigger disposal. Release POST requests
retirement, then positive can_retire and can_dispose checks gate two distinct
phases. False means wait; nil/error/failed native mutation blocks without retry,
retaining ownership. Hook observation errors are exposed as blocked status.

Create the lifecycle coordinator on UpdateBehavior, install its router once per
Lua state, and watch the owned mount before attachment. Do not construct it on
an arbitrary loader/render callback and assume that thread is the update thread.
The gates MUST come from the future native permit, not bare observed event flags.
Tests combine this coordinator with the actual native-array/menu modules under
a fake SDK, including the recorded four-thread event order. This is simulation,
not real concurrency/engine acceptance. Nothing installs this router in-game yet.

The synchronous manual_runtime adapter remains separate: it must not report
retirement complete merely because this coordinator queued it. Reset continuity,
save-return ownership and native consumer-completion evidence remain unresolved;
this module does not permit Lua reset while a bank or save snapshot is in use.

`core.lua` implements the recording-only part of the proposed per-character
library. It is deliberately outside `autorun`, is not packaged, and never
allocates native objects, installs hooks, reads files or saves automatically.
Existing training setup V2 and frozen Combo V2 are unchanged.

## Implemented Boundary

- At most 200 valid recordings, each with 1..3600 uint32 input frames. These are
  draft file limits, not established game limits. Empty native slots are not
  library recordings.
- A draft bank has `schema`, `fighter_id`, `source_player="P2"`, `next_id`,
  `records` and `record_refs`. A record has `id`, `name`, `enabled`, `weight`, and `recording`.
  `recording` retains `frame`, `input_buff`, `fields` and `input_fields`.
- `schema` is `sf6cc.training_record_bank.draft2`; this is not an accepted import
  format for `DynamicRecords` or a stable sharing contract.
- Recording-only `draft1` remains readable and migrates to an empty reference
  list in memory. Reading never rewrites the file; only explicit save publishes
  draft2. A draft1 document carrying new reference fields is rejected, not ignored.
- IDs are positive, bank-local, monotonically allocated and never reused after
  a saved deletion. Array positions are not IDs. Different banks may reuse IDs;
  merge returns an explicit source-ID to destination-ID map.
- Exact normalized input/length/native-scalar equality is the only dedup rule.
  Known selection fields (`IsActive`, `IsValid`, `Weight`) and redundant length
  fields (`Frame`, `Num`) are excluded. Other native scalar differences retain
  distinct recordings. This does not claim semantic equivalence across builds.
- Merge retains existing names, enabled flags and weights. Explicitly opening
  a different saved bank retains that bank's settings instead. Cross-character
  merge fails; there is no hardcoded 33-character inventory.
- `edit` accepts only name/enabled/weight; delete preserves surviving IDs.
  Names are bounded UTF-8 plain text. Native UI controls are not connected yet.
- Invalid edits and overflow merges are all-or-nothing. Snapshot tables do not
  alias internal state. Failed saves retain dirty edits; discard restores the
  last saved snapshot. Switching character/config must discard the old editor,
  not implicitly call save.

## Explicit Save Adapter

`save(writer)` calls the supplied writer only on explicit invocation. `true`
means the adapter has durably saved the complete detached document; failure or
exception leaves the bank dirty. Reentrant edits are blocked while saving.
`AtomicBankStore.cs` now supplies an **offline .NET filesystem backend**, tested
without game or bridge references. There is still no Lua-to-.NET wiring or native
menu integration. Do not substitute unchecked `json.dump_file` for publication.

The caller explicitly supplies a trusted absolute root directory. Files are
fixed as `fighter-<decimal-id>.json`, one default bank per character; no arbitrary
filename argument or implicit selection of another character is accepted.
Alternative named/shared profiles remain future work. Read returns bytes plus a
SHA-256 version, or null/null only for a missing file/path; sharing violations,
access errors, invalid JSON and corruption are errors, not an empty library.
Reparse-point roots/ancestors, target files and lock files are rejected.

Save accepts the version from the caller's read (null for an explicitly new bank).
A persistent `.json.lock` filename provides an exclusive cooperative-writer
lock. The backend validates the envelope and checks the expected version before
writing and again before replacing. It writes a unique same-directory
`.json.<GUID>.tmp`, flushes to disk, closes it, then uses `File.Replace` for an
existing file or non-overwriting `File.Move` for a new one. Exact-byte no-op saves
do not rewrite the target. Cleanup only removes that operation's temporary file;
abandoned temporary files are never promoted, read as banks or broadly deleted.
The committed file is bounded to 16 MiB, JSON depth 12, with duplicate keys,
foreign-character/schema envelopes and more than 200 records rejected.
Draft2 adds at most 600 recording-reference entries to the storage envelope;
the Lua model owns their target and group/location validation.

**Validation ownership:** the C# backend validates storage envelopes, not the
recording schema in parallel. The caller must serialize a validated Lua-model
snapshot before save and validate decoded bytes through `Bank.open` after read.
It must catch storage exceptions and only return true to `editor.save` when the
backend returns successfully. This connection is not implemented yet.

The lock serializes cooperating backend writers. The second version check detects
observed edits by other programs; it is not an OS compare-and-swap guarantee
against an uncooperative writer racing the final replace. Atomic replacement and
file flush cover tested process interruption, not a guarantee against power loss
or filesystem/hardware failure. Existing target corruption requires explicit
recovery, never automatic replacement with an empty bank. Test-only fault hooks
are omitted when compiled without `BANK_STORE_TEST`.

Example for an offline caller:

```lua
local Bank = dofile("tools/training_record_bank/core.lua")
local editor = assert(Bank.open(assert(Bank.empty(28))))
-- editor.add_slot(validCapturedSlot) -> stableId, added
-- editor.merge(otherEditor.snapshot()) -> sourceToDestinationIds
-- editor.edit(stableId, { name = "Anti-air", enabled = true, weight = 5 })
-- editor.delete(stableId)
-- editor.save(durableWriter) -- only on explicit user save
-- editor.discard()          -- cancel unsaved edits
```

## Not Implemented / Not Proven

### Offline Editing Session

`session.lua` connects the real Lua bank model to injected JSON and storage
adapters. `select(fighter)` performs one read and explicitly abandons the previous
unsaved editor, even when the new load fails; a failed switch cannot keep the old
character's bank editable under a new selection. Only a null/null storage read
means a new empty library. Malformed data, foreign characters and invalid version
tokens fail closed. Browsing snapshots has no filesystem work.

The codec adapter provides `encode(document)` and `decode(bytes)`. The storage
adapter provides `read(fighter) -> bytes, version` and
`replace(fighter, bytes, expectedVersion) -> writtenBytes, newVersion`, translating
`AtomicBankStore.Snapshot` at the future bridge boundary. Before any write the
session validates a serialization roundtrip through the real bank model and
compares every recording field with the original snapshot. Encoder mutation,
lossy serialization, oversized bytes and exceptions do not reach storage.

Save returns success only with an exact-byte receipt and a valid version token.
An exception or unconfirmed result after attempting publication leaves edits
dirty and requires explicit reload before another save. This covers the case
where the write committed but its response was lost, without blindly retrying
with an old version. Read/save operations lock selection and edits against
reentrant callbacks. Discard is not an acknowledgement of an ambiguous save.

The session fault tests use an opaque in-memory codec and storage fixture;
they prove workflow, not runtime integration. Separate real JSON tests now use
`json_codec.lua` with the pinned, unmodified MIT-licensed dkjson 2.8 under `vendor`.
The codec validates through `Bank.open`, explicitly distinguishes JSON arrays
from objects (including empty containers), sorts object keys for deterministic
bytes, rejects trailing data and returns detached model snapshots. It does not
replace REFramework's global `json` module or introduce a game dependency.

Non-integral native scalars use dkjson's documented `__tojson` extension with
17-digit roundtrip formatting, localized decimal separators converted to JSON's
dot, and explicit preservation of negative zero. Default Lua `tostring` precision
is insufficient for values such as `1.2000000476837158`; this is covered by a
regression and by the actual Lua/.NET/file roundtrip. The vendored source itself
is unchanged. Integer-valued SDK numbers retain canonical integer tokens.

The .NET storage suite launches the installed standalone Lua interpreter to
generate real JSON, writes it through `AtomicBankStore`, reopens the actual file
and passes it back to Lua for content/ID verification and further edits. Separate
tests persist all 200 records, verify Chinese names and uint32 inputs, and check
the vendor SHA-256. These establish offline Lua/JSON/filesystem interchange,
not in-game bridge calls. The test JSON exchange files live only in temporary
directories. There is still no installed .NET bridge binding or gameplay codec.

Strict disk parsing remains `AtomicBankStore`'s responsibility (including
duplicate properties, comments and depth). dkjson accepts some JSON extensions;
`json_codec.decode` is not a replacement for that gate on arbitrary external
files. Read bytes through the strict store first, then through the Lua model.
The offline API is synchronous: do not call it on every frame or directly from
the gameplay callback. A bounded deferred I/O integration is required first.

### Remaining Native Work

Native allocation/lifetime safety, native pagination, rename/delete controls,
automatic P2 library loading, runtime binding of the offline storage backend and
integration with saved training setups remain pending. Do not treat this module
as a playable expansion.
Complete reversal definitions are not supported by this draft: unknown fields
fail rather than being silently discarded. `record_refs` contains **only**
logical recording bindings `{group, slot, record_id}`, with down/guard/damage
groups and up to 200 one-based positions in each. It is not a replacement for
native Type, delay, level, count, enable flags or other reversal settings.

`set_reference(group, slot, recordId)` links an existing recording; passing nil
explicitly unlinks that one location. Delete refuses while any reference remains,
including references not currently enabled in a future UI. There is no cascade
delete or silent reassignment. Duplicate locations and dangling IDs cannot load;
integer-valued floats and integers identify the same location.

Merge remaps source record IDs through the recording dedup map. An occupied
reference location targeting a different recording rejects the whole merge,
including candidate recordings and next-ID changes. Reference ordering is
canonical down/guard/damage then position. `reference_plan(recordCapacity,
reversalCapacity)` produces detached zero-based record indices from current
record order, after checking the entire bank and reference spans. It neither
writes native `skill_index` nor verifies the capacities supplied by its caller.
For example, deleting an unrelated recording changes the projected index, not
the reference's stable ID. No unsupported rows are truncated.

Actual native capture/application remains absent. The current backend and WTT
overlay use Type=4 plus zero-based SkillIndex to find recording names, but that
observation is not an authority for blindly converting all reversal entries.
A future native adapter must verify the current type/index route, preserve all
other reversal data, validate capacities and refresh the entire reference plan
on the safe game thread before applying it. Never use stable IDs directly as
native indices. Changes to reversal-entry order require their own ownership
rules before exposing reversal deletion/reordering.

The ninth native recording was recorded and played during research, but does not
establish safety for 50/100/200 slots. The observed managed-wrapper finalizer crash
is unresolved. Native reversal execution still has a ten-entry traversal. Large
array construction alone does not prove executable reversal expansion.

## Tests

Run from repository root:

```powershell
lua tools/test_training_record_bank.lua
lua tools/test_training_record_bank_session.lua
lua tools/test_training_record_bank_json.lua
lua tools/test_training_record_bank_refs.lua
lua tools/test_training_record_bank_native_array.lua
lua tools/test_training_record_bank_native_mount.lua
lua tools/test_training_record_bank_native_save.lua
lua tools/test_training_record_bank_native_lifecycle.lua
lua tools/test_training_slot_layout.lua
lua tools/test_training_record_import.lua
lua tools/test_training_library.lua
```

Storage tests require a .NET 10 SDK and Lua 5.4 on PATH (or an explicit
`SF6CC_LUA` executable environment override). Put build output outside the repository:

```powershell
dotnet run --project tools/training_record_bank/storage-tests/StorageTests.csproj --configuration Release --artifacts-path "$env:TEMP/sf6cc-bank-store-build"
```

The storage tests use isolated temporary directories and include returned/thrown
failures before publication, actual child-process exit before replacement,
abandoned-temp recovery, stale writes, sharing errors, corruption, writer locking,
character isolation and envelope bounds. They do not load Steam, the game, the
.NET bridge or native save objects.

These tests are offline data and simulated-import evidence only. Existing native
probes stay disabled; nothing here is deployed automatically.
