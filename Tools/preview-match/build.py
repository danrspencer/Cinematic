"""Preview Match report: each Style preview next to the game frame it stands for.

Reads what /cine debug previewmatch saved (CinematicDB.previewMatch in the dev copy's SavedVariables) and the
screenshots it took, cuts each bar out, sizes both to the same bar width and writes one page:
game | ours | difference, a pixel match % per pair, and the test's part-by-part differences under each.

    python Tools/preview-match/build.py [forever] [retail]

Writes Tools/preview-match/out/preview-match.html (not committed). The game's folder: CINE_WOW, else
C:/Program Files (x86)/World of Warcraft. Plan: Tools/preview-match-plan.md.
"""
import base64
import datetime
import glob
import html
import io
import os
import sys

from lupa import LuaRuntime
from PIL import Image, ImageChops, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
WOW = os.environ.get("CINE_WOW", r"C:\Program Files (x86)\World of Warcraft")
CLIENTS = {"forever": "_forever_", "retail": "_retail_"}
BAR_W = 420  # every bar is drawn this wide on the page
PAD = 0.25  # room around the cut, as a part of the bar's width


def to_py(value):
    """A Lua table as Python lists/dicts (lists when its keys are 1..n)."""
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    try:
        items = list(value.items())
    except AttributeError:
        return value
    keys = [k for k, _ in items]
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(v) for _, v in sorted(items)]
    return {k: to_py(v) for k, v in items}


def load(client):
    files = sorted(glob.glob(os.path.join(WOW, CLIENTS[client], "WTF", "Account", "*", "SavedVariables",
                                          "CinematicDev.lua")))
    if not files:
        return None, None
    lua = LuaRuntime(unpack_returned_tuples=True)
    with open(files[-1], encoding="utf-8", errors="replace") as handle:
        lua.execute(handle.read())
    db = lua.globals().CinematicDB
    store = db and db["previewMatch"] and db["previewMatch"][client]
    return (to_py(store) if store else None), files[-1]


def find_shot(client, stamp):
    """The screenshot taken at stamp (MMDDYY_HHMMSS), or within 3 s after it."""
    folder = os.path.join(WOW, CLIENTS[client], "Screenshots")
    when = datetime.datetime.strptime(stamp, "%m%d%y_%H%M%S")
    for step in range(0, 4):
        name = (when + datetime.timedelta(seconds=step)).strftime("WoWScrnShot_%m%d%y_%H%M%S")
        for ext in ("jpg", "png", "tga"):
            path = os.path.join(folder, f"{name}.{ext}")
            if os.path.exists(path):
                return path
    return None


def cut(client, read):
    """The bar and what hangs off it, from its screenshot, sized so the bar is BAR_W wide."""
    if not (read and read.get("shot") and read.get("box")):
        return None, "no place or shot"
    path = find_shot(client, read["shot"])
    if not path:
        return None, f"screenshot {read['shot']} not found"
    image = Image.open(path).convert("RGB")
    left, top, right, bottom = read["box"]
    if read.get("barBox"):
        bar_left, _, bar_right, _ = read["barBox"]
        bar_w = max(1, bar_right - bar_left)
    else:
        # (The bar's place is secret: the frame around it, sized by the bar's width the template gives.)
        bar_w = max(1, read.get("barPxW") or (right - left))
    pad = bar_w * PAD
    box = (max(0, left - pad), max(0, top - pad), min(image.width, right + pad), min(image.height, bottom + pad))
    piece = image.crop(tuple(int(round(v)) for v in box))
    scale = BAR_W / bar_w
    piece = piece.resize((max(1, int(piece.width * scale)), max(1, int(piece.height * scale))), Image.LANCZOS)
    # (Where the bar's own top-left landed, to line the two up.)
    anchor = None
    if read.get("barBox"):
        anchor = (int((bar_left - box[0]) * scale), int((read["barBox"][1] - box[1]) * scale))
    label = os.path.basename(path) + (f", all of {read['areaOf']} (its place is secret)" if read.get("areaOf") else "")
    return (piece, anchor, label), None


def compare(game, ours):
    """Line both up by the bar's top-left; a difference picture and a match %."""
    (g, g_at, _), (o, o_at, _) = game, ours
    left = max(g_at[0], o_at[0])
    top = max(g_at[1], o_at[1])
    width = max(g.width - g_at[0], o.width - o_at[0]) + left
    height = max(g.height - g_at[1], o.height - o_at[1]) + top
    canvas_g = Image.new("RGB", (width, height))
    canvas_o = Image.new("RGB", (width, height))
    canvas_g.paste(g, (left - g_at[0], top - g_at[1]))
    canvas_o.paste(o, (left - o_at[0], top - o_at[1]))
    diff = ImageChops.difference(canvas_g, canvas_o)
    gray = ImageOps.grayscale(diff)
    mean = sum(i * n for i, n in enumerate(gray.histogram())) / max(1, width * height)
    match = max(0.0, 100.0 - mean / 255.0 * 100.0 * 3)  # (3x: most of a cut is background, which always matches a bit)
    heat = ImageOps.autocontrast(gray).convert("RGB")
    heat = ImageChops.multiply(heat, Image.new("RGB", heat.size, (255, 80, 80)))
    return heat, match


def data_url(image):
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode()


def section(client):
    store, path = load(client)
    if not store:
        return f"<h2>{client}</h2><p class=dim>No /cine debug previewmatch run saved on {client} yet.</p>", []
    reads = store.get("reads") or {}
    out = [f"<h2>{client} <span class=dim>{html.escape(str(store.get('build')))}, run {html.escape(str(store.get('started')))}"
           f", screen {store.get('screen')}</span></h2>"]
    summary = []
    for pair in store.get("pairs") or []:
        name = pair.get("name")
        out.append(f"<section><h3>{html.escape(name)}</h3>")
        if pair.get("missing"):
            out.append(f"<p class=dim>{html.escape(pair['missing'])}</p></section>")
            summary.append((client, name, None, None))
            continue
        game, why_g = cut(client, reads.get(pair["real"]))
        ours, why_o = cut(client, reads.get(pair["ours"]))
        cells = []
        for label, item, why in (("Game", game, why_g), ("Ours", ours, why_o)):
            if item:
                cells.append(f"<figure><figcaption>{label} <span class=dim>{html.escape(item[2])}</span></figcaption>"
                             f"<img src='{data_url(item[0])}'></figure>")
            else:
                cells.append(f"<figure><figcaption>{label}</figcaption><p class=dim>{html.escape(why)}</p></figure>")
        match = None
        if game and ours and game[1] and ours[1]:
            heat, match = compare(game, ours)
            cells.append(f"<figure><figcaption>Difference <b>{match:.0f}% match</b></figcaption>"
                         f"<img src='{data_url(heat)}'></figure>")
        out.append("<div class=row>" + "".join(cells) + "</div>")
        findings = pair.get("findings") or []
        out.append(f"<p>Parts: <b>{pair.get('score')}</b>/100, {len(findings)} differences</p><ul>")
        out.extend(f"<li>{html.escape(line)}</li>" for line in findings)
        out.append("</ul></section>")
        summary.append((client, name, pair.get("score"), match))
    return "".join(out), summary


def main():
    clients = [c for c in sys.argv[1:] if c in CLIENTS] or list(CLIENTS)
    parts, summary = [], []
    for client in clients:
        body, rows = section(client)
        parts.append(body)
        summary.extend(rows)
    os.makedirs(OUT, exist_ok=True)
    table = "".join(
        f"<tr><td>{c}</td><td>{html.escape(n)}</td><td>{'-' if s is None else s}</td>"
        f"<td>{'-' if m is None else f'{m:.0f}%'}</td></tr>" for c, n, s, m in summary)
    page = f"""<!doctype html><meta charset=utf-8><title>Preview Match</title>
<style>
body {{ background:#15161a; color:#e8e6e1; font:14px system-ui, sans-serif; margin:24px; }}
h2 {{ border-bottom:1px solid #333; padding-bottom:6px; }} .dim {{ color:#8b8a86; font-weight:normal; }}
.row {{ display:flex; gap:16px; flex-wrap:wrap; align-items:flex-start; }}
figure {{ margin:0; background:#0c0c0e; padding:8px; border:1px solid #2a2a2e; }}
figcaption {{ margin-bottom:6px; }} img {{ display:block; max-width:100%; }}
table {{ border-collapse:collapse; }} td, th {{ padding:4px 12px; border-bottom:1px solid #2a2a2e; text-align:left; }}
li {{ font-family:Consolas, monospace; font-size:13px; }}
</style>
<h1>Preview Match</h1>
<table><tr><th>Client</th><th>Preview</th><th>Parts /100</th><th>Pixels</th></tr>{table}</table>
{''.join(parts)}"""
    target = os.path.join(OUT, "preview-match.html")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(page)
    for c, n, s, m in summary:
        print(f"{c:8} {n:22} parts {'-' if s is None else s:>4}  pixels {'-' if m is None else f'{m:.0f}%'}")
    print("wrote", target)


if __name__ == "__main__":
    main()
