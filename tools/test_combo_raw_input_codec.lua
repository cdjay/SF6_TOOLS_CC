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

for mask = 0, 0xFFFF do
    for _, facing_right in ipairs({ true, false }) do
        local relative_mask = codec.native_to_relative(mask, facing_right)
        local restored_mask = codec.relative_to_native(relative_mask, facing_right)
        assert(restored_mask == mask,
            string.format("facing roundtrip changed mask 0x%04X", mask))
        assert((relative_mask & ~0x0C) == (mask & ~0x0C),
            string.format("facing conversion changed non-horizontal bits in 0x%04X", mask))
    end
end

local function capture_and_play(native_masks, capture_facings, playback_facings)
    local relative_masks = {}
    local played_masks = {}
    for index, mask in ipairs(native_masks) do
        relative_masks[index] = codec.native_to_relative(
            mask,
            capture_facings[index]
        )
        played_masks[index] = codec.relative_to_native(
            relative_masks[index],
            playback_facings[index]
        )
    end
    return relative_masks, played_masks
end

local schedule_facings = { true, true, false, false, true }
local semantic_forward_native = { 0x04, 0x04, 0x08, 0x08, 0x04 }
local semantic_forward_relative, semantic_forward_played = capture_and_play(
    semantic_forward_native,
    schedule_facings,
    schedule_facings
)
assert(table.concat(semantic_forward_relative, ",") == "4,4,4,4,4",
    "held semantic forward must remain stable across side switches")
assert(table.concat(semantic_forward_played, ",") == "4,4,8,8,4",
    "held semantic forward must reproduce the physical switch-frame inputs")

local physical_right_native = { 0x04, 0x04, 0x04, 0x04, 0x04 }
local physical_right_relative, physical_right_played = capture_and_play(
    physical_right_native,
    schedule_facings,
    schedule_facings
)
assert(table.concat(physical_right_relative, ",") == "4,4,8,8,4",
    "held physical right must change semantic direction after crossing")
assert(table.concat(physical_right_played, ",") == "4,4,4,4,4",
    "held physical right must roundtrip without inventing a release")

local switch_boundaries = {
    { name = "press", native = { 0, 0, 0x08 | 0x10, 0x08 | 0x10 } },
    { name = "release", native = { 0x04 | 0x10, 0x04 | 0x10, 0, 0 } },
    { name = "neutral", native = { 0x04 | 0x10, 0, 0, 0x08 | 0x10 } },
    { name = "multi-button", native = { 0x04 | 0x30, 0x04 | 0x30, 0x08 | 0x30, 0x08 | 0x30 } },
}
local boundary_facings = { true, true, false, false }
for _, case in ipairs(switch_boundaries) do
    local _, played = capture_and_play(
        case.native,
        boundary_facings,
        boundary_facings
    )
    assert(table.concat(played, ",") == table.concat(case.native, ","),
        case.name .. " on a switch frame must roundtrip exactly")
end

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

local lowercase_timeline_step = codec.parse_timeline_line("1f : 6+lp")
assert(lowercase_timeline_step
        and lowercase_timeline_step.frames == 1
        and lowercase_timeline_step.mask == (0x04 | 0x10),
    "timeline playback must preserve lowercase named buttons")
assert(codec.parse_timeline_line("0f : 4") == nil,
    "zero-duration timeline rows must not enter playback")
assert(codec.parse_timeline_line("1f : 6+MYSTERY") == nil,
    "unknown timeline tokens must not degrade to partial input")
assert(codec.has_usable_timeline({ "1f : 6+lp" }) == true
        and codec.has_usable_timeline({ "0f : 4" }) == false
        and codec.has_usable_timeline({ "1f : 6+MYSTERY" }) == false,
    "timeline usability must share the playback parser contract")
local lowercase_timeline = codec.build_timeline_steps({
    "1f : 6+lp",
    "2f : 5",
})
assert(lowercase_timeline
        and #lowercase_timeline == 2
        and lowercase_timeline[1].mask == (0x04 | 0x10),
    "timeline playback must build every row through the strict parser")
assert(codec.build_timeline_steps({
    "1f : 6+LP",
    "1f : 6+MYSTERY",
    "1f : 5",
}) == nil,
    "one unknown row must reject playback instead of shortening the stream")

local description = codec.describe_relative_stream()
assert(description.field == "relative_raw_inputs"
    and description.encoding == "facing_relative_v1",
    "portable stream metadata must be stable")

print("combo raw input codec tests passed")
