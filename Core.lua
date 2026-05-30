-- Core.lua
-- Moteur XpAura (WoW 12.0.5 / Midnight).
-- En combat, vie et puissance du joueur sont des "valeurs secretes" : on ne peut
-- ni les comparer ni faire d'arithmetique dessus. On passe donc le pourcentage
-- (UnitPowerPercent / UnitHealthPercent) dans une Curve (C_CurveUtil) qui le mappe
-- vers un alpha 0/1, puis on l'applique avec frame:SetAlpha() (qui accepte les secrets).
local ADDON, ns = ...
local L = ns.L

ns.rules  = {}   -- regles enregistrees (toutes classes)
ns.frames = {}   -- frames crees pour la classe du joueur

--------------------------------------------------------------------------------
-- API locale
--------------------------------------------------------------------------------
local issecretvalue    = issecretvalue or function() return false end
local CreateCurve      = C_CurveUtil and C_CurveUtil.CreateCurve
local UnitPowerPercent  = UnitPowerPercent
local UnitHealthPercent = UnitHealthPercent
local GetSpellTexture   = (C_Spell and C_Spell.GetSpellTexture)  or _G.GetSpellTexture
local GetSpellCooldown  = (C_Spell and C_Spell.GetSpellCooldown)
local IsSpellUsable     = (C_Spell and C_Spell.IsSpellUsable)
-- Objets "Duration" : seule voie combat-safe pour exploiter cooldown / charges.
local GetSpellCooldownDuration = (C_Spell and C_Spell.GetSpellCooldownDuration)
local GetSpellChargeDuration   = (C_Spell and C_Spell.GetSpellChargeDuration)
-- Convertit un booleen secret en valeur (secret-safe) : (boolSecret, valeurSiVrai, valeurSiFaux).
local EvalBoolToValue = (C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean)

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffXpAura|r: " .. msg)
end

--------------------------------------------------------------------------------
-- Helpers NON-secrets (utilisables dans un check() optionnel, hors vie/puissance)
--------------------------------------------------------------------------------

-- true si le sort n'est pas en cooldown.
function ns.SpellReady(spellID)
    if not GetSpellCooldown then return true end
    local cd = GetSpellCooldown(spellID)
    if type(cd) == "table" then
        if not cd.duration or cd.duration == 0 then return true end
        return (cd.startTime + cd.duration - GetTime()) <= 0
    end
    return true
end

-- true si le sort est utilisable (connu + pret).
function ns.SpellUsable(spellID)
    if not IsSpellUsable then return true end
    return IsSpellUsable(spellID) and true or false
end

--------------------------------------------------------------------------------
-- Enregistrement des regles
--------------------------------------------------------------------------------
-- Regle a SEUIL (vie / puissance) -- secret-safe :
--   {
--     class     = "DEATHKNIGHT",            -- optionnel
--     spellID   = 49998,                    -- icone
--     label     = "...",
--     source    = "power" | "health",
--     powerType = Enum.PowerType.RunicPower, -- si source == "power"
--     op        = ">" | "<",                 -- au-dessus / en-dessous du seuil
--     value     = 75,                        -- seuil en valeur ABSOLUE, OU
--     pct       = 50,                        -- seuil en POURCENTAGE (0-100)
--   }
--
-- Regle a FONCTION (conditions NON secretes : cooldown, sort utilisable, ...) :
--   {
--     class = "...", spellID = ..., label = "...",
--     check = function() return ns.SpellReady(49998) end,   -- ne PAS lire vie/puissance ici
--   }
function ns:AddRule(rule)
    table.insert(ns.rules, rule)
end

--------------------------------------------------------------------------------
-- SavedVariables
--------------------------------------------------------------------------------
local function GetDB()
    -- Stockage PAR PERSONNAGE : chaque perso a ses propres regles/positions.
    XpAuraCharDB = XpAuraCharDB or {}
    local db = XpAuraCharDB
    if db.locked == nil then db.locked = true end
    if db.combatOnly == nil then db.combatOnly = false end
    db.positions = db.positions or {}
    db.sizes     = db.sizes or {}      -- taille par icone : db.sizes[posKey] = px
    db.userRules = db.userRules or {}  -- regles creees via le menu (propres a ce perso)
    db.nextId    = db.nextId or 1
    -- Grille d'aide au placement (mode deverrouille uniquement).
    if db.gridShow == nil then db.gridShow = true end
    db.gridSize = db.gridSize or 20    -- pas de la grille (px)
    if db.gridSnap == nil then db.gridSnap = false end

    -- Migration unique : recupere les anciennes regles account-wide vers ce perso.
    if not db.migrated then
        db.migrated = true
        if type(XpAuraDB) == "table" and type(XpAuraDB.userRules) == "table"
           and #XpAuraDB.userRules > 0 and #db.userRules == 0 then
            for _, r in ipairs(XpAuraDB.userRules) do
                local t = {}; for k, v in pairs(r) do t[k] = v end
                table.insert(db.userRules, t)
            end
            if type(XpAuraDB.positions) == "table" then
                for k, v in pairs(XpAuraDB.positions) do db.positions[k] = v end
            end
            if XpAuraDB.nextId and XpAuraDB.nextId > db.nextId then db.nextId = XpAuraDB.nextId end
        end
    end
    return db
end
ns.GetDB = GetDB

--------------------------------------------------------------------------------
-- Courbes de seuil  (mappe un pourcentage 0-1 vers alpha 0 ou 1)
--------------------------------------------------------------------------------
local EPS = 0.0001

local function BuildThresholdCurve(op, fraction)
    if not CreateCurve then return nil end
    fraction = math.max(0, math.min(1, fraction or 0.5))
    local above = (op == ">" or op == ">=")
    local lo = above and 0 or 1   -- alpha SOUS le seuil
    local hi = above and 1 or 0   -- alpha AU-DESSUS du seuil
    local c = CreateCurve()
    if fraction <= EPS then
        c:AddPoint(0, hi); c:AddPoint(1, hi)
    elseif fraction >= 1 - EPS then
        c:AddPoint(0, lo); c:AddPoint(1, lo)
    else
        c:AddPoint(0, lo)
        c:AddPoint(fraction - EPS, lo)
        c:AddPoint(fraction, hi)
        c:AddPoint(1, hi)
    end
    return c
end

-- Courbe (en SECONDES) pour "glow quand pret" qui IGNORE le GCD :
--   restant <= 1.6s (GCD) -> alpha 1 (on considere le sort "pret")
--   restant > 1.6s (vraie recharge) -> alpha 0 (cache)
-- Evaluee via duo:EvaluateRemainingDuration(curve, default).
local readyCurve
local function GetReadyCurve()
    if readyCurve ~= nil then return readyCurve or nil end
    if not CreateCurve then readyCurve = false; return nil end
    local c = CreateCurve()
    if c.SetType and Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Step) end
    c:AddPoint(0, 1)
    c:AddPoint(1.6, 1)
    c:AddPoint(1.601, 0)
    readyCurve = c
    return c
end

-- Courbe inverse de la precedente : alpha 1 quand le sort est EN RECHARGE (>1.6s),
-- 0 quand il est pret (ou pendant le GCD). Pour la condition "sort PAS pret".
local notReadyCurve
local function GetNotReadyCurve()
    if notReadyCurve ~= nil then return notReadyCurve or nil end
    if not CreateCurve then notReadyCurve = false; return nil end
    local c = CreateCurve()
    if c.SetType and Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Step) end
    c:AddPoint(0, 0)
    c:AddPoint(1.6, 0)
    c:AddPoint(1.601, 1)
    notReadyCurve = c
    return c
end

-- Fraction (0-1) correspondant au seuil de la regle.
-- UnitPowerMax / UnitHealthMax ne sont PAS secrets pour le joueur.
local function RuleFraction(rule)
    if rule.pct then return rule.pct / 100 end
    if rule.value then
        local max
        if rule.source == "health" then
            max = UnitHealthMax("player")
        else
            max = UnitPowerMax("player", rule.powerType)
        end
        if not max or max == 0 then return 0.5 end
        local v = rule.value
        -- Ressource discrete a petit maximum (pts sacres, combo, fragments...) :
        -- on vise le MILIEU entre deux paliers entiers pour des seuils NETS.
        -- Sinon "< 5" sur un max de 5 -> 5/5=1.0 -> bord casse (toujours visible).
        if rule.source ~= "health" and max <= 10 then
            local above = (rule.op == ">" or rule.op == ">=")
            v = above and (v + 0.5) or (v - 0.5)
        end
        return v / max
    end
    return 0.5
end

-- Une regle peut avoir plusieurs conditions (rule.conditions) combinees en OU/ET.
-- Sinon, la regle elle-meme est l'unique condition (retro-compat).
local function GetConditions(rule)
    if rule.conditions and #rule.conditions > 0 then
        return rule.conditions, (rule.combine == "AND") and "AND" or "OR"
    end
    return { rule }, "OR"
end

local GetPlayerAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
local GetAuraByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
local GetRuneCooldown = _G.GetRuneCooldown  -- runes DK : non secret en combat

-- NB : le NOM d'une aura est une "valeur secrete" en combat -> on ne peut PAS comparer
-- les noms (toute operation sur le nom plante). On suit donc les auras par spellID.

-- Comparaison de nombres "normaux" (jamais sur un secret -> appelee sous pcall).
local function Compare(a, op, b)
    if op == ">"  then return a > b
    elseif op == "<"  then return a < b
    elseif op == ">=" then return a >= b
    elseif op == "<=" then return a <= b
    elseif op == "==" then return a == b
    end
    return false
end

-- Enveloppe une fonction booleenne -> eval renvoyant alpha 0/1, protege par pcall.
-- Si la fonction touche une valeur secrete, l'erreur est avalee -> 0 (icone masquee).
local function BoolEval(fn)
    return function()
        local ok, res = pcall(fn)
        if ok and res then return 1 else return 0 end
    end
end

-- Construit eval() -> alpha (0/1). nil si indisponible.
-- defaultSpellID : sort de l'icone, utilise par les conditions "spell" sans watchSpellID.
local function BuildConditionEval(cond, defaultSpellID)
    -- Aura (buff/debuff) sur le joueur, suivie par spellID.
    if cond.kind == "aura" then
        local id   = cond.watchSpellID
        local mode = cond.mode or "present"
        local op   = cond.op or ">="
        local val  = cond.value or 1
        return BoolEval(function()
            local aura
            if id and GetPlayerAura then
                aura = GetPlayerAura(id)
            end
            if mode == "present" then return aura ~= nil end
            if mode == "absent"  then return aura == nil end
            if not aura then return false end
            if mode == "stacks" then
                return Compare(aura.applications or 0, op, val)
            elseif mode == "time" then
                local exp = aura.expirationTime or 0
                if exp == 0 then return false end          -- aura permanente
                return Compare(exp - GetTime(), op, val)
            end
            return false
        end)
    end

    -- Runes disponibles (DK) : nombre de runes pretes ⋛ valeur. Non secret en combat.
    if cond.kind == "runes" then
        local op  = cond.op or ">="
        local val = cond.value or 2
        return BoolEval(function()
            if not GetRuneCooldown then return false end
            local n = 0
            for i = 1, 6 do
                local _, _, ready = GetRuneCooldown(i)
                if ready then n = n + 1 end
            end
            return Compare(n, op, val)
        end)
    end

    -- Disponibilite d'un sort (combat-safe) : meme voie "objet Duration" que le mode
    -- cooldown. Suit le sort de l'icone (defaultSpellID) sauf si cond.watchSpellID.
    if cond.kind == "spell" then
        local sid  = cond.watchSpellID or defaultSpellID
        local mode = cond.mode or "ready"
        if mode == "charged" then
            -- Glow quand charges pleines (la recharge de charge ignore le GCD).
            if not (GetSpellChargeDuration and EvalBoolToValue) then return nil end
            return function()
                if not sid then return 0 end
                local duo = GetSpellChargeDuration(sid)
                if not duo then return 1 end               -- pas de recharge = charges pleines
                if not duo.IsZero then return 1 end
                return EvalBoolToValue(duo:IsZero(), 1, 0)
            end
        elseif mode == "notready" then
            -- Inverse de "pret" : visible quand le sort est EN RECHARGE (>1.6s, hors GCD).
            if not GetSpellCooldownDuration then return nil end
            local curve = GetNotReadyCurve()
            return function()
                if not sid then return 0 end
                local duo = GetSpellCooldownDuration(sid)
                if not duo then return 0 end               -- pas de recharge = pret -> pas "pas pret"
                if not duo.EvaluateRemainingDuration or not curve then return 0 end
                return duo:EvaluateRemainingDuration(curve, 0)  -- restant >1.6s -> en recharge
            end
        else
            -- Glow quand pret, en IGNORANT le GCD (sinon chaque cast eteint ~1.5s).
            if not GetSpellCooldownDuration then return nil end
            local curve = GetReadyCurve()
            return function()
                if not sid then return 0 end
                local duo = GetSpellCooldownDuration(sid)
                if not duo then return 1 end               -- pas de recharge = pret
                if not duo.EvaluateRemainingDuration or not curve then return 1 end
                return duo:EvaluateRemainingDuration(curve, 1)  -- restant <=1.6s (GCD) -> pret
            end
        end
    end

    -- Condition a fonction libre (avancee).
    if cond.check then
        return BoolEval(cond.check)
    end

    -- Ressource (vie / puissance) : voie secret-safe (Curve -> alpha).
    local fraction = RuleFraction(cond)
    local curve = BuildThresholdCurve(cond.op or "<", fraction)
    if not curve then return nil end
    if cond.source == "health" then
        return function() return UnitHealthPercent("player", false, curve) end
    else
        local pt = cond.powerType
        return function() return UnitPowerPercent("player", pt, false, curve) end
    end
end

-- IMPORTANT : appeler curve:Evaluate(secret) depuis du code addon est INTERDIT
-- ("secret values only allowed during untainted execution"). La voie sanctionnee
-- est de passer la courbe a l'API de pourcentage, qui l'evalue en interne et
-- renvoie l'alpha secret :
--   UnitPowerPercent(unit, powerType, unmodified, curve)
--   UnitHealthPercent(unit, usePredicted, curve)

--------------------------------------------------------------------------------
-- Creation des frames
--------------------------------------------------------------------------------
local function PositionKey(rule, index)
    return rule.id or rule.label or ("rule" .. index)
end

local function Snap(v, step) return math.floor(v / step + 0.5) * step end

local function SavePosition(frame)
    local db = GetDB()
    local point, _, relPoint, x, y = frame:GetPoint()
    -- Aimantation optionnelle : aligne l'offset sur le pas de grille.
    if db.gridSnap and db.gridSize and db.gridSize > 1 then
        x = Snap(x, db.gridSize); y = Snap(y, db.gridSize)
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, relPoint, x, y)
    end
    db.positions[frame.posKey] = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Redimensionne une icone (carree) et resynchronise le halo de chaque couche.
-- save=true persiste la taille pour ce posKey.
local MIN_SIZE, MAX_SIZE = 16, 200
local function SetIconSize(f, size, save)
    size = math.max(MIN_SIZE, math.min(MAX_SIZE, math.floor((size or 50) + 0.5)))
    f._sizeGuard = true
    f:SetSize(size, size)
    f._sizeGuard = false
    local fontSize = math.max(8, math.floor(size * 0.30))
    for _, layer in ipairs(f.layers) do
        if layer.glow then ns.Glow.Resize(layer.glow) end
        if layer.keytext then layer.keytext:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE") end
    end
    if save and f.posKey then
        GetDB().sizes[f.posKey] = size
    end
    return size
end
ns.SetIconSize = SetIconSize

local function ApplyPosition(frame, index)
    local db = GetDB()
    local pos = db.positions[frame.posKey]
    frame:ClearAllPoints()
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", (index - 1) * 60 - 60, -120)
    end
end

-- Une "couche" = un frame portant une copie de l'icone + son glow.
local function CreateLayer(top)
    local layer = CreateFrame("Frame", nil, top)
    layer:SetAllPoints(top)
    local icon = layer:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(layer)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    layer.icon = icon
    layer.glow = ns.Glow.Create(layer)
    -- Texte custom (ex. raccourci clavier), au-dessus de l'icone ET du glow.
    -- Porte par la couche -> herite de son alpha = visible quand l'icone l'est.
    local th = CreateFrame("Frame", nil, layer)
    th:SetAllPoints(layer)
    -- Au-dessus du glow ET du widget cooldown (f+10) pour rester lisible partout.
    th:SetFrameLevel(layer.glow:GetFrameLevel() + 8)
    local kt = th:CreateFontString(nil, "OVERLAY")
    kt:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    kt:SetPoint("CENTER", th, "CENTER", 0, 0)
    kt:SetJustifyH("CENTER")
    layer.keytext = kt
    return layer
end

-- Cree un frame conteneur "vide" (bordure + label + pool de couches).
local function CreateBlankFrame(index)
    local f = CreateFrame("Frame", "XpAuraIcon" .. index, UIParent)
    f:SetSize(50, 50)
    f:SetFrameStrata("HIGH")

    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0, 0, 0, 0.8)
    border:Hide()
    f.border = border

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOP", f, "BOTTOM", 0, -2)
    label:Hide()
    f.label = label

    f.layers = {}        -- pool de couches
    f.alphaTargets = {}  -- { {region=, eval=}, ... } maj a chaque tick

    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)

    -- Redimensionnement (mode deverrouille).
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_SIZE, MIN_SIZE, MAX_SIZE, MAX_SIZE) end
    -- Molette : agrandit/retrecit l'icone (4 px / cran). Ignoree si verrouille.
    f:SetScript("OnMouseWheel", function(self, delta)
        if GetDB().locked then return end
        SetIconSize(self, self:GetWidth() + delta * 4, true)
    end)
    -- Garde l'icone CARREE pendant le glisser de poignee + resync du halo.
    f:SetScript("OnSizeChanged", function(self, w)
        if self._sizeGuard then return end
        self._sizeGuard = true
        self:SetSize(w, w)
        self._sizeGuard = false
        for _, layer in ipairs(self.layers) do
            if layer.glow then ns.Glow.Resize(layer.glow) end
        end
    end)

    -- Poignee de coin pour redimensionner a la souris (visible si deverrouille).
    local sizer = CreateFrame("Button", nil, f)
    sizer:SetSize(14, 14)
    sizer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
    sizer:SetFrameLevel(f:GetFrameLevel() + 20)
    sizer:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
    sizer:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
    sizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    sizer:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SetIconSize(f, f:GetWidth(), true)
    end)
    sizer:Hide()
    f.sizer = sizer

    -- Widget Cooldown (mode "suivi de cooldown"), au-dessus des couches.
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints(f)
    cd:SetFrameLevel(f:GetFrameLevel() + 10)
    cd:SetDrawEdge(true)
    cd:Hide()
    f.cd = cd
    return f
end

-- Rafraichit le balayage de cooldown (objet Duration -> secret-safe, marche en combat).
local function RefreshCooldown(f)
    if not f.cooldownSpellID then return end
    local duo = GetSpellCooldownDuration and GetSpellCooldownDuration(f.cooldownSpellID)
    if duo then
        f.cd:SetCooldownFromDurationObject(duo)
    else
        f.cd:Clear()
    end
end
ns.RefreshCooldown = RefreshCooldown

-- Applique une regle (1 ou N conditions, ou suivi de cooldown) a un frame existant.
local function ConfigureFrame(f, rule, index)
    f.rule = rule
    f.posKey = PositionKey(rule, index)
    f.label:SetText(rule.label or f.posKey)
    ApplyPosition(f, index)

    local tex = rule.texture or (rule.spellID and GetSpellTexture(rule.spellID)) or 134400

    -- Mode "suivi de cooldown".
    if rule.cooldown then
        wipe(f.alphaTargets)
        local layer = f.layers[1]
        if not layer then layer = CreateLayer(f); f.layers[1] = layer end
        layer:SetParent(f); layer:ClearAllPoints(); layer:SetAllPoints(f)
        layer.icon:SetTexture(tex); layer.icon:Show()
        layer.keytext:SetText(rule.keyText or "")
        layer:Show()
        for i = 2, #f.layers do f.layers[i]:Hide() end

        if rule.glowWhenReady and GetSpellCooldownDuration then
            -- Glow quand pret, en IGNORANT le GCD (sinon chaque cast eteint tout ~1.5s).
            f.cooldownSpellID = nil
            f.cd:Hide()
            if rule.glow ~= false then layer.glow:Show() else layer.glow:Hide() end  -- glow optionnel
            local sid = rule.spellID
            local curve = GetReadyCurve()
            f.alphaTargets[1] = { region = layer, eval = function()
                if not sid then return 0 end
                local duo = GetSpellCooldownDuration(sid)
                if not duo then return 1 end                       -- pas de recharge = pret
                if not duo.EvaluateRemainingDuration or not curve then return 1 end
                return duo:EvaluateRemainingDuration(curve, 1)      -- <=1.6s (GCD) -> visible
            end }
            layer:SetAlpha(0)
        elseif rule.glowWhenCharged and GetSpellChargeDuration and EvalBoolToValue then
            -- Glow quand charges pleines (la recharge de charge ignore le GCD).
            f.cooldownSpellID = nil
            f.cd:Hide()
            if rule.glow ~= false then layer.glow:Show() else layer.glow:Hide() end  -- glow optionnel
            local sid = rule.spellID
            f.alphaTargets[1] = { region = layer, eval = function()
                if not sid then return 0 end
                local duo = GetSpellChargeDuration(sid)
                if not duo then return 1 end                       -- pas de recharge = charges pleines
                if not duo.IsZero then return 1 end
                return EvalBoolToValue(duo:IsZero(), 1, 0)
            end }
            layer:SetAlpha(0)
        else
            -- Balayage de recharge, icone toujours visible.
            f.cooldownSpellID = rule.spellID
            f.cd:Show()
            layer.glow:Hide()
            layer:SetAlpha(1)
            RefreshCooldown(f)
        end
        f:SetAlpha(1); f:Show()
        return
    end

    -- Mode conditions (glow) :
    f.cooldownSpellID = nil
    f.cd:Hide()
    local conds, combine = GetConditions(rule)

    wipe(f.alphaTargets)
    -- Glow optionnel : rule.glow == false -> icone seule. nil/true -> icone + halo
    -- (retro-compat : les anciennes regles sans ce champ gardent le glow).
    local showGlow = rule.glow ~= false
    local parent = f
    for i, cond in ipairs(conds) do
        local layer = f.layers[i]
        if not layer then layer = CreateLayer(f); f.layers[i] = layer end
        layer.icon:SetTexture(tex)
        layer:ClearAllPoints()
        layer:Show()
        if combine == "AND" then
            -- Imbrication : alpha(enfant) * alpha(parent) -> ET. Icone/glow sur le dernier.
            layer:SetParent(parent)
            layer:SetAllPoints(parent)
            local isLast = (i == #conds)
            layer.icon:SetShown(isLast)
            layer.keytext:SetText(isLast and (rule.keyText or "") or "")
            if isLast and showGlow then layer.glow:Show() else layer.glow:Hide() end
            parent = layer
        else
            -- Empilement : couches soeurs -> OU visuel.
            layer:SetParent(f)
            layer:SetAllPoints(f)
            layer.icon:Show()
            layer.keytext:SetText(rule.keyText or "")
            if showGlow then layer.glow:Show() else layer.glow:Hide() end
        end
        f.alphaTargets[i] = { region = layer, eval = BuildConditionEval(cond, rule.spellID) }
    end
    for i = #conds + 1, #f.layers do
        f.layers[i]:Hide()
    end

    f:SetAlpha(1)
    f:Show()
end

-- Liste des regles actives (integrees + utilisateur) pour la classe ET la spe courantes.
-- Une regle s'affiche si : (pas de classe OU classe = la mienne) ET (pas de spe OU spe = la mienne).
local function ActiveRules()
    local _, playerClass = UnitClass("player")
    local specID
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        if idx then specID = GetSpecializationInfo(idx) end
    end
    local function keep(r)
        if r.class and r.class ~= playerClass then return false end
        if r.spec and r.spec ~= specID then return false end
        return true
    end
    local list = {}
    for _, r in ipairs(ns.rules) do
        if keep(r) then list[#list + 1] = r end
    end
    local db = GetDB()
    for _, r in ipairs(db.userRules) do
        if keep(r) then list[#list + 1] = r end
    end
    return list
end

ns.framePool = {}

--------------------------------------------------------------------------------
-- Grille d'aide au placement (visible seulement en mode deverrouille)
--------------------------------------------------------------------------------
local gridFrame, gridLines = nil, {}

local function EnsureGrid()
    if gridFrame then return gridFrame end
    gridFrame = CreateFrame("Frame", "XpAuraGrid", UIParent)
    gridFrame:SetAllPoints(UIParent)
    gridFrame:SetFrameStrata("BACKGROUND")
    gridFrame:Hide()
    return gridFrame
end

-- (Re)dessine les lignes selon le pas courant (db.gridSize). Reutilise le pool.
function ns.RebuildGrid()
    local g = EnsureGrid()
    for _, t in ipairs(gridLines) do t:Hide() end
    local step = GetDB().gridSize or 20
    if step < 4 then step = 4 end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local n = 0
    local function Line()
        n = n + 1
        local t = gridLines[n]
        if not t then t = g:CreateTexture(nil, "BACKGROUND"); gridLines[n] = t end
        t:SetColorTexture(1, 1, 1, 0.12)
        t:Show()
        return t
    end
    -- Lignes verticales (depuis le centre vers les bords).
    for x = 0, w / 2, step do
        for _, sx in ipairs(x == 0 and { 0 } or { x, -x }) do
            local t = Line()
            t:ClearAllPoints(); t:SetSize(1, h)
            t:SetPoint("CENTER", UIParent, "CENTER", sx, 0)
        end
    end
    -- Lignes horizontales.
    for y = 0, h / 2, step do
        for _, sy in ipairs(y == 0 and { 0 } or { y, -y }) do
            local t = Line()
            t:ClearAllPoints(); t:SetSize(w, 1)
            t:SetPoint("CENTER", UIParent, "CENTER", 0, sy)
        end
    end
    for i = n + 1, #gridLines do gridLines[i]:Hide() end
end

-- Montre/cache la grille selon l'etat (deverrouille + option activee).
function ns.UpdateGrid()
    local db = GetDB()
    if (not db.locked) and db.gridShow then
        EnsureGrid()
        ns.RebuildGrid()
        gridFrame:Show()
    elseif gridFrame then
        gridFrame:Hide()
    end
end

-- (Re)construit l'affichage a partir des regles actives. Reutilise les frames du pool.
function ns.Rebuild()
    local rules = ActiveRules()
    local db = GetDB()
    for i, rule in ipairs(rules) do
        local f = ns.framePool[i]
        if not f then
            f = CreateBlankFrame(i)
            ns.framePool[i] = f
        end
        ConfigureFrame(f, rule, i)
        SetIconSize(f, db.sizes[f.posKey] or 50, false)
    end
    for i = #rules + 1, #ns.framePool do
        ns.framePool[i].rule = nil
        ns.framePool[i]:Hide()
    end
    ns.frames = {}
    for i = 1, #rules do ns.frames[i] = ns.framePool[i] end

    if #rules > 0 and not CreateCurve then
        Print("|cffff4040" .. L["WARNING: C_CurveUtil unavailable — health/power thresholds will only work out of combat."] .. "|r")
    end
end

--------------------------------------------------------------------------------
-- Boucle d'evaluation
--------------------------------------------------------------------------------
local function UpdateFrame(f)
    local db = GetDB()
    local unlocked = not db.locked
    f:EnableMouse(unlocked)
    f:EnableMouseWheel(unlocked)
    f.border:SetShown(unlocked)
    f.label:SetShown(unlocked)
    if f.sizer then f.sizer:SetShown(unlocked) end
    f:Show()

    -- Option globale : masquer hors combat (sauf en mode positionnement).
    if not unlocked and db.combatOnly and not InCombatLockdown() then
        f:SetAlpha(0)
        return
    end
    f:SetAlpha(1)

    -- Mode suivi de cooldown : icone toujours visible (le balayage est gere par event).
    if f.cooldownSpellID then
        f.layers[1]:SetAlpha(1)
        return
    end

    -- Mode positionnement : tout visible.
    if unlocked then
        for _, t in ipairs(f.alphaTargets) do t.region:SetAlpha(1) end
        return
    end

    -- Chaque condition pilote l'alpha de sa couche (OU = soeurs, ET = imbriquees).
    -- On ne teste jamais le resultat (secret) : if/else sur le "ok" du pcall.
    -- Chaque SetAlpha est protege individuellement : l'echec d'une couche ne doit
    -- pas empecher la mise a jour des autres couches/regles.
    for _, t in ipairs(f.alphaTargets) do
        if t.eval then
            local ok, a = pcall(t.eval)
            if ok then
                pcall(t.region.SetAlpha, t.region, a)
            else
                t.region:SetAlpha(0)
            end
        else
            t.region:SetAlpha(0)
        end
    end
end

local accum, THROTTLE = 0, 0.1
local function OnUpdate(_, elapsed)
    accum = accum + elapsed
    if accum < THROTTLE then return end
    accum = 0
    -- pcall par frame : une erreur sur une regle ne doit pas figer les autres.
    for _, f in ipairs(ns.frames) do
        pcall(UpdateFrame, f)
    end
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------
SLASH_XPAURA1 = "/xpaura"
SLASH_XPAURA2 = "/xpa"
SlashCmdList.XPAURA = function(msg)
    local db = GetDB()
    -- 1er mot = commande ; le reste (espaces/accents preserves) = parametre.
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local arg = (cmd or ""):lower()
    if arg == "config" or arg == "options" or arg == "menu" then
        if ns.OpenConfig then ns.OpenConfig() else Print(L["menu unavailable."]) end
    elseif arg == "unlock" then
        db.locked = false
        ns.UpdateGrid()
        Print(string.format(L["unlocked — move (drag), resize (wheel/handle), then %s."], "|cffffff00/xpaura lock|r"))
    elseif arg == "lock" then
        db.locked = true
        ns.UpdateGrid()
        Print(L["locked."])
    elseif arg == "grid" then
        db.gridShow = not db.gridShow
        ns.UpdateGrid()
        Print(string.format(L["grid: %s (in unlocked mode)."], db.gridShow and L["shown"] or L["hidden"]))
    elseif arg == "reset" then
        db.positions = {}
        db.sizes = {}
        for i, f in ipairs(ns.frames) do ApplyPosition(f, i); SetIconSize(f, 50, false) end
        Print(L["positions and sizes reset."])
    elseif arg == "test" or arg == "debug" then
        Print(("locked=%s  frames=%d  combat=%s  CurveUtil=%s"):format(
            tostring(db.locked), #ns.frames, tostring(InCombatLockdown()),
            tostring(CreateCurve ~= nil)))
        Print(("spell-link hook fires=%s lastId=%s"):format(
            tostring(ns._linkFires or 0), tostring(ns._linkLastId)))
        for i, f in ipairs(ns.frames) do
            local r = f.rule
            local parts = {}
            for j, t in ipairs(f.alphaTargets) do
                local s = "?"
                if t.eval then
                    local ok, a = pcall(t.eval)
                    if ok then s = "OK/secret=" .. tostring(issecretvalue(a)) else s = "ERR" end
                end
                parts[j] = "c" .. j .. "=" .. s
            end
            Print(("r%d [%s] combine=%s | %s"):format(
                i, tostring(r.label), tostring(r.combine or "OR"),
                table.concat(parts, " ")))
        end
    else
        Print(string.format(L["commands: %s"],
            "|cffffff00/xpaura config|r, |cffffff00unlock|r, |cffffff00lock|r, |cffffff00grid|r, |cffffff00reset|r, |cffffff00test|r"))
    end
end

--------------------------------------------------------------------------------
-- Initialisation
--------------------------------------------------------------------------------
local driver = CreateFrame("Frame")
local needRebuild = false
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterUnitEvent("UNIT_MAXPOWER", "player")
driver:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")  -- sortie de combat
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")  -- changement de spe -> refiltrer
driver:SetScript("OnEvent", function(self, event)
    GetDB()
    if event == "PLAYER_LOGIN" then
        ns.Rebuild()
        ns.UpdateGrid()
        if ns.SetupMinimap then ns.SetupMinimap() end
        if ns.SetupOptions then ns.SetupOptions() end
        self:SetScript("OnUpdate", OnUpdate)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Hors combat seulement (un changement de spe n'arrive pas en combat).
        if InCombatLockdown() then needRebuild = true else ns.Rebuild() end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        -- Rafraichit les balayages des regles "suivi de cooldown".
        for _, f in ipairs(ns.frames) do RefreshCooldown(f) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Sortie de combat : applique une reconstruction differee si besoin.
        if needRebuild then needRebuild = false; ns.Rebuild() end
    else
        -- Max change (UNIT_MAXPOWER/MAXHEALTH) : reconstruire (seuils absolus -> fractions),
        -- mais JAMAIS en combat (un Rebuild en combat fait clignoter/disparaitre les icones).
        if InCombatLockdown() then
            needRebuild = true
        else
            ns.Rebuild()
        end
    end
end)
