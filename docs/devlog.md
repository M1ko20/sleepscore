# Devlog

Co je hotové a jak. Nejnovější nahoře. Detaily backendu v `backend.md`, vzhled v `design.md`.

## Další krok
**iOS appka (SwiftUI)** podle `design.md`. Navržené pořadí (nejdřív probrat s Adamem):
1. ~~Xcode projekt, design tokeny, Supabase SDK, testovací přihlášení~~ hotovo.
2. ~~Onboarding s pozvánkou → profil~~ hotovo (HealthKit tlačítko zatím jen pokračuje).
3. ~~Feed + karta noci + detail s hypnogramem~~ hotovo (bez fotek – přijdou se Storage).
4. ~~HealthKit~~ hotovo (ověřeno v simulátoru, na telefonu s Garminem zatím ne).
5. ~~Výzvy (seznam, detail, založení, výsledek)~~ hotovo.
6. ~~Profil, přátelé, profil přítele + Vyzvat~~ hotovo. ~~Skupinové výzvy~~ otestované se 3. účtem.
7. ~~Fotky a profilovky~~ hotovo.
8. ~~Insighty z tagů a týdenní recap~~ hotovo.
9. ~~Zpřísnění skóre (v2)~~ hotovo.
10. ~~Sleep Wrapped~~ hotovo.
11. ~~GDPR (export, smazání účtu, Soukromí)~~ hotovo.
12. ~~Notifikace ve zvonečku~~ hotovo (#9). Další: push přes APNs (#10, Developer Program), nastavení notifikací (#11), privacy policy + landing page (Adam), test na iPhonu s Garminem. (konec roku), smazání účtu (GDPR), push notifikace (až s Developer Programem – pak i pondělní push na recap).

## 2026-11-07 – Notifikace: zvoneček (issue #9)
- Migrace `…20261107010500_notifications.sql`: tabulka `notifications`, vznik jen v DB (triggery + pg_cron), text skládá SQL funkce `notification_text` (stejná pro zvoneček i budoucí push). Detail v `backend.md` → Notifikace.
- Události: reakce (1 řádek na kartu, slučuje se), komentář, žádost / přijetí přátelství (i „je tu přes tvoji pozvánku“), pozvánka do výzvy, odpověď zakladateli, start, „zítra konec“ (20:00 místního času), výsledek, splacený dluh, odznak (opakovaný = „Zase.“), ranní karta, pondělní recap (9:00). Vynecháno: „kamarád tě předběhl“ (ke zvážení v issue).
- Appka: zvoneček vpravo nahoře ve feedu s počtem nepřečtených (počet se načte jedním `HEAD` dotazem s feedem, žádný polling). Výpis „Upozornění“: avatar nebo glyf, text, čas, žlutá tečka u nových; otevření = `mark_notifications_read()` (1 call). Proklik: karta (i starší, než je ve feedu – dotáhne se), výzva, profil, recap.
- Lokální SQL testy jsou nově v repu: `supabase/tests/local/run.sh` (stub Supabase + pg_cron, všechny migrace) a `notifications_test.sql` (62 kontrol). Starý test sérií/výzev s triggery prošel beze změny výsledků.
- **Nenasazeno** – Adam: `supabase db push --remote --yes`. Do nasazení appka funguje dál, jen zvoneček ukáže „Upozornění se nenačetla.“
- DEBUG: `-debugNotifications` otevře výpis.

## 2026-11-06 – GDPR: export a smazání účtu
- Migrace `…210000_gdpr.sql`: `challenges.timezone` (doplní trigger ze zakladatele; start a uzavírání ve 14:00 už nečtou profil zakladatele), `creator_id` nullable + `on delete set null` (dřív by smazání zakladatele smazalo výzvu i ostatním hráčům, včetně jejich výher a duší). RPC `delete_my_account()` a `export_my_data()`, detaily v `backend.md` → GDPR.
- Appka: Nastavení → Soukromí a moje data (co ukládáme, jak vypnout Zdraví, Stáhnout moje data → JSON soubor ke sdílení, Smazat účet s potvrzením přezdívkou → smaže soubory ve Storage, pak účet, odhlásí). Odhlášení teď maže cache obrázků a lokální klíče.
- Ověřeno: export 200 (92 kB), smazání v rollback transakci (viz backend.md). Klikací tok smazání v UI netestován – smazal by testovací účet; Storage mazání jde přes SDK `list` + `remove`.
- DEBUG: `-debugPrivacy`.

## 2026-11-06 – Sleep Wrapped
- RPC `sleep_wrapped(year?)` (migrace `…200000`, security invoker, 1 call při otevření): noci, hodiny spánku a deepu, průměrné skóre, nejlepší noc, nejlepší měsíc (min. 5 nocí), průměrný čas usnutí, nejdelší série, top 3 tagy, bilance a počet výzev (podle `end_date`), duše, oblíbená oběť a nemesis, odznaky + nejčastější, reakce od kamarádů + nejčastější, komentáře. Bez parametru: v lednu uplynulý rok, jinak letošní.
- Appka: stories na celou obrazovku (proužky nahoře, swipe nebo klepnutí = další), slide = popisek + velké číslo + suchá věta, slidy bez dat se vynechají. Poslední slide shrnutí + Sdílet (obrázek přes ImageRenderer).
- Nabízí se jen v prosinci (letošní) a lednu (uplynulý): karta nahoře ve feedu + řádek v profilu. Mimo okno žádný call.
- DEBUG: `-debugWrapped` (okno kdykoliv), `-debugWrappedOpen`, `-debugWrappedPage n`.

## 2026-11-06 – Sleep score v2 (přísnější)
- Adam: „zpřísni skóre“. v1 dávalo běžným nocím 92–99. v2 (vzorec v `backend.md`): 100 jen za 8–9 h, deep a REM zvlášť proti běžným hodnotám dospělého, přísnější probuzení a pravidelnost, „normál“ (bez historie, běžný tep) = 85 místo 100, strop < 5 h 45 / < 6 h 65.
- Dev data přepočítaná znovunahráním (`seed_dev.py --ingest-only` + `--history`): průměr 84,9, rozptyl 55–95 (dřív 92,7 a 64–99). Seed generuje nadprůměrné fáze (složka fází ~98), reálná data z Garminu vyjdou níž.
- Testy 15/15 (nové: fáze v2, tep v2). `ingest-sleep` nasazen.
- Seed výzev opraven: maže i odznaky za smazané testovací výzvy (jinak unikátní klíč při znovuudělení). Uzavřené testovací výzvy teď: Jakub 71,0 : Adam 66,3; FFA Karolína 71,6.

## 2026-11-06 – Zjištění z tagů a týdenní recap
- Migrace `…190000_insights_recap.sql`, vše **security invoker + na požádání** (žádný cron ani Edge Function):
  - `tag_insights(user)`: pro každý tag noci s tagem vs. bez něj za 90 dní (min. 3 + 3) – průměr skóre, podíl deep (jen noci s fázemi), čas usnutí (minuty od poledne, ať průměr funguje přes půlnoc – `minutes_since_noon`), délka spánku.
  - `profile_summary` vrací `insights` + `nights_90` jen na vlastním profilu → bez callu navíc.
  - `weekly_recap(week_start?)`: bez parametru minulý týden po–ne (tz uživatele) – počet nocí, průměr a průměr týdne předtím, nejlepší/nejhorší noc, průměrná délka, série, nové odznaky.
- Věty skládá appka (`InsightCopy`): nejvýš 2 nejsilnější rozdíly nad prahem (deep ±10 %, usínání ±15 min, délka ±20 min, skóre ±3 body) → „S alkoholem usínáš o 32 min později a máš o 17 % méně deep.“ Zjištění se ukážou od 14 nocí za 90 dní, max. 4, sekce ZJIŠTĚNÍ na mém profilu.
- Recap: karta „Tvůj týden“ nahoře ve feedu jen po–st (jinak se nevolá vůbec), křížkem skrýt do dalšího týdne (UserDefaults). Obrazovka: průměr (+/− proti minulému), nocí x/7, průměrná délka, série, nejlepší/nejhorší noc, nové odznaky, výzvy toho týdne (z ChallengeStore, bez callu). Sdílet = obrázek přes ImageRenderer (ShareLink). Z profilu kdykoliv „Minulý týden v číslech“.
- `Calendar.iso.firstWeekday = 2` (týden od pondělí – dřív by recap začínal nedělí).
- Dev data: `seed_dev.py --history 42` (noci 8–42 dní zpět s tagy, které spánek opravdu zhorší) + `seed_dev_history.sql` (posune `created_at` starých karet, ať nejsou ve feedu nahoře). Pozn.: odznaky z historie mají `earned_at` = dnešek → recap tohoto týdne ukazuje +34.
- DEBUG: `-debugRecap` (karta kdykoliv, za tento týden), `-debugRecapOpen`.
- Neověřeno: tlačítko Sdílet (neumím klepat) – obrázek se renderuje, ale náhled jsem neviděl.
- Pozorování pro Adama: nahrané noci po přidání (backfill) dostanou kartu s `created_at` = teď → ve feedu se objeví nahoře. U reálných uživatelů to nastane jen při první synchronizaci (3 dny) – zatím nechávám.

## 2026-11-06 – Fotky a profilovky
- Zmenšení na telefonu (`ImageResize`): profilovka 256×256 výřez ze středu, JPEG ≤ 60 kB; fotka karty max. 1280 px, kvalita se snižuje do ≤ 200 kB. Server (bucket limity z `…180000`) pustí max. 150 / 400 kB a jen JPEG.
- Cesta `<user_id>/<uuid>.jpg` – nový soubor = nové jméno → `ImageStore` (actor) cachuje v paměti i na disku (Caches) navždy podle cesty, stahuje přes autorizovaný download (1 request na obrázek za celou dobu života, souběžné požadavky na stejný obrázek se spojí). Nahraná vlastní fotka jde rovnou do cache.
- Výměna/odebrání: starý soubor se smaže ze Storage; když selže zápis cesty do DB, nově nahraný se smaže (žádní sirotci).
- UI: Nastavení → Přidat/Změnit fotku + Odebrat (PhotosPicker, nepotřebuje oprávnění k fotkám). Úprava karty → Fotka (náhled 4:5, Změnit, Odebrat). Karta ve feedu: fotka nad čísly 4:5, rádius 10; detail: fotka pod tagy. `Avatar(profile:)` všude ukazuje profilovku, iniciála jako zástupce.
- **Opravena chyba:** syntetické `Encodable` vynechává `nil` → smazaný název/komentář karty se na serveru nikdy nevymazal. Nový `NullableRow` posílá explicitní `null`.
- Ověřeno přes API: upload 200, 6,8MB soubor 400, PNG 400, cizí složka 400, cizí `avatar_path` 400 (check), přítel čte fotku 200, anon 400. Screenshot feedu s fotkou a profilovkou (testovací data u @adam a @jakub). Výběr fotky v UI neověřen (neumím klepat).

## 2026-11-06 – 3. testovací účet a skupinové výzvy
- `karolina@sleepscore.test` (@karolina „Karolína Dvořáková“) – auth účet založil Adam v dashboardu (registrace přes API odmítá `.test`), profil přes Adamovu pozvánku (`redeem_invite`) → automaticky přítel Adama; přátelství s Jakubem přes žádost. 7 nocí ze `seed_dev.py`.
- Skutečný tok přes RPC: Adam založí FFA s Jakubem a Karolínou → `start_challenge` s 1 přijatým selže („need at least 3 accepted“) → oba přijmou → start → active od zítřka.
- `seed_dev_challenges.sql` rozšířen: uzavřená FFA (Karolína vyhrála průměrem 79,1, i když nevyhrála jediný den → dluhy Adama a Jakuba vůči ní), běžící FFA, běžící společný cíl 85.
- Opraveno: texty bez rodu („Jakub Novotny: souboj, 14 dní, večeře.“, „čeká“/„odmítnuto“), u společného cíle se nezvýrazňuje vítěz dne. `-debugOpenChallenge` bere i typ (`free_for_all`, `team_goal`).
- Supabase: bucket limity (avatars 150 kB, night-photos 400 kB, jen JPEG) a check, že `avatar_path`/`photo_path` vede do vlastní složky (migrace `…180000_photo_limits.sql`) – příprava na fotky.

## 2026-11-06 – Profil a přátelé
- RPC `profile_summary(user)` (migrace `…170000_profile_summary.sql`, **security invoker** → vše přes RLS): profil, MMA bilance, série, průměr 30 dní (skóre + délka), duše seskupené podle poraženého, počty odznaků, vzájemná bilance s volajícím, stav přátelství. Celý profil = 1 call místo 6. U ne-přítele RLS vrátí `streak`/`avg30` null a appka ukáže jen hlavičku + žádost.
- Můj profil: bilance `0-1-0` (scoreXL), SÉRIE + nejlepší, PRŮMĚR 30 DNÍ, vitrína duší (4 sloupce, desaturovaný avatar, datum, `×N`), odznaky (22 šestiúhelníků, získané žlutě s `×N` první, klepnutí = název + podmínka), Přátelé (n) s odznakem žádostí, Pozvánky. Nastavení pod ⚙: jméno, Apple Health, Odhlásit.
- Profil přítele (z Přátel, hledání i z detailu noci – klepnutí na autora): karta „Ty vs Jakub 0-1 · Jakub vede.“, Vyzvat (→ nová výzva s předvyplněným soupeřem, titulek „Výzva: …“), statistiky, menu Odebrat z přátel. Ne-přítel: Přidat do přátel / Stáhnout žádost / Přijmout + Odmítnout.
- Přátelé: hledání podle začátku přezdívky (debounce 350 ms, min. 2 znaky), Žádosti, Odeslané, seznam. Žlutý odznak s počtem žádostí i na záložce Profil.
- Texty bez rodu („Jakub ti posílá žádost“, „uvidíte si navzájem noci“).
- Ověřeno: `profile_summary` přes REST (já / přítel / ne-přítel / anon 42501), tok žádosti Jakub → Adam přes RPC (remove → send → pending → screenshot žádosti v appce → accept), screenshoty všech obrazovek. Klikání v UI (hledání, tlačítka) jsem neověřil – neumím do simulátoru klepat.
- DEBUG: `-debugProfile friends|<přezdívka>`.

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

## 2026-11-06 – Web: landing page, zásady ochrany osobních údajů, podmínky
- `site/` (statické HTML, barvy z design.md, žádné externí fonty/skripty/cookies): `index.html`, `privacy.html`, `terms.html`, `style.css`.
- Nasazení: `.github/workflows/pages.yml` → GitHub Pages (`https://m1ko20.github.io/sleepscore/`), po zapnutí Settings → Pages → Source: GitHub Actions.
- Omezení odpovědnosti je v podmínkách (ne zdravotnický prostředek, „tak, jak je“, sázky = soukromá dohoda hráčů).
- Chybí doplnit (žlutě v textu): správce (jméno/IČO/adresa), kontaktní e-mail, datum účinnosti, věková hranice. Před ostrým spuštěním nechat zkontrolovat právníkem.
- Další krok: notifikace (návrh u Adama).

## 2026-11-06 – Zmenšování starých nocí
- Migrace `…220000_compact_night_raw.sql`: noci starší 120 dní denně zmenší pg_cron (slití úseků, tep do 5min průměrů). Na dev datech −56 % místa, nic se neztratilo z toho, co appka zobrazuje. Detail v backend.md.
- Notifikace: návrh (zvoneček v appce + pushe přes frontu a pg_cron, mazání po 30 dnech) čeká na Adamovo OK.
