-- Pure save-call correlation. Native storage may copy a returned baseline.
local M = {}
local MAX_PENDING = 64
local function same_snapshot(a,b)
    if not a or not b or a.container~=b.container or #a.items~=#b.items then return false end
    for i,address in ipairs(a.items) do if address~=b.items[i] then return false end end
    return true
end

function M.new()
    local scopes,controllers,next_id={},{},0
    local self={}
    function self.begin(thread_id,controller,training)
        next_id=next_id+1
        local frame={id=next_id,thread_id=thread_id,controller=controller,training=training,
            previous=scopes[thread_id],tickets={}}
        scopes[thread_id]=frame
        -- A new start invalidates the prior identity binding, not its pending tickets.
        if training then controllers[controller]=frame end
        return frame
    end
    function self.issue(thread_id,entry)
        entry.issued=entry.issued+1
        entry.pending_saves=entry.pending_saves or {}
        local frame=scopes[thread_id]
        if entry.issued-entry.completed>MAX_PENDING then return end
        local ticket={entry=entry,scoped=frame~=nil}
        entry.pending_saves[ticket]=true
        if frame and frame.training then frame.tickets[#frame.tickets+1]=ticket end
    end
    function self.end_start(frame,snapshot,started)
        assert(scopes[frame.thread_id]==frame,"save call scope mismatch")
        scopes[frame.thread_id]=frame.previous
        if frame.training and controllers[frame.controller]==frame then
            if started and snapshot and #snapshot.items>0 and #frame.tickets>0 then
                frame.snapshot=snapshot
            else
                controllers[frame.controller]=nil
            end
        end
    end
    function self.capture(controller,snapshot,entries)
        local batch={}
        local frame=controllers[controller]
        if frame and same_snapshot(frame.snapshot,snapshot) then
            batch.transaction=frame
            for _,ticket in ipairs(frame.tickets) do
                if not ticket.done then batch[#batch+1]=ticket end
            end
        end
        -- Preserve direct, unscoped saves only with one unambiguous pending return.
        local owned={}
        for _,address in ipairs(snapshot.items) do owned[address]=true end
        for _,entry in ipairs(entries) do
            if entry.baseline and entry.readers==0 and owned[entry.baseline:get_address()] then
                local candidate,count=nil,0
                for ticket in pairs(entry.pending_saves or {}) do candidate=ticket; count=count+1 end
                if count==1 and not candidate.scoped then batch[#batch+1]=candidate end
            end
        end
        return batch
    end
    function self.complete(batch)
        for _,ticket in ipairs(batch) do
            if not ticket.done then
                ticket.done=true
                ticket.entry.pending_saves[ticket]=nil
                -- Count acknowledgements, not the highest generation: saves can finish out of order.
                ticket.entry.completed=ticket.entry.completed+1
            end
        end
        local frame=batch.transaction
        if frame and controllers[frame.controller]==frame then controllers[frame.controller]=nil end
    end
    return self
end
return M
