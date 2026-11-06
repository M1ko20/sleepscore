# Devlog

Co je hotové a jak. Nejnovější nahoře. Detaily backendu v `backend.md`, vzhled v `design.md`.

## Další krok
**iOS appka (SwiftUI)** podle `design.md`. Navržené pořadí (nejdřív probrat s Adamem):
1. ~~Xcode projekt, design tokeny, Supabase SDK, testovací přihlášení~~ hotovo.
2. Onboarding s pozvánkou → profil.
3. Feed + karta noci + detail s hypnogramem (zatím data z testovacího uživatele).
4. HealthKit: čtení spánku a tepu, `HKObserverQuery`, odeslání na `ingest-sleep`.
5. Výzvy (seznam, detail, založení, výsledek), profil, přátelé, pozvánky.

## 2026-11-06 – iOS kostra
- `ios/`: projekt přes **XcodeGen** (`ios/project.yml`, `.xcodeproj` není v gitu → `cd ios && xcodegen generate`). iOS 17+, bundle `cz.mikolas.sleepscore`, jen iPhone na výšku, vynucený tmavý režim.
- Klíče: `ios/Config/Secrets.xcconfig` (v .gitignore, vzor `Secrets.example.xcconfig`) → Info.plist → `Backend.client`. V appce jen publishable klíč.
- Design tokeny `Color.app.*`, `Font.app.*`, `Metrics`, `.statLabel()`, `.cardStyle()`, styly tlačítek `.primary/.secondary/.plainText`, `AppTextFieldStyle`.
- `Session` (@Observable): stav `loading / signedOut / needsProfile / ready(Profile)`, poslouchá `authStateChanges`.
- Testovací přihlášení e-mail + heslo. Registrace z appky není: hostovaný projekt vyžaduje potvrzení e-mailu (a Free SMTP posílá 2 maily/h) → testovací účty se zakládají přes admin API (`email_confirm: true`) + ruční insert do `profiles` a `user_stats`.
- Testovací účet Adama: `adam@sleepscore.test`, profil `@adam`, heslo ti řeknu osobně (v gitu není).
- 3 záložky (Feed / Výzvy / Profil) zatím s prázdnými stavy. Build: `xcodebuild -project ios/SleepApp.xcodeproj -scheme SleepApp -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath ios/build build`.

## 2026-11-06 – Design
- `docs/design.md`: noční sportovní směr, jen tmavý režim, jedna akcentní barva (žlutá `#F5C542`), SF Pro condensed pro čísla, vlastní ikony místo emoji, 3 záložky (Feed / Výzvy / Profil), drátěné modely 11 obrazovek, tón textů, anti-slop pravidla.
- Rozhodnuto s Adamem přes otázky: směr, tmavý režim, vlastní ikony, inspirace Whoop/Oura, Strava, BeReal/Locket. Adam: „žádný emoji spam“.

## 2026-11-06 – Série, achievementy, uzavírání výzev
- Všechno v Postgresu (`…140000_streaks_achievements_challenges.sql`) + pg_cron (`…140100_cron.sql`), žádná nová Edge Function – kvůli Free tieru.
- `ingest-sleep` po uložení noci volá `after_night_ingest` → achievementy za noc + přepočet série, vrací `streak` a `new_achievements`.
- Trigger na `night_tags` uděluje tagové achievementy hned.
- Rozhodnutá pravidla: shoda nahoře = remíza bez dluhů/duší; den vyhrává jen jasně nejvyšší skóre; +1 pozvánka za výhru (ne team_goal) a za sérii 30/100; freeze automaticky 1× týdně; opakované achievementy (Sběratel /10, Neporazitelný /5, Švýcarské hodinky /14 dní); uzavření výzvy poslední den ve 14:00 tz zakladatele.
- Ověřeno: lokální SQL scénáře (série s freeze, duel, FFA shoda, team goal, tagy, idempotence) + E2E 25/25 na živém projektu.

## 2026-11-06 – Strop skóre podle délky
- < 5 h max 50, < 6 h max 70 (4h noc dřív dostala 56). Unit test přidán.

## 2026-11-06 – Ingest a sleep score
- Edge Function `ingest-sleep` + čistá logika `_shared/sleep.ts` (výběr hlavního spánku, metriky, skóre v1), 13 unit testů (Deno).
- Nasazení bez Dockeru: `--use-api`.
- E2E test `supabase/tests/e2e.py`: založí 2 uživatele přes admin API, projde pozvánku, souboj, ingest, RLS, komentáře, reakce, zpětné nahrání; na konci smaže. Klíče jen dočasně v souboru mimo repo.

## 2026-11-06 – Databáze
- Schéma, RLS, RPC funkce, storage buckety, číselníky tagů a achievementů. Nasazeno přes Supabase CLI.
- Security Advisor: RLS helpery přesunuty do schématu `private` (dřív šlo přes API zjistit přátelství cizích lidí), opraven `search_path`. Zbylá varování = záměrné RPC funkce.
- Testováno lokálně na Postgresu 16 se stuby Supabase (auth/storage) – Docker není k dispozici.
- Rozhodnutí: pozvaný je automaticky přítel zvoucího; žádost o přátelství může poslat kdokoliv; jedna reakce na kartu; pevné tagy; achievementy opakovatelné; karta se zveřejní automaticky; FFA = vítěz bere vše; společný cíl se počítá do MMA, ale bez duší a bez vzájemné bilance.
