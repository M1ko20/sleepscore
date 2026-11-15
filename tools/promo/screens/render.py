#!/usr/bin/env python3
"""Screenshoty do App Storu (iPhone 6,9" = 1320 × 2868) s titulkem nad obrazovkou.

  python3 tools/promo/screens/render.py <složka se surovými screenshoty> <výstup>

Surové PNG ze simulátoru (iPhone 16 Pro Max, status bar 9:41) – viz tools/promo/README.md.
Vykresluje headless Chrome (systémové písmo = SF Pro, zúžené jako v appce).
Barvy z docs/design.md; žlutá jen u „tvoje / vyhrál jsi“.
"""
import html
import os
import pathlib
import subprocess
import sys
import tempfile

SHOTS = [
    # (soubor, štítek, titulek – *slovo* = žlutě, podtitulek)
    ("feed.png", "Ráno", "Každé ráno\n*tvoje* noc.", "Spánek z hodinek se sám objeví jako karta. Kámoši ho uvidí."),
    ("duel_live.png", "Souboj", "Vyzvi kámoše\nna souboj.", "Sedm dní. Rozhoduje jen sleep score."),
    ("result.png", "Konec výzvy", "Prohraný\nplatí pivo.", "Sázku si napíšete sami. Vítěz bere *ovečku*."),
    ("profile.png", "Profil", "Bilance\njako v MMA.", "Výhry, prohry a stádo oveček poražených."),
    ("night.png", "Detail noci", "Celá noc\nv jednom grafu.", "Fáze, tep a z čeho je skóre."),
    ("challenges.png", "Výzvy", "Dluhy se\nneodpouštějí.", "Appka si pamatuje, kdo komu co dluží."),
]

W, H = 1320, 2868
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def rich(s):
    out, on = [], False
    for part in html.escape(s).split("*"):
        out.append(f'<span class="a">{part}</span>' if on else part)
        on = not on
    return "".join(out).replace("\n", "<br>")


def page(img, idx, label, title, sub):
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;width:{W}px;height:{H}px;overflow:hidden;background:#0B0D12;}}
.lab{{position:absolute;left:120px;top:190px;font:600 40px system-ui;letter-spacing:.16em;text-transform:uppercase;color:#9AA0AB}}
.lab b{{color:#F5C542;font-weight:600}}
h1{{position:absolute;left:112px;top:250px;margin:0;font:900 172px/0.9 system-ui;font-stretch:condensed;letter-spacing:-.01em;color:#F2F1EC}}
p{{position:absolute;left:120px;right:120px;top:590px;margin:0;font:500 50px/1.25 system-ui;color:#9AA0AB}}
.a{{color:#F5C542}}
.shot{{position:absolute;left:{(W - 1080) // 2}px;top:790px;width:1080px;border-radius:84px;outline:3px solid #262B36;display:block}}
</style></head><body>
<div class="lab"><b>{idx:02d}</b> / {len(SHOTS):02d} · {html.escape(label)}</div>
<h1>{rich(title)}</h1>
<p>{rich(sub)}</p>
<img class="shot" src="file://{img}">
</body></html>"""


def main():
    src, out = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for i, (f, label, title, sub) in enumerate(SHOTS, 1):
            h = pathlib.Path(tmp) / f"s{i}.html"
            h.write_text(page(src / f, i, label, title, sub))
            png = out / f"{i}-{f}"
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                            f"--window-size={W},{H}", f"--screenshot={png}", f"file://{h}"],
                           check=True, capture_output=True)
            print(png)


if __name__ == "__main__":
    main()
