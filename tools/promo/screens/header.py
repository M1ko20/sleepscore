#!/usr/bin/env python3
"""Hlavička produktové stránky (iOS 27+): univerzální 16:9 PNG 5244 × 2950 (header + výsledky hledání).

  python3 tools/promo/screens/header.py <složka se surovými screenshoty> <výstup.png> [cs|en]

Ořezy změřené v náhledu App Store Connect (kalibrační mřížka, 15. 11. 2026):
  iPhone produkt  x 1150–4060, y 0–1830 (v rozích y 380–760 tlačítka zpět/sdílet)
  hledání (3:2)   x 1450–3800, y 390–1940
  iPad na šířku   x 0–5244,    y 420–1620 (uprostřed nahoře lišta záložek)
  iPad na výšku   x 500–4700,  y 450–1830
→ titulek a hlavní karta drží x 1450–3800, y 650–1600. Bez sázek/alkoholu (asset musí být 4+).
"""
import pathlib, subprocess, sys, tempfile

W, H = 5244, 2950
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
K = 0.68  # zmenšení výřezů ze screenshotu 1320 × 2868
CY = 1430  # svislý střed řady výřezů
GAP = 70
# (soubor, x0, y0, x1, y1 v surovém screenshotu, rámeček)
CROPS = [
    ("profile.png", 0, 560, 1320, 1100, True),     # 8-2-0, série
    ("duel_live.png", 0, 410, 1320, 1260, True),   # 90,3 : 69,8 (bez řádku se sázkou)
    ("feed.png", 40, 448, 1280, 1499, False),      # ranní karta 89 (vlastní žlutý rámeček)
    ("result.png", 0, 820, 1320, 1940, True),      # VÝHRA
    ("night.png", 0, 1250, 1320, 1730, True),      # hypnogram
]


TEXT = {
    "cs": ("Spíš líp než kámoši?", 'Každé ráno <span class="a">tvoje</span> noc. Pak týdenní souboj.'),
    "en": ("Out-sleep your friends.", '<span class="a">Your</span> night, every morning. Then a duel.'),
}


def main():
    title, sub = TEXT[sys.argv[3] if len(sys.argv) > 3 else "cs"]
    src, out = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).expanduser().resolve()
    widths = [(x1 - x0) * K for _, x0, _, x1, _, _ in CROPS]
    mid = len(CROPS) // 2
    left = W / 2 - widths[mid] / 2 - sum(widths[:mid]) - GAP * mid
    panels, x = [], left
    for (f, x0, y0, x1, y1, frame), w in zip(CROPS, widths):
        h = (y1 - y0) * K
        style = (f"left:{x:.0f}px;top:{CY - h / 2:.0f}px;width:{w:.0f}px;height:{h:.0f}px;"
                 f"background:url('file://{src / f}') {-x0 * K:.0f}px {-y0 * K:.0f}px / {1320 * K:.0f}px auto no-repeat")
        panels.append(f'<div class="p{" f" if frame else ""}" style="{style}"></div>')
        x += w + GAP
    html = f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;width:{W}px;height:{H}px;overflow:hidden;background:#0B0D12}}
h1{{position:absolute;left:0;right:0;top:640px;margin:0;text-align:center;font:900 210px/1 system-ui;
   font-stretch:condensed;letter-spacing:-.01em;color:#F2F1EC}}
p{{position:absolute;left:0;right:0;top:880px;margin:0;text-align:center;font:500 84px/1.2 system-ui;color:#9AA0AB}}
.a{{color:#F5C542}}
.p{{position:absolute;border-radius:40px}}
.f{{outline:4px solid #262B36;outline-offset:0}}
</style></head><body>
<h1>{title}</h1>
<p>{sub}</p>
{''.join(panels)}
</body></html>"""
    with tempfile.TemporaryDirectory() as tmp:
        h = pathlib.Path(tmp) / "h.html"; h.write_text(html)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                        f"--window-size={W},{H}", f"--screenshot={out}", f"file://{h}"], check=True, capture_output=True)
    # bez alfa kanálu
    jpg = str(out) + ".jpg"
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "100", str(out), "--out", jpg], check=True, capture_output=True)
    subprocess.run(["sips", "-s", "format", "png", jpg, "--out", str(out)], check=True, capture_output=True)
    pathlib.Path(jpg).unlink()
    print(out)


if __name__ == "__main__":
    main()
