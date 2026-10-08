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
local function training_state()
    local tm = sdk.get_managed_singleton("app.training.TrainingManager")
    if not tm or read(tm,"_IsInit") ~= true or read(tm,"_GameMode") ~= 1 then return nil end
    local data = read(tm,"_tData")
    if not data or not read(data,"SelectMenu") or not read(data,"RecordSetting")
        or not read(tm,"_UIData") then return nil end
    local network = sdk.get_managed_singleton("app.network.NetworkManager")
    if not network then return nil end
    local flow = sdk.get_managed_singleton("app.bFlowManager")
    local work = read(flow,"m_flow_work")
    local map = work and work._FlowMap
    local id = map and map._ID
    if id == 9 or id == 10 then return nil end
    local recorder = tm:call("get_RecordFunc")
    local owner = read(recorder,"_tData")
    if owner == nil or owner:get_address() ~= data:get_address() then return nil end
    -- Matchmaking from training switches this rule to an online mode for about
    -- a second per search attempt while the training scene stays intact.
    local session = read(network,"<Session>k__BackingField")
    local battle = read(session,"<FGBattle>k__BackingField")
    local rule = read(battle,"<BattleRule>k__BackingField")
    if rule then
        local mode = read(rule,"GameMode")
        if type(mode) ~= "number" or ONLINE[mode] then return "online" end
    end
    return "training"
end
-- "training": operations allowed. "online": the training scene is intact but an
-- online battle rule is set, so operations pause without ending the session.
-- nil: not in offline training.
function M.training_state()
    local ok, state = pcall(training_state)
    return ok and state or nil
end
function M.is_training_allowed()
    return M.training_state() == "training"
end
return M
