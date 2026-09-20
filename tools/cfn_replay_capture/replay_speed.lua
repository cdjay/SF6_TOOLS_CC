local M = {}
function M.matches(a,b)
    return type(a)=="number" and type(b)=="number" and math.abs(a-b)<=0.0001
end
function M.new(sdk)
    local values
    local adapter={matches=M.matches}
    local function value(item)
        if not item then return nil end
        if not values then
            local enum=sdk.find_type_definition("app.esports.ReplayUICtrl.SpeedData.ESpeed")
            if not enum then return nil end
            values={}
            -- Resolve named enum values; neither the enum ordinals nor array indices are multipliers.
            for _,name in ipairs({"0_5","0_6","0_7","0_8","0_9","1_0","1_1","1_2","1_3","1_4","1_5","2_0","4_0","8_0"}) do
                local field=enum:get_field("Speed_"..name)
                local id=field and tonumber(field:get_data(nil))
                if id then values[id]=tonumber((name:gsub("_","."))) end
            end
        end
        -- Calling GetSpeedValue on array value-type copies returned 0.5 for every live entry.
        return values[tonumber(item:get_field("Speed"))]
    end
    local function list(ui)
        local speeds=ui:get_field("_ReplaySpeeds")
        if not speeds then return nil end
        local count=speeds:get_size()
        if type(count)~="number" or count<1 or count>64 or count%1~=0 then return nil end
        return speeds,count
    end
    function adapter.read(ui)
        local speeds,count=list(ui)
        local index=tonumber(ui:get_field("_CurretSpeed"))
        if speeds and index and index%1==0 and index>=0 and index<count then
            return value(speeds:get_element(index))
        end
    end
    function adapter.set(ui,target)
        if type(target)~="number" or target~=target or target<0.1 or target>8 then return false,"speed_unavailable" end
        local speeds,count=list(ui)
        if not speeds then return false,"speed_list_unavailable" end
        local match
        for index=0,count-1 do
            if M.matches(value(speeds:get_element(index)),target) then
                if match~=nil then return false,"speed_ambiguous" end
                match=index
            end
        end
        if match==nil then return false,"speed_target_missing" end
        if tonumber(ui:get_field("_CurretSpeed"))==match then return true end
        if ui:call("CanChangedSpeed(System.Int32)",match)~=true then return false,"speed_change_denied" end
        -- Parameters verified in the generated API: speedIndex, isOverwritePrev.
        ui:call("ChangeSpeed(System.Int32, System.Boolean)",match,true)
        return true
    end
    return adapter
end
return M
