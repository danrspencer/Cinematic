# Style Lab

Every frame the Style pages can preview, drawn by the addon's own code in every style theme, on one web page. Use it
to look at a theme or compare one frame across all of them without starting the game.

From the repo root:

```bash
python Tools/style-lab/build.py retail
```

That writes `Tools/style-lab/out/style-lab.html` (not committed). `forever` in place of `retail` draws that client's
version. To look at it, start the `style-lab` server from `.claude/launch.json`.

## How it works

- `frames.lua` puts real layout on the offline stand-in (`Tools/offline/wow.lua`): anchors, sizes, scale, alpha, draw
  layers, status bars, fonts and colors. `Dump` reads back everything a frame drew.
- `dump.lua` loads the addon, and for each theme in `ns.StyleThemeList()` calls `ns.ApplyStyleTheme`, runs each preview
  maker and settings page, and writes the results as JSON. Nothing is drawn by hand, so a change to a preview, a page
  or a theme shows at the next build.
- `build.py` turns the addon's own textures into images and fills `lab_template.html`, which paints the drawn items on
  canvases.

## Adding things

- A frame: add a line to `FRAMES` in `dump.lua` (a preview maker on `ns`), or to `PAGES` (a whole settings page, by its
  `pageName`).
- A theme: add it to `THEMES` in `StyleThemes.lua`, and its art to `Media/make_theme_art.py`. `check.lua` tests that a
  pick and Undo work and that every setting it writes is real.

## What it can't show

- The game's own art isn't ours to copy, so it's a stand-in (`standin()` in `build.py`): icons, portraits, bars and
  the parts of the game's frames. Art with no stand-in is left out, and the build lists it.
- The fonts we bundle are the real ones here. The game's four are web fonts near them, so their widths differ a little.
- Colors and layout come from the real code, but only the game can show the final result. Check a new look there
  before trusting it.
- Only frames with a preview or a settings page are here. The wheels, Welcome, What's new and the hub window around
  the pages aren't.
