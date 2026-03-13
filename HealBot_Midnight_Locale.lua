-------------------------------------------------------------------------------
-- HealBot Midnight - Lokalisierung / Localization
-- Unterstuetzte Sprachen / Supported locales:
--   enUS (default/fallback)
--   deDE
--   frFR (partial)
--   ruRU (partial)
--
-- Verwendung in anderen Dateien:
--   local L = HBM_L
--   label:SetText(L["General Settings"])
--
-- Neue Sprachen: Einfach einen weiteren Block am Ende hinzufuegen.
-------------------------------------------------------------------------------

-- Metatable: Gibt den Key zurueck wenn keine Uebersetzung vorhanden ist
-- Dadurch sind unuebersetzte Strings automatisch auf Englisch (Key)
local L = setmetatable({}, {
    __index = function(t, k)
        -- Fehlendes L["..."] gibt den Key selbst zurueck (English Fallback)
        return k
    end,
    __newindex = function(t, k, v)
        if v ~= k then  -- Nur speichern wenn Translation sich von Key unterscheidet
            rawset(t, k, v)
        end
    end,
})

-- Global exportieren (wird in allen anderen Addon-Dateien als `local L = HBM_L` verwendet)
HBM_L = L

local locale = GetLocale()

-------------------------------------------------------------------------------
-- Deutsch / German (deDE)
-------------------------------------------------------------------------------
if locale == "deDE" then

    -- Sidebar-Kategorien
    L["General"]        = "Allgemein"
    L["Spells"]         = "Spells"       -- same
    L["Import/Export"]  = "Import/Export" -- same

    -- Panel: Allgemein
    L["General Settings"]               = "Allgemeine Einstellungen"
    L["Raid Frame Size"]                = "Raid-Frame Groesse"
    L["Width:"]                         = "Breite:"
    L["Height:"]                        = "Hoehe:"
    L["Columns:"]                       = "Spalten:"
    L["Display"]                        = "Anzeige"
    L["Show options button in main window"]
        = "Optionen-Button im Hauptfenster anzeigen"
    L["Use class colors for health bars"]
        = "Klassenfarben fuer Lebenspunktbalken verwenden"

    -- Panel: Spells
    L["Click-Cast Spells"]  = "Click-Cast Spells"  -- same
    L["Modifier:"]          = "Modifier:"           -- same
    L["No Modifier"]        = "Kein Modifier"
    L["Active:"]            = "Aktiv:"
    L["Left"]               = "Links"
    L["Right"]              = "Rechts"
    L["Middle"]             = "Mitte"
    L["(not assigned)"]     = "(nicht belegt)"

    -- Panel: Import/Export
    L["Import/Export Settings Description"] =
        "Alle Einstellungen als kompakten Base64-String exportieren\n" ..
        "oder einen gespeicherten String importieren.\n\n" ..
        "Das Format ist versions-kompatibel:\n" ..
        "  \xe2\x80\xa2 Neue Belegungen brechen keine alten Exports\n" ..
        "  \xe2\x80\xa2 Fehlende Keys behalten ihre Standardwerte"
    L["Import"]             = "Importieren"
    L["Export"]             = "Exportieren"
    L["Internal format info"]
        = "Internes Format: v:1|s:Key=Value|w:120|h:40|c:8  (Base64)"

    -- Popup-Titel
    L["Export - Copy string:"]  = "Export - String kopieren:"
    L["Import - Paste string:"] = "Import - String einfuegen:"

    -- Buttons
    L["Save"]   = "Speichern"
    L["Cancel"] = "Abbrechen"
    L["OK"]     = "OK"

    -- Spell-Dropdown
    L["(Empty)"]            = "(Leer)"
    L["--- Helpful Spells ---"]  = "--- Hilfreiche Spells ---"
    L["--- Other Spells ---"]    = "--- Andere Spells ---"

    -- ClickCast Labels
    L["Left Click"]   = "Linksklick"
    L["Right Click"]  = "Rechtsklick"
    L["Middle Click"] = "Mittelklick"
    L["Button4"]      = "Taste 4"
    L["Button5"]      = "Taste 5"
    L["Ctrl"]         = "Strg"   -- used in modifier labels
    -- "Shift" and "Alt" are the same in all locales

    -- Core Chat-Nachrichten
    L["Frames shown."]      = "Frames eingeblendet."
    L["Frames hidden."]     = "Frames ausgeblendet."
    L["Open Configuration"] = "Konfiguration oeffnen"
    L["HealBot Midnight\nOpen Configuration"]
        = "HealBot Midnight\nKonfiguration oeffnen"
    L["Changes will be applied after combat."]
        = "Aenderungen werden nach dem Kampf angewendet."
    L["Settings saved!"]    = "Einstellungen gespeichert!"
    L["Config module not loaded."]
        = "Config-Modul nicht geladen."
    L["Position reset."]    = "Position zurueckgesetzt."
    L["v0.0.1 loaded. Type /hbm for help."]
        = "v0.0.1 geladen. /hbm fuer Hilfe."
    L["Click-Cast bindings updated."]
        = "Click-Cast Bindings aktualisiert."
    L["Bindings will be updated after combat."]
        = "Bindings werden nach dem Kampf aktualisiert."
    L["No spells configured."]
        = "Keine Spells konfiguriert."
    L["Current Click-Cast Bindings:"]
        = "Aktuelle Click-Cast Bindings:"
    L["Import successful!"]     = "Import erfolgreich!"
    L["Invalid import string."] = "Ungueltiger Import-String."
    L["Deserialization error."] = "Fehler beim Deserialisieren."
    L["Show HP as number on frames"] = "HP als Zahl auf Frames anzeigen"

    -- Profile-System
    L["Profiles"]                    = "Profile"
    L["Saved Profiles"]              = "Gespeicherte Profile"
    L["No profile selected."]        = "Kein Profil ausgewaehlt."
    L["No profiles saved yet."]      = "Noch keine Profile gespeichert."
    L["Load"]                        = "Laden"
    L["Delete"]                      = "Loeschen"
    L["Save current settings as:"]   = "Aktuelle Einstellungen speichern als:"
    L["Profile Name..."]             = "Profilname..."
    L["Save as Profile"]             = "Als Profil speichern"
    L["Export Profile"]              = "Profil exportieren"
    L["Export selected Profile"]     = "Ausgewaehltes Profil exportieren"
    L["Import Profile"]              = "Profil importieren"
    L["Profile Name:"]               = "Profilname:"
    L["Paste Base64 string here..."] = "Base64-String hier einfuegen..."
    L["Profile saved!"]              = "Profil gespeichert!"
    L["Profile loaded!"]             = "Profil geladen!"
    L["Profile deleted!"]            = "Profil geloescht!"
    L["Profile name required."]      = "Profilname erforderlich."

end

-------------------------------------------------------------------------------
-- Franzoesisch / French (frFR) - Partial
-------------------------------------------------------------------------------
if locale == "frFR" then

    L["General"]        = "General"
    L["No Modifier"]    = "Sans modificateur"
    L["Active:"]        = "Actif :"
    L["Left"]           = "Gauche"
    L["Right"]          = "Droite"
    L["Middle"]         = "Milieu"
    L["(not assigned)"] = "(non assigne)"
    L["Import"]         = "Importer"
    L["Export"]         = "Exporter"
    L["Save"]           = "Sauvegarder"
    L["Cancel"]         = "Annuler"
    L["Width:"]         = "Largeur :"
    L["Height:"]        = "Hauteur :"
    L["Columns:"]       = "Colonnes :"
    L["Left Click"]     = "Clic gauche"
    L["Right Click"]    = "Clic droit"
    L["Middle Click"]   = "Clic milieu"
    L["Ctrl"]           = "Ctrl"

end

-------------------------------------------------------------------------------
-- Russisch / Russian (ruRU) - Partial
-------------------------------------------------------------------------------
if locale == "ruRU" then

    L["General"]        = "\xd0\x9e\xd0\xb1\xd1\x89\xd0\xb5\xd0\xb5"
    L["No Modifier"]    = "\xd0\x91\xd0\xb5\xd0\xb7 \xd0\xbc\xd0\xbe\xd0\xb4\xd0\xb8\xd1\x84\xd0\xb8\xd0\xba\xd0\xb0\xd1\x82\xd0\xbe\xd1\x80\xd0\xb0"
    L["Save"]           = "\xd0\xa1\xd0\xbe\xd1\x85\xd1\x80\xd0\xb0\xd0\xbd\xd0\xb8\xd1\x82\xd1\x8c"
    L["Cancel"]         = "\xd0\x9e\xd1\x82\xd0\xbc\xd0\xb5\xd0\xbd\xd0\xb0"
    L["Left"]           = "\xd0\x9b\xd0\xb5\xd0\xb2\xd0\xb0\xd1\x8f"
    L["Right"]          = "\xd0\x9f\xd1\x80\xd0\xb0\xd0\xb2\xd0\xb0\xd1\x8f"
    L["Left Click"]     = "\xd0\x9b\xd0\xb5\xd0\xb2\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd0\xb8\xd0\xba"
    L["Right Click"]    = "\xd0\x9f\xd1\x80\xd0\xb0\xd0\xb2\xd1\x8b\xd0\xb9 \xd0\xba\xd0\xbb\xd0\xb8\xd0\xba"
    L["Ctrl"]           = "Ctrl"

end
