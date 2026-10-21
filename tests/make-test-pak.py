#!/usr/bin/env python3
"""make-test-pak.py - writes the test game the test scripts and CI run.

A tiny OpenBOR game made here, from nothing, so it may be shipped and run
anywhere: one player character (a block figure that stands, walks, jumps and
punches), a box to punch, one scrolling level, three fonts, and a few sounds.
Every picture is drawn by this script; every sound is a tone made by it.

Writes an OpenBOR .pak (the PAK32 layout of OpenBOR's packfile.c): "PACK",
format 0, the files one after another, then a table of
[record size][offset][size][name] entries and the table's offset.

Usage: make-test-pak.py [--legacy-pictures] <out.pak>

--legacy-pictures writes the same game with its pictures as GIF, PCX and BMP
files instead of PNG, the formats games made for older OpenBOR builds use
(chimera#342): the hero's frames GIF, the box's BMP, the level's background
PCX and its floor GIF, and the screens and fonts, which OpenBOR finds by name
without an extension, a mix of the three. It plays exactly as the PNG game.
"""
import math
import struct
import sys
import zlib

# ------------------------------------------------------------------ pictures

def png(width, height, rows, palette):
    """An 8-bit paletted PNG; index 0 is the transparent colour (OpenBOR's)."""
    def chunk(kind, data):
        c = struct.pack(">I", len(data)) + kind + data
        return c + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\0" + bytes(r) for r in rows)
    pal = b"".join(bytes(c) for c in palette) + b"\0\0\0" * (256 - len(palette))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0)) +
            chunk(b"PLTE", pal) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


class Canvas:
    def __init__(self, w, h, fill=0):
        self.w, self.h = w, h
        self.px = [[fill] * w for _ in range(h)]

    def rect(self, x, y, w, h, c):
        for yy in range(max(0, y), min(self.h, y + h)):
            for xx in range(max(0, x), min(self.w, x + w)):
                self.px[yy][xx] = c

    def rows(self):
        return self.px


# 0 transparent, then the figure's and the scenery's colours
PALETTE = [
    (0, 0, 0),       # 0 transparent
    (0, 0, 0),       # 1 black
    (255, 255, 255), # 2 white
    (220, 60, 50),   # 3 red
    (60, 110, 220),  # 4 blue
    (240, 200, 150), # 5 skin
    (90, 170, 80),   # 6 grass
    (120, 190, 240), # 7 sky
    (150, 100, 50),  # 8 wood
    (250, 220, 60),  # 9 yellow
    (110, 110, 120), # 10 grey
]


def figure(pose):
    """The hero, 40x64, feet at the bottom middle."""
    c = Canvas(40, 64)
    head_y = 4 if pose != "crouch" else 12
    c.rect(14, head_y, 12, 12, 5)            # head
    c.rect(17, head_y + 4, 2, 2, 1)          # eyes
    c.rect(22, head_y + 4, 2, 2, 1)
    c.rect(12, head_y + 12, 16, 22, 3)       # body
    legs = {"stand": [(13, 0), (21, 0)], "walk1": [(10, 0), (24, 0)], "walk2": [(15, 0), (19, 0)],
            "jump": [(12, -6), (22, -6)], "punch1": [(13, 0), (21, 0)], "punch2": [(11, 0), (23, 0)],
            "pain": [(13, 0), (21, 0)], "crouch": [(11, 0), (23, 0)]}[pose]
    for lx, dy in legs:
        c.rect(lx, 46 + dy, 6, 18 + min(dy, 0) * -0 - (0 if dy == 0 else 6), 4)
    if pose == "punch2":
        c.rect(28, head_y + 14, 12, 5, 5)    # arm out
    elif pose == "punch1":
        c.rect(26, head_y + 14, 6, 5, 5)
    else:
        c.rect(8, head_y + 14, 4, 14, 5)     # arms down
        c.rect(28, head_y + 14, 4, 14, 5)
    if pose == "pain":
        c.rect(14, head_y + 9, 12, 2, 1)
    return png(40, 64, c.rows(), PALETTE)


def box(hit=False):
    c = Canvas(36, 36)
    c.rect(0, 0, 36, 36, 1)
    c.rect(2, 2, 32, 32, 9 if hit else 8)
    c.rect(2, 16, 32, 4, 1)
    c.rect(16, 2, 4, 32, 1)
    return png(36, 36, c.rows(), PALETTE)


def background(width=320, height=240):
    """Sky, clouds and hills, behind the level."""
    c = Canvas(width, height, 7)
    for x in range(width):
        top = 120 + int(18 * math.sin(x / 47.0)) + int(8 * math.sin(x / 13.0))
        for y in range(top, 160):
            c.px[y][x] = 6
    for x in range(0, width, 160):
        c.rect(x + 40, 40, 30, 20, 2)
        c.rect(x + 50, 32, 40, 24, 2)
    return png(width, height, c.rows(), PALETTE)


def panel(width=320, height=240):
    """The floor the level is made of, one panel; the top is see-through.
    Posts every 64 pixels show it scrolling."""
    c = Canvas(width, height, 0)
    c.rect(0, 150, width, 90, 10)
    for x in range(0, width, 64):
        c.rect(x, 150, 4, 90, 1)
        c.rect(x + 20, 110, 6, 40, 8)
    return png(width, height, c.rows(), PALETTE)


def text(c, x, y, words, colour, scale=2):
    """Writes in the 5x7 font onto a canvas."""
    for i, ch in enumerate(words.upper()):
        bits = GLYPHS.get(ch)
        if not bits:
            continue
        for j, bit in enumerate(bits):
            if bit == "#":
                c.rect(x + (i * 6 + j % 5) * scale, y + (j // 5) * scale, scale, scale, colour)


def screen(title, colour, lines=()):
    """One of the menu screens' backgrounds: a frame, a title, a few lines."""
    c = Canvas(320, 240, 1)
    c.rect(8, 8, 304, 224, colour)
    c.rect(12, 12, 296, 216, 1)
    text(c, 160 - len(title) * 9, 40, title, 2, 3)
    for k, line in enumerate(lines):
        text(c, 160 - len(line) * 6, 100 + k * 24, line, 9)
    return png(320, 240, c.rows(), PALETTE)


def shadow():
    c = Canvas(32, 8)
    c.rect(4, 2, 24, 4, 1)
    return png(32, 8, c.rows(), PALETTE)


# A 5x7 font. OpenBOR's font picture is 16 by 16 cells of the 256 character
# codes; this draws the codes it knows into 8x10 cells, in one colour.
GLYPHS = {
    "A": ".###.#...##...#######...##...##...#", "B": "####.#...#####.#...##...##...#####.",
    "C": ".###.#...##....#....#....#...#.###.", "D": "####.#...##...##...##...##...#####.",
    "E": "######....####.#....#....#....#####", "F": "######....####.#....#....#....#....",
    "G": ".###.#...##....#.####...##...#.####", "H": "#...##...#######...##...##...##...#",
    "I": ".###...#....#....#....#....#...###.", "J": "..###...#....#....#....#.#..#..##..",
    "K": "#...##..#.###..#..#.#...##...##...#", "L": "#....#....#....#....#....#....#####",
    "M": "#...###.###.#.##...##...##...##...#", "N": "#...###..##.#.##..###...##...##...#",
    "O": ".###.#...##...##...##...##...#.###.", "P": "####.#...##...#####.#....#....#....",
    "Q": ".###.#...##...##...##.#.##..#..##.#", "R": "####.#...##...#####.#..#.#...##...#",
    "S": ".####.....#.....###.....#....#####.", "T": "#####..#....#....#....#....#....#..",
    "U": "#...##...##...##...##...##...#.###.", "V": "#...##...##...##...#.#.#..#.#...#..",
    "W": "#...##...##...##.#.##.#.###.###...#", "X": "#...#.#.#...#...#.#.#...##...##...#",
    "Y": "#...#.#.#...#....#....#....#....#..", "Z": "#####....#...#...#...#...#....#####",
    "0": ".###.#..###.#.###..##...##...#.###.", "1": "..#...##....#....#....#....#...###.",
    "2": ".###.#...#....#...#...#...#...#####", "3": "####.....#....#.###.....#....#####.",
    "4": "#...##...##...######....#....#....#", "5": "######....####.....#....#....#####.",
    "6": ".###.#....#....####.#...##...#.###.", "7": "#####....#...#...#...#....#....#...",
    "8": ".###.#...##...#.###.#...##...#.###.", "9": ".###.#...##...#.####....#....#.###.",
    ".": "..............................##...", ":": ".......##..##.......##..##.........",
    "-": "...............###.................", "!": "..#....#....#....#....#.........#..",
    "?": ".###.#...#...#...#....#.........#..", "/": "....#...#....#...#....#...#....#...",
    "(": "...#...#...#....#....#.....#.....#.", ")": ".#.....#.....#....#....#...#...#...",
    "'": "..#....#..........................." ,",": ".....................##....#...#...",
    "%": "##...##..#...#...#...#...#..##...##", "+": ".......#....#..#####..#....#.......",
    "=": "..........#####.....#####..........", "*": ".......#.#..###..#.#...............",
    "<": "...#...#...#...#.....#.....#.....#.", ">": ".#.....#.....#.....#...#...#...#...",
    "#": ".#.#..#.#.#####.#.#.#####.#.#..#.#.",
}


assert all(len(bits) == 35 for bits in GLYPHS.values())


def font(colour):
    c = Canvas(128, 160)
    # OpenBOR takes the palette of every character from the first cell's,
    # and an empty cell has none: the first cell has a dot
    c.px[0][0] = colour
    for ch, bits in GLYPHS.items():
        for code in {ord(ch), ord(ch.lower())}:
            cx, cy = (code % 16) * 8, (code // 16) * 10
            for i, b in enumerate(bits):
                if b == "#":
                    c.px[cy + 1 + i // 5][cx + 1 + i % 5] = colour
    return png(128, 160, c.rows(), PALETTE)


# ------------------------------------------------------------------- sounds

def tone(freq, ms, rate=22050, volume=0.35, slide=0.0):
    n = rate * ms // 1000
    out = bytearray()
    phase = 0.0
    for i in range(n):
        f = freq * (1.0 + slide * i / n)
        phase += f / rate
        v = volume if (phase % 1.0) < 0.5 else -volume
        env = 1.0 - i / n
        out += struct.pack("<h", int(v * env * 32767))
    data = bytes(out)
    return (b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " +
            struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16) + b"data" + struct.pack("<I", len(data)) + data)


# -------------------------------------------------------------------- texts

ANIM_STAND = "\tframe data/chars/hero/stand.png\n"

HERO = """name Hero
type player
health 100
speed 12
jumpheight 4
shadow 3
diesound data/sounds/fall.wav

anim idle
\tloop 1
\tdelay 30
\toffset 20 63
\tbbox 10 4 20 60
\tframe data/chars/hero/stand.png
\tframe data/chars/hero/crouch.png

anim walk
\tloop 1
\tdelay 10
\toffset 20 63
\tbbox 10 4 20 60
\tframe data/chars/hero/walk1.png
\tframe data/chars/hero/stand.png
\tframe data/chars/hero/walk2.png
\tframe data/chars/hero/stand.png

anim jump
\tdelay 10
\toffset 20 63
\tbbox 10 4 20 60
\tframe data/chars/hero/jump.png

anim land
\tdelay 6
\toffset 20 63
\tframe data/chars/hero/crouch.png

anim attack1
\tdelay 6
\toffset 20 63
\tbbox 10 4 20 60
\tframe data/chars/hero/punch1.png
\tsound data/sounds/punch.wav
\tattack 26 16 16 8 10 0 0 0
\tframe data/chars/hero/punch2.png
\tattack 0
\tframe data/chars/hero/punch1.png

anim pain
\tdelay 20
\toffset 20 63
\tframe data/chars/hero/pain.png

anim fall
\tdelay 40
\toffset 20 63
\tframe data/chars/hero/pain.png

anim rise
\tdelay 20
\toffset 20 63
\tframe data/chars/hero/crouch.png

anim death
\tdelay 60
\toffset 20 63
\tframe data/chars/hero/pain.png
"""

BOX = """name Box
type obstacle
health 30
shadow 0
nolife 1

anim idle
\tloop 0
\tdelay 100
\toffset 18 35
\tbbox 0 0 36 36
\tframe data/chars/box/box.png

anim pain
\tdelay 10
\toffset 18 35
\tbbox 0 0 36 36
\tframe data/chars/box/hit.png

anim fall
\tdelay 10
\toffset 18 35
\tframe data/chars/box/hit.png

anim death
\tdelay 30
\toffset 18 35
\tframe data/chars/box/hit.png
"""

MODELS = """load Hero data/chars/hero/hero.txt
load Box data/chars/box/box.txt
"""

LEVELS = """set Test
lives 3
z 160 230 150
file data/levels/field.txt
"""

LEVEL = """music none
background data/bgs/field.png
panel data/bgs/floor.png
order aaa
direction right

spawn Box
coords 200 200
at 0

spawn Box
coords 260 210
at 200

spawn Box
coords 280 190
at 500
"""


# The probe: OpenBOR runs data/scripts/update.c every pass of its loop. It
# writes to OpenBOR's log (the core's error output) what the game learns
# from the machine: every 60th pass the game's clock, the date and a random
# number, and every key a player newly presses.
PROBE = """void key(int p, int n, char name)
{
    if (playerkeys(p, 1, name))
    {
        log("probe n=" + n + " p" + (p + 1) + " " + name + "\\n");
    }
}

void main()
{
    void n = getglobalvar("probe_n");
    int p;
    if (n == NULL())
    {
        n = 0;
    }
    setglobalvar("probe_n", n + 1);
    if (n % 60 == 0)
    {
        log("probe n=" + n + " elapsed=" + openborvariant("elapsed_time") + " unix=" + datetime_gettimestamp() +
            " date=" + datetime_format("%Y-%m-%dT%H:%M:%S") + " rnd=" + rand() + "\\n");
    }
    for (p = 0; p < 4; p++)
    {
        key(p, n, "moveup");
        key(p, n, "movedown");
        key(p, n, "moveleft");
        key(p, n, "moveright");
        key(p, n, "attack");
        key(p, n, "attack2");
        key(p, n, "attack3");
        key(p, n, "attack4");
        key(p, n, "jump");
        key(p, n, "special");
        key(p, n, "start");
    }
}
"""


def files():
    yield "data/scripts/update.c", PROBE.encode()
    yield "data/models.txt", MODELS.encode()
    yield "data/levels.txt", LEVELS.encode()
    yield "data/levels/field.txt", LEVEL.encode()
    yield "data/chars/hero/hero.txt", HERO.encode()
    yield "data/chars/box/box.txt", BOX.encode()
    for pose in ("stand", "walk1", "walk2", "jump", "crouch", "punch1", "punch2", "pain"):
        yield "data/chars/hero/%s.png" % pose, figure(pose)
    yield "data/chars/box/box.png", box()
    yield "data/chars/box/hit.png", box(True)
    yield "data/bgs/field.png", background()
    yield "data/bgs/floor.png", panel()
    yield "data/bgs/logo.png", screen("CHIMERA", 4, ["OPENBOR TEST GAME"])
    yield "data/bgs/title.png", screen("TEST GAME", 3, ["PRESS START"])
    yield "data/bgs/titleb.png", screen("TEST GAME", 3)
    yield "data/bgs/select.png", screen("SELECT", 6)
    yield "data/bgs/loading.png", screen("LOADING", 10)
    yield "data/bgs/loading2.png", screen("LOADING", 10)
    yield "data/bgs/hiscore.png", screen("HIGH SCORES", 9)
    yield "data/bgs/complete.png", screen("STAGE CLEAR", 6)
    yield "data/bgs/unlockbg.png", screen("UNLOCKED", 9)
    for i in range(1, 7):
        yield "data/sprites/shadow%d.png" % i, shadow()
    yield "data/sprites/font.png", font(2)
    yield "data/sprites/font2.png", font(9)
    yield "data/sprites/font3.png", font(3)
    yield "data/sounds/beep.wav", tone(880, 60)
    yield "data/sounds/beep2.wav", tone(660, 80)
    yield "data/sounds/punch.wav", tone(220, 90, slide=-0.5)
    yield "data/sounds/fall.wav", tone(330, 250, slide=-0.6)
    yield "data/sounds/go.wav", tone(523, 200, slide=0.5)


def pak(entries):
    out = bytearray(b"PACK" + struct.pack("<I", 0))
    table = bytearray()
    for name, data in entries:
        offset = len(out)
        out += data
        raw = name.encode() + b"\0"
        table += struct.pack("<III", 12 + len(raw), offset, len(data)) + raw
    table_offset = len(out)
    out += table + struct.pack("<I", table_offset)
    return bytes(out)


# ------------------------------------------------- older picture formats

def unpng(data):
    """(width, height, rows, palette) of a PNG png() wrote: one IDAT, filter 0"""
    at, width, height, palette, idat = 8, 0, 0, [], b""
    while at < len(data):
        size, kind = struct.unpack(">I4s", data[at:at + 8])
        body = data[at + 8:at + 8 + size]
        if kind == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
        elif kind == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif kind == b"IDAT":
            idat += body
        at += 12 + size
    raw = zlib.decompress(idat)
    rows = [list(raw[y * (width + 1) + 1:(y + 1) * (width + 1)]) for y in range(height)]
    return width, height, rows, palette


def gif(width, height, rows, palette):
    """A GIF of 8-bit codes: a clear code every 250 pixels keeps every code
    9 bits long, so no compression is needed, only the bit packing"""
    pal = b"".join(bytes(c) for c in palette) + b"\0\0\0" * (256 - len(palette))
    codes = []
    pixels = [c for r in rows for c in r]
    for i, c in enumerate(pixels):
        if i % 250 == 0:
            codes.append(256)
        codes.append(c)
    codes.append(257)
    bits, nbits, packed = 0, 0, bytearray()
    for c in codes:
        bits |= c << nbits
        nbits += 9
        while nbits >= 8:
            packed.append(bits & 0xFF)
            bits >>= 8
            nbits -= 8
    if nbits:
        packed.append(bits & 0xFF)
    blocks = b"".join(bytes([len(packed[i:i + 255])]) + bytes(packed[i:i + 255]) for i in range(0, len(packed), 255))
    return (b"GIF89a" + struct.pack("<HHBBB", width, height, 0xF7, 0, 0) + pal +
            b"," + struct.pack("<HHHHB", 0, 0, width, height, 0) + bytes([8]) + blocks + b"\0;")


def pcx(width, height, rows, palette):
    """A PCX that OpenBOR reads as width by height: it takes xmax and ymax as
    the size, one less each way than the file holds, so the file holds a
    column and a row more (index 0)"""
    stride = width + 1
    header = struct.pack("<BBBBHHHHHH", 10, 5, 1, 8, 0, 0, width, height, 72, 72)
    header += b"\0" * 48 + b"\0" + bytes([1]) + struct.pack("<HH", stride, 1) + b"\0" * 58
    body = bytearray()
    for y in range(height + 1):
        line = (rows[y] if y < height else [0] * width) + [0]
        x = 0
        while x < len(line):
            run = 1
            while x + run < len(line) and line[x + run] == line[x] and run < 63:
                run += 1
            if run > 1 or line[x] >= 0xC0:
                body += bytes([0xC0 | run, line[x]])
            else:
                body.append(line[x])
            x += run
    pal = b"".join(bytes(c) for c in palette) + b"\0\0\0" * (256 - len(palette))
    return header + bytes(body) + b"\x0c" + pal


def bmp(width, height, rows, palette):
    """An 8-bit BMP, rows bottom up and padded to four bytes"""
    stride = (width + 3) & ~3
    pal = b"".join(bytes((c[2], c[1], c[0], 0)) for c in palette) + b"\0" * 4 * (256 - len(palette))
    pixels = b"".join(bytes(rows[y]) + b"\0" * (stride - width) for y in range(height - 1, -1, -1))
    start = 14 + 40 + 1024
    return (b"BM" + struct.pack("<IIi", start + len(pixels), 0, start) +
            struct.pack("<iiiHHiiiiii", 40, width, height, 1, 8, 0, len(pixels), 2835, 2835, 256, 0) + pal + pixels)


# where each picture goes in the older formats, the first name that starts it
# deciding (so a longer name comes before a shorter one it starts with); a
# name not here stays PNG
LEGACY = {
    "data/chars/hero/": gif,
    "data/chars/box/": bmp,
    "data/bgs/field": pcx,
    "data/bgs/floor": gif,
    "data/bgs/logo": gif,
    "data/bgs/titleb": bmp,
    "data/bgs/title": pcx,
    "data/bgs/select": gif,
    "data/bgs/loading2": pcx,
    "data/bgs/loading": gif,
    "data/bgs/hiscore": bmp,
    "data/bgs/complete": gif,
    "data/bgs/unlockbg": pcx,
    "data/sprites/shadow": gif,
    "data/sprites/font": pcx,
}


def legacy(entries):
    """The game's files with its pictures in the older formats, and the text
    files naming them by their new names"""
    renamed, out = {}, []
    for name, data in entries:
        if name.endswith(".png"):
            stem = name[:-4]
            make = next((f for prefix, f in LEGACY.items() if stem.startswith(prefix)), None)
            if make is not None:
                new = stem + "." + make.__name__
                renamed[name] = new
                out.append((new, make(*unpng(data))))
                continue
        out.append((name, data))
    final = []
    for name, data in out:
        if name.endswith(".txt"):
            text = data.decode()
            for old, new in renamed.items():
                text = text.replace(old, new)
            data = text.encode()
        final.append((name, data))
    return final


def main():
    args = sys.argv[1:]
    old = "--legacy-pictures" in args
    args = [a for a in args if a != "--legacy-pictures"]
    if len(args) != 1:
        sys.exit(__doc__)
    entries = list(files())
    with open(args[0], "wb") as f:
        f.write(pak(legacy(entries) if old else entries))


if __name__ == "__main__":
    main()
