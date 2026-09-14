-- Configuration edits share verified backup/restore around REFramework's non-atomic writer.
local M = {}
local MAX_BYTES = 16 * 1024 * 1024
local function equal(a, b, depth, scope)
    -- REFramework encodes {} as null and reads null as nil. Only a verified
    -- zero-frame recording buffer may use that equivalence, never other data.
    if scope == "empty_input" and type(a) == "table" and next(a) == nil and b == nil then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    if depth > 64 then return false end
    for k, v in pairs(a) do
        local child_scope
        if scope == "snapshot" and k == "slots" then child_scope = "slots"
        elseif scope == "slots" and type(k) == "number" then child_scope = "slot"
        elseif scope == "slot" and k == "input_buff" and a.frame == 0 and a.input_num == 0 then
            child_scope = "empty_input"
        end
        if not equal(v, b[k], depth + 1, child_scope) then return false end
    end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function valid_note(text)
    if type(text) ~= "string" or #text > 60 or text:find("[%c<>]") then return false end
    local ok, n = pcall(utf8.len, text)
    return ok and n ~= nil and n <= 15
end
M.valid_note = valid_note
function M.new(deps)
    local serial = 0
    local function read(path)
        local ok, raw = pcall(deps.read, path)
        if ok and type(raw) == "string" and #raw <= MAX_BYTES then return raw end
    end
    local function decode(raw)
        if not raw then return nil end
        local ok, data = pcall(deps.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    local function write_verified(path, raw)
        local ok, result = pcall(deps.write, path, raw)
        return ok and result ~= false and read(path) == raw
    end
    local function prepare(path, snapshot_update)
        if type(path) ~= "string" or #path > 512 or path:find("[%c\\:]")
            or not path:match("^SF6CC_TrainingConfigs/configs/[^/]+%.json$") then
            return nil, "仅支持当前木人库配置目录中的文件"
        end
        local raw = read(path)
        local data = decode(raw)
        if not data or data.schema ~= "sf6cc.training_setup.v2" or type(data.slots) ~= "table"
            or (data.description ~= nil and type(data.description) ~= "string") then
            return nil, "配置不可读或格式不支持，未修改文件"
        end
        local initial = data.title or ""
        if not snapshot_update and type(initial) ~= "string" then return nil, "配置名称格式无效，未修改文件" end
        local consumed = false
        -- The native editor replaces an overlength title; cancel never truncates the file.
        return { text = valid_note(initial) and initial or "", save = function(text)
            if consumed then return false, "配置编辑已结束" end
            consumed = true
            if snapshot_update then
                if type(text) ~= "table" or text.schema ~= data.schema or not data.fighter_id
                    or text.fighter_id ~= data.fighter_id or text.source_player ~= "P2"
                    or data.source_player ~= "P2" or type(text.slots) ~= "table"
                    or type(text.reversals) ~= "table" or type(text.settings) ~= "table"
                    or type(text.annotations) ~= "table" then
                    return false, "配置角色或快照格式不匹配，未覆盖文件"
                end
            else
                if not valid_note(text) then return false, "配置名称应为最多15个字符，且不能包含控制符或标记" end
                text = text:match("^%s*(.-)%s*$")
                if text == "" then return false, "配置名称不能为空，文件未修改" end
            end
            if read(path) ~= raw then return false, "配置已被外部修改或删除，请刷新后重试" end
            if snapshot_update then
                -- Keep the selected file's title, description and unknown metadata.
                for _, key in ipairs({ "created_at", "fighter_name", "slots", "reversals", "settings", "annotations" }) do
                    data[key] = text[key]
                end
            else
                if text == initial then return true, "配置名称未变化", path end
                data.title = text
            end
            local ok, encoded = pcall(deps.encode, data)
            if not ok or type(encoded) ~= "string" or encoded == "" then return false, "配置序列化失败，原文件未修改" end
            if #encoded > MAX_BYTES then return false, "配置超过16 MiB，原文件未修改" end
            if not equal(data, decode(encoded), 0, snapshot_update and "snapshot" or nil) then
                return false, "配置序列化往返校验失败，原文件未修改"
            end
            local backup
            for _ = 1, 100 do
                serial = serial + 1
                local candidate = "SF6CC_TrainingConfigs/backups/" .. (snapshot_update and "update_" or "name_")
                    .. deps.stamp() .. "_" .. serial .. ".json"
                if not deps.exists(candidate) then backup = candidate; break end
            end
            if not backup or not write_verified(backup, raw) then
                return false, "原文件备份失败，未保存配置"
            end
            -- Recheck after backup/serialization so a concurrent edit is not silently lost.
            if read(path) ~= raw then return false, "备份期间配置发生变化，未覆盖原文件" end
            if not write_verified(path, encoded) then
                local restored = write_verified(path, raw)
                return false, restored and "配置保存失败，原文件已恢复"
                    or ("配置保存失败，请从备份恢复：" .. backup)
            end
            return true, snapshot_update and "配置已保存" or "配置名称已保存", path
        end }
    end
    return { prepare = function(path) return prepare(path, false) end,
        prepare_update = function(path) return prepare(path, true) end }
end
return M
