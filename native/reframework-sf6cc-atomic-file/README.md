# reframework-sf6cc-atomic-file

This narrowly scoped REFramework plugin provides the native operations
needed by the SF6CC cumulative combo telemetry producer:

```lua
sf6cc_atomic_file.write(relative_path, complete_bytes)
sf6cc_atomic_file.probe(relative_path)
sf6cc_atomic_file.random_epoch()
sf6cc_atomic_file.random_id()
```

`write` accepts only the tracked producer's checkpoint, durable-state,
bounded pending-journal, and combo-feedback outbox paths under
`reframework/data/SF6_TrainingRemoteControl_data`. The feedback path is:

```text
ComboFeedback/feedback-outbox-v1.json
```

It creates a unique same-directory temporary file, writes all bytes, flushes
and closes the handle, then publishes with `MoveFileExW` using
`MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH`. A failed write or replace
deletes only the temporary file and leaves the prior destination untouched.

`probe` accepts those same fixed paths and returns `exists` or `missing`.
Only Win32 `ERROR_FILE_NOT_FOUND` and `ERROR_PATH_NOT_FOUND` are classified as
missing. ACL, sharing, I/O, or other attribute failures return an error so the
Lua producer fails closed without generating a replacement epoch.

`random_epoch` returns 16 bytes from Windows `BCryptGenRandom` encoded as 32
lowercase hexadecimal characters. It is called only when no checkpoint and no
durable producer state exist. `random_id` uses the same cryptographic generator
for independent feedback item IDs without assigning epoch semantics.

Build with the same pinned REFramework source and x64 Visual Studio toolchain
documented by `native/reframework-imgui-texture`.
