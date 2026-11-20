# Loose parts plan: a fade that reaches every detached child

Status: planned 2026-11-20, nothing built. Trigger: a player on Forever with FlareUI 6.13 (support case
"gryphons back"). FlareUI calls `SetIgnoreParentAlpha(true)` on `MainActionBar.EndCaps.LeftEndCap/RightEndCap`,
so our fade of action bar 1's art no longer reached them and `/cine why` said HIDDEN while they showed. The
gryphon-only fix (`barArtSeen.caps` in Frames.lua, Tools/offline/gryphons.lua) handles that one case; this
plan makes it general so the next addon (or game patch) that detaches a part doesn't need its own fix.

## The problem in one line

A frame we fade only hides what follows its alpha. Any child or region that ignores its parent's alpha
(set by the game, by another addon, or flipped later) stays drawn while we report the frame as hidden.

## What we already have

- `LooseParts` / `FadeLooseParts` (Frames.lua ~323-360): finds regions ignoring parent alpha a few levels
  down and fades them along (alpha x their own), back to their own alpha after. Only for the raid groups
  (`LOOSE_PART_GROUPS`), found once per frame.
- `ns.DetachWhileFading` (Frames.lua ~783): our OWN detached parts (cast bars, minimap header, bar art...).
  These must never be treated as loose: they fade by their own row.
- `RecomputeNesting` already stops a parent's fade at a frame ignoring it.
- AutoHideUI 1.2.31 (looked at for ideas): forces `SetIgnoreParentAlpha(false)` on known children and
  replaces methods with no-ops. We won't replace methods (taint, and our own rule: hooks only).

## Design

1. **Every managed entry gets loose parts**, not just raid groups. `LooseParts(entry.frame, depth)` walks
   children and regions (depth 3, skips forbidden frames, secret answers count as "not loose") and keeps
   the ones ignoring parent alpha, minus:
   - frames that are entries themselves (`seen[part]`): they fade by their own row
   - our own detached parts (`parts` in the DetachWhileFading block)
   - a short allow-list of parts the game means to stay up while the frame is faded (found by the
     survey in step A; e.g. a raid target's selection outline already handled today)
   - parts a Support file says belong to the addon (`ns.KeepLoose(region)`, new, for an addon whose
     own fade we must not fight)
2. **Fade them with the frame.** `FadeLooseParts` for every entry: while the entry's visual alpha < 1, a
   part gets `alpha x its own`; back at 1 it gets its own alpha back, but only if it still holds what we
   set (someone else changed it meanwhile: theirs wins, nothing restored over it).
3. **Kept down.** A part raised by another addon while we have it down is put back. Two ways, cheapest
   first: (a) the existing settle pass (`ReapplyIfChanged` on faded entries each tick) also checks its
   loose parts' alpha against what we set; (b) a `hooksecurefunc(part, "SetAlpha")` only for parts seen
   raised twice (like the gryphons), so steady parts cost nothing.
4. **Found again when things change.** A part can be detached after we scanned (FlareUI does it on its
   refresh). Rescan an entry's loose parts: when its fade starts (alpha leaving 1), on
   PLAYER_ENTERING_WORLD and UI_SCALE/EDIT_MODE_LAYOUTS_UPDATED, and on a slow spread pass (one entry per
   frame, only faded entries) so a full cycle takes a few seconds. No per-frame full walks.
5. **Shown in `/cine why`.** The frame's card lists "N parts ignore its fade; faded along" with their names,
   and any part it couldn't fade (forbidden, secret, kept by a Support file). A case like FlareUI's then
   shows in the first report instead of three rounds of questions.
6. **Gryphon fix folded in.** Once this covers EndCaps' children, `barArtSeen.caps` goes and
   gryphons.lua tests the general path (same checks).

## Limits and risks

- **Lua locals cap**: Frames.lua's main chunk is at 200. Everything new lives on `ns`, on an existing
  table, or in a `do` block. luacheck misses this; the offline load catches it (gryphons.lua did).
- **Cost**: city with 40 plates is ~0.8 ms/frame today (cpu-profiling memory). Budget for this: scans
  spread to ~0.05 ms/frame, nothing per frame for steady parts. Measure with the Profiler page before and
  after (compare ms, not %).
- **Secret values** (both clients, in fights): `IsIgnoringParentAlpha` or `GetAlpha` reading secret =
  part skipped / own alpha taken as 1, as LooseParts does now.
- **Forbidden / protected**: forbidden skipped. SetAlpha on protected frames is allowed in fights, but a
  part inside a frame locked in fights must still be checked in game (unit frames, bar 1).
- **Intended loose parts**: the game keeps some parts up on purpose (glows, alerts). Fading them with a
  frame that's fully hidden is what the player asked for; the survey decides any exceptions.
- **One-client fixes**: behavior must be the same on Forever and retail; any exception is per client
  and tested on both.

## Steps

A. **Survey (dev only, no behavior change).** `/cine debug loose`: for every managed entry, the parts
   ignoring parent alpha (name or debug name, depth, current alpha, shown), to the log. Run once with
   Cinematic alone and once with the user's usual addons, on Forever and retail. Decides the allow-list
   and shows how many parts we're talking about (cost).
B. **Fade every entry's loose parts** (design 1-2), offline test extended: a stand-in frame with a
   detached region and child, faded out, half, back up, someone else's alpha kept.
C. **Keep down + rescan** (design 3-4), offline: a part detached after the scan, a part raised while
   faded.
D. **`/cine why` lines** (design 5).
E. **Fold in the gryphon fix** (design 6), gryphons.lua unchanged and passing.
F. **In game, one self-running test** `/cine debug loosetest`: turns CineMode off for the test's own
   steps, makes a texture of ours inside a faded frame ignore its parent, fades the frame, raises the
   part, brings the frame back, logs each step's alpha and its own PASS/FAIL, screenshots, says DONE.
   Run on Forever and retail, then once more with FlareUI on Forever for the gryphons.
G. Profiler before/after (city), sweep baseline, prerelease.

## Open questions

- Depth: 3 levels covers bars and unit frames; the minimap cluster and chat go deeper. Per-group depth?
- Should a row set to Hidden also keep the frame itself down against other addons (AutoHideUI's
  `forceAlpha` idea, done with hooks)? Separate from this plan; worth its own.
