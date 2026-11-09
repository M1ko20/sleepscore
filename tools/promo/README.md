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
4. `swift gfx.swift gfx/` vykreslí titulky a úvodní/závěrečnou kartu (SF Pro, barvy z docs/design.md).
5. `./build.sh` (ffmpeg) složí scény; časy střihu v něm upravit podle nové nahrávky.

`simctl recordVideo` ukládá snímky jen při změně obrazu (proměnná snímková frekvence), proto `fps=30` před `trim`.
Hotové video se do gitu nedává (repo je veřejné, velikost).
