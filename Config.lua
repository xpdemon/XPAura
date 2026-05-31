-- Config.lua
-- Menu in-game (theme sombre plat, fenetre a onglets) : creer/editer/supprimer des regles.
--   * Conditions (vie/puissance, secret-safe) -> glow combinables OU/ET.
--   * Suivi de cooldown -> icone + balayage de recharge (combat-safe via objet Duration).
local ADDON, ns = ...

local GetSpellTexture = (C_Spell and C_Spell.GetSpellTexture) or _G.GetSpellTexture
local QUESTION = 134400
local L = ns.L

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffXpAura|r: " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Theme sombre plat (assets natifs : WHITE8x8 recolore + BackdropTemplate)
--------------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8x8"
local PAL = {
    bg     = { 0.08, 0.08, 0.08, 0.96 },
    panel  = { 0.12, 0.12, 0.12, 1 },
    elem   = { 0.18, 0.18, 0.18, 1 },
    border = { 0.25, 0.25, 0.25, 1 },
    hover  = { 0.24, 0.24, 0.24, 1 },
    accent = { 0.30, 0.45, 0.85, 1 },
    title  = { 0.16, 0.20, 0.34, 1 },
    text   = { 0.90, 0.90, 0.90 },
    dim    = { 0.60, 0.60, 0.60 },
    danger = { 0.70, 0.35, 0.35, 1 },
}
local function C(t) return t[1], t[2], t[3], t[4] or 1 end

local function Skin(f, bg, border)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(C(bg or PAL.panel))
    f:SetBackdropBorderColor(C(border or PAL.border))
end

--------------------------------------------------------------------------------
-- Listes d'options
--------------------------------------------------------------------------------
local function PT(name) return Enum.PowerType and Enum.PowerType[name] end
-- Nom localise d'une ressource : constante globale Blizzard (deja traduite) si dispo.
local function GS(global, fallbackKey)
    local s = _G[global]
    if type(s) == "string" and s ~= "" then return s end
    return L[fallbackKey]
end
local RAW_SOURCES = {
    { name = GS("HEALTH", "Health"),            source = "health" },
    { name = GS("MANA", "Mana"),                source = "power", pt = PT("Mana") },
    { name = GS("RAGE", "Rage"),                source = "power", pt = PT("Rage") },
    { name = GS("ENERGY", "Energy"),            source = "power", pt = PT("Energy") },
    { name = GS("FOCUS", "Focus"),              source = "power", pt = PT("Focus") },
    { name = GS("RUNIC_POWER", "Runic Power"),  source = "power", pt = PT("RunicPower") },
    { name = GS("FURY", "Fury"),                source = "power", pt = PT("Fury") },
    { name = GS("PAIN", "Pain"),                source = "power", pt = PT("Pain") },
    { name = GS("HOLY_POWER", "Holy Power"),    source = "power", pt = PT("HolyPower") },
    { name = GS("MAELSTROM", "Maelstrom"),      source = "power", pt = PT("Maelstrom") },
    { name = GS("INSANITY", "Insanity"),        source = "power", pt = PT("Insanity") },
    { name = GS("SOUL_SHARDS", "Soul Shards"),  source = "power", pt = PT("SoulShards") },
    { name = GS("LUNAR_POWER", "Lunar Power"),  source = "power", pt = PT("LunarPower") },
    { name = GS("ESSENCE", "Essence"),          source = "power", pt = PT("Essence") },
    { name = GS("COMBO_POINTS", "Combo Points"),source = "power", pt = PT("ComboPoints") },
    { name = L["Spell ready"],        source = "spellready" },
    { name = L["Spell NOT ready"],    source = "spellnotready" },
    { name = L["Spell charges full"], source = "spellcharged" },
}
local SPELL_SOURCE = { spellready = true, spellnotready = true, spellcharged = true }
local SOURCES = {}
for _, s in ipairs(RAW_SOURCES) do
    if s.source == "health" or SPELL_SOURCE[s.source] or s.pt ~= nil then
        SOURCES[#SOURCES + 1] = s
    end
end

local RULETYPE_ITEMS = {
    { name = L["Conditions (health / power)"], mode = "conditions",
      tip = "Show the icon when conditions are met: resource thresholds and/or spell availability, combined with AND/OR." },
    { name = L["Cooldown tracking (spell)"], mode = "cooldown",
      tip = "Track a spell's cooldown: a sweep timer on the icon, or glow when it is ready / at full charges." },
    { name = L["Runes available (DK)"], mode = "runes",
      tip = "Death Knight: glow when the number of ready runes meets a threshold." },
}
local SCOPE_ITEMS = { { name = L["Global (all classes)"] },
                      { name = L["Current class"] },
                      { name = L["Current spec"] } }

local function CurrentSpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return nil end
    local idx = GetSpecialization()
    if not idx then return nil end
    return (GetSpecializationInfo(idx))
end

local function SpecList()
    local out = {}
    if GetNumSpecializations and GetSpecializationInfo then
        for i = 1, GetNumSpecializations() do
            local id, name = GetSpecializationInfo(i)
            if id then out[#out + 1] = { id = id, name = name or string.format(L["Spec %d"], i) } end
        end
    end
    return out
end

local function RefreshScopeName()
    local name
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        if idx then local _, sname = GetSpecializationInfo(idx); name = sname end
    end
    SCOPE_ITEMS[3].name = name and string.format(L["Spec: %s"], name) or L["Current spec"]
end
local RUNEOP_ITEMS   = { { name = L[">= (at least)"], op = ">=" }, { name = L["> (more than)"], op = ">" },
                         { name = L["<= (at most)"], op = "<=" }, { name = L["< (less than)"], op = "<" } }
local CDMODE_ITEMS   = { { name = L["sweep (always visible)"], mode = "sweep" },
                         { name = L["glow when ready (else hidden)"], mode = "ready" },
                         { name = L["glow when charges full"], mode = "charged" } }
local OP_ITEMS      = { { name = L["below threshold"], op = "<" }, { name = L["above threshold"], op = ">" } }
local TYPE_ITEMS    = { { name = L["percentage"], pct = true },        { name = L["absolute value"], pct = false } }
local COMBINE_ITEMS = { { name = L["at least one (OR)"], combine = "OR" }, { name = L["all (AND)"], combine = "AND" } }
local GRIDSTEP_ITEMS = { { name = "5 px", step = 5 }, { name = "10 px", step = 10 },
                         { name = "20 px", step = 20 }, { name = "25 px", step = 25 },
                         { name = "50 px", step = 50 } }

--------------------------------------------------------------------------------
-- Helpers descriptifs
--------------------------------------------------------------------------------
local function SourceLabel(c)
    if c.source == "health" then return GS("HEALTH", "Health") end
    for _, s in ipairs(SOURCES) do
        if s.source == "power" and s.pt == c.powerType then return s.name end
    end
    return L["Resource"]
end

local function CondDesc(c)
    if c.kind == "runes" then
        return "runes " .. (c.op or ">=") .. " " .. (c.value or 2)
    end
    if c.kind == "aura" then
        return "aura #" .. tostring(c.watchSpellID) .. " " .. tostring(c.mode)
    end
    if c.kind == "spell" then
        local m = (c.mode == "charged") and L["charges full"]
               or (c.mode == "notready") and L["not ready"] or L["ready"]
        local who = c.watchSpellID and ("#" .. c.watchSpellID) or L["icon"]
        return string.format(L["spell %s: %s"], who, m)
    end
    local thr = c.pct and (c.pct .. "%") or tostring(c.value)
    local op  = (c.op == ">") and ">" or "<"
    return SourceLabel(c) .. " " .. op .. " " .. thr
end

local function RuleDesc(rule)
    if rule.cooldown then
        if rule.glowWhenReady then return L["glow when ready"] end
        if rule.glowWhenCharged then return L["glow when charges full"] end
        return L["cooldown sweep"]
    end
    local conds = rule.conditions
    if not conds then return CondDesc(rule) end
    local parts = {}
    for _, c in ipairs(conds) do parts[#parts + 1] = CondDesc(c) end
    local sep = (rule.combine == "AND") and L[" AND "] or L[" OR "]
    return table.concat(parts, sep)
end

local function ResolveSpell(text)
    if not text or text == "" then return nil, QUESTION, nil end
    local id = tonumber(text)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id or text)
        if ok and info and info.spellID then
            return info.spellID, info.iconID or QUESTION, info.name
        end
    end
    local tex = id and GetSpellTexture(id)
    return id, tex or QUESTION, nil
end

--------------------------------------------------------------------------------
-- Toolkit de widgets sombres
--------------------------------------------------------------------------------
-- Reduit la police d'un FontString jusqu'a tenir dans maxW (anti-debordement i18n).
local function FitText(fs, maxW)
    if not (fs and fs.GetFont and maxW and maxW > 0) then return end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    local file, size, flags = fs:GetFont()
    if not file then return end
    local guard = 0
    while fs:GetStringWidth() > maxW and size > 8 and guard < 24 do
        size = size - 1
        fs:SetFont(file, size, flags)
        guard = guard + 1
    end
end

local function MakeLabel(parent, text, x, y, maxW)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetTextColor(C(PAL.text))
    fs:SetText(text)
    if maxW then FitText(fs, maxW) end
    return fs
end

local function MakeHeader(parent, text, x, y, w)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetTextColor(C(PAL.accent))
    fs:SetText(text)
    -- ligne separatrice sous le titre
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C(PAL.border))
    line:SetPoint("TOPLEFT", x, y - 16)
    line:SetSize(w or 300, 1)
    fs.line = line
    return fs
end

local function MakeEdit(parent, w, x, y)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(w, 22)
    if x then e:SetPoint("TOPLEFT", x, y) end
    Skin(e, { 0.05, 0.05, 0.05, 1 }, PAL.border)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetTextColor(C(PAL.text))
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

local function MakeButton(parent, w, x, y, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 100, 22)
    if x then b:SetPoint("TOPLEFT", x, y) end
    Skin(b, PAL.elem, PAL.border)
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.fs:SetPoint("CENTER")
    b.fs:SetTextColor(C(PAL.text))
    b.SetText = function(self, t) self.fs:SetText(t); FitText(self.fs, (self:GetWidth() or w) - 10) end
    b.GetText = function(self) return self.fs:GetText() end
    if text then b:SetText(text) end
    b:SetScript("OnEnter", function(s) s:SetBackdropColor(C(PAL.hover)) end)
    b:SetScript("OnLeave", function(s) s:SetBackdropColor(C(PAL.elem)) end)
    return b
end

-- Case a cocher custom (carre + coche accent).
local function MakeCheck(parent, x, y, label, maxW)
    local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
    c:SetSize(18, 18)
    c:SetPoint("TOPLEFT", x, y)
    Skin(c, PAL.elem, PAL.border)
    c.tick = c:CreateTexture(nil, "ARTWORK")
    c.tick:SetPoint("TOPLEFT", 3, -3)
    c.tick:SetPoint("BOTTOMRIGHT", -3, 3)
    c.tick:SetColorTexture(C(PAL.accent))
    c.tick:Hide()
    c.checked = false
    c.GetChecked = function(self) return self.checked end
    c.SetChecked = function(self, v) self.checked = v and true or false; self.tick:SetShown(self.checked) end
    c:SetScript("OnEnter", function(s) s:SetBackdropColor(C(PAL.hover)) end)
    c:SetScript("OnLeave", function(s) s:SetBackdropColor(C(PAL.elem)) end)
    c:SetScript("OnClick", function(self)
        self:SetChecked(not self.checked)
        if self.onClick then self.onClick(self) end
    end)
    if label then
        c.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        c.label:SetPoint("LEFT", c, "RIGHT", 6, 0)
        c.label:SetTextColor(C(PAL.text))
        c.label:SetText(label)
        if maxW then FitText(c.label, maxW) end
    end
    return c
end

-- Dropdown custom (bouton + liste deroulante). Ferme au choix ou au clic-dehors.
local ddRefreshers = {}
local openList
local ddCloser
local function CloseDD() if openList then openList:Hide(); openList = nil end if ddCloser then ddCloser:Hide() end end
local function GetCloser()
    if ddCloser then return ddCloser end
    ddCloser = CreateFrame("Button", nil, UIParent)
    ddCloser:SetAllPoints(UIParent)
    ddCloser:SetFrameStrata("FULLSCREEN_DIALOG")
    ddCloser:Hide()
    ddCloser:SetScript("OnClick", CloseDD)
    return ddCloser
end

local function MakeDropdown(parent, w, x, y, items, getIndex, setIndex)
    local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dd:SetSize(w, 22)
    if x then dd:SetPoint("TOPLEFT", x, y) end
    Skin(dd, PAL.elem, PAL.border)
    dd.fs = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dd.fs:SetPoint("LEFT", 8, 0)
    dd.fs:SetPoint("RIGHT", -18, 0)
    dd.fs:SetJustifyH("LEFT")
    dd.fs:SetTextColor(C(PAL.text))
    local arrow = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(C(PAL.dim))

    local function refresh()
        local it = items[getIndex()]
        dd.fs:SetText(it and it.name or "")
        FitText(dd.fs, w - 26)
    end
    refresh()
    ddRefreshers[#ddRefreshers + 1] = refresh

    local list = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetClampedToScreen(true)
    Skin(list, PAL.panel, PAL.border)
    list:Hide()
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    list.btns = {}

    dd:SetScript("OnEnter", function(s) s:SetBackdropColor(C(PAL.hover)) end)
    dd:SetScript("OnLeave", function(s) s:SetBackdropColor(C(PAL.elem)) end)
    dd:SetScript("OnHide", function() if openList == list then CloseDD() end end)
    dd:SetScript("OnClick", function()
        if list:IsShown() then CloseDD(); return end
        if openList then openList:Hide() end
        local n = #items
        for i = 1, n do
            local ob = list.btns[i]
            if not ob then
                ob = CreateFrame("Button", nil, list, "BackdropTemplate")
                ob:SetHeight(20)
                ob.fs = ob:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                ob.fs:SetPoint("LEFT", 8, 0)
                ob.fs:SetPoint("RIGHT", -6, 0)
                ob.fs:SetJustifyH("LEFT")
                ob.fs:SetTextColor(C(PAL.text))
                list.btns[i] = ob
            end
            ob.fs:SetText(items[i].name)
            ob:ClearAllPoints()
            ob:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
            ob:SetPoint("RIGHT", list, "RIGHT", -2, 0)
            ob:SetScript("OnEnter", function(s)
                Skin(s, PAL.accent, PAL.accent)
                local it = items[i]
                if it and it.tip then
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(it.name)
                    GameTooltip:AddLine(L[it.tip], 0.9, 0.9, 0.9, true)
                    GameTooltip:Show()
                end
            end)
            ob:SetScript("OnLeave", function(s) s:SetBackdrop(nil); GameTooltip:Hide() end)
            ob:SetScript("OnClick", function() setIndex(i); refresh(); CloseDD() end)
            ob:SetBackdrop(nil)
            ob:Show()
        end
        for i = n + 1, #list.btns do list.btns[i]:Hide() end
        list:SetSize(w, n * 20 + 4)
        local closer = GetCloser()
        closer:SetFrameLevel(math.max(1, dd:GetFrameLevel()))
        closer:Show()
        list:SetFrameLevel(closer:GetFrameLevel() + 5)
        list:Show()
        openList = list
    end)
    return dd
end

-- Infobulle d'aide sur un widget (titre + corps localise).
local function AddTooltip(w, title, bodyKey)
    if not w then return end
    w:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title) end
        if bodyKey then GameTooltip:AddLine(L[bodyKey], 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    w:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Recolore la scrollbar d'un UIPanelScrollFrameTemplate (best-effort).
local function StyleScroll(scroll)
    local sb = scroll.ScrollBar or _G[(scroll:GetName() or "") .. "ScrollBar"]
    if sb then
        if sb.Background then sb.Background:Hide() end
        local thumb = sb.ThumbTexture or (sb.GetThumbTexture and sb:GetThumbTexture())
        if thumb then thumb:SetColorTexture(C(PAL.accent)) end
    end
end

--------------------------------------------------------------------------------
-- Maj+clic d'un sort du grimoire pour remplir un EditBox.
--------------------------------------------------------------------------------
local spellLinkTargets = {}
local lastFocusedSpellBox
local spellDropHooked = false
local function EnableSpellDrop(editbox)
    if not editbox then return end
    spellLinkTargets[#spellLinkTargets + 1] = editbox
    editbox:HookScript("OnEditFocusGained", function(self) lastFocusedSpellBox = self end)
    editbox:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Shift-click a spell in your spellbook to fill this field."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    editbox:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if spellDropHooked then return end
    spellDropHooked = true
    local function onLink(text)
        if type(text) ~= "string" then return end
        local id = tonumber(text:match("spell:(%d+)"))
        if not id then return end
        ns._linkFires = (ns._linkFires or 0) + 1
        ns._linkLastId = id
        local target
        for _, eb in ipairs(spellLinkTargets) do
            if eb:IsVisible() and eb:HasFocus() then target = eb; break end
        end
        if not target and lastFocusedSpellBox and lastFocusedSpellBox:IsVisible() then
            target = lastFocusedSpellBox
        end
        if target then
            target:SetText(tostring(id))
            target:SetCursorPosition(0)
        end
    end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", onLink)
    end
    if _G.ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", onLink)
    end
end

--------------------------------------------------------------------------------
-- Etat + logique
--------------------------------------------------------------------------------
local cfg
local form, pendRows, ruleRows, headerRows
local LoadRule
local RefreshList
local UpdateEditBanner

local function CurrentCondition()
    local s = SOURCES[form.sourceIndex]
    if SPELL_SOURCE[s.source] then
        local mode = (s.source == "spellcharged") and "charged"
                  or (s.source == "spellnotready") and "notready" or "ready"
        local c = { kind = "spell", mode = mode }
        local wid = ResolveSpell(cfg.watchSpellBox:GetText())
        if wid then c.watchSpellID = wid end
        return c
    end
    local c = { kind = "resource", source = s.source, op = OP_ITEMS[form.opIndex].op }
    if s.source == "power" then c.powerType = s.pt end
    local v = tonumber(cfg.valueBox:GetText()) or 50
    if TYPE_ITEMS[form.typeIndex].pct then c.pct = v else c.value = v end
    return c
end

-- Lignes de conditions en attente, rendues dans la zone editeur (cfg.editorBody).
local PEND_Y = -412
local function RefreshPending()
    pendRows = pendRows or {}
    for _, r in ipairs(pendRows) do r:Hide() end
    if not cfg or RULETYPE_ITEMS[form.ruleTypeIndex].mode ~= "conditions" then return end
    local parent = cfg.editorBody
    local y = PEND_Y
    for i, c in ipairs(form.pending) do
        local row = pendRows[i]
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetSize(420, 20)
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetWidth(360)
            row.text:SetJustifyH("LEFT")
            row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.del:SetSize(20, 20)
            row.del:SetPoint("RIGHT", 0, 0)
            pendRows[i] = row
        end
        row:SetParent(parent)
        row.text:SetText("|cffaad4ff- " .. CondDesc(c) .. "|r")
        row.del:SetScript("OnClick", function()
            table.remove(form.pending, i)
            RefreshPending()
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, y)
        row:Show()
        y = y - 22
    end
end

-- Source "sort dispo" : masque Condition/Seuil, montre "Sort surveille".
local function RefreshCondFields()
    if not cfg or not cfg.opDD then return end
    local condMode = RULETYPE_ITEMS[form.ruleTypeIndex].mode == "conditions"
    local s = SOURCES[form.sourceIndex]
    local isSpell = (s and SPELL_SOURCE[s.source]) and true or false
    local showResource = condMode and not isSpell
    local showSpell    = condMode and isSpell
    cfg.opLabel:SetShown(showResource)
    cfg.opDD:SetShown(showResource)
    cfg.seuilLabel:SetShown(showResource)
    cfg.typeDD:SetShown(showResource)
    cfg.valueBox:SetShown(showResource)
    cfg.watchLabel:SetShown(showSpell)
    cfg.watchSpellBox:SetShown(showSpell)
    cfg.watchHint:SetShown(showSpell)
end

-- Affiche/masque les blocs selon le type de regle (plus de tail-shift).
local function UpdateFields()
    if not cfg then return end
    local mode = RULETYPE_ITEMS[form.ruleTypeIndex].mode
    for _, w in ipairs(cfg.condWidgets) do w:SetShown(mode == "conditions") end
    for _, w in ipairs(cfg.cdWidgets)   do w:SetShown(mode == "cooldown") end
    for _, w in ipairs(cfg.runeWidgets) do w:SetShown(mode == "runes") end
    -- Le glow est desormais optionnel pour TOUS les types (conditions, runes, cooldown).
    if cfg.glowWidgets then
        for _, w in ipairs(cfg.glowWidgets) do w:SetShown(true) end
    end
    RefreshCondFields()
    RefreshPending()
end

-- Ligne de regle (icone + texte + Editer/Suppr.) dans l'onglet "Mes regles".
local function CreateRuleRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(380, 34)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints(); hl:SetColorTexture(C(PAL.accent)); hl:SetAlpha(0.12); hl:Hide()
    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)
    row:EnableMouse(true)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 32, 0)
    row.text:SetWidth(210)
    row.text:SetJustifyH("LEFT")
    row.del = MakeButton(row, 58)
    row.del:ClearAllPoints(); row.del:SetPoint("RIGHT", -4, 0); row.del:SetText(L["Delete"])
    row.del.fs:SetTextColor(C(PAL.danger))
    row.edit = MakeButton(row, 56)
    row.edit:ClearAllPoints(); row.edit:SetPoint("RIGHT", row.del, "LEFT", -4, 0); row.edit:SetText(L["Edit"])
    return row
end

-- En-tete d'accordeon cliquable.
local function CreateRulesHeader(parent)
    local h = CreateFrame("Button", nil, parent, "BackdropTemplate")
    h:SetSize(380, 22)
    Skin(h, PAL.panel, PAL.border)
    h:SetScript("OnEnter", function(s) s:SetBackdropColor(C(PAL.hover)) end)
    h:SetScript("OnLeave", function(s) s:SetBackdropColor(C(PAL.panel)) end)
    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h.text:SetPoint("LEFT", 8, 0)
    h.text:SetJustifyH("LEFT")
    h.text:SetTextColor(C(PAL.accent))
    h:SetScript("OnClick", function(self)
        cfg.collapsed[self.key] = not cfg.collapsed[self.key]
        RefreshList()
    end)
    return h
end

function RefreshList()
    local db = ns.GetDB()
    ruleRows = ruleRows or {}
    headerRows = headerRows or {}
    cfg.collapsed = cfg.collapsed or {}
    for _, r in ipairs(ruleRows) do r:Hide() end
    for _, h in ipairs(headerRows) do h:Hide() end

    local groups = { { key = "global", name = L["Global"], rules = {} } }
    local byKey = {}
    for _, s in ipairs(SpecList()) do
        local g = { key = "spec" .. s.id, name = s.name, rules = {} }
        groups[#groups + 1] = g
        byKey[s.id] = g
    end
    for i, rule in ipairs(db.userRules) do
        local g = (rule.spec and byKey[rule.spec]) or groups[1]
        g.rules[#g.rules + 1] = { idx = i, rule = rule }
    end

    local parent = cfg.rulesChild
    local y = -4
    local hN, rN = 0, 0
    for _, g in ipairs(groups) do
        hN = hN + 1
        local header = headerRows[hN] or CreateRulesHeader(parent)
        headerRows[hN] = header
        header:SetParent(parent)
        local collapsed = cfg.collapsed[g.key] and true or false
        header.key = g.key
        header.text:SetText(("%s %s |cff888888(%d)|r"):format(collapsed and "+" or "-", g.name, #g.rules))
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
        header:Show()
        y = y - 26
        if not collapsed then
            for _, entry in ipairs(g.rules) do
                rN = rN + 1
                local row = ruleRows[rN] or CreateRuleRow(parent)
                ruleRows[rN] = row
                row:SetParent(parent)
                local i, rule = entry.idx, entry.rule
                local tex = rule.texture or (rule.spellID and GetSpellTexture(rule.spellID)) or QUESTION
                row.icon:SetTexture(tex)
                local tag = (g.key == "global" and rule.class) and (" |cff888888[" .. rule.class .. "]|r") or ""
                row.text:SetText(("|cffffffff%s|r : %s%s"):format(rule.label or "?", RuleDesc(rule), tag))
                row.del:SetScript("OnClick", function()
                    table.remove(db.userRules, i)
                    if form.editIndex == i then form.editIndex = nil; if UpdateEditBanner then UpdateEditBanner() end end
                    ns.Rebuild()
                    RefreshList()
                end)
                row.edit:SetScript("OnClick", function() LoadRule(i) end)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
                row:Show()
                y = y - 36
            end
        end
    end
    parent:SetHeight(math.max(10, math.abs(y) + 6))
end

-- Met a jour le bandeau "Edition: <nom>" + le libelle du bouton Creer/Enregistrer.
function UpdateEditBanner()
    if not cfg or not cfg.editBanner then return end
    local db = ns.GetDB()
    local r = form.editIndex and db.userRules[form.editIndex]
    if r then
        cfg.editBanner:SetText("|cffffd100" .. string.format(L["Editing: %s"], r.label or "?") .. "|r")
        cfg.editBanner:Show()
        cfg.createBtn:SetText(L["Save"])
    else
        cfg.editBanner:Hide()
        cfg.createBtn:SetText(L["Create rule"])
    end
end

local function ResetForm()
    if not cfg then return end
    form.editIndex = nil
    form.pending = {}
    if cfg.labelBox then cfg.labelBox:SetText("") end
    if cfg.spellBox then cfg.spellBox:SetText("") end
    if cfg.keyTextBox then cfg.keyTextBox:SetText("") end
    if cfg.watchSpellBox then cfg.watchSpellBox:SetText("") end
    if cfg.valueBox then cfg.valueBox:SetText("50") end
    UpdateEditBanner()
    RefreshPending()
end

local function CreateRule()
    local db = ns.GetDB()
    local sid, _, sname = ResolveSpell(cfg.spellBox:GetText())
    local label = cfg.labelBox:GetText()
    if label == "" then label = sname or "Aura" end

    local rule = { label = label, spellID = sid }
    local keyText = cfg.keyTextBox:GetText()
    if keyText and keyText ~= "" then rule.keyText = keyText end
    local scope = form.scopeIndex or 1
    if scope == 2 then
        rule.class = select(2, UnitClass("player"))
    elseif scope == 3 then
        rule.class = select(2, UnitClass("player"))
        rule.spec = CurrentSpecID()
    end

    local rmode = RULETYPE_ITEMS[form.ruleTypeIndex].mode
    if rmode == "cooldown" then
        rule.cooldown = true
        rule.glow = form.glow and true or false  -- glow optionnel (modes pret/charges)
        local m = CDMODE_ITEMS[form.cdModeIndex].mode
        rule.glowWhenReady   = (m == "ready")
        rule.glowWhenCharged = (m == "charged")
    elseif rmode == "runes" then
        rule.combine = "OR"
        rule.glow = form.glow and true or false
        rule.conditions = { { kind = "runes",
            op = RUNEOP_ITEMS[form.runeOpIndex].op,
            value = tonumber(cfg.runeValueBox:GetText()) or 2 } }
    else
        local conds = {}
        if #form.pending > 0 then
            for _, c in ipairs(form.pending) do
                local t = {}
                for k, v in pairs(c) do t[k] = v end
                conds[#conds + 1] = t
            end
        else
            conds[1] = CurrentCondition()
        end
        rule.combine = COMBINE_ITEMS[form.combineIndex].combine
        rule.glow = form.glow and true or false
        rule.conditions = conds
    end

    if form.editIndex and db.userRules[form.editIndex] then
        rule.id = db.userRules[form.editIndex].id
        db.userRules[form.editIndex] = rule
        form.editIndex = nil
    else
        rule.id = "user" .. db.nextId
        db.nextId = db.nextId + 1
        table.insert(db.userRules, rule)
    end
    form.pending = {}
    ns.Rebuild()
    UpdateEditBanner()
    RefreshPending()
    RefreshList()
    cfg.labelBox:SetText("")
    cfg.spellBox:SetText("")
    cfg.keyTextBox:SetText("")
end

function LoadRule(i)
    local db = ns.GetDB()
    local rule = db.userRules[i]
    if not rule then return end
    form.editIndex = i
    cfg.labelBox:SetText(rule.label or "")
    cfg.spellBox:SetText(rule.spellID and tostring(rule.spellID) or "")
    cfg.keyTextBox:SetText(rule.keyText or "")
    form.scopeIndex = rule.spec and 3 or (rule.class and 2 or 1)
    form.glow = rule.glow ~= false
    if cfg.glowCheck then cfg.glowCheck:SetChecked(form.glow) end
    form.pending = {}

    if rule.cooldown then
        form.ruleTypeIndex = 2
        form.cdModeIndex = rule.glowWhenReady and 2 or (rule.glowWhenCharged and 3 or 1)
    elseif rule.conditions and rule.conditions[1] and rule.conditions[1].kind == "runes" then
        form.ruleTypeIndex = 3
        local c = rule.conditions[1]
        for k, it in ipairs(RUNEOP_ITEMS) do if it.op == c.op then form.runeOpIndex = k end end
        cfg.runeValueBox:SetText(tostring(c.value or 2))
    else
        form.ruleTypeIndex = 1
        form.combineIndex = (rule.combine == "AND") and 2 or 1
        if rule.conditions then
            for _, c in ipairs(rule.conditions) do
                local t = {}; for k, v in pairs(c) do t[k] = v end
                form.pending[#form.pending + 1] = t
            end
        elseif rule.source then
            form.pending[1] = { kind = "resource", source = rule.source,
                powerType = rule.powerType, op = rule.op, pct = rule.pct, value = rule.value }
        end
    end

    UpdateEditBanner()
    if cfg.RefreshDropdowns then cfg.RefreshDropdowns() end
    UpdateFields()
    if cfg.SelectTab then cfg.SelectTab(1) end
end

--------------------------------------------------------------------------------
-- Export / Import (par perso) : code texte partageable.
--------------------------------------------------------------------------------
local Serialize
Serialize = function(v)
    local t = type(v)
    if t == "number" then return tostring(v)
    elseif t == "boolean" then return v and "true" or "false"
    elseif t == "string" then return string.format("%q", v)
    elseif t == "table" then
        local parts = {}
        local n = #v
        for i = 1, n do parts[#parts + 1] = Serialize(v[i]) end
        for k, val in pairs(v) do
            local isArrayIdx = (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k))
            if not isArrayIdx then
                local key
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key = k .. "="
                else
                    key = "[" .. Serialize(k) .. "]="
                end
                parts[#parts + 1] = key .. Serialize(val)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "nil"
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Base64Encode(data)
    return ((data:gsub(".", function(x)
        local r, b = "", x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then return "" end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0) end
        return B64:sub(c + 1, c + 1)
    end) .. ({ "", "==", "=" })[#data % 3 + 1])
end
local function Base64Decode(data)
    data = tostring(data):gsub("[^" .. B64 .. "=]", "")
    return (data:gsub(".", function(x)
        if x == "=" then return "" end
        local r, f = "", (B64:find(x, 1, true) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and "1" or "0") end
        return r
    end):gsub("%d%d%d?%d?%d?%d?%d?%d?", function(x)
        if #x ~= 8 then return "" end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == "1" and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

local function ExportString()
    local db = ns.GetDB()
    local out = {}
    for _, rule in ipairs(db.userRules) do
        local copy = {}
        for k, val in pairs(rule) do
            if k ~= "id" and k ~= "check" then copy[k] = val end
        end
        if rule.id then
            copy._pos  = db.positions and db.positions[rule.id] or nil
            copy._size = db.sizes and db.sizes[rule.id] or nil
        end
        out[#out + 1] = copy
    end
    return "XPA1:" .. Base64Encode(Serialize(out))
end

local function ImportString(str)
    str = (str or ""):gsub("%s", "")
    local payload = str:match("^XPA1:(.+)$")
    if not payload then return false, L["unknown format (must start with XPA1:)"] end
    local lua = Base64Decode(payload)
    if not lua or lua == "" then return false, L["decode failed"] end
    local f = loadstring("return " .. lua)
    if not f then return false, L["unreadable data"] end
    if setfenv then setfenv(f, {}) end
    local ok, data = pcall(f)
    if not ok or type(data) ~= "table" then return false, L["invalid data"] end
    local db = ns.GetDB()
    db.positions = db.positions or {}
    db.sizes = db.sizes or {}
    db.nextId = db.nextId or 1
    local n = 0
    for _, rule in ipairs(data) do
        if type(rule) == "table" then
            local pos, size = rule._pos, rule._size
            rule._pos, rule._size = nil, nil
            rule.id = "user" .. db.nextId
            db.nextId = db.nextId + 1
            if type(pos) == "table" then db.positions[rule.id] = pos end
            if type(size) == "number" then db.sizes[rule.id] = size end
            table.insert(db.userRules, rule)
            n = n + 1
        end
    end
    pcall(ns.Rebuild)
    return true, n
end

-- Fenetre export/import (sombre).
local function EnsureIOPopup()
    if cfg.ioPopup then return cfg.ioPopup end
    local p = CreateFrame("Frame", "XpAuraIO", cfg, "BackdropTemplate")
    p:SetSize(440, 320)
    p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG")
    Skin(p, PAL.bg, { 0, 0, 0, 1 })
    p:EnableMouse(true); p:SetMovable(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.title:SetPoint("TOP", 0, -8); p.title:SetTextColor(C(PAL.text))
    p.note = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    p.note:SetPoint("TOPLEFT", 16, -28); p.note:SetPoint("TOPRIGHT", -16, -28); p.note:SetJustifyH("LEFT")

    -- Conteneur qui DECOUPE le texte : une longue chaine ne deborde plus sur les boutons.
    local holder = CreateFrame("Frame", nil, p, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", 16, -52)
    holder:SetPoint("BOTTOMRIGHT", -16, 48)
    Skin(holder, { 0.05, 0.05, 0.05, 1 }, PAL.border)
    holder:SetClipsChildren(true)   -- empeche le texte de l'editbox de depasser le cadre
    holder:EnableMouse(true)

    local box = CreateFrame("EditBox", nil, holder)
    box:SetMultiLine(true)
    -- Largeur bornee (TOPLEFT + TOPRIGHT) -> retour a la ligne ; hauteur auto, decoupee par le holder.
    box:SetPoint("TOPLEFT", 4, -4)
    box:SetPoint("TOPRIGHT", -4, -4)
    box:SetFontObject(ChatFontNormal)
    box:SetAutoFocus(false); box:SetMaxLetters(0)
    box:SetTextInsets(2, 2, 2, 2); box:SetTextColor(C(PAL.text))
    box:SetScript("OnEscapePressed", box.ClearFocus)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)  -- clic dans la zone vide = focus
    p.edit = box

    p.accept = MakeButton(p, 150); p.accept:ClearAllPoints(); p.accept:SetPoint("BOTTOMLEFT", 16, 14)
    p.close = MakeButton(p, 100, nil, nil, L["Close"]); p.close:ClearAllPoints(); p.close:SetPoint("BOTTOMRIGHT", -16, 14)
    p.close:SetScript("OnClick", function() p:Hide() end)
    cfg.ioPopup = p
    return p
end

local function ShowExport()
    local p = EnsureIOPopup()
    p.title:SetText(L["Export my rules"])
    p.note:SetText("|cffaad4ff" .. L["Ctrl+A to select all, Ctrl+C to copy, then share the code."] .. "|r")
    p.edit:SetText(ExportString())
    p.accept:Hide()
    p:Show()
    p.edit:SetFocus(); p.edit:HighlightText(); p.edit:SetCursorPosition(0)
end

local function ShowImport()
    local p = EnsureIOPopup()
    p.title:SetText(L["Import rules"])
    p.note:SetText("|cffaad4ff" .. L["Paste a code (Ctrl+V) then click Import. Only import codes you trust."] .. "|r")
    p.edit:SetText("")
    p.accept:Show(); p.accept:SetText(L["Import"])
    p.accept:SetScript("OnClick", function()
        local ok, res = ImportString(p.edit:GetText())
        if ok then
            Print(string.format(L["imported %d rule(s)."], res))
            RefreshList(); p:Hide()
        else
            Print("|cffff4040" .. string.format(L["import failed: %s"], tostring(res)) .. "|r")
        end
    end)
    p:Show(); p.edit:SetFocus()
end

--------------------------------------------------------------------------------
-- Construction de la fenetre (3 onglets)
--------------------------------------------------------------------------------
local function SelectTab(i)
    if not cfg or not cfg.tabs then return end
    for j, body in ipairs(cfg.tabs) do body:SetShown(j == i) end
    for j, t in ipairs(cfg.tabBtns) do t:SetActive(j == i) end
    cfg.currentTab = i
end

local function MakeTab(parent, w, label, onClick)
    local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
    t:SetSize(w, 24)
    Skin(t, PAL.elem, PAL.border)
    t.fs = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t.fs:SetPoint("CENTER"); t.fs:SetTextColor(C(PAL.text)); t.fs:SetText(label); FitText(t.fs, w - 8)
    t.active = false
    t.SetActive = function(self, a) self.active = a; self:SetBackdropColor(C(a and PAL.accent or PAL.elem)) end
    t:SetScript("OnEnter", function(s) if not s.active then s:SetBackdropColor(C(PAL.hover)) end end)
    t:SetScript("OnLeave", function(s) s:SetBackdropColor(C(s.active and PAL.accent or PAL.elem)) end)
    t:SetScript("OnClick", onClick)
    return t
end

local function BuildEditor(body)
    cfg.editorBody = body
    cfg.condWidgets, cfg.cdWidgets, cfg.runeWidgets, cfg.glowWidgets = {}, {}, {}, {}
    local function cw(w) cfg.condWidgets[#cfg.condWidgets + 1] = w; return w end
    local function cdw(w) cfg.cdWidgets[#cfg.cdWidgets + 1] = w; return w end
    local function rw(w) cfg.runeWidgets[#cfg.runeWidgets + 1] = w; return w end

    -- Type de regle
    MakeLabel(body, L["Rule type:"], 10, -12, 95)
    cfg.ruleTypeDD = MakeDropdown(body, 320, 110, -10, RULETYPE_ITEMS,
        function() return form.ruleTypeIndex end,
        function(i) form.ruleTypeIndex = i; UpdateFields() end)
    AddTooltip(cfg.ruleTypeDD, L["Rule type:"], "Choose what triggers the glow: resource/spell conditions, a spell cooldown, or DK runes.")

    -- Icone & nom
    MakeHeader(body, L["Icon & name"], 10, -44, 440)
    MakeLabel(body, L["Icon (name/ID):"], 10, -66, 95)
    cfg.spellBox = MakeEdit(body, 150, 110, -64)
    cfg.iconPreview = body:CreateTexture(nil, "ARTWORK")
    cfg.iconPreview:SetSize(24, 24); cfg.iconPreview:SetPoint("TOPLEFT", 268, -64)
    cfg.iconPreview:SetTexCoord(0.07, 0.93, 0.07, 0.93); cfg.iconPreview:SetTexture(QUESTION)
    cfg.spellBox:SetScript("OnTextChanged", function(self)
        local _, tex = ResolveSpell(self:GetText())
        cfg.iconPreview:SetTexture(tex or QUESTION)
    end)
    EnableSpellDrop(cfg.spellBox)
    MakeLabel(body, L["Name:"], 10, -94, 95)
    cfg.labelBox = MakeEdit(body, 150, 110, -92)
    MakeLabel(body, L["Text:"], 300, -94, 40)
    cfg.keyTextBox = MakeEdit(body, 50, 340, -92)

    -- Options de la regle
    MakeHeader(body, L["Rule options"], 10, -124, 440)
    MakeLabel(body, L["Scope:"], 10, -146, 60)
    cfg.scopeDD = MakeDropdown(body, 300, 110, -144, SCOPE_ITEMS,
        function() return form.scopeIndex end,
        function(i) form.scopeIndex = i end)
    AddTooltip(cfg.scopeDD, L["Scope:"], "Where this rule is active: everywhere, your class, or only your current spec.")
    cfg.glowCheck = MakeCheck(body, 10, -174, L["Add the glow (halo) when the icon lights up"], 380)
    cfg.glowCheck.onClick = function(self) form.glow = self:GetChecked() end
    cfg.glowWidgets[1] = cfg.glowCheck
    cfg.glowWidgets[2] = cfg.glowCheck.label
    AddTooltip(cfg.glowCheck, nil, "Add a pulsing halo around the icon when it lights up.")

    -- ===== Bloc CONDITIONS =====
    local condHeader = MakeHeader(body, L["Conditions"], 10, -204, 440)
    cw(condHeader); cw(condHeader.line)
    cw(MakeLabel(body, L["Show if:"], 10, -226, 90))
    cfg.combineDD = cw(MakeDropdown(body, 300, 110, -224, COMBINE_ITEMS,
        function() return form.combineIndex end,
        function(i) form.combineIndex = i end))
    cw(MakeLabel(body, "|cff66ccff" .. L["New condition:"] .. "|r", 10, -254, 320))
    cw(MakeLabel(body, L["Resource:"], 10, -278, 90))
    cfg.sourceDD = cw(MakeDropdown(body, 300, 110, -276, SOURCES,
        function() return form.sourceIndex end,
        function(i) form.sourceIndex = i; RefreshCondFields() end))
    AddTooltip(cfg.sourceDD, L["Resource:"], "Pick a health/power threshold, or a spell's availability (ready / not ready / charges full).")
    cfg.opLabel = cw(MakeLabel(body, L["Condition:"], 10, -306, 90))
    cfg.opDD = cw(MakeDropdown(body, 300, 110, -304, OP_ITEMS,
        function() return form.opIndex end,
        function(i) form.opIndex = i end))
    cfg.seuilLabel = cw(MakeLabel(body, L["Threshold:"], 10, -334, 90))
    cfg.typeDD = cw(MakeDropdown(body, 120, 110, -332, TYPE_ITEMS,
        function() return form.typeIndex end,
        function(i) form.typeIndex = i end))
    cfg.valueBox = cw(MakeEdit(body, 55, 240, -332))
    cfg.valueBox:SetText("50")
    AddTooltip(cfg.seuilLabel, L["Threshold:"], "Value to compare. For discrete resources (Holy Power, Combo Points...) it snaps between whole numbers.")
    cfg.watchLabel = cw(MakeLabel(body, L["Watched spell:"], 10, -306, 90))
    cfg.watchSpellBox = cw(MakeEdit(body, 180, 110, -304))
    EnableSpellDrop(cfg.watchSpellBox)
    cfg.watchHint = cw(MakeLabel(body, "|cff888888" .. L["(empty = icon's spell)"] .. "|r", 10, -334, 300))
    cfg.addCondBtn = cw(MakeButton(body, 200, 10, -362, L["+ Add condition"]))
    cfg.addCondBtn:SetScript("OnClick", function()
        table.insert(form.pending, CurrentCondition())
        RefreshPending()
    end)
    cw(MakeLabel(body, L["Added conditions:"], 10, -392, 320))

    -- ===== Bloc COOLDOWN =====
    cfg.cdNote = cdw(body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    cfg.cdNote:SetPoint("TOPLEFT", 10, -226); cfg.cdNote:SetWidth(440); cfg.cdNote:SetJustifyH("LEFT")
    cfg.cdNote:SetText("|cffaad4ff" .. L["The icon (above) follows the spell cooldown. Works in combat."] .. "|r")
    cdw(MakeLabel(body, L["Display:"], 10, -262, 90))
    cfg.cdModeDD = cdw(MakeDropdown(body, 300, 110, -260, CDMODE_ITEMS,
        function() return form.cdModeIndex end,
        function(i) form.cdModeIndex = i end))

    -- ===== Bloc RUNES =====
    cfg.runeNote = rw(body:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    cfg.runeNote:SetPoint("TOPLEFT", 10, -226); cfg.runeNote:SetWidth(440); cfg.runeNote:SetJustifyH("LEFT")
    cfg.runeNote:SetText("|cffaad4ff" .. L["Glow when the number of ready runes meets the threshold. Works in combat."] .. "|r")
    rw(MakeLabel(body, L["Runes ready:"], 10, -262, 90))
    cfg.runeOpDD = rw(MakeDropdown(body, 130, 110, -260, RUNEOP_ITEMS,
        function() return form.runeOpIndex end,
        function(i) form.runeOpIndex = i end))
    cfg.runeValueBox = rw(MakeEdit(body, 40, 246, -260))
    cfg.runeValueBox:SetText("2")
    rw(MakeLabel(body, "/ 6", 294, -260))

    -- Barre d'action (bas de l'onglet)
    cfg.editBanner = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cfg.editBanner:SetPoint("BOTTOMLEFT", 10, 38); cfg.editBanner:Hide()
    cfg.createBtn = MakeButton(body, 220, nil, nil, L["Create rule"])
    cfg.createBtn:ClearAllPoints(); cfg.createBtn:SetPoint("BOTTOMLEFT", 10, 8)
    cfg.createBtn:SetScript("OnClick", CreateRule)
    cfg.cancelBtn = MakeButton(body, 120, nil, nil, L["Cancel"])
    cfg.cancelBtn:ClearAllPoints(); cfg.cancelBtn:SetPoint("BOTTOMLEFT", 238, 8)
    cfg.cancelBtn:SetScript("OnClick", ResetForm)
end

local function BuildRulesTab(body)
    cfg.exportBtn = MakeButton(body, 150, 4, -6, L["Export all"])
    cfg.exportBtn:SetScript("OnClick", ShowExport)
    cfg.importBtn = MakeButton(body, 150, 162, -6, L["Import"])
    cfg.importBtn:SetScript("OnClick", ShowImport)

    local scroll = CreateFrame("ScrollFrame", "XpAuraRulesScroll", body, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -36)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(400, 10)
    scroll:SetScrollChild(child)
    cfg.rulesChild = child
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * 36)))
    end)
    StyleScroll(scroll)
end

local function BuildSettingsTab(body)
    MakeHeader(body, L["Global settings"], 10, -12, 440)
    cfg.combatCheck = MakeCheck(body, 10, -36, L["Show icons only in combat (global)"], 400)
    cfg.combatCheck.onClick = function(self) ns.GetDB().combatOnly = self:GetChecked() end
    AddTooltip(cfg.combatCheck, nil, "Hide all XpAura icons while you are out of combat.")

    MakeHeader(body, L["Placement grid"], 10, -74, 440)
    cfg.gridShowCheck = MakeCheck(body, 10, -98, L["Show grid in move mode"], 400)
    cfg.gridShowCheck.onClick = function(self)
        ns.GetDB().gridShow = self:GetChecked()
        if ns.UpdateGrid then ns.UpdateGrid() end
    end
    MakeLabel(body, L["Grid step:"], 10, -130, 108)
    cfg.gridStepDD = MakeDropdown(body, 110, 124, -128, GRIDSTEP_ITEMS,
        function()
            local s = ns.GetDB().gridSize or 20
            for i, it in ipairs(GRIDSTEP_ITEMS) do if it.step == s then return i end end
            return 3
        end,
        function(i)
            ns.GetDB().gridSize = GRIDSTEP_ITEMS[i].step
            if ns.RebuildGrid then ns.RebuildGrid() end
            if ns.UpdateGrid then ns.UpdateGrid() end
        end)
    cfg.gridSnapCheck = MakeCheck(body, 10, -160, L["Snap icons to grid"], 400)
    cfg.gridSnapCheck.onClick = function(self) ns.GetDB().gridSnap = self:GetChecked() end

    MakeHeader(body, L["Icon placement"], 10, -198, 440)
    cfg.unlockBtn = MakeButton(body, 200, 10, -222, L["Unlock (place)"])
    cfg.unlockBtn:SetScript("OnClick", function()
        ns.GetDB().locked = false
        if ns.UpdateGrid then ns.UpdateGrid() end
    end)
    cfg.lockBtn = MakeButton(body, 150, 220, -222, L["Lock"])
    cfg.lockBtn:SetScript("OnClick", function()
        ns.GetDB().locked = true
        ns.linkAnchor = nil
        if ns.UpdateGrid then ns.UpdateGrid() end
    end)

    MakeLabel(body, L["Shift+click icons to link or unlink; drag a member to move the whole group."], 10, -252, 440)
    cfg.newGroupBtn = MakeButton(body, 200, 10, -278, L["New group"])
    cfg.newGroupBtn:SetScript("OnClick", function()
        ns.linkAnchor = nil
        if ns.RefreshLinkVisuals then ns.RefreshLinkVisuals() end
    end)
    AddTooltip(cfg.newGroupBtn, nil, "Release the current anchor so your next Shift+clicks start a brand-new group.")
    cfg.unlinkAllBtn = MakeButton(body, 200, 220, -278, L["Unlink all"])
    cfg.unlinkAllBtn:SetScript("OnClick", function()
        local db = ns.GetDB()
        db.links = {}; db.nextGroupId = 1; ns.linkAnchor = nil
        if ns.RefreshLinkVisuals then ns.RefreshLinkVisuals() end
    end)
end

local function BuildConfig()
    cfg = CreateFrame("Frame", "XpAuraConfig", UIParent, "BackdropTemplate")
    cfg:SetSize(480, 600)
    cfg:SetPoint("CENTER")
    cfg:SetFrameStrata("HIGH")
    cfg:SetMovable(true); cfg:EnableMouse(true); cfg:SetClampedToScreen(true)
    Skin(cfg, PAL.bg, { 0, 0, 0, 1 })
    wipe(ddRefreshers)

    form = { ruleTypeIndex = 1, sourceIndex = 1, opIndex = 1, typeIndex = 1,
             combineIndex = 1, cdModeIndex = 1, runeOpIndex = 1, scopeIndex = 1,
             glow = false, pending = {} }

    -- Barre de titre
    local tb = CreateFrame("Frame", nil, cfg, "BackdropTemplate")
    tb:SetPoint("TOPLEFT", 1, -1); tb:SetPoint("TOPRIGHT", -1, -1); tb:SetHeight(26)
    Skin(tb, PAL.title, { 0, 0, 0, 0 })
    tb:EnableMouse(true); tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() cfg:StartMoving() end)
    tb:SetScript("OnDragStop", function() cfg:StopMovingOrSizing() end)
    local title = tb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 10, 0); title:SetText("XpAura"); title:SetTextColor(C(PAL.text))
    cfg.closeBtn = MakeButton(tb, 22, nil, nil, "X")
    cfg.closeBtn:ClearAllPoints(); cfg.closeBtn:SetPoint("RIGHT", -3, 0)
    cfg.closeBtn:SetScript("OnClick", function() cfg:Hide() end)

    -- Onglets
    cfg.tabs, cfg.tabBtns = {}, {}
    local names = { L["Editor"], L["My rules"], L["Settings"] }
    for i = 1, 3 do
        local t = MakeTab(cfg, 152, names[i], function() SelectTab(i) end)
        t:SetPoint("TOPLEFT", 6 + (i - 1) * 156, -30)
        cfg.tabBtns[i] = t
        local body = CreateFrame("Frame", nil, cfg)
        body:SetPoint("TOPLEFT", 6, -58)
        body:SetPoint("BOTTOMRIGHT", -6, 6)
        cfg.tabs[i] = body
    end
    cfg.SelectTab = SelectTab

    BuildEditor(cfg.tabs[1])
    BuildRulesTab(cfg.tabs[2])
    BuildSettingsTab(cfg.tabs[3])

    cfg.RefreshDropdowns = function()
        for _, fn in ipairs(ddRefreshers) do pcall(fn) end
    end

    UpdateFields()
    SelectTab(1)
    cfg:Hide()
end

function ns.OpenConfig()
    if not cfg then
        local ok, err = pcall(BuildConfig)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffXpAura|r: |cffff4040" .. L["menu error"] .. "|r: " .. tostring(err))
            cfg = nil
            return
        end
    end
    if cfg:IsShown() then
        cfg:Hide()
    else
        local db = ns.GetDB()
        cfg.combatCheck:SetChecked(db.combatOnly and true or false)
        if cfg.glowCheck then cfg.glowCheck:SetChecked(form and form.glow and true or false) end
        if cfg.gridShowCheck then cfg.gridShowCheck:SetChecked(db.gridShow and true or false) end
        if cfg.gridSnapCheck then cfg.gridSnapCheck:SetChecked(db.gridSnap and true or false) end
        RefreshScopeName()
        if cfg.RefreshDropdowns then cfg.RefreshDropdowns() end
        UpdateEditBanner()
        pcall(RefreshPending)
        local ok, err = pcall(RefreshList)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffXpAura|r: |cffff4040" .. L["list error"] .. "|r: " .. tostring(err))
        end
        cfg:Show()
    end
end

--------------------------------------------------------------------------------
-- Entree dans les Options Blizzard (Menu Jeu -> Options -> AddOns).
--------------------------------------------------------------------------------
function ns.SetupOptions()
    if ns._optionsDone or not Settings or not Settings.RegisterCanvasLayoutCategory then return end
    ns._optionsDone = true
    local panel = CreateFrame("Frame")
    panel.name = "XpAura"
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    fs:SetPoint("TOPLEFT", 16, -16); fs:SetText("XpAura")
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(220, 26); btn:SetPoint("TOPLEFT", 16, -52)
    btn:SetText(L["Open configuration"])
    btn:SetScript("OnClick", function() ns.OpenConfig() end)
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, "XpAura")
    if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
end

--------------------------------------------------------------------------------
-- Bouton minimap (sans lib) : clic gauche = config, clic droit = (de)verrouiller.
--------------------------------------------------------------------------------
function ns.SetupMinimap()
    if ns.minimapBtn or not Minimap then return end
    local db = ns.GetDB()
    db.minimap = db.minimap or {}
    db.minimap.angle = db.minimap.angle or 215

    local b = CreateFrame("Button", "XpAuraMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\Spell_Nature_StarFall")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetPoint("TOPLEFT")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function UpdatePos()
        local a = math.rad(db.minimap.angle or 215)
        local r = (Minimap:GetWidth() / 2) + 8
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
    end
    UpdatePos()

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local px, py = GetCursorPosition()
            px, py = px / scale, py / scale
            db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            UpdatePos()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local d = ns.GetDB()
            d.locked = not d.locked
            if ns.UpdateGrid then ns.UpdateGrid() end
            Print(d.locked and L["placement: locked"] or L["placement: unlocked (move the icons)"])
        else
            ns.OpenConfig()
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("XpAura")
        GameTooltip:AddLine(L["Left click: configuration"], 1, 1, 1)
        GameTooltip:AddLine(L["Right click: lock / unlock"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move the icon"], 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.minimapBtn = b
end
