"""Builds the mdpeek icon: SVGs (text outlined to paths), PNGs at every size, and AppIcon.icns.

icon.svg, with the tile drawn as a slab casting a shadow, is for showing the logo (the README,
the start page). The app icon keeps to the standard rounded square, without the slab's edge or
shadow, since macOS shrinks icons of any other shape into a box in the Dock and the switcher:
icon-app.svg, and icon-small.svg for 16 and 32 px."""
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image
from playwright.sync_api import sync_playwright

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)

INK, LIME, PAPER = "#23262B", "#C6F05A", "#FAFAF7"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


def text_path(text, cx, baseline, size):
    font = TTFont(FONT)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    names = [cmap[ord(c)] for c in text]
    width = sum(glyphs[n].width for n in names) * scale
    x = cx - width / 2
    pen = SVGPathPen(glyphs)
    for name in names:
        # Font units are y-up; flip into SVG's y-down space.
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x, baseline)))
        x += glyphs[name].width * scale
    return pen.getCommands()


PAGE = "M100 600H924V739A185 185 0 0 1 739 924H285A185 185 0 0 1 100 739Z"
TEXT_BARS = """<g fill="{ink}" fill-opacity="0.24">
<rect x="196" y="716" width="150" height="26" rx="13"/>
<rect x="196" y="770" width="110" height="26" rx="13"/>
<rect x="678" y="716" width="150" height="26" rx="13"/>
<rect x="718" y="770" width="110" height="26" rx="13"/>
</g>""".format(ink=INK)

# The tile as a slab: its thickness shows below it (ink, and paper below the page), with an
# ink face lit from above and a light rim along its top edge.
GRADIENTS = f"""<linearGradient id="face" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3B4048"/><stop offset="1" stop-color="#1C1F23"/></linearGradient>
<linearGradient id="paper" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E7E7DF"/></linearGradient>
<radialGradient id="iris" cx="0.5" cy="0.5" r="0.5" fx="0.4" fy="0.35"><stop offset="0" stop-color="#E4FF9A"/><stop offset="0.55" stop-color="{LIME}"/><stop offset="0.85" stop-color="#93B82C"/><stop offset="1" stop-color="#5F7A15"/></radialGradient>
<radialGradient id="pupil" cx="0.5" cy="0.5" r="0.5" fx="0.42" fy="0.38"><stop offset="0" stop-color="#3A3F47"/><stop offset="1" stop-color="#0B0C0E"/></radialGradient>
<linearGradient id="gloss" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.85"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>"""
FACE = '<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#face)"/>'
SLAB = """<rect x="100" y="136" width="824" height="824" rx="185" fill="#ADADA4"/>
<rect x="100" y="136" width="824" height="500" rx="185" fill="#111316"/>
""" + FACE

# The full icon: the tile (with the slab's edge and floor shadow if `slab`), and the iris as a
# glossy lens rising out of the eye and shadowing it.
def full(slab):
    floor = '<ellipse cx="512" cy="968" rx="360" ry="30" fill="#000000" opacity="0.22" filter="url(#floor)"/>'
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<defs>
{GRADIENTS}
<filter id="lift" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="22" stdDeviation="20" flood-color="#000000" flood-opacity="0.45"/></filter>
<filter id="floor" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="18"/></filter>
</defs>
{floor if slab else ""}
{SLAB if slab else FACE}
<path d="M196 456C330 240 694 240 828 456C694 672 330 672 196 456Z" fill="{PAPER}"/>
<ellipse cx="530" cy="486" rx="150" ry="120" fill="#000000" opacity="0.16"/>
<circle cx="512" cy="446" r="150" fill="url(#iris)" filter="url(#lift)"/>
<circle cx="512" cy="446" r="60" fill="url(#pupil)"/>
<ellipse cx="482" cy="366" rx="96" ry="52" fill="url(#gloss)"/>
<circle cx="574" cy="516" r="14" fill="#FFFFFF" opacity="0.6"/>
<path d="{PAGE}" fill="url(#paper)"/>
<path d="M100 600H924" stroke="{INK}" stroke-width="28"/>
<path d="M120 621H904" stroke="#000000" stroke-opacity="0.1" stroke-width="14"/>
<path d="{text_path("md", 512, 826, 230)}" fill="{INK}"/>
{TEXT_BARS}
<rect x="108" y="108" width="808" height="808" rx="178" fill="none" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="8"/>
</svg>
"""


FULL = full(slab=True)
APP = full(slab=False)

# 16 and 32 px: the same tile and lens, with bolder shapes and no blurred shadows, which only
# muddy at that size.
SMALL = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<defs>
{GRADIENTS}
</defs>
{FACE}
<path d="M180 440C320 200 704 200 844 440C704 680 320 680 180 440Z" fill="{PAPER}"/>
<circle cx="512" cy="440" r="160" fill="url(#iris)"/>
<circle cx="512" cy="440" r="66" fill="url(#pupil)"/>
<path d="{PAGE}" fill="url(#paper)"/>
<path d="M100 600H924" stroke="{INK}" stroke-width="40"/>
<rect x="196" y="716" width="170" height="60" rx="30" fill="{INK}" fill-opacity="0.3"/>
<rect x="398" y="676" width="228" height="140" rx="36" fill="{INK}"/>
<rect x="658" y="716" width="170" height="60" rx="30" fill="{INK}" fill-opacity="0.3"/>
</svg>
"""

(OUT / "icon.svg").write_text(FULL)
(OUT / "icon-app.svg").write_text(APP)
(OUT / "icon-small.svg").write_text(SMALL)

pngs = {}
with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        svg = SMALL if size <= 32 else APP
        page.set_viewport_size({"width": size, "height": size})
        page.set_content(
            f'<style>html,body{{margin:0;background:transparent}}svg{{display:block;width:{size}px;height:{size}px}}</style>{svg}')
        path = OUT / f"icon_{size}.png"
        page.screenshot(path=str(path), omit_background=True)
        pngs[size] = Image.open(path).convert("RGBA")
    browser.close()

# ICNS: Pillow uses each appended image at its own size.
pngs[1024].save(OUT / "AppIcon.icns", append_images=[pngs[s] for s in [16, 32, 64, 128, 256, 512]])
print("ok", sorted(pngs))
