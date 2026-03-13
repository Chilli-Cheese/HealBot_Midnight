-------------------------------------------------------------------------------
-- HealBotMidnight - Click-Casting Modul
-- Verwaltet die Zuordnung von Maustasten + Modifiern zu Spells
-- Verwendet SecureActionButtonTemplate (in Midnight weiterhin erlaubt)
-- WICHTIG: Alle SetAttribute-Aufrufe pruefen InCombatLockdown()
-- Unterstuetzt: None/Shift/Ctrl/Alt Modifier x Links/Rechts/Mitte
-------------------------------------------------------------------------------

local HBM = HealBotMidnight
local L = HBM_L  -- Lokalisierung (von HealBot_Midnight_Locale.lua gesetzt)

-------------------------------------------------------------------------------
-- Mapping von internen Keys zu SecureActionButton-Attributen
-- WoW SecureActionButton verwendet:
--   type1 = "spell"  -> Linksklick
--   type2 = "spell"  -> Rechtsklick
--   type3 = "spell"  -> Mittelklick
--   Mit Modifier-Prefix: shift-type1, ctrl-type1, alt-type1 usw.
-------------------------------------------------------------------------------

-- Alle unterstuetzten Klick-Kombinationen (4 Modifier x 3 Buttons = 12)
local CLICK_BINDINGS = {
    -- { DB-Key,             type-Attribut,       spell-Attribut }
    -- Ohne Modifier
    { "LeftButton",          "type1",             "spell1"          },
    { "RightButton",         "type2",             "spell2"          },
    { "MiddleButton",        "type3",             "spell3"          },
    -- Shift
    { "ShiftLeftButton",     "shift-type1",       "shift-spell1"    },
    { "ShiftRightButton",    "shift-type2",       "shift-spell2"    },
    { "ShiftMiddleButton",   "shift-type3",       "shift-spell3"    },
    -- Ctrl
    { "CtrlLeftButton",      "ctrl-type1",        "ctrl-spell1"     },
    { "CtrlRightButton",     "ctrl-type2",        "ctrl-spell2"     },
    { "CtrlMiddleButton",    "ctrl-type3",        "ctrl-spell3"     },
    -- Alt
    { "AltLeftButton",       "alt-type1",         "alt-spell1"      },
    { "AltRightButton",      "alt-type2",         "alt-spell2"      },
    { "AltMiddleButton",     "alt-type3",         "alt-spell3"      },
    -- Taste 4
    { "Button4",             "type4",             "spell4"          },
    { "ShiftButton4",        "shift-type4",       "shift-spell4"    },
    { "CtrlButton4",         "ctrl-type4",        "ctrl-spell4"     },
    { "AltButton4",          "alt-type4",         "alt-spell4"      },
    -- Taste 5
    { "Button5",             "type5",             "spell5"          },
    { "ShiftButton5",        "shift-type5",       "shift-spell5"    },
    { "CtrlButton5",         "ctrl-type5",        "ctrl-spell5"     },
    { "AltButton5",          "alt-type5",         "alt-spell5"      },
}

-- Maustasten-IDs (fuer Config UI)
HBM.MOUSE_BUTTONS = { "LeftButton", "MiddleButton", "RightButton", "Button4", "Button5" }

-- Maustasten-Labels (lokalisiert)
HBM.MOUSE_BUTTON_LABELS = {
    LeftButton   = L["Left"],
    RightButton  = L["Right"],
    MiddleButton = L["Middle"],
    Button4      = L["Button4"] or "Taste 4",
    Button5      = L["Button5"] or "Taste 5",
}

-- Modifier-Prefixe (lokalisiert)
HBM.MODIFIER_PREFIXES = {
    [""]      = L["No Modifier"],
    ["Shift"] = "Shift",
    ["Ctrl"]  = L["Ctrl"],
    ["Alt"]   = "Alt",
}

-- Baut den DB-Key aus Modifier-Prefix und Button
-- z.B. GetDBKey("Shift", "LeftButton") -> "ShiftLeftButton"
-- z.B. GetDBKey("", "LeftButton") -> "LeftButton"
function HBM.GetDBKey(modifier, button)
    if modifier == "" then
        return button
    end
    return modifier .. button
end

-------------------------------------------------------------------------------
-- Click-Cast Attribute auf einen Frame setzen
-- SCHUTZ: Wird nicht im Kampf ausgefuehrt (SecureButton-Restriktion)
-------------------------------------------------------------------------------

function HBM.UpdateClickCastAttributes(frame)
    if InCombatLockdown() then return end
    if not frame or not HealBotMidnightDB or not HealBotMidnightDB.spells then
        return
    end

    local spells = HealBotMidnightDB.spells

    for _, binding in ipairs(CLICK_BINDINGS) do
        local dbKey = binding[1]
        local typeAttr = binding[2]
        local spellAttr = binding[3]

        local spellName = spells[dbKey]

        if spellName and spellName ~= "" then
            frame:SetAttribute(typeAttr, "spell")
            frame:SetAttribute(spellAttr, spellName)
        else
            if typeAttr == "type1" then
                frame:SetAttribute(typeAttr, "target")
            else
                frame:SetAttribute(typeAttr, "")
            end
            frame:SetAttribute(spellAttr, "")
        end
    end
end

-------------------------------------------------------------------------------
-- Alle aktiven Frames mit neuen Click-Cast Bindings aktualisieren
-------------------------------------------------------------------------------

function HBM.RefreshAllClickCasts()
    if InCombatLockdown() then
        print("|cFF80C0FFHealBot Midnight|r: " .. L["Bindings will be updated after combat."])
        return
    end

    if not HBM.unitFrames then return end

    for _, frame in ipairs(HBM.unitFrames) do
        if frame and frame:IsShown() then
            HBM.UpdateClickCastAttributes(frame)
        end
    end

    print("|cFF80C0FFHealBot Midnight|r: " .. L["Click-Cast bindings updated."])
end

-------------------------------------------------------------------------------
-- Hilfsfunktion: Gibt den lesbaren Namen einer Tastenkombination zurueck
-------------------------------------------------------------------------------

function HBM.GetBindingLabel(dbKey)
    local lLeft   = L["Left"]
    local lRight  = L["Right"]
    local lMiddle = L["Middle"]
    local lCtrl   = L["Ctrl"]
    local lBtn4   = L["Button4"] or "Taste 4"
    local lBtn5   = L["Button5"] or "Taste 5"
    local labels = {
        ["LeftButton"]        = L["Left Click"],
        ["ShiftLeftButton"]   = "Shift + " .. lLeft,
        ["CtrlLeftButton"]    = lCtrl .. " + " .. lLeft,
        ["AltLeftButton"]     = "Alt + " .. lLeft,
        ["RightButton"]       = L["Right Click"],
        ["ShiftRightButton"]  = "Shift + " .. lRight,
        ["CtrlRightButton"]   = lCtrl .. " + " .. lRight,
        ["AltRightButton"]    = "Alt + " .. lRight,
        ["MiddleButton"]      = L["Middle Click"],
        ["ShiftMiddleButton"] = "Shift + " .. lMiddle,
        ["CtrlMiddleButton"]  = lCtrl .. " + " .. lMiddle,
        ["AltMiddleButton"]   = "Alt + " .. lMiddle,
        ["Button4"]           = lBtn4,
        ["ShiftButton4"]      = "Shift + " .. lBtn4,
        ["CtrlButton4"]       = lCtrl .. " + " .. lBtn4,
        ["AltButton4"]        = "Alt + " .. lBtn4,
        ["Button5"]           = lBtn5,
        ["ShiftButton5"]      = "Shift + " .. lBtn5,
        ["CtrlButton5"]       = lCtrl .. " + " .. lBtn5,
        ["AltButton5"]        = "Alt + " .. lBtn5,
    }
    return labels[dbKey] or dbKey
end

-------------------------------------------------------------------------------
-- Gibt alle Binding-Keys in geordneter Reihenfolge zurueck
-------------------------------------------------------------------------------

function HBM.GetBindingKeys()
    local keys = {}
    for _, binding in ipairs(CLICK_BINDINGS) do
        table.insert(keys, binding[1])
    end
    return keys
end

-------------------------------------------------------------------------------
-- Debug: Aktuelle Bindings ausgeben
-------------------------------------------------------------------------------

function HBM.PrintBindings()
    if not HealBotMidnightDB or not HealBotMidnightDB.spells then
        print("|cFF80C0FFHealBot Midnight|r: " .. L["No spells configured."])
        return
    end

    print("|cFF80C0FFHealBot Midnight|r - " .. L["Current Click-Cast Bindings:"])
    for _, binding in ipairs(CLICK_BINDINGS) do
        local dbKey = binding[1]
        local spellName = HealBotMidnightDB.spells[dbKey] or ""
        local label = HBM.GetBindingLabel(dbKey)
        if spellName ~= "" then
            print("  " .. label .. " = |cFF00FF00" .. spellName .. "|r")
        else
            print("  " .. label .. " = |cFF888888" .. L["(not assigned)"] .. "|r")
        end
    end
end
