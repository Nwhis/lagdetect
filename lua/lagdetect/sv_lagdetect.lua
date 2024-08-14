local threshold_start = { 150, 60, 30, 15 } -- maximum processing time before slowing down, sorted most>least severe; 15ms = ~1 tick
local speeds = { 0, 0.03, 0.3, 0.75 } -- corresponding timescales to use
local function Cooldown(level, ms) return
    math.Round(math.min(3 + (#speeds - level) + ms / 30, 20), 1)
end -- how long to stay at the slower speed before ramping back up

local svrcolor = 90 / #speeds

local speed = 1
local t_raw, t = 0, 0
local level = #speeds + 1
local msgcolor = color_white
local p, m = Color(255, 50, 25), "[LagDetect] "
local cv = GetConVar("phys_timescale")
local debug_mode = CreateConVar("lagdetect_debug", 0, FCVAR_NEVER_AS_STRING, "Enable debug printing for LagDetect", 0, 1)
local cv_enabled = CreateConVar("lagdetect_enabled",1,FCVAR_NEVER_AS_STRING,"Enable lag detection/mitigation",0,1)
local cv_minlag = CreateConVar("lagdetect_mintrigger",0,FCVAR_NEVER_AS_STRING,"Minimum lag amount to trigger (in ms). Set this higher to lower sensitivity",0,10000)

util.AddNetworkString("lagdetect_notify")

util.AddNetworkString("lagdetect_scale")
cvars.AddChangeCallback("phys_timescale", function(_, oldScale, scale)
    oldScale, scale = tonumber(oldScale), tonumber(scale)
    if oldScale >= 0.999 and scale >= 0.999 then return end
    if math.abs(oldScale - scale) <= 0.0001 then return end

    net.Start("lagdetect_scale")
        net.WriteBool(false)
        net.WriteFloat(scale)
    net.Broadcast()
end)

--broadcastType: true for admin only, false for serverside only, nil for all players
local function Notify(broadcastType, ...)
    local textTable = {...}
    local notify = true

    local skip, notify1, broadcastType1, textTable1 = hook.Run("lagdetect_notify_server", notify, broadcastType, textTable)
    if skip == false then return end
    if notify1 ~= nil then notify = notify1 end
    if textTable1 then textTable = textTable1 end
    if broadcastType1 ~= nil then broadcastType = broadcastType1 end

    MsgC(p, m, unpack(textTable))
    MsgN("")

    if broadcastType == false then return end

    net.Start("lagdetect_notify")
        net.WriteTable(textTable, true)
        net.WriteBool(notify)

    if broadcastType == true then
        local tbl = {}
        for _, ply in player.Iterator() do
            if ply:IsAdmin() then table.insert(tbl, ply) end
        end
        net.Send(tbl)
    else
        net.Broadcast()
    end
end

local function ChangeTimeScale(scale, ms, svr)
    local svrc = HSVToColor(-svrcolor + (svr or 0) * svrcolor, 0.8, 1)

    if math.abs(cv:GetFloat() - scale) <= 0.001 then
        if scale == 1 then
            Notify(false, msgcolor, "phys_timescale returned to ", svrc, 1)

            return
        end

        if debug_mode:GetBool() then
            local tick = {}
            if ms then
                tick = { msgcolor, " (last tick: ", ms, " ms) (cooldown: ", Cooldown(level, ms), " s)" }
            end

            Notify(false, msgcolor, "[dbg] maintaining phys_timescale of ", svrc, tostring(scale), unpack(tick))
        end

        return
    end

    local tick = {}
    if ms then
        tick = { msgcolor, " (last tick: ", ms, " ms)" }

        if debug_mode:GetBool() then
            table.Add(tick, { " (cooldown: ", Cooldown(level, ms), " s)" })
        end
    end

    Notify(false, msgcolor, "Setting phys_timescale to ", svrc, tostring(scale), unpack(tick))

    game.ConsoleCommand("phys_timescale " .. tostring(scale) .. "\n")
    prev_scale = scale
end

local function FindIntersects(svr)
    local allents = ents.FindByClass("prop_*")
    table.Add(allents, ents.FindByClass("func_physbox"))

    local intersects = {}
    for _, ent in ipairs(allents) do
        ent = ent:GetPhysicsObject()

        if not IsValid(ent) then continue end
        if not ent:IsPenetrating() then continue end

        table.insert(intersects, ent)
    end

    -- svr = it is very dangerous and we must deal with it
    if svr ~= 1 then
        return intersects
    end

    local total = 0
    for _, ent in ipairs(intersects) do
        local realent = ent:GetEntity()
        if constraint.HasConstraints(realent) then
            for k, v in ipairs(constraint.GetAllConstrainedEntities(realent)) do
                total = total + 1
                ent:EnableMotion(false)
            end
        else
            total = total + 1
            ent:EnableMotion(false)
        end
    end

    Notify(true, Color(255, 150, 25), "Severe lag!! Froze all intersecting and constrained props (", total, ")")

    return intersects
end

local function Defuse(svr)
    local newspeed = speeds[svr]
    ChangeTimeScale(newspeed, t, svr)
    speed = newspeed

    -- find intersecting props
    local intersects = FindIntersects(svr)
    if #intersects == 0 then
        -- not having the possible intersects notification implies zero intersects
        if debug_mode:GetBool() then
            Notify(false, msgcolor, "[dbg] Tried defusing without intersects", svr and " (severe)" or "")
        end

        return
    end

    -- find owner of the most props
    local owners = {}
    for _, ent in ipairs(intersects) do
        ent = ent:GetEntity():CPPIGetOwner()
        if IsValid(ent) then
            owners[ent] = (owners[ent] or 0) + 1
        end
    end

    local most = table.GetWinningKey(owners)
    local total = 0
    for ply, num in pairs(owners) do
        total = total + num
    end

    local percent = math.Round((owners[most] / total) * 100, 1)
    local c, n, s = color_white, "World", ":3" -- if it's the world, throw some placeholder stuff in
    if not most:IsWorld() then
        c, n, s = team.GetColor(most:Team()), most:GetName(), most:SteamID()
    end

    Notify(true, Color(255, 60, 40), #intersects, msgcolor, " possible intersecting ents, ", c,
            n, msgcolor, " [", s, "] has the most (", HSVToColor(90 - percent * 0.9, 0.8, 1),
            owners[most], ", ", percent, "%", msgcolor, ")")
end

local function CooldownDone() -- begin ramping timescale back up
    timer.Create("recover", 0.5, 0, function()
        if speed == 1 then
            timer.Remove("recover")
            level = #speeds + 1
            ChangeTimeScale(1)

            return
        end

        speed = math.Round(math.min(speed * 1.33 + 0.01, 1), 2)
        level = level + 0.5

        game.ConsoleCommand("phys_timescale " .. tostring(speed) .. "\n")
    end)
end

game.ConsoleCommand("phys_timescale 1\n")

--[[
local t_avg_tbl = {}
local function avg(tbl, div)
    local avg = 0
    for k,v in ipairs(tbl) do
        avg = avg + v
    end
    avg = avg / div
    return avg
end
--]]

local lastSendTick = CurTime()
local t_avg = 0
hook.Add("Think", "lagdetector", function()
    if not cv_enabled:GetBool() then return end
    local mult = 0.6 + speed * 0.4
    t_raw = physenv.GetLastSimulationTime() * 1000
    t = math.Round((t_raw - 0.001) / mult, 2)
    --[[
    table.insert(t_avg_tbl,t)
    if #t_avg_tbl > 33 then table.remove(t_avg_tbl,1) end
    t_avg = avg(t_avg_tbl,33)
    --]]
    t_avg = t_avg + (t - t_avg) / 6

    if timer.Exists("cooldown") and CurTime() - lastSendTick > 1 then
        net.Start("lagdetect_scale")
            net.WriteBool(true)
            net.WriteFloat(t)
        net.Broadcast()

        lastSendTick = CurTime()
    end

    if t < cv_minlag:GetFloat() then return end -- if the lag is less than the threshold then just ignore it

    for k, v in ipairs(threshold_start) do
        if t_avg <= v and (k > 2 or t <= v) then
            continue
        end

        if level > k then
            level = k

            Defuse(level)
            timer.Create("cooldown", Cooldown(level, t), 1, CooldownDone)
            timer.Remove("recover")

            return
        end

        if level < k then return end

        if timer.Exists("cooldown") and timer.TimeLeft("cooldown") < 1.5 then -- if timer is about to expire
            local ts = math.Round(cv:GetFloat(), 2)

            if ts ~= speed then
                Notify(true, "[WARN] ", Color(255, 225, 75), "Physics timescale was overridden!")

                level = #speeds + 1

                timer.Remove("cooldown")
                timer.Remove("recover")

                return
            end

            if level == 1 then FindIntersects(1) end

            timer.Adjust("cooldown", Cooldown(level, t))
            timer.Start("cooldown") -- refresh the cooldown

            --for displaying the timescale in debug
            ChangeTimeScale(ts, t)
        end

        return
    end
end)

local cached_sizes = {}
local function GetSmallestSize(ent)
    if not IsValid(ent:GetPhysicsObject()) then return 0 end

    local cached = cached_sizes[ent:GetModel()]
    if cached then return cached end

    local ra, rb = ent:GetPhysicsObject():GetAABB()
    local r = math.min(rb.x - ra.x, rb.y - ra.y, rb.z - ra.z) / 2

    if table.Count(cached_sizes) > 62 then cached_sizes = {} end
    cached_sizes[ent:GetModel()] = r

    return r
end

local function GetOverlap(ent1, ent2)
    if not IsValid(ent1) or not IsValid(ent2) then return 0 end
    if not IsValid(ent1:GetPhysicsObject()) or not IsValid(ent2:GetPhysicsObject()) then return 0 end

    local p1 = ent1:WorldSpaceCenter()
    local p2 = ent2:WorldSpaceCenter()
    local dist = p1:Distance(p2)

    local r1 = GetSmallestSize(ent1)
    local r2 = GetSmallestSize(ent2)
    local overlap = 1 - (dist / math.min(r1, r2) / 2)

    return math.Clamp(overlap, 0, 1)
end

local monitor_props = CreateConVar("lagdetect_monitor_propspawns", 1, FCVAR_NEVER_AS_STRING, "Enable prop spawn monitoring", 0, 1)
local overlaps = {} -- tbl of players and how much overlap their latest prop spawns have

hook.Add("PlayerSpawnedProp", "lagdetect_propspawn", function(ply, _, ent)
    if not monitor_props:GetBool() then return end
    if not IsValid(ent) then return end
    if not IsValid(ent:GetPhysicsObject()) then return end
    timer.Simple(0,function()
        if not IsValid(ent) then return end
        if not IsValid(ent:GetPhysicsObject()) then return end
        if not ent:GetPhysicsObject():IsMotionEnabled() then return end

        if not overlaps[ply] then overlaps[ply] = {overlap = 0, notify = 0} end

        local overlap = 0
        local count = 0
        for _, v in ipairs(ents.FindInSphere(ent:GetPos(), GetSmallestSize(ent) * 2)) do
            if not IsValid(ent:GetPhysicsObject()) then continue end
            if not string.StartsWith(v:GetClass(),"prop") then continue end

            count = count + 1
            if ent == v then continue end

            overlap = overlap + GetOverlap(ent, v)
        end

        overlaps[ply].overlap = math.max(overlap, overlaps[ply].overlap - 1)
        local overlap_n = math.ceil(math.max((overlap / 3) - 0.5, 0) ^ 0.8)
        if overlap_n > overlaps[ply].notify then
            Notify(true, team.GetColor(ply:Team()), ply:GetName(), msgcolor, " is spawning a lot of intersecting props! (",
                    HSVToColor(math.max(0, 75 - count * 3), 0.8, 1), count, msgcolor, " props, ",
                    HSVToColor(math.max(0, 90 - overlap / (count - 1) * 90), 0.8, 1), math.Round(overlap, 2), msgcolor, " total overlap)")
        end
        overlaps[ply].notify = overlap_n
    end)
end)

concommand.Add("lagdetect_debug_dump", function(ply, str, args, argstr)
    local overlaps_str = ""
    if argstr == "v" then
        overlaps_str = "\nplayer dump:"
        for k, v in pairs(overlaps) do
            overlaps_str = overlaps_str .. "\n[" .. tostring(k) .. "]:\n"
            for l, b in pairs(v) do
                overlaps_str = overlaps_str .. "\n    [" .. l .. "] = " .. tostring(b)
            end
        end
    end

    net.Start("lagdetect_notify")
    net.WriteTable({ msgcolor,"Debug info:",
        "\ncurrent ms (instant) : ", t,
        "\ncurrent ms (smoothed): ", math.Round(t_avg, 3),
        overlaps_str }, true)
    net.WriteBool(false)
    net.Send(ply)
end)
