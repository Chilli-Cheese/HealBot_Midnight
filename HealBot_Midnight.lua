-------------------------------------------------------------------------------
-- HealBotMidnight - Core + Frames
-- Moderner HealBot-Ersatz fuer WoW Midnight (Patch 12.0.1)
-- Verwendet KEINE GetRaidRosterInfo() - nur sichere Midnight-APIs
--
-- Gefixte APIs:
--   Debuffs:        C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
--   Heal-Predict:   UnitGetIncomingHeals() mit Nil-Guard
--   Roster:         GROUP_ROSTER_UPDATE + UnitExists() (kein GetRaidRosterInfo)
--   Click-Cast:     SecureActionButtonTemplate mit InCombatLockdown()-Schutz
-------------------------------------------------------------------------------

-- Globale Addon-Tabelle
HealBotMidnight = HealBotMidnight or {}
local HBM = HealBotMidnight

-- Lokalisierung (HBM_L wird von HealBot_Midnight_Locale.lua gesetzt, laedt zuerst)
local L = HBM_L

-- Standard-Einstellungen
local DEFAULTS = {
    frameWidth = 120,
    frameHeight = 40,
    spells = {
        -- [Modifier..Button] = Spellname (4 Modifier x 3 Buttons = 12 Slots)
        ["LeftButton"]       = "",   -- Linksklick
        ["ShiftLeftButton"]  = "",   -- Shift+Links
        ["CtrlLeftButton"]   = "",   -- Ctrl+Links
        ["AltLeftButton"]    = "",   -- Alt+Links
        ["RightButton"]      = "",   -- Rechtsklick
        ["ShiftRightButton"] = "",   -- Shift+Rechts
        ["CtrlRightButton"]  = "",   -- Ctrl+Rechts
        ["AltRightButton"]   = "",   -- Alt+Rechts
        ["MiddleButton"]      = "",  -- Mittelklick
        ["ShiftMiddleButton"] = "",  -- Shift+Mitte
        ["CtrlMiddleButton"]  = "",  -- Ctrl+Mitte
        ["AltMiddleButton"]   = "",  -- Alt+Mitte
        ["Button4"]           = "",  -- Maustaste 4
        ["ShiftButton4"]      = "",  -- Shift+Taste4
        ["CtrlButton4"]       = "",  -- Ctrl+Taste4
        ["AltButton4"]        = "",  -- Alt+Taste4
        ["Button5"]           = "",  -- Maustaste 5
        ["ShiftButton5"]      = "",  -- Shift+Taste5
        ["CtrlButton5"]       = "",  -- Ctrl+Taste5
        ["AltButton5"]        = "",  -- Alt+Taste5
    },
    anchorX = 100,
    anchorY = -200,
    visible = true,
    columns = 8,             -- Spalten im Raid-Layout
    showOptionsButton = true, -- Optionen-Button im Hauptfenster anzeigen
    classColors = false,     -- Klassenfarben fuer Lebenspunktbalken
    showHPNumbers = true,    -- HP als Zahl auf Unit-Frames anzeigen
    profiles = {},           -- Benannte Konfigurations-Profile
}

-- Lokale Referenzen fuer Performance (nur APIs die in 12.0.1 existieren)
local UnitExists = UnitExists
local UnitName = UnitName
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
-- UnitInRange: Kann in manchen WoW-Versionen nil sein oder fehlen
-- Wird daher NICHT gecacht, sondern sicher per Wrapper aufgerufen
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local GetNumGroupMembers = GetNumGroupMembers
local InCombatLockdown = InCombatLockdown

-- Hilfsfontstring zum Lesen von secret numbers via SetFormattedText (C-Funktion)
-- WICHTIG: FontString darf NICHT Hide() sein - GetText() gibt sonst nil zurueck!
-- Stattdessen: Alpha=0 + weit ausserhalb des Bildschirms
-- WICHTIG: SetAlpha(0) macht GetText() kaputt (gibt nil zurueck)!
-- Stattdessen: 1x1px FontString komplett ausserhalb des Bildschirms, OHNE Alpha-Aenderung
local _secretNumFS = nil
local function ReadSecretNumber(n)
    if not _secretNumFS then
        _secretNumFS = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        _secretNumFS:SetSize(1, 1)
        _secretNumFS:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -200, -200)
    end
    local ok = pcall(_secretNumFS.SetFormattedText, _secretNumFS, "%d", n)
    if not ok then return 0 end
    return tonumber(_secretNumFS:GetText()) or 0
end

-- Interne Variablen
local unitFrames = {}        -- Tabelle aller erstellten Unit-Frames
local activeUnits = {}       -- Aktuell aktive Units (unit IDs)
local mainContainer = nil    -- Haupt-Container-Frame
local isVisible = true       -- Sichtbarkeit der Frames
local rosterPending = false  -- Flag: Roster-Scan nach Kampfende noetig

-- Debuff-Typ Farben fuer Rahmen-Highlighting
local DEBUFF_COLORS = {
    Magic   = { r = 0.6, g = 0.2, b = 0.8 },  -- Lila
    Poison  = { r = 0.0, g = 0.8, b = 0.0 },  -- Gruen
    Disease = { r = 0.6, g = 0.4, b = 0.2 },  -- Braun
    Curse   = { r = 1.0, g = 0.5, b = 0.0 },  -- Orange
}

-- Debuff-Prioritaet (hoeher = wichtiger)
local DEBUFF_PRIORITY = {
    Magic   = 4,
    Poison  = 3,
    Disease = 2,
    Curse   = 1,
}

-- Forward-Deklarationen fuer lokale Funktionen
local UpdateHealPrediction
local UpdateDebuffs
local ScanGroupRoster

-------------------------------------------------------------------------------
-- Hilfsfunktionen
-------------------------------------------------------------------------------

-- Gibt die Health-Bar-Farbe basierend auf dem Prozentsatz zurueck
local function GetHealthColor(pct)
    if pct > 0.5 then
        -- Gruen zu Gelb (1.0 -> 0.5)
        local g = 1.0
        local r = (1.0 - pct) * 2.0
        return r, g, 0
    else
        -- Gelb zu Rot (0.5 -> 0.0)
        local r = 1.0
        local g = pct * 2.0
        return r, g, 0
    end
end

-- Gibt die Balkenfarbe zurueck: Klassenfarbe ODER Gradient
-- pct kann nil sein (secret values) -> Fallback zu Gruen
local function GetBarColorRGB(unit, pct)
    if HealBotMidnightDB and HealBotMidnightDB.classColors then
        local ok, _, classFile = pcall(UnitClass, unit)
        if ok and classFile and RAID_CLASS_COLORS then
            local cc = RAID_CLASS_COLORS[classFile]
            if cc then return cc.r, cc.g, cc.b end
        end
    end
    if pct then return GetHealthColor(pct) end
    return 0.2, 0.7, 0.2
end

-- Formatiert Health-Werte als Prozentzahl
local function FormatHealthPercent(health, maxHealth)
    if maxHealth == 0 then return "0%" end
    return string.format("%d%%", (health / maxHealth) * 100)
end

-- Formatiert HP-Werte kompakt: 45200 -> "45.2k", 1230000 -> "1.2M"
local function FormatHP(value)
    local v = math.floor(value + 0.5)
    if v >= 1000000 then
        return string.format("%.1fM", v / 1000000)
    elseif v >= 1000 then
        return string.format("%.1fk", v / 1000)
    else
        return tostring(v)
    end
end

-------------------------------------------------------------------------------
-- Haupt-Container erstellen
-------------------------------------------------------------------------------

local function CreateMainContainer()
    if mainContainer then return mainContainer end

    local f = CreateFrame("Frame", "HBMContainer", UIParent)
    f:SetSize(800, 600)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT",
        HealBotMidnightDB.anchorX, HealBotMidnightDB.anchorY)

    -- Container verschiebbar machen
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Position speichern
        local _, _, _, x, y = self:GetPoint()
        HealBotMidnightDB.anchorX = x
        HealBotMidnightDB.anchorY = y
    end)

    -- Hintergrund (halbtransparent)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.6)

    -- Titelleiste
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -2)
    title:SetText("HealBot Midnight")
    title:SetTextColor(0.5, 0.8, 1.0)

    -- Optionen-Button (kleiner Zahnrad-/Konfig-Knopf in der Titelleiste)
    local optBtn = CreateFrame("Button", "HBMOptionsButton", f)
    optBtn:SetSize(16, 16)
    optBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -1)

    local optBtnTex = optBtn:CreateTexture(nil, "ARTWORK")
    optBtnTex:SetAllPoints()
    optBtnTex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    optBtn.normalTex = optBtnTex

    local optBtnHL = optBtn:CreateTexture(nil, "HIGHLIGHT")
    optBtnHL:SetAllPoints()
    optBtnHL:SetColorTexture(1, 1, 1, 0.25)

    optBtn:SetScript("OnClick", function()
        if HBM.ToggleConfig then
            HBM.ToggleConfig()
        end
    end)
    optBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["HealBot Midnight\nOpen Configuration"], 1, 1, 1)
        GameTooltip:Show()
    end)
    optBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.optionsButton = optBtn
    HBM.optionsButton = optBtn

    mainContainer = f
    return f
end

-------------------------------------------------------------------------------
-- Einzelnen Unit-Frame erstellen (SecureActionButton fuer Click-Casting)
-------------------------------------------------------------------------------

local function CreateUnitFrame(unitID, index)
    local width = HealBotMidnightDB.frameWidth
    local height = HealBotMidnightDB.frameHeight

    -- SecureActionButtonTemplate fuer geschuetztes Click-Casting
    local frameName = "HBMUnitFrame_" .. index
    local f = CreateFrame("Button", frameName, mainContainer,
        "SecureActionButtonTemplate")
    f:SetSize(width, height)

    -- Attribute fuer Click-Casting werden spaeter gesetzt
    f:SetAttribute("unit", unitID)
    f:SetAttribute("type1", "spell")  -- Linksklick = Spell
    f:SetAttribute("type2", "spell")  -- Rechtsklick = Spell

    -- RegisterForClicks erlaubt alle Maustasten
    f:RegisterForClicks("AnyUp", "AnyDown")

    -- Rahmen (Border)
    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    border:SetFrameLevel(f:GetFrameLevel() + 2)
    f.border = border

    -- Hintergrund
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.9)
    f.bg = bg

    -- Health Bar
    local healthBar = CreateFrame("StatusBar", nil, f)
    healthBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    healthBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(0, 1, 0)
    healthBar:SetMinMaxValues(0, 100)
    healthBar:SetValue(100)
    healthBar:SetFrameLevel(f:GetFrameLevel() + 1)
    f.healthBar = healthBar

    -- Health Bar Hintergrund (dunkel)
    local healthBg = healthBar:CreateTexture(nil, "BACKGROUND")
    healthBg:SetAllPoints()
    healthBg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
    f.healthBg = healthBg

    -- Shine-Effekt: subtiler Glanz an der Oberkante (HealBot-typischer Glass-Look)
    local shine = healthBar:CreateTexture(nil, "OVERLAY")
    shine:SetHeight(2)
    shine:SetPoint("TOPLEFT",  healthBar, "TOPLEFT",  0, 0)
    shine:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
    shine:SetColorTexture(1, 1, 1, 0.13)
    f.shine = shine

    -- Heal-Prediction Bar (heller Balken ueber der Health Bar)
    local predBar = CreateFrame("StatusBar", nil, f)
    predBar:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    predBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    predBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    predBar:SetStatusBarColor(0.5, 1.0, 0.5, 0.4)
    predBar:SetMinMaxValues(0, 100)
    predBar:SetValue(0)
    predBar:SetFrameLevel(f:GetFrameLevel() + 1)
    f.predBar = predBar

    -- Spielername Text (leicht nach oben verschoben fuer zweizeiliges Layout)
    local nameText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", healthBar, "LEFT", 4, 5)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1)
    nameText:SetShadowOffset(1, -1)
    f.nameText = nameText

    -- HP-Wert Text: zeigt formatierte HP-Zahl ("45.2k") oder Prozentzahl ("75%")
    local hpValueText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hpValueText:SetPoint("RIGHT", healthBar, "RIGHT", -4, 5)
    hpValueText:SetJustifyH("RIGHT")
    hpValueText:SetTextColor(1, 1, 1)
    hpValueText:SetShadowOffset(1, -1)
    f.hpValueText = hpValueText

    -- HP-Fehlbetrag Text: zeigt fehlendes HP ("-14.2k") am unteren Rand
    -- Nur sichtbar wenn showHPNumbers aktiv und Frame >= 34px hoch
    local deficitText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deficitText:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -4, 3)
    deficitText:SetJustifyH("RIGHT")
    deficitText:SetTextColor(1, 0.5, 0.15)  -- warmes Orange
    deficitText:SetShadowOffset(1, -1)
    deficitText:SetText("")
    f.deficitText = deficitText

    -- Status-Text (DEAD / OOR / DC) - mittig
    local statusText = healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("CENTER", healthBar, "CENTER", 0, -3)
    statusText:SetTextColor(1, 0, 0)
    statusText:SetShadowOffset(1, -1)
    statusText:SetText("")
    f.statusText = statusText

    -- Debuff-Icon (kleines Symbol rechts unten)
    local debuffIcon = healthBar:CreateTexture(nil, "OVERLAY")
    debuffIcon:SetSize(16, 16)
    debuffIcon:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", -2, 2)
    debuffIcon:Hide()
    f.debuffIcon = debuffIcon

    -- HealBot-Style Tooltip bei Mouseover
    f:SetScript("OnEnter", function(self)
        local unit = self.unitID
        if not unit or not UnitExists(unit) then return end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()

        -- Name + Klasse (klassenfarbe)
        local uName = UnitName(unit) or "?"
        local _, classFile = UnitClass(unit)
        local cc = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
        if cc then
            GameTooltip:AddLine(uName, cc.r, cc.g, cc.b)
        else
            GameTooltip:AddLine(uName, 1, 1, 1)
        end

        -- Klasse / Level / Rasse
        local level = UnitLevel(unit) or "?"
        local race  = UnitRace(unit)  or "?"
        local class = UnitClass(unit) or "?"
        GameTooltip:AddLine(class .. "  |cFFAAAAAA" .. race .. "  Lv." .. level .. "|r", 1, 0.82, 0)

        -- Zone
        local zone = GetZoneText and GetZoneText() or ""
        if zone ~= "" then
            GameTooltip:AddLine(zone, 0.7, 0.7, 0.7)
        end

        GameTooltip:AddLine(" ")

        -- HP: hpMax direkt (regulaere Zahl), hp via mehrere Ansaetze
        local hpMax = 0
        pcall(function() hpMax = math.floor(UnitHealthMax(unit)) end)
        local hp = 0
        -- Versuch 1: Fill-Textur-Breite
        pcall(function()
            if hpMax > 0 then
                local fillTex = self.healthBar:GetStatusBarTexture()
                local barW    = self.healthBar:GetWidth()
                if fillTex and barW and barW > 0 then
                    local fillW = fillTex:GetWidth()
                    if fillW and fillW > 0 and fillW <= barW then
                        hp = math.floor((fillW / barW) * hpMax)
                    end
                end
            end
        end)
        -- Versuch 2: GetValue()
        if hp == 0 then
            pcall(function()
                local v = self.healthBar:GetValue()
                if v and v > 0 then hp = math.floor(v) end
            end)
        end
        -- Versuch 3: ReadSecretNumber
        if hp == 0 then
            hp = ReadSecretNumber(UnitHealth(unit))
        end
        local hpPct = (hpMax > 0 and hp > 0) and math.floor(hp / hpMax * 100) or 0
        GameTooltip:AddDoubleLine(
            "HP:",
            string.format("%s / %s  |cFFAAAAAA(%d%%)|r", FormatHP(hp), FormatHP(hpMax), hpPct),
            0.6, 1, 0.6,   1, 1, 1
        )

        -- Mana / Energie / Rage etc.
        local powerType = UnitPowerType(unit)
        if powerType then
            local power, powerMax = 0, 0
            -- Getrennte pcalls: UnitPowerMax ist regulaer (wie UnitHealthMax),
            -- UnitPower ist secret - beide separat damit Max auch bei Fehler gesetzt wird
            pcall(function() powerMax = math.floor(UnitPowerMax(unit, powerType)) end)
            pcall(function() power    = math.floor(UnitPower(unit, powerType))    end)
            local powerName = (PowerBarColor and PowerBarColor[powerType] and
                               _G["POWER_TYPE_" .. (powerType or "")] ) or "Mana"
            local pc = PowerBarColor and PowerBarColor[powerType]
            local pr, pg, pb = 0.3, 0.5, 1
            if pc then pr, pg, pb = pc.r, pc.g, pc.b end
            GameTooltip:AddDoubleLine(
                (powerName ~= "" and powerName or "Power") .. ":",
                string.format("%s / %s", FormatHP(power), FormatHP(powerMax)),
                pr, pg, pb,   1, 1, 1
            )
        end

        -- Spell-Bindings: alle 12 Keys dynamisch (via HBM.GetBindingKeys)
        if HealBotMidnightDB and HealBotMidnightDB.spells
                and HBM.GetBindingKeys and HBM.GetBindingLabel then
            local spells = HealBotMidnightDB.spells
            local shown = false
            for _, key in ipairs(HBM.GetBindingKeys()) do
                local spell = spells[key]
                if spell and spell ~= "" then
                    if not shown then
                        GameTooltip:AddLine(" ")
                        shown = true
                    end
                    GameTooltip:AddDoubleLine(
                        HBM.GetBindingLabel(key) .. ":", spell,
                        1, 0.82, 0,   0.5, 1, 0.5)
                end
            end
            if not shown then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFF888888(keine Spells zugewiesen)|r")
            end
        end

        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Interne Referenz auf Unit
    f.unitID = unitID
    f:Hide()

    return f
end

-------------------------------------------------------------------------------
-- Unit-Frame aktualisieren
-------------------------------------------------------------------------------

local function UpdateUnitFrame(frame)
    local unit = frame.unitID
    if not unit or not UnitExists(unit) then
        frame:Hide()
        return
    end

    frame:Show()

    -- In Midnight geben UnitHealth/UnitHealthMax "secret number" Werte zurueck
    -- fuer andere Spieler. Diese duerfen NICHT mit Lua-Arithmetic verarbeitet
    -- werden, aber C-seitige Widget-Funktionen (SetValue etc.) akzeptieren sie.
    local health = UnitHealth(unit)
    local maxHealth = UnitHealthMax(unit)
    local isDead = UnitIsDeadOrGhost(unit)
    local name = UnitName(unit) or "Unbekannt"

    -- Range-Check: Konservativ - nur OOR anzeigen wenn wir SICHER sind
    -- CheckInteractDistance gibt im Kampf oft false fuer alle Units zurueck
    -- -> Nur OOR wenn: Unit connected UND Range-Check explizit false (nicht nil)
    local isOutOfRange = false
    local isDisconnected = false
    if unit ~= "player" then
        -- Erst pruefen ob der Spieler ueberhaupt online ist
        if UnitIsConnected and not UnitIsConnected(unit) then
            isDisconnected = true
        elseif CheckInteractDistance then
            local ok, canInteract = pcall(CheckInteractDistance, unit, 4)
            -- Nur OOR wenn pcall erfolgreich UND Ergebnis explizit false
            -- nil = unbekannt/nicht pruefbar -> als "in range" werten
            if ok and canInteract == false then
                isOutOfRange = true
            end
        end
    end
    if isDisconnected then
        frame:SetAlpha(0.4)
        frame.statusText:SetText("DC")
        frame.statusText:SetTextColor(0.5, 0.5, 0.5)
    elseif isOutOfRange then
        frame:SetAlpha(0.4)
        frame.statusText:SetText("OOR")
        frame.statusText:SetTextColor(0.7, 0.7, 0.7)
    else
        frame:SetAlpha(1.0)
        if isDead then
            frame.healthBar:SetMinMaxValues(0, 1)
            frame.healthBar:SetValue(0)
            frame.healthBar:SetStatusBarColor(0.3, 0.3, 0.3)
            frame.statusText:SetText("DEAD")
            frame.statusText:SetTextColor(1, 0, 0)
            frame.nameText:SetText(name)
            frame.hpValueText:SetText("")
            frame.deficitText:Hide()
            frame.predBar:SetMinMaxValues(0, 1)
            frame.predBar:SetValue(0)
            frame.debuffIcon:Hide()
            frame.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            return
        else
            frame.statusText:SetText("")
        end
    end

    -- Health-Bar: Secret Values direkt an C-seitige Widget-Funktionen uebergeben
    pcall(frame.healthBar.SetMinMaxValues, frame.healthBar, 0, maxHealth)
    pcall(frame.healthBar.SetValue, frame.healthBar, health)

    -- maxHealth: regulaere Zahl -> direkte Lua-Arithmetik moeglich
    local dispMax = 0
    pcall(function() dispMax = math.floor(maxHealth) end)

    -- dispHP: mehrere Ansaetze in Reihenfolge
    local dispHP = 0

    -- Versuch 1: Fill-Textur-Breite (reine Geometrie, keine secret numbers)
    -- Funktioniert wenn StatusBar Textur-Resize verwendet (nicht texcoord-clipping)
    pcall(function()
        if dispMax > 0 then
            local fillTex = frame.healthBar:GetStatusBarTexture()
            local barW    = frame.healthBar:GetWidth()
            if fillTex and barW and barW > 0 then
                local fillW = fillTex:GetWidth()
                if fillW and fillW > 0 and fillW <= barW then
                    dispHP = math.floor((fillW / barW) * dispMax)
                end
            end
        end
    end)

    -- Versuch 2: GetValue() auf dem StatusBar (koennte regulaere Zahl zurueckgeben)
    if dispHP == 0 then
        pcall(function()
            local v = frame.healthBar:GetValue()
            if v and v > 0 then
                dispHP = math.floor(v)
            end
        end)
    end

    -- Versuch 3: ReadSecretNumber via FontString (SetFormattedText ist C-Funktion)
    if dispHP == 0 then
        dispHP = ReadSecretNumber(health)
    end

    local pct = (dispMax > 0 and dispHP > 0) and (dispHP / dispMax) or nil

    -- Balkenfarbe basierend auf Prozent
    frame.healthBar:SetStatusBarColor(GetBarColorRGB(unit, pct))

    -- HP-Anzeige: Zahl ("45.2k") oder Prozent ("75%") je nach Einstellung
    frame.nameText:SetText(name)
    local showNumbers = HealBotMidnightDB and HealBotMidnightDB.showHPNumbers ~= false

    if showNumbers and dispMax > 0 then
        if dispHP > 0 and dispHP <= dispMax then
            -- Aktueller HP lesbar: Zahl + Fehlbetrag anzeigen
            frame.hpValueText:SetTextColor(1, 1, 1)
            frame.hpValueText:SetText(FormatHP(dispHP))
            local deficit = dispMax - dispHP
            if deficit > 1 and frame:GetHeight() >= 34 then
                frame.deficitText:SetText("-" .. FormatHP(deficit))
                frame.deficitText:Show()
            else
                frame.deficitText:Hide()
            end
        else
            -- Aktueller HP nicht lesbar (secret number): Max-HP gedimmt anzeigen
            -- Balken zeigt trotzdem korrekten Fuellstand visuell
            frame.hpValueText:SetTextColor(0.6, 0.6, 0.6)
            frame.hpValueText:SetText(FormatHP(dispMax))
            frame.deficitText:Hide()
        end
    else
        frame.hpValueText:SetTextColor(1, 1, 1)
        frame.hpValueText:SetText("")
        frame.deficitText:Hide()
    end

    -- Heal-Prediction und Debuffs (ebenfalls pcall-geschuetzt)
    pcall(UpdateHealPrediction, frame, unit, health, maxHealth)
    pcall(UpdateDebuffs, frame, unit)
end

-------------------------------------------------------------------------------
-- Heal-Prediction aktualisieren
-- Verwendet UnitGetIncomingHeals() mit Nil-Guard
-- Falls die API in Midnight entfernt wird: degradiert graceful zu "kein Balken"
-------------------------------------------------------------------------------

UpdateHealPrediction = function(frame, unit, health, maxHealth)
    -- Health/maxHealth koennen secret values sein -> pcall fuer alle Arithmetic
    -- SetMinMaxValues/SetValue als C-Funktionen koennen secret values annehmen
    pcall(frame.predBar.SetMinMaxValues, frame.predBar, 0, maxHealth)

    if not UnitGetIncomingHeals then
        frame.predBar:SetValue(0)
        return
    end

    local ok, _ = pcall(function()
        local incomingHeal = UnitGetIncomingHeals(unit) or 0
        if incomingHeal > 0 then
            local predValue = math.min(health + incomingHeal, maxHealth)
            frame.predBar:SetValue(predValue)
        else
            frame.predBar:SetValue(0)
        end
    end)
    if not ok then
        frame.predBar:SetValue(0)
    end
end

-------------------------------------------------------------------------------
-- Debuff-Erkennung und Rahmen-Highlighting
-- Verwendet C_UnitAuras.GetAuraDataByIndex() (korrekte moderne API seit 10.0)
-- NICHT GetDebuffDataByIndex (existiert nicht) oder UnitDebuff (entfernt in 10.0)
-------------------------------------------------------------------------------

UpdateDebuffs = function(frame, unit)
    local highestPriority = 0
    local highestType = nil
    local debuffTexture = nil

    -- Scanne alle Debuffs des Units via C_UnitAuras (moderne API)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HARMFUL")
            if not auraData then break end  -- Keine weiteren Debuffs

            local dispelName = auraData.dispelName
            if dispelName and DEBUFF_PRIORITY[dispelName] then
                local prio = DEBUFF_PRIORITY[dispelName]
                if prio > highestPriority then
                    highestPriority = prio
                    highestType = dispelName
                    debuffTexture = auraData.icon
                end
            end
        end
    end

    -- Rahmenfarbe setzen basierend auf Debuff-Typ
    if highestType and DEBUFF_COLORS[highestType] then
        local c = DEBUFF_COLORS[highestType]
        frame.border:SetBackdropBorderColor(c.r, c.g, c.b, 1)

        -- Debuff-Icon anzeigen
        if debuffTexture then
            frame.debuffIcon:SetTexture(debuffTexture)
            frame.debuffIcon:Show()
        else
            frame.debuffIcon:Hide()
        end
    else
        -- Kein dispelbarer Debuff: normaler Rahmen
        frame.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        frame.debuffIcon:Hide()
    end
end

-------------------------------------------------------------------------------
-- Gruppen-Roster scannen und Unit-Frames zuweisen
-- WICHTIG: Nicht im Kampf ausfuehren wegen SetAttribute() auf SecureButtons
-------------------------------------------------------------------------------

ScanGroupRoster = function()
    -- Im Kampf duerfen keine SecureButton-Attribute geaendert werden
    if InCombatLockdown() then
        rosterPending = true
        return
    end

    wipe(activeUnits)

    if IsInRaid() then
        -- Raid-Modus: raid1 bis raidN
        local numMembers = GetNumGroupMembers()
        for i = 1, numMembers do
            local raidUnit = "raid" .. i
            if UnitExists(raidUnit) then
                table.insert(activeUnits, raidUnit)
            end
        end
    elseif IsInGroup() then
        -- Party-Modus: player + party1 bis party4
        table.insert(activeUnits, "player")
        for i = 1, 4 do
            local partyUnit = "party" .. i
            if UnitExists(partyUnit) then
                table.insert(activeUnits, partyUnit)
            end
        end
    else
        -- Solo: nur der Spieler
        table.insert(activeUnits, "player")
    end

    -- Frames zuweisen (bestehende Frames recyceln statt neu erstellen)
    local cols = HealBotMidnightDB.columns or 8
    local width = HealBotMidnightDB.frameWidth
    local height = HealBotMidnightDB.frameHeight
    local padding = 2

    for i, unit in ipairs(activeUnits) do
        -- Frame erstellen wenn noetig, sonst recyceln
        if not unitFrames[i] then
            unitFrames[i] = CreateUnitFrame(unit, i)
        end

        local frame = unitFrames[i]
        frame.unitID = unit
        frame:SetAttribute("unit", unit)

        -- Click-Casting Attribute aktualisieren
        if HBM.UpdateClickCastAttributes then
            HBM.UpdateClickCastAttributes(frame)
        end

        -- Position berechnen (Raster-Layout)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local x = col * (width + padding) + 4
        local y = -(row * (height + padding)) - 18  -- 18px fuer Titelleiste

        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", mainContainer, "TOPLEFT", x, y)
        frame:SetSize(width, height)
        frame:Show()
    end

    -- Ueberzaehlige Frames verstecken (nicht zerstoeren - Frame-Recycling)
    for i = #activeUnits + 1, #unitFrames do
        if unitFrames[i] then
            unitFrames[i]:Hide()
        end
    end

    -- Container-Groesse anpassen
    local totalCols = math.min(#activeUnits, cols)
    local totalRows = math.ceil(#activeUnits / cols)
    local containerW = totalCols * (width + padding) + 8
    local containerH = totalRows * (height + padding) + 22
    mainContainer:SetSize(math.max(containerW, 100), math.max(containerH, 40))
end

-------------------------------------------------------------------------------
-- Update-Ticker: Alle Frames regelmaessig aktualisieren
-------------------------------------------------------------------------------

local updateInterval = 0.05  -- 20 FPS Update-Rate
local timeSinceLastUpdate = 0
local updateErrorLogged = {}  -- Pro Unit nur einmal loggen

local function OnUpdate(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate < updateInterval then return end
    timeSinceLastUpdate = 0

    -- Alle aktiven Frames aktualisieren (mit Error-Catching)
    for i = 1, #activeUnits do
        if unitFrames[i] then
            local ok, err = pcall(UpdateUnitFrame, unitFrames[i])
            if not ok and not updateErrorLogged[i] then
                updateErrorLogged[i] = true
                print("|cFFFF4444HBM Fehler bei Unit " .. i .. ":|r " ..
                    tostring(err))
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Event-Handler
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Kampf beendet

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "HealBot_Midnight" then
            -- SavedVariables initialisieren
            if not HealBotMidnightDB then
                HealBotMidnightDB = {}
            end
            -- Defaults einfuegen fuer fehlende Werte
            for key, value in pairs(DEFAULTS) do
                if HealBotMidnightDB[key] == nil then
                    if type(value) == "table" then
                        HealBotMidnightDB[key] = {}
                        for k, v in pairs(value) do
                            HealBotMidnightDB[key][k] = v
                        end
                    else
                        HealBotMidnightDB[key] = value
                    end
                end
            end

            isVisible = HealBotMidnightDB.visible

            -- Haupt-Container erstellen
            CreateMainContainer()

            -- Update-Ticker starten
            mainContainer:SetScript("OnUpdate", OnUpdate)

            -- Sichtbarkeit aus SavedVariables wiederherstellen
            if not isVisible then
                mainContainer:Hide()
            end

            -- Optionen-Button Sichtbarkeit
            if HBM.optionsButton then
                if HealBotMidnightDB.showOptionsButton == false then
                    HBM.optionsButton:Hide()
                else
                    HBM.optionsButton:Show()
                end
            end

            -- Initialer Roster-Scan (kurz verzoegert damit alle Units geladen sind)
            C_Timer.After(0.5, function()
                ScanGroupRoster()
            end)

            print("|cFF80C0FFHealBot Midnight|r " .. L["v0.0.1 loaded. Type /hbm for help."])
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Gruppe hat sich geaendert: Roster neu scannen
        -- ScanGroupRoster prueft intern auf InCombatLockdown()
        if mainContainer then
            ScanGroupRoster()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Nach Instanz-Wechsel neu scannen
        if mainContainer then
            C_Timer.After(1.0, function()
                ScanGroupRoster()
            end)
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Kampf beendet: ausstehenden Roster-Scan nachholen
        if rosterPending and mainContainer then
            rosterPending = false
            ScanGroupRoster()
        end
    end
    -- UNIT_HEALTH, UNIT_MAXHEALTH, UNIT_AURA werden ueber OnUpdate behandelt
end)

-------------------------------------------------------------------------------
-- Slash-Commands
-------------------------------------------------------------------------------

SLASH_HEALBOTMIDNIGHT1 = "/hbm"
SlashCmdList["HEALBOTMIDNIGHT"] = function(msg)
    msg = msg and msg:lower():trim() or ""

    if msg == "" then
        -- Toggle Sichtbarkeit
        if mainContainer then
            isVisible = not isVisible
            HealBotMidnightDB.visible = isVisible
            if isVisible then
                mainContainer:Show()
                print("|cFF80C0FFHealBot Midnight|r: " .. L["Frames shown."])
            else
                mainContainer:Hide()
                print("|cFF80C0FFHealBot Midnight|r: " .. L["Frames hidden."])
            end
        end

    elseif msg == "config" then
        -- Konfigurationsfenster oeffnen
        if HBM.ToggleConfig then
            HBM.ToggleConfig()
        else
            print("|cFF80C0FFHealBot Midnight|r: " .. L["Config module not loaded."])
        end

    elseif msg == "reset" then
        -- Position zuruecksetzen
        if mainContainer then
            HealBotMidnightDB.anchorX = 100
            HealBotMidnightDB.anchorY = -200
            mainContainer:ClearAllPoints()
            mainContainer:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -200)
            print("|cFF80C0FFHealBot Midnight|r: " .. L["Position reset."])
        end

    elseif msg == "debug" then
        -- Debug-Ausgabe: Alle erkannten Gruppenmitglieder auflisten
        print("|cFF80C0FFHealBot Midnight|r --- DEBUG Gruppeninfo ---")

        -- Kampfstatus
        if InCombatLockdown() then
            print("  |cFFFF4444ACHTUNG: Im Kampf! Roster-Updates sind verzoegert.|r")
        end

        -- Gruppen-Typ erkennen
        local groupType
        if IsInRaid() then
            groupType = "Raid"
        elseif IsInGroup() then
            groupType = "Party"
        else
            groupType = "Solo"
        end
        print("  Gruppen-Typ: |cFF00CCFF" .. groupType .. "|r")
        print("  GetNumGroupMembers(): |cFF00CCFF" ..
            tostring(GetNumGroupMembers()) .. "|r")

        -- Aktive Units auflisten
        print("  Erkannte Units (" .. #activeUnits .. "):")
        for i, unit in ipairs(activeUnits) do
            local name = UnitName(unit) or "???"
            local isDead = UnitIsDeadOrGhost(unit)

            -- Range/DC-Check (pcall wegen moeglicher taint)
            local isOOR = false
            local isDC = false
            if unit ~= "player" then
                if UnitIsConnected and not UnitIsConnected(unit) then
                    isDC = true
                elseif CheckInteractDistance then
                    local ok2, res = pcall(CheckInteractDistance, unit, 4)
                    if ok2 and res == false then isOOR = true end
                end
            end

            -- Health-Prozent (pcall wegen secret number values)
            local status = ""
            if isDC then
                status = "|cFF555555DC|r"
            elseif isDead then
                status = "|cFFFF0000DEAD|r"
            elseif isOOR then
                status = "|cFF888888OOR|r"
            else
                local okPct, pctStr = pcall(function()
                    local h = UnitHealth(unit)
                    local mh = UnitHealthMax(unit)
                    if mh > 0 then
                        local p = math.floor((h / mh) * 100)
                        return tostring(p) .. "%%"
                    end
                    return "0%%"
                end)
                if okPct and pctStr then
                    status = "|cFF00FF00" .. pctStr .. "|r"
                else
                    status = "|cFF888888(secret)|r"
                end
            end

            -- Debuff-Info
            local debuffInfo = ""
            if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                local debuffCount = 0
                local dispelTypes = {}
                for j = 1, 40 do
                    local auraData = C_UnitAuras.GetAuraDataByIndex(unit, j, "HARMFUL")
                    if not auraData then break end
                    debuffCount = debuffCount + 1
                    if auraData.dispelName and auraData.dispelName ~= "" then
                        dispelTypes[auraData.dispelName] = true
                    end
                end
                if debuffCount > 0 then
                    local dispelStr = ""
                    for dtype in pairs(dispelTypes) do
                        if dispelStr ~= "" then dispelStr = dispelStr .. "," end
                        dispelStr = dispelStr .. dtype
                    end
                    debuffInfo = " Debuffs:" .. debuffCount
                    if dispelStr ~= "" then
                        debuffInfo = debuffInfo .. " [" .. dispelStr .. "]"
                    end
                end
            else
                debuffInfo = " |cFFFF4444(C_UnitAuras nicht verfuegbar!)|r"
            end

            -- Frame-Status
            local frameStatus = ""
            if unitFrames[i] and unitFrames[i]:IsShown() then
                frameStatus = " Frame:OK"
            else
                frameStatus = " |cFFFF4444Frame:FEHLT|r"
            end

            print(string.format("    %2d. %-6s %-15s %s%s%s",
                i, unit, name, status, debuffInfo, frameStatus))
        end

        -- API-Verfuegbarkeit pruefen
        print("  --- API-Check ---")
        print("  C_UnitAuras.GetAuraDataByIndex: " ..
            (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
                and "|cFF00FF00verfuegbar|r" or "|cFFFF0000FEHLT|r"))
        print("  UnitGetIncomingHeals: " ..
            (UnitGetIncomingHeals
                and "|cFF00FF00verfuegbar|r" or "|cFFFF4444nicht verfuegbar|r"))
        print("  UnitInRange: |cFFFF4444NICHT NUTZBAR (secret boolean/taint)|r")
        print("  CheckInteractDistance: " ..
            (CheckInteractDistance
                and "|cFF00FF00verfuegbar (Ersatz fuer UnitInRange)|r"
                or "|cFFFF0000FEHLT|r"))
        print("  SecureActionButton: " ..
            (unitFrames[1] and unitFrames[1]:GetAttribute("unit")
                and "|cFF00FF00OK (unit=" .. unitFrames[1]:GetAttribute("unit") .. ")|r"
                or "|cFF888888kein Frame|r"))

        -- Ausstehender Roster-Scan?
        if rosterPending then
            print("  |cFFFFFF00Roster-Scan ausstehend (wird nach Kampfende ausgefuehrt)|r")
        end

        -- Spell-Bindings ausgeben
        if HBM.PrintBindings then
            HBM.PrintBindings()
        end

    else
        -- Hilfe anzeigen
        print("|cFF80C0FFHealBot Midnight|r Befehle:")
        print("  /hbm - Frames ein/ausblenden")
        print("  /hbm config - Konfiguration oeffnen")
        print("  /hbm reset - Position zuruecksetzen")
        print("  /hbm debug - Debug-Info: Gruppenmitglieder + API-Check")
    end
end

-------------------------------------------------------------------------------
-- Oeffentliche API fuer andere Module
-------------------------------------------------------------------------------

HBM.unitFrames = unitFrames
HBM.activeUnits = activeUnits
HBM.ScanGroupRoster = ScanGroupRoster

-- Funktion um Frames nach Config-Aenderung neu aufzubauen
-- Recycelt bestehende Frames statt sie zu zerstoeren (verhindert Taint)
function HBM.RebuildFrames()
    if mainContainer then
        if InCombatLockdown() then
            rosterPending = true
            print("|cFF80C0FFHealBot Midnight|r: " ..
                L["Changes will be applied after combat."])
            return
        end
        -- Alle Frames verstecken
        for i, frame in ipairs(unitFrames) do
            frame:Hide()
        end
        -- Roster neu scannen (erstellt/recycelt Frames automatisch)
        ScanGroupRoster()
    end
end

-- Container-Referenz exportieren
function HBM.GetContainer()
    return mainContainer
end
