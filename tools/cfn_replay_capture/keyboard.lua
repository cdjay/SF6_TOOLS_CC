local M = {}
M.press_ms_options = {45, 30, 20, 12}
function M.allowed_press_ms(value)
    for _, n in ipairs(M.press_ms_options) do if value == n then return true end end
    return false
end
function M.new(deps)
    local k = { sequence = 0 }
    local now = deps.time or os.time
    local function healthy(ready)
        if type(ready) ~= "table" or ready.protocol ~= 1 or type(ready.token) ~= "string" or ready.token == ""
            or type(ready.updated_at) ~= "number" then return false end
        local age = now() - ready.updated_at
        return age >= 0 and age <= 6
    end
    function k:overlay_open()
        if self.hide_request then
            local reply = self:poll(self.hide_request)
            if not reply and now()-self.hide_started<3 then return true end
            self.hide_error = reply~="sent" and (reply or "expired") or nil
            if reply~="sent" then self.restore_owned=nil end
            self.hide_request=nil
        end
        return deps.reframework:is_drawing_ui()
            or deps.review_input_blocked and deps.review_input_blocked() == true or false
    end
    function k:hide_overlay()
        if self.hide_request or self.restore_request then return false end
        self.hide_error,self.restore_error=nil,nil
        if not deps.reframework:is_drawing_ui() then return true end
        local ready=deps.json.load_file("cfn-keyboard-ready.json")
        if not healthy(ready) or ready.hide_overlay~=true then self.hide_error="keyboard_unavailable"; return false end
        self.sequence=self.sequence+1
        local request={token=ready.token,id=tostring(deps.date("%Y%m%d%H%M%S")).."-"..tostring(self).."-"..self.sequence,
            action="hide_overlay",press_ms=45}
        if deps.json.dump_file("cfn-keyboard-request.json",request,-1)~=true then self.hide_error="send_failed"; return false end
        self.hide_request,self.hide_started=request,now()
        self.restore_owned=request.token
        self.last_game_request=nil
        return true
    end
    function k:update_handoff(busy)
        if self.hide_request then self:overlay_open(); if self.hide_request then return end end
        if self.restore_request then
            local reply=self:poll(self.restore_request)
            if not reply and now()-self.restore_started<3 then return end
            self.restore_error=reply~="sent" and (reply or "expired") or nil
            self.restore_request=nil
            return
        end
        if busy or not self.restore_owned then return end
        if deps.reframework:is_drawing_ui() then self.restore_owned=nil; return end
        if self.last_game_request then
            local reply=self:poll(self.last_game_request)
            if not reply and now()-self.last_game_started<3 then return end
            if not reply or reply=="release_failed" then self.restore_owned=nil; self.restore_error=reply or "expired"; return end
        end
        local token=self.restore_owned; self.restore_owned=nil
        local ready=deps.json.load_file("cfn-keyboard-ready.json")
        if not healthy(ready) or ready.token~=token or ready.restore_overlay~=true then self.restore_error="keyboard_unavailable"; return end
        self.sequence=self.sequence+1
        local request={token=token,id=tostring(deps.date("%Y%m%d%H%M%S")).."-"..tostring(self).."-"..self.sequence,
            action="show_overlay",press_ms=45}
        if deps.json.dump_file("cfn-keyboard-request.json",request,-1)~=true then self.restore_error="send_failed"; return end
        self.restore_request,self.restore_started=request,now()
    end
    function k:cancel_handoff()
        if self.hide_request then self:cancel(self.hide_request); self.hide_request=nil end
        if self.restore_request then self:cancel(self.restore_request); self.restore_request=nil end
        self.restore_owned=nil
    end
    function k:send(key, press_ms)
        press_ms = press_ms or 45
        if not M.allowed_press_ms(press_ms) then return nil, "press_unavailable" end
        local ready = deps.json.load_file("cfn-keyboard-ready.json")
        if not healthy(ready) then return nil, "keyboard_unavailable" end
        if press_ms ~= 45 then
            local supported = false
            for _, n in ipairs(type(ready.press_ms_options) == "table" and ready.press_ms_options or {}) do
                if n == press_ms then supported = true end
            end
            if not supported then return nil, "press_unavailable" end
        end
        self.sequence = self.sequence + 1
        local id = tostring(deps.date("%Y%m%d%H%M%S")) .. "-" .. tostring(self) .. "-" .. self.sequence
        local request = { token = ready.token, id = id, key = key, press_ms = press_ms }
        if deps.json.dump_file("cfn-keyboard-request.json", request, -1) ~= true then return nil, "send_failed" end
        self.last_game_request,self.last_game_started=request,now()
        return request
    end
    function k:poll(request)
        local reply = deps.json.load_file("cfn-keyboard-response.json")
        if type(reply) == "table" and reply.token == request.token and reply.id == request.id then
            if reply.status == "sent" and request.press_ms ~= 45 and reply.press_ms ~= request.press_ms then
                return "press_unavailable"
            end
            return reply.status, reply
        end
        local ready = deps.json.load_file("cfn-keyboard-ready.json")
        if not healthy(ready) or ready.token ~= request.token then return "keyboard_unavailable" end
    end
    function k:cancel(request)
        return deps.json.dump_file("cfn-keyboard-cancel.json", { token = request.token, id = request.id }, -1)
    end
    return k
end
return M
