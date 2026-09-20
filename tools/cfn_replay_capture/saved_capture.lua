-- Read-only saved evidence. Never starts capture, changes playback or writes files.
local M = {}
local function size(t, limit)
    if type(t) ~= "table" then return nil end
    local n = #t
    if n > limit then return nil end
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > n then return nil end
        count = count + 1
    end
    return count == n and n or nil
end
local function header(c, schema)
    return c.schema == schema.version and c.state == "stopped" and type(c.stop_reason) == "string"
        and size(c.columns, #schema.columns) == #schema.columns
        and size(c.samples, 120000) ~= nil and #c.samples > 0 and c.sample_count == #c.samples
end
local function valid_row(row, schema)
    if size(row, #schema.columns) ~= #schema.columns then return false end
    for _, v in ipairs(row) do
        if v ~= false and (type(v) ~= "number" or v ~= v or math.abs(v) > 9007199254740991) then return false end
    end
    for _, name in ipairs({"round", "battle_round", "replay_frame", "stage_frame", "thread_id", "render_tick"}) do
        local n = row[schema.index[name]]
        if type(n) ~= "number" or n < 0 or n % 1 ~= 0 then return false end
    end
    return true
end
function M.new(deps, schema, replay_id)
    assert(type(replay_id) == "string" and replay_id ~= "")
    local loader = {index=1, files={}}
    local ok, paths = pcall(deps.fs.glob, [[cfn-capture-.*\.json]])
    if not ok or type(paths) ~= "table" then loader.error="saved_read_failed"; return loader end
    local seen = {}
    for _, path in ipairs(paths) do
        local name = type(path) == "string" and path:match("[^/\\]+$")
        local date, time, suffix, file_replay
        if name then
            file_replay,date,time,suffix=name:match("^cfn%-capture%-([A-Za-z0-9_]+)%-(%d%d%d%d%d%d%d%d)%-(%d%d%d%d%d%d)(.-)%.json$")
            if not file_replay then date,time,suffix=name:match("^cfn%-capture%-(%d%d%d%d%d%d%d%d)%-(%d%d%d%d%d%d)(.-)%.json$") end
        end
        local serial = suffix == "" and 0 or suffix and tonumber(suffix:match("^%-(%d+)$"))
        if date and serial and not seen[name] and (not file_replay or file_replay==replay_id) then
            loader.files[#loader.files+1] = {name=name, stamp=date..time, serial=serial}; seen[name]=true
        end
    end
    table.sort(loader.files, function(a,b) return a.stamp > b.stamp or a.stamp == b.stamp and
        (a.serial > b.serial or a.serial==b.serial and a.name>b.name) end)
    function loader:step()
        if self.error or self.capture then return true end
        if self.pending then
            for _=1,256 do
                local row = self.pending.samples[self.cursor]
                if not row then self.capture=self.pending; self.pending=nil; return true end
                if not valid_row(row, schema) then self.pending=nil; self.error="saved_invalid"; return true end
                self.cursor=self.cursor+1
            end
            return false
        end
        local entry=self.files[self.index]
        if not entry then self.error=self.read_failed and "saved_read_failed" or "saved_missing"; return true end
        self.index=self.index+1
        local loaded, c=pcall(deps.json.load_file, entry.name)
        if not loaded or type(c) ~= "table" then self.read_failed=true; return false end
        if type(c.metadata) ~= "table" or c.metadata.replay_id ~= replay_id then return false end
        if not header(c,schema) then self.error="saved_invalid"; return true end
        for i,name in ipairs(schema.columns) do if c.columns[i] ~= name then self.error="saved_invalid"; return true end end
        self.pending,self.path,self.cursor=c,entry.name,1
        return false
    end
    return loader
end
return M
