local function Notify(msg)
    if hook.Run("LagDetect_Notify", msg) == false then return end
    notification.AddLegacy(msg, 0, 5)
end

local p, m = Color(255, 50, 25), "[LagDetect] "
net.Receive("lagdetect_notify",function()
    local textTable = net.ReadTable(true)
    local notify = net.ReadBool()

    local skip, notify1, textTable1 = hook.Run("lagdetect_notify_client", notify, textTable)
    if skip == false then return end
    if notify1 ~= nil then notify = notify1 end
    if textTable1 then textTable = textTable1 end

    MsgC(p, m, unpack(textTable))
    MsgC("\n")

    if notify == false then return end

    local text = { m }
    for _, v in ipairs(textTable) do
        if type(v) == "table" then
            continue
        end

        table.insert(text, tostring(v))
    end

    Notify(table.concat(text))
end)

local lagPanel
net.Receive("lagdetect_scale", function()
    if not IsValid(lagPanel) then
        lagPanel = vgui.Create("LagDetectPanel")
    end

    if net.ReadBool() then
        lagPanel:SetLastTick(net.ReadFloat())

        return
    end

    lagPanel:SetScale(net.ReadFloat())
end)
