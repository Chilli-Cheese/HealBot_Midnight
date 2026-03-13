> [!WARNING]
> ## 🚧 STILL UNDER CONSTRUCTION 🚧
> This addon is actively being developed and is not yet in a stable release state.

# HealBot Midnight

> A modern, lightweight healer addon for **World of Warcraft: Midnight** (12.0.1)
> Raid & Party frames with full click-casting — built from scratch for the new API.

---

## Features

- **Compact Raid/Party Frames** — color-coded health bars for your whole group at a glance
- **Click-Casting** — bind any spell to Left / Right / Middle click, each with Shift / Ctrl / Alt modifier support (12 bindings total)
- **HP Numbers** — live HP and deficit display on each frame, toggleable in options
- **Smart Spell Dropdown** — shows all spells your class has learned, with heal/buff spells sorted first
- **Profile System** — save, load, delete and export named configurations; share them via Base64 strings
- **Import / Export** — copy a compact Base64 string to share your full setup with others
- **German / English** — built-in deDE localization with enUS fallback

---

## Installation

1. Download the latest release (or clone this repo)
2. Copy the `HealBot_Midnight` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Log in and enable the addon in the **AddOns** menu on the character select screen

> **Note:** The addon folder name must match exactly: `HealBot_Midnight`

---

## Usage

| Command | Description |
|---|---|
| `/hbm` | Show available commands |
| `/hbm config` | Open the configuration window |
| `/hbm show` | Show raid/party frames |
| `/hbm hide` | Hide raid/party frames |
| `/hbm bindings` | Print current click-cast bindings to chat |
| `/hbm rebuild` | Rebuild all unit frames (useful after roster changes) |

---

## Configuration

Open the config window with `/hbm config` or the gear icon on the frame border.

### General
- Frame width, height, and number of columns
- Class-colored health bars (toggleable)
- HP numbers with deficit display (e.g. `-14.2k`)

### Click-Casting
- Select a **modifier** (None / Shift / Ctrl / Alt)
- Assign a spell from the dropdown to each of the three mouse buttons
- Bindings apply instantly outside of combat

### Profiles
- **Save** your current settings as a named profile
- **Load / Delete** profiles from the dropdown
- **Export** a profile as a Base64 string to share
- **Import** a profile by name + Base64 string

---

## Compatibility

| WoW Version | Status |
|---|---|
| Midnight 12.0.1 | ✅ Supported |
| The War Within 11.x | ❌ Not tested |
| Dragonflight 10.x | ❌ Not tested |

---

## Known API Quirks (Midnight)

- `UnitHealth()` / `UnitHealthMax()` return *secret numbers* — direct Lua arithmetic is tainted. HealBot Midnight uses a widget-readback pattern (`SetValue` → `GetValue`) to safely display HP.
- `UnitInRange()` returns a *secret boolean* — not directly comparable with `==`. Range checks use `CheckInteractDistance(unit, 4)` with `UnitIsConnected()` as fallback.
- `OptionsSliderTemplate` was removed in 10.0 — sliders are built manually.

---

## License

MIT — do whatever you want.
