-- Saved scalar evidence only. No game access, move naming or skill scores.
local M={}
local function number(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function integer(n) return number(n) and n>=0 and n%1==0 end
local function inc(t,k,n) t[k]=(t[k] or 0)+(n or 1) end
local function moment() return {frames=0,mean=0,m2=0,min=nil,max=nil,gain=0,drop=0,zero=0,low=0,full=0} end
local function observe(m,v)
    m.frames=m.frames+1; local delta=v-m.mean; m.mean=m.mean+delta/m.frames; m.m2=m.m2+delta*(v-m.mean)
    m.min=math.min(m.min or v,v); m.max=math.max(m.max or v,v)
end
function M.distribution(values)
    local a={}; for i,v in ipairs(values) do a[i]=v end; table.sort(a)
    local n=#a
    if n==0 then return {n=0} end
    local function quantile(q)
        local k=1+(n-1)*q; local lo=math.floor(k)
        return a[lo]+(a[math.min(n,lo+1)]-a[lo])*(k-lo)
    end
    local r=moment(); local sum=0
    for _,v in ipairs(a) do observe(r,v); sum=sum+v end
    local top=0; for i=math.max(1,n-2),n do top=top+a[i] end
    return {n=n,sum=sum,mean=r.mean,sd=math.sqrt(r.m2/n),min=a[1],max=a[n],q1=quantile(.25),
        median=quantile(.5),q3=quantile(.75),p90=a[math.ceil(n*.9)],top3_share=sum>0 and top/sum or nil}
end
local categories={"forward","backward","walk","attack","guard","parry","throw","air","dash","reaction","down","neutral","other","unknown"}
M.categories=categories
M.labels={forward="前走",backward="后走",walk="其他移动",attack="地面出招",guard="防御",parry="蓝防",throw="抓取 / 演出",
    air="空中",dash="前冲",reaction="受击 / 演出",down="倒地 / 起身",neutral="站蹲待机",other="其他状态",unknown="状态未知"}
M.damage_edges={500,1000,2000,3000,5000,math.huge}
M.distance_edges={50,100,150,200,300,400,600,math.huge}
local function bin(edges,v) for i,e in ipairs(edges) do if v<e then return i end end return #edges end
local function player()
    return {behavior={},entries={},features={},feature_valid={},signals={},signal_frames=0,directions={},direction_frames=0,direction_changes=0,
        resources={health=moment(),drive=moment(),super=moment()},damage_received=0,damage_dealt=0,losses={},dealt={},
        damage_bins={},causes={},priorities={},segments=0,damage_observations=0,unknown_source_damage=0}
end
local function scope(round)
    return {round=round,frames=0,first_frame=nil,last_frame=nil,players={player(),player()},distance={},distance_bins={},
        positions={},series={health={{},{}},drive={{},{}},super={{},{}}},missing={}}
end
local function direction(input,facing)
    if not integer(input) or (facing~=0 and facing~=1) or input & 3==3 or input & 12==12 then return nil end
    local horizontal=input & (facing==1 and 8 or 4)~=0 and 1 or input & (facing==1 and 4 or 8)~=0 and -1 or 0
    local vertical=input & 1~=0 and 1 or input & 2~=0 and -1 or 0
    return 5+horizontal+vertical*3
end
local function category(state,y,dir)
    if not number(state) then return "unknown" end
    if state==27 or state==28 then return "guard" end
    if state==32 or state==38 then return "reaction" end
    if state==34 or state==35 or state==36 then return "down" end
    if number(y) and y>0 then return "air" end
    if state==29 or state==30 or state==31 then return "attack" end
    if state==39 then return "parry" end
    if state==37 then return "throw" end
    if state==10 then return "dash" end
    if state==8 or state==9 then
        if dir and (dir==3 or dir==6 or dir==9) then return "forward" end
        if dir and (dir==1 or dir==4 or dir==7) then return "backward" end
        return "walk"
    end
    if state==0 or state==1 or state==3 or state==4 or state==5 or state==6 then return "neutral" end
    return "other"
end
local gauges={health={"vital_new","vital_max"},drive={"focus_new","focus_max"},super={"mSuperGauge","mSuperGaugeMax"}}
function M.new(schema,metadata)
    if not metadata or metadata.version~=20004000 then return nil,"unsupported_analysis" end
    local ix=schema.index
    local s={all=scope(nil),by_round={},rounds={},metadata=metadata,duplicates=0,gaps=0,transitions=0,seen=0,excluded_after_end=0}
    local previous,highest
    local function get(r,n) return r and r[ix[n]] end
    local function p(r,side,n) return get(r,"p"..side.."."..n) end
    local function timer(r)
        local sec,part=get(r,"play_timer"),get(r,"play_timer_ms")
        if not integer(sec) or not integer(part) or part>60 then return nil end
        return sec*60+part
    end
    local function percent(r,side,key)
        local names=gauges[key]; local v,max=p(r,side,names[1]),p(r,side,names[2])
        if not number(v) or not number(max) or max<=0 or v<0 or v>max then return nil end
        return v/max*100
    end
    local function add_to(a,row,prior,continuous,frame)
        a.frames=a.frames+1; a.first_frame=a.first_frame or frame; a.last_frame=frame
        for side=1,2 do
            local out=a.players[side]
            local st,y=p(row,side,"act_st"),p(row,side,"y_raw")
            local dir=direction(p(row,side,"pl_input_new"),p(row,side,"facing_right"))
            local cat=category(st,y,dir)
            inc(out.behavior,cat)
            if continuous then
                local old=category(p(prior,side,"act_st"),p(prior,side,"y_raw"),direction(p(prior,side,"pl_input_new"),p(prior,side,"facing_right")))
                if old~="unknown" and cat~="unknown" and old~=cat then inc(out.entries,cat) end
            end
            for name,value in pairs({forward=cat=="forward",backward=cat=="backward",air=number(y) and y>0,
                attack=st==29 or st==30 or st==31,guard=st==27 or st==28,parry=st==39}) do if value then inc(out.features,name) end end
            for _,name in ipairs({"forward","backward","air","attack","guard","parry"}) do
                local valid=(name=="air" and number(y)) or (name~="air" and number(st) and
                    ((name~="forward" and name~="backward") or dir~=nil))
                if valid then inc(out.feature_valid,name) end
            end
            if dir then
                inc(out.directions,dir); out.direction_frames=out.direction_frames+1
                local old=continuous and direction(p(prior,side,"pl_input_new"),p(prior,side,"facing_right")) or nil
                if old and old~=dir then out.direction_changes=out.direction_changes+1 end
            end
            local hit,old=p(row,side,"hit_st"),continuous and p(prior,side,"hit_st") or nil
            if integer(hit) and integer(old) then
                out.signal_frames=out.signal_frames+1
                for name,mask in pairs({hit=0x8000,guard=4,counter=0x80,punish=0x100}) do
                    if hit & mask~=0 and old & mask==0 then inc(out.signals,name) end
                end
            end
            for key in pairs(gauges) do
                local v=percent(row,side,key); local m=out.resources[key]
                if v then
                    observe(m,v)
                    if v==0 then m.zero=m.zero+1 end
                    if v<=25 then m.low=m.low+1 end
                    if v==100 then m.full=m.full+1 end
                    local before=continuous and percent(prior,side,key) or nil
                    if before and p(row,side,gauges[key][2])==p(prior,side,gauges[key][2]) then
                        m.delta_frames=(m.delta_frames or 0)+1
                        if v>before then m.gain=m.gain+v-before else m.drop=m.drop+before-v end
                    end
                    if a.round~=nil then
                        local cells=a.series[key][side]; local index=math.floor(frame/30)
                        local last=cells[#cells]
                        if not last or last.index~=index or not continuous or not number(before) then
                            last={index=index,first=frame,last=frame,first_value=v,value=v,min=v,max=v,connected=continuous and number(before) and last~=nil}
                            cells[#cells+1]=last
                        else last.last=frame; last.value=v; last.min=math.min(last.min,v); last.max=math.max(last.max,v) end
                    end
                else inc(a.missing,"p"..side.."."..key) end
            end
        end
        local x1,x2=p(row,1,"x_raw"),p(row,2,"x_raw")
        if number(x1) and number(x2) then
            local distance=math.abs(x1-x2)/65536
            a.distance[#a.distance+1]=distance; inc(a.distance_bins,bin(M.distance_edges,distance))
        end
    end
    function s:add(row)
        if self.error or self.finished then return end
        self.seen=self.seen+1
        local round,frame,stage=get(row,"round"),get(row,"replay_frame"),get(row,"stage_frame")
        if not integer(round) or not integer(frame) or not integer(stage) then self.error="invalid_clock"; return end
        if highest and round<highest then self.error="rewound_capture"; return end
        highest=round
        if round~=get(row,"battle_round") then self.transitions=self.transitions+1; previous=nil; return end
        local info=self.by_round[round]
        if not info then info=scope(round); self.by_round[round]=info; self.rounds[#self.rounds+1]=info end
        if previous and round==get(previous,"round") and frame==get(previous,"replay_frame") and stage==get(previous,"stage_frame") then
            for side=1,2 do for _,name in ipairs({"vital_new","focus_new","mSuperGauge","x_raw","y_raw","act_st","hit_st","pl_input_new"}) do
                if p(row,side,name)~=p(previous,side,name) then self.error="conflicting_samples"; return end
            end end
            self.duplicates=self.duplicates+1; previous=row; return
        end
        if previous and round==get(previous,"round") and (frame<get(previous,"replay_frame") or stage<get(previous,"stage_frame")) then
            self.error="rewound_capture"; return
        end
        if info.ending then self.excluded_after_end=self.excluded_after_end+1; previous=row; return end
        local contiguous=previous and round==get(previous,"round") and frame==get(previous,"replay_frame")+1 and stage==get(previous,"stage_frame")+1
        if previous and round==get(previous,"round") and not contiguous then self.gaps=self.gaps+1 end
        local continuous=contiguous and get(row,"fight_st")==get(previous,"fight_st")
        local before,now=timer(previous),timer(row)
        -- Conservative chart lower bound, not a claim about the game's first playable frame.
        if not info.seek_first and continuous and before and now and now<before then info.seek_first=frame end
        add_to(info,row,previous,continuous,frame); add_to(self.all,row,previous,continuous,frame)
        info.positions[#info.positions+1]=frame
        local hp1,hp2=p(row,1,"vital_new"),p(row,2,"vital_new")
        if number(hp1) and number(hp2) and hp1>0 and hp2>0 then info.live_seen=true end
        if info.live_seen then
            if hp1==0 and hp2==0 then info.ending="both_zero"
            elseif hp1==0 then info.ending="p1_zero" elseif hp2==0 then info.ending="p2_zero"
            elseif get(row,"play_timer")==0 and get(row,"play_timer_ms")==0 then info.ending="timeout" end
        end
        previous=row
    end
    function s:nearest_frame(round,target)
        if self.error or not number(target) then return nil end
        local r=self.by_round[round]; if not r or #r.positions==0 then return nil end
        if not r.seek_first then return nil end
        target=math.max(target,r.seek_first)
        local a=r.positions; local lo,hi=1,#a
        while lo<hi do local mid=math.floor((lo+hi)/2); if a[mid]<target then lo=mid+1 else hi=mid end end
        if lo>1 and math.abs(a[lo-1]-target)<math.abs(a[lo]-target) then lo=lo-1 end
        return a[lo]
    end
    function s:finish(items,review_items,playback_finished,engine)
        if self.finished then return end
        self.finished=true; self.playback_finished=playback_finished==true
        if self.error then return end
        local function damage(a,item)
            local out=a.players[item.receiver]; out.damage_received=out.damage_received+item.damage
            out.segments=out.segments+1; out.damage_observations=out.damage_observations+(item.damage_observations or 0)
            out.losses[#out.losses+1]=item.damage; inc(out.damage_bins,bin(M.damage_edges,item.damage))
            local rule=item.classification.rule; local entry=out.causes[rule] or {title=item.classification.title,count=0,damage=0,items={}}
            out.causes[rule]=entry; entry.count=entry.count+1; entry.damage=entry.damage+item.damage; entry.items[#entry.items+1]=item
            if not out.largest or item.damage>out.largest.damage then out.largest=item end
            local source=item.facts and item.facts.source_observed
            if source==3-item.receiver then
                local attacker=a.players[source]; attacker.damage_dealt=attacker.damage_dealt+item.damage; attacker.dealt[#attacker.dealt+1]=item.damage
            else out.unknown_source_damage=out.unknown_source_damage+item.damage end
        end
        for _,item in ipairs(items or {}) do
            if self.by_round[item.round] then damage(self.all,item); damage(self.by_round[item.round],item) end
        end
        for _,item in ipairs(review_items or items or {}) do
            for _,a in ipairs({self.all,self.by_round[item.round]}) do
                if a and item.priority and (not engine or engine:includes(item)) then inc(a.players[item.receiver].priorities,item.priority) end
            end
        end
        local scopes={self.all}; for _,r in ipairs(self.rounds) do scopes[#scopes+1]=r end
        for _,a in ipairs(scopes) do
            a.distance_distribution=M.distribution(a.distance); a.distance=nil
            for _,out in ipairs(a.players) do
                out.loss_distribution=M.distribution(out.losses); out.dealt_distribution=M.distribution(out.dealt)
                out.losses,out.dealt=nil,nil
                local entropy=0
                for _,n in pairs(out.directions) do local p=n/out.direction_frames; entropy=entropy-p*math.log(p,2) end
                out.direction_entropy=out.direction_frames>0 and entropy/math.log(9,2) or nil
                for _,r in pairs(out.resources) do r.sd=r.frames>0 and math.sqrt(r.m2/r.frames) or nil; if r.frames==0 then r.mean=nil end end
            end
        end
    end
    function s:relabel(items,review_items,engine)
        if not self.finished or self.error then return end
        local scopes={self.all};for _,r in ipairs(self.rounds) do scopes[#scopes+1]=r end
        for _,a in ipairs(scopes) do for _,p in ipairs(a.players) do p.causes,p.priorities,p.largest={},{},nil end end
        for _,item in ipairs(items or {}) do
            for _,a in ipairs({self.all,self.by_round[item.round]}) do
                if a then
                    local p=a.players[item.receiver];local rule=item.classification.rule
                    local entry=p.causes[rule] or {title=item.classification.title,count=0,damage=0,items={}}
                    p.causes[rule]=entry;entry.count=entry.count+1;entry.damage=entry.damage+item.damage;entry.items[#entry.items+1]=item
                    if not p.largest or item.damage>p.largest.damage then p.largest=item end
                end
            end
        end
        for _,item in ipairs(review_items or items or {}) do
            for _,a in ipairs({self.all,self.by_round[item.round]}) do
                if a and item.priority and (not engine or engine:includes(item)) then inc(a.players[item.receiver].priorities,item.priority) end
            end
        end
    end
    return s
end
return M
