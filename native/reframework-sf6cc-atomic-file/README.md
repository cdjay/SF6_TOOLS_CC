# reframework-sf6cc-atomic-file

This narrowly scoped REFramework plugin provides the two native operations
needed by the SF6CC cumulative combo telemetry producer:

```lua
sf6cc_atomic_file.write(relative_path, complete_bytes)
sf6cc_atomic_file.random_epoch()
```

`write` accepts only the tracked producer's checkpoint and durable-state paths
under `reframework/data/SF6_TrainingRemoteControl_data/ComboTrialTelemetry`.
It creates a unique same-directory temporary file, writes all bytes, flushes
and closes the handle, then publishes with `MoveFileExW` using
`MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH`. A failed write or replace
deletes only the temporary file and leaves the prior destination untouched.

`random_epoch` returns 16 bytes from Windows `BCryptGenRandom` encoded as 32
lowercase hexadecimal characters. It is called only when no checkpoint and no
durable producer state exist.

Build with the same pinned REFramework source and x64 Visual Studio toolchain
documented by `native/reframework-imgui-texture`.
