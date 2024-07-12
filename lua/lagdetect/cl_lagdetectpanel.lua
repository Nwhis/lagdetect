surface.CreateFont("LagDetect",{
    font = "Arial",
    size = 18,
    italic = true,
})

local PANEL = {}

function PANEL:Init()
    self:SetSize(174, 30)
    self:SetPos(ScrW() - self:GetWide(), ScrH() / 3 - self:GetTall())

    self:SetAlpha(0)
    self:SetScale(1)

    self.ScaleTween = self.Scale
end

function PANEL:SetScale(scale)
    self.Scale = scale
    self:Reveal(scale <= 0.999)
end

function PANEL:Reveal(goOut)
    if goOut then
        self:Show()
        self:AlphaTo(255, 0.25)
        timer.Remove("LagDetectPanel")

        return
    end

    self:AlphaTo(0, 0.5)
    timer.Create("LagDetectPanel", 0.25, 1, function()
        self.ScaleTween = self.Scale
        self:Hide()
    end)
end

function PANEL:Paint(w, h)
    self:Blur()

    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawRect(0, 0, w, h)

    self:PaintBar(0, h * 0.75, w, h)
end

local blur = Material("pp/blurscreen")
function PANEL:Blur()
    local x, y = self:LocalToScreen(0, 0)

    surface.SetDrawColor(255, 255, 255)
    surface.SetMaterial(blur)

    local clipping = DisableClipping(false)
    for i = 1, 5 do
        blur:SetFloat("$blur", (i / 4) * 4)
        blur:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(-x, -y, ScrW(), ScrH())
    end

    DisableClipping(clipping)
end

function PANEL:PaintBar(x, y, w, h)
    self.ScaleTween = (self.Scale + self.ScaleTween * 6) / 7

    local consider = math.min(math.max(1 - self.ScaleTween, 0), 1)
    local red = math.min(math.floor(consider * 512), 255)
    local green = math.min(math.floor((1 - consider) * 512), 255)

    local parsed = markup.Parse(string.format("<font=LagDetect>physics timescale: <color=%s,%s,0>%s</color></font>", red, green, math.Round(self.Scale, 2)), w)
    parsed:Draw(w / 2, 2, TEXT_ALIGN_CENTER)

    surface.SetDrawColor(red, green, 0)
    surface.DrawRect(x, y, w * self.ScaleTween, h)
end

vgui.Register("LagDetectPanel", PANEL, "DPanel")