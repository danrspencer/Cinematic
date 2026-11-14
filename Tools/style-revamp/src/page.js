// Mock-ups for the Style revamp. Everything drawn here follows the addon's own
// data where it has some (THEMES: StyleThemes.lua; IMG: Textures/), and the
// proposed new data (plate themes, name themes) is worked out from it below,
// the same way the plan says the addon would.
"use strict";

// ---------- helpers
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const h = (html) => { const t = document.createElement("template"); t.innerHTML = html.trim(); return t.content.firstElementChild; };
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const rgb = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;
const mix = (a, b, t) => [0, 1, 2].map((i) => a[i] + (b[i] - a[i]) * t);
const clone = (o) => JSON.parse(JSON.stringify(o));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const fmtColor = (c) => "#" + c.map((x) => Math.round(x * 255).toString(16).padStart(2, "0")).join("");

// ---------- the addon's choices (names as the menus show them)
const FONT_FAMILY = {
	game: "'Marcellus', serif", friz: "'Marcellus', serif", arial: "'Archivo Narrow', sans-serif",
	morpheus: "'Metamorphous', serif", skurri: "'Federo', sans-serif",
	marcellus: "'CinMarcellus', serif", almendra: "'CinAlmendra', serif", philosopher: "'CinPhilosopher', serif",
	cinzel: "'CinCinzel', serif", germania: "'CinGermania', serif", barlow: "'CinBarlow', sans-serif",
	bebas: "'CinBebas', sans-serif", rajdhani: "'CinRajdhani', sans-serif",
};
const FONT_NAME = { game: "The game's", friz: "Friz Quadrata", arial: "Arial Narrow", morpheus: "Morpheus", skurri: "Skurri",
	marcellus: "Marcellus", almendra: "Almendra", philosopher: "Philosopher", cinzel: "Cinzel Decorative",
	germania: "Germania One", barlow: "Barlow Condensed", bebas: "Bebas Neue", rajdhani: "Rajdhani" };
const FONTS = ["friz", "arial", "morpheus", "skurri", "marcellus", "almendra", "philosopher", "cinzel", "germania", "barlow", "bebas", "rajdhani"];
// (Bar textures: the game's stand-ins, then ours, real.)
const GAME_TEX = {
	game: "linear-gradient(180deg, rgba(255,255,255,.55) 0%, rgba(255,255,255,.95) 45%, rgba(190,190,190,1) 55%, rgba(120,120,120,1) 100%)",
	flat: "linear-gradient(#fff,#fff)",
	smooth: "linear-gradient(180deg, #fff 0%, #ddd 40%, #9a9a9a 100%)",
	raid: "linear-gradient(180deg, #f2f2f2 0%, #bdbdbd 60%, #8d8d8d 100%)",
};
const TEX_NAME = { game: "The game's", flat: "Flat", smooth: "Smooth", raid: "Raid frame", glass: "Glass", soft: "Soft", striped: "Striped",
	minimal: "Minimal", rounded: "Rounded", gilt: "Gilt", forged: "Forged", lunar: "Lunar", rime: "Rime", reel: "Reel", tile: "Tile",
	brushed: "Brushed", worn: "Worn", linen: "Linen", satin: "Satin", hammered: "Hammered" };
const TEXTURES = ["game", "flat", "smooth", "raid", "glass", "soft", "striped", "minimal", "rounded", "gilt", "forged", "lunar", "rime", "reel",
	"tile", "brushed", "worn", "linen", "satin", "hammered"];
function texImage(tex) {
	if (GAME_TEX[tex]) return GAME_TEX[tex];
	const img = IMG["bar_" + tex];
	return img ? `url(${img})` : GAME_TEX.game;
}
// A bar's fill: the texture times its color (the game tints grey art by the bar's color).
function fillCSS(tex, color, grad) {
	const base = grad ? `linear-gradient(90deg, ${rgb(color)}, ${rgb(grad)})` : `linear-gradient(${rgb(color)},${rgb(color)})`;
	return `background-image:${texImage(tex)}, ${base};background-size:100% 100%;background-blend-mode:multiply;`;
}
const SHAPES = { square: "Square", soft: "Soft", capsule: "Capsule", bevel: "Bevel", chisel: "Chisel" };
function shapeCSS(shape) {
	const img = IMG["shape_" + shape];
	return img && shape !== "square" ? `-webkit-mask-image:url(${img});mask-image:url(${img});-webkit-mask-size:100% 100%;mask-size:100% 100%;` : "";
}
const CLASS = { warrior: [0.78, 0.61, 0.43], mage: [0.25, 0.78, 0.92], shaman: [0, 0.44, 0.87], paladin: [0.96, 0.55, 0.73],
	rogue: [1, 0.96, 0.41], druid: [1, 0.49, 0.04], hunter: [0.67, 0.83, 0.45], priest: [1, 1, 1] };
const REACT = { hostile: [1, 0, 0], neutral: [1, 1, 0], friendly: [0, 1, 0] };
const BAR_REACT = { hostile: [0.85, 0.12, 0.1], neutral: [0.9, 0.78, 0.15], friendly: [0.2, 0.75, 0.2] };
const FRIEND_BLUE = [0.4, 0.4, 1];

// ---------- the real themes, and what the plan derives from each
const TH = Object.fromEntries(THEMES.map((t) => [t.key, t]));
const SLAB = (t) => t.layout === "slab";
// (Names are small: the theme's Small names font, as unit frames use: Friz
// for most, the theme's own for the flat modern ones.)
const smallFont = (t) => (SLAB(t) ? t.settings.styleFont : "friz");

// Plate themes. One per main theme, made from its own colors and art, and a
// few that stand alone. look: a Nameplate Style Look, as the Default row's.
const PLATE_THEMES = [{ key: "game", name: "The game's", about: "The game's own plates. Nothing changed.", look: {} }];
const NAME_THEMES = [{ key: "game", name: "The game's", about: "Names as the game draws them over heads.", look: {}, was: "Like the game's names" }];
for (const t of THEMES) {
	if (t.key === "game") continue;
	const s = t.settings;
	const plate = {
		texture: s.styleTexture, border: "custom", borderSize: t.lineSize, borderColor: t.line,
		shape: s.styleBarShape || "square", back: t.panel, backAlpha: 0.8,
		veil: t.veil ? t.veil.plate : 0,
	};
	PLATE_THEMES.push({ key: t.key, name: t.name, about: t.tip, look: plate, family: true });
	const name = {
		font: smallFont(t), shadow: "soft",
		hostile: mix([1, 0.22, 0.18], t.stop, 0.35), neutral: mix([1, 0.92, 0.2], t.cast, 0.35),
		friendly: mix([0.25, 1, 0.3], t.health, 0.45), line2Color: "theme", line2Tint: mix([0.75, 0.75, 0.75], t.ornament, 0.6),
	};
	if (t.nameColor) name.friendsTint = t.nameColor;
	if (["fel", "void", "glade"].includes(t.key)) Object.assign(name, { glow: "soft", glowColor: mix(t.ornament, [0, 0, 0], 0.45), glowSize: 1 });
	if (t.key === "forge") Object.assign(name, { glow: "soft", glowColor: [1, 0.45, 0.12], glowSize: 0.8 });
	if (SLAB(t)) Object.assign(name, { backdrop: "band", backdropColor: t.panel, backdropAlpha: 0.6, size: 1.05 });
	if (t.key === "reel") Object.assign(name, { size: 0.95, shadow: "hard", line2Color: "dim" });
	if (t.key === "codex") Object.assign(name, { line2Tint: [0.93, 0.74, 0.34] });
	NAME_THEMES.push({ key: t.key, name: t.name, about: t.tip, look: name, family: true });
}
PLATE_THEMES.push(
	{ key: "clean", name: "Clean", about: "A flat bar with a thin black line round it, the name outlined. Nothing else.",
		look: { texture: "flat", border: "thin" } },
	{ key: "raider", name: "Raider", about: "Bigger, heavier bars with the health in numbers. Built for fights.",
		look: { texture: "smooth", border: "thick", width: 1.15, height: 1.4, healthText: "percent" } },
	{ key: "minimal", name: "Minimal", about: "A thin strip with no border.",
		look: { texture: "flat", border: "none", height: 0.55, backAlpha: 0.35 } },
);
NAME_THEMES.push(
	{ key: "bold", name: "Bold", about: "Colored, with a thin black outline, a little bigger.", look: { outline: 1, size: 1.1 }, was: "Bold" },
	{ key: "subtle", name: "Subtle", about: "Colored, a little smaller and see-through.", look: { size: 0.9, alpha: 0.75 }, was: "Subtle" },
	{ key: "storybook", name: "Storybook", about: "Warm colors in a hand-lettered font, with a soft shadow. A tale told as you pass.",
		look: { font: "almendra", size: 1.15, shadow: "soft", hostile: [0.92, 0.38, 0.28], neutral: [0.96, 0.82, 0.48],
			friendly: [0.64, 0.86, 0.46], line2Color: "theme", line2Tint: [0.93, 0.78, 0.5] } },
	{ key: "subtitle", name: "Subtitle", about: "White on a soft dark band, like film subtitles. Reads over anything.",
		look: { font: "barlow", size: 1.1, colorBy: "one", one: [0.96, 0.96, 0.94], backdrop: "band", backdropColor: [0, 0, 0],
			backdropAlpha: 0.5, line2Color: "dim" } },
	{ key: "lantern", name: "Lantern", about: "A warm glow behind each name, as if lit by a lantern at night.",
		look: { glow: "soft", glowColor: [1, 0.72, 0.3], glowSize: 1.1, shadow: "soft" } },
);
const PT = Object.fromEntries(PLATE_THEMES.map((t) => [t.key, t]));
const NT = Object.fromEntries(NAME_THEMES.map((t) => [t.key, t]));

// ---------- the game's own looks (what's left when nothing sets a value)
const GAME_PLATE = { texture: "game", gradient: "off", gradColor: [0.1, 0.1, 0.1], back: [0, 0, 0], backAlpha: 0.6, shape: "square", width: 1,
	height: 1, font: "game", textSize: 1, outline: 0, shadow: "game", namePos: "above", healthText: "none", border: "game", borderSize: 1,
	borderColor: [0, 0, 0], level: "show", veil: 0 };
const GAME_NAME = { font: "game", size: 1, alpha: 1, caps: "as", colorBy: "reaction", hostile: REACT.hostile, neutral: REACT.neutral,
	friendly: REACT.friendly, friends: "blue", enemies: "class", one: [1, 1, 1], outline: 0, outlineColor: "black", outlineTint: [0, 0, 0],
	shadow: "none", shadowX: 1, shadowY: -1, shadowAlpha: 1, glow: "none", glowColor: [1, 0.82, 0], glowSize: 1, backdrop: "none",
	backdropColor: [0, 0, 0], backdropAlpha: 0.5, line2: "both", line2Size: 0.85, line2Color: "dim", line2Tint: [0.75, 0.75, 0.75],
	brackets: "angle", serviceIcons: false, level: "none", elite: "none", marker: "above" };

// ---------- drawing a nameplate
// sample: { name, react, cls, level, hp }, look: resolved values, rowColor: { c, bar, name } or null.
function plateHTML(sample, look, opt = {}) {
	const w = Math.round(118 * (look.width || 1)), bh = Math.max(3, Math.round(10 * (look.height || 1)));
	let barColor = sample.cls ? CLASS[sample.cls] : BAR_REACT[sample.react || "hostile"];
	let nameColor = sample.cls ? [1, 1, 1] : { hostile: [1, 0.25, 0.2], neutral: [1, 0.9, 0.3], friendly: [0.4, 1, 0.4] }[sample.react || "hostile"];
	if (opt.row && opt.row.bar) barColor = opt.row.c;
	if (opt.row && opt.row.name) nameColor = opt.row.c;
	if (look.veil) barColor = mix(barColor, [0.12, 0.12, 0.14], look.veil);
	const grad = look.gradient === "on" ? look.gradColor : null;
	// border
	let border = "";
	const b = look.border;
	if (b === "game") border = "box-shadow:0 0 0 2px rgba(0,0,0,.75);";
	else if (b === "thin") border = "box-shadow:0 0 0 1px #000;";
	else if (b === "thick") border = "box-shadow:0 0 0 2px #000;";
	else if (b === "custom") border = `box-shadow:0 0 0 ${look.borderSize}px ${rgb(look.borderColor)};`;
	if (opt.row && opt.row.border) border = `box-shadow:0 0 0 2px #000, 0 0 0 4px ${rgb(opt.row.c)};`;
	const shape = shapeCSS(look.shape);
	const tx = textShadowCSS({ outline: look.outline, outlineTint: [0, 0, 0], shadow: look.shadow === "on" ? "soft" : "none", shadowX: 1, shadowY: -1, shadowAlpha: 1 });
	const font = FONT_FAMILY[look.font] || FONT_FAMILY.game;
	const fs = 12 * (look.textSize || 1);
	const nameSpan = `<span class="nm" style="font-family:${font};font-size:${fs}px;color:${rgb(nameColor)};text-shadow:${tx}">${esc(sample.name)}</span>`;
	const hp = sample.hp ?? 0.72;
	const htxt = look.healthText === "percent" ? `<span class="htxt">${Math.round(hp * 100)}%</span>` : look.healthText === "value" ? `<span class="htxt">${Math.round(hp * 4210).toLocaleString()}</span>` : "";
	const inside = look.namePos === "inside";
	const bar = `<div class="bar" style="width:${w}px;height:${bh}px;${border}">
		<div style="position:absolute;inset:0;${shape}">
			<div class="back" style="background:${rgb(look.back, look.backAlpha)}"></div>
			<div class="fill" style="width:${hp * 100}%;${fillCSS(look.texture, barColor, grad)}"></div>
		</div>${htxt}${inside ? `<span class="inname">${nameSpan}</span>` : ""}</div>`;
	const lvl = look.level === "show" && opt.forever && !sample.player ? `<span class="lvl">${sample.level ?? "??"}</span>` : "";
	const above = !inside && look.namePos !== "below" ? nameSpan : "";
	const below = look.namePos === "below" ? nameSpan : "";
	const mark = opt.mark ? `<span class="mark" style="top:${-14 - (opt.markY || 0)}px;width:${opt.mark[1]}px;height:${opt.mark[1]}px;background-image:url(${IMG["tex_target" + opt.mark[0]]});${opt.mark[2] ? "filter:" + opt.mark[2] : ""}"></span>` : "";
	return `<div class="np" style="${opt.pos || ""}">${mark}${above}<div class="row">${bar}${lvl}</div>${below}</div>`;
}

// ---------- drawing a name (name-only plates)
function textShadowCSS(l) {
	const out = [];
	const oc = l.outlineColor === "custom" ? l.outlineTint : [0, 0, 0];
	if (l.outline >= 1) for (const [x, y] of [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]]) out.push(`${x}px ${y}px 0 ${rgb(oc)}`);
	if (l.outline >= 2) for (const [x, y] of [[2, 0], [-2, 0], [0, 2], [0, -2], [2, 1], [-2, 1], [2, -1], [-2, -1], [1, 2], [-1, 2], [1, -2], [-1, -2]]) out.push(`${x}px ${y}px 0 ${rgb(oc)}`);
	if (l.shadow === "soft") out.push(`${l.shadowX}px ${-l.shadowY}px 2px rgba(0,0,0,${l.shadowAlpha})`);
	if (l.shadow === "hard") out.push(`${l.shadowX}px ${-l.shadowY}px 0 rgba(0,0,0,${l.shadowAlpha})`);
	return out.length ? out.join(",") : "none";
}
function nameColorOf(s, l) {
	if (l.colorBy === "one") return l.one;
	if (s.cls) {
		if (s.react === "hostile") return l.enemies === "class" || l.colorBy === "class" ? CLASS[s.cls] : l.hostile;
		if (l.colorBy === "class" || l.friends === "class") return CLASS[s.cls];
		if (l.friends === "white") return [1, 1, 1];
		return l.friendsTint || FRIEND_BLUE;
	}
	return l[s.react] || [1, 1, 1];
}
function nameHTML(s, l, pos, scale = 1) {
	const c = nameColorOf(s, l);
	const fs = 12 * (l.size || 1) * scale;
	const font = FONT_FAMILY[l.font] || FONT_FAMILY.game;
	const tx = textShadowCSS(l);
	let txt = s.name;
	if (l.caps === "caps") txt = txt.toUpperCase();
	const lv = l.level !== "none" && s.level ? `<span style="font-size:${fs * 0.8}px;color:${rgb([0.85, 0.85, 0.85])}">${s.level}</span>` : "";
	const el = l.elite !== "none" && s.elite ? `<span style="color:${s.elite === "rare" ? "#cfd6e6" : "#ffd100"};font-size:${fs * 0.75}px">&#9670;</span>` : "";
	const marker = s.marker ? `<span style="color:#ffe14a;font-size:${fs}px;text-shadow:0 0 2px #000">&#9733;</span>` : "";
	const svc = s.title && l.serviceIcons ? `<span class="ic" style="background:#3a3a3a;color:#ddd;font-size:${9 * scale}px;line-height:12px;text-align:center;width:${14 * scale}px;height:${14 * scale}px">&#9874;</span>` : "";
	let glow = "";
	if (l.glow === "soft") {
		const gw = (txt.length * fs * 0.62 + 40) * (l.glowSize || 1), gh = fs * 3.2 * (l.glowSize || 1);
		glow = `<span class="glow" style="width:${gw}px;height:${gh}px;background:${rgb(l.glowColor, 0.42)};-webkit-mask-image:url(${IMG.tex_softglow});mask-image:url(${IMG.tex_softglow});-webkit-mask-size:100% 100%;mask-size:100% 100%"></span>`;
	}
	let bd = "";
	if (l.backdrop !== "none") {
		const col = rgb(l.backdropColor, l.backdropAlpha);
		const style = l.backdrop === "pill" ? `background:${col};border-radius:999px;inset:-2px -9px;`
			: l.backdrop === "banner" ? `background:linear-gradient(90deg,transparent,${col} 22%,${col} 78%,transparent);inset:-2px -26px;`
			: `background:${col};inset:-1px -7px;border-radius:2px;`;
		bd = `<span class="bd" style="${style}"></span>`;
	}
	const before = l.level === "before" ? lv : "", after = l.level === "after" ? lv : "";
	const markerLeft = l.marker === "left" ? marker : "", markerRight = l.marker === "right" ? marker : "";
	const markerAbove = l.marker === "above" && marker ? `<div style="line-height:1">${marker}</div>` : "";
	let line2 = "";
	const second = s.guild ? s.guild : s.title;
	const showL2 = second && (l.line2 === "both" || (l.line2 === "guild" && s.guild) || (l.line2 === "title" && s.title));
	if (showL2 && !(s.title && l.serviceIcons)) {
		const br = l.brackets === "angle" ? ["&lt;", "&gt;"] : l.brackets === "guillemet" ? ["&laquo;", "&raquo;"] : ["", ""];
		const lc = l.line2Color === "dim" ? mix(c, [0.55, 0.55, 0.55], 0.55) : l.line2Color === "grey" ? [0.72, 0.72, 0.72] : l.line2Color === "gold" ? [1, 0.82, 0] : l.line2Tint;
		line2 = `<div class="l2" style="font-family:${font};font-size:${fs * l.line2Size}px;color:${rgb(lc)};text-shadow:${tx}">${br[0]}${esc(second)}${br[1]}</div>`;
	}
	const nameSpan = svc && s.title ? "" : `<span>${esc(txt)}</span>`;
	const px = (v) => (typeof v === "number" ? v + "px" : v);
	return `<div class="nmw" style="left:${px(pos[0])};top:${px(pos[1])};opacity:${l.alpha}">${markerAbove}<div class="l1" style="font-family:${font};font-size:${fs}px;color:${rgb(c)};text-shadow:${tx}">${glow}${bd}${markerLeft}${before}${el}${svc}${nameSpan}${after}${markerRight}</div>${line2}</div>`;
}

// ---------- resolution: own -> default row -> part theme -> the game's
const MAIN_THEME = { key: "codex" }; // (the mock's main theme: picked on General)
const PARTS_OF_MAIN = Object.fromEntries(THEMES.map((t) => [t.key, { plate: t.key, names: t.key }]));
function partTheme(kind, pick) {
	const list = kind === "plate" ? PT : NT;
	const key = pick === "main" ? PARTS_OF_MAIN[MAIN_THEME.key][kind === "plate" ? "plate" : "names"] : pick;
	return list[key] || list.game;
}
function makeStore(game, themes, kindDefault, defaultName, themeWord) {
	return {
		pick: "main", rows: {},
		theme() { return partTheme(themes, this.pick); },
		own(kind, key) { return (this.rows[kind] || {})[key]; },
		res(kind, key, over) {
			if (over && key in over) return { v: over[key], src: "Preview", own: true };
			const mine = this.own(kind, key);
			if (mine !== undefined) {
				const w = this.writtenBy && this.writtenBy(kind);
				if (w && w.look[key] !== undefined && same(w.look[key], mine)) return { v: mine, src: `Set by theme: ${w.name}`, own: true, byTheme: true };
				return { v: mine, src: kind === kindDefault ? "Set here" : "This row", own: true };
			}
			if (kind !== kindDefault) {
				const d = this.own(kindDefault, key);
				if (d !== undefined) return { v: d, src: defaultName, own: false };
			}
			const t = this.theme();
			if (t.look[key] !== undefined) return { v: t.look[key], src: this.pick === "main" ? (themes === "plate" ? `General: ${t.name}` : `${themeWord}: ${t.name}`) : `${themeWord}: ${t.name}`, own: false };
			if (this.below) { const b = this.below(key); if (b) return b; }
			if (this.offWhen && this.offWhen(key)) return { v: game[key], src: "Off", own: false };
			return { v: game[key], src: "The game's", own: false };
		},
		// Every key as it shows (over: { key: value } pointed at, not saved).
		look(kind, over) { const o = {}; for (const k of Object.keys(game)) o[k] = this.res(kind, k, over).v; for (const k of Object.keys(this.theme().look)) if (!(k in o)) o[k] = this.theme().look[k]; for (const k of ["friendsTint"]) { const r = this.res(kind, k, over); if (r.v !== undefined) o[k] = r.v; } return o; },
		set(kind, key, v) { (this.rows[kind] = this.rows[kind] || {})[key] = v; },
		clear(kind, key) { if (this.rows[kind]) delete this.rows[kind][key]; },
	};
}
const plates = makeStore(GAME_PLATE, "plate", "others", "Default row's", "Plate theme");
// (The name on a full plate: under the Default row, Name Style's All names, D10.)
const PLATE_TEXT = { font: "font", textSize: "size", outline: "outline", shadow: "shadow" };
plates.below = (key) => {
	if (!(key in PLATE_TEXT)) return null;
	const r = names.res("all", PLATE_TEXT[key]);
	if (r.src === "The game's") return null;
	let v = r.v;
	if (key === "shadow") v = v === "none" ? "none" : "on";
	return { v, src: "Name Style: All names", own: false };
};
plates.offWhen = (key) => key === "gradColor";
const names = makeStore(GAME_NAME, "names", "all", "All names'", "Name theme");
// (A little set already, so the mock shows rows with looks of their own.)
plates.rows = { target: { border: "custom", borderSize: 2, borderColor: [1, 0.82, 0] }, focus: { gradient: "on", gradColor: [0.1, 0.35, 0.6] } };
names.rows = { target: { size: 1.2, outline: 1 }, service: { line2Color: "gold" } };

// ---------- the Look panel (the template), generic
// cfg: { mount, crumb, title, store, kind(), tabs: [{ name, fields }], preview(over) -> { html, mount }, tools }
// field: { key, label, type, options, flag, when(look), min, max, step, fmt, help }
function LookPanel(cfg) {
	const el = h(`<div class="lp wow" role="region" aria-label="Look panel">
		<div class="head"><div class="crumb"></div><div style="display:flex;gap:6px;align-items:center"><button class="btn" type="button">Pop out</button><span class="x">&#10005;</span></div></div>
		<div class="preview scene"></div>
		<div class="tools" style="display:flex;gap:6px;padding:8px 12px 0;align-items:center"></div>
		<div class="strip" role="tablist"></div>
		<div class="page"></div>
		<div class="foot"><span class="sum look-dim"></span><button class="btn" type="button" data-a="clear">Clear this row</button></div>
	</div>`);
	cfg.mount.appendChild(el);
	let tab = 0, hover = null, comparing = false;
	const store = cfg.store;
	const prev = $(".preview", el);
	function look(over) {
		if (comparing) { const saved = store.rows[cfg.kind()]; store.rows[cfg.kind()] = {}; const l = store.look(cfg.kind(), over); store.rows[cfg.kind()] = saved; return l; }
		return store.look(cfg.kind(), over);
	}
	function drawPreview() { cfg.preview(prev, look(hover), !!hover, comparing); }
	function tabMoved(t) { return t.fields.some((f) => f.key && store.own(cfg.kind(), f.key) !== undefined); }
	function draw() {
		$(".crumb", el).innerHTML = `<s>${esc(cfg.crumb)} &gt;</s> ${esc(cfg.title())}`;
		const strip = $(".strip", el);
		strip.innerHTML = "";
		cfg.tabs.forEach((t, i) => {
			const b = h(`<button class="tab ${i === tab ? "on" : ""} ${tabMoved(t) ? "moved" : ""}" role="tab" type="button">${esc(t.name)}<span class="dot"></span></button>`);
			b.onclick = () => { tab = i; draw(); };
			strip.appendChild(b);
		});
		const page = $(".page", el);
		page.innerHTML = "";
		const l = look();
		for (const f of cfg.tabs[tab].fields) {
			if (f.only && !f.only(cfg.kind())) continue;
			page.appendChild(fieldEl(f, l));
		}
		const moved = cfg.tabs.filter(tabMoved).map((t) => t.name);
		$(".sum", el).textContent = moved.length ? "Changed here: " + moved.join(" · ") : "Nothing changed here: all inherited";
		$("[data-a=clear]", el).textContent = cfg.clearLabel ? cfg.clearLabel() : "Clear this row";
		$("[data-a=clear]", el).classList.toggle("grey", !moved.length);
		drawPreview();
	}
	function fieldEl(f, l) {
		const kind = cfg.kind();
		const r = f.key ? store.res(kind, f.key) : { v: null, src: "", own: false };
		const enabled = !f.when || f.when(l);
		if (!enabled && !r.own) r.src = "Off";
		const w = h(`<div class="field ${r.own ? "own" : ""}" style="${enabled ? "" : "opacity:.4;pointer-events:none"}"></div>`);
		const shown = f.type === "chips" ? fmtColor(r.v || [1, 1, 1]) : f.type === "slider" ? (f.fmt || ((v) => v))(r.v) : f.type === "check" ? (r.v ? "On" : "Off") : (f.options || []).find((o) => same(o.v, r.v))?.label ?? "";
		const flag = f.flag === "test" ? `<span class="flag" title="Needs a test in the game">needs a test</span>` : f.flag === "new" ? `<span class="flag new">new</span>` : "";
		if (f.type !== "note") {
			const head = h(`<div class="fh"><span class="n">${esc(f.label)}</span>${flag}<span class="v look-dim">${esc(shown)}</span><span class="src ${r.own ? "own" : ""}">${esc(r.src)}</span><button class="rs" type="button">Reset</button></div>`);
			$(".rs", head).onclick = () => { store.clear(kind, f.key); draw(); cfg.changed && cfg.changed(); };
			w.appendChild(head);
		}
		const pick = (v) => { store.set(kind, f.key, v); hover = null; draw(); cfg.changed && cfg.changed(); };
		const point = (v) => { hover = v === undefined ? null : { [f.key]: v }; prev.classList.toggle("hovering", !!hover); drawPreview(); };
		if (f.type === "tiles") {
			const g = h(`<div class="tiles"></div>`);
						// (the first tile: inherit, saying what it gives and from where)
			const parent = (() => { const saved = store.own(kind, f.key); store.clear(kind, f.key); const p = store.res(kind, f.key); if (saved !== undefined) store.set(kind, f.key, saved); return p; })();
			const from = /theme/i.test(parent.src) ? "theme" : parent.src === "The game's" ? "game" : /Name Style/.test(parent.src) ? "Name Style" : "Default row";
			const opts = [{ v: undefined, label: "Inherit", sub: `${f.options.find((o) => same(o.v, parent.v))?.label ?? ""} \u00b7 ${from}`, inherit: true, tip: "Follow it: changes when that changes. Picking the same choice below pins it here instead." }, ...f.options];
			const max = f.max || 12;
			const list = opts.slice(0, max);
			for (const o of list) {
				const on = o.inherit ? !r.own : r.own && same(o.v, r.v);
				const showV = o.inherit ? parent.v : o.v;
				let pic = "";
				if (f.pic === "texture") pic = `<span class="strip-img" style="${fillCSS(showV, [0.3, 0.75, 0.35])}"></span>`;
				if (f.pic === "shape") pic = `<span class="strip-img" style="height:10px;${fillCSS("soft", [0.3, 0.75, 0.35])}${shapeCSS(showV)}"></span>`;
				if (f.pic === "border") {
					const bs = showV === "game" ? "box-shadow:0 0 0 2px rgba(0,0,0,.85)" : showV === "thin" ? "box-shadow:0 0 0 1px #000" : showV === "thick" ? "box-shadow:0 0 0 2px #000" : showV === "custom" ? `box-shadow:0 0 0 ${l.borderSize}px ${rgb(l.borderColor)}` : "";
					pic = `<span class="strip-img" style="width:86px;margin-left:6px;height:8px;background:#4cad52;${bs}"></span>`;
				}
				const fontStyle = f.pic === "font" ? `font-family:${FONT_FAMILY[showV] || FONT_FAMILY.game};font-size:14px` : "";
				const t = h(`<button type="button" class="tile ${f.pic === "font" ? "font" : ""} ${o.inherit && f.pic === "font" ? "sub2" : ""} ${on ? "on" : ""}" title="${esc(o.tip || "")}">${pic}<span class="w" style="${fontStyle}">${esc(o.label)}</span>${o.inherit ? `<span class="sub">${esc(o.sub)}</span>` : ""}</button>`);
				if (o.inherit && f.pic !== "font") t.classList.add("tall");
				t.onmouseenter = () => point(o.inherit ? parent.v : o.v);
				t.onmouseleave = () => point(undefined);
				t.onclick = () => (o.inherit ? (store.clear(kind, f.key), hover = null, draw(), cfg.changed && cfg.changed()) : pick(o.v));
				g.appendChild(t);
			}
			if (opts.length > max) g.appendChild(h(`<button type="button" class="tile more"><span class="w">More (${opts.length - max})</span></button>`));
			w.appendChild(g);
		} else if (f.type === "seg") {
			const g = h(`<div class="segs"></div>`);
			for (const o of f.options) {
				const s = h(`<button type="button" class="seg ${same(o.v, r.v) ? "on" : ""}" title="${esc(o.tip || "")}">${esc(o.label)}</button>`);
				if (f.sample === "outline") s.style.textShadow = textShadowCSS({ ...GAME_NAME, outline: o.v });
				s.onmouseenter = () => point(o.v); s.onmouseleave = () => point(undefined); s.onclick = () => pick(o.v);
				g.appendChild(s);
			}
			w.appendChild(g);
		} else if (f.type === "chips") {
			const g = h(`<div class="chips"></div>`);
			const pal = f.palette || [[1, 0.82, 0], [1, 1, 1], [0.95, 0.3, 0.25], [0.3, 0.8, 0.35], [0.3, 0.6, 1], [0.7, 0.45, 1], [0.1, 0.1, 0.1], [0.55, 0.55, 0.6]];
			for (const c of pal) {
				const s = h(`<button type="button" class="chip ${same(c, r.v) ? "on" : ""}" style="background:${rgb(c)}" aria-label="${fmtColor(c)}"></button>`);
				s.onmouseenter = () => point(c); s.onmouseleave = () => point(undefined); s.onclick = () => pick(c);
				g.appendChild(s);
			}
			g.appendChild(h(`<button type="button" class="chip pick" title="Any color (the game's color picker)"></button>`));
			w.appendChild(g);
		} else if (f.type === "slider") {
			const s = h(`<div class="slide"><input type="range" min="${f.min}" max="${f.max}" step="${f.step}" value="${r.v}" aria-label="${esc(f.label)}"><span class="num">${esc((f.fmt || ((v) => v))(r.v))}</span></div>`);
			const inp = $("input", s);
			inp.oninput = () => { hover = { [f.key]: +inp.value }; prev.classList.add("hovering"); $(".num", s).textContent = (f.fmt || ((v) => v))(+inp.value); drawPreview(); };
			inp.onchange = () => pick(+inp.value);
			w.appendChild(s);
		} else if (f.type === "check") {
			const s = h(`<label class="chk"><input type="checkbox" ${r.v ? "checked" : ""}>${esc(f.text || f.label)}</label>`);
			$("input", s).onchange = (e) => pick(e.target.checked);
			w.appendChild(s);
		} else if (f.type === "note") {
			w.appendChild(h(`<div class="sublinks">${f.html}</div>`));
		}
		if (f.help) w.appendChild(h(`<div class="look-dim" style="line-height:1.35">${f.help}</div>`));
		return w;
	}
	// tools: compare (hold), copy, paste, start from a theme
	const tools = $(".tools", el);
	const cmp = h(`<button class="btn" type="button" title="Hold to see this row without its own changes">Hold to compare</button>`);
	const on = () => { comparing = true; cmp.textContent = "Showing: before"; drawPreview(); };
	const off = () => { comparing = false; cmp.textContent = "Hold to compare"; drawPreview(); };
	cmp.onmousedown = on; cmp.onmouseup = off; cmp.onmouseleave = () => comparing && off();
	cmp.ontouchstart = on; cmp.ontouchend = off;
	cmp.onkeydown = (e) => { if (e.key === " " || e.key === "Enter") on(); };
	cmp.onkeyup = off;
	let clip = null;
	const copy = h(`<button class="btn" type="button">Copy look</button>`);
	const paste = h(`<button class="btn grey" type="button">Paste</button>`);
	copy.onclick = () => { clip = clone(store.rows[cfg.kind()] || {}); paste.classList.remove("grey"); copy.textContent = "Copied"; setTimeout(() => (copy.textContent = "Copy look"), 900); };
	paste.onclick = () => { if (!clip) return; store.rows[cfg.kind()] = clone(clip); draw(); cfg.changed && cfg.changed(); };
	const from = h(`<span class="look-dim" style="margin-left:auto">Start from a theme</span>`);
	const sel = h(`<select aria-label="Start this row from a theme" style="background:#1d1d22;color:#ddd;border:1px solid #3d3d47;font:12px 'Archivo Narrow',sans-serif;height:22px"></select>`);
	sel.innerHTML = `<option value="">Pick a theme…</option>` + (cfg.themes || []).map((t) => `<option value="${t.key}">${esc(t.name)}</option>`).join("");
	sel.onchange = () => { const t = (cfg.themes || []).find((x) => x.key === sel.value); if (t) { store.rows[cfg.kind()] = clone(t.look); delete store.rows[cfg.kind()].veil; draw(); cfg.changed && cfg.changed(); } sel.value = ""; };
	tools.append(cmp, copy, paste, from, sel);
	el.querySelector("[data-a=clear]").onclick = () => { store.rows[cfg.kind()] = {}; draw(); cfg.changed && cfg.changed(); };
	draw();
	return { draw, el };
}

// ---------- shared option lists
const opt = (pairs) => pairs.map(([v, label, tip]) => ({ v, label, tip }));
const TEX_OPTS = TEXTURES.map((v) => ({ v, label: TEX_NAME[v] }));
const FONT_OPTS = [{ v: "game", label: "The game's" }, ...FONTS.map((v) => ({ v, label: FONT_NAME[v] }))];
const pct = (v) => Math.round(v * 100) + "%";

// ---------- Mock 2: Nameplate Style page + its Look panel
const PLATE_ROWS = [
	{ kind: "target", label: "Target", mark: ["arrow", 16, "hue-rotate(250deg) saturate(3)"], row: { c: [0.75, 0.2, 1], bar: true }, when: "Always" },
	{ kind: "mouseover", label: "Mouseover", mark: ["chevron", 14, ""], row: null, when: "Always" },
	{ kind: "focus", label: "Focus", mark: ["diamond", 12, "hue-rotate(150deg) saturate(2)"], row: { c: [0.15, 0.85, 0.85], bar: true, name: true }, when: "Always" },
	{ kind: "aggro", label: "Aggro on you", mark: ["arrow", 14, "hue-rotate(0deg)"], row: null, when: "In fights" },
	{ kind: "others", label: "Default", mark: null, row: null, when: "Always" },
];
let plateKind = "target";
const PLATE_SAMPLES = [
	{ name: "Gnoll Brute", react: "hostile", level: 17, hp: 0.72 }, { name: "Kodo Bull", react: "neutral", level: 14, hp: 0.9 },
	{ name: "Stormwind Guard", react: "friendly", level: 55, hp: 1 }, { name: "Elandra", cls: "mage", player: true, level: 60, hp: 0.64 },
];
let plateSample = 0, plateCloser = false, forever = false;
function scenePrep(el, h1) { el.style.backgroundImage = `url(${IMG.scene})`; el.style.backgroundPosition = "center 62%"; if (h1) el.style.height = h1 + "px"; }
function drawPlatePreview(el, l, hovering, comparing) {
	scenePrep(el);
	const r = PLATE_ROWS.find((x) => x.kind === plateKind);
	const s = PLATE_SAMPLES[plateSample];
	const sc = plateCloser ? 2.3 : 1.6;
	el.innerHTML = `<span class="cap">Preview</span><span class="tag">${comparing ? "Before this row's changes" : "Preview: not saved"}</span>
		<div style="position:absolute;left:50%;top:44%;transform:translate(-50%,-50%) scale(${sc})">${plateHTML(s, l, { row: r.row, mark: r.mark, forever, pos: "position:relative" })}</div>
		<div class="pills">${PLATE_SAMPLES.map((x, i) => `<button type="button" class="pillbtn ${i === plateSample ? "on" : ""}" data-s="${i}">${["Hostile", "Neutral", "Friendly", "Player"][i]}</button>`).join("")}<span class="sp"></span><button type="button" class="pillbtn on">Scene</button><button type="button" class="pillbtn ${plateCloser ? "on" : ""}" data-c="1">Closer</button></div>`;
	el.classList.toggle("hovering", hovering || comparing);
	$$("[data-s]", el).forEach((b) => (b.onclick = () => { plateSample = +b.dataset.s; platePanel.draw(); }));
	$("[data-c]", el).onclick = () => { plateCloser = !plateCloser; platePanel.draw(); };
}
const PLATE_TABS = [
	{ name: "Bar", fields: [
		{ key: "texture", label: "Texture", type: "tiles", pic: "texture", options: TEX_OPTS, max: 11 },
		{ key: "gradient", label: "Gradient", type: "seg", options: opt([["off", "Off"], ["on", "On", "The fill fades from its color on the left to the color below."]]) },
		{ key: "gradColor", label: "Fades to", type: "chips", when: (l) => l.gradient === "on" },
		{ key: "back", label: "Background", type: "chips", flag: "new", palette: [[0, 0, 0], [0.1, 0.08, 0.06], [0.15, 0.1, 0.07], [0.06, 0.06, 0.14], [0.2, 0.2, 0.22]] },
		{ key: "backAlpha", label: "Background opacity", type: "slider", flag: "new", min: 0, max: 1, step: 0.05, fmt: pct },
	] },
	{ name: "Shape", fields: [
		{ key: "shape", label: "Bar shape", type: "tiles", pic: "shape", flag: "new", options: Object.entries(SHAPES).map(([v, label]) => ({ v, label })),
			help: "The Bar shape General already gives the personal display, now on plates too." },
		{ key: "width", label: "Width", type: "slider", flag: "test", min: 0.6, max: 1.6, step: 0.05, fmt: pct, help: "This row's plates only (All rows' width stays under the grid). Plate size is one for all plates in the game, and it lays out a plate's parts again on each refresh: the bar can be resized inside it, but the click area stays the game's." },
		{ key: "height", label: "Height", type: "slider", flag: "test", min: 0.4, max: 2.5, step: 0.05, fmt: pct },
	] },
	{ name: "Text", fields: [
		{ key: "font", label: "Font", type: "tiles", pic: "font", options: FONT_OPTS, max: 11 },
		{ key: "textSize", label: "Size", type: "slider", min: 0.5, max: 2, step: 0.05, fmt: pct },
		{ key: "outline", label: "Outline", type: "seg", sample: "outline", options: opt([[0, "None"], [1, "Thin"], [2, "Thick"]]) },
		{ key: "shadow", label: "Shadow", type: "seg", options: opt([["game", "The game's"], ["on", "Shadow"], ["none", "None"]]) },
		{ key: "namePos", label: "Name", type: "seg", flag: "test", options: opt([["above", "Above the bar"], ["inside", "On the bar"], ["below", "Under the bar"]]) },
		{ key: "healthText", label: "Health text", type: "seg", flag: "test", options: opt([["none", "None"], ["percent", "Percent"], ["value", "Number"]]),
			help: "Health is secret in fights on retail and on Forever: drawn only if the game hands it to the text as it is. Test first." },
	] },
	{ name: "Border", fields: [
		{ key: "border", label: "Border", type: "tiles", pic: "border", options: opt([["game", "The game's"], ["none", "None"], ["thin", "Thin"], ["thick", "Thick"], ["custom", "Custom"]]) },
		{ key: "borderSize", label: "Thickness", type: "slider", min: 1, max: 6, step: 1, fmt: (v) => v + " px", when: (l) => l.border === "custom" },
		{ key: "borderColor", label: "Color", type: "chips", when: (l) => l.border === "custom" },
	] },
	{ name: "Level", fields: [
		{ key: "level", label: "Level box", type: "seg", options: opt([["show", "Shown"], ["hide", "Hidden"]]), help: "WoW Forever's plates only: retail's have no level box." },
	] },
];
let platePanel;

// ---------- Mock 3: Name Style page + its Look panel
const NAME_KINDS = [
	{ kind: "all", label: "All names", note: "Every name, unless its row below has its own" },
	{ kind: "target", label: "Your target" },
	{ kind: "group", label: "Group members" },
	{ kind: "friends", label: "Friendly players" },
	{ kind: "enemies", label: "Enemy players" },
	{ kind: "service", label: "Service NPCs" },
	{ kind: "friendly", label: "Friendly NPCs" },
	{ kind: "neutral", label: "Neutral NPCs" },
	{ kind: "hostile", label: "Hostile NPCs" },
	{ kind: "fminions", label: "Friendly minions" },
	{ kind: "gminions", label: "Group minions" },
	{ kind: "eminions", label: "Enemy minions" },
];
const NAME_SAMPLES = {
	all: { name: "Stormwind Guard", react: "friendly", level: 55 },
	target: { name: "Defias Pillager", react: "hostile", level: 18, elite: "elite", marker: true },
	group: { name: "Thrall", cls: "shaman", react: "friendly", guild: "Horde Vanguard", level: 60 },
	friends: { name: "Elandra", cls: "mage", react: "friendly", guild: "Knights of Azeroth", level: 60 },
	enemies: { name: "Varok", cls: "warrior", react: "hostile", level: 60, guild: "Blood and Thunder" },
	service: { name: "Innkeeper Allison", react: "friendly", title: "Innkeeper", level: 30 },
	friendly: { name: "Stormwind Guard", react: "friendly", level: 55 },
	neutral: { name: "Kodo Bull", react: "neutral", level: 14 },
	hostile: { name: "Gnoll Brute", react: "hostile", level: 17, elite: "rare" },
	fminions: { name: "Searing Totem", react: "friendly", level: 50 },
	gminions: { name: "Wolf", react: "friendly", level: 58 },
	eminions: { name: "Felhunter", react: "hostile", level: 60 },
};
// (where each sits on the page's scene: the near ones bigger)
const NAME_SPOTS = { target: [0.5, 0.5, 1.2], group: [0.2, 0.3, 0.85], friends: [0.8, 0.27, 0.85], enemies: [0.66, 0.68, 1.05], service: [0.33, 0.68, 1.05],
	friendly: [0.12, 0.79, 1.1], neutral: [0.85, 0.83, 1.15], hostile: [0.5, 0.17, 0.75], gminions: [0.37, 0.33, 0.8], eminions: [0.86, 0.55, 0.8] };
let nameKind = "all", nameCloser = false, nameDistance = 0.1;
function drawNameLookPreview(el, l, hovering, comparing) {
	scenePrep(el);
	const kinds = nameKind === "all" ? ["hostile", "neutral", "friends", "service"] : [nameKind];
	const W = 516, H = 128, sc = nameCloser ? 1.6 : 1.2;
	const spots = kinds.length === 1 ? [[W / 2, H * 0.42]] : [[W * 0.16, H * 0.3], [W * 0.43, H * 0.46], [W * 0.68, H * 0.3], [W * 0.86, H * 0.5]];
	el.innerHTML = `<span class="cap">Preview</span><span class="tag">${comparing ? "Before this row's changes" : "Preview: not saved"}</span>` +
		kinds.map((k, i) => nameHTML(NAME_SAMPLES[k], k === nameKind || nameKind === "all" ? l : names.look(k), spots[i], sc)).join("") +
		`<div class="pills"><span class="sp"></span><button type="button" class="pillbtn on">Scene</button><button type="button" class="pillbtn ${nameCloser ? "on" : ""}" data-c="1">Closer</button></div>`;
	el.classList.toggle("hovering", hovering || comparing);
	$("[data-c]", el).onclick = () => { nameCloser = !nameCloser; namePanel.draw(); };
}
const NAME_TABS = [
	{ name: "Text", fields: [
		{ key: "font", label: "Font", type: "tiles", pic: "font", options: FONT_OPTS, max: 11 },
		{ key: "size", label: "Size", type: "slider", min: 0.5, max: 2, step: 0.05, fmt: pct },
		{ key: "alpha", label: "Opacity", type: "slider", min: 0.2, max: 1, step: 0.05, fmt: pct },
		{ key: "outline", label: "Outline", type: "seg", sample: "outline", options: opt([[0, "None"], [1, "Thin"], [2, "Thick"]]) },
		{ key: "outlineColor", label: "Outline color", type: "seg", flag: "test", options: opt([["black", "Black"], ["custom", "Custom"]]), when: (l) => l.outline > 0,
			help: "Custom draws the name again round itself (ns.SetTextRim, as Battle Vision's rim). It reads the name's text, which can be secret: test, and keep it to a few rows if it costs too much." },
		{ key: "outlineTint", label: "Its color", type: "chips", when: (l) => l.outline > 0 && l.outlineColor === "custom" },
		{ key: "shadow", label: "Shadow", type: "seg", options: opt([["none", "None"], ["soft", "Soft"], ["hard", "Hard"]]) },
		{ key: "shadowAlpha", label: "Shadow opacity", type: "slider", min: 0, max: 1, step: 0.05, fmt: pct, when: (l) => l.shadow !== "none" },
		{ key: "caps", label: "Letters", type: "seg", flag: "test", options: opt([["as", "As written"], ["caps", "CAPITALS"]]),
			help: "Only where the game lets us read the name; elsewhere it shows as written. A capitals-only font (Bebas Neue) works everywhere." },
	] },
	{ name: "Color", fields: [
		{ key: "colorBy", label: "Color by", type: "seg", options: opt([["reaction", "How they see you"], ["class", "Class (players)"], ["one", "One color"]]) },
		{ key: "hostile", label: "Hostile", type: "chips", flag: "new", when: (l) => l.colorBy !== "one", palette: [[1, 0, 0], [1, 0.25, 0.2], [0.9, 0.36, 0.28], [0.8, 0.15, 0.2], [1, 0.5, 0.4]] },
		{ key: "neutral", label: "Neutral", type: "chips", flag: "new", when: (l) => l.colorBy !== "one", palette: [[1, 1, 0], [1, 0.9, 0.3], [0.96, 0.82, 0.48], [0.95, 0.7, 0.2]] },
		{ key: "friendly", label: "Friendly", type: "chips", flag: "new", when: (l) => l.colorBy !== "one", palette: [[0, 1, 0], [0.4, 1, 0.4], [0.64, 0.86, 0.46], [0.3, 0.8, 0.6]] },
		{ key: "friends", label: "Friendly players", type: "seg", options: opt([["blue", "Blue"], ["class", "Class colors"], ["white", "White"]]), when: (l) => l.colorBy === "reaction" },
		{ key: "enemies", label: "Enemy players", type: "seg", flag: "new", options: opt([["class", "Class colors"], ["react", "Hostile's color"]]), when: (l) => l.colorBy !== "one" },
		{ key: "one", label: "Color", type: "chips", when: (l) => l.colorBy === "one" },
		{ type: "note", html: "Health on names (the name greys from the right as health drops) stays Heal Vision's: <a href='#'>Heal Vision &gt; Names</a>." },
	] },
	{ name: "Glow", fields: [
		{ key: "glow", label: "Glow", type: "seg", flag: "new", options: opt([["none", "None"], ["soft", "Soft glow"]]),
			help: "A soft light behind the name (Textures/SoftGlow), one texture per name: profile with 40 plates up." },
		{ key: "glowColor", label: "Glow color", type: "chips", when: (l) => l.glow !== "none", palette: [[1, 0.82, 0], [1, 0.72, 0.3], [0.42, 0.86, 0.2], [0.55, 0.42, 0.95], [0.72, 0.88, 1], [1, 1, 1]] },
	] },
	{ name: "Background", fields: [
		{ key: "backdrop", label: "Behind the name", type: "seg", flag: "test", options: opt([["none", "Nothing"], ["band", "Band"], ["pill", "Pill"], ["banner", "Banner"]]),
			help: "Sized to the name: needs its width, which the game may keep secret. If so, one width for every name." },
		{ key: "backdropColor", label: "Color", type: "chips", when: (l) => l.backdrop !== "none", palette: [[0, 0, 0], [0.15, 0.1, 0.07], [0.06, 0.06, 0.14], [0.2, 0.2, 0.22]] },
		{ key: "backdropAlpha", label: "Opacity", type: "slider", min: 0.1, max: 1, step: 0.05, fmt: pct, when: (l) => l.backdrop !== "none" },
	] },
	{ name: "Second line", fields: [
		{ key: "line2", label: "Shows", type: "seg", options: opt([["both", "Guilds and titles"], ["guild", "Guilds"], ["title", "Titles"], ["none", "Nothing"]]),
			help: "Which guilds show still goes by the Names grid's Guild names row (Nameplates page)." },
		{ key: "line2Size", label: "Size", type: "slider", flag: "new", min: 0.5, max: 1.2, step: 0.05, fmt: pct, help: "Next to the name's." },
		{ key: "line2Color", label: "Color", type: "seg", flag: "new", options: opt([["dim", "Name's, dimmed"], ["grey", "Grey"], ["gold", "Gold"], ["theme", "Theme's"]]) },
		{ key: "brackets", label: "Brackets", type: "seg", options: opt([["angle", "<Innkeeper>"], ["none", "Innkeeper"], ["guillemet", "\u00abInnkeeper\u00bb"]]),
			help: "Moved here from the Nameplates page's Service NPCs section." },
		{ key: "serviceIcons", label: "Service icons", type: "check", text: "An icon in place of the title (an anvil for repairs\u2026)", only: (k) => k === "all" || k === "service" },
	] },
	{ name: "Level", fields: [
		{ key: "level", label: "Level", type: "seg", flag: "test", options: opt([["none", "None"], ["before", "Before the name"], ["after", "After it"]]) },
		{ key: "elite", label: "Elite and rare", type: "seg", flag: "test", options: opt([["none", "None"], ["mark", "A mark beside the name"]]) },
		{ key: "marker", label: "Raid marker", type: "seg", flag: "new", options: opt([["above", "Above"], ["left", "Left"], ["right", "Right"]]),
			help: "Kept up over names by the Names grid's Raid marker row." },
	] },
];
let namePanel;

// ---------- drawing the pages
function themeStrip(mount, kind, store, onPick, sample) {
	const list = kind === "plate" ? PLATE_THEMES : NAME_THEMES;
	const main = partTheme(kind, "main");
	mount.innerHTML = "";
	const cards = [{ key: "main", name: kind === "plate" ? "Follow General" : "Follow main theme", sub: TH[MAIN_THEME.key].name, look: main.look }, ...list.map((t) => ({ key: t.key, name: t.name, sub: t.was ? "was a preset" : t.family ? "" : "on its own", look: t.look }))];
	for (const c of cards) {
		const b = h(`<button type="button" class="tcard ${store.pick === c.key ? "on" : ""} ${c.key === "main" ? "follow" : ""}" title="${esc((list.find((t) => t.key === c.key) || {}).about || "Whatever the main theme on Style > General brings: " + c.sub)}"><span class="stage-mini" style="background:url(${IMG.scene}) center 60%/cover"></span><span class="tn">${esc(c.name)}${c.sub ? `<br><small>${esc(c.sub)}</small>` : ""}</span></button>`);
		const mini = $(".stage-mini", b);
		if (kind === "plate") mini.innerHTML = `<div style="position:absolute;left:50%;top:50%;transform:translate(-50%,-50%) scale(.95)">${plateHTML(sample, { ...GAME_PLATE, ...c.look }, { pos: "position:relative" })}</div>`;
		else mini.innerHTML = nameHTML({ name: "Allison", react: "friendly", title: "Innkeeper" }, { ...GAME_NAME, ...c.look }, [64, 26], 1.05);
		b.onclick = () => { store.pick = c.key; onPick(); };
		mount.appendChild(b);
	}
}
function drawPlatePage() {
	const root = $("#np-page");
	themeStrip($("#np-themes", root), "plate", plates, () => { drawPlatePage(); platePanel.draw(); }, { name: "Kodo Bull", react: "neutral", hp: 0.8 });
	$("#np-theme-now").textContent = plates.pick === "main" ? `Following General (the ${partTheme("plate", "main").name} theme): its texture, border and bar shape, as plates do today` : `${partTheme("plate", plates.pick).name}, picked here: stays when the main theme changes`;
	// scene: a plate per row
	const sc = $("#np-scene", root);
	scenePrep(sc, 210);
	const spots = { target: [0.27, 0.42, 1], mouseover: [0.73, 0.4, 1], focus: [0.16, 0.76, 0.9], aggro: [0.5, 0.7, 0.95], others: [0.5, 0.17, 0.75] };
	const who = { target: PLATE_SAMPLES[0], mouseover: PLATE_SAMPLES[1], focus: { name: "Defias Pillager", react: "hostile", level: 18, hp: 0.4 }, aggro: { name: "Gnoll Mystic", react: "hostile", level: 16, hp: 0.55 }, others: { name: "Kobold Miner", react: "hostile", level: 9, hp: 0.85 } };
	sc.innerHTML = `<span class="cap">Preview</span>` + PLATE_ROWS.map((r) => {
		const [x, y, s] = spots[r.kind];
		const glow = r.kind === plateKind ? "filter:drop-shadow(0 0 6px rgba(255,209,0,.55));" : "";
		return `<div style="position:absolute;left:${x * 100}%;top:${y * 100}%;transform:translate(-50%,-50%) scale(${s * 1.25});${glow}">${plateHTML({ ...who[r.kind], name: r.label === "Default" ? who.others.name : who[r.kind].name }, plates.look(r.kind), { row: r.row, mark: r.mark, pos: "position:relative" })}</div>`;
	}).join("");
	// grid
	const g = $("#np-grid", root);
	g.innerHTML = `<div class="grow head look-dim"><span></span><span></span><span style="color:#d9a6ff">Mark</span><span style="color:#ffcc59">Look</span><span style="color:#8cccff">When</span></div>`;
	PLATE_ROWS.forEach((r, i) => {
		const own = Object.keys(plates.rows[r.kind] || {});
		const names2 = { texture: "Texture", border: "Border", gradient: "Gradient", font: "Font", textSize: "Size", outline: "Outline", shadow: "Shadow", shape: "Shape", width: "Width", height: "Height", back: "Background", backAlpha: "Background", namePos: "Name", healthText: "Health text", borderSize: "Border", borderColor: "Border", gradColor: "Gradient", level: "Level" };
		const words = [...new Set(own.map((k) => names2[k] || k))];
		const chip = words.length ? `<span class="lookchip">${esc(words.join(" · "))}</span>` : `<span class="lookchip inh">${r.kind === "others" ? (plates.pick === "main" ? "General (" + esc(partTheme("plate", "main").name) + ")" : esc(partTheme("plate", plates.pick).name) + " (theme)") : "Default row's"}</span>`;
		const markCell = r.mark ? `<span class="samplebox" style="width:44px;height:22px"><span style="width:12px;height:12px;background:url(${IMG["tex_target" + r.mark[0]]}) center/contain no-repeat;${r.mark[2] ? "filter:" + r.mark[2] : ""}"></span></span>` : `<span class="look-dim">Game's</span>`;
		const row = h(`<div class="grow ${r.kind === plateKind ? "on" : ""}" role="button" tabindex="0"><span class="num">${r.kind === "others" ? "" : i + 1}</span><span>${esc(r.label)}</span><span>${markCell}</span><span>${chip}</span><span class="look-dim">${esc(r.when)}</span></div>`);
		row.onclick = () => { plateKind = r.kind; drawPlatePage(); platePanel.draw(); };
		row.onkeydown = (e) => { if (e.key === "Enter") row.onclick(); };
		g.appendChild(row);
	});
}
function drawNamePage() {
	const root = $("#nm-page");
	themeStrip($("#nm-themes", root), "names", names, () => { drawNamePage(); namePanel.draw(); });
	$("#nm-theme-now").textContent = names.pick === "main" ? `Following the main theme: ${partTheme("names", "main").name} names` : `${partTheme("names", names.pick).name}, picked here: stays when the main theme changes`;
	const sc = $("#nm-scene", root);
	scenePrep(sc, 230);
	const W = 586, H = 230;
	const far = nameDistance;
	sc.innerHTML = `<span class="cap">Preview</span>` + Object.entries(NAME_SPOTS).map(([k, [x, y, s]]) => {
		const depth = 1 - far * (1 - s) * 1.4;
		const ring = k === nameKind ? `<span style="position:absolute;left:${x * W}px;top:${y * H}px;width:6px;height:6px;margin:10px 0 0 -3px;border-radius:50%;background:#ffd100;box-shadow:0 0 6px #ffd100"></span>` : "";
		return nameHTML(NAME_SAMPLES[k], names.look(k), [x * W, y * H], Math.max(0.75, 1.2 * s * depth)) + ring;
	}).join("") + `<div class="pills"><button type="button" class="pillbtn on">Scene</button><span class="sp"></span><span class="look-text" style="align-self:center">Near</span><input id="nm-dist" type="range" min="0" max="1" step="0.05" value="${far}" aria-label="Distance" style="width:120px;accent-color:#ffd100"><span class="look-text" style="align-self:center">Far</span></div>`;
	$("#nm-dist", sc).oninput = (e) => { nameDistance = +e.target.value; drawNamePage(); };
	const g = $("#nm-grid", root);
	g.innerHTML = `<div class="grow head look-dim" style="grid-template-columns:26px 150px 132px 1fr"><span></span><span></span><span style="color:#ffcc59">Sample</span><span style="color:#ffcc59">Look</span></div>`;
	NAME_KINDS.forEach((r) => {
		const own = Object.keys(names.rows[r.kind] || {});
		const words = { font: "Font", size: "Size", alpha: "Opacity", caps: "Capitals", colorBy: "Color", hostile: "Colors", neutral: "Colors", friendly: "Colors", friends: "Color", enemies: "Color", one: "Color", outline: "Outline", outlineColor: "Outline", outlineTint: "Outline", shadow: "Shadow", shadowAlpha: "Shadow", glow: "Glow", glowColor: "Glow", backdrop: "Backdrop", backdropColor: "Backdrop", backdropAlpha: "Backdrop", line2: "Second line", line2Size: "Second line", line2Color: "Second line", brackets: "Second line", serviceIcons: "Icons", level: "Level", elite: "Elite", marker: "Marker" };
		const w = [...new Set(own.map((k) => words[k] || k))];
		const chip = w.length ? `<span class="lookchip">${esc(w.join(" · "))}</span>` : `<span class="lookchip inh">${r.kind === "all" ? esc(partTheme("names", names.pick).name) + " (theme)" : "All names'"}</span>`;
		const sample = NAME_SAMPLES[r.kind];
		const row = h(`<div class="grow ${r.kind === nameKind ? "on" : ""}" role="button" tabindex="0" style="grid-template-columns:26px 150px 132px 1fr${r.kind === "all" ? ";border-bottom:1px solid rgba(255,209,0,.35)" : ""}"><span></span><span>${esc(r.label)}</span><span class="samplebox" style="width:124px;background:url(${IMG.scene}) center 58%/300px auto">${nameHTML({ ...sample, guild: null, title: null, marker: false }, names.look(r.kind), [62, 12], 0.9)}</span><span>${chip}</span></div>`);
		row.onclick = () => { nameKind = r.kind; drawNamePage(); namePanel.draw(); };
		row.onkeydown = (e) => { if (e.key === "Enter") row.onclick(); };
		g.appendChild(row);
	});
}

// ---------- Mock 1: General's theme gallery, with plates and names
const REACH = [
	{ key: "frames", label: "Unit, raid and personal frames", now: "Bars, fonts, borders and shapes" },
	{ key: "panels", label: "Tooltips, bubbles and menus", now: "Panels, palette and corners" },
	{ key: "bars", label: "Action bars", now: "Button shape and edges" },
	{ key: "plates", label: "Nameplates", now: "Its plate theme", part: "plate", link: "Nameplate Style" },
	{ key: "names", label: "Names", now: "Its name theme", part: "names", link: "Name Style" },
	{ key: "casts", label: "Cast bars", now: "Cast colors" },
	{ key: "visions", label: "Visions", now: "Card fonts and colors" },
];
const reachOn = Object.fromEntries(REACH.map((r) => [r.key, true]));
function drawGallery() {
	const g = $("#gal");
	g.innerHTML = "";
	for (const t of THEMES) {
		const sw = (t.swatch || []).slice(1).map((c) => `<i style="background:${rgb(c)}"></i>`).join("");
		const font = FONT_FAMILY[t.settings && t.settings.styleFont] || FONT_FAMILY.game;
		const plateLook = { ...GAME_PLATE, ...PT[t.key].look };
		const nameLook = { ...GAME_NAME, ...NT[t.key].look };
		const bg = t.panel ? rgb(t.panel) : "#141210";
		const edge = t.line ? rgb(t.line) : "#3d3a33";
		const corner = t.corner ? IMG["corner_" + t.corner.toLowerCase()] : null;
		const b = h(`<button type="button" class="tg ${t.key === MAIN_THEME.key ? "on" : ""}" style="background:${bg};box-shadow:inset 0 0 0 ${t.lineSize || 1}px ${edge}" title="${esc(t.tip)}">
			${corner ? `<span class="corner" style="left:2px;top:2px;background-image:url(${corner})"></span><span class="corner" style="right:2px;bottom:2px;transform:rotate(180deg);background-image:url(${corner})"></span>` : ""}
			<span class="tgn" style="font-family:${font};color:${rgb(t.menu ? t.menu.accent : [1, 0.82, 0])}">${esc(t.name)}</span><span class="sw">${sw}</span>
			<span class="mini">${nameHTML({ name: "Marshal Dughan", react: "friendly" }, nameLook, [79, 10], 0.9)}<span style="position:absolute;left:79px;top:38px;transform:translate(-50%,-50%) scale(.9)">${plateHTML({ name: "Gnoll Brute", react: "hostile", hp: 0.7 }, plateLook, { pos: "position:relative" })}</span></span></button>`);
		b.onclick = () => { MAIN_THEME.key = t.key; castStore.rows.def = clone(castWritten().look); castPanel && castPanel.draw(); drawGallery(); drawPlatePage(); drawNamePage(); platePanel.draw(); namePanel.draw(); drawLibrary(); };
		g.appendChild(b);
	}
	const t = TH[MAIN_THEME.key];
	const r = $("#reach");
	r.innerHTML = `<div class="hdr" style="margin-top:0">${esc(t.name)} reaches</div><div class="look-dim" style="margin-bottom:6px;line-height:1.35">Off: that part keeps what you have when you pick a theme. Undo still puts everything back.</div>`;
	for (const x of REACH) {
		let now = x.now;
		if (x.part === "plate") now = plates.pick === "main" ? `${PT[t.key].name} plates` : `Kept: ${partTheme("plate", plates.pick).name} plates (picked on Nameplate Style)`;
		if (x.part === "names") now = names.pick === "main" ? `${NT[t.key].name} names` : `Kept: ${partTheme("names", names.pick).name} names (picked on Name Style)`;
		const it = h(`<div class="ritem"><span class="rn">${esc(x.label)}</span><button type="button" class="tog ${reachOn[x.key] ? "on" : ""}" aria-label="${esc(x.label)}" aria-pressed="${reachOn[x.key]}"></button><span class="rd">${esc(reachOn[x.key] ? now : "Keep mine")}</span></div>`);
		$(".tog", it).onclick = () => { reachOn[x.key] = !reachOn[x.key]; drawGallery(); };
		r.appendChild(it);
	}
}

// ---------- Mock 4: Cast Bar Style on the template
const castStore = makeStore({ texture: "game", height: 1, spark: true, icon: true, iconSize: 1, shield: true, font: "game", spell: true, timer: false, border: "game",
	cast: [1, 0.7, 0], channel: [0, 0.8, 0], locked: [0.6, 0.6, 0.6] }, "plate", "def", "Default tab's", "Theme");
castStore.theme = () => ({ name: "", look: {} });
const castWritten = () => { const t = TH[MAIN_THEME.key]; return { name: t.name, look: t.cast ? { cast: t.cast, channel: t.channel, locked: t.locked } : {} }; };
castStore.writtenBy = (kind) => (kind === "def" ? castWritten() : null);
castStore.rows.def = clone(castWritten().look);
let castKind = "plates", castPanel;
function drawCast(el, l, hovering) {
	scenePrep(el);
	const one = (label, col, w, y) => {
		const hgt = Math.round(8 * l.height);
		const bord = l.border === "thin" ? "box-shadow:0 0 0 1px #000" : l.border === "none" ? "" : "box-shadow:0 0 0 2px rgba(0,0,0,.75)";
		const ic = l.icon ? `<span style="width:${14 * l.iconSize}px;height:${14 * l.iconSize}px;background:linear-gradient(135deg,#d8742a,#5a2a10);box-shadow:0 0 0 1px #000;flex:none"></span>` : "";
		const spark = l.spark ? `<span style="position:absolute;left:${w * 100}%;top:-3px;bottom:-3px;width:3px;margin-left:-2px;background:radial-gradient(#fff,rgba(255,255,200,0))"></span>` : "";
		return `<div style="position:absolute;left:50%;top:${y}px;transform:translateX(-50%) scale(1.5);display:flex;gap:3px;align-items:center">${ic}<div style="position:relative;width:118px;height:${hgt}px;background:rgba(0,0,0,.6);${bord}"><div style="position:absolute;left:0;top:0;bottom:0;width:${w * 100}%;${fillCSS(l.texture, col)}"></div>${spark}</div></div>` +
			(l.spell ? `<div style="position:absolute;left:50%;top:${y + 18}px;transform:translateX(-50%);font:12px ${FONT_FAMILY[l.font] || FONT_FAMILY.game};color:#fff;text-shadow:1px -1px 0 #000">${label}${l.timer ? " <span style='color:#ccc'>1.2</span>" : ""}</div>` : "");
	};
	el.innerHTML = `<span class="cap">Preview</span><span class="tag">Preview: not saved</span>` + one("Fireball", l.cast, 0.62, 18) + one("Drain Life", l.channel, 0.45, 62);
	el.classList.toggle("hovering", hovering);
}
const CAST_TABS = [
	{ name: "Bar", fields: [
		{ key: "texture", label: "Texture", type: "tiles", pic: "texture", options: TEX_OPTS, max: 7 },
		{ key: "cast", label: "Casting", type: "chips", palette: [[1, 0.7, 0], [0.93, 0.7, 0.28], [1, 0.6, 0.12], [0.72, 0.9, 1], [0.5, 0.9, 0.24]] },
		{ key: "channel", label: "Channeling", type: "chips", palette: [[0, 0.8, 0], [0.42, 0.6, 0.78], [0.95, 0.82, 0.4], [0.56, 0.62, 0.95]] },
		{ key: "height", label: "Height", type: "slider", min: 0.5, max: 2, step: 0.05, fmt: pct },
		{ key: "spark", label: "Spark", type: "check", text: "The spark at the fill's end" },
	] },
	{ name: "Icon", fields: [
		{ key: "icon", label: "Spell icon", type: "check", text: "The spell's icon" },
		{ key: "iconSize", label: "Size", type: "slider", min: 0.5, max: 2, step: 0.05, fmt: pct },
		{ key: "shield", label: "Shield", type: "check", text: "The shield on casts that can't be interrupted" },
	] },
	{ name: "Text", fields: [
		{ key: "font", label: "Font", type: "tiles", pic: "font", options: FONT_OPTS, max: 7 },
		{ key: "spell", label: "Spell name", type: "check", text: "The spell's name" },
		{ key: "timer", label: "Time left", type: "check", text: "Seconds left at its right end" },
	] },
	{ name: "Border", fields: [
		{ key: "border", label: "Border", type: "tiles", pic: "border", options: opt([["game", "The game's"], ["none", "None"], ["thin", "Thin"]]) },
	] },
];

// ---------- the theme library (every family, plates and names)
function drawLibrary() {
	const L = $("#lib");
	L.innerHTML = "";
	for (const t of THEMES.concat([{ key: "clean", standalone: true }, { key: "raider", standalone: true }, { key: "minimal", standalone: true }])) {
		const p = PT[t.key], n = NT[t.key];
		if (!p && !n) continue;
		const pl = { ...GAME_PLATE, ...(p ? p.look : {}) };
		const nl = { ...GAME_NAME, ...(n ? n.look : {}) };
		const kv = [];
		if (p && p.look.texture) kv.push(["Bar", `${TEX_NAME[pl.texture] || pl.texture}, ${SHAPES[pl.shape] || pl.shape}, ${pl.border === "custom" ? pl.borderSize + " px line" : pl.border}`]);
		if (n && t.key !== "game") kv.push(["Names", `${FONT_NAME[nl.font]}${nl.glow !== "none" ? ", glow" : ""}${nl.backdrop !== "none" ? ", band" : ""}${nl.shadow !== "none" ? ", " + nl.shadow + " shadow" : ""}`]);
		const card = h(`<div class="libcard"><div class="ls" style="background:url(${IMG.scene}) center 62%/cover"></div><div class="lt"><b>${esc((p || n).name)}</b><span style="color:#9a9aa3">${esc(t.standalone ? "Plate theme on its own" : t.key === "game" ? "Plates and names as the game draws them" : "Plate and name themes")}</span>${kv.map(([k, v]) => `<span class="kv">${k}: <span>${esc(v)}</span></span>`).join("")}</div></div>`);
		const ls = $(".ls", card);
		ls.innerHTML = `<div style="position:absolute;left:50%;top:36%;transform:translate(-50%,-50%) scale(1.3)">${plateHTML({ name: "Gnoll Brute", react: "hostile", hp: 0.66 }, pl, { pos: "position:relative" })}</div>` +
			(n || t.key === "game" ? nameHTML({ name: "Allison", react: "friendly", title: "Innkeeper" }, nl, ["27%", 88], 1.1) + nameHTML({ name: "Kodo Bull", react: "neutral" }, nl, ["73%", 88], 1.1) : "");
		L.appendChild(card);
	}
	for (const n of NAME_THEMES.filter((x) => !x.family && x.key !== "game")) {
		const nl = { ...GAME_NAME, ...n.look };
		const card = h(`<div class="libcard"><div class="ls" style="background:url(${IMG.scene}) center 62%/cover"></div><div class="lt"><b>${esc(n.name)}</b><span style="color:#9a9aa3">${esc(n.was ? "Name theme (was the " + n.was + " preset)" : "Name theme on its own")}</span><span class="kv">About: <span>${esc(n.about)}</span></span></div></div>`);
		$(".ls", card).innerHTML = nameHTML(NAME_SAMPLES.hostile, nl, [70, 34], 1) + nameHTML(NAME_SAMPLES.service, nl, [190, 30], 1) + nameHTML({ name: "Elandra", cls: "mage", react: "friendly", guild: "Knights of Azeroth" }, nl, [130, 76], 1);
		L.appendChild(card);
	}
}

// ---------- the proposed data, as Lua (from the same tables)
function luaVal(v) {
	if (Array.isArray(v)) return "{ " + v.map((x) => +(+x).toFixed(2)).join(", ") + " }";
	if (typeof v === "string") return `<span class="s">"${v}"</span>`;
	return String(typeof v === "number" ? +v.toFixed(2) : v);
}
function drawLua() {
	const pick = ["codex", "slate"];
	let out = `<span class="c">-- PlateThemes.lua (new): a Nameplate Style look per theme, as the Default row's.</span>\n<span class="c">-- Made from each main theme's own colors and art; three stand alone.</span>\nns.PLATE_THEMES = {\n`;
	for (const k of pick.concat(["clean"])) {
		const t = PT[k];
		out += `\t{ key = ${luaVal(k)}, name = ${luaVal(t.name)}, look = {\n`;
		for (const [kk, v] of Object.entries(t.look)) if (v !== 0) out += `\t\t${kk} = ${luaVal(v)},\n`;
		out += `\t} },\n`;
	}
	out += `\t<span class="c">-- … one for each of the other ${THEMES.length - 3} themes, then Raider and Minimal</span>\n}\n\n<span class="c">-- NameThemes.lua (new): a Name Style look per theme, as the All names row's.</span>\nns.NAME_THEMES = {\n`;
	for (const k of pick.concat(["storybook"])) {
		const t = NT[k];
		out += `\t{ key = ${luaVal(k)}, name = ${luaVal(t.name)}, look = {\n`;
		for (const [kk, v] of Object.entries(t.look)) out += `\t\t${kk} = ${luaVal(v)},\n`;
		out += `\t} },\n`;
	}
	out += `\t<span class="c">-- … the rest; Bold and Subtle are the old presets, kept as themes</span>\n}\n\n<span class="c">-- StyleThemes.lua: each main theme names its parts (nil: its own key).</span>\nTheme({ key = <span class="s">"codex"</span>, name = <span class="s">"Gilded Codex"</span>, plates = <span class="s">"codex"</span>, names = <span class="s">"codex"</span>, <span class="c">--[[ …as now ]]</span> })\n\n<span class="c">-- Core.lua DEFAULTS: the two picks. "main": whatever the main theme names.</span>\nDEFAULTS.plateTheme = <span class="s">"main"</span>\nDEFAULTS.nameTheme = <span class="s">"main"</span>`;
	$("#lua").innerHTML = out;
}

// ---------- start
function start() {
	drawGallery();
	platePanel = LookPanel({ mount: $("#np-panel"), crumb: "Nameplates > Nameplate Style", title: () => (PLATE_ROWS.find((r) => r.kind === plateKind).label + " - Look"),
		store: plates, kind: () => plateKind, tabs: PLATE_TABS, preview: drawPlatePreview, changed: () => { drawPlatePage(); drawGallery(); }, themes: PLATE_THEMES,
		clearLabel: () => (plateKind === "others" ? "Reset all" : "Clear this row") });
	drawPlatePage();
	// (The template section's copy: the same panel, its parts numbered.)
	const demo = LookPanel({ mount: $("#np-panel-demo"), crumb: "Nameplates > Nameplate Style", title: () => "Focus - Look",
		store: plates, kind: () => "focus", tabs: PLATE_TABS, preview: (el, l, hv, cmp) => { const k = plateKind; plateKind = "focus"; drawPlatePreview(el, l, hv, cmp); plateKind = k; },
		themes: PLATE_THEMES, changed: () => { drawPlatePage(); platePanel.draw(); } });
	const badge = (target, n, dx, dy, add) => {
		if (!target) return;
		const p = demo.el, a = target.getBoundingClientRect(), o = p.getBoundingClientRect();
		const x = a.left - o.left + dx, y = a.top - o.top + dy;
		const b = h(`<span aria-hidden="true" style="position:absolute;left:${x}px;top:${y}px;z-index:9;width:18px;height:18px;border-radius:50%;background:${add ? "#ffd100" : "#7c5cd6"};color:${add ? "#111" : "#fff"};font:600 11px/18px 'Archivo Narrow',sans-serif;text-align:center;box-shadow:0 0 0 2px #08090b">${n}</span>`);
		p.appendChild(b);
	};
	const annotate = () => {
		const p = demo.el;
		$$("[aria-hidden=true]", p).forEach((x) => x.remove());
		badge($(".head", p), 1, -9, 6); badge($(".preview", p), 2, -9, 40); badge($(".preview", p), 3, 300, 2);
		badge($(".strip", p), 4, -9, 4); badge($(".fh", p), 5, -21, -2); badge($(".tiles", p), 6, -21, 12); badge($(".foot", p), 7, -9, 8);
		badge($(".tools", p), "+", -9, 2, true);
	};
	const redraw = demo.draw;
	demo.draw = () => { redraw(); annotate(); };
	annotate();
	demo.el.addEventListener("click", () => setTimeout(annotate, 0));
	namePanel = LookPanel({ mount: $("#nm-panel"), crumb: "Nameplates > Name Style", title: () => (NAME_KINDS.find((r) => r.kind === nameKind).label + " - Look"),
		store: names, kind: () => nameKind, tabs: NAME_TABS, preview: drawNameLookPreview, changed: () => { drawNamePage(); drawGallery(); }, themes: NAME_THEMES,
		clearLabel: () => (nameKind === "all" ? "Reset all" : "Clear this row") });
	drawNamePage();
	castPanel = LookPanel({ mount: $("#cb-panel"), crumb: "Nameplates > Cast Bar Style", title: () => "Nameplates - Look", store: castStore, kind: () => castKind, tabs: CAST_TABS,
		preview: drawCast, themes: [], clearLabel: () => "Clear this row" });
	drawLibrary();
	drawLua();
	$("#forever").onchange = (e) => { forever = e.target.checked; platePanel.draw(); };
}
document.fonts && document.fonts.ready ? document.fonts.ready.then(start) : start();
