# Heal Vision nameplates: test plan

Tick under test: Heal Vision page > Nameplates > **Health bars only while hurt**
(`healVisionPlates`). Code: end of HealVisionFrames.lua.

What the code does (read from the code, not tested): on a friendly player's or
minion's plate that the game lets addons reach, it sets the **health bar's**
alpha from Heal Vision's curve. Nothing else on the plate is touched. It
doesn't check whether the name shows.

So it can only show where the bar is showing anyway:
- **Outside CineMode:** the game's own friendly plates, if they're turned on and
  not name-only.
- **In CineMode:** only plates a Nameplates row keeps whole (your pet: My pet >
  Always). A plate cut down to its name (Names rows, your target's) has no bar
  to fade. A plate CineMode hides shows nothing.

Unexplained: in the 08-42 and 08-46 videos, Gelloz showed no name, bar or level
box at all with the tick on. Part A finds out whether the tick causes that.

## Setup, every part

- Gelloz out, at full health, **not targeted, not focused**.
- Settings window **closed** while you look (it changes what CineMode shows).
- Your pet thresholds as saved: shows below 35%, 5% while hidden.
- After any **no**: run `/cine debug healplates` once and note the step number.

## A. Outside CineMode

| Step | Do | Check (yes/no) |
|---|---|---|
| A1 | Tick **off** | Gelloz shows name, bar and level box? |
| A2 | Tick **on** | Bar almost gone, name and level box still there? |
| A3 | Tick **on** | Is Gelloz's name gone too? (yes = the unexplained bug) |
| A4 | Let a mob hit Gelloz below about a third | Bar comes back? |
| A5 | Let Gelloz heal to full | Bar fades again? |
| A6 | Target Gelloz | Bar shows (your target always does)? |
| A7 | Clear target, tick **off** | Everything back at once? |

## B. In CineMode

| Step | Do | Check (yes/no) |
|---|---|---|
| B1 | Tick **off**, go into CineMode | Gelloz shows its full plate (My pet > Always)? |
| B2 | Tick **on** | Bar almost gone, name and level box still there? |
| B3 | Tick **on** | Is Gelloz's name gone too? |

## C. Another player (only if one is near)

| Step | Do | Check (yes/no) |
|---|---|---|
| C1 | Tick **on**, outside CineMode, player at full health | Their bar almost gone, name still there? |

## D. Don't fade (Pets at 99%, Gelloz at full health, outside CineMode)

| Step | Do | Check (yes/no) |
|---|---|---|
| D1 | Don't fade = Name only (default) | Bar and level box gone, name stays? |
| D2 | Add Level to Don't fade | Level box comes back, bar stays gone? |
| D3 | Remove Name from Don't fade | Name fades too? |
| D4 | Set Don't fade back to Name only | Name back at once? |
| D5 | Gelloz casts or gets a buff (if it can) | Cast bar / buff icon faded too? |

`/cine debug healplates` lists, per plate, each part it faded and how many
layers: paste it after any **no**.

Stop at the first unexpected answer: the steps after it depend on it.
