-- Facing-portable raw-input helpers.
--
-- Legacy `raw_inputs` are native/screen-relative masks and must remain
-- byte-for-byte compatible with WTT. `relative_raw_inputs` use the same
-- uint16 masks, except horizontal direction bits are stored relative to the
-- actor's current facing and are converted back at playback time.

local RawInputCodec = {
    name = "ComboTrials.RawInputCodec",
    RELATIVE_FIELD = "relative_raw_inputs",
    RELATIVE_ENCODING = "facing_relative_v1",
}

local HORIZONTAL_MASK = 0x0C
local PHYSICAL_RIGHT = 0x04
local PHYSICAL_LEFT = 0x08
local TIMELINE_DIRECTION_MASKS = {
    ["7"] = 0x09,
    ["8"] = 0x01,
    ["9"] = 0x05,
    ["4"] = 0x08,
    ["5"] = 0x00,
    ["6"] = 0x04,
    ["1"] = 0x0A,
    ["2"] = 0x02,
    ["3"] = 0x06,
}
local TIMELINE_BUTTON_MASKS = {
    LP = 0x10,
    MP = 0x20,
    HP = 0x40,
    LK = 0x80,
    MK = 0x100,
    HK = 0x200,
}
local stream_cache = setmetatable({}, { __mode = "k" })

function RawInputCodec.normalize_mask(value)
    value = tonumber(value)
    if value == nil then return nil end
    return math.floor(value) & 0xFFFF
end

function RawInputCodec.normalize_stream(values)
    if type(values) ~= "table" or #values == 0 then return nil end
    local normalized = {}
    for index = 1, #values do
        local mask = RawInputCodec.normalize_mask(values[index])
        if mask == nil then return nil end
        normalized[index] = mask
    end
    return normalized
end

function RawInputCodec.swap_horizontal(mask)
    mask = RawInputCodec.normalize_mask(mask)
    if mask == nil then return nil end
    local has_right = (mask & PHYSICAL_RIGHT) ~= 0
    local has_left = (mask & PHYSICAL_LEFT) ~= 0
    mask = mask & ~HORIZONTAL_MASK
    if has_right then mask = mask | PHYSICAL_LEFT end
    if has_left then mask = mask | PHYSICAL_RIGHT end
    return mask
end

-- Native and facing-relative masks differ only while the actor faces left.
-- The transform is its own inverse, so recording and playback intentionally
-- share the same operation.
function RawInputCodec.native_to_relative(mask, facing_right)
    if facing_right == false then
        return RawInputCodec.swap_horizontal(mask)
    end
    return RawInputCodec.normalize_mask(mask)
end

function RawInputCodec.relative_to_native(mask, facing_right)
    if facing_right == false then
        return RawInputCodec.swap_horizontal(mask)
    end
    return RawInputCodec.normalize_mask(mask)
end

function RawInputCodec.select_stream(first_step)
    if type(first_step) ~= "table" then return nil, nil end
    local cached = stream_cache[first_step]
    if cached then
        if cached.stream == false then return nil, nil end
        return cached.stream, cached.source
    end

    local relative = RawInputCodec.normalize_stream(
        first_step[RawInputCodec.RELATIVE_FIELD]
    )
    if relative then
        stream_cache[first_step] = {
            stream = relative,
            source = RawInputCodec.RELATIVE_FIELD,
        }
        return relative, RawInputCodec.RELATIVE_FIELD
    end

    local native = RawInputCodec.normalize_stream(first_step.raw_inputs)
    if native then
        stream_cache[first_step] = {
            stream = native,
            source = "raw_inputs",
        }
        return native, "raw_inputs"
    end
    stream_cache[first_step] = { stream = false, source = false }
    return nil, nil
end

function RawInputCodec.invalidate_stream_cache(first_step)
    if type(first_step) == "table" then stream_cache[first_step] = nil end
end

function RawInputCodec.has_valid_stream(first_step)
    local stream = RawInputCodec.select_stream(first_step)
    return stream ~= nil
end

function RawInputCodec.parse_timeline_line(line)
    if type(line) ~= "string" then return nil end
    local frames_str, rest = line:match("^(%d+)f%s*:%s*(.-)%s*$")
    local frames = tonumber(frames_str)
    if frames == nil or frames <= 0 or rest == ""
        or rest:match("^%s*%+") or rest:match("%+%s*$")
        or rest:match("%+%s*%+") then
        return nil
    end

    local tokens = {}
    for part in rest:gmatch("[^+]+") do
        tokens[#tokens + 1] = tostring(
            part:match("^%s*(.-)%s*$") or ""
        ):upper()
    end
    local mask = TIMELINE_DIRECTION_MASKS[tokens[1]]
    if mask == nil then return nil end
    for index = 2, #tokens do
        local button_mask = TIMELINE_BUTTON_MASKS[tokens[index]]
        if button_mask == nil then return nil end
        mask = mask | button_mask
    end
    return { frames = frames, mask = mask }
end

function RawInputCodec.build_timeline_steps(timeline)
    if type(timeline) ~= "table" or #timeline == 0 then return nil end
    local steps = {}
    for index = 1, #timeline do
        local step = RawInputCodec.parse_timeline_line(timeline[index])
        if step == nil then return nil end
        steps[index] = step
    end
    return steps
end

function RawInputCodec.has_usable_timeline(timeline)
    return RawInputCodec.build_timeline_steps(timeline) ~= nil
end

function RawInputCodec.select_transcription_stream(first_step, runtime_audit)
    if type(first_step) ~= "table" then return nil, nil, false end
    local selected, source = RawInputCodec.select_stream(first_step)
    local has_timeline = RawInputCodec.has_usable_timeline(
        first_step.timeline
    )

    if source == RawInputCodec.RELATIVE_FIELD then
        return selected, source, has_timeline
    end
    -- Conversion rebuilds a legacy native stream from timeline. Runtime audit
    -- instead tests the stream that an installed file actually selects.
    if runtime_audit ~= true and has_timeline then
        return nil, "timeline", true
    end
    if source == "raw_inputs" then return selected, source, has_timeline end
    if has_timeline then return nil, "timeline", true end
    return nil, nil, false
end

function RawInputCodec.describe_relative_stream()
    return {
        field = RawInputCodec.RELATIVE_FIELD,
        encoding = RawInputCodec.RELATIVE_ENCODING,
    }
end

return RawInputCodec
