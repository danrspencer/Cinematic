# Style revamp mock-ups

The design plan and clickable mock-ups for the styling revamp: the Look panel as the template for every Style page, a
scaled-up Name Style page, plate and name themes, and main themes that use them. Nothing here is built into the addon yet.

From the repo root (needs Python with Pillow and lupa):

```bash
python Tools/style-revamp/extract.py   # the themes, textures and fonts, from the addon's own files
python Tools/style-revamp/build.py     # writes Tools/style-revamp/out/style-revamp.html
```

`src/page.html` is the plan's text, `src/page.js` the mock-ups and the proposed plate and name theme data (worked out
from `StyleThemes.lua` the way the plan says the addon would).
