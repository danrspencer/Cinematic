"""Renders a cut of the showcase video from filed takes.

A cut is a JSON file (trailer.json): an output name and a list of segments,
each a take (its file name in the library, without .mp4), where it starts
and ends ("m:ss.s" or seconds) and optionally a crop [w, h, x, y] in the
take's own pixels, for a close shot. Every segment is scaled to the output's
size (2.39:1 by default, as the takes are), then all are joined, crossfading
into each other.

The look follows the v1.7 video: captions bottom left over the picture, a
title in Palatino capitals with an italic gold line under it, on a soft dark
glow; title cards black, the title spaced out in the middle.

A segment can also have:
    "speed": 1.5          played faster (sound too; silent above 2x)
    "mute": true          silent
    "game": 0.75          its own sound at this level under the music, not the cut's
    "soundearly": 1       its own sound faded out this many seconds before it ends
    "text": "Tele Vision" the caption's title (in capitals; \n breaks it over lines)
    "sub": "A portal..."  its line underneath (italic, gold); in either, words in
                          {braces} are in the Visions' colors
    "pos": "tl"           where the caption sits: "bl" bottom left (default), "tl" top
                          left, "ml" middle left, "br" bottom right
    "size": 0.8           the caption smaller (or bigger)
    "textat": 2.0         the caption only from this many seconds in
    "split": {"take", "in", "labels": ["Retail", "Classic"]}
                          a second take beside it, the middle half of each
    "card": {"title": "CINEMATIC", "sub": "Free on CurseForge", "seconds": 4}
                          (instead of a take) a black title card; "sound": {"take", "in"}
                          in it plays that take's sound under it, fading in
    "black": 1.0          (instead of a take) this many seconds of black
    "cut": true           a hard cut into it, not a crossfade
    "fadein": 1.0         from black (and silence) over this many seconds
    "fadeout": 1.5        to black (and silence) over its last seconds
The cut's "music": {"file": "music/song.mp3", "from": 0, "volume": 1, "game": 0.25,
"fadein": 1.5, "fadeout": 3} lays a song over it all (its file in the library,
or a full path), with the game's sound turned down under it. For more than one:
"songs": [{"file", "from", "fadein"}, {"file", "at": 19, "fadein": 6}, ...], each
next one starting at that segment and crossfading over its fade-in. "gamefadein": 6
fades the game's sound in from the start over that many seconds. "sync": {"take":
"V09 boss-fight t1", "song": 69.4} holds a moment in the first song to a shot: the
song starts wherever it must for that moment to play as that take's first clip starts.

A caption fades in and out, unless the segment before or after has the same
one (then it carries on over the join). The cut's "crossfade" sets how long
each crossfade takes (default 0.6 s).

    python Tools/video/cut.py                  renders trailer.json
    python Tools/video/cut.py other.json       renders another cut
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GLOW = os.path.join(HERE, "caption-glow.png")
FONT = "C\\:/Windows/Fonts/pala.ttf"
FONT_ITALIC = "C\\:/Windows/Fonts/palai.ttf"
CREAM = "0xF2EDE3"
GOLD = "0xE0C68C"
PIL_FONT = "C:/Windows/Fonts/pala.ttf"
PIL_FONT_ITALIC = "C:/Windows/Fonts/palai.ttf"
CREAM_RGB = (242, 237, 227)
GOLD_RGB = (224, 198, 140)
ACCENT = [(255, 90, 200), (160, 100, 255), (70, 220, 255)]  # (the Visions' words: magenta, violet, cyan)
ACCENT_GLOW = (170, 100, 255, 200)
BACKING = 170  # (how dark the glow behind a caption is, 0-255)
TEXT_FADE = 0.5
HARD_CUT = 0.04  # (a crossfade this short is a cut)
ENCODE = ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
          "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"]


def seconds(value):
    if isinstance(value, (int, float)):
        return float(value)
    minutes, _, rest = value.rpartition(":")
    return float(minutes or 0) * 60 + float(rest)


def fading(length, fade_in, fade_out, start=0.0, rise=TEXT_FADE):
    """An alpha expression (0-1 over time t) fading in at start (over rise seconds)
    and out before length."""
    parts = []
    if start:
        parts.append(f"(t-{start})/{rise}")
    elif fade_in:
        parts.append(f"t/{rise}")
    if fade_out:
        parts.append(f"({length}-t)/{TEXT_FADE}")
    alpha = "1"
    for p in parts:
        alpha = f"min({alpha}\\,{p})"
    return f"max(0\\,{alpha})"


def words(text, work, name, font, size, color, x, y, alpha="1", shadow=True):
    """A drawtext filter for text (through a file: no escaping its quotes and colons)."""
    path = os.path.join(work, name + ".txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    path = path.replace("\\", "/").replace(":", "\\:")
    look = ":shadowcolor=black@0.6:shadowx=2:shadowy=2" if shadow else ""
    return (f"drawtext=fontfile='{font}':textfile='{path}':fontcolor={color}:fontsize={size}:"
            f"x={x}:y={y}:alpha='{alpha}'{look}")


def caption_picture(seg, work, i, width, height):
    """The segment's caption as a see-through picture the video's size: the glow, then
    the title (capitals, cream) and its line (italic, gold), each with a soft shadow.
    Words in {braces} are the Visions' color: a gradient across them, with a glow."""
    from PIL import Image, ImageDraw, ImageFilter, ImageFont
    pos = seg.get("pos", "bl")
    scale = float(seg.get("size", 1))
    sub = seg.get("sub")
    # (where the two lines sit: the title's top and the sub line's, as shares of the height)
    top = {"bl": 0.74, "tl": 0.08, "ml": 0.40, "br": 0.74}[pos] + (0 if sub else 0.06)
    under = top + 0.115 * scale
    right = pos == "br"
    picture = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    # (a title with a line break: each extra line pushes it, and the sub line, down)
    lines = []
    title = seg.get("text", "").upper().split("\n") if seg.get("text") else []
    step = 0.09 * scale
    for n, line in enumerate(title):
        lines.append((line, ImageFont.truetype(PIL_FONT, round(60 * scale)), CREAM_RGB, top + n * step, 84))
    if sub:
        lines.append((sub, ImageFont.truetype(PIL_FONT_ITALIC, round(42 * scale)), GOLD_RGB,
                      under + max(0, len(title) - 1) * step, 88))
    # The dark glow behind it all: as wide and tall as the words, soft at its edges,
    # so the words read on a bright or busy picture.
    measure = ImageDraw.Draw(picture)
    boxes = []
    for text, font, _, y_share, margin in lines:
        plain = text.replace("{", "").replace("}", "")
        w = measure.textlength(plain, font=font)
        x = width - margin - w if right else margin
        y = round(height * y_share)
        boxes.append((x, y, x + w, y + font.size * 1.25))
    if boxes:
        left, top_px = min(b[0] for b in boxes), min(b[1] for b in boxes)
        right_px, bottom = max(b[2] for b in boxes), max(b[3] for b in boxes)
        backing = Image.new("RGBA", picture.size, (0, 0, 0, 0))
        ImageDraw.Draw(backing).rounded_rectangle(
            [left - 70, top_px - 40, right_px + 70, bottom + 30], radius=60, fill=(0, 0, 0, BACKING))
        picture.alpha_composite(backing.filter(ImageFilter.GaussianBlur(45)))
    for text, font, color, y_share, margin in lines:
        pieces = [(p, n % 2 == 1) for n, p in enumerate(text.replace("}", "{").split("{")) if p]
        plain = "".join(p for p, _ in pieces)
        draw = ImageDraw.Draw(picture)
        x = width - margin - draw.textlength(plain, font=font) if right else margin
        y = round(height * y_share)
        shadow, accent_glow = (Image.new("RGBA", picture.size, (0, 0, 0, 0)) for _ in range(2))
        # (a wide, faint halo round the words, then a soft shadow just under them: no
        # hard edge round each letter, which looked like a cheap border on the thin italics)
        ImageDraw.Draw(shadow).text((x, y), plain, font=font, fill=(0, 0, 0, 150))
        picture.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(6, font.size // 6))))
        close = Image.new("RGBA", picture.size, (0, 0, 0, 0))
        ImageDraw.Draw(close).text((x + 1, y + 2), plain, font=font, fill=(0, 0, 0, 170))
        picture.alpha_composite(close.filter(ImageFilter.GaussianBlur(2)))
        for piece, accent in pieces:
            if accent:
                mask = Image.new("L", picture.size, 0)
                ImageDraw.Draw(mask).text((x, y), piece, font=font, fill=255)
                ImageDraw.Draw(accent_glow).text((x, y), piece, font=font, fill=ACCENT_GLOW)
                box = mask.getbbox()
                colors = Image.new("RGBA", picture.size, (0, 0, 0, 0))
                colors.paste(gradient(box[2] - box[0], box[3] - box[1]), box[:2])
                colors.putalpha(mask)
                picture.alpha_composite(accent_glow.filter(ImageFilter.GaussianBlur(8)))
                picture.alpha_composite(colors)
            else:
                ImageDraw.Draw(picture).text((x, y), piece, font=font, fill=color)
            x += draw.textlength(piece, font=font)
    path = os.path.join(work, f"{i:03d}c.png")
    picture.save(path)
    return path


def gradient(w, h):
    """The Visions' colors across a word: magenta, violet, cyan."""
    from PIL import Image
    strip = Image.new("RGB", (len(ACCENT) * 64, 1))
    for x in range(strip.width):
        t = x / (strip.width - 1) * (len(ACCENT) - 1)
        n = min(int(t), len(ACCENT) - 2)
        a, b, f = ACCENT[n], ACCENT[n + 1], t - n
        strip.putpixel((x, 0), tuple(round(a[k] + (b[k] - a[k]) * f) for k in range(3)))
    return strip.resize((max(1, w), max(1, h)), Image.BILINEAR)


def spaced(title):
    """A title card's title, its capitals spaced out."""
    return " ".join(title.upper())


def render(seg, library, work, i, width, height, fps, fade_in, fade_out):
    """One segment to its own file; returns (path, seconds long)."""
    part = os.path.join(work, f"{i:03d}.mp4")
    if "black" in seg or "card" in seg:
        card = seg.get("card")
        length = float(card.get("seconds", 4) if card else seg["black"])
        video = f"[0:v]null"
        if card:
            alpha = fading(length, True, True, rise=float(card.get("rise", TEXT_FADE)))  # ("rise": its fade-in)
            video += "," + words(spaced(card["title"]), work, f"{i:03d}t", FONT, 84, CREAM,
                                 "(w-tw)/2", "h*0.36", alpha, False)
            if card.get("sub"):
                # (its line a moment after the title: "subat" seconds, 1 by default)
                video += "," + words(card["sub"], work, f"{i:03d}s", FONT_ITALIC, 44, GOLD, "(w-tw)/2", "h*0.55",
                                     fading(length, True, True, float(card.get("subat", 1))), False)
        # (silent, or a take's sound under it: "sound": {"take", "in"}, fading in)
        sound = card.get("sound") if card else None
        if sound:
            audio_in = ["-ss", str(seconds(sound["in"])), "-t", str(length),
                        "-i", os.path.join(library, sound["take"] + ".mp4")]
            audio = (f";[1:a]volume={level(seg)},afade=t=in:st=0:d={sound.get('fadein', length)},"
                     f"aresample=48000[a]")
        else:
            audio_in = ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
            audio = ";[1:a]anull[a]"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"color=black:s={width}x{height}:r={fps}"] + audio_in +
                       ["-filter_complex", video + "[v]" + audio,
                        "-map", "[v]", "-map", "[a]", "-t", str(length)] + ENCODE + [part], check=True)
        return part, length
    start, end = seconds(seg["in"]), seconds(seg["out"])
    speed = float(seg.get("speed", 1))
    length = (end - start) / speed
    take = os.path.join(library, seg["take"] + ".mp4")
    inputs = ["-ss", str(start), "-t", str(end - start), "-i", take]
    if seg.get("split"):
        other = seg["split"]
        inputs += ["-ss", str(seconds(other["in"])), "-t", str(end - start),
                   "-i", os.path.join(library, other["take"] + ".mp4")]
        labels = other.get("labels", ["", ""])
        sides = []
        for n in range(2):
            chain = f"[{n}:v]crop=iw/2:ih:iw/4:0,scale={width // 2 - 2}:{height}:flags=lanczos,setsar=1"
            if labels[n]:
                chain += "," + words(labels[n], work, f"{i:03d}l{n}", FONT_ITALIC, 40, GOLD, "(w-tw)/2", "h*0.06")
            sides.append(chain + f"[s{n}]")
        video = ";".join(sides) + f";[s0][s1]hstack=inputs=2,pad={width}:{height}:(ow-iw)/2:0:black"
    else:
        video = "[0:v]"
        if seg.get("crop"):
            w, h, x, y = seg["crop"]
            video += f"crop={w}:{h}:{x}:{y},"
        video += f"scale={width}:{height}:flags=lanczos"
    video += f",setpts=PTS/{speed},fps={fps},setsar=1"
    if seg.get("text") or seg.get("sub"):
        # (the caption drawn as a picture, glow and all, fading in and out over the take)
        start = float(seg.get("textat", 0))
        inputs += ["-loop", "1", "-i", caption_picture(seg, work, i, width, height)]
        g = len([a for a in inputs if a == "-i"]) - 1
        alpha_in = f",fade=t=in:st={start}:d={TEXT_FADE}:alpha=1" if fade_in or start else ""
        alpha_out = f",fade=t=out:st={length - TEXT_FADE}:d={TEXT_FADE}:alpha=1" if fade_out else ""
        video += f"[base];[{g}:v]format=rgba{alpha_in}{alpha_out}[c];[base][c]overlay=0:0:shortest=1"
    if seg.get("fadein"):
        video += f",fade=t=in:st=0:d={seg['fadein']}"
    if seg.get("fadeout"):
        video += f",fade=t=out:st={length - seg['fadeout']}:d={seg['fadeout']}"
    video += "[v]"
    if seg.get("mute") or speed > 2:
        audio = f"[0:a]volume=0,atrim=0:{length}"
    elif speed == 1:
        audio = f"[0:a]volume={level(seg)}"
    else:
        audio = f"[0:a]atempo={speed},volume={level(seg)}"
    if seg.get("fadein") and seg.get("fadesound", True):
        audio += f",afade=t=in:st=0:d={seg['fadein']}"
    if seg.get("fadeout"):
        audio += f",afade=t=out:st={length - seg['fadeout']}:d={seg['fadeout']}"
    if seg.get("soundearly"):
        # (its sound gone this many seconds before it ends, fading out over a second first)
        audio += f",afade=t=out:st={max(0, length - seg['soundearly'] - 1):.3f}:d=1"
    audio += ",aresample=48000[a]"
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + ["-filter_complex", video + ";" + audio,
                    "-map", "[v]", "-map", "[a]", "-t", str(length)] + ENCODE + [part], check=True)
    return part, length


GAME = 1.0  # (the cut's game sound level under the music: main sets it)


def level(seg):
    """How loud this segment's own sound is before the cut's game level is put on it:
    its "game" level, if it has one, in place of the cut's."""
    return f"{float(seg['game']) / GAME:.3f}" if seg.get("game") is not None and GAME else "1"


def same_caption(a, b):
    return a is not None and b is not None and (a.get("text"), a.get("sub")) == (b.get("text"), b.get("sub"))


def main(args):
    sys.stdout.reconfigure(encoding="utf-8")
    cut_file = os.path.join(HERE, args[0] if args else "trailer.json")
    with open(cut_file, encoding="utf-8") as f:
        cut = json.load(f)
    with open(os.path.join(HERE, "clips.json"), encoding="utf-8") as f:
        library = json.load(f)["library"]
    width, height, fps = cut.get("width", 1920), cut.get("height", 804), cut.get("fps", 60)
    crossfade = float(cut.get("crossfade", 0.6))
    global GAME
    GAME = float(cut["music"].get("game", 0.25)) if cut.get("music") else 1.0
    segments = cut["segments"]
    work = tempfile.mkdtemp(prefix="cut-")
    parts, lengths, starts = [], [], []
    at = 0.0
    for i, seg in enumerate(segments):
        before = segments[i - 1] if i > 0 else None
        after = segments[i + 1] if i + 1 < len(segments) else None
        part, length = render(seg, library, work, i, width, height, fps,
                              not same_caption(before, seg), not same_caption(seg, after))
        parts.append(part)
        lengths.append(length)
        if "card" in seg:
            what = f"card: {seg['card']['title']}"
        elif "black" in seg:
            what = f"black {seg['black']}s"
        else:
            what = f"{seg['take']} {seg['in']}-{seg['out']}"
        print(f"  {stamp(at)}  {what}  {seg.get('note', '')}")
        starts.append(at)
        overlap = 0 if after is None else (HARD_CUT if after.get("cut") else crossfade)
        at += length - overlap
    # All joined: each crossfading into the next (a hard cut: a crossfade of a frame).
    inputs, chain, last_v, last_a, offset = [], [], "[0:v]", "[0:a]", 0.0
    for p in parts:
        inputs += ["-i", p]
    for i in range(1, len(parts)):
        d = HARD_CUT if segments[i].get("cut") else crossfade
        offset += lengths[i - 1] - d
        chain.append(f"{last_v}[{i}:v]xfade=transition=fade:duration={d}:offset={offset:.3f}[v{i}]")
        chain.append(f"{last_a}[{i}:a]acrossfade=d={d}[a{i}]")
        last_v, last_a = f"[v{i}]", f"[a{i}]"
    output = os.path.join(library, cut["output"])
    music = cut.get("music")
    if music:
        # The songs over it all, each from "from" seconds into it, starting "at" a
        # segment (its number, from 1) or the start, fading in and out (a song whose
        # next one starts fades out over the next one's fade-in: a crossfade), with
        # the game's own sound turned down under them to "game" of its level.
        songs = music.get("songs") or [music]
        sync = music.get("sync")
        if sync:
            # (the first song's start picked so that "song" seconds into it play as the
            # first segment of that take starts: a moment in the music held to a shot)
            k = next(n for n, s in enumerate(segments) if s.get("take") == sync["take"])
            songs[0] = dict(songs[0], **{"from": max(0.0, sync["song"] - starts[k])})
            print(f"  music: {sync['take']} at {stamp(starts[k])}, {sync['song']} s into the song "
                  f"(the song starts {songs[0]['from']:.1f} s in)")
        names = []
        for k, song in enumerate(songs):
            path = song["file"] if os.path.isabs(song["file"]) else os.path.join(library, song["file"])
            n = len([a for a in inputs if a == "-i"])
            inputs += ["-ss", str(song.get("from", 0)), "-i", path]
            begin = starts[song["at"] - 1] if song.get("at") else 0.0
            nxt = songs[k + 1] if k + 1 < len(songs) else None
            fade_in = song.get("fadein", 1.5)
            if nxt:
                fade_out = nxt.get("fadein", 1.5)
                end = starts[nxt["at"] - 1] + fade_out
            else:
                fade_out, end = song.get("fadeout", 3), at
            chain.append(f"[{n}:a]volume={song.get('volume', 1)},afade=t=in:st=0:d={fade_in},"
                         f"afade=t=out:st={end - begin - fade_out:.3f}:d={fade_out},"
                         f"atrim=0:{end - begin:.3f},adelay={round(begin * 1000)}:all=1,apad,"
                         f"atrim=0:{at:.3f}[song{k}]")
            names.append(f"[song{k}]")
        game = "[0:a]" if not chain[:-len(songs)] else last_a
        rise = music.get("gamefadein")
        chain.append(f"{game}volume={music.get('game', 0.25)}"
                     + (f",afade=t=in:st=0:d={rise}" if rise else "") + "[bed]")
        chain.append(f"[bed]{''.join(names)}amix=inputs={len(names) + 1}:duration=first:normalize=0[mix]")
        last_a = "[mix]"
    if chain:
        maps = ["-filter_complex", ";".join(chain), "-map", last_v, "-map", last_a]
    else:
        maps = []
    subprocess.run(["ffmpeg", "-v", "error", "-y"] + inputs + maps + ENCODE + [output], check=True)
    for name in os.listdir(work):
        os.remove(os.path.join(work, name))
    os.rmdir(work)
    print(f"{output}: {stamp(at)}")


def stamp(value):
    return f"{int(value // 60)}:{value % 60:04.1f}"


if __name__ == "__main__":
    main(sys.argv[1:])
