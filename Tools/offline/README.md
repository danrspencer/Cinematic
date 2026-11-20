# Offline tools

The addon loaded outside the game, for checks and for looking at the profile modules. They need Lua 5.1
(`sudo apt install lua5.1`) and run from the repo root. Not packaged (`.pkgmeta` leaves `Tools` out).

Without Lua 5.1 (Windows), run any of them through `run.py` instead, which uses Python's lupa (`pip install lupa`):
`python -I Tools/offline/run.py Tools/offline/check.lua`. It runs each client's part through itself too, so nothing
looks for `lua5.1`. (Don't put a `lua5.1` stand-in on PATH: Windows asks what to open it with.)

- `wow.lua`: a stand-in for the game. Frames keep their parent, scripts, events and text; any other API call or global
  hands back a do-nothing stub.
- `load.lua`: loads a .toc's files in order on the stand-in, then fires `ADDON_LOADED` and `PLAYER_LOGIN` as a fresh
  install, so every options page is built.
- `check.lua`: `lua5.1 Tools/offline/check.lua` runs the profile modules' checks (ProfileModules.lua) on both clients
  and both builds. It exits 1 on any problem. CI runs it on every push (`.github/workflows/checks.yml`).
  It also compares each built-in profile's settings, retired ones too, with `profile-settings-<client>.txt`, so a
  change to a module or a choice shows in every profile it reaches. When that change is meant, run it with
  `--update` to save the new settings, and commit the files with the change.
- `sweep.lua`: `lua5.1 Tools/offline/sweep.lua <forever|retail>` runs the settings sweep (Dev/Sweep.lua) on the
  stand-in: every page opened, every setting changed and put back. The stand-in's stubs make FAIL lines of their own,
  so they're compared with `sweep-baseline-<client>.txt` and only new ones fail it; `--update` saves this run's as
  the baseline. `SWEEP_DEBUG=1` prints one raw line per erroring code line.
- `partyflicker.lua`: a stand-in for DaylightUI's party tile dimming itself by a secret range answer
  (SetAlphaFromBoolean), checked against our fade: its dim kept while not faded, our fade back at once while faded.
  An optional .toc argument runs it on other code (a copy with an older Frames.lua, say).
- `tooltiplocation.lua`: the Tooltips page's Location row. A party member's zone on their short tooltip goes
  by it, apart from Spec and class, and a full tooltip's faction line under the class isn't taken for the zone; the
  update starts Location as Spec was set.
- `loopsoff.lua`: a feature loop runs no update loop with its page off, even with the page's rows ticked, and
  starts again with the page (Heal Vision's kept going every frame). And the settings pages made ahead wait while
  `/cine debug loops` measures, so their time isn't counted as the loops'.
- `chatdefault.lua`: the Chat page's Show just those messages copies lines only with the game's own chat; with
  EllesmereUI's, ElvUI's or Glass's window (a chat window link claim) or Chattynator a message shows the window.
- `cardwait.lua`: the Rested card waiting while DaylightUI's zone title shows (ns.AddCardWait), on a clock of its
  own: waits, shows once the title's gone, gives up after 8 s, no wait without the title or for other cards.
- `cooldownnever.lua`: the Cooldown Manager page's Icon shows Never. The mode read back for a spell, its override, a
  group and a numbered line; the dropdown and profiles carry it; and the ready pass fades a Never icon (a
  flashing one too) while an Always one beside it stays.
- `cooldownlines.lua`: the Cooldown Manager page's numbered lines (UI/CooldownRules.lua, in place of situations).
  Fitting by Combat and Location or CQL, top to bottom with the row's own dropdown last, a spell's lines before its
  bar's, buffs too; a typed rule back into the dropdowns; the page's block adding, moving, deleting and lighting the
  line in use; the ready pass fading by a line; and the update turning saved situations into lines.
- `combattextkeep.lua`: Combat Text Style's game-number settings kept as its rows say: a reset of the game's options
  (an outside write) put back, Game's handing them over, the page off and Keep yours letting go; a plain "your
  change wins" set still lets go.
- `notchgap.lua <forever|retail>`: full-screen effects (ns.CoverWorld: letterbox, tint edges, death screen, Focus,
  low health, teleport) reach up over a Mac's camera notch strip above UIParent, at UI scale 1 and 0.8, and come back
  down when it goes.
- `reload.lua <forever|retail>`: our reloads (QoL/Reload.lua). Forever, where ReloadUI from our code is blocked: a
  popup that reloads gets a secure /reload button over the right button, whose click runs the popup's work without
  our ReloadUI, and with no such click it says to type /reload. Retail: ReloadUI as before, nothing covered.
- `castlook.lua <forever|retail>`: a cast bar's These bars pick of the other kind's game look (PlateCastStyle.lua's
  GameAs/DressAs) on the style lab's real-layout stand-in: put on (border, name, icon as the game lays the other kind
  out) and taken off again (every anchor, size and justify back).
- `gryphons.lua`: parts that ignore their frame's alpha follow our fade (FadeDetached.lua). Action bar 1's
  gryphons on Forever, made to ignore EndCaps' alpha by another addon (FlareUI 6.13): the HUD's Action bar art row
  and the Overrides tab's Hide still reach them (kept down if that addon raises them, following a half fade, handed
  back after). And any faded frame: another addon's detached part follows it, Cinematic's own stays, /cine why
  says who detached it.
- `loosesurvey.lua`: `/cine debug loose` (Dev/LoosePartsSurvey.lua, step A of Tools/loose-parts-plan.md) on the
  dev copy: finds exactly the parts under faded frames that ignore their alpha (regions, children, deeper ones),
  not frames with a row of their own or our own detached parts, counts secret answers apart, changes no alpha.
- `Tools/prerelease.py` (one folder up) runs these checks and the rest side by side before a release, and reads the
  in-game `/cine prerelease` results from the saved settings.
- `export.lua`: `lua5.1 Tools/offline/export.lua > profiles.json` writes the options pages and their sections, the
  modules and the built-in profiles as JSON, for mock-ups and the like.
- `hublasttab.lua`: the tab last open under each settings icon (db.hubLastTab) kept through a /reload and a loading
  screen, forgotten by a real login, so each icon opens on its own page after a logout. One item's pages (`forget` in
  HUBS: Card Settings, Card Style, Card Sounds, Trigger Settings) are never saved: their icon opens its list page.
