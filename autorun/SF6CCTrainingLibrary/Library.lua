-- Shared library selection and deferred operations for native and ImGui menus.
local Compatibility = require("SF6CCTrainingLibrary/TrainingConfigCompatibility")
local character_name = require("SF6CCTrainingLibrary/CharacterNames")
-- Autorun search paths are unavailable on first use from a deferred callback.
local Safety = require("SF6CCTrainingLibrary/Context")
local Records = require("SF6CCTrainingLibrary/Records")
local M = {}

function M.new(records, context, choices)
    local self = { entries = {}, labels = {}, selected = 1, loaded = false,
        revision = 0, result_revision = 0, status = "就绪", status_ok = true,
        options = { only_import_valid = false, clear_empty_slots = true,
            reject_fighter_mismatch = true, force_apply_after_import = true } }
    local pending, note_edit, cancel_requested
    local remembered = choices and choices.load() or {}
    if type(remembered) ~= "table" then remembered = {} end
    local function remember(fighter, path)
        if not choices or type(path) ~= "string" then return end
        remembered[tostring(fighter)] = path
        local ok, result = pcall(choices.save, remembered)
        if not ok or result == false then
            if log and log.warn then log.warn("[TrainingLibrary] Could not remember selected configuration") end
        end
    end
    local function status(ok, text)
        self.status_ok, self.status = ok == true, tostring(text or "")
    end
    local function diagnostic(message)
        if log and log.warn then pcall(log.warn, "[TrainingLibrary] " .. tostring(message or "")) end
    end
    -- Only the explicit restore operation may run on a legacy (>8) recording bank.
    local function safe_context(allow_legacy)
        local ok, ctx = pcall(context)
        if not ok or type(ctx) ~= "table" or not ctx.allowed
            or (ctx.error and not (allow_legacy and ctx.bank_unsupported == true))
            or ctx.fighter_id == nil or not ctx.session or not ctx.data then
            return nil, "仅可在离线训练场、角色数据就绪后操作"
        end
        return ctx
    end
    local legacy_cache
    function self.legacy_summary()
        local ctx = safe_context(true)
        if not ctx or ctx.bank_unsupported ~= true or not records.legacy_bank_summary then
            legacy_cache = nil
            return nil
        end
        local c = legacy_cache
        if c and c.session == ctx.session and c.data == ctx.data and c.fighter_id == ctx.fighter_id
            and c.slot_count == ctx.slot_count and c.revision == self.result_revision then
            return c.summary
        end
        local ok, summary = pcall(records.legacy_bank_summary)
        summary = ok and type(summary) == "table" and summary or nil
        legacy_cache = { session = ctx.session, data = ctx.data, fighter_id = ctx.fighter_id,
            slot_count = ctx.slot_count, revision = self.result_revision, summary = summary }
        return summary
    end
    function self.selection() return self.entries[self.selected] end
    function self.selection_compatibility(ctx)
        local entry = self.selection()
        if not entry then return false, "请先选择配置", "no_selection" end
        if not ctx then
            local ok, value = pcall(context)
            ctx = ok and type(value) == "table" and value or { error = true }
            if not ctx.allowed then ctx = { error = true } end
        end
        return Compatibility.check(entry.metadata, ctx, self.options)
    end
    function self.selection_details()
        local entry = self.selection()
        if not entry then return { file = "（暂无配置）", character = "-", saved = "-", slots = "-", notes = "-" } end
        local meta = entry.metadata or {}
        local function text(value, fallback)
            if type(value) ~= "string" or value:match("^%s*$") then return fallback end
            return value:gsub("[%c<>]", " ")
        end
        local function number(value) return type(value) == "number" and tostring(value) or "?" end
        return {
            file = entry.filename or entry.path:match("([^/\\]+)$") or entry.path,
            character = character_name(meta.fighter_name) .. " / ID " .. number(meta.fighter_id)
                .. " / " .. text(meta.source_player, "未知方位"),
            saved = text(meta.created_at, "未记录保存时间"),
            slots = "有效录像 " .. number(meta.valid_slots) .. "/" .. number(meta.record_slots or 8)
                .. "，启用 " .. number(meta.active_slots)
                .. "；启用反击 " .. number(meta.active_reversals) .. "/" .. number(meta.reversal_slots or 30),
            notes = text(meta.description, "无备注"),
        }
    end
    function self.selection_label(index)
        local entry = self.entries[index or self.selected]
        if not entry then return "（暂无配置）" end
        return character_name((entry.metadata or {}).fighter_name) .. "【"
            .. (self.labels[index or self.selected] or "未命名配置") .. "】"
    end
    function self.select(index)
        if pending or note_edit or type(index) ~= "number" or index % 1 ~= 0 or not self.entries[index] then return false end
        self.selected = index
        return true
    end
    function self.refresh(select_path)
        if pending or note_edit then return false end
        -- A failed automatic load must not retry disk IO on every UI frame.
        self.loaded = true
        local ok, entries = pcall(records.list_configs)
        if not ok or type(entries) ~= "table" then status(false, "配置列表刷新失败"); return false end
        local old = self.selection()
        select_path = select_path or (old and old.path)
        local rows, labels, selected = {}, {}, 1
        for _, entry in ipairs(entries) do
            if type(entry) == "table" and type(entry.path) == "string" then
                if #rows >= 256 then status(false, "配置超过 256 个，请先整理目录"); return false end
                local read_ok, meta = pcall(records.read_config_metadata, entry.path)
                local title,named
                if read_ok and type(meta) == "table" then
                    for _, value in ipairs({ meta.title or "", meta.description or "",
                        meta.fighter_name and (meta.fighter_name .. " 训练配置") or "" }) do
                        if type(value) == "string" and not value:match("^%s*$") then title = value; named=true; break end
                    end
                end
                if not title then title = entry.filename or "未命名配置" end
                -- Native hMsg interprets markup; file titles must remain plain text.
                title = title:gsub("[%c<>]", " "):match("^%s*(.-)%s*$")
                if utf8 and utf8.len then
                    local valid, count = pcall(utf8.len, title)
                    if not valid or not count then title = "未命名配置"
                    elseif count > 64 then title = title:sub(1, utf8.offset(title, 65) - 1) .. "..." end
                end
                rows[#rows + 1] = { path = entry.path, filename = entry.filename, legacy = entry.legacy,
                    metadata = read_ok and type(meta) == "table" and meta or {},display_title=named and title or nil }
                labels[#rows] = (entry.legacy and "[旧目录] " or "") .. title
                if entry.path == select_path then selected = #rows end
            end
        end
        -- Number equal titles within each fighter, independently of listing order.
        -- This is display-only: paths, stored names and recordings are untouched.
        local groups,reserved={},{}
        for i,entry in ipairs(rows) do
            local fighter=tostring(entry.metadata.fighter_id or "unknown")
            reserved[fighter]=reserved[fighter] or {}
            reserved[fighter][labels[i]]=true
            groups[fighter]=groups[fighter] or {}
            local by_name=groups[fighter]
            by_name[labels[i]]=by_name[labels[i]] or {}
            table.insert(by_name[labels[i]],i)
        end
        for fighter,by_name in pairs(groups) do
            for title,indices in pairs(by_name) do
                if #indices>1 then
                    table.sort(indices,function(a,b) return rows[a].path<rows[b].path end)
                    local suffix=0
                    for _,i in ipairs(indices) do
                        local label
                        repeat suffix=suffix+1; label=title.."（"..suffix.."）" until not reserved[fighter][label]
                        reserved[fighter][label]=true; labels[i]=label
                        if rows[i].display_title then rows[i].display_title=label end
                    end
                end
            end
        end
        self.entries, self.labels, self.selected = rows, labels, selected
        self.loaded, self.revision = true, self.revision + 1
        status(true, "已刷新，共 " .. #rows .. " 个配置")
        return true
    end
    function self.request(kind)
        if pending or note_edit then return false end
        if kind ~= "import" and kind ~= "export" and kind ~= "refresh" and kind ~= "save" and kind ~= "clear"
            and kind ~= "backup" and kind ~= "restore" and kind ~= "restore_native" then return false end
        local ctx, err = safe_context(true)
        if not ctx then status(false, err); return false end
        if kind == "restore_native" then
            if ctx.bank_unsupported ~= true then status(false, "当前录像已是原生8栏位"); return false end
        elseif ctx.bank_unsupported == true or (ctx.slot_count ~= nil and ctx.slot_count ~= 8) then
            status(false, "当前录像超过8栏位，请先恢复为原生8栏位")
            return false
        end
        if ctx.busy ~= false then status(false, "请先停止录制、播放或连段训练"); return false end
        local entry = self.selection()
        if (kind == "import" or kind == "save") and not entry then status(false, "请先选择配置"); return false end
        if kind == "save" and type(entry.metadata.record_slots)=="number"
            and entry.metadata.record_slots>8 then
            status(false, "此配置超过8栏位，无法覆盖；原文件未修改")
            return false
        end
        if kind == "import" then
            if type(entry.metadata.record_slots)=="number" and entry.metadata.record_slots>8 then
                status(false, "此配置超过8栏位，无法导入；原文件未修改")
                return false
            end
            local compatible, reason = self.selection_compatibility(ctx)
            if not compatible then status(false, reason); return false end
        end
        local options = {}
        for key, value in pairs(self.options) do options[key] = value end
        pending = { kind = kind, path = entry and entry.path, options = options,
            session = ctx.session, data = ctx.data, fighter_id = ctx.fighter_id,
            title=entry and entry.display_title }
        status(true, "已排队，关闭游戏暂停菜单后执行")
        return true
    end
    function self.cancel()
        cancel_requested=nil
        if pending and pending.task then pcall(pending.task.cancel, safe_context()) end
        if pending or note_edit then pending, note_edit = nil, nil; status(false, "环境改变，操作已取消") end
    end
    function self.request_cancel()
        cancel_requested=pending or note_edit
    end
    function self.abandon()
        -- Lua reset cannot safely run native task cleanup on its callback thread.
        -- Do not inspect the context, restore recorder settings or close a widget.
        pending,note_edit,cancel_requested=nil,nil,nil
    end
    function self.autoload(fighter)
        local path = remembered[tostring(fighter)]
        if not path or pending or note_edit then return false end
        if not self.refresh(path) then return false end
        local entry = self.selection()
        if not entry or entry.path ~= path or tonumber(entry.metadata.fighter_id) ~= fighter then
            status(false, "上次配置不存在或角色不匹配，未自动导入")
            return false
        end
        return self.request("import")
    end
    -- Native recordings persist in the game's own training data, so entering
    -- training never imports. Each new session re-selects this fighter's
    -- remembered configuration; its slot descriptions, which the game does not
    -- store, are read only the first time the fighter appears this Lua session.
    function self.restore_names(fighter)
        local state = records.select_fighter_annotations and records.select_fighter_annotations(fighter)
        local path = remembered[tostring(fighter)]
        if not path or pending or note_edit or not self.refresh(path) then return false end
        local entry = self.selection()
        if not entry or entry.path ~= path or tonumber(entry.metadata.fighter_id) ~= fighter then return false end
        if state ~= "new" or not records.load_config_annotations then return false end
        local ok, loaded = pcall(records.load_config_annotations, path)
        if not ok then diagnostic("Slot descriptions not loaded: " .. tostring(loaded)) end
        return ok and loaded == true
    end
    function self.has_pending() return pending ~= nil or note_edit ~= nil end
    function self.slot_capacity() return records.get_record_capacity and records.get_record_capacity() or 8 end
    function self.record_frames() return records.get_record_frames and records.get_record_frames() or nil end
    function self.slot_name(slot) return records.get_slot_name and records.get_slot_name(slot) or "" end
    function self.can_edit_slot_names() return type(records.set_slot_name)=="function" end
    function self.reset_slot_names() if records.reset_slot_names then records.reset_slot_names() end end
    local function note_context(token)
        if type(token) ~= "table" then return false end
        local ctx = safe_context()
        return note_edit == token and ctx and ctx.busy == false and ctx.session == token.session
            and ctx.data == token.data and ctx.fighter_id == token.fighter_id and ctx
    end
    function self.begin_note_edit(slot)
        if pending or note_edit then return nil end
        local ctx, err = safe_context()
        if not ctx or ctx.busy ~= false then status(false, err or "请先停止录制和播放"); return nil end
        if slot~=nil then
            if type(slot)~="number" or slot%1~=0 or slot<1 or slot>self.slot_capacity() then return nil end
            note_edit={slot=slot,session=ctx.session,data=ctx.data,fighter_id=ctx.fighter_id}
            return note_edit
        end
        local entry = self.selection()
        if not entry then status(false, "请先选择配置"); return nil end
        note_edit = { path = entry.path, session = ctx.session, data = ctx.data, fighter_id = ctx.fighter_id }
        return note_edit
    end
    function self.cancel_note_edit(token)
        if token == nil or note_edit ~= token then return end
        note_edit = nil
        status(true, "已取消编辑，文件未修改")
    end
    function self.prepare_note_edit(token)
        local ctx = note_context(token)
        if not ctx or ctx.menu_closed ~= true then self.cancel_note_edit(token); return nil end
        if token.slot then
            if token.slot>self.slot_capacity() then self.cancel_note_edit(token); return nil end
            token.edit=true
            return self.slot_name(token.slot)
        end
        local ok, edit, err = pcall(records.prepare_note_edit, token.path)
        if not ok or not edit then
            self.cancel_note_edit(token)
            diagnostic("Note preparation failed: " .. tostring(ok and err or edit))
            status(false, ok and err or "读取配置失败，未修改文件")
            return nil
        end
        token.edit = edit
        return edit.text
    end
    function self.submit_note_edit(token, text)
        if not note_context(token) or not token.edit then self.cancel_note_edit(token); return false end
        pending = { kind = token.slot and "slot_name" or "notes", slot=token.slot, path = token.path, edit = token.edit, text = text,
            session = token.session, data = token.data, fighter_id = token.fighter_id }
        note_edit = nil
        status(true, token.slot and "名称已确认，关闭弹窗后应用" or "配置名称已确认，关闭弹窗后保存")
        return true
    end
    function self.tick()
        if cancel_requested then
            local target=cancel_requested
            cancel_requested=nil
            if target==pending or target==note_edit then self.cancel(); return end
        end
        if not pending then return end
        if pending.running then return end
        local ctx = safe_context(pending.kind == "restore_native")
        if pending.task then
            local active = pending
            active.running = true
            local result = table.pack(pcall(active.task.tick, ctx))
            active.running = nil
            if pending ~= active then return end
            if result[1] and not result[2] then return end
            if not result[1] then pcall(active.task.cancel, ctx) end
            active.finished = result[1] and table.pack(true, table.unpack(result, 3, result.n))
                or table.pack(false, result[2])
            active.task = nil
        end
        if not pending.finished then
            if not ctx or ctx.session ~= pending.session or ctx.data ~= pending.data
                or ctx.fighter_id ~= pending.fighter_id then self.cancel(); return end
            if ctx.busy ~= false then self.cancel(); return end
            if ctx.menu_closed ~= true then return end
        end
        -- Take before invoking the backend: reentry and repeated callbacks cannot replay it.
        local job = pending
        pending = nil
        if job.kind == "refresh" then self.refresh(); return end
        if job.kind == "restore_native" then
            local ok, success, msg = pcall(records.restore_native_bank)
            self.result_revision = self.result_revision + 1
            legacy_cache = nil
            if not ok or success ~= true then
                diagnostic(ok and msg or success)
                status(false, "恢复未完成，请检查录像和反击设置")
                return
            end
            status(true, msg)
            return
        end
        if job.kind=="backup" or job.kind=="restore" then
            local action=job.kind=="backup" and records.backup_current or records.restore_latest_backup
            local ok,success,msg=pcall(action,job.options)
            self.result_revision=self.result_revision+1
            status(ok and success==true,ok and msg or "备份操作失败，请查看日志")
            if not ok then diagnostic(success) end
            return
        end
        if job.kind == "clear" then
            local ok, success, msg = pcall(records.clear_current_configuration)
            self.result_revision = self.result_revision + 1
            if not ok or success ~= true then
                diagnostic(ok and msg or success)
                status(false, "清空未完成，请查看日志及自动备份")
            else
                status(true, msg or "已清空全部录像栏位和三类反击，已保存的配置文件未修改")
            end
            return
        end
        if job.kind == "slot_name" then
            local ok,success,msg=pcall(records.set_slot_name,job.slot,job.text)
            self.result_revision=self.result_revision+1
            status(ok and success,ok and msg or "栏位改名失败，录像未修改")
            return
        end
        if job.kind == "notes" then
            local ok, success, msg = pcall(records.commit_note_edit, job.edit, job.text)
            self.result_revision = self.result_revision + 1
            self.result_configuration=nil
            if not ok or success ~= true then status(false, ok and msg or "配置名称保存失败，请检查原文件备份"); return end
            if not self.refresh(job.path) then status(false, "配置名称已保存，但列表刷新失败，请手动刷新"); return end
            local entry=self.selection()
            self.result_configuration={revision=self.result_revision,kind=job.kind,
                title=entry and entry.path==job.path and entry.display_title or nil}
            status(true, msg or "配置名称已保存")
            return
        end
        local ok, success, msg, path, payload, receipt
        if job.finished then
            ok, success, msg, path, payload, receipt = table.unpack(job.finished, 1, job.finished.n)
        elseif job.kind == "import" then
            ok, success, msg, path, payload, receipt = pcall(
                records.begin_import or records.import_from_file, job.path, job.options, ctx)
        elseif job.kind == "save" then
            ok, success, msg, path = pcall(records.save_current, job.path)
        else
            ok, success, msg, path = pcall(records.export_new)
        end
        if ok and success == true and type(receipt) == "table" and receipt.kind == "initializing" then
            job.task = receipt.task
            pending = job
            status(true, "正在初始化 " .. tostring(receipt.count) .. " 个空录像栏位，请稍候")
            return
        end
        self.result_revision = self.result_revision + 1
        self.result_configuration=nil
        local verb = job.kind == "save" and "保存" or (job.kind == "import" and "导入" or "导出")
        if not ok or success ~= true then
            diagnostic(ok and msg or success)
            status(false, verb .. "未完成，请检查文件、角色和录像状态；详细原因见日志")
            return
        end
        if success and (job.kind == "export" or job.kind == "save") then
            local refreshed = self.refresh(path)
            if not refreshed then diagnostic(msg); status(false, "配置已" .. verb .. "，但列表刷新失败，请手动刷新"); return end
        end
        local result_title=job.title
        if job.kind=="export" or job.kind=="save" then
            result_title=nil
            for _,entry in ipairs(self.entries) do
                if entry.path==path then result_title=entry.display_title; break end
            end
        end
        self.result_configuration={revision=self.result_revision,title=result_title,kind=job.kind}
        if job.kind == "export" or job.kind == "save" then remember(job.fighter_id, path)
        elseif not receipt or receipt.apply_state ~= "failed" then remember(job.fighter_id, job.path) end
        if job.kind == "export" or job.kind == "save" then
            status(true, "已" .. verb .. "：" .. tostring(path and path:match("([^/\\]+)$") or "新配置"))
        elseif type(receipt) == "table" and receipt.kind == "import" then
            local summary = "已导入 " .. tostring(receipt.written) .. " 个录像栏位，清空 " .. tostring(receipt.cleared)
                .. " 个，恢复 " .. tostring(receipt.reversals) .. " 项反击设置"
            if (receipt.initialized_slots or 0) > 0 then
                summary = summary .. "；已初始化 " .. tostring(receipt.initialized_slots) .. " 个空栏位"
            end
            if receipt.apply_state == "failed" then
                diagnostic(msg); status(false, summary .. "；即时应用失败，请查看日志及自动备份")
            else status(true, summary .. (receipt.apply_state == "skipped" and "；未启用即时应用" or "；已应用")) end
        else
            status(true, "配置已导入，请核对录像栏位及播放效果")
        end
    end
    return self
end

function M.runtime_context()
    local state = Safety.training_state()
    -- online_hold: matchmaking inside training. Nothing may run, but the
    -- session must not be treated as left and re-entered.
    if state ~= "training" then return { allowed = false, online_hold = state == "online" } end
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm or tm:get_field("_IsInit") ~= true then return { allowed = false } end
    local record = tm:call("get_RecordFunc")
    if not record then return { allowed = false } end
    local ctx = Records.get_context()
    local capacity_ok, slot_count = pcall(Records.get_record_bank_size)
    local unsupported = capacity_ok and type(slot_count) == "number" and slot_count > 8
    local recording, replay = record:call("IsRecording"), record:call("IsReplayNow")
    local pause = sdk.get_managed_singleton("app.PauseManager")
    local bit = pause and pause:get_field("_CurrentPauseTypeBit")
    return { allowed = true, session = tm, data = tm:get_field("_tData"),
        fighter_id = ctx.fighter_id,
        error = ctx.error or (slot_count ~= 8 and "当前录像不是8栏位" or nil),
        bank_unsupported = unsupported,
        slot_count = capacity_ok and slot_count or nil,
        menu_closed = bit == 64 or bit == 2112,
        record_func = record, recording = recording, replay = replay,
        combo_busy = _G.ComboTrials_IsPlaying == true or _G.ComboTrials_IsRecording == true,
        busy = recording ~= false or replay ~= false
            or _G.ComboTrials_IsPlaying == true or _G.ComboTrials_IsRecording == true }
end

function M.shared()
    if not M.instance then
        local path = "SF6CC_TrainingConfigs/last_selected.json"
        local choices = {
            load = function()
                local ok, data = pcall(json.load_file, path)
                return ok and type(data) == "table" and data or {}
            end,
            save = function(data) return json.dump_file(path, data) end,
        }
        M.instance = M.new(require("SF6CCTrainingLibrary/Records"), M.runtime_context, choices)
    end
    return M.instance
end

return M
