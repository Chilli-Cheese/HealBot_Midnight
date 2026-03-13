-------------------------------------------------------------------------------
-- HealBot Midnight - Konfigurations-UI (v4)
-- Sidebar-Navigation: Allgemein | Spells | Import/Export
-- Vollstaendige Lokalisierung via HBM_L
-- Klassenfarben-Option fuer Lebenspunktbalken
-- WoW Midnight (12.0.1) APIs
-------------------------------------------------------------------------------

local HBM = HealBotMidnight
local L = HBM_L  -- Lokalisierung (von HealBot_Midnight_Locale.lua gesetzt)

local configFrame        = nil
local spellDropdownPopup = nil
local importExportPopup  = nil

local pendingSpells        = {}
local activeModifier       = ""
local playerSpells         = nil
local profileDropdownPopup = nil
local selectedProfile      = ""

-------------------------------------------------------------------------------
-- Base64 Encode / Decode
-------------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function Base64Encode(data)
    local out = {}
    local pad = ""
    local len = #data
    if len % 3 == 2 then data = data .. "\0"; pad = "="
    elseif len % 3 == 1 then data = data .. "\0\0"; pad = "=="
    end
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + b * 256 + c
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096)   % 64
        local c3 = math.floor(n / 64)     % 64
        local c4 = n % 64
        out[#out+1] = B64:sub(c1+1,c1+1)..B64:sub(c2+1,c2+1)
            ..B64:sub(c3+1,c3+1)..B64:sub(c4+1,c4+1)
    end
    local result = table.concat(out)
    if pad ~= "" then result = result:sub(1, #result - #pad) .. pad end
    return result
end

local function Base64Decode(data)
    data = data:gsub("[^" .. B64 .. "=]", "")
    local padLen = 0
    if data:sub(-2) == "==" then padLen = 2
    elseif data:sub(-1) == "=" then padLen = 1 end
    data = data:gsub("=", "A")
    local out = {}
    for i = 1, #data, 4 do
        local a = B64:find(data:sub(i,   i))   - 1
        local b = B64:find(data:sub(i+1, i+1)) - 1
        local c = B64:find(data:sub(i+2, i+2)) - 1
        local d = B64:find(data:sub(i+3, i+3)) - 1
        if a and b and c and d then
            local n = a*262144 + b*4096 + c*64 + d
            out[#out+1] = string.char(
                math.floor(n/65536)%256,
                math.floor(n/256)%256,
                n%256)
        end
    end
    local result = table.concat(out)
    if padLen > 0 then result = result:sub(1, #result - padLen) end
    return result
end

-------------------------------------------------------------------------------
-- Serialisierung: Versioniertes Key=Value Format
-- v:VERSION|s:Key=Value|w:WIDTH|h:HEIGHT|c:COLS
-- Forward/Backward-kompatibel
-------------------------------------------------------------------------------

local SERIAL_VERSION = 1

local function SerializeConfig()
    local parts = { "v:" .. SERIAL_VERSION }
    local db = HealBotMidnightDB
    if not db then return "" end
    if db.spells then
        for key, spell in pairs(db.spells) do
            if spell and spell ~= "" then
                local s = spell:gsub("\\","\\\\"):gsub("|","\\p")
                    :gsub("=","\\e"):gsub(":","\\c")
                parts[#parts+1] = "s:" .. key .. "=" .. s
            end
        end
    end
    if db.frameWidth  then parts[#parts+1] = "w:" .. db.frameWidth  end
    if db.frameHeight then parts[#parts+1] = "h:" .. db.frameHeight end
    if db.columns     then parts[#parts+1] = "c:" .. db.columns     end
    return table.concat(parts, "|")
end

local function DeserializeConfig(str)
    local result = { spells = {} }
    if not str or str == "" then return nil end
    for part in str:gmatch("[^|]+") do
        local prefix, value = part:match("^(%a+):(.+)$")
        if prefix == "v" then
            result.version = tonumber(value) or 0
        elseif prefix == "s" then
            local key, spell = value:match("^(.-)=(.*)$")
            if key and spell then
                spell = spell:gsub("\\c",":"):gsub("\\e","=")
                    :gsub("\\p","|"):gsub("\\\\","\\")
                result.spells[key] = spell
            end
        elseif prefix == "w" then result.frameWidth  = tonumber(value)
        elseif prefix == "h" then result.frameHeight = tonumber(value)
        elseif prefix == "c" then result.columns     = tonumber(value)
        end
    end
    return result
end

function HBM.ExportConfig()
    local s = SerializeConfig()
    if s == "" then return "" end
    return Base64Encode(s)
end

function HBM.ImportConfig(base64str)
    local decoded = Base64Decode(base64str)
    if not decoded or decoded == "" then
        return false, L["Invalid import string."]
    end
    local imported = DeserializeConfig(decoded)
    if not imported then return false, L["Deserialization error."] end

    if not HealBotMidnightDB then HealBotMidnightDB = {} end
    if not HealBotMidnightDB.spells then HealBotMidnightDB.spells = {} end

    if imported.spells then
        for _, key in ipairs(HBM.GetBindingKeys()) do
            HealBotMidnightDB.spells[key] = imported.spells[key] or ""
        end
    end
    if imported.frameWidth  then HealBotMidnightDB.frameWidth  = imported.frameWidth  end
    if imported.frameHeight then HealBotMidnightDB.frameHeight = imported.frameHeight end
    if imported.columns     then HealBotMidnightDB.columns     = imported.columns     end

    return true, L["Import successful!"]
end

-------------------------------------------------------------------------------
-- Spieler-Spells laden (C_SpellBook / C_Spell - Midnight 12.0.1 API)
-------------------------------------------------------------------------------

-- Sichere Enum-Referenzen (koennen in Midnight-Versionen fehlen)
local SPELL_BANK_PLAYER = Enum.SpellBookSpellBank  and Enum.SpellBookSpellBank.Player  or 0
local SPELL_TYPE_SPELL  = Enum.SpellBookItemType   and Enum.SpellBookItemType.Spell    or 0

local function LoadPlayerSpells()
    if playerSpells then return playerSpells end
    playerSpells = { helpful = {}, other = {} }

    local ok0, numLines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    if not ok0 or not numLines or numLines == 0 then return playerSpells end

    for i = 1, numLines do
        local ok1, lineInfo = pcall(C_SpellBook.GetSpellBookSkillLineInfo, i)
        if ok1 and lineInfo and lineInfo.numSpellBookItems then
            local offset = lineInfo.itemIndexOffset or 0
            for j = offset+1, offset+lineInfo.numSpellBookItems do
                local ok2, item = pcall(C_SpellBook.GetSpellBookItemInfo,
                    j, SPELL_BANK_PLAYER)
                if ok2 and item and item.spellID then
                    -- Nur aktive Spells (kein Passive, kein Off-Spec)
                    -- itemType == SPELL_TYPE_SPELL ODER itemType nil (alte API)
                    local isSpell = (item.itemType == nil)
                        or (item.itemType == SPELL_TYPE_SPELL)
                    if isSpell
                            and not item.isPassive
                            and not item.isOffSpec then
                        local id = item.spellID
                        local ok3, name = pcall(C_Spell.GetSpellName, id)
                        if ok3 and name and name ~= "" then
                            local icon = nil
                            local ok4, tex = pcall(C_Spell.GetSpellTexture, id)
                            if ok4 then icon = tex end

                            local isHelpful = false
                            local ok5, hRes = pcall(C_Spell.IsSpellHelpful, id)
                            if ok5 then isHelpful = hRes end

                            local entry = {
                                name    = name,
                                icon    = icon or 134400,
                                spellID = id,
                            }
                            if isHelpful then
                                table.insert(playerSpells.helpful, entry)
                            else
                                table.insert(playerSpells.other, entry)
                            end
                        end
                    end
                end
            end
        end
    end

    local function byName(a,b) return a.name < b.name end
    table.sort(playerSpells.helpful, byName)
    table.sort(playerSpells.other,   byName)
    return playerSpells
end

local spellCacheFrame = CreateFrame("Frame")
spellCacheFrame:RegisterEvent("SPELLS_CHANGED")
spellCacheFrame:SetScript("OnEvent", function() playerSpells = nil end)

-------------------------------------------------------------------------------
-- Custom Slider (OptionsSliderTemplate entfernt seit 10.0)
-------------------------------------------------------------------------------

local function CreateHBMSlider(name, parent, label, minVal, maxVal, step, defVal)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(340, 32)

    local lbl = container:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lbl:SetPoint("LEFT", container, "LEFT", 0, 0)
    lbl:SetText(label)
    lbl:SetWidth(90)
    lbl:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", name, container, "BackdropTemplate")
    slider:SetSize(186, 14)
    slider:SetPoint("LEFT", lbl, "RIGHT", 10, 0)
    slider:SetBackdrop({
        bgFile   = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        edgeSize = 6,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(defVal)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 24)
    thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:SetThumbTexture(thumb)

    local valTxt = container:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    valTxt:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valTxt:SetWidth(35)
    valTxt:SetJustifyH("LEFT")
    valTxt:SetText(tostring(defVal))

    slider:SetScript("OnValueChanged", function(self, v)
        valTxt:SetText(tostring(math.floor(v)))
    end)

    container.slider    = slider
    container.valueText = valTxt
    return container, slider
end

-------------------------------------------------------------------------------
-- Spell-Dropdown Popup
-------------------------------------------------------------------------------

-- Unsichtbarer Vollbild-Frame der Klicks ausserhalb des Dropdowns abfaengt
local dropdownClickCatcher = CreateFrame("Frame", nil, UIParent)
dropdownClickCatcher:SetAllPoints(UIParent)
dropdownClickCatcher:SetFrameStrata("DIALOG")  -- unter TOOLTIP (Popup-Strata)
dropdownClickCatcher:EnableMouse(true)
dropdownClickCatcher:Hide()

-- Handler einmalig hier setzen (nicht in den Create-Funktionen, da sonst
-- der zweite Aufruf den ersten ueberschreibt)
dropdownClickCatcher:SetScript("OnMouseDown", function()
    if spellDropdownPopup   then spellDropdownPopup:Hide()   end
    if profileDropdownPopup then profileDropdownPopup:Hide() end
    dropdownClickCatcher:Hide()
end)

local function CreateSpellDropdownPopup()
    if spellDropdownPopup then return spellDropdownPopup end

    local popup = CreateFrame("Frame","HBMSpellPopup",UIParent,"BackdropTemplate")
    popup:SetSize(260, 320)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left=3, right=3, top=3, bottom=3 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.12, 0.97)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()

    -- Scrollframe: Breite explizit, NICHT sf:GetWidth() (= 0 wenn noch versteckt)
    -- popup(260) - linker Inset(6) - Scrollbar(26) - rechter Inset(3) = 225
    local SCROLL_W = 225

    local sf = CreateFrame("ScrollFrame","HBMSpellPopupScroll",popup,
        "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     6, -6)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -26, 6)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(SCROLL_W)  -- Explizite Breite, nicht sf:GetWidth()
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    popup.scrollChild = sc
    popup.scrollW     = SCROLL_W
    popup.buttons     = {}

    -- ESC schliesst Popup
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
            dropdownClickCatcher:Hide()
        end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
    end)

    popup:SetScript("OnHide", function()
        dropdownClickCatcher:Hide()
    end)

    spellDropdownPopup = popup
    return popup
end

local function ShowSpellDropdown(anchorFrame, dbKey, onSelect)
    local popup  = CreateSpellDropdownPopup()
    local spells = LoadPlayerSpells()

    for _, btn in ipairs(popup.buttons) do btn:Hide() end

    local sc     = popup.scrollChild
    local yOff   = 0
    local btnIdx = 0
    -- Explizite Breite verwenden (sc:GetWidth() kann 0 sein wenn noch nie angezeigt)
    local bWidth = (popup.scrollW or 225) - 4

    local function Entry(text, icon, isHeader, spellName)
        btnIdx = btnIdx + 1
        local btn = popup.buttons[btnIdx]
        if not btn then
            btn = CreateFrame("Button", nil, sc)
            btn:SetHeight(20)
            popup.buttons[btnIdx] = btn
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(18, 18)
            btn.icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
            btn.text = btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            btn.text:SetPoint("LEFT",  btn.icon, "RIGHT", 4, 0)
            btn.text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            btn.text:SetJustifyH("LEFT")
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.3, 0.5, 0.8, 0.3)
            btn.hl = hl
        end
        btn:SetPoint("TOPLEFT", sc, "TOPLEFT", 2, -yOff)
        btn:SetWidth(bWidth)
        btn:Show()

        if isHeader then
            btn.text:SetText("|cFFFFCC00" .. text .. "|r")
            btn.icon:Hide()
            btn.hl:Hide()
            btn:EnableMouse(false)
        else
            btn.text:SetText(text)
            btn.icon:SetTexture(icon or 134400)
            btn.icon:Show()
            btn.hl:Show()
            btn:EnableMouse(true)
            local sn = spellName or ""
            btn:SetScript("OnClick", function()
                if onSelect then onSelect(sn) end
                popup:Hide()
            end)
        end
        yOff = yOff + btn:GetHeight() + 1
    end

    Entry(L["(Empty)"],               136235, false, "")
    if #spells.helpful > 0 then
        Entry(L["--- Helpful Spells ---"], nil, true)
        for _, sp in ipairs(spells.helpful) do
            Entry(sp.name, sp.icon, false, sp.name)
        end
    end
    if #spells.other > 0 then
        Entry(L["--- Other Spells ---"], nil, true)
        for _, sp in ipairs(spells.other) do
            Entry(sp.name, sp.icon, false, sp.name)
        end
    end

    sc:SetHeight(yOff + 4)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    dropdownClickCatcher:Show()  -- Klicks ausserhalb schliessen Popup
    popup:Show()
end

-------------------------------------------------------------------------------
-- Import/Export Popup
-------------------------------------------------------------------------------

local function CreateImportExportPopup()
    if importExportPopup then return importExportPopup end

    local popup = CreateFrame("Frame","HBMImportExportPopup",UIParent,"BackdropTemplate")
    popup:SetSize(460, 200)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets   = { left=4, right=4, top=4, bottom=4 },
    })
    popup:SetBackdropColor(0.1, 0.1, 0.1, 0.98)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetMovable(true)
    popup:EnableMouse(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)

    local titleFS = popup:CreateFontString(nil,"OVERLAY","GameFontNormal")
    titleFS:SetPoint("TOP", popup, "TOP", 0, -14)
    popup.title = titleFS

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)

    local sf = CreateFrame("ScrollFrame","HBMIEScroll",popup,
        "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     16, -40)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -36, 50)

    local eb = CreateFrame("EditBox","HBMIEEditBox",sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(sf:GetWidth() or 390)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        popup:Hide()
    end)
    sf:SetScrollChild(eb)
    popup.editBox = eb

    local okBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    okBtn:SetSize(100, 24)
    okBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 14)
    okBtn:SetText(L["OK"])
    popup.okBtn = okBtn

    popup:Hide()
    importExportPopup = popup
    return popup
end

local function ShowExportPopup()
    local popup = CreateImportExportPopup()
    popup.title:SetText("|cFF80C0FF" .. L["Export - Copy string:"] .. "|r")
    popup.editBox:SetText(HBM.ExportConfig())
    popup.editBox:SetCursorPosition(0)
    popup.okBtn:SetScript("OnClick", function() popup:Hide() end)
    popup:Show()
    popup.editBox:SetFocus()
    popup.editBox:HighlightText()
end

local function ShowImportPopup()
    local popup = CreateImportExportPopup()
    popup.title:SetText("|cFF80C0FF" .. L["Import - Paste string:"] .. "|r")
    popup.editBox:SetText("")
    popup.okBtn:SetScript("OnClick", function()
        local text = popup.editBox:GetText():trim()
        if text == "" then popup:Hide() return end
        local ok, msg = HBM.ImportConfig(text)
        if ok then
            print("|cFF80C0FFHealBot Midnight|r: |cFF00FF00" .. msg .. "|r")
            HBM.RebuildFrames()
            if configFrame and configFrame:IsShown() then
                HBM.RefreshConfigUI()
            end
        else
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" .. msg .. "|r")
        end
        popup:Hide()
    end)
    popup:Show()
    popup.editBox:SetFocus()
end

-------------------------------------------------------------------------------
-- Profile-System: Serialisierung, Export-Popup, Dropdown
-------------------------------------------------------------------------------

-- Serialisiert ein einzelnes Profil-Objekt (nicht die gesamte DB)
local function SerializeProfile(prof)
    local parts = { "v:" .. SERIAL_VERSION }
    if prof.spells then
        for key, spell in pairs(prof.spells) do
            if spell and spell ~= "" then
                local s = spell:gsub("\\","\\\\"):gsub("|","\\p")
                    :gsub("=","\\e"):gsub(":","\\c")
                parts[#parts+1] = "s:" .. key .. "=" .. s
            end
        end
    end
    if prof.frameWidth  then parts[#parts+1] = "w:" .. prof.frameWidth  end
    if prof.frameHeight then parts[#parts+1] = "h:" .. prof.frameHeight end
    if prof.columns     then parts[#parts+1] = "c:" .. prof.columns     end
    return table.concat(parts, "|")
end

-- Zeigt das Export-Popup fuer ein benanntes Profil
local function ShowProfileExportPopup(name)
    if not (HealBotMidnightDB and HealBotMidnightDB.profiles) then return end
    local prof = HealBotMidnightDB.profiles[name]
    if not prof then return end
    local popup = CreateImportExportPopup()
    popup.title:SetText("|cFF80C0FF" .. L["Export Profile"] .. ": " .. name .. "|r")
    popup.editBox:SetText(Base64Encode(SerializeProfile(prof)))
    popup.editBox:SetCursorPosition(0)
    popup.okBtn:SetScript("OnClick", function() popup:Hide() end)
    popup:Show()
    popup.editBox:SetFocus()
    popup.editBox:HighlightText()
end

-- Erstellt das Profil-Auswahl-Dropdown-Popup (lazy, einmalig)
local function CreateProfileDropdownPopup()
    if profileDropdownPopup then return profileDropdownPopup end

    local popup = CreateFrame("Frame","HBMProfilePopup",UIParent,"BackdropTemplate")
    popup:SetSize(220, 200)
    popup:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left=3, right=3, top=3, bottom=3 },
    })
    popup:SetBackdropColor(0.08, 0.08, 0.12, 0.97)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    popup:Hide()

    local SCROLL_W = 184  -- 220-6(inset)-26(scrollbar)-4(pad) = 184
    local sf = CreateFrame("ScrollFrame","HBMProfilePopupScroll",popup,
        "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     popup, "TOPLEFT",     6, -6)
    sf:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -26, 6)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(SCROLL_W)
    sc:SetHeight(1)
    sf:SetScrollChild(sc)

    popup.scrollChild = sc
    popup.scrollW     = SCROLL_W
    popup.buttons     = {}

    popup:SetScript("OnHide", function()
        dropdownClickCatcher:Hide()
    end)

    profileDropdownPopup = popup
    return popup
end

-- Zeigt das Profil-Dropdown-Popup unter anchorBtn
-- onSelect(name) wird aufgerufen wenn ein Profil ausgewaehlt wird
local function ShowProfileDropdown(anchorBtn, onSelect)
    local popup = CreateProfileDropdownPopup()
    local sc    = popup.scrollChild

    for _, btn in ipairs(popup.buttons) do btn:Hide() end

    local profiles = HealBotMidnightDB and HealBotMidnightDB.profiles or {}
    local names    = {}
    for k in pairs(profiles) do table.insert(names, k) end
    table.sort(names)

    local yOff   = 0
    local btnIdx = 0
    local bWidth = (popup.scrollW or 184) - 2

    local function Entry(text, enabled, profileName)
        btnIdx = btnIdx + 1
        local btn = popup.buttons[btnIdx]
        if not btn then
            btn = CreateFrame("Button", nil, sc)
            btn:SetHeight(22)
            popup.buttons[btnIdx] = btn
            btn.lbl = btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            btn.lbl:SetPoint("LEFT", btn, "LEFT", 8, 0)
            btn.lbl:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
            btn.lbl:SetJustifyH("LEFT")
            local hl = btn:CreateTexture(nil,"HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(0.3, 0.5, 0.8, 0.3)
            btn.hl = hl
        end
        btn:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -yOff)
        btn:SetWidth(bWidth)
        btn:Show()
        btn.lbl:SetText(text)
        btn.hl:SetShown(enabled ~= false)
        btn:EnableMouse(enabled ~= false)
        if enabled ~= false then
            local n = profileName or text
            btn:SetScript("OnClick", function()
                if onSelect then onSelect(n) end
                popup:Hide()
            end)
        end
        yOff = yOff + 23
    end

    if #names == 0 then
        Entry("|cFF888888" .. L["No profiles saved yet."] .. "|r", false)
    else
        for _, name in ipairs(names) do
            Entry(name, true, name)
        end
    end

    sc:SetHeight(yOff + 4)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    dropdownClickCatcher:Show()
    popup:Show()
end

-------------------------------------------------------------------------------
-- Spell-Zeile (Dropdown-Button fuer eine Maustaste)
-------------------------------------------------------------------------------

local function CreateSpellRow(parent, buttonLabel, yOffset)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(360, 28)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset)

    local lbl = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lbl:SetPoint("LEFT", row, "LEFT", 0, 0)
    lbl:SetText(buttonLabel .. ":")
    lbl:SetWidth(56)
    lbl:SetJustifyH("RIGHT")

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
    icon:SetTexture(134400)
    row.icon = icon

    local dropBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
    dropBtn:SetSize(248, 24)
    dropBtn:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    dropBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    dropBtn:SetBackdropColor(0.12, 0.12, 0.18, 0.9)

    local btnText = dropBtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    btnText:SetPoint("LEFT",  dropBtn, "LEFT",  8, 0)
    btnText:SetPoint("RIGHT", dropBtn, "RIGHT", -20, 0)
    btnText:SetJustifyH("LEFT")
    btnText:SetText("|cFF888888" .. L["(not assigned)"] .. "|r")
    dropBtn.text = btnText

    local arrow = dropBtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", dropBtn, "RIGHT", -6, 0)
    arrow:SetText("|cFFAAAACCv|r")

    dropBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(0.2,0.2,0.3,0.9) end)
    dropBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(0.12,0.12,0.18,0.9) end)

    row.dropBtn = dropBtn
    return row
end

-------------------------------------------------------------------------------
-- Config UI aktualisieren (wird aus ToggleConfig und ImportConfig aufgerufen)
-------------------------------------------------------------------------------

function HBM.RefreshConfigUI()
    if not configFrame then return end

    -- Pending Spells aus DB laden falls noch nicht geschehen
    if HealBotMidnightDB and HealBotMidnightDB.spells then
        for _, key in ipairs(HBM.GetBindingKeys()) do
            if pendingSpells[key] == nil then
                pendingSpells[key] = HealBotMidnightDB.spells[key] or ""
            end
        end
    end

    -- Modifier-Label
    local modName = L["No Modifier"]
    if     activeModifier == "Shift" then modName = "Shift"
    elseif activeModifier == "Ctrl"  then modName = L["Ctrl"]
    elseif activeModifier == "Alt"   then modName = "Alt"
    end
    if configFrame.modifierLabel then
        configFrame.modifierLabel:SetText(
            L["Active:"] .. " |cFF80C0FF" .. modName .. "|r")
    end

    -- Spell-Zeilen
    for i, btn in ipairs(HBM.MOUSE_BUTTONS) do
        local row = configFrame.spellRows and configFrame.spellRows[i]
        if row then
            local dbKey     = HBM.GetDBKey(activeModifier, btn)
            local spellName = pendingSpells[dbKey] or ""

            if spellName ~= "" then
                row.dropBtn.text:SetText(spellName)
                local iconTex = nil
                local ok, tex = pcall(C_Spell.GetSpellTexture, spellName)
                if ok and tex then iconTex = tex end
                row.icon:SetTexture(iconTex or 134400)
            else
                row.dropBtn.text:SetText(
                    "|cFF888888" .. L["(not assigned)"] .. "|r")
                row.icon:SetTexture(134400)
            end

            row.dropBtn:SetScript("OnClick", function(self)
                ShowSpellDropdown(self, dbKey, function(selected)
                    pendingSpells[dbKey] = selected
                    HBM.RefreshConfigUI()
                end)
            end)
        end
    end

    -- Modifier-Checkboxen
    if configFrame.checkShift then
        configFrame.checkShift:SetChecked(activeModifier == "Shift")
    end
    if configFrame.checkCtrl then
        configFrame.checkCtrl:SetChecked(activeModifier == "Ctrl")
    end
    if configFrame.checkAlt then
        configFrame.checkAlt:SetChecked(activeModifier == "Alt")
    end

    -- Optionen-Button Checkbox
    if configFrame.optBtnCheck then
        configFrame.optBtnCheck:SetChecked(
            HealBotMidnightDB and HealBotMidnightDB.showOptionsButton ~= false)
    end

    -- Klassenfarben Checkbox
    if configFrame.classColorCheck then
        configFrame.classColorCheck:SetChecked(
            HealBotMidnightDB and HealBotMidnightDB.classColors == true)
    end

    -- HP-Zahlen Checkbox
    if configFrame.hpNumCheck then
        configFrame.hpNumCheck:SetChecked(
            HealBotMidnightDB and HealBotMidnightDB.showHPNumbers ~= false)
    end

    -- Slider
    if configFrame.widthSlider then
        configFrame.widthSlider:SetValue(
            HealBotMidnightDB and HealBotMidnightDB.frameWidth or 120)
    end
    if configFrame.heightSlider then
        configFrame.heightSlider:SetValue(
            HealBotMidnightDB and HealBotMidnightDB.frameHeight or 40)
    end
    if configFrame.colSlider then
        configFrame.colSlider:SetValue(
            HealBotMidnightDB and HealBotMidnightDB.columns or 8)
    end
end

-------------------------------------------------------------------------------
-- Config-Fenster erstellen (Sidebar-Layout)
-------------------------------------------------------------------------------

local function CreateConfigFrame()
    if configFrame then return configFrame end

    local f = CreateFrame("Frame","HBMConfigFrame",UIParent,"BackdropTemplate")
    f:SetSize(520, 450)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets   = { left=4, right=4, top=4, bottom=4 },
    })
    f:SetBackdropColor(0.08, 0.08, 0.12, 0.97)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetScript("OnHide", function()
        if spellDropdownPopup   then spellDropdownPopup:Hide()   end
        if profileDropdownPopup then profileDropdownPopup:Hide() end
        dropdownClickCatcher:Hide()
    end)
    f:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "HBMConfigFrame")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    ---------------------------------------------------------------------------
    -- SIDEBAR
    ---------------------------------------------------------------------------
    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetWidth(108)
    sidebar:SetPoint("TOPLEFT",    f, "TOPLEFT",    4,  -4)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4,  44)

    local sidebarBg = sidebar:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetAllPoints()
    sidebarBg:SetColorTexture(0.04, 0.04, 0.07, 0.97)

    -- Logo
    local logo1 = sidebar:CreateFontString(nil,"OVERLAY","GameFontNormal")
    logo1:SetPoint("TOP", sidebar, "TOP", 0, -14)
    logo1:SetText("HealBot")
    logo1:SetTextColor(0.5, 0.8, 1.0)

    local logo2 = sidebar:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    logo2:SetPoint("TOP", logo1, "BOTTOM", 0, -2)
    logo2:SetText("Midnight")
    logo2:SetTextColor(0.35, 0.55, 0.82)

    local logoSep = sidebar:CreateTexture(nil, "ARTWORK")
    logoSep:SetHeight(1)
    logoSep:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  6, -46)
    logoSep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -6, -46)
    logoSep:SetColorTexture(0.2, 0.35, 0.6, 0.45)

    local versionLbl = sidebar:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    versionLbl:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 8)
    versionLbl:SetText("v0.0.1")
    versionLbl:SetTextColor(0.28, 0.28, 0.36)

    -- Vertikaler Trenner
    local vDiv = f:CreateTexture(nil, "ARTWORK")
    vDiv:SetWidth(1)
    vDiv:SetPoint("TOPLEFT",    f, "TOPLEFT",    113, -4)
    vDiv:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 113, 44)
    vDiv:SetColorTexture(0.15, 0.28, 0.5, 0.6)

    ---------------------------------------------------------------------------
    -- CONTENT AREA
    ---------------------------------------------------------------------------
    local contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT",    f, "TOPLEFT",    115, -4)
    contentArea:SetPoint("BOTTOMRIGHT",f, "BOTTOMRIGHT", -4, 44)

    ---------------------------------------------------------------------------
    -- NAV-SYSTEM
    ---------------------------------------------------------------------------
    local navButtons = {}
    local panels     = {}

    local function SetNavSelected(selBtn)
        for _, btn in ipairs(navButtons) do
            btn.bg:SetColorTexture(0,0,0,0)
            btn.indicator:Hide()
            btn.label:SetTextColor(0.6, 0.62, 0.68)
        end
        selBtn.bg:SetColorTexture(0.12, 0.22, 0.42, 0.92)
        selBtn.indicator:Show()
        selBtn.label:SetTextColor(1, 1, 1)
    end

    local function ShowPanel(id)
        for _, panel in pairs(panels) do panel:Hide() end
        if panels[id] then panels[id]:Show() end
    end

    local categories = {
        { id="general", label=L["General"]       },
        { id="spells",  label=L["Spells"]        },
        { id="profiles", label=L["Profiles"]      },
    }

    for i, cat in ipairs(categories) do
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetHeight(30)
        btn:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  0, -52 - (i-1)*32)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -52 - (i-1)*32)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0,0,0,0)
        btn.bg = bg

        local ind = btn:CreateTexture(nil, "OVERLAY")
        ind:SetSize(3, 30)
        ind:SetPoint("LEFT", btn, "LEFT", 0, 0)
        ind:SetColorTexture(0.4, 0.65, 1.0, 1.0)
        ind:Hide()
        btn.indicator = ind

        local lbl = btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        lbl:SetPoint("LEFT", btn, "LEFT", 16, 0)
        lbl:SetText(cat.label)
        lbl:SetJustifyH("LEFT")
        lbl:SetTextColor(0.6, 0.62, 0.68)
        btn.label = lbl

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1,1,1, 0.05)

        local catId = cat.id
        btn:SetScript("OnClick", function()
            SetNavSelected(btn)
            ShowPanel(catId)
        end)

        navButtons[i] = btn
    end

    ---------------------------------------------------------------------------
    -- PANEL: ALLGEMEIN
    ---------------------------------------------------------------------------
    local panelGeneral = CreateFrame("Frame", nil, contentArea)
    panelGeneral:SetAllPoints()
    panels["general"] = panelGeneral

    local genTitle = panelGeneral:CreateFontString(nil,"OVERLAY","GameFontNormal")
    genTitle:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 12, -14)
    genTitle:SetText(L["General Settings"])
    genTitle:SetTextColor(1, 0.82, 0)

    local genSep1 = panelGeneral:CreateTexture(nil,"ARTWORK")
    genSep1:SetHeight(1)
    genSep1:SetPoint("TOPLEFT",  panelGeneral, "TOPLEFT",  12, -32)
    genSep1:SetPoint("TOPRIGHT", panelGeneral, "TOPRIGHT", -12,-32)
    genSep1:SetColorTexture(0.25, 0.3, 0.45, 0.55)

    -- Unterueberschrift Groesse
    local genSizeSub = panelGeneral:CreateFontString(nil,"OVERLAY",
        "GameFontHighlightSmall")
    genSizeSub:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 12, -42)
    genSizeSub:SetText(L["Raid Frame Size"])
    genSizeSub:SetTextColor(0.65, 0.65, 0.72)

    local wC, wS = CreateHBMSlider("HBMWidthSlider", panelGeneral,
        L["Width:"], 60, 200, 5,
        HealBotMidnightDB and HealBotMidnightDB.frameWidth or 120)
    wC:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 12, -58)
    f.widthSlider = wS

    local hC, hS = CreateHBMSlider("HBMHeightSlider", panelGeneral,
        L["Height:"], 20, 80, 2,
        HealBotMidnightDB and HealBotMidnightDB.frameHeight or 40)
    hC:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 12, -92)
    f.heightSlider = hS

    local cC, cS = CreateHBMSlider("HBMColSlider", panelGeneral,
        L["Columns:"], 1, 10, 1,
        HealBotMidnightDB and HealBotMidnightDB.columns or 8)
    cC:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 12, -126)
    f.colSlider = cS

    local genSep2 = panelGeneral:CreateTexture(nil,"ARTWORK")
    genSep2:SetHeight(1)
    genSep2:SetPoint("TOPLEFT",  panelGeneral, "TOPLEFT",  12, -163)
    genSep2:SetPoint("TOPRIGHT", panelGeneral, "TOPRIGHT", -12,-163)
    genSep2:SetColorTexture(0.25, 0.3, 0.45, 0.55)

    -- Unterueberschrift Anzeige
    local genDisplaySub = panelGeneral:CreateFontString(nil,"OVERLAY",
        "GameFontHighlightSmall")
    genDisplaySub:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 12, -173)
    genDisplaySub:SetText(L["Display"])
    genDisplaySub:SetTextColor(0.65, 0.65, 0.72)

    -- Checkbox: Optionen-Button anzeigen
    local optBtnCheck = CreateFrame("CheckButton", nil, panelGeneral,
        "UICheckButtonTemplate")
    optBtnCheck:SetSize(22, 22)
    optBtnCheck:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 14, -192)
    optBtnCheck:SetChecked(
        HealBotMidnightDB and HealBotMidnightDB.showOptionsButton ~= false)
    f.optBtnCheck = optBtnCheck

    local optLbl = panelGeneral:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    optLbl:SetPoint("LEFT", optBtnCheck, "RIGHT", 4, 0)
    optLbl:SetText(L["Show options button in main window"])

    -- Checkbox: Klassenfarben
    local classColorCheck = CreateFrame("CheckButton", nil, panelGeneral,
        "UICheckButtonTemplate")
    classColorCheck:SetSize(22, 22)
    classColorCheck:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 14, -218)
    classColorCheck:SetChecked(
        HealBotMidnightDB and HealBotMidnightDB.classColors == true)
    f.classColorCheck = classColorCheck

    local classColorLbl = panelGeneral:CreateFontString(nil,"OVERLAY",
        "GameFontHighlightSmall")
    classColorLbl:SetPoint("LEFT", classColorCheck, "RIGHT", 4, 0)
    classColorLbl:SetText(L["Use class colors for health bars"])

    -- Checkbox: HP als Zahl anzeigen
    local hpNumCheck = CreateFrame("CheckButton", nil, panelGeneral,
        "UICheckButtonTemplate")
    hpNumCheck:SetSize(22, 22)
    hpNumCheck:SetPoint("TOPLEFT", panelGeneral, "TOPLEFT", 14, -244)
    hpNumCheck:SetChecked(
        HealBotMidnightDB and HealBotMidnightDB.showHPNumbers ~= false)
    f.hpNumCheck = hpNumCheck

    local hpNumLbl = panelGeneral:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    hpNumLbl:SetPoint("LEFT", hpNumCheck, "RIGHT", 4, 0)
    hpNumLbl:SetText(L["Show HP as number on frames"])

    ---------------------------------------------------------------------------
    -- PANEL: SPELLS
    ---------------------------------------------------------------------------
    local panelSpells = CreateFrame("Frame", nil, contentArea)
    panelSpells:SetAllPoints()
    panels["spells"] = panelSpells
    panelSpells:Hide()

    local spellTitle = panelSpells:CreateFontString(nil,"OVERLAY","GameFontNormal")
    spellTitle:SetPoint("TOPLEFT", panelSpells, "TOPLEFT", 12, -14)
    spellTitle:SetText(L["Click-Cast Spells"])
    spellTitle:SetTextColor(1, 0.82, 0)

    local spSep1 = panelSpells:CreateTexture(nil,"ARTWORK")
    spSep1:SetHeight(1)
    spSep1:SetPoint("TOPLEFT",  panelSpells, "TOPLEFT",  12, -32)
    spSep1:SetPoint("TOPRIGHT", panelSpells, "TOPRIGHT", -12,-32)
    spSep1:SetColorTexture(0.25, 0.3, 0.45, 0.55)

    -- Modifier-Label
    local modSubHdr = panelSpells:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    modSubHdr:SetPoint("TOPLEFT", panelSpells, "TOPLEFT", 12, -42)
    modSubHdr:SetText(L["Modifier:"])
    modSubHdr:SetTextColor(0.65, 0.65, 0.72)

    -- Modifier-Checkboxen (radio-Verhalten)
    local modDefs = {
        { lbl="Shift",   mod="Shift", x=72  },
        { lbl=L["Ctrl"], mod="Ctrl",  x=148 },
        { lbl="Alt",     mod="Alt",   x=218 },
    }
    for _, md in ipairs(modDefs) do
        local cb = CreateFrame("CheckButton", nil, panelSpells, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", panelSpells, "TOPLEFT", md.x, -56)

        local cbLbl = panelSpells:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        cbLbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cbLbl:SetText(md.lbl)

        local m = md.mod
        cb:SetScript("OnClick", function(self)
            activeModifier = self:GetChecked() and m or ""
            HBM.RefreshConfigUI()
        end)

        if m == "Shift" then f.checkShift = cb
        elseif m == "Ctrl" then f.checkCtrl = cb
        elseif m == "Alt"  then f.checkAlt  = cb
        end
    end

    -- Aktiver Modifier Label
    f.modifierLabel = panelSpells:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.modifierLabel:SetPoint("TOPLEFT", panelSpells, "TOPLEFT", 12, -86)
    f.modifierLabel:SetText(L["Active:"] .. " |cFF80C0FF" .. L["No Modifier"] .. "|r")

    local spSep2 = panelSpells:CreateTexture(nil,"ARTWORK")
    spSep2:SetHeight(1)
    spSep2:SetPoint("TOPLEFT",  panelSpells, "TOPLEFT",  12, -98)
    spSep2:SetPoint("TOPRIGHT", panelSpells, "TOPRIGHT", -12,-98)
    spSep2:SetColorTexture(0.25, 0.3, 0.45, 0.55)

    -- Spell-Zeilen (Links / Rechts / Mitte - lokalisiert)
    f.spellRows = {}
    local btnLabels = {
        L["Left"], L["Middle"], L["Right"],
        L["Button4"] or "Taste 4",
        L["Button5"] or "Taste 5",
    }
    for i, lbl in ipairs(btnLabels) do
        local row = CreateSpellRow(panelSpells, lbl, -108 - (i-1)*36)
        f.spellRows[i] = row
    end

    ---------------------------------------------------------------------------
    -- PANEL: PROFILE
    ---------------------------------------------------------------------------
    local panelProfiles = CreateFrame("Frame", nil, contentArea)
    panelProfiles:SetAllPoints()
    panels["profiles"] = panelProfiles
    panelProfiles:Hide()

    local profTitle = panelProfiles:CreateFontString(nil,"OVERLAY","GameFontNormal")
    profTitle:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -14)
    profTitle:SetText(L["Profiles"])
    profTitle:SetTextColor(1, 0.82, 0)

    local profSep1 = panelProfiles:CreateTexture(nil,"ARTWORK")
    profSep1:SetHeight(1)
    profSep1:SetPoint("TOPLEFT",  panelProfiles, "TOPLEFT",  12, -32)
    profSep1:SetPoint("TOPRIGHT", panelProfiles, "TOPRIGHT", -12,-32)
    profSep1:SetColorTexture(0.25, 0.3, 0.45, 0.55)

    -- Sub-Header: Gespeicherte Profile
    local profSavedHdr = panelProfiles:CreateFontString(nil,"OVERLAY",
        "GameFontHighlightSmall")
    profSavedHdr:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -42)
    profSavedHdr:SetText(L["Saved Profiles"])
    profSavedHdr:SetTextColor(0.65, 0.65, 0.72)

    -- Profil-Dropdown
    local profDropBtn = CreateFrame("Button", nil, panelProfiles, "BackdropTemplate")
    profDropBtn:SetSize(210, 24)
    profDropBtn:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -58)
    profDropBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    profDropBtn:SetBackdropColor(0.12, 0.12, 0.18, 0.9)
    local profDropText = profDropBtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    profDropText:SetPoint("LEFT",  profDropBtn, "LEFT",  8, 0)
    profDropText:SetPoint("RIGHT", profDropBtn, "RIGHT", -20, 0)
    profDropText:SetJustifyH("LEFT")
    profDropText:SetText("|cFF888888" .. L["No profile selected."] .. "|r")
    local profDropArrow = profDropBtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    profDropArrow:SetPoint("RIGHT", profDropBtn, "RIGHT", -6, 0)
    profDropArrow:SetText("|cFFAAAACCv|r")
    profDropBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(0.2,0.2,0.3,0.9) end)
    profDropBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(0.12,0.12,0.18,0.9) end)
    profDropBtn:SetScript("OnClick", function(self)
        ShowProfileDropdown(self, function(name)
            selectedProfile = name
            profDropText:SetText(name)
        end)
    end)

    -- Laden / Loeschen Buttons
    local profLoadBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    profLoadBtn:SetSize(64, 24)
    profLoadBtn:SetPoint("LEFT", profDropBtn, "RIGHT", 6, 0)
    profLoadBtn:SetText(L["Load"])
    profLoadBtn:SetScript("OnClick", function()
        local db = HealBotMidnightDB
        if selectedProfile == "" or not (db and db.profiles and db.profiles[selectedProfile]) then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["No profile selected."] .. "|r")
            return
        end
        local prof = db.profiles[selectedProfile]
        if not db.spells then db.spells = {} end
        if prof.spells then
            for _, key in ipairs(HBM.GetBindingKeys()) do
                db.spells[key]   = prof.spells[key] or ""
                pendingSpells[key] = db.spells[key]
            end
        end
        if prof.frameWidth  then db.frameWidth  = prof.frameWidth  end
        if prof.frameHeight then db.frameHeight = prof.frameHeight end
        if prof.columns     then db.columns     = prof.columns     end
        if prof.classColors   ~= nil then db.classColors   = prof.classColors   end
        if prof.showHPNumbers ~= nil then db.showHPNumbers = prof.showHPNumbers end
        HBM.RebuildFrames()
        HBM.RefreshConfigUI()
        print("|cFF80C0FFHealBot Midnight|r: |cFF00FF00" ..
            L["Profile loaded!"] .. " (" .. selectedProfile .. ")|r")
    end)

    local profDelBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    profDelBtn:SetSize(64, 24)
    profDelBtn:SetPoint("LEFT", profLoadBtn, "RIGHT", 4, 0)
    profDelBtn:SetText(L["Delete"])
    profDelBtn:SetScript("OnClick", function()
        local db = HealBotMidnightDB
        if selectedProfile == "" or not (db and db.profiles and db.profiles[selectedProfile]) then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["No profile selected."] .. "|r")
            return
        end
        db.profiles[selectedProfile] = nil
        print("|cFF80C0FFHealBot Midnight|r: |cFF00FF00" ..
            L["Profile deleted!"] .. " (" .. selectedProfile .. ")|r")
        selectedProfile = ""
        profDropText:SetText("|cFF888888" .. L["No profile selected."] .. "|r")
    end)

    -- Speichern Row
    local profSaveSub = panelProfiles:CreateFontString(nil,"OVERLAY",
        "GameFontHighlightSmall")
    profSaveSub:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -92)
    profSaveSub:SetText(L["Save current settings as:"])
    profSaveSub:SetTextColor(0.65, 0.65, 0.72)

    local profNameBox = CreateFrame("EditBox", "HBMProfileNameBox",
        panelProfiles, "BackdropTemplate")
    profNameBox:SetSize(210, 24)
    profNameBox:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -108)
    profNameBox:SetAutoFocus(false)
    profNameBox:SetFontObject(GameFontHighlightSmall)
    profNameBox:SetTextInsets(6, 6, 0, 0)
    profNameBox:SetMaxLetters(40)
    profNameBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    profNameBox:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    profNameBox:SetBackdropBorderColor(0.25, 0.3, 0.5, 0.7)

    local profSaveBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    profSaveBtn:SetSize(130, 24)
    profSaveBtn:SetPoint("LEFT", profNameBox, "RIGHT", 6, 0)
    profSaveBtn:SetText(L["Save as Profile"])
    profSaveBtn:SetScript("OnClick", function()
        local name = profNameBox:GetText()
        if not name or name:trim() == "" then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["Profile name required."] .. "|r")
            return
        end
        name = name:trim()
        local db = HealBotMidnightDB
        if not db then return end
        if not db.profiles then db.profiles = {} end
        local prof = {
            spells      = {},
            frameWidth  = math.floor((f.widthSlider  and f.widthSlider:GetValue())  or db.frameWidth  or 120),
            frameHeight = math.floor((f.heightSlider and f.heightSlider:GetValue()) or db.frameHeight or 40),
            columns     = math.floor((f.colSlider    and f.colSlider:GetValue())    or db.columns     or 8),
            classColors   = f.classColorCheck and f.classColorCheck:GetChecked() or false,
            showHPNumbers = f.hpNumCheck      and f.hpNumCheck:GetChecked()      or false,
        }
        for _, key in ipairs(HBM.GetBindingKeys()) do
            prof.spells[key] = pendingSpells[key]
                or (db.spells and db.spells[key]) or ""
        end
        db.profiles[name] = prof
        selectedProfile = name
        profDropText:SetText(name)
        profNameBox:SetText("")
        print("|cFF80C0FFHealBot Midnight|r: |cFF00FF00" ..
            L["Profile saved!"] .. " (" .. name .. ")|r")
    end)

    -- Separator
    local profSep2 = panelProfiles:CreateTexture(nil,"ARTWORK")
    profSep2:SetHeight(1)
    profSep2:SetPoint("TOPLEFT",  panelProfiles, "TOPLEFT",  12, -144)
    profSep2:SetPoint("TOPRIGHT", panelProfiles, "TOPRIGHT", -12,-144)
    profSep2:SetColorTexture(0.25, 0.3, 0.45, 0.55)

    -- Export Section
    local profExpHdr = panelProfiles:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    profExpHdr:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -154)
    profExpHdr:SetText(L["Export Profile"])
    profExpHdr:SetTextColor(0.65, 0.65, 0.72)

    local profExpBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    profExpBtn:SetSize(240, 24)
    profExpBtn:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -170)
    profExpBtn:SetText(L["Export selected Profile"])
    profExpBtn:SetScript("OnClick", function()
        local db = HealBotMidnightDB
        if selectedProfile == "" or not (db and db.profiles and db.profiles[selectedProfile]) then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["No profile selected."] .. "|r")
            return
        end
        ShowProfileExportPopup(selectedProfile)
    end)

    -- Separator
    local profSep3 = panelProfiles:CreateTexture(nil,"ARTWORK")
    profSep3:SetHeight(1)
    profSep3:SetPoint("TOPLEFT",  panelProfiles, "TOPLEFT",  12, -206)
    profSep3:SetPoint("TOPRIGHT", panelProfiles, "TOPRIGHT", -12,-206)
    profSep3:SetColorTexture(0.25, 0.3, 0.45, 0.55)

    -- Import Section
    local profImpHdr = panelProfiles:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    profImpHdr:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -216)
    profImpHdr:SetText(L["Import Profile"])
    profImpHdr:SetTextColor(0.65, 0.65, 0.72)

    local profImpNameLbl = panelProfiles:CreateFontString(nil,"OVERLAY",
        "GameFontHighlightSmall")
    profImpNameLbl:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -238)
    profImpNameLbl:SetText(L["Profile Name:"])

    local profImpNameBox = CreateFrame("EditBox", "HBMImportProfileNameBox",
        panelProfiles, "BackdropTemplate")
    profImpNameBox:SetSize(210, 24)
    profImpNameBox:SetPoint("LEFT", profImpNameLbl, "RIGHT", 6, 0)
    profImpNameBox:SetAutoFocus(false)
    profImpNameBox:SetFontObject(GameFontHighlightSmall)
    profImpNameBox:SetTextInsets(6, 6, 0, 0)
    profImpNameBox:SetMaxLetters(40)
    profImpNameBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    profImpNameBox:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    profImpNameBox:SetBackdropBorderColor(0.25, 0.3, 0.5, 0.7)

    -- Base64-Eingabefeld fuer Import
    local profImpBox = CreateFrame("EditBox", "HBMProfileImportBox",
        panelProfiles, "BackdropTemplate")
    profImpBox:SetSize(354, 40)
    profImpBox:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -266)
    profImpBox:SetAutoFocus(false)
    profImpBox:SetFontObject(GameFontNormalSmall)
    profImpBox:SetTextInsets(6, 6, 4, 4)
    profImpBox:SetMaxLetters(8192)
    profImpBox:SetMultiLine(true)
    profImpBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    profImpBox:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    profImpBox:SetBackdropBorderColor(0.25, 0.3, 0.5, 0.7)

    local profImpBtn = CreateFrame("Button", nil, panelProfiles, "UIPanelButtonTemplate")
    profImpBtn:SetSize(140, 24)
    profImpBtn:SetPoint("TOPLEFT", panelProfiles, "TOPLEFT", 12, -314)
    profImpBtn:SetText(L["Import Profile"])
    profImpBtn:SetScript("OnClick", function()
        local name = profImpNameBox:GetText()
        if not name or name:trim() == "" then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["Profile name required."] .. "|r")
            return
        end
        name = name:trim()
        local b64 = profImpBox:GetText()
        if not b64 or b64:trim() == "" then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["Invalid import string."] .. "|r")
            return
        end
        local decoded = Base64Decode(b64:trim())
        if not decoded or decoded == "" then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["Invalid import string."] .. "|r")
            return
        end
        local imported = DeserializeConfig(decoded)
        if not imported then
            print("|cFF80C0FFHealBot Midnight|r: |cFFFF4444" ..
                L["Deserialization error."] .. "|r")
            return
        end
        local db = HealBotMidnightDB
        if not db then return end
        if not db.profiles then db.profiles = {} end
        db.profiles[name] = {
            spells      = imported.spells or {},
            frameWidth  = imported.frameWidth,
            frameHeight = imported.frameHeight,
            columns     = imported.columns,
        }
        selectedProfile = name
        profDropText:SetText(name)
        profImpNameBox:SetText("")
        profImpBox:SetText("")
        print("|cFF80C0FFHealBot Midnight|r: |cFF00FF00" ..
            L["Profile saved!"] .. " (" .. name .. ")|r")
    end)

    ---------------------------------------------------------------------------
    -- BOTTOM: Speichern / Abbrechen
    ---------------------------------------------------------------------------
    local saveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveBtn:SetSize(130, 26)
    saveBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    saveBtn:SetText(L["Save"])
    saveBtn:SetScript("OnClick", function()
        if not HealBotMidnightDB then HealBotMidnightDB = {} end
        if not HealBotMidnightDB.spells then HealBotMidnightDB.spells = {} end

        -- Spells uebernehmen
        for key, spell in pairs(pendingSpells) do
            HealBotMidnightDB.spells[key] = spell
        end

        -- Slider
        HealBotMidnightDB.frameWidth  = math.floor(f.widthSlider:GetValue())
        HealBotMidnightDB.frameHeight = math.floor(f.heightSlider:GetValue())
        HealBotMidnightDB.columns     = math.floor(f.colSlider:GetValue())

        -- Optionen-Button
        local showOpt = f.optBtnCheck and f.optBtnCheck:GetChecked()
        HealBotMidnightDB.showOptionsButton = showOpt ~= false
        if HBM.optionsButton then
            if HealBotMidnightDB.showOptionsButton then
                HBM.optionsButton:Show()
            else
                HBM.optionsButton:Hide()
            end
        end

        -- Klassenfarben
        HealBotMidnightDB.classColors =
            f.classColorCheck and f.classColorCheck:GetChecked() or false

        -- HP als Zahl anzeigen
        HealBotMidnightDB.showHPNumbers =
            f.hpNumCheck and f.hpNumCheck:GetChecked() or false

        HBM.RebuildFrames()
        f:Hide()
        print("|cFF80C0FFHealBot Midnight|r: " .. L["Settings saved!"])
    end)

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(130, 26)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    cancelBtn:SetText(L["Cancel"])
    cancelBtn:SetScript("OnClick", function()
        pendingSpells = {}
        if HealBotMidnightDB and HealBotMidnightDB.spells then
            for _, key in ipairs(HBM.GetBindingKeys()) do
                pendingSpells[key] = HealBotMidnightDB.spells[key] or ""
            end
        end
        activeModifier = ""
        f:Hide()
    end)

    -- Erstes Panel anzeigen
    SetNavSelected(navButtons[1])
    ShowPanel("general")

    f:Hide()
    configFrame = f
    return f
end

-------------------------------------------------------------------------------
-- Toggle
-------------------------------------------------------------------------------

function HBM.ToggleConfig()
    if not configFrame then
        CreateConfigFrame()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        -- Pending Spells aus DB laden
        pendingSpells = {}
        if HealBotMidnightDB and HealBotMidnightDB.spells then
            for _, key in ipairs(HBM.GetBindingKeys()) do
                pendingSpells[key] = HealBotMidnightDB.spells[key] or ""
            end
        end
        activeModifier = ""
        playerSpells   = nil  -- Spell-Cache neu laden

        HBM.RefreshConfigUI()
        configFrame:Show()
    end
end
