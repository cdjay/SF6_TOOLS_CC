-- Detached native name-picker pages. UI construction is supplied by its owner.
local Layout=require("SF6CCTrainingLibrary/TrainingSlotLayout")
local M={}
function M.new(make,arr,library,editor)
    local pages,kinds,current={}, {},nil
    local function address(o) return o and o:get_address() end
    local function count() return math.ceil(math.min(library.slot_capacity(),Layout.EXPANDED_RECORDS)/8) end
    local function row(kind,title,slot)
        local data=make(0,title,true,nil,nil,kind=="header")
        kinds[address(data)]={kind=kind,slot=slot}
        return data
    end
    for p=1,Layout.EXPANDED_RECORDS/8 do
        local rows={row("header",function() return "槽位名称  "..p.." / "..count() end)}
        for n=(p-1)*8+1,p*8 do
            rows[#rows+1]=row("slot",function()
                local name=library.slot_name(n)
                return "槽位"..n.."："..(name~="" and name or "默认名称")
            end,n)
        end
        rows[#rows+1]=row("previous","上一页")
        rows[#rows+1]=row("next","下一页")
        rows[#rows+1]=row("back","返回")
        pages[p]=make(22,"槽位名称",true)
        for _,data in ipairs(rows) do kinds[address(data)].page=p end
        pages[p]:set_field("_ChildData",arr(rows))
    end
    local self={}
    function self.open() current=1; return pages[current] end
    function self.close() current=nil end
    function self.current() return current and pages[current] end
    function self.owns(data,parent)
        local item=kinds[address(data)]
        return current~=nil and address(parent)==address(pages[current]) and item~=nil and item.page==current
    end
    function self.active(data,parent)
        if not self.owns(data,parent) then return false end
        local item=kinds[address(data)]
        if item.kind=="header" then return false end
        if item.kind=="previous" then return current>1 end
        if item.kind=="next" then return current<count() end
        return item.kind~="slot" or item.slot<=library.slot_capacity()
    end
    function self.handle(data,parent)
        if not self.owns(data,parent) then return false end
        if not self.active(data,parent) or library.has_pending() then return true,false end
        local item=kinds[address(data)]
        if item.kind=="back" then current=nil
        elseif item.kind=="previous" then current=current-1
        elseif item.kind=="next" then current=current+1
        elseif item.kind=="slot" then
            local close=editor.request(item.slot)==true
            if close then current=nil end
            return true,close
        end
        return true,false
    end
    return self
end
return M
