-- void show_custom_ticker(String message, Single time, Int32 category)
-- or
-- void show_custom_ticker(Function message, Single time, Int32 category)
--     Function message <= Function that returns String value (useful to handle localization thing)
-- Just shows a ticker with some message.
-- time is how long the ticker will be displayed in seconds.
-- category is enum (app.AppDefine.TickerCategory).

local sdk = sdk

local this = {}
this.mReq = nil
this.message = {}
this.queue = {}

function this.isGameReady()
    local bFlowManager = sdk.get_managed_singleton("app.bFlowManager")
    return bFlowManager and bFlowManager:get_MainFlowID() ~= 1
end
function this.initReq()
    if this.mReq then return sdk.PreHookResult.CALL_ORIGINAL end
    this.mReq = sdk.create_instance("app.TickerRequestData", true)
    this.mReq:Init(112,nil)
    this.mReq.TickerId = 1
end
function this.show_custom_ticker(message, time, category)
    if category == nil then category = 6 end
    if time == nil or time <= 0 then time = 3.5 end
    if not this.isGameReady() then
        table.insert(this.queue,{message, time, category})
        return
    end
    sdk.find_type_definition("app.TickerUtil"):get_method(".cctor"):call(nil)
    if this.mReq then
        this.message[this.mReq.RequestId.mData4L] = message
        this.mReq.Category = category
        this.mReq.DisplaySecond = time
        local manager = sdk.find_type_definition("app.helper.hTicker"):get_method("get_Manager"):call(nil)
        if manager then
            manager:call("RequestShowTicker(app.TickerRequestData)", this.mReq)
        end
        this.mReq = nil
    end
end



sdk.hook(sdk.find_type_definition("app.TickerUtil"):get_method(".cctor"), this.initReq) 
sdk.hook(sdk.find_type_definition("app.TickerRequestData"):get_method("GetMessage"), function(args)
    for k,v in pairs(this.message) do
        if k == sdk.to_managed_object(args[2]).RequestId.mData4L then
            if type(v) == "function" then
                thread.get_hook_storage()["message"] = v()
            else
                thread.get_hook_storage()["message"] = v
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end
end,function(retval)
    local m = thread.get_hook_storage()["message"]
    if m then
        return sdk.to_ptr(sdk.create_managed_string(m))
    end
    return retval
end)
sdk.hook(sdk.find_type_definition("app.bBootFlow"):get_method("UpdatePhaseTransition"), function()
    if #this.queue > 0 then
        for k,v in ipairs(this.queue) do
            this.show_custom_ticker(table.unpack(v))
        end
        this.queue = {}
    end
end)

return this.show_custom_ticker