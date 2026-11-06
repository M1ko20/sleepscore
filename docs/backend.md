# Backend – jak to funguje

Stav k 2026-11-06. Supabase projekt **Sleepscore** (`tlespfcbqzddddhjsieu`, eu-central-1, Free).
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
| `supabase/functions/ingest-sleep/index.ts` | Edge Function pro příjem spánku |
| `supabase/functions/_shared/sleep.ts` | čistá logika: hlavní spánek, metriky, skóre |
| `supabase/functions/_shared/sleep_test.ts` | unit testy skóre (13) |
| `supabase/tests/e2e.py` | E2E test proti živému projektu (25 kontrol, uklidí po sobě) |

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

Pohledy (security_invoker): `mma_records` (všechny typy výzev), `souls` (bez team_goal), `head_to_head` (bez team_goal).

Storage: buckety `avatars`, `night-photos` (privátní), cesta `<user_id>/<soubor>`. Fotky karet vidí jen přátelé.

## Kdo co vidí (RLS)
- Základní profil (přezdívka, jméno, avatar): každý člen – kvůli hledání přátel.
- Noci, hypnogram, karty, komentáře, reakce, série, achievementy: vlastník + přátelé.
- Výzvy, účastníci, denní skóre: účastníci + přátelé účastníků.
- Dluhy: jen dlužník a věřitel.
- Bez profilu (Apple login bez pozvánky) nevidí nic. `anon` nemá přístup nikam.
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
| `profile_summary(user)` | celý profil jedním callem (bilance, série, průměr 30 dní, duše, odznaky, vzájemná bilance, stav přátelství); security invoker → RLS |
| `create_challenge(type, opponents[], duration_days, stake?, target_score?)` | jen s přáteli; duel = 1 soupeř, skupina ≥ 2 pozvaní |
| `respond_challenge(challenge, accept)` | duel po přijetí startuje zítra (tz zakladatele) |
| `start_challenge(challenge)` | skupinu spouští zakladatel, min. 3 přijatí |
| `cancel_challenge(challenge)` | zakladatel, jen pending |
| `settle_debt(debt)` | dlužník označí splacení |

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

## Sleep score v1 (`_shared/sleep.ts`)
| Složka | Váha | Výpočet |
|---|---|---|
| Délka | 35 % | 7–9 h = 100; pod 7 h lineárně na 0 ve 4 h; nad 9 h −20/h, min 50 |
| Fáze | 25 % | (deep + REM) / spánek s fázemi; 40 % = 100. Bez fází (< 50 % spánku má fázi) = vynechat |
| Přerušovanost | 15 % | 100 − 5 × probuzení − minuty vzhůru (probuzení ≥ 1 min) |
| Pravidelnost | 15 % | odchylka usnutí od průměru 14 nocí; ≤ 15 min = 100, 120 min = 0; < 3 noci historie = 100 |
| Tep | 10 % | průměr ve spánku vs. normál 30 nocí; normál = 100, +10 tepů = 0; < 3 noci = 100; bez tepu = vynechat |

Vynechané složky → váhy se přepočítají. **Strop podle délky:** < 5 h max 50, < 6 h max 70.
Čas usnutí se počítá jako „minuty od poledne“ (bez skoku přes půlnoc).

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
cd supabase/functions && deno test _shared/               # unit testy
# E2E (vytvoří 2 testovací uživatele a smaže je):
supabase projects api-keys --project-ref tlespfcbqzddddhjsieu -o json > /tmp/keys.json
python3 -I supabase/tests/e2e.py /tmp/keys.json && rm /tmp/keys.json
```
SQL logiku lze testovat lokálně: Postgres 16 (`/opt/homebrew/opt/postgresql@16/bin`) + stub schémat `auth`/`storage` (role anon/authenticated/service_role, `auth.uid()` z `request.jwt.claim.sub`). Docker není, `supabase start` nejde. Postgres potřebuje `LC_ALL=C`.

## Chybí / TODO
- Push notifikace (APNs) – až bude Apple Developer Program.
- Sign in with Apple – totéž; do té doby testovací přihlášení e-mailem v dev buildu.
- První uživatel (Adam) nemá pozvánku → profil založit ručně (service role insert do `profiles` + `user_stats`).
- Insighty z tagů, týdenní recap, Sleep Wrapped.
- Mazání účtu z appky (GDPR) – smazání `auth.users` vše kaskádově smaže, chybí jen endpoint.
