# Simple Frame Assistant

**A lightweight, Midnight-exclusive unit frame and utility addon** built for players who want clean, responsive frames without the bloat — plus a fully redesigned macro manager starting in v0.22.

---

## Overview

Simple Frame Assistant (SFA) provides compact, highly configurable friendly and enemy unit frames designed around arena and group play. It displays the information you actually need — health, debuffs, role icons, HoTs — and stays out of the way the rest of the time. Every element is optional and controlled through a single `/sfa` panel.

---

## Unit Frames

### Friendly Frames
Display your party and group with clean, role-aware layouts:
- **Class colors** on health bars
- **Debuff tracking** — shows debuffs currently on friendly units
- **Healer & Tank icons** — instant role recognition at a glance
- **HoT display** — option to show only your own HoTs (`Show my HoTs only`)
- **Auto-shrink for large groups** — frames scale down automatically when switching from small group to raid, keeping the UI clean
- **Blizzard raid frame suppression** — optionally hides the default raid frames so they don't overlap
- **Per-scenario positioning** — frame positions save separately for Arena, Dungeon, Raid 10, Raid 25, and open world
- **Fully configurable size, spacing, and scale**

### Enemy Frames
Arena-focused enemy display (defaults to arena1/2/3):
- **Class colors** and **role icons** (healer marker)
- **Debuff tracking**
- **Healer marker** highlights dangerous targets

### Click Actions
Both friendly and enemy frames support fully customizable click macros for every mouse button (Left, Right, Middle, Button4, Button5). Set any macro string per button — e.g., target on left-click, heal on right-click, dispel on middle-click.

---

## HUD Indicators

| Indicator | Description |
|-----------|-------------|
| **Character GCD** | Visual GCD tracker on your character frame |
| **Builder/Spender indicator** | Shows current resource state for builder/spender rotations |
| **Quest indicator** | Optional quest objective tracker overlay |
| **Target X mark** | Visual marker on your current target frame |

---

## Debuff Blacklist

Filter out unimportant debuffs from your frames. Add any spell by name through the `/sfa` panel — blacklisted spells will no longer appear on friendly or enemy frames, keeping the display clean during busy encounters.

---

## Alerts

- **Resource Voice Alerts** — audio cues triggered by resource thresholds; configurable volume, cooldown, and voice style (male/female)
- **Proc Ready Alerts** — define a list of spells; SFA announces when they become available

---

## Macro Manager *(v0.22.00)*

A fully custom macro window that replaces `/macro` when enabled in `/sfa → General`.

Open it with `/sfamacro` or enable **Redesign Macro Window** in options to redirect `/macro` to it.

### Auto-categorization
On open, SFA scans every global macro body and classifies it:
- **Global tab** — macros with no class-specific content (consumables, targeting, utility)
- **Class tab** (e.g. *Druid*) — macros using class spells detected from your live spellbook + a curated per-class keyword list
- **Character tab** (e.g. *Entaro*) — WoW's native character-specific macros, shown as-is

Detection re-runs every time the window opens, so edited macros are re-categorized automatically.

### Grid
- **8 columns × 4 rows = 32 macros per page** with `<` / `>` pagination
- Live macro count displayed per tab
- **Drag to action bar** directly from the grid

### Editor
- Click any macro to load it for editing
- Icon picker — type an icon name or texture ID
- Macro name field and multiline command body
- **Enter** inserts a new line (standard macro editor behavior)
- Character counter positioned clear of the Save button
- **Full keyboard capture** — keybindings do not fire while typing

### Autocomplete
Triggers automatically while typing:

| Context | Activates when | Examples |
|---------|---------------|---------|
| Slash commands | typing `/` | `/cast`, `/castsequence`, `/castrandom`, `/target`… |
| Conditions | inside `[` | `mod:alt`, `mod:ctrl`, `combat`, `stealth`, `mounted`… |
| Unit targets | typing `@` inside `[` | `@focus`, `@mouseover`, `@party1`, `@arena2`… |
| Spell names | after `/cast ` + 2 chars | live results from your spellbook |

`↑` `↓` to navigate · `Tab` or `Enter` to confirm · `Esc` to dismiss

---

## Options Panel — `/sfa`

- **Lock frames** — prevent accidental dragging
- **Hide header text** — cleaner look without labels
- **Minimap button** — toggle the SFA icon on the minimap
- **Redesign Macro Window** — enables the SFA Macro Manager and redirects `/macro`
- Friendly and Enemy sub-panels for full frame configuration
- Buff blacklist manager
- Click action editor

---

## Commands

| Command | Action |
|---------|--------|
| `/sfa` | Open the options panel |
| `/sfamacro` | Open SFA Macro Manager |
| `/macro` | Opens SFA Macro Manager if Redesign is enabled |

---

## Notes

- **Midnight exclusive** — built and tested for the Midnight private server (Interface 120005). Not supported on other clients.
- Lightweight by design — no external library dependencies.
- All settings persist per account via `SFA_DB` SavedVariables.

---


*Current version: 0.22.01*
