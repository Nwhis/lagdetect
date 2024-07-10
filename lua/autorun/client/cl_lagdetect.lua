local msgcolor = Color(255,255,255)
local p,m = Color(255,100,25),"[LagDetect] "

MsgC(p,m,Color(255,255,255),"Client Loaded!\n")
net.Receive("lagdetect_notify",function()
    local islag = net.ReadBool()
    if not islag then
        --notification.AddLegacy("[LagDetect] Physics timescale restored!",0,3)
        bs.Notify("[LagDetect] Physics timescale restored!",4,Color(50,255,0),true)
        MsgC(p,m,Color(50,255,0),"No lag detected, timescale returned to normal!\n")
        return
    end
    local ply = net.ReadEntity()
    local num = net.ReadUInt(10)
    local percent = net.ReadUInt(7)
    local speed = math.Round(net.ReadFloat(),2)
    local t = math.Round(net.ReadFloat(),2)
    local cd = math.Round(net.ReadFloat(),1)

    --notification.AddLegacy("[LagDetect] Physics timescale set to "..tostring(math.Round(speed,2)),0,6)
    bs.Notify("[LagDetect] Physics timescale set to "..tostring(math.Round(speed,2)),6,Color(255,200,0),true)
    local svrc = HSVToColor(math.Max(90 - t*0.8,0),0.8,1)
    MsgC(p,m,msgcolor,"Physics lag detected (last tick required ",
        svrc,tostring(t).."ms",
        msgcolor,")! Slowing physics to ",
        Color(120,200,255),tostring(speed).."x",
        msgcolor," and waiting ",cd,"s\n")
    
    if not LocalPlayer():IsAdmin() then return end

    if speed == 0 then
        bs.Notify("[LagDetect] Severe lag!! Freezing all intersecting props.",6,Color(255,100,0),true)
        MsgC(p,m,Color(255,100,0),"Severe lag!!",msgcolor," Freezing all intersecting props.\n")
    end
    local c,n,s = Color(255,255,255),"World",":3"
    if not ply:IsWorld() then
        c,n,s = team.GetColor(ply:Team()),ply:GetName(),ply:SteamID()
    end

    --notification.AddLegacy("[LagDetect] "..n.." has "..tostring(num).." intersecting props ("..tostring(percent).."%)",0,8)
    bs.Notify("[LagDetect] "..n.." has "..tostring(num).." intersecting props ("..tostring(percent).."%)",10,Color(255,125,0),true)
    MsgC(p,m,c,n,
        msgcolor," [",s,"] has ",
        Color(255,60,40),num,
        msgcolor," possible intersecting ents (",
        HSVToColor(90-percent*0.9,0.8,1),percent,"%",
        msgcolor,")\n")
end)