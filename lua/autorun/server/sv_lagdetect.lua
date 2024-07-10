local threshold_start = {150,60,30,15} -- maximum processing time before slowing down, sorted most>least severe; 15ms = ~1 tick
local speeds = {0,0.03,0.3,0.75} -- corresponding timescales to use
local function Cooldown(level,ms) return math.Min(3+(#speeds-level) + ms/30,20) end -- how long to stay at the slower speed before ramping back up

local svrcolor = 90/#speeds

local speed = 1
local cooldown = 0
local t_raw,t = 0,0
local level = #speeds+1
local msgcolor = Color(255,255,255)
local p,m = Color(255,50,25),"[LagDetect] "
local cv = GetConVar("phys_timescale")
util.AddNetworkString("lagdetect_notify")

MsgC(p,m,msgcolor,"Loaded!\n")
game.ConsoleCommand("phys_timescale 1\n")

local function FindIntersects(svr)
    local allents = ents.FindByClass("prop_*")
    table.Add(allents,ents.FindByClass("func_physbox"))
    local intersects = {}
    for _,ent in ipairs(allents) do
        ent = ent:GetPhysicsObject()
        if not IsValid(ent) then continue end
        if not ent:IsPenetrating() then continue end
        table.insert(intersects,ent)
    end
    local total = 0
    if svr == 1 then -- it is very dangerous and we must deal with it
        for _,ent in ipairs(intersects) do
            local realent = ent:GetEntity()
            if constraint.HasConstraints(realent) then
                for k,v in ipairs(constraint.GetAllConstrainedEntities(realent)) do
                    total = total + 1
                    ent:EnableMotion(false)
                end
            else total = total + 1 ent:EnableMotion(false) end
        end
        MsgC(p,m,Color(255,150,25),"Froze all intersecting and constrained props! (",total,")\n")
    end
    return intersects
end

local function Defuse(svr)
    local newspeed = speeds[svr]
    local svrc = HSVToColor(-svrcolor + svr*svrcolor,0.8,1)
    MsgC(p,m,msgcolor,(speed == 1 and "Lagging" or "Still lagging!").." (last tick required ",
        svrc,tostring(math.Round(t,2)).."ms",
        msgcolor,")! Slowing down to ",
        Color(120,200,255),tostring(newspeed).."\n")
    game.ConsoleCommand("phys_timescale "..tostring(newspeed).."\n")
    speed = newspeed
    -- find intersecting props
    local intersects = FindIntersects(svr)
    if #intersects == 0 then
        MsgC(p,m,msgcolor,"No intersecting entities detected!\n")
        net.Start("lagdetect_notify")
        net.WriteBool(true) -- slowdown message
        net.WriteEntity(game.GetWorld()) -- player with most props
        net.WriteUInt(0,10) -- how many props
        net.WriteUInt(0,7) -- what percent of all props
        net.WriteFloat(speed) -- current timescale
        net.WriteFloat(t) -- lag time
        net.WriteFloat(Cooldown(level,t)) -- delay time
        net.Broadcast()
        return
    end
    -- find owner of the most props
    local owners = {}
    for _,ent in ipairs(intersects) do
        ent = ent:GetEntity():CPPIGetOwner()
        owners[ent] = (owners[ent] and owners[ent] + 1 or 1)
    end
    local most = table.GetWinningKey(owners)
    local total = 0
    for ply,num in pairs(owners) do
        total = total + num
    end
    local percent = math.Round((owners[most]/total)*100,1)
    local c,n,s = Color(255,255,255),"World",":3" -- if it's the world, throw some placeholder stuff in
    if not most:IsWorld() then
        c,n,s = team.GetColor(most:Team()),most:GetName(),most:SteamID()
    end
    MsgC(p,m,Color(255,60,40),#intersects,
        msgcolor," possible intersecting ents, ",
        c,n,
        msgcolor," [",s,"] has the most (",
        HSVToColor(90-percent*0.9,0.8,1),owners[most],", ",percent,"%",
        msgcolor,")\n")
    net.Start("lagdetect_notify")
    net.WriteBool(true) -- slowdown message
    net.WriteEntity(most) -- player with most props
    net.WriteUInt(owners[most],10) -- how many props
    net.WriteUInt(math.Round(percent),7) -- what percent of all props
    net.WriteFloat(speed) -- current timescale
    net.WriteFloat(t) -- lag time
    net.WriteFloat(Cooldown(level,t)) -- delay time
    net.Broadcast()
end

local function CooldownDone() -- begin ramping timescale back up
    MsgC(p,m,Color(175,255,75),"Low lag detected, returning to normal speed...\n")
    timer.Create("recover",0.5,0,function()
        if speed == 1 then
            timer.Remove("recover")
            level = #speeds+1
            MsgC(p,m,Color(50,255,0),"No lag detected, timescale returned to normal!\n")
            net.Start("lagdetect_notify") net.WriteBool(false) net.Broadcast()
            return
        end
        speed = math.Round(math.Min(speed*1.33 + 0.01,1),2)
        level = level + 0.5
        game.ConsoleCommand("phys_timescale "..tostring(speed).."\n")
    end)
end
local t_avg_tbl = {}
local t_avg = 0
local function avg(tbl,div)
    local avg = 0
    for k,v in ipairs(tbl) do
        avg = avg + v
    end
    avg = avg/div
    return avg
end
hook.Add("Think","lagdetector",function()
    local mult = 0.7 + speed*0.3
    t_raw = physenv.GetLastSimulationTime()*1000
    t = math.Round((t_raw-0.001)/mult,2)
    --[[]
    table.insert(t_avg_tbl,t)
    if #t_avg_tbl > 33 then table.remove(t_avg_tbl,1) end
    t_avg = avg(t_avg_tbl,33)]]
    t_avg = t_avg + (t - t_avg) / 3

    for k,v in ipairs(threshold_start) do
        if t_avg > v or (k <= 2 and t > v) then
            if level == k then -- if we are already at this level
                if timer.Exists("cooldown") and timer.TimeLeft("cooldown") < 1.5 then -- if timer is about to expire
                    local ts = math.Round(cv:GetFloat(),2)
                    if ts != speed then
                        MsgC(p,m,"[WARN] ",Color(255,225,75),"Physics timescale was overridden! Readjusting...\n")
                        level = #speeds+1
                        timer.Remove("cooldown")
                        timer.Remove("recover")
                        return
                    end
                    MsgC(p,m,msgcolor,"Still lagging! (",HSVToColor(-svrcolor + k*svrcolor,0.8,1),tostring(t).."ms",msgcolor,") Maintaining timescale...\n")
                    if level == 1 then FindIntersects(1) end
                    timer.Adjust("cooldown",Cooldown(level,t))
                    timer.Start("cooldown")  -- refresh the cooldown
                end
                return
            end
            if level < k then return end
            level = k
            Defuse(level)
            timer.Create("cooldown",Cooldown(level,t),1,CooldownDone)
            timer.Remove("recover")
            return
        end
    end
end)