# Devlog

Co je hotové a jak. Nejnovější nahoře. Detaily backendu v `backend.md`, vzhled v `design.md`.

## Další krok
**iOS appka (SwiftUI)** podle `design.md`. Navržené pořadí (nejdřív probrat s Adamem):
1. ~~Xcode projekt, design tokeny, Supabase SDK, testovací přihlášení~~ hotovo.
2. ~~Onboarding s pozvánkou → profil~~ hotovo (HealthKit tlačítko zatím jen pokračuje).
3. ~~Feed + karta noci + detail s hypnogramem~~ hotovo (bez fotek – přijdou se Storage).
4. ~~HealthKit~~ hotovo (ověřeno v simulátoru, na telefonu s Garminem zatím ne).
5. ~~Výzvy (seznam, detail, založení, výsledek)~~ hotovo. Zbývá: profil (bilance, série, vitrína duší, odznaky, vzájemná bilance), přátelé (hledání, žádosti), profil přítele + Vyzvat.

## 2026-11-06 – Výzvy v appce
- `ChallengeStore` (sdílený): moje výzvy jedním dotazem (`challenge_participants!inner` jako filtr `mine` + všichni účastníci s profily + denní skóre), otevřené dluhy, přátelé (`friendships` s hinty `profiles!friendships_user_a_fkey/_b_fkey`).
- Seznam: ČEKÁ NA TEBE (Přijmout/Odmítnout), BĚŽÍ (vč. mých čekajících), DLUHY (Splaceno – jen dlužník), HOTOVÉ. Žlutý odznak s počtem pozvánek na záložce (`badgeBackgroundColor` = accent).
- Detail: plakát (duel = 2 sloupce s průměry, FFA = pořadí, team_goal = pruh proti cíli), mřížka dní (vítěz dne zvýrazněný, chybějící uplynulá noc 0 šedě + „dá se dohrát“, budoucí den „·“), sázka, konec („končí pondělí 9. 11. ve 14:00“). Akce: přijmout/odmítnout, spustit skupinu (od 3 přijatých), zrušit, Odplata.
- Průběžný průměr počítá appka (uplynulý den bez noci = 0, dnešek jen když noc dorazila); po uzavření bere `final_avg`/`days_won` ze serveru. Den vyhrává jen jasně nejvyšší skóre (stejně jako server).
- Nová výzva (sheet, 4 kroky): typ → soupeři (jen přátelé; duel 1, skupina ≥ 2) → délka 7/14/30/vlastní (≥ 7) → sázka (+ cílový průměr 50–100 u společného cíle).
- Výsledek (fullScreenCover, jednou – viděné v UserDefaults, jen výzvy do týdne staré): VÝHRA s konfetami (jediné v appce, žlutá + bílá, 3 s) a duší letící do vitríny / PROHRA bez animace + Odplata / REMÍZA / společný cíl.
- Feed: karty výsledků výzev mezi kartami nocí (jedna suchá věta: „Jakub bere duši. Sázka: …“).
- Zaokrouhlení průměrů `.halfUp` (NumberFormatter má defaultně bankéřské: 87,25 → 87,2).
- `supabase/tests/seed_dev_challenges.sql` (`supabase db query --remote --yes -f …`): uzavřená (přes `private.finalize_challenge`), běžící a čekající výzva mezi @adam a @jakub.
- DEBUG launch argumenty: `-debugLogin email:heslo`, `-debugTab n`, `-debugNoResult`, `-debugOpenChallenge active|finished|pending`.
- **Chyba, opraveno:** první verze `-debugLogin` volala `start()` rekurzivně → ~330 pokusů o přihlášení za 2 min → Supabase Auth 429 (rate limit) na pár minut. Teď jednorázový příznak. Auth se na Free nepočítá po requestech, takže bez nákladů.
- Skupinové výzvy v UI netestované (potřeba 3. testovací účet – přijde s přáteli).

## 2026-11-06 – HealthKit
- `HealthSync` (`ios/SleepApp/Health/`): čte `sleepAnalysis` + `heartRate`, zahodí ruční záznamy (`HKMetadataKeyWasUserEntered`), `inBed` se neposílá. Mapování: asleepCore/Deep/REM/awake/asleepUnspecified → core/deep/rem/awake/asleep.
- **Šetření callů:** `HKAnchoredObjectQuery` (anchor v UserDefaults, posune se až po úspěšném nahrání) → když nepřibyl spánkový vzorek, nic se neposílá. Když ano: okno 3 dnů + tep jen v oknech spánku (sloučené úseky, mezera ≤ 60 min).
- Spouštění: `HKObserverQuery` + background delivery (hourly), při startu appky a při návratu do popředí; souběžný požadavek se zařadí a proběhne po dokončení. Ruční „Synchronizovat“ v Profilu (posílá i bez změn).
- Onboarding „Povolit“ → `requestAuthorization`. Odhlášení zastaví observer a smaže anchor.
- Entitlementy `healthkit` + `background-delivery` (z `project.yml`, soubor se generuje), texty `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription`. Zápis do Zdraví se žádá jen v DEBUG.
- DEBUG: Profil → „vložit noc do Zdraví“, nebo `simctl launch … -debugSeedHealth` (vloží noc končící dnes ráno a synchronizuje).
- Ověřeno v simulátoru: 25 vzorků → `ingest-sleep` → noc 2026-11-06 vytvořena, karta ve feedu; další start = „nic nového“, bez callu.
- Na telefonu: oprávnění ke Zdraví v simulátoru musí odklepnout člověk (simctl privacy Health neumí).

## 2026-11-06 – Feed, karta noci, detail
- `FeedStore` (sdílený feedem a detailem): jeden dotaz na `posts` s embedy (autor `profiles!posts_user_id_fkey` – bez hintu je vazba nejednoznačná kvůli `reactions`), noc, `night_tags`, `night_raw(segments)`, `user_achievements`, reakce, `comments(count)`. K tomu jednou katalog tagů a achievementů + `user_stats` autorů.
- Karta noci podle design.md: skóre (naběhne za 0,6 s), délka, usnutí, mini hypnogram, tagy textem, nový odznak, reakce (max. 3 + „+N“), počet komentářů. Moje dnešní nedoplněná karta nahoře se žlutým obrysem a „Doplň název a tagy“. Série jen na nejnovější kartě autora a od 3.
- Reakce: tlačítko nebo dlouhý stisk → lišta 5 ikon (zatím SF Symbols), moje = žlutá, opětovné klepnutí zruší; optimisticky, při chybě vrátí.
- Detail: autor + datum, skóre XL, délka/usnutí/vstávání, hypnogram s tepem (klouzavý průměr ±5 min, tah prstem = čas/fáze/tep), délky fází, rozpad skóre („bez dat“ šedě), tagy, odznaky, reakce, komentáře (přidat, smazat dlouhým stiskem – autor komentáře nebo karty).
- Úprava karty (sheet): název (80), komentář (1000), tagy jako chipy. Fotka zatím ne.
- Časy z Postgresu mají 6 desetinných míst → vlastní `parseTimestamp`.
- `supabase/tests/seed_dev.py email:heslo …` – 7 realistických nocí na účet přes `ingest-sleep` + názvy, tagy, reakce, komentáře.
- DEBUG: `xcrun simctl launch "iPhone 16" cz.mikolas.sleepscore -debugOpen 2` otevře 2. kartu (screenshoty bez klikání).
- Postřeh: vygenerované noci (7–8 h, 40 %+ deep+REM) mají skóre 92–99 – složky Délka a Fáze snadno dosáhnou 100. Probrat, jestli skóre nezpřísnit.

## 2026-11-06 – Onboarding a pozvánky
- Nepřihlášený: kód pozvánky („Sem se dostaneš jen přes kamaráda.“) → přihlášení; „Už mám účet“ jde rovnou na přihlášení. Kód se uloží (`Session.pendingInviteCode`, UserDefaults) a ověří až po přihlášení.
- Přihlášený bez profilu (`OnboardingFlow`): ověření kódu → přezdívka (kontrola dostupnosti s debounce 400 ms) + jméno → `redeem_invite` → obrazovka Apple Health → appka.
- Nové RPC (migrace `…160000_onboarding_checks.sql`): `check_invite(code)`, `username_available(username)` – jen `authenticated`, anon dostane 42501.
- Profil → Pozvánky: zbývající počet, Vytvořit kód (`create_invite`), nepoužité kódy se sdílením „Pojď se měřit ve spaní. Kód: …“.
- `Session.State.offline`: když se profil nenačte (síť), obrazovka „Bez připojení“ + Zkusit znovu – dřív by přihlášený skončil v onboardingu. Tvrdý timeout 15 s, `emitLocalSessionAsInitialSession` (obnova tokenu neblokuje start).
- **Pozor simulátor:** HTTP/3 (QUIC) v simulátoru na tomhle Macu nefunguje (VPN/utun) → URLSession `.ephemeral` (bez Alt-Svc cache → HTTP/2).
- `API.swift`: všechna volání nonisolated (odpovědi SDK nejsou Sendable), `serverMessage()` překládá chyby RPC do češtiny.
- Testovací účty: `adam@sleepscore.test` (profil @adam), `jakub@sleepscore.test` (bez profilu – na test onboardingu). Hesla nejsou v gitu.

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
