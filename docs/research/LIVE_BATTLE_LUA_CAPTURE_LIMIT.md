# SF6 online battle Lua capture limit

Status: verified for the installed REFramework build; no online capture is claimed.

The game log for the October 9 process reports REFramework commit
`0a07faae46a6fc1c51cd1699a0cf99a3f9c2679f`. In that build's
`src/mods/ScriptRunner.cpp`, `on_frame()` sets `m_last_online_match_state`
from `sdk::sf6::is_online_match()` and skips every Lua state's `on_frame()`
while it is true (lines 1049, 1070-1079). `on_draw_ui()` also omits
`Script Generated UI` (lines 1193-1207); native Lua method hooks and
application-entry callbacks have the same online gate.

Source: https://github.com/praydog/REFramework/blob/0a07faae46a6fc1c51cd1699a0cf99a3f9c2679f/src/mods/ScriptRunner.cpp

The October 9 live report that the script menu disappears on matching is
consistent with this gate. The earlier standalone `re.on_frame` probe cannot
record a real online match, even when armed before matchmaking. During the
search, the game can briefly expose online GameMode 14 while FlowMap remains
3 (training); any samples from that interval are not match evidence. The
probe and its instructions were removed before treating results as valid.

Do not bypass REFramework's online safeguard for this project. For post-match
analysis, capture the CFN replay through the existing offline replay path.
