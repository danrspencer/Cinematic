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
- `export.lua`: `lua5.1 Tools/offline/export.lua > profiles.json` writes the options pages and their sections, the
  modules and the built-in profiles as JSON, for mock-ups and the like.
