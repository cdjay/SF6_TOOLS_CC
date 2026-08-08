local MAIN_PATH = arg[1] or "autorun/TrainingComboTrials_v1.0.lua"
local LUA_LOCAL_LIMIT = 200
local TARGET = 130
local WARNING_THRESHOLD = 150
local CURRENT_CEILING = 165
local REPORT_ONLY = arg[2] == "--report-only"

local function read_all(path)
    if path == "-" then return assert(io.read("*a")) end
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    file:close()
    return value
end

local function long_bracket_open(source, index)
    if source:sub(index, index) ~= "[" then return nil end
    local cursor = index + 1
    while source:sub(cursor, cursor) == "=" do cursor = cursor + 1 end
    if source:sub(cursor, cursor) ~= "[" then return nil end
    return cursor - index - 1, cursor - index + 1
end

local function strip_strings_and_comments(source)
    local out = {}
    local index = 1
    local state = "code"
    local quote = nil
    local long_equals = nil

    while index <= #source do
        local char = source:sub(index, index)
        if char == "\n" then
            out[#out + 1] = "\n"
            if state == "line_comment" then state = "code" end
            index = index + 1
        elseif state == "code" then
            if source:sub(index, index + 1) == "--" then
                local equals, length = long_bracket_open(source, index + 2)
                if equals ~= nil then
                    state = "long_comment"
                    long_equals = equals
                    out[#out + 1] = string.rep(" ", length + 2)
                    index = index + length + 2
                else
                    state = "line_comment"
                    out[#out + 1] = "  "
                    index = index + 2
                end
            elseif char == "\"" or char == "'" then
                state = "short_string"
                quote = char
                out[#out + 1] = " "
                index = index + 1
            else
                local equals, length = long_bracket_open(source, index)
                if equals ~= nil then
                    state = "long_string"
                    long_equals = equals
                    out[#out + 1] = string.rep(" ", length)
                    index = index + length
                else
                    out[#out + 1] = char
                    index = index + 1
                end
            end
        elseif state == "short_string" then
            if char == "\\" then
                out[#out + 1] = "  "
                index = index + 2
            else
                out[#out + 1] = " "
                if char == quote then state = "code" end
                index = index + 1
            end
        elseif state == "long_string" or state == "long_comment" then
            local closer = "]" .. string.rep("=", long_equals) .. "]"
            if source:sub(index, index + #closer - 1) == closer then
                out[#out + 1] = string.rep(" ", #closer)
                index = index + #closer
                state = "code"
            else
                out[#out + 1] = " "
                index = index + 1
            end
        else
            out[#out + 1] = " "
            index = index + 1
        end
    end

    assert(state == "code" or state == "line_comment",
        "unterminated string or long comment while counting main locals")
    return table.concat(out)
end

local function tokenize(source)
    local tokens = {}
    local index = 1
    while index <= #source do
        local char = source:sub(index, index)
        if char:match("[%a_]") then
            local finish = index + 1
            while source:sub(finish, finish):match("[%w_]") do finish = finish + 1 end
            tokens[#tokens + 1] = source:sub(index, finish - 1)
            index = finish
        elseif char:match("%s") then
            index = index + 1
        else
            tokens[#tokens + 1] = char
            index = index + 1
        end
    end
    return tokens
end

local keywords = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
    ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
    ["until"] = true, ["while"] = true,
}

local function is_identifier(token)
    return token ~= nil and token:match("^[%a_][%w_]*$") ~= nil
        and not keywords[token]
end

local function count_top_level_locals(source)
    local tokens = tokenize(strip_strings_and_comments(source))
    local depth = 0
    local total = 0
    local local_functions = 0
    local plain_locals = 0
    local index = 1

    while index <= #tokens do
        local token = tokens[index]
        if token == "local" and tokens[index + 1] == "function" then
            assert(is_identifier(tokens[index + 2]), "local function name is missing")
            if depth == 0 then
                total = total + 1
                local_functions = local_functions + 1
            end
            depth = depth + 1
            index = index + 3
        elseif token == "local" then
            local cursor = index + 1
            while is_identifier(tokens[cursor]) do
                if depth == 0 then
                    total = total + 1
                    plain_locals = plain_locals + 1
                end
                if tokens[cursor + 1] ~= "," then break end
                cursor = cursor + 2
            end
            index = cursor
        elseif token == "function" or token == "if"
            or token == "do" or token == "repeat" then
            depth = depth + 1
            index = index + 1
        elseif token == "end" or token == "until" then
            depth = depth - 1
            assert(depth >= 0, "unbalanced Lua block while counting main locals")
            index = index + 1
        else
            index = index + 1
        end
    end

    assert(depth == 0, "unclosed Lua block while counting main locals")
    return total, local_functions, plain_locals
end

local total, local_functions, plain_locals =
    count_top_level_locals(read_all(MAIN_PATH))
local remaining = LUA_LOCAL_LIMIT - total
local status = total <= TARGET and "target"
    or total > WARNING_THRESHOLD and "warning"
    or "acceptable"

print(string.format(
    "combo main local limit: total=%d local_functions=%d plain_locals=%d remaining=%d limit=%d target=%d status=%s",
    total,
    local_functions,
    plain_locals,
    remaining,
    LUA_LOCAL_LIMIT,
    TARGET,
    status
))

if not REPORT_ONLY then
    assert(total <= CURRENT_CEILING, string.format(
        "main chunk top-level locals regressed: %d > governance ceiling %d",
        total,
        CURRENT_CEILING
    ))
    assert(total <= LUA_LOCAL_LIMIT,
        "main chunk exceeds Lua's 200-local compile limit")
end

print("combo main local limit test passed")
