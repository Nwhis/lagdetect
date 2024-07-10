local msgcolor = Color(255,255,255)
local p,m = Color(255,100,25),"[LagDetect] "

MsgC(p,m,Color(255,255,255),"Client Loaded!\n")
net.Receive("lagdetect_notify",function()
    local ply = net.ReadEntity()
    if not IsValid(ply) and not ply:IsWorld() then
        notification.AddLegacy("[LagDetect] Physics timescale restored!",0,3)
        MsgC(p,m,Color(50,255,0),"No lag detected, timescale returned to normal!\n")
        return
    end
    local num = net.ReadUInt(10)
    local percent = net.ReadUInt(7)
    local speed = math.Round(net.ReadFloat(),2)
    local t = math.Round(net.ReadFloat(),2)

    notification.AddLegacy("[LagDetect] Physics timescale set to "..tostring(math.Round(speed,2)),0,6)
    local svrc = HSVToColor(math.Max(90 - t*0.8,0),0.8,1)
    MsgC(p,m,msgcolor,"Physics lag detected (last tick required ",
        svrc,tostring(t).."ms",
        msgcolor,")! Slowing physics to ",
        Color(120,200,255),tostring(speed).."x\n")
    
    if not LocalPlayer():IsAdmin() then return end

    local c,n,s = Color(255,255,255),"World",":3"
    if not ply:IsWorld() then
        c,n,s = team.GetColor(ply:Team()),ply:GetName(),ply:SteamID()
    end

    notification.AddLegacy("[LagDetect] "..n.." has "..tostring(num).." intersecting props ("..tostring(percent).."%)",0,8)
    MsgC(p,m,c,n,
        msgcolor," [",s,"] has ",
        Color(255,60,40),num,
        msgcolor," possible intersecting ents (",
        HSVToColor(90-percent*0.9,0.8,1),percent,"%",
        msgcolor,")\n")
end)