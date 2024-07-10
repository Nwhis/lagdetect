if not bs then
    bs = {}
    function bs.Notify(msg,time) notification.AddLegacy(msg,0,time) end
end
local p,m = Color(255,100,25),"[LagDetect] "

MsgC(p,m,Color(255,255,255),"Client Loaded!\n")
net.Receive("lagdetect_notify",function()
    local console = net.ReadTable(true)
    MsgC(p,m,unpack(console))
    MsgC("\n")
    if not net.ReadBool() then return end
    local msg,time,color = net.ReadString(),net.ReadUInt(6),net.ReadVector():ToColor()
    bs.Notify(msg,time,color,true)
end)