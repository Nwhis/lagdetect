local directory = "lagdetect/"
local files = file.Find(directory .. "*", "LUA")
for _, v in ipairs(files) do
    if not string.EndsWith(v, ".lua") then continue end

    local prefix = string.lower(string.Left(v, 3))

    if SERVER and prefix == "sv_" then
        include(directory .. v)
    elseif prefix == "sh_" then
        if SERVER then
            AddCSLuaFile(directory .. v)
        end
        include(directory .. v)
    elseif prefix == "cl_" then
        if SERVER then
            AddCSLuaFile(directory .. v)
        elseif CLIENT then
            include(directory .. v)
        end
    end
end