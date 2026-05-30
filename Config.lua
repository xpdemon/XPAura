-- Config.lua
-- Menu in-game : creer/supprimer des regles.
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
-- Listes d'options
--------------------------------------------------------------------------------
local function PT(name) return Enum.PowerType and Enum.PowerType[name] end
-- Nom localise d'une ressource : constante globale Blizzard (deja traduite dans
-- chaque client) si dispo, sinon repli sur la traduction L (puis l'anglais).
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
    -- Disponibilite d'un sort (combat-safe). On choisit le sort surveille (vide = icone).
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

local RULETYPE_ITEMS = { { name = L["Glow on conditions (health/power)"], mode = "conditions" },
                         { name = L["Cooldown tracking (spell)"], mode = "cooldown" },
                         { name = L["Runes available (DK)"], mode = "runes" } }
-- Portee d'une regle : globale / classe actuelle / spe actuelle. Le nom de la spe (3e
-- option) est rafraichi dynamiquement par RefreshScopeName().
local SCOPE_ITEMS = { { name = L["Global (all classes)"] },
                      { name = L["Current class"] },
                      { name = L["Current spec"] } }

-- ID de spe (global, unique) courant, ou nil hors-jeu/indispo.
local function CurrentSpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return nil end
    local idx = GetSpecialization()
    if not idx then return nil end
    return (GetSpecializationInfo(idx))
end

-- Liste {id, name} des spes de la classe courante, dans l'ordre des index.
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

-- Met a jour le libelle de la 3e option de portee avec le nom de la spe courante.
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
    if c.kind == "aura" then  -- ancienne regle aura (hors combat seulement)
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
-- Constructeurs de widgets
--------------------------------------------------------------------------------
-- Reduit la police d'un FontString jusqu'a tenir dans maxW (plancher 8) : evite que
-- les traductions longues (de/ru...) debordent ou chevauchent le widget voisin.
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

-- maxW (optionnel) : largeur max ; au-dela, la police retrecit (anti-debordement i18n).
local function MakeLabel(parent, text, x, y, maxW)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    if maxW then FitText(fs, maxW) end
    return fs
end

local function MakeEdit(parent, w, x, y)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetPoint("TOPLEFT", x, y)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
end

local function MakeButton(parent, w, x, y, text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(text)
    if b.GetFontString then FitText(b:GetFontString(), w - 10) end
    return b
end

local ddRefreshers = {}  -- pour rafraichir le texte affiche apres un changement programme
local function MakeDropdown(parent, w, x, y, items, getIndex, setIndex)
    local ok, dd = pcall(function()
        local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        d:SetSize(w, 22)
        d:SetPoint("TOPLEFT", x, y)
        d:SetupMenu(function(_, root)
            for i, it in ipairs(items) do
                root:CreateRadio(it.name,
                    function() return getIndex() == i end,
                    function() setIndex(i); return MenuResponse and MenuResponse.Close or 2 end)
            end
        end)
        return d
    end)
    if ok and dd then
        ddRefreshers[#ddRefreshers + 1] = function()
            if dd.GenerateMenu then dd:GenerateMenu() end
            if dd.Text then FitText(dd.Text, w - 26) end  -- best-effort anti-debordement
        end
        return dd
    end

    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, y)
    local function setBtn() b:SetText(items[getIndex()].name); if b.GetFontString then FitText(b:GetFontString(), w - 10) end end
    setBtn()
    b:SetScript("OnClick", function()
        setIndex((getIndex() % #items) + 1)
        setBtn()
    end)
    ddRefreshers[#ddRefreshers + 1] = setBtn
    return b
end

-- Permet de remplir un EditBox par Maj+clic sur un sort du grimoire.
-- Au shift-clic, WoW appelle ChatEdit_InsertLink(lien) ; on intercepte (hooksecurefunc)
-- et on extrait le spellID du lien |Hspell:ID:...|h. Le clic sur le sort peut faire
-- PERDRE le focus du champ -> on memorise le dernier champ focus comme repli (robuste).
local spellLinkTargets = {}
local lastFocusedSpellBox
local spellDropHooked = false
local function EnableSpellDrop(editbox)
    if not editbox then return end
    spellLinkTargets[#spellLinkTargets + 1] = editbox
    editbox:HookScript("OnEditFocusGained", function(self) lastFocusedSpellBox = self end)
    -- Infobulle d'aide.
    editbox:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Shift-click a spell in your spellbook to fill this field."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    editbox:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if spellDropHooked then return end
    spellDropHooked = true
    -- Recoit le lien (spellbook -> ChatFrameUtil.InsertLink en 12.0 ; ChatEdit_InsertLink en legacy).
    local function onLink(text)
        if type(text) ~= "string" then return end
        local id = tonumber(text:match("spell:(%d+)"))
        if not id then return end
        ns._linkFires = (ns._linkFires or 0) + 1  -- diagnostic (cf. /xpaura test)
        ns._linkLastId = id
        -- 1) un champ a le focus ; sinon 2) le dernier champ focus encore visible.
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
        hooksecurefunc(ChatFrameUtil, "InsertLink", onLink)  -- grimoire Midnight (12.0)
    end
    if _G.ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", onLink)        -- voie historique
    end
end

--------------------------------------------------------------------------------
-- Etat + menu
--------------------------------------------------------------------------------
local cfg
local form, pendRows, ruleRows, headerRows
local LoadRule    -- forward declaration (defini plus bas, reference par RefreshList)
local RefreshList -- forward declaration (defini plus bas, appele par UpdateFields)

local function CurrentCondition()
    local s = SOURCES[form.sourceIndex]
    -- Condition "sort disponible" : surveille un sort precis (vide = sort de l'icone).
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

local function RefreshPending()
    pendRows = pendRows or {}
    for _, r in ipairs(pendRows) do r:Hide() end
    if RULETYPE_ITEMS[form.ruleTypeIndex].mode ~= "conditions" then return end
    local y = -344
    for i, c in ipairs(form.pending) do
        local row = pendRows[i]
        if not row then
            row = CreateFrame("Frame", nil, cfg)
            row:SetSize(360, 20)
            row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", 8, 0)
            row.text:SetWidth(280)
            row.text:SetJustifyH("LEFT")
            row.del = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.del:SetSize(22, 22)
            row.del:SetPoint("RIGHT", 0, 0)
            pendRows[i] = row
        end
        row.text:SetText("|cffaad4ff• " .. CondDesc(c) .. "|r")
        row.del:SetScript("OnClick", function()
            table.remove(form.pending, i)
            RefreshPending()
        end)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 16, y)
        row:Show()
        y = y - 22
    end
end

-- Pour les sources "sort dispo" : on masque Condition + Seuil (inapplicables) et on
-- montre a la place le champ "Sort surveille". Sinon l'inverse. Rien si pas en mode
-- conditions (UpdateFields a deja tout masque).
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

-- Affiche/masque le bloc conditions vs la note cooldown selon le type de regle.
local function UpdateFields()
    if not cfg then return end
    local mode = RULETYPE_ITEMS[form.ruleTypeIndex].mode
    for _, w in ipairs(cfg.condWidgets) do w:SetShown(mode == "conditions") end
    for _, w in ipairs(cfg.cdWidgets)   do w:SetShown(mode == "cooldown") end
    for _, w in ipairs(cfg.runeWidgets) do w:SetShown(mode == "runes") end
    -- Le glow concerne les modes a conditions (vie/puissance) et runes.
    if cfg.glowWidgets then
        local glowable = (mode == "conditions" or mode == "runes")
        for _, w in ipairs(cfg.glowWidgets) do w:SetShown(glowable) end
    end
    RefreshCondFields()
    -- Remonte en bloc la section basse sous le contenu du mode actif (supprime le vide).
    -- conditions = position de base (0) ; cooldown/runes finissent plus haut -> on remonte.
    if cfg.tailItems then
        local delta = (mode == "conditions") and 0 or (mode == "runes" and 206 or 228)
        local lowest = 0
        for _, it in ipairs(cfg.tailItems) do
            it.w:ClearAllPoints()
            local yy = it.y + delta
            it.w:SetPoint("TOPLEFT", it.x, yy)
            if yy < lowest then lowest = yy end
        end
        cfg.tailShift = delta
        -- La fenetre principale s'adapte juste au formulaire (la liste est dans le panneau lateral).
        cfg:SetHeight(math.abs(lowest) + 44)
        if RefreshList then RefreshList() end
    end
    RefreshPending()
end

-- Cree une ligne de regle (texte + boutons Editer/Suppr.) dans le panneau.
local function CreateRuleRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(350, 34)
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 6, 0)
    row.text:SetWidth(210)
    row.text:SetJustifyH("LEFT")
    row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.del:SetSize(62, 20)
    row.del:SetPoint("RIGHT", -4, 0)
    row.del:SetText(L["Delete"])
    if row.del.GetFontString then FitText(row.del:GetFontString(), 56) end
    row.edit = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.edit:SetSize(62, 20)
    row.edit:SetPoint("RIGHT", row.del, "LEFT", -4, 0)
    row.edit:SetText(L["Edit"])
    if row.edit.GetFontString then FitText(row.edit:GetFontString(), 56) end
    return row
end

-- Cree un en-tete d'accordeon cliquable (replie/deplie son groupe).
local function CreateRulesHeader(parent)
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(360, 22)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.25, 0.45, 0.75, 0.25)
    local hl = h:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10)
    h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h.text:SetPoint("LEFT", 6, 0)
    h.text:SetJustifyH("LEFT")
    h:SetScript("OnClick", function(self)
        cfg.collapsed[self.key] = not cfg.collapsed[self.key]
        RefreshList()
    end)
    return h
end

-- Liste des regles, groupee en accordeons : Global puis une section par spe de la classe.
function RefreshList()
    local db = ns.GetDB()
    ruleRows = ruleRows or {}
    headerRows = headerRows or {}
    cfg.collapsed = cfg.collapsed or {}
    for _, r in ipairs(ruleRows) do r:Hide() end
    for _, h in ipairs(headerRows) do h:Hide() end

    -- Groupes : Global, puis une entree par spe de la classe courante.
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
        header.text:SetText(("|cffffd100%s %s|r |cff888888(%d)|r"):format(
            collapsed and "+" or "-", g.name, #g.rules))
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
        header:Show()
        y = y - 24
        if not collapsed then
            for _, entry in ipairs(g.rules) do
                rN = rN + 1
                local row = ruleRows[rN] or CreateRuleRow(parent)
                ruleRows[rN] = row
                row:SetParent(parent)
                local i, rule = entry.idx, entry.rule
                -- Tag [CLASSE] seulement dans Global pour les regles classe-only (sinon implicite).
                local tag = (g.key == "global" and rule.class) and (" |cff888888[" .. rule.class .. "]|r") or ""
                row.text:SetText(("|cffffffff%s|r : %s%s"):format(rule.label or "?", RuleDesc(rule), tag))
                row.del:SetScript("OnClick", function()
                    table.remove(db.userRules, i)
                    if form.editIndex == i then form.editIndex = nil; cfg.createBtn:SetText(L["Create rule"]) end
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
    if cfg.rulesEmpty then cfg.rulesEmpty:Hide() end
    parent:SetHeight(math.max(10, math.abs(y) + 6))
end

-- Annule l'edition/creation en cours : remet le formulaire a un etat "nouvelle regle".
local function ResetForm()
    if not cfg then return end
    form.editIndex = nil
    form.pending = {}
    if cfg.labelBox then cfg.labelBox:SetText("") end
    if cfg.spellBox then cfg.spellBox:SetText("") end
    if cfg.keyTextBox then cfg.keyTextBox:SetText("") end
    if cfg.watchSpellBox then cfg.watchSpellBox:SetText("") end
    if cfg.valueBox then cfg.valueBox:SetText("50") end
    if cfg.createBtn then cfg.createBtn:SetText(L["Create rule"]) end
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
        rule.id = db.userRules[form.editIndex].id  -- conserve l'id (et la position sauvegardee)
        db.userRules[form.editIndex] = rule
        form.editIndex = nil
        cfg.createBtn:SetText(L["Create rule"])
    else
        rule.id = "user" .. db.nextId
        db.nextId = db.nextId + 1
        table.insert(db.userRules, rule)
    end
    form.pending = {}
    ns.Rebuild()
    RefreshPending()
    RefreshList()
    cfg.labelBox:SetText("")
    cfg.spellBox:SetText("")
    cfg.keyTextBox:SetText("")
end

-- Charge une regle existante dans le formulaire pour l'editer.
function LoadRule(i)
    local db = ns.GetDB()
    local rule = db.userRules[i]
    if not rule then return end
    form.editIndex = i
    cfg.labelBox:SetText(rule.label or "")
    cfg.spellBox:SetText(rule.spellID and tostring(rule.spellID) or "")
    cfg.keyTextBox:SetText(rule.keyText or "")
    form.scopeIndex = rule.spec and 3 or (rule.class and 2 or 1)
    -- Glow : ancienne regle sans champ -> consideree avec glow (retro-compat).
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
        elseif rule.source then  -- ancienne regle a 1 condition
            form.pending[1] = { kind = "resource", source = rule.source,
                powerType = rule.powerType, op = rule.op, pct = rule.pct, value = rule.value }
        end
    end

    cfg.createBtn:SetText(L["Save"])
    if cfg.RefreshDropdowns then cfg.RefreshDropdowns() end
    UpdateFields()
end

--------------------------------------------------------------------------------
-- Export / Import des regles (par perso) : code texte partageable.
--------------------------------------------------------------------------------
-- Serialise une valeur "donnee" (table de scalaires) en litteral Lua compact.
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

-- Base64 (encode/decode) standard, pour un code sur une seule ligne propre.
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

-- Construit le code d'export pour toutes les regles du perso (positions/tailles incluses).
local function ExportString()
    local db = ns.GetDB()
    local out = {}
    for _, rule in ipairs(db.userRules) do
        local copy = {}
        for k, val in pairs(rule) do
            if k ~= "id" and k ~= "check" then copy[k] = val end  -- id reattribue ; pas de fonctions
        end
        if rule.id then
            copy._pos  = db.positions and db.positions[rule.id] or nil
            copy._size = db.sizes and db.sizes[rule.id] or nil
        end
        out[#out + 1] = copy
    end
    return "XPA1:" .. Base64Encode(Serialize(out))
end

-- Importe un code : ajoute les regles au perso courant (sans ecraser). Retourne ok, nb/err.
local function ImportString(str)
    str = (str or ""):gsub("%s", "")
    local payload = str:match("^XPA1:(.+)$")
    if not payload then return false, L["unknown format (must start with XPA1:)"] end
    local lua = Base64Decode(payload)
    if not lua or lua == "" then return false, L["decode failed"] end
    local f = loadstring("return " .. lua)
    if not f then return false, L["unreadable data"] end
    if setfenv then setfenv(f, {}) end  -- bac a sable : aucun acces aux globals
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

-- Fenetre unique reutilisee pour exporter (lecture) et importer (saisie).
local function EnsureIOPopup()
    if cfg.ioPopup then return cfg.ioPopup end
    local p = CreateFrame("Frame", "XpAuraIO", cfg, "BasicFrameTemplateWithInset")
    p:SetSize(440, 320)
    p:SetPoint("CENTER")
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop", p.StopMovingOrSizing)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p.title:SetPoint("TOP", 0, -5)

    p.note = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    p.note:SetPoint("TOPLEFT", 16, -28)
    p.note:SetPoint("TOPRIGHT", -16, -28)
    p.note:SetJustifyH("LEFT")

    local box = CreateFrame("EditBox", nil, p)
    box:SetMultiLine(true)
    box:SetPoint("TOPLEFT", 16, -48)
    box:SetPoint("BOTTOMRIGHT", -16, 48)
    box:SetFontObject(ChatFontNormal)
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetTextInsets(4, 4, 4, 4)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    p.edit = box
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.5)
    bg:SetPoint("TOPLEFT", box, "TOPLEFT", -4, 4)
    bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 4, -4)

    p.accept = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.accept:SetSize(150, 24)
    p.accept:SetPoint("BOTTOMLEFT", 16, 14)

    p.close = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.close:SetSize(100, 24)
    p.close:SetPoint("BOTTOMRIGHT", -16, 14)
    p.close:SetText(L["Close"])
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
    p.edit:SetFocus()
    p.edit:HighlightText()
    p.edit:SetCursorPosition(0)
end

local function ShowImport()
    local p = EnsureIOPopup()
    p.title:SetText(L["Import rules"])
    p.note:SetText("|cffaad4ff" .. L["Paste a code (Ctrl+V) then click Import. Only import codes you trust."] .. "|r")
    p.edit:SetText("")
    p.accept:Show()
    p.accept:SetText(L["Import"])
    p.accept:SetScript("OnClick", function()
        local ok, res = ImportString(p.edit:GetText())
        if ok then
            Print(string.format(L["imported %d rule(s)."], res))
            RefreshList()
            p:Hide()
        else
            Print("|cffff4040" .. string.format(L["import failed: %s"], tostring(res)) .. "|r")
        end
    end)
    p:Show()
    p.edit:SetFocus()
end

local function BuildConfig()
    cfg = CreateFrame("Frame", "XpAuraConfig", UIParent, "BasicFrameTemplateWithInset")
    cfg:SetSize(440, 784)
    wipe(ddRefreshers)
    cfg:SetPoint("CENTER")
    cfg:SetFrameStrata("HIGH")
    cfg:SetMovable(true)
    cfg:EnableMouse(true)
    cfg:RegisterForDrag("LeftButton")
    cfg:SetScript("OnDragStart", cfg.StartMoving)
    cfg:SetScript("OnDragStop", cfg.StopMovingOrSizing)
    cfg:SetClampedToScreen(true)

    local title = cfg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("XpAura — Configuration")

    form = { ruleTypeIndex = 1, sourceIndex = 1, opIndex = 1, typeIndex = 1,
             combineIndex = 1, cdModeIndex = 1, runeOpIndex = 1, scopeIndex = 1,
             glow = false, pending = {} }

    -- Nom + Icone (le sort dont on prend l'icone, et la cible du suivi de cooldown)
    MakeLabel(cfg, L["Name:"], 16, -34, 98)
    cfg.labelBox = MakeEdit(cfg, 128, 120, -32)
    MakeLabel(cfg, L["Text:"], 256, -34, 50)
    cfg.keyTextBox = MakeEdit(cfg, 58, 312, -32)  -- texte sur l'icone (ex. "F1")

    MakeLabel(cfg, L["Icon (name/ID):"], 16, -62, 98)
    cfg.spellBox = MakeEdit(cfg, 150, 120, -60)
    cfg.iconPreview = cfg:CreateTexture(nil, "ARTWORK")
    cfg.iconPreview:SetSize(26, 26)
    cfg.iconPreview:SetPoint("TOPLEFT", 296, -56)
    cfg.iconPreview:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    cfg.iconPreview:SetTexture(QUESTION)
    cfg.spellBox:SetScript("OnTextChanged", function(self)
        local _, tex = ResolveSpell(self:GetText())
        cfg.iconPreview:SetTexture(tex or QUESTION)
    end)
    EnableSpellDrop(cfg.spellBox)

    -- Type de regle
    MakeLabel(cfg, L["Rule type:"], 16, -92, 98)
    cfg.ruleTypeDD = MakeDropdown(cfg, 300, 120, -96, RULETYPE_ITEMS,
        function() return form.ruleTypeIndex end,
        function(i) form.ruleTypeIndex = i; UpdateFields() end)

    -- ===== Bloc CONDITIONS =====
    cfg.condWidgets = {}
    local function cw(w) cfg.condWidgets[#cfg.condWidgets + 1] = w; return w end

    cw(MakeLabel(cfg, L["Show if:"], 16, -126, 98))
    cfg.combineDD = cw(MakeDropdown(cfg, 300, 120, -130, COMBINE_ITEMS,
        function() return form.combineIndex end,
        function(i) form.combineIndex = i end))

    cw(MakeLabel(cfg, "|cff66ccff" .. L["New condition:"] .. "|r", 16, -160, 320))
    cw(MakeLabel(cfg, L["Resource:"], 16, -186, 98))
    cfg.sourceDD = cw(MakeDropdown(cfg, 290, 120, -190, SOURCES,
        function() return form.sourceIndex end,
        function(i) form.sourceIndex = i; RefreshCondFields() end))
    cfg.opLabel = cw(MakeLabel(cfg, L["Condition:"], 16, -218, 98))
    cfg.opDD = cw(MakeDropdown(cfg, 290, 120, -222, OP_ITEMS,
        function() return form.opIndex end,
        function(i) form.opIndex = i end))
    cfg.seuilLabel = cw(MakeLabel(cfg, L["Threshold:"], 16, -250, 98))
    cfg.typeDD = cw(MakeDropdown(cfg, 120, 120, -254, TYPE_ITEMS,
        function() return form.typeIndex end,
        function(i) form.typeIndex = i end))
    cfg.valueBox = cw(MakeEdit(cfg, 55, 250, -254))
    cfg.valueBox:SetText("50")

    -- Champ "sort surveille" : remplace Condition/Seuil quand la source est un "sort dispo".
    -- Vide = surveille le sort de l'icone ; sinon on surveille ce sort precis (ex. icone
    -- Eclair lumineux qui s'allume quand Horion sacre n'est PAS pret).
    cfg.watchLabel = cw(MakeLabel(cfg, L["Watched spell:"], 16, -218, 98))
    cfg.watchSpellBox = cw(MakeEdit(cfg, 180, 120, -222))
    EnableSpellDrop(cfg.watchSpellBox)
    cfg.watchHint = cw(MakeLabel(cfg, "|cff888888" .. L["(empty = icon's spell)"] .. "|r", 16, -250))

    cfg.addCondBtn = cw(MakeButton(cfg, 200, 16, -286, L["+ Add this condition"]))
    cfg.addCondBtn:SetScript("OnClick", function()
        table.insert(form.pending, CurrentCondition())
        RefreshPending()
    end)
    cw(MakeLabel(cfg, L["Added conditions:"], 16, -318, 320))
    -- (lignes de conditions creees par RefreshPending a partir de y=-344)

    -- ===== Bloc COOLDOWN =====
    cfg.cdWidgets = {}
    local function cdw(w) cfg.cdWidgets[#cfg.cdWidgets + 1] = w; return w end
    cfg.cdNote = cdw(cfg:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    cfg.cdNote:SetPoint("TOPLEFT", 16, -130)
    cfg.cdNote:SetWidth(360)
    cfg.cdNote:SetJustifyH("LEFT")
    cfg.cdNote:SetText("|cffaad4ff" .. L["The icon (above) follows the spell cooldown. Works in combat."] .. "|r")
    cdw(MakeLabel(cfg, L["Display:"], 16, -168, 98))
    cfg.cdModeDD = cdw(MakeDropdown(cfg, 300, 120, -172, CDMODE_ITEMS,
        function() return form.cdModeIndex end,
        function(i) form.cdModeIndex = i end))

    -- ===== Bloc RUNES =====
    cfg.runeWidgets = {}
    local function rw(w) cfg.runeWidgets[#cfg.runeWidgets + 1] = w; return w end
    rw(cfg:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")):SetText("")
    cfg.runeNote = cfg.runeWidgets[1]
    cfg.runeNote:SetPoint("TOPLEFT", 16, -130)
    cfg.runeNote:SetWidth(360); cfg.runeNote:SetJustifyH("LEFT")
    cfg.runeNote:SetText("|cffaad4ff" .. L["Glow when the number of ready runes meets the threshold. Works in combat."] .. "|r")
    rw(MakeLabel(cfg, L["Runes ready:"], 16, -164, 98))
    cfg.runeOpDD = rw(MakeDropdown(cfg, 130, 120, -168, RUNEOP_ITEMS,
        function() return form.runeOpIndex end,
        function(i) form.runeOpIndex = i end))
    cfg.runeValueBox = rw(MakeEdit(cfg, 40, 256, -168))
    cfg.runeValueBox:SetText("2")
    rw(MakeLabel(cfg, "/ 6", 304, -166))

    -- ===== Section basse ("queue") : repositionnee en bloc par UpdateFields selon le mode.
    -- ti(widget, x, y) enregistre sa position de base et le renvoie.
    cfg.tailItems = {}
    local function ti(w, x, y)
        cfg.tailItems[#cfg.tailItems + 1] = { w = w, x = x, y = y }
        return w
    end

    -- Glow (halo lumineux) -- par regle, visible en modes conditions / runes.
    cfg.glowWidgets = {}
    cfg.glowCheck = CreateFrame("CheckButton", nil, cfg, "UICheckButtonTemplate")
    cfg.glowCheck:SetPoint("TOPLEFT", 16, -406)
    cfg.glowCheck:SetScript("OnClick", function(self)
        form.glow = self:GetChecked() and true or false
    end)
    cfg.glowWidgets[1] = ti(cfg.glowCheck, 16, -406)
    cfg.glowWidgets[2] = ti(MakeLabel(cfg, L["Add the glow (halo) when the icon lights up"], 44, -410, 382), 44, -410)

    -- Portee de la regle (globale / classe actuelle / spe actuelle) -- par regle.
    ti(MakeLabel(cfg, L["Scope:"], 16, -436, 68), 16, -436)
    cfg.scopeDD = MakeDropdown(cfg, 320, 90, -432, SCOPE_ITEMS,
        function() return form.scopeIndex end,
        function(i) form.scopeIndex = i end)
    ti(cfg.scopeDD, 90, -432)

    -- Afficher seulement en combat (global)
    cfg.combatCheck = CreateFrame("CheckButton", nil, cfg, "UICheckButtonTemplate")
    cfg.combatCheck:SetPoint("TOPLEFT", 16, -458)
    cfg.combatCheck:SetScript("OnClick", function(self)
        local db = ns.GetDB()
        db.combatOnly = self:GetChecked() and true or false
    end)
    ti(cfg.combatCheck, 16, -458)
    ti(MakeLabel(cfg, L["Show icons only in combat (global)"], 44, -462, 382), 44, -462)

    -- ===== Grille d'aide au placement (global) =====
    cfg.gridShowCheck = CreateFrame("CheckButton", nil, cfg, "UICheckButtonTemplate")
    cfg.gridShowCheck:SetPoint("TOPLEFT", 16, -486)
    cfg.gridShowCheck:SetScript("OnClick", function(self)
        ns.GetDB().gridShow = self:GetChecked() and true or false
        if ns.UpdateGrid then ns.UpdateGrid() end
    end)
    ti(cfg.gridShowCheck, 16, -486)
    ti(MakeLabel(cfg, L["Show grid in move mode"], 44, -490, 382), 44, -490)

    ti(MakeLabel(cfg, L["Grid step:"], 16, -514, 108), 16, -514)
    cfg.gridStepDD = MakeDropdown(cfg, 110, 130, -518, GRIDSTEP_ITEMS,
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
    ti(cfg.gridStepDD, 130, -518)

    cfg.gridSnapCheck = CreateFrame("CheckButton", nil, cfg, "UICheckButtonTemplate")
    cfg.gridSnapCheck:SetPoint("TOPLEFT", 16, -542)
    cfg.gridSnapCheck:SetScript("OnClick", function(self)
        ns.GetDB().gridSnap = self:GetChecked() and true or false
    end)
    ti(cfg.gridSnapCheck, 16, -542)
    ti(MakeLabel(cfg, L["Snap icons to grid"], 44, -546, 382), 44, -546)

    -- Creer / Enregistrer la regle
    cfg.createBtn = MakeButton(cfg, 200, 90, -572, L["Create rule"])
    cfg.createBtn:SetScript("OnClick", CreateRule)
    ti(cfg.createBtn, 90, -572)
    -- Annuler : sort du mode edition / vide le formulaire (marche arriere si erreur).
    cfg.cancelBtn = MakeButton(cfg, 120, 298, -572, L["Cancel"])
    cfg.cancelBtn:SetScript("OnClick", ResetForm)
    ti(cfg.cancelBtn, 298, -572)

    -- Verrouiller / Deverrouiller le placement des icones (global, comme /xpaura lock/unlock).
    cfg.unlockBtn = MakeButton(cfg, 185, 16, -606, L["Unlock (place)"])
    cfg.unlockBtn:SetScript("OnClick", function()
        ns.GetDB().locked = false
        if ns.UpdateGrid then ns.UpdateGrid() end
    end)
    ti(cfg.unlockBtn, 16, -606)
    cfg.lockBtn = MakeButton(cfg, 185, 211, -606, L["Lock"])
    cfg.lockBtn:SetScript("OnClick", function()
        ns.GetDB().locked = true
        if ns.UpdateGrid then ns.UpdateGrid() end
    end)
    ti(cfg.lockBtn, 211, -606)

    -- ===== Panneau lateral "Mes regles" (ancre a droite, liste defilante) =====
    local side = CreateFrame("Frame", "XpAuraRulesPanel", cfg, "BasicFrameTemplateWithInset")
    side:SetSize(420, 560)
    side:SetPoint("TOPLEFT", cfg, "TOPRIGHT", -4, 0)
    side:SetFrameStrata("HIGH")
    if side.CloseButton then side.CloseButton:Hide() end
    cfg.side = side

    local stitle = side:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    stitle:SetPoint("TOP", 0, -5)
    stitle:SetText(L["My rules"])

    cfg.exportBtn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    cfg.exportBtn:SetSize(150, 22)
    cfg.exportBtn:SetPoint("TOPLEFT", 12, -28)
    cfg.exportBtn:SetText(L["Export all"])
    cfg.exportBtn:SetScript("OnClick", ShowExport)

    cfg.importBtn = CreateFrame("Button", nil, side, "UIPanelButtonTemplate")
    cfg.importBtn:SetSize(150, 22)
    cfg.importBtn:SetPoint("LEFT", cfg.exportBtn, "RIGHT", 8, 0)
    cfg.importBtn:SetText(L["Import"])
    cfg.importBtn:SetScript("OnClick", ShowImport)

    local scroll = CreateFrame("ScrollFrame", "XpAuraRulesScroll", side, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -56)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(370, 10)
    scroll:SetScrollChild(child)
    cfg.rulesChild = child
    cfg.rulesScroll = scroll
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetVerticalScrollRange() or 0
        local cur = self:GetVerticalScroll()
        self:SetVerticalScroll(math.max(0, math.min(range, cur - delta * 36)))
    end)

    cfg.rulesEmpty = child:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    cfg.rulesEmpty:SetPoint("TOPLEFT", 6, -8)
    cfg.rulesEmpty:SetText(L["(no rule — create one on the left)"])
    cfg.rulesEmpty:Hide()

    cfg.RefreshDropdowns = function()
        for _, fn in ipairs(ddRefreshers) do pcall(fn) end
    end

    UpdateFields()
    cfg:Hide()  -- creee masquee : OpenConfig la montre (sinon il faut 2 commandes).
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
        pcall(RefreshPending)
        local ok, err = pcall(RefreshList)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffXpAura|r: |cffff4040" .. L["list error"] .. "|r: " .. tostring(err))
        end
        cfg:Show()
    end
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

    -- Rayon = demi-largeur reelle de la minimap (+ marge) -> sur la PERIPHERIE,
    -- quelle que soit la taille de la minimap (la valeur fixe tombait dedans).
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
