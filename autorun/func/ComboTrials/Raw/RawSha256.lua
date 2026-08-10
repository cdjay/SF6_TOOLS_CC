-- RawSha256.lua
-- Allocation-bounded SHA-256 for megabyte-scale Raw artifacts. string.unpack
-- avoids the per-byte callback overhead of the telemetry-oriented hasher.

local RawSha256 = { name = "ComboTrials.Raw.RawSha256" }

local MASK = 0xffffffff
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function rotate_right(value, bits)
    return ((value >> bits) | (value << (32 - bits))) & MASK
end

function RawSha256.digest(message)
    message = tostring(message or "")
    local length = #message
    local zero_padding = (56 - ((length + 1) % 64)) % 64
    local padded = message .. string.char(0x80)
        .. string.rep("\0", zero_padding) .. string.pack(">I8", length * 8)
    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local words = {}

    for chunk = 1, #padded, 64 do
        for index = 0, 15 do
            words[index] = string.unpack(">I4", padded, chunk + index * 4)
        end
        for index = 16, 63 do
            local x, y = words[index - 15], words[index - 2]
            local s0 = rotate_right(x, 7) ~ rotate_right(x, 18) ~ (x >> 3)
            local s1 = rotate_right(y, 17) ~ rotate_right(y, 19) ~ (y >> 10)
            words[index] = (words[index - 16] + s0 + words[index - 7] + s1) & MASK
        end

        local a, b, c, d = h0, h1, h2, h3
        local e, f, g, h = h4, h5, h6, h7
        for index = 0, 63 do
            local sum1 = rotate_right(e, 6) ~ rotate_right(e, 11) ~ rotate_right(e, 25)
            local choice = (e & f) ~ ((~e) & g)
            local temp1 = (h + sum1 + choice + K[index + 1] + words[index]) & MASK
            local sum0 = rotate_right(a, 2) ~ rotate_right(a, 13) ~ rotate_right(a, 22)
            local majority = (a & b) ~ (a & c) ~ (b & c)
            local temp2 = (sum0 + majority) & MASK
            h, g, f, e, d, c, b, a = g, f, e, (d + temp1) & MASK,
                c, b, a, (temp1 + temp2) & MASK
        end

        h0, h1, h2, h3 = (h0 + a) & MASK, (h1 + b) & MASK,
            (h2 + c) & MASK, (h3 + d) & MASK
        h4, h5, h6, h7 = (h4 + e) & MASK, (h5 + f) & MASK,
            (h6 + g) & MASK, (h7 + h) & MASK
    end

    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x",
        h0, h1, h2, h3, h4, h5, h6, h7)
end

return RawSha256
