# Simple Frame Assistant (SFA)

Click-and-cast on Blizzard's own frames — keep the frames you already positioned and styled with the native Edit Mode, and just add fast one-click spells on top.

## Why it's different

Most click-cast addons come with their own unit frames, which means re-doing your layout, losing Edit Mode, and running two frame systems side by side. SFA doesn't touch your frames at all — it drops your Left / Right / Middle click macros straight onto Blizzard's real Player, Target, Focus, Party, Raid, and Arena frames. Move them, resize them, skin them with Edit Mode or any layout addon you like; SFA just makes them clickable.

## Features

- **Click-cast on native frames** — Player, Target, Focus, Party/Raid (any layout, any group size), and Arena enemy frames. Left / Right / Middle, separate macros for friendly and enemy, per specialization.
- **Per-spec macros** — set once per specialization, switches automatically with your spec.
- **Modifier bypass, per button** — choose which of Ctrl/Alt/Shift (held together) makes Left-click select the unit instead of casting, or Right-click open Blizzard's real context menu instead of casting — no need to disable click-cast to reach either.
- **Turn it off per group, any time** — a "disable click-cast" toggle for Friendly or Enemy instantly hands the clicks back to Blizzard's own defaults, no need to disable the whole addon.
- **Redesigned macro window** (optional) — organizes Blizzard's macro UI into Global / Class / Character tabs.

## Smart Assist

- **Proc-ready voice alerts** — announces a chosen spell out loud, once, the moment it comes off cooldown and is usable, using the game's built-in Text-to-Speech. Pick the exact TTS voice installed on your system, with Prev/Next/Test controls, plus adjustable volume and cooldown.
- **Auto-sell junk** (optional, off by default) — automatically sells gray (Poor quality) items from your bags whenever you open a merchant window.
- **Cursor Ring** — a colored ring around your mouse cursor, adjustable color, size, and thickness.
- Quest-objective `!` marker on nameplates.
- Enemy target `X` marker on the current target's nameplate.
- Estimated GCD readout under the Character window.
- Optional minimap button.

## Options

`/sfa`, or Esc → Options → AddOns → Simple Frame Assistant.

## Compatibility

World of Warcraft: Midnight (Interface 120100, 120105), WoW Forever / Classic+ (beta, Interface 16001), and Classic Era (Interface 11509). Click-cast is confirmed working on Midnight.

Click-cast relies on a secure-macro engine feature that Blizzard's client compiles on demand; on a client build where that compile fails, SFA detects the failure directly (by attempting the real operation, not by guessing from client version) and disables click-cast cleanly for that login (a one-time chat message explains why instead of an error) — everything else (options panel, per-spec macro storage, Proc-ready voice alerts, auto-sell junk, Cursor Ring, quest/target markers, GCD readout) keeps working normally regardless. This is currently known to fail on the WoW Forever beta (confirmed, tracked upstream as a Blizzard-side bug); Classic Era's status isn't fully confirmed yet. Because the check reacts to what actually happens on each login rather than assuming based on which client it is, click-cast will start working again on its own, with no addon update needed, the moment Blizzard fixes it on any given client.
