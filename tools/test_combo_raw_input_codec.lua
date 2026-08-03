package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local codec = require("func/ComboTrials/RawInputCodec")

assert(codec.swap_horizontal(0x04) == 0x08
    and codec.swap_horizontal(0x08) == 0x04,
    "horizontal direction bits must swap")
assert(codec.swap_horizontal(0x06) == 0x0A
    and codec.swap_horizontal(0x0A) == 0x06,
    "diagonals must preserve vertical direction while swapping horizontal")
assert(codec.swap_horizontal(0x0C | 0x30) == (0x0C | 0x30),
    "opposite horizontal bits and buttons must remain intact")
assert(codec.native_to_relative(0x04 | 0x40, true) == (0x04 | 0x40)
    and codec.native_to_relative(0x04 | 0x40, false) == (0x08 | 0x40),
    "recording must normalize native input against the live facing")
assert(codec.relative_to_native(0x04 | 0x40, false) == (0x08 | 0x40)
    and codec.relative_to_native(0x04 | 0x40, true) == (0x04 | 0x40),
    "playback must project relative input through the live facing")
local crossing_route = { 0x04, 0x04, 0x08 }
local crossing_facings = { true, false, false }
local projected = {}
for index, mask in ipairs(crossing_route) do
    projected[index] = codec.relative_to_native(
        mask,
        crossing_facings[index]
    )
end
assert(projected[1] == 0x04
    and projected[2] == 0x08
    and projected[3] == 0x04,
    "a side-switching route must preserve forward/back intent frame by frame")

local relative, source = codec.select_stream({
    relative_raw_inputs = { 4, 20, 0 },
    raw_inputs = { 8, 24, 0 },
})
assert(source == "relative_raw_inputs"
    and relative[1] == 4
    and relative[2] == 20,
    "portable relative input must take precedence over legacy native raw")

local native, native_source = codec.select_stream({
    relative_raw_inputs = { "invalid" },
    raw_inputs = { 8, 24, 0 },
})
assert(native_source == "raw_inputs" and native[1] == 8,
    "malformed extensions must not break a valid legacy raw stream")
local mutable = { raw_inputs = { 8, 0 } }
local mutable_stream, mutable_source = codec.select_stream(mutable)
assert(mutable_source == "raw_inputs" and mutable_stream[1] == 8,
    "legacy stream selection must be cacheable")
mutable.relative_raw_inputs = { 4, 0 }
codec.invalidate_stream_cache(mutable)
local refreshed_stream, refreshed_source = codec.select_stream(mutable)
assert(refreshed_source == "relative_raw_inputs" and refreshed_stream[1] == 4,
    "explicit invalidation must expose a newly attached portable stream")
do
    local long_stream = {}
    for index = 1, 10000 do long_stream[index] = index & 0xFFFF end
    local holder = { relative_raw_inputs = long_stream }
    local first_selection = codec.select_stream(holder)
    local second_selection = codec.select_stream(holder)
    assert(first_selection == second_selection,
        "long input streams must be normalized once and reused from cache")
end

local conversion_stream, conversion_source, conversion_has_timeline =
    codec.select_transcription_stream({
        raw_inputs = { 8, 24, 0 },
        timeline = { "1f : 4", "1f : 4+LP" },
    }, false)
assert(conversion_stream == nil
    and conversion_source == "timeline"
    and conversion_has_timeline == true,
    "conversion must rebuild legacy native raw from a retained timeline")
local audit_stream, audit_source = codec.select_transcription_stream({
    raw_inputs = { 8, 24, 0 },
    timeline = { "1f : 4", "1f : 4+LP" },
}, true)
assert(audit_source == "raw_inputs" and audit_stream[1] == 8,
    "runtime audit must test the installed legacy stream")
local timeline_audit_stream, timeline_audit_source, timeline_audit_available =
    codec.select_transcription_stream({
        timeline = { "1f : 4", "1f : 4+LP" },
    }, true)
assert(timeline_audit_stream == nil
    and timeline_audit_source == "timeline"
    and timeline_audit_available == true,
    "runtime audit must accept a usable timeline when no raw stream exists")
local damaged_timeline_stream, damaged_timeline_source =
    codec.select_transcription_stream({
        raw_inputs = { 8, 24, 0 },
        timeline = { "", false, "not a timeline row" },
    }, false)
assert(damaged_timeline_source == "raw_inputs"
    and damaged_timeline_stream[1] == 8,
    "an unusable timeline must not displace valid legacy raw input")
local mixed_timeline_stream, mixed_timeline_source =
    codec.select_transcription_stream({
        raw_inputs = { 8, 24, 0 },
        timeline = { "1f : 4", false },
    }, false)
assert(mixed_timeline_source == "raw_inputs"
    and mixed_timeline_stream[1] == 8,
    "a partially malformed timeline must not displace valid legacy raw input")
local portable_stream, portable_source = codec.select_transcription_stream({
    relative_raw_inputs = { 4, 20, 0 },
    raw_inputs = { 8, 24, 0 },
    timeline = { "1f : 6", "1f : 6+LP" },
}, false)
assert(portable_source == "relative_raw_inputs" and portable_stream[1] == 4,
    "an existing portable stream must not be needlessly rebuilt")
assert(codec.normalize_stream({}) == nil
    and codec.normalize_stream({ 0, false }) == nil,
    "empty or malformed streams must be rejected")

local description = codec.describe_relative_stream()
assert(description.field == "relative_raw_inputs"
    and description.encoding == "facing_relative_v1",
    "portable stream metadata must be stable")

print("combo raw input codec tests passed")
