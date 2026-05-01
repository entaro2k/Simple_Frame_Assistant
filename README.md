# Simple Frame Assistant (SFA)

Lightweight PvP / PvE helper addon for World of Warcraft  
Focused on clarity, speed, and minimal UI clutter.

---

## ✨ Features

### 🟢 Friendly Frames
- Solo → shows only player
- Party / Raid → automatically displays group members
- Clean vertical / grid layout for large groups
- Click-cast macros (Left / Right / Middle / extra buttons)
- Buffs (on bar) & debuffs (below bar)
- Optional class-colored health bars
- Healer (+) and Tank (shield) indicators

---

### 🔴 Enemy Frames
- Arena enemy tracking (auto slots)
- World → shows current hostile target only
- Target highlight (border)
- Click-cast support (Cyclone, Roots, etc.)
- Class-colored health bars (optional)

---

### 🧠 Smart Assist

Advanced automation & awareness tools:

#### 🎯 Visual Assist

- ❌ **Target Marker**
  - Red **X above nameplate** for current target
  - Optional builder–spender orb when resource is full

- ❗ **Quest Indicator**
  - Yellow **! above NPCs** related to active quests or scenarios
  - Smart detection using tooltip data (safe, no taint)

---

#### 🔊 Voice Assist

- Triggers when builder–spender resource is full:
  - COMBO FULL
  - CHI FULL
  - HOLY POWER FULL
  - SOUL SHARDS FULL
  - ESSENCE FULL

- 🎧 Voice styles:
  - Male
  - Female (smooth, natural tone)

- 🎚️ Adjustable voice volume (0–10)
- ⏱️ Configurable alert cooldown

- 🔄 Trigger conditions:
  - On reaching full resource
  - On ability usage while resource is full

---

### ⚔️ Simulation Mode
Test the UI without combat.

Available modes:
- Arena 3v3
- Dungeon (5-man)
- Raid (10 / 25)
- World

Simulates:
- roles (healer / tank / dps)
- buffs & debuffs
- realistic layouts
- target states

---

### ⚙️ Options Menu

Available in:
ESC → Options → AddOns → Simple Frame Assistant  
or via command: `/sfa`

Sections:
- General
- Friendly Frame
- Enemy Frame
- Smart Assist
- Simulation

---

### 🔵 Additional Features

- Builder–spender resource indicator (combo / holy power / etc.)
- Enemy target **X marker**
- Quest objective detection on nameplates
- Estimated / One-Button GCD display in Character window

---

## 🚀 Design Goals

- Minimal UI clutter
- Fast updates (arena-ready)
- No taint / safe API usage
- Clear visual + audio feedback

---

## 🧩 Compatibility

- Designed for WoW Midnight
- Compatible with Interface: 120005+

---

## 📌 Notes

- Positions are saved per context (Arena / Party / Raid / World)
- Click-cast macros support `[unit]` expansion automatically
- Voice alerts use custom `.ogg` files (user-replaceable)


