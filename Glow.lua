-- Glow.lua
-- Glow autonome de type "proc" (pulsation), sans librairie externe.
local ADDON, ns = ...
local Glow = {}
ns.Glow = Glow

-- Cree un glow attache a "parent" (le frame de l'icone).
-- Le glow deborde legerement de l'icone pour un rendu "halo".
-- (Re)calcule les ancres du halo a partir de la largeur ACTUELLE du parent.
-- A rappeler apres un redimensionnement de l'icone, sinon le debord reste fige
-- a la valeur calculee a la creation.
function Glow.Resize(g)
    local p = g:GetParent()
    if not p then return end
    local over = p:GetWidth() * 0.45
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", p, "TOPLEFT", -over, over)
    g:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", over, -over)
end

function Glow.Create(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetFrameLevel(parent:GetFrameLevel() + 4)

    -- Le halo est plus grand que l'icone (debord = 45% de la largeur).
    Glow.Resize(g)

    local tex = g:CreateTexture(nil, "OVERLAY")
    tex:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    -- On selectionne la portion "anneau" de la texture proc Blizzard.
    tex:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    tex:SetAllPoints(g)
    tex:SetBlendMode("ADD")
    g.tex = tex

    -- Animation de pulsation (alpha + leger zoom), en boucle BOUNCE.
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")

    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.55)
    a:SetSmoothing("IN_OUT")

    local s = ag:CreateAnimation("Scale")
    s:SetScaleFrom(1, 1)
    s:SetScaleTo(1.12, 1.12)
    s:SetDuration(0.55)
    s:SetSmoothing("IN_OUT")
    s:SetOrigin("CENTER", 0, 0)

    g.anim = ag
    -- Le glow tourne en permanence ; sa visibilite est pilotee par l'alpha
    -- du frame parent (lui-meme commande par la Curve / valeur secrete).
    g:Show()
    ag:Play()
    return g
end

function Glow.Show(g)
    if not g:IsShown() then
        g:Show()
        g.anim:Play()
    end
end

function Glow.Hide(g)
    if g:IsShown() then
        g.anim:Stop()
        g:Hide()
    end
end
