# Heal Vision for nameplates: design plan

Player request (pkecerski, a healer): friendly players whose plates show only a
name give no sign that they're hurt. Turning on full friendly plates for
everyone clutters the screen.

Goal: friendly players' nameplates show health **only while they're hurt**,
the way Heal Vision shows party and raid frames.

## What the player sees

Threshold example: **Show below 90%**.

| Health | What shows |
|---|---|
| 100% to 90% | The name only, as now |
| Below 90% | The name plus a thin health bar under it (look A), or the name greyed from the right by the missing health (look B) |

The looks:

- **A. Bar:** our own thin health bar under the name, filled by health and
  faded in below the threshold. Clear at a glance. Uses the Nameplate Style
  page's bar texture, so it matches the enemy plates.
- **B. Name:** the name itself works as the bar: colored part = health left,
  grey part = health missing. No extra space. Hard to read on short names
  ("Bo").
- **C. Both:** the name greys and the bar shows.

Friendly plates that already show a full health bar (name-only off): the whole
plate fades out at full health and in below the threshold (the Heal Vision fade
on the plate).

## Where it works

| Place | Works | Why |
|---|---|---|
| Open world, inns | Yes | |
| Cities | Yes | |
| BGs & arenas | Probably, needs a test | not locked as far as we know |
| Dungeons, raids | **No** | the game locks friendly plates from addons (Effects.lua LOCKED_PLATE_SETS) |

Dungeons and Raids columns are **hidden** for this row, not greyed (they can
never be used). Group members there are covered by Heal Vision on the frames.

## How it works (the addon never learns anyone's health)

Health of other players is secret on Forever (even out of combat) and on retail
in fights. Everything goes through the game:

- Bar fill: `StatusBar:SetValue(UnitHealthPercent(unit))`, secret accepted
  (tested on frames 2026-10-18).
- Show below X%: `SetAlpha(UnitHealthPercent(unit, true, stepCurve))`, the same
  step curve Heal Vision builds (HealVisionFrames.lua Curve).
- Look B: a colored copy of our name text (PlateParts.lua DrawName) inside a
  clipping frame anchored to the bar fill's right edge. **Untested**: does
  anchoring to a fill edge driven by a secret value work?
- Updates: UNIT_HEALTH / UNIT_MAXHEALTH on nameplate units, NAME_PLATE_UNIT_ADDED
  and REMOVED.
- Players are found by GUID ("Player-"), not UnitIsPlayer (false on Forever
  for some friendly players).
- Plates owned by another addon (EllesmereUI, Plater...) are left alone, as
  PlateHealthStyle.lua does.

What it **can't** do (the addon never knows who's hurt): sort, list, sound or
alert on hurt players; remove a plate at full health (it's see-through but
still there, still stacks and may still be clicked).

## Settings

Recommended place: **Heal Vision page**, since it decides who shows by health.

- A second grid row under **Show in**: **Nameplates**, with its own Always,
  Location (Open world, Cities, BGs & arenas; no Dungeons, Raids), In combat,
  Calm Timer. Off to start with.
- In the health table, a new line: **Friendly players (nameplates)**,
  Show below health (default 90%) and Opacity while hidden (default 0%). It
  follows the role tabs like the other lines.
- **Look**: Bar / Name / Both (default Bar).
- **Who**: Everyone / Group members only (default Everyone).

Alternative: the Nameplates page's Friendly tab. It's where plates live, but
the health table and role tabs would have to be repeated there.

Needs friendly player plates turned on. If they're off, the row says so (with a
button to turn them on, name-only).

## Test steps (each one action + yes/no)

1. Open world, friendly player plates name-only, look Bar. A friend jumps from
   high up. Does a bar show under their name? Does it go once healed past 90%?
2. Same in a fight (target dummy, a friend hits it and takes damage).
3. Look Name. Is the right part of the name grey after the fall?
4. A battleground: does the bar show on a hurt teammate's plate?
5. A dungeon: nothing changes on friendly plates (expected).
6. Retail: steps 1, 2 and 4.

## Open questions

1. Heal Vision page or Nameplates page?
2. Which look to build first (A, B or both)?
3. Friendly pets and minions too, or players only?
4. Everyone, or a choice of group-only?
