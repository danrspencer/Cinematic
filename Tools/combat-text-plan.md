# Combat Text Style: plan (2026-11-10)

## Goal
Hide the game's "XP: 35" floating text while keeping damage and healing numbers.
The game can't hide XP alone (searched every CVar, both clients). One font draws
all of its floating world text. So we:

1. blank that font (the existing `hideWorldText`: `DAMAGE_TEXT_FONT` -> Fonts/Blank.ttf, game restart), and
2. draw our own damage and healing numbers on nameplates, made to look like the game's.

Tested 2026-11-10 on Forever: blank font + Forever Combat Text = XP gone, damage numbers kept.
This plan builds the second half into Cinematic.

Bonus: our numbers are UI text, so they sit above nameplates (the original wish 2).

## Where it lives
A new **Style hub page, "Combat Text Style"**, in the Overhead section
(next to Nameplate, Name, Cast Bar and Chat Bubble Style).
HUBS entry in Options.lua: `{ "Combat Text Style", <icon>, label = "Combat Text Style", section = "Overhead" }`.
New file: `CombatTextStyle.lua` (toc: next to PlateCastStyle.lua).

Page layout, top to bottom (StyleRows, like Cast Bar Style):
- **Enable Page** (`combatTextStyle`, off by default)
- **Preview**: our numbers popping over a sample plate, drawn by the real code (ns.StyleScene)
- **Hide the game's floating text** (restart required). This is the existing `hideWorldText`,
  moved here from the CineMode page (decided 2026-11-10; same saved key, so players keep their choice;
  `/cine find` and the docs point here). It works with the page's Enable off too? No: page off =
  off ([[page-switch-gates-all]]), so turning the page on is part of using it. Migration: a player
  with hideWorldText on gets combatTextStyle on, so nothing they had changes.
- **Look**: "Game" (default: match the game's) or our Style theme (font, outline, shadow from General)
- **Show**: damage, crits bigger, healing, misses (Miss / Dodge / Parry / Immune...), on all enemy plates or the target only
- **Size** (times the game's), **Height** above the plate
- **Colors**: game's (white / yellow crit / green heal), or by damage school

Page off = everything on it off ([[page-switch-gates-all]]).

## How it works
- **Data**: `RegisterUnitEvent("UNIT_COMBAT", "nameplateN")` for each plate, on
  NAME_PLATE_UNIT_ADDED / REMOVED. Args: action (WOUND, HEAL, MISS, DODGE, PARRY,
  BLOCK, RESIST, IMMUNE, ABSORB...), flag (CRITICAL, CRUSHING, GLANCING), amount, school.
  The amount may be secret: never compare it, only `SetText` it (works on Forever, per
  Forever Combat Text). An action we can't read: skip it.
- **Placement**: a FontString pool, each anchored to its plate (the base plate, not
  the faded UnitFrame, like the Questie plate icon). Forbidden plates (retail
  dungeons) can't be anchored to: no numbers there.
- **Motion**: copy the game's, from its own CVars (read live, not hard-coded):
  `WorldTextRampDuration_v2` (1 s life), `WorldTextRampPow_v2` 1.9 / `RampPowCrit_v2` 8
  (easing; crit pop), `WorldTextGravity_v2` 0.5, `WorldTextRandomZMin/Max_v2` 0.8-1.5,
  `WorldTextNonRandomZ_v2` 2, `WorldTextMinAlpha_v2` 0.5 (fade floor), `WorldTextScale_v2` (size).
  The meaning of each one is a guess until the side-by-side test below.
  Move and fade only, no SetScale animation ([[text-growth-wobbles]]): the crit pop is a
  bigger font size picked at the start, not a growing one.
- **Font**: the game's `DAMAGE_TEXT_FONT` value saved at ADDON_LOADED *before* we blank it
  (Fonts\FRIZQT__.TTF on Forever); "Look: Style theme" uses General's font.
- **One OnUpdate** for all live numbers, via ns.SetOnUpdate, stopped when none are showing.
- **Other addons**: if Forever Combat Text or MSBT's nameplate text is on, ours stays off
  (an Addon Support row; no double numbers).

## Known gaps (tell players)
- A unit with no visible plate gets no numbers (the game's text has no such limit).
- **Whose damage (built 2026-11-10, untested in a group)**: a hit is yours when a combat log
  line (COMBAT_LOG_MESSAGE, protected text) comes within 0.15 s of it, one line per hit;
  hits on you and your pet take their own lines. Relies on Blizzard's combat log filter being
  "yours" (its default); we keep its filtered events on while our numbers are on.
  The same idea is MSBT's first test. Old note: UNIT_COMBAT doesn't say who hit. Solo that's yours anyway; in a group,
  everyone's hits would show. Options: show on your target only in groups, or later try
  `COMBAT_LOG_MESSAGE` (unrestricted log lines, needs `C_CombatLog.SetFilteredEventsEnabled`)
  to keep only yours. Phase 3.
- **Your own hits taken and heals**: the game also shows red "-8" and green "+8" low over
  your character (seen 2026-11-10). The blank font hides those too. We'd need a spot for
  them: the personal plate if shown, else low screen center. Not built yet.
- No shrinking with distance (the game's is 3D). Maybe later: scale by the plate's own scale.

## Probe results (Forever, 2026-11-10)
- Amount: always secret, but SetText works. Action, flag and school: plain. Plates: open.
- Use per-plate listeners: the all-units listener gets each hit 3-4 times (nameplate1, target, softenemy).
- COMBAT_LOG_MESSAGE text is a protected `|Ky..|k` string: no use for "whose hit". Groups: target only.
- Still to see: a crit (flag), a heal, and retail.

## Built 2026-11-10 (untested in game)
- The page: Style hub > Overhead > Combat Text Style (CombatTextStyle.lua's CreateCombatTextStylePanel).
- "Turn off the game's damage and healing numbers" (combatTextHideGame, on by default): their CVars at once,
  through a playerWins CVar set, put back when the page goes off.
- Hide all (hideWorldText) moved here; Core gates it by the page; migration keeps old users as they were.

## Steps
1. **Probe** (`/cine debug combattext`, dev): log UNIT_COMBAT args per plate for 20 s:
   which are secret, which actions come, on Forever, then retail. Decides the retail scope.
2. **Engine**: CombatTextStyle.lua: the pool, events, motion, colors. Dev-only at first.
3. **Side-by-side tuning**: with the blank font off, ours and the game's show together.
   Tune motion, size, start height until they match. Video frames (ffmpeg) to compare.
4. **Page**: the Style page, preview, the settings above, defaults in ns.DEFAULTS, Reset.
5. **Hide switch moved** from the CineMode page (Options.lua "Combat text" area) to this page,
   with the migration above; Why/Inspect line if it hides anything.
6. **Phase 3** (later): group attribution via COMBAT_LOG_MESSAGE; distance scale.
7. Before the commit: luacheck, local count check ([[lua-local-cap]]), what's new skill, feature doc.

## Test steps (simple: one action, yes/no)
- Forever, solo: hit a mob: do our numbers show on its plate? Crit bigger? Heal green?
- Kill it: no "XP: 35"? (blank font on, after restart)
- Side by side: do ours and the game's move the same way?
- Retail: same, plus a dungeon (forbidden plates: expect none).
