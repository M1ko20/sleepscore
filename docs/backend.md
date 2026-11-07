# Backend – jak to funguje

Stav k 2026-11-07. Supabase projekt **Sleepscore** (`tlespfcbqzddddhjsieu`, eu-central-1, Free).
Tenhle soubor je zkratka, aby se nemuselo číst SQL. Při změně backendu ho aktualizuj.

## Princip
- Telefon **čte** přes RLS (PostgREST), ale citlivé věci **nezapisuje přímo**.
- Zápisy z telefonu: RPC funkce (kontrolují pravidla) + pár přímých zápisů (vlastní karta, tagy, komentáře, reakce, push tokeny, profil).
- Noci, skóre, výsledky výzev, dluhy, achievementy, série zapisuje jen server (Edge Function se service role nebo SQL funkce).
- Všechno plánované běží v DB přes **pg_cron** – žádná Edge Function navíc (Free tier, Adam hlídá počet callů).

## Tok dat
```
iPhone (HealthKit) ──POST samples + tep──▶ Edge Function ingest-sleep
                                            │ vybere hlavní spánek / den
                                            │ spočítá skóre (_shared/sleep.ts)
                                            ├─▶ nights, night_raw (upsert)
                                            ├─▶ posts (karta, auto-zveřejnění)
                                            ├─▶ challenge_day_scores (běžící výzvy)
                                            └─▶ rpc after_night_ingest → achievementy za noc + přepočet série
pg_cron každou hodinu v :05 ─▶ private.hourly_jobs()
                                ├─ finalize_due_challenges (poslední den ve 14:00 tz zakladatele)
                                ├─ díry v sériích (1× denně po 14:00, jen rozjeté série)
                                └─ Dvojí život (pondělí 10:00)
pg_cron denně 3:45 UTC ─▶ private.compact_old_night_raw()  (noci starší 120 dní)
pg_cron každou hodinu v :35 ─▶ private.remind_open_reports()  (hlášení otevřená > 12 h)
reports INSERT ─trigger─▶ webhook pro nás (pg_net, bez Edge Function)
night_tags INSERT ─trigger─▶ Navzdory / Pivo vyhrálo
```

## Soubory
| Cesta | Co je to |
|---|---|
| `supabase/migrations/20261106120000_init.sql` | tabulky, enumy, RLS, pohledy, RPC, storage |
| `…120100_seed_catalogs.sql` | tagy a achievementy (číselníky) |
| `…130000_private_helpers.sql` | RLS helpery přesunuté do schématu `private` |
| `…140000_streaks_achievements_challenges.sql` | série, achievementy, uzavírání výzev |
| `…140100_cron.sql` | pg_cron úlohy |
| `…220000_compact_night_raw.sql` | zmenšení starých surových dat (viz níže) |
| `20261107100000_apple_tokens.sql` | `apple_tokens` (Apple refresh token kvůli revokaci) |
| `20261107010215_moderation.sql` | blokování, nahlášení, ban, upozornění (viz Moderace) |
| `supabase/functions/ingest-sleep/index.ts` | Edge Function pro příjem spánku |
| `supabase/functions/_shared/sleep.ts` | čistá logika: hlavní spánek, metriky, skóre |
| `supabase/functions/_shared/sleep_test.ts` | unit testy skóre (15) |
| `supabase/functions/apple-token/index.ts` | po Apple přihlášení: authorization code → refresh token |
| `supabase/functions/delete-account/index.ts` | smazání Apple účtu: revokace tokenu + `delete_my_account` |
| `supabase/functions/_shared/apple.ts` (+ `apple_test.ts`, 8 testů) | Apple REST API: client_secret (ES256), `/auth/token`, `/auth/revoke` |
| `supabase/tests/e2e.py` | E2E test proti živému projektu (25 kontrol, uklidí po sobě) |
| `supabase/tests/local/run.sh` | lokální SQL testy: dočasný Postgres 16 + `stub.sql` (auth, storage, cron, net) + všechny migrace + `*_test.sql` |
| `supabase/tests/local/moderation_test.sql` | moderace (68 kontrol) |

## Tabulky (public)
- `profiles` – přezdívka (`^[a-z0-9_.]{3,20}$`), jméno, avatar, timezone, `invites_available` (start 3), `invited_by`
- `invites` – kód (8 znaků bez 0/O/1/I/L), kdo pozval, kdo uplatnil
- `friendships` – 1 řádek na dvojici (`user_a < user_b`), `pending/accepted`, `requested_by`
- `nights` – 1 hlavní noc / uživatel / den; usnutí, vstávání, minuty fází, probuzení, tep, `score`, `score_breakdown` (jsonb), `score_version`
- `night_raw` – úseky fází + tep jako JSON (hypnogram, přepočet). Ne řádek na vzorek (Free tier 500 MB).
- `tags` / `night_tags` – pevný seznam tagů
- `posts` – feed: `night` (karta noci) nebo `challenge_result`; název, komentář, fotka
- `comments`, `reactions` (1 reakce / člověk / karta)
- `challenges` – `duel | free_for_all | team_goal`, sázka (text), `duration_days ≥ 7`, `target_score` (jen team_goal), `pending/active/finished/cancelled`
- `challenge_participants` – `invited/accepted/declined`, `final_avg`, `days_won`, `result`
- `challenge_day_scores` – skóre hráče za den výzvy (0 = chybějící noc, `night_id null`)
- `debts` – dlužník, věřitel, sázka, `settled_at`
- `achievements` (katalog) / `user_achievements` (opakovatelné; unikátní per noc / výzva)
- `user_stats` – aktuální a nejlepší série, poslední týden s freeze
- `push_tokens`
- `apple_tokens` – Apple refresh token (Sign in with Apple), jen service role (RLS bez politik, práva anon/authenticated odebraná), kaskáda s `auth.users`
- `blocks` – kdo koho zablokoval (`blocker_id`, `blocked_id`); řádek vidí jen blokující
- `reports` – hlášení: co (`post | comment | profile | challenge` + id), kdo, na koho, důvod (`harassment | hate | sexual | spam | other`), poznámka, `snapshot` obsahu, `open/resolved/dismissed`. Klient nemá k tabulce žádný přístup.
- `profiles.banned_at` – zabanovaný účet (`private.is_member()` pak vrací false)
- `private.app_config` – klíč/hodnota pro nastavení mimo repo (URL webhooku)

Pohledy (security_invoker): `mma_records` (všechny typy výzev), `souls` (bez team_goal), `head_to_head` (bez team_goal).

Storage: buckety `avatars` (max 150 kB), `night-photos` (max 400 kB) – privátní, jen `image/jpeg`, cesta `<user_id>/<uuid>.jpg` (unikátní → klient cachuje navždy). Fotky karet vidí jen přátelé, profilovky všichni členové. Check constraint: `profiles.avatar_path` i `posts.photo_path` musí vést do vlastní složky.

## Kdo co vidí (RLS)
- Základní profil (přezdívka, jméno, avatar): každý člen – kvůli hledání přátel.
- Noci, hypnogram, karty, komentáře, reakce, série, achievementy: vlastník + přátelé.
- Výzvy, účastníci, denní skóre: účastníci + přátelé účastníků.
- Dluhy: jen dlužník a věřitel.
- Bez profilu (Apple login bez pozvánky) nevidí nic. Zabanovaný taky ne. `anon` nemá přístup nikam.
- Blok (oběma směry): komentáře a reakce toho druhého nevidím a nemůžu komentovat/reagovat na jeho karty. Noci a karty mizí samy – blok ruší přátelství.
- Co jsem nahlásil (karta, komentář), se mi hned skryje (`private.reported_by_me`). Ostatní to vidí dál, dokud hlášení nevyřídíme.
- Helpery `private.is_member / are_friends / can_view_challenge / can_view_post / is_friend_folder` – schéma `private` není v API.

## RPC pro appku
| Funkce | Co dělá |
|---|---|
| `redeem_invite(code, username, display_name)` | registrace: založí profil, spotřebuje kód, udělá přátelství s tím, kdo pozval |
| `create_invite()` | vrátí nový kód, ubere 1 pozvánku |
| `check_invite(code)` | platí kód? (onboarding, nevrací zvoucího) |
| `username_available(username)` | volná a platná přezdívka? |
| `send_friend_request(user)` | žádost; když protistrana už žádala, rovnou přijme |
| `respond_friend_request(user, accept)` / `remove_friend(user)` | |
| `tag_insights(user)` | tagy: noci s tagem vs. bez (90 dní, min. 3+3) – skóre, deep, usínání, délka |
| `weekly_recap(week_start?)` | recap týdne volajícího (default minulý po–ne) |
| `export_my_data()` | GDPR export: všechna moje data jako JSON (vč. surových dat nocí) |
| `delete_my_account()` | GDPR smazání: zruší neuzavřené souboje se mnou a moje čekající výzvy, smaže `auth.users` → kaskáda |
| `sleep_wrapped(year?)` | rok volajícího (Wrapped) jedním callem |
| `profile_summary(user)` | celý profil jedním callem (bilance, série, průměr 30 dní, duše, odznaky, vzájemná bilance, stav přátelství); security invoker → RLS |
| `create_challenge(type, opponents[], duration_days, stake?, target_score?)` | jen s přáteli; duel = 1 soupeř, skupina ≥ 2 pozvaní |
| `respond_challenge(challenge, accept)` | duel po přijetí startuje zítra (tz zakladatele) |
| `start_challenge(challenge)` | skupinu spouští zakladatel, min. 3 přijatí |
| `cancel_challenge(challenge)` | zakladatel, jen pending |
| `settle_debt(debt)` | dlužník označí splacení |
| `block_user(user)` | blok + zruší přátelství/žádost, čekající souboj mezi nimi zruší, z čekající skupinové výzvy jednoho z nich vyřadí druhého |
| `unblock_user(user)` | zruší blok (přátelství se neobnoví) |
| `report_content(kind, target, reason, note?, block?)` | nahlášení (jen viditelný obsah, ne vlastní, 1× na obsah, max. 20/den); `block = true` rovnou zablokuje autora |

Přímé zápisy: `profiles` (display_name, avatar_path, timezone), `posts` (title, body, photo_path – jen vlastní noční karta), `night_tags`, `comments`, `reactions`, `push_tokens`.

## Edge Function `ingest-sleep`
`POST /functions/v1/ingest-sleep` s JWT uživatele.
```json
{ "timezone": "Europe/Prague",
  "samples": [{ "uuid": "…", "start": "ISO", "end": "ISO", "stage": "core|deep|rem|awake|asleep", "source": "Garmin Connect", "userEntered": false }],
  "heart_rate": [{ "t": "ISO", "bpm": 52 }] }
```
Odpověď: `{ nights: [{ date, score, status: created|updated|kept_existing|error, streak, new_achievements[] }] }`.
Limity: 5 000 vzorků spánku, 60 000 tepu. Posílat okno ~2–3 dny (zpětné dohrání funguje).

Pravidla:
- Ruční záznamy (`userEntered`) se zahazují.
- Session = souvislé vzorky jednoho zdroje, mezera > 60 min = nová session. Úvodní/koncové awake se ořízne.
- Hlavní spánek dne = nejdelší session (napříč zdroji), která skončila do 14:00 místního času. Zdroje se nesčítají.
- Kratší nepřekrývající se session nepřepíše uloženou noc (ochrana proti šlofíku při zpětném nahrání).

## GDPR
- Data: Supabase eu-central-1 (Frankfurt). Spánek = zdravotní data (čl. 9) → jen přátelé (RLS), HealthKit data nikdy do reklamy ani třetím stranám.
- **Export** (`export_my_data`, security invoker): profil, statistiky, noci + `night_raw` + tagy, karty, moje komentáře a reakce, přátelství, účasti ve výzvách, denní skóre, dluhy, odznaky, pozvánky. Appka uloží `sleepscore-<přezdívka>-<datum>.json` (ochrana souboru `complete`) a nabídne sdílení.
- **Smazání** (Nastavení → Soukromí → Smazat účet, potvrzení napsáním přezdívky): appka smaže moje soubory v `avatars/` a `night-photos/` (`<uid>/…`; přímý DELETE ze `storage.objects` Supabase blokuje), pak `delete_my_account()`: neuzavřené souboje se mnou → `cancelled`, moje čekající výzvy → `cancelled`, `delete from auth.users` → kaskáda na `profiles` a vše navázané. Výzvy mají vlastní `timezone` a `creator_id … on delete set null` → ostatním zůstanou výsledky, MMA i duše proti jiným hráčům; skupinové výzvy běží dál beze mě.
- Po odhlášení / smazání appka vyčistí cache obrázků a lokální klíče (`seenChallengeResults`, `dismissedRecapWeek`).
- Ověřeno: export přes REST (Karolína 92 kB), anon 401, smazání v transakci s `rollback` (účet, profil, noci, přátelství, dluhy pryč; její výzvy zůstaly s `creator_id null`, výsledky ostatních zůstaly).
- **Sign in with Apple – zneplatnění tokenu** (App Review 5.1.1(v)):
  - Po přihlášení (`Session.signInWithApple`) appka pošle jednorázový `authorizationCode` na `apple-token` → server ho vymění na `https://appleid.apple.com/auth/token` za refresh token, ověří, že `sub` z `id_token` = Apple identita přihlášeného účtu, a uloží do `apple_tokens`. Chyba přihlášení neblokuje (jen log). 1 call na přihlášení přes Apple.
  - Smazání Apple účtu: appka smaže Storage a místo RPC zavolá `delete-account` → `/auth/revoke` s refresh tokenem, pak `delete_my_account()` jménem uživatele (jeho JWT). Revokace je best effort: chybí-li konfigurace, token nebo Apple vrátí chybu, jen se zaloguje a účet se smaže stejně. Odpověď `{ deleted, revoked }`.
  - E-mailové účty (dev build) dál volají rovnou `delete_my_account()` → fungují i bez nasazené funkce.
  - `client_secret` = JWT ES256 podepsaný `.p8` klíčem (platnost 5 min), generuje se při každém volání.
  - Secrets: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_CLIENT_ID` (= bundle `cz.mikolas.sleepscore`), `APPLE_PRIVATE_KEY` (obsah `.p8`). Bez nich se výměna i revokace přeskočí (`apple-token` vrátí `{ stored: false }`).
- Chybí: zásady ochrany osobních údajů (privacy policy) a jejich odkaz v onboardingu – přijde s landing page (nutné i pro App Store a Garmin).

## Moderace (App Store 1.2)
Slib v podmínkách: hlášení vyřídíme do 24 h, nulová tolerance.
- **Nahlášení** z appky: detail karty (⋯ → Nahlásit kartu), komentář (dlouhý stisk → Nahlásit), profil (⋯ → Nahlásit profil), detail výzvy se sázkou (⋯ → Nahlásit sázku). Důvod + nepovinná poznámka + „Zablokovat @x“.
- **Upozornění pro nás:** trigger na `reports` pošle přes `pg_net` webhook (Discord / Slack / ntfy) – jen druh, důvod a id, žádný obsah ani jména. Hodinový pg_cron `report-reminder` (:35) jednou připomene hlášení otevřená přes 12 h. Bez nastavené URL se nic neposílá (hlášení se uloží).
  ```sql
  insert into private.app_config values ('report_webhook_url', 'https://discord.com/api/webhooks/…'),
                                        ('report_webhook_format', 'discord');   -- discord | slack | ntfy
  -- ntfy: URL https://ntfy.sh/<tajné-téma>, formát 'ntfy'
  ```
- **Vyřízení** (SQL editor v dashboardu, jako postgres):
  ```sql
  select id, target_kind, reason, note, snapshot, reported_user_id, created_at
  from public.reports where status = 'open' order by created_at;
  select private.resolve_report('<id>', 'dismiss', 'poznámka');  -- nic se nemaže
  select private.resolve_report('<id>', 'remove');  -- komentář smazat / karta: název+komentář+fotka null / profil: jméno = přezdívka, bez fotky / sázka null
  select private.resolve_report('<id>', 'ban');     -- remove + ban autora
  select private.unban_user('<user>');
  ```
  Vyřídí všechna otevřená hlášení stejného obsahu. Soubory ve Storage SQL smazat nejde → `notice` řekne cestu, smazat ručně v dashboardu.
- **Ban** (`private.ban_user`): `profiles.banned_at`, `auth.users.banned_until = infinity` (nepřihlásí se; platný JWT dožije max. 1 h, ale `is_member()` už vrací false), přátelství, komentáře, reakce, nepoužité pozvánky a push tokeny pryč, texty a fotky karet null, čekající výzvy zrušené. Běžící souboje doběhnou (zabanovaný nic nenahraje → nuly). Účet a noci zůstávají (důkaz, případné odvolání); úplné smazání = `delete from auth.users`.
- **Blok** běžící výzvy neruší (jinak by šlo blokem utéct před prohrou). Skupinovou výzvu od někoho třetího můžou hrát i dva lidé s blokem mezi sebou (vidí jen skóre).
- Smazání účtu: moje bloky zmizí, moje hlášení zůstanou bez `reporter_id`.
- Export dat (`export_my_data`) zatím bloky a hlášení neobsahuje.

## Sleep score v2 (`_shared/sleep.ts`, `score_version = 2`)
v1 dávalo běžným nocím 92–99 (plných 100 za 7–9 h, za 40 % deep+REM, za „normál“) → ve výzvách se noci skoro nelišily. v2: 100 jen za nadprůměr, „normál“ = 85.

| Složka | Váha | Výpočet |
|---|---|---|
| Délka | 35 % | body: 4 h = 0, 5 h = 30, 6 h = 55, 7 h = 80, 8–9 h = 100, 10 h = 85, 11 h = 65, 12 h+ = 50 (lineárně mezi) |
| Fáze | 25 % | půl deep, půl REM (podíl na spánku s fázemi): deep 4 % = 0 → 16 % = 100, REM 8 % = 0 → 22 % = 100. Bez fází (< 50 % spánku má fázi) = vynechat |
| Přerušovanost | 15 % | 100 − 7 × probuzení − 1,2 × minuty vzhůru (probuzení ≥ 1 min) |
| Pravidelnost | 15 % | odchylka usnutí od průměru 14 nocí; ≤ 10 min = 100, 90 min = 0; < 3 noci historie = 85 |
| Tep | 10 % | průměr ve spánku vs. normál 30 nocí; normál = 85, −2 tepy = 100, +10 tepů = 5; < 3 noci = 85; bez tepu = vynechat |

Vynechané složky → váhy se přepočítají. **Strop podle délky:** < 5 h max 45, < 6 h max 65.
Čas usnutí se počítá jako „minuty od poledne“ (bez skoku přes půlnoc).
Referenční noc 8 h, 1 probuzení, 10 min vzhůru, deep 13 %, REM 19 %, bez historie → 88.
Prahy achievementů zůstaly (Dokonalá noc ≥ 95, Navzdory = alkohol + ≥ 85, Pivo vyhrálo < 50) – s v2 jsou vzácnější, jak mají být.
Přepočet starých nocí: zatím jen dev data → znovu nahrát (`seed_dev.py --ingest-only`). Až budou skuteční uživatelé, změna vzorce = nová verze + přepočet z `night_raw` (nenapsáno).

## Série
- Dobrá noc = ≥ 6 h a usnutí ±30 min od průměru předchozích 14 nocí (při < 3 nocích stačí délka).
- Freeze automaticky: první špatná/chybějící noc v týdnu (po–ne) nepřeruší, ale nepřičte se. Druhá přeruší.
- Dnešní noc se počítá, když už dorazila nebo je po 14:00.
- Přepočet celé historie jednoho uživatele (`private.recompute_streak`) – ms, správně i při zpětném nahrání.
- Milníky 7/30/100 → achievement; 30 a 100 → +1 pozvánka. Udělují se jen za poslední týden.

## Uzavření výzvy (`private.finalize_challenge`)
1. Dopíše skóre z nocí, které se nepropsaly; za chybějící noci 0 + achievement Zapomněl hodinky.
2. Průměr (2 desetinná místa), vyhrané dny (jen jasně nejvyšší skóre dne).
3. Výsledek: duel / všichni proti všem → nejvyšší průměr vyhrává, shoda nahoře = remíza mezi nimi, ostatní prohra. Společný cíl → průměr skupiny ≥ cíl = výhra všem, jinak prohra všem.
4. Karta výsledku do feedu.
5. Jen při jasném vítězi (ne team_goal): dluhy poražených vůči vítězi (když je sázka), +1 pozvánka, achievementy První duše, Sběratel (každých 10 duší), Neporazitelný (každých 5 výher v řadě), Odplata (porazil toho, kdo ho naposledy porazil), O chlup (< 1 bod).

## Jak nasazovat a testovat
```bash
supabase db push --remote --yes                          # migrace
supabase functions deploy ingest-sleep --use-api --yes    # funkce (bez Dockeru)
supabase functions deploy apple-token --use-api --yes
supabase functions deploy delete-account --use-api --yes
# Apple secrets (až bude Developer Program; .p8 nikdy do gitu):
supabase secrets set APPLE_TEAM_ID=… APPLE_KEY_ID=… APPLE_CLIENT_ID=cz.mikolas.sleepscore
supabase secrets set APPLE_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
cd supabase/functions && deno test _shared/               # unit testy
# E2E (vytvoří 2 testovací uživatele a smaže je):
supabase projects api-keys --project-ref tlespfcbqzddddhjsieu -o json > /tmp/keys.json
python3 -I supabase/tests/e2e.py /tmp/keys.json && rm /tmp/keys.json
```
SQL logiku lze testovat lokálně: Postgres 16 (`/opt/homebrew/opt/postgresql@16/bin`) + stub schémat `auth`/`storage`/`cron`/`net` (role anon/authenticated/service_role, `auth.uid()` z `request.jwt.claim.sub`, výchozí granty jako Supabase). Docker není, `supabase start` nejde. Postgres potřebuje `LC_ALL=C`.
```bash
supabase/tests/local/run.sh                      # všechny migrace + všechny *_test.sql
supabase/tests/local/run.sh cesta/x_test.sql     # jen jeden test
```
Testy: `select t_ok(podmínka, 'popis')`, `select t_err($$sql$$, 'část chyby', 'popis')`; role přes `set role authenticated` + `set_config('request.jwt.claim.sub', …)`.

## Chybí / TODO
- Push notifikace (APNs) – až bude Apple Developer Program.
- Sign in with Apple – totéž; do té doby testovací přihlášení e-mailem v dev buildu. Backend pro revokaci tokenu je hotový (viz GDPR), chybí přihlašovací obrazovka (`ASAuthorizationAppleIDProvider` → `Session.signInWithApple`).
- První uživatel (Adam) nemá pozvánku → profil založit ručně (service role insert do `profiles` + `user_stats`).
- Insighty z tagů, týdenní recap, Sleep Wrapped.

## Zmenšování starých surových dat (`night_raw`)
Plná data se drží 120 dní (výzvy, insighty 90 dní, přepočet skóre). Pak je denně pg_cron
(`compact-night-raw`, 3:45 UTC, max 5000 nocí/běh) zmenší a nastaví `compacted = true`:
- `segments`: sousední úseky stejné fáze se slijí, `hk_uuid` zmizí. Délky fází zůstanou přesně.
- `heart_rate`: průměry do 5min oken (`[t, bpm]`, stejný formát). Průměr a minimum tepu za noc jsou v `nights`.
Formát zůstává, appka, Wrapped i export fungují beze změn. Test na dev datech (rollback):
146 kB → 64 kB uloženo (−56 %), deep sedí na sekundu, průměr tepu ±0,1. Odhad pro 100 lidí trvale ~250 MB.
Ruční spuštění: `select private.compact_old_night_raw(p_keep_days => 120);`
