"""Assembles the mock-up page: src/page.html with the assets put in.
Writes out/style-revamp.html."""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
A = os.path.join(HERE, "assets")
themes = json.load(open(os.path.join(A, "themes.json")))
images = json.load(open(os.path.join(A, "images.json")))
fonts = json.load(open(os.path.join(A, "fonts.json")))
FAMILY = {"Marcellus-Regular": "CinMarcellus", "Almendra-Bold": "CinAlmendra", "Philosopher-Regular": "CinPhilosopher",
          "CinzelDecorative-Regular": "CinCinzel", "GermaniaOne-Regular": "CinGermania",
          "BarlowCondensed-Medium": "CinBarlow", "BebasNeue-Regular": "CinBebas", "Rajdhani-SemiBold": "CinRajdhani"}
faces = "\n".join("@font-face{font-family:'%s';src:url(%s) format('truetype');font-display:block}" % (FAMILY[k], v)
                  for k, v in fonts.items())
page = open(os.path.join(HERE, "src", "page.html"), encoding="utf-8").read()
css = open(os.path.join(HERE, "src", "page.css"), encoding="utf-8").read()
js = open(os.path.join(HERE, "src", "page.js"), encoding="utf-8").read()
page = page.replace("/*__CSS__*/", css).replace("/*__FONTFACES__*/", faces)
page = page.replace("/*__JS__*/", "const THEMES=" + json.dumps(themes) + ";\nconst IMG=" + json.dumps(images) + ";\n" + js)
os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
out = os.path.join(HERE, "out", "style-revamp.html")
open(out, "w", encoding="utf-8").write(page)
print(out, len(page) // 1024, "KB")
