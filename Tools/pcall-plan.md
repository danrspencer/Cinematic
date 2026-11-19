# Fewer pcalls: fix the cause, don't catch the error

Goal: Cinematic calls things only when they can work. A pcall stays only
where failing can't be known ahead of time, and every one that stays says why
and reports an unexpected failure. Started 2026-11-19, after the floating
combat text taint (Shoulder Cam moved the game's texts; a pcall hid nothing
there, but it's the same habit: try it and see).

## Where we are (2026-11-19)

2,396 pcall/xpcall calls in the addon's Lua (Tools/ left out).

| Kind                                  | Count |
|---------------------------------------|------:|
| method on an object (GetWidth, GetPoint, IsShown...) | 796 |
| game API (UnitReaction, GetSpellBaseCooldown...)     | 633 |
| inline `pcall(function() ... end)`    | 386 |
| C_ API                                | 151 |
| local function                        | 133 |
| RegisterEvent                         | 110 |
| our own `ns.*`                        |  99 |
| CreateFrame                           |  20 |
| other / tostring                      |  68 |

By folder: root 538 (Frames.lua 242, Diagnostics.lua 107, Effects.lua 74),
Style 407, Dev 353, Visions 338, UI 261, Camera 204, Plates 156.

## Why they're there (the root causes)

1. **Forbidden frames.** Nameplates in instances, some Blizzard frames. Any
   call errors. Check: `frame:IsForbidden()` (used 251 times already, not
   everywhere).
2. **Secret values in fights** (Forever and retail). Reading is fine, comparing
   or doing math errors in tainted code. Check: `issecretvalue(v)`,
   `issecrettable(t)`, and whatever else each client has (find out: step 1).
3. **Protected frames in combat.** Moving or showing them errors or is blocked.
   Check: `InCombatLockdown()`, `frame:IsProtected()`, then wait for
   PLAYER_REGEN_ENABLED.
4. **The client hasn't got it.** A function, method, event, template or C_
   table missing on some client. Check: look it up once at load (see step 2),
   not on every call.
5. **Not sure what the object is.** Other addons' frames, unknown regions,
   values from the game. Check: `type()`, `GetObjectType`, the method existing.
6. **Our own frames.** Getters on frames we made can't fail; those pcalls are
   habit and just go.
7. **Code that isn't ours runs.** Other addons' functions (Support/), the
   player's rules and scripts, Blizzard callbacks. Failing here can't be
   known ahead: these are the pcalls that stay.

## Steps

### 1. Find out what each client can check (one dev run per client)
A dev command that lists, on Forever and on retail: which secret checks exist
(`issecretvalue`, `issecrettable`, `canaccessvalue`, `canaccesstable`, any
"is this anchor secret" method on regions), `C_EventUtils.IsEventValid`, and
which templates we use exist. Written into this file. Nothing guessed.

#### Results: Forever (16001, build 70959, 2026-11-19)
- **Secret values:** `issecretvalue`, `issecrettable`, `canaccessvalue`,
  `canaccesstable`, `canaccessallvalues`, `canaccesssecrets`,
  `hasanysecretvalues`, `scrubsecretvalues`, `secretwrap`,
  `dropsecretaccess`. Out of a fight all say "not secret" as expected
  (`canaccesstable(5)` is false: it wants a table).
- **Secret before reading:** `C_Secrets` says ahead whether a read will be
  secret: `ShouldUnitHealthMaxBeSecret`, `ShouldUnitPowerBeSecret`,
  `ShouldAurasBeSecret`, `ShouldUnitAuraInstanceBeSecret`,
  `ShouldUnitSpellCastBeSecret`, `ShouldSpellCooldownBeSecret`,
  `ShouldUnitThreatValuesBeSecret`, `ShouldUnitIdentityBeSecret`,
  `ShouldUnitComparisonBeSecret`, `HasSecretRestrictions` and more (27).
- **On every region** (Frame, Button, StatusBar, Cooldown, FontString,
  Texture): `IsForbidden`, `IsProtected`, `CanChangeProtectedState`,
  `IsAnchoringSecret`, `IsAnchoringRestricted`, `HasSecretValues`,
  `HasSecretAspect`, `HasAnySecretAspect`, `IsPreventingSecretValues`,
  `HasAnyAccessRestrictions`, `CanBeAccessedInContext`.
  `IsAnchoringSecret` is the check the combat text follow needed.
- **Protected actions:** `C_RestrictedActions.CheckAllowProtectedFunctions`,
  `IsAddOnRestrictionActive`, `GetAddOnRestrictionState`.
- **Events:** `C_EventUtils.IsEventValid` agreed with RegisterEvent on all 95.
  Not on Forever: `GAME_PAD_BUTTON_DOWN` (Frames.lua:8294), `MINIMAP_PING`
  (Frames.lua:8089).
- **Templates:** `C_XMLUtil.GetTemplateInfo` agreed with CreateFrame on all
  17; every template we use exists.

So on Forever every cause 1-5 has a real check: no pcall is needed to find out.

#### Results: retail (120105, build 70961, 2026-11-19)
The same as Forever, line for line: every secret check, all 27 `C_Secrets`
functions, the same region methods (`IsAnchoringSecret` included),
`C_RestrictedActions`, `IsEventValid` and `GetTemplateInfo` agreeing every
time. `GAME_PAD_BUTTON_DOWN` and `MINIMAP_PING` don't exist here either, so
`ns.padEventOK` (Frames.lua:8294) is false on both clients: whatever hangs on
it never runs.

#### Not probed
The other clients in the TOC (Classic Era 11509/11508, 20506, 38000, 40402,
50504). They may lack some or all of these, so Checks.lua looks each one up
and treats a missing check as "nothing to check" (no secrets there), never as
an error.

### 2. One place for the checks (`Checks.lua`, loaded early)
Done 2026-11-19 as `ns.Check`: `Secret`, `Known`, `Number`, `True`, `Usable`,
`Movable`, `PlaceKnown` (IsAnchoringSecret), `ValuesKnown` (HasSecretValues),
`Api(path)`, `Event`, `RegisterEvent`, `RegisterUnitEvent`, `Template`.
Tested offline on a stand-in with and without the secret API. Not yet used
by any file (that's step 3). Open: whether `C_XMLUtil.GetTemplateInfo` errors
or returns nil for a missing template (the probe can't tell).

The original sketch:
- `ns.Can.X`: what this client has, read once at load (functions, methods,
  events, templates). The few probes that need a pcall (templates) live here
  and only here.
- `ns.Usable(frame)`: exists, not forbidden.
- `ns.Known(v)` / `ns.KnownNumber(v)`: not secret (replaces the copies of
  `Known` and `Number(pcall(...))` in PlateParts, PlateCastStyle and others).
- `ns.Movable(frame)`: not protected while in a fight.
- `ns.RegisterIfValid(frame, event)` instead of `pcall(RegisterEvent)`.

### 3. Fix file by file, fights first
Order: Plates, Style (cast, unit, raid, combat text), Camera/ShoulderCam,
Visions, Frames.lua, Effects.lua, UI, then the rest. Dev/ last (test code;
it may keep its pcalls).

For each pcall:
- cause 1-6: replace it with the check, and decide what to do when the check
  says no (skip, wait for the fight to end, use a fallback);
- cause 7: keep it, with a `-- pcall: <why>` comment, and send failures to
  `ns.ReportError(..., caught)` so /cine log and the dev error window see them.

One file per commit, so a regression points at one change.

### 4. Keep it from coming back
`Tools/pcall-audit.py`: counts pcalls per file and fails when a file has
more than its saved baseline, or a pcall with no `-- pcall:` reason. Run in
the pre-commit hook and prerelease. The baseline only goes down.

## Testing each batch
- `luacheck .`, `Tools/check-toc.py`, `Tools/prerelease.py`, the settings
  sweep offline.
- In game on Forever and retail (one-client rule: a fix for one must not
  change the other): one recorder run per batch, with the dev error window
  open. A removed pcall that was hiding a real failure now shows there, and
  that's the point: fix what it shows, don't put the pcall back.
- Fight tests where the batch touches fight code: a dungeon or a target dummy,
  CineMode off.

## Risks
- Taking a pcall out where the check is wrong turns a silent skip into an
  error for players. That's why each batch is tested in game on both clients
  before it ships, and why the dev error window comes first.
- Secret rules change with game patches. The checks live in one file
  (step 2), so a patch means one fix there, not hundreds.
