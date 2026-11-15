# Promo video

Vertikální video 1080×1920 z reálné appky v simulátoru (přihlášený účet, produkční data). Nahrávka nic nemění.

1. Simulátor s přihlášeným účtem, čistý status bar:
   `xcrun simctl status_bar <sim> override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4`
2. Hlavní průchod: spustit `xcrun simctl io <sim> recordVideo --codec=h264 raw.mp4` a zároveň
   `xcodebuild … test-without-building -only-testing:SleepAppUITests/PromoTourTests > test.log`.
   Test vypisuje `PROMO_MARK <scéna> start|end <epoch>` → časy scén = značka − čas startu nahrávání.
3. Výsledek výzvy a nastavení notifikací zvlášť (pod XCUITestem se nevykreslí):
   `simctl launch <sim> cz.mikolas.bedrival -debugTab 1` → `result.mp4`,
   `… -debugNoResult -debugTab 2 -debugNotificationSettings` → `settings.mp4`.
4. `swift gfx.swift gfx/` (spouštět z `tools/promo/`) vykreslí titulky a úvodní/závěrečnou kartu s logem (SF Pro, barvy z docs/design.md, logo z `LaunchLogo@3x.png`).
5. `./build.sh` (ffmpeg) složí scény; časy střihu v něm upravit podle nové nahrávky.

`simctl recordVideo` ukládá snímky jen při změně obrazu (proměnná snímková frekvence), proto `fps=30` před `trim`.
Hotové video se do gitu nedává (repo je veřejné, velikost).

## App Store (2026-11-14)

Demo data: `supabase/tests/promo_seed.py` (postup v hlavičce). Simulátor iPhone 16 Pro Max, přihlásit hrdinu:
`simctl launch <sim> cz.mikolas.bedrival -debugLogin "<email>:<heslo>"` (údaje v `~/.bedrival/promo_state.json`).

**Screenshoty** (6,9" 1320×2868): surové PNG přes `simctl io <sim> screenshot` (`-debugNoResult -debugTab 0|1|2`, `-debugOpen 1`),
souboj a výhra jako snímek z nahrávky. Pak `python3 tools/promo/screens/render.py <složka> ~/Pictures/Bedrival/app-store-6.9-v2`.
Titulky a pořadí jsou v `SHOTS` v render.py.

**App preview** (886×1920, 15–30 s):
1. Záběry: pro každý test z `ios/SleepAppUITests/AppPreviewTests.swift` pustit `simctl io <sim> recordVideo` a
   `xcodebuild … test-without-building -only-testing:SleepAppUITests/AppPreviewTests/<test>`; obrazovku výsledku
   zvlášť (`simctl launch` bez `-debugNoResult`, pod XCUITestem se nevykreslí).
2. Převést na 30 fps do `tools/promo/preview/public/<test>.mp4` (`ffmpeg -i in.mp4 -vf fps=30 -c:v libx264 -crf 17 -an`).
3. `cd tools/promo/preview && npm install && python3 music.py && npx remotion render src/index.ts Preview out/raw.mp4`
   (časy záběrů a kamera jsou v `src/Preview.tsx`, takt = 60 snímků).
4. Finální kódování: `ffmpeg -i out/raw.mp4 -c:v libx264 -profile:v high -crf 16 -r 30 -af loudnorm=I=-14:TP=-1.5 -c:a aac -b:a 256k out.mp4`.

**Hlavička a výsledky hledání** (iOS 27+, 16:9 5244 × 2950): `python3 tools/promo/screens/header.py <složka se surovými screenshoty> ~/Pictures/Bedrival/header-5244x2950.png [cs|en]`.
Ořezy pro iPhone, hledání a iPad jsou změřené v hlavičce skriptu – titulek a hlavní karta musí zůstat v x 1450–3800, y 650–1600. V ASC zaškrtnout „Use header asset in search results“.
