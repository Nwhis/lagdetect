local threshold_start = {150,60,30,15} -- maximum processing time before slowing down, sorted most>least severe; 15ms = ~1 tick
local speeds = {0,0.03,0.3,0.75} -- corresponding timescales to use
local function Cooldown(level,ms) return math.Round(math.min(3+(#speeds-level) + ms/30,20),1) end -- how long to stay at the slower speed before ramping back up

local svrcolor = 90/#speeds

local speed = 1
local cooldown = 0
local t_raw,t = 0,0
local level = #speeds+1
local msgcolor = Color(255,255,255)
local p,m = Color(255,50,25),"[LagDetect] "
local cv = GetConVar("phys_timescale")
util.AddNetworkString("lagdetect_notify")

local function GetAdmins()
    local tbl = {}
    for _,ply in player.Iterator() do
        if ply:IsAdmin() then table.insert(tbl,ply) end
    end
    return tbl
end
local function Notify(adminonly, console, notif)
    net.Start("lagdetect_notify")
    net.WriteTable(console,true)
    net.WriteBool(notif and true)
    if notif then
        net.WriteString(notif[1])
        net.WriteUInt(notif[2],6)
        net.WriteVector(notif[3]:ToVector())
    end
    if adminonly then net.Send(GetAdmins()) else net.Broadcast() end
    MsgC(p,m,unpack(console))
    MsgC("\n")
end
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
        Notify(true,{Color(255,150,25),"Severe lag!! Froze all intersecting and constrained props (",total,")"},
        {m.."Severe lag!! Froze all intersecting and constrained props ("..tostring(total)..")",8,Color(255,150,0)})
    end
    return intersects
end

local function Defuse(svr)
    local newspeed = speeds[svr]
    local svrc = HSVToColor(-svrcolor + svr*svrcolor,0.8,1)
    Notify(false,{msgcolor,(speed == 1 and "Lagging" or "Still lagging!").." (last tick required ",
        svrc,tostring(math.Round(t,2)).."ms",
        msgcolor,")! Slowing down to ",
        Color(120,200,255),tostring(newspeed),
        msgcolor,", and waiting ",Cooldown(level,t),"s"},
        {m.."Physics timescale set to "..tostring(newspeed),Cooldown(level,t),Color(255,200,0)})
    game.ConsoleCommand("phys_timescale "..tostring(newspeed).."\n")
    speed = newspeed
    -- find intersecting props
    local intersects = FindIntersects(svr)
    if #intersects == 0 then Notify(true,{msgcolor,"No intersecting entities detected!"}) return end
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
    Notify(true,{Color(255,60,40),#intersects,
        msgcolor," possible intersecting ents, ",
        c,n,
        msgcolor," [",s,"] has the most (",
        HSVToColor(90-percent*0.9,0.8,1),owners[most],", ",percent,"%",
        msgcolor,")"},
        {m..n.." has "..tostring(owners[most]).." intersecting props ("..tostring(percent).."%)",10,Color(255,125,0)}
    )
end

local function CooldownDone() -- begin ramping timescale back up
    Notify(false,{Color(175,255,75),"Low lag detected, returning to normal speed..."},{"Restoring physics timescale...",3,Color(175,255,75)})
    timer.Create("recover",0.5,0,function()
        if speed == 1 then
            timer.Remove("recover")
            level = #speeds+1
            Notify(false,{Color(50,255,0),"No lag detected, timescale returned to normal!"},
                {m.."Physics timescale restored!",4,Color(50,255,0)})
            return
        end
        speed = math.Round(math.min(speed*1.33 + 0.01,1),2)
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

Notify(false,{msgcolor,"Server Loaded!"})
game.ConsoleCommand("phys_timescale 1\n")

hook.Add("Think","lagdetector",function()
    local mult = 0.6 + speed*0.4
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
                        Notify(true,{"[WARN] ",Color(255,225,75),"Physics timescale was overridden! Readjusting..."})
                        level = #speeds+1
                        timer.Remove("cooldown")
                        timer.Remove("recover")
                        return
                    end
                    Notify(true,{
                        msgcolor,"Still lagging! (",HSVToColor(-svrcolor + k*svrcolor,0.8,1),tostring(t).."ms",
                        msgcolor,") Maintaining timescale for ",Cooldown(level,t),"s..."},
                        {m.."Maintaining timescale...",Cooldown(level,t),Color(255,200,0)})
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
local cached_sizes = {}
local function GetSmallestSize(ent)
    local cached = cached_sizes[ent:GetModel()]
    if cached then return cached end
    local ra,rb = ent:GetPhysicsObject():GetAABB()
    local r = math.min(rb.x - ra.x,rb.y - ra.y, rb.z - ra.z)/2
    if table.Count(cached_sizes) > 62 then cached_sizes = {} end
    cached_sizes[ent:GetModel()] = r
    return r
end
    
local function GetOverlap(ent1,ent2)
    local p1 = ent1:WorldSpaceCenter()
    local p2 = ent2:WorldSpaceCenter()
    local dist = p1:Distance(p2)
    local r1 = GetSmallestSize(ent1)
    local r2 = GetSmallestSize(ent2)
    local overlap = 1 - (dist/math.min(r1, r2)/2)
    return math.Clamp(overlap,0,1)
end

local overlaps = {} -- tbl of players and how much overlap their latest prop spawns have

hook.Add("PlayerSpawnedProp","lagdetect_propspawn",function(ply,_,ent)
    if not IsValid(ent) then return end
    if not IsValid(ent:GetPhysicsObject()) then return end
    if not overlaps[ply] then overlaps[ply] = {overlap = 0, notify = 0} end
    local overlap = 0
    local count = 0
    for _,v in ipairs(ents.FindInSphere(ent:GetPos(),GetSmallestSize(ent)*2)) do
        if ent == v then continue end
        if not string.StartsWith(v:GetClass(),"prop") then continue end
        overlap = overlap + GetOverlap(ent,v)
        count = count + 1
    end
    overlaps[ply].overlap = math.max(overlap,overlaps[ply].overlap-1)

    local overlap_n = math.ceil(math.max((overlap/3)-0.85,0)^0.9)
    if overlap_n > overlaps[ply].notify then
        Notify(true,{
            team.GetColor(ply:Team()),ply:GetName(),
            msgcolor," is spawning a lot of intersecting props! (",
            HSVToColor(math.max(0,75 - count*3),0.8,1),count,
            msgcolor," props, ",
            HSVToColor(math.max(0,75 - overlap*9),0.8,1),math.Round(overlap,2),
            msgcolor," total overlap)"},
            {m..ply:GetName().." is spawning a lot of intersecting props! ("..tostring(count)..")",
            math.min(4+overlap_n,12),Color(255,200,0)
        })
    end
    overlaps[ply].notify = overlap_n
end)