-- Fresh, read-only offline-training gate. No SF6CC publisher or cached globals.
local M = {}
local ONLINE = { [14]=true, [15]=true, [16]=true, [17]=true, [18]=true }
local function read(obj, key) return obj and obj:get_field(key) end
function M.pause_open()
    local ok, bit = pcall(function()
        return read(sdk.get_managed_singleton("app.PauseManager"), "_CurrentPauseTypeBit")
    end)
    if not ok or type(bit) ~= "number" then return nil end
    return bit ~= 64 and bit ~= 2112
end
function M.is_training_allowed()
    local ok, allowed = pcall(function()
        local tm = sdk.get_managed_singleton("app.training.TrainingManager")
        if not tm or read(tm,"_IsInit") ~= true or read(tm,"_GameMode") ~= 1 then return false end
        local data = read(tm,"_tData")
        if not data or not read(data,"SelectMenu") or not read(data,"RecordSetting")
            or not read(tm,"_UIData") then return false end
        local network = sdk.get_managed_singleton("app.network.NetworkManager")
        if not network then return false end
        local session = read(network,"<Session>k__BackingField")
        local battle = read(session,"<FGBattle>k__BackingField")
        local rule = read(battle,"<BattleRule>k__BackingField")
        if rule then
            local mode = read(rule,"GameMode")
            if type(mode) ~= "number" or ONLINE[mode] then return false end
        end
        local flow = sdk.get_managed_singleton("app.bFlowManager")
        local work = read(flow,"m_flow_work")
        local map = work and work._FlowMap
        local id = map and map._ID
        if id == 9 or id == 10 then return false end
        local recorder = tm:call("get_RecordFunc")
        local owner = read(recorder,"_tData")
        return owner ~= nil and owner:get_address() == data:get_address()
    end)
    return ok and allowed == true
end
return M
