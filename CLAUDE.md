# Sleep app – „Strava pro spánek“

Komunikuj česky. Uživatel (Adam) je zakladatel projektu, kód píšeš ty. Před větší implementací se nejdřív domluv – Adam chce věci nejdřív probrat, pak stavět.

Kompletní specifikace V1 (živý dokument, Adam ho upravuje): https://claude.ai/artifact/GQNvwsfGShHdbMmEEPrqCK
Pokud se tento soubor a dokument liší, platí dokument – zeptej se Adama.

## Stav
- Repo: https://github.com/M1ko20/sleepscore (veřejné – žádné klíče do gitu!). Název appky ještě není.
- Hotovo: DB schéma v `supabase/migrations/` (tabulky, RLS, RPC funkce, číselníky), **nasazeno** do Supabase projektu `tlespfcbqzddddhjsieu` (Sleepscore, eu-central-1). Nasazení: `supabase db push --remote --yes` (CLI je přihlášené a nalinkované).
- Pomocné funkce pro RLS jsou ve schématu `private` (není v API). Zbylá varování Security Advisoru „SECURITY DEFINER callable“ jsou záměrné RPC funkce.
- První uživatel (Adam) nemá pozvánku – profil mu po prvním přihlášení založit ručně.
- Hotovo: Edge Function `ingest-sleep` (nasazená, `supabase functions deploy ingest-sleep --use-api --yes`). Logika skóre v `supabase/functions/_shared/sleep.ts`, testy `cd supabase/functions && deno test _shared/`.
  - Hlavní spánek = nejdelší souvislý spánek (mezera > 60 min = nový) končící do 14:00; víc zdrojů se nesčítá, bere se ten delší.
  - Chybějící složka skóre (bez fází / bez tepu) se vynechá a váhy se přepočítají. Pravidelnost = průměr usnutí za 14 nocí, tep = normál za 30 nocí; při < 3 nocích historie plné body.
  - Strop podle délky: pod 5 h max 50 bodů, pod 6 h max 70.
  - Minimální délka pro sérii: 6 h.
- Apple Developer Program až bude appka skoro hotová → do té doby simulátor + testovací přihlášení, Sign in with Apple a HealthKit na reálném iPhonu na konec.
- E2E test: `supabase/tests/e2e.py` (25 kontrol, po sobě uklidí). Prošel 2026-11-06.
- Hotovo: série, achievementy a uzavírání výzev – **vše v DB** (migrace `…140000_streaks_achievements_challenges.sql`), plánováno přes **pg_cron** (`hourly-jobs` v :05, úklid historie v 3:30). Žádné Edge Function volání navíc → šetří Free tier. Adam chce hlídat počet callů na Supabase.
  - Série se přepočítává jen uživateli, který nahrál noc (`after_night_ingest`, volá ingest), a jednou denně po 14:00 lidem s rozjetou sérií bez dnešní noci.
  - Tagové achievementy uděluje trigger při uložení tagu.
- **Další krok:** iOS appka (SwiftUI) – nejdřív probrat strukturu obrazovek.

## Produkt
Sociální appka pro spánek: každé ráno se noc objeví jako karta, kamarádi ji komentují a lidi se měří ve výzvách. Tón hravý a soutěživý, ne wellness a ne „AI cringe“.

- **Jen iOS** (SwiftUI). Android není v plánu.
- **Invite-only**: každý dostane 3 pozvánky, další za výhry ve výzvách a milníky sérií. Profil i karty jsou defaultně jen pro přátele.
- **Ranní karta**: sleep score, hypnogram (fáze v čase, případně s tepem), usnutí a vstávání, délka, délky fází, probuzení, název a komentář, tagy (alkohol, kafe po 15:00, večerní trénink, telefon v posteli, pozdní jídlo, dítě, nemoc…), volitelná fotka.
- **Karta se zveřejní automaticky** po synchronizaci + notifikace „doplň komentář“. Tagy jen z pevného seznamu.
- **Feed** karet přátel, komentáře, spánkové reakce místo lajků (**jedna reakce od člověka na kartu**).
- **Přátelé**: kdo tě pozval, je automaticky kamarád. Žádost o přátelství může poslat kdokoliv komukoliv.
- Achievementy jdou získat **opakovaně**.
- **Profil**: profilovka, MMA bilance z výzev (výhry-prohry-remízy, např. 12-3-1), vitrína „duší“ (trofej za každého poraženého), vzájemná bilance se soupeřem.
- **Série**: odměňuje pravidelnost (usnutí ±30 min od průměru 14 nocí + min. 6 h), streak freeze 1× týdně automaticky (první špatná/chybějící noc v týdnu nepřeruší, ale nepřičte se).
- Opakované achievementy: Sběratel za každých 10 duší, Neporazitelný za každých 5 výher v řadě, Švýcarské hodinky za každý další 14denní úsek. Ukradená hodina = noc na poslední neděli v březnu, Dvojí život se vyhodnocuje v pondělí.
- **Achievementy**: viz dokument (Kóma, Zombie, Noční směna, Ani se nehnul, Hlubinář, Dokonalá noc, Švýcarské hodinky, Dvojí život, Stovka, Navzdory, Pivo vyhrálo, První duše, Sběratel, Neporazitelný, Odplata, O chlup, Zapomněl hodinky, Ukradená hodina, Novoroční přeživší…).
- **Tagy → insighty** („s alkoholem máš o 38 % méně deep“), **týdenní recap** v pondělí, **Sleep Wrapped** na konci roku.
- Vyřazeno: tlačítko „Jdu spát“, týdenní ligy.

## Výzvy (souboje) – klíčová mechanika
- 1v1, nebo skupinové ve dvou variantách: všichni proti všem / společný cíl.
- Minimální délka **7 dní**.
- Sázku si hráči napíšou sami („prohraný platí pivo“); appka vede účet dluhů, dlužník označí splacení.
- **Rozhoduje výhradně sleep score**, nic se nehodnotí ručně.
  - Den vyhrává vyšší sleep score té noci.
  - Výzvu vyhrává vyšší **průměrné** sleep score za celou dobu; vyhrané dny jsou jen statistika.
  - Remíza = stejný průměr.
- Noc bez dat = sleep score **0** ve výzvě. Dokud výzva běží, jde nahrát zpětně a 0 se nahradí. Do feedu se chybějící noc nedostane.
- Výzva se **uzavírá automaticky posledním dnem ve 14:00** (místní čas zakladatele) – poslední noc už nemůže přibýt; data nahraná po uzavření výsledek nemění.
- Odměny: sázka, duše poraženého do vitríny, zápis do MMA bilance, pozvánka navíc.
- **Všichni proti všem**: vítěz bere vše – každý ostatní mu dluží sázku, vítěz bere duše všech, v MMA má vítěz výhru, ostatní prohru. Shodný nejvyšší průměr = remíza.
- **Společný cíl**: počítá se do MMA (splněno = výhra všem, nesplněno = prohra všem), nebere se duše, nepočítá se do vzájemné bilance. Sázka může být (bez účtu dluhů).
- Shoda na 1. místě (všichni proti všem) = remíza mezi nimi, ostatní prohra, žádné dluhy ani duše. Den vyhrává jen jasně nejvyšší skóre (shoda = nikdo).
- Pozvánka navíc: +1 za výhru v duelu / všichni proti všem, +1 za sérii 30 a 100 dní. Za společný cíl ne.
- Výzvy jen mezi přáteli. Duel startuje den po přijetí; skupinovou spouští zakladatel (min. 3 přijatí).

## Data
- **V1: Apple Health přes HealthKit.** Garmin Connect zapisuje spánek jako úseky (Core/Deep/REM/Awake) a tep zvlášť. Nejsou tam Garmin sleep score, HRV, dech, Body Battery, SpO2.
- Brát jen data ze zařízení (ne ruční záznamy) – ochrana proti podvádění.
- **Počítá se jen hlavní spánek**, šlofíky ne. Spánek patří ke dni, ve kterém skončil, pokud skončil do 14:00.
- Načítání: HKObserverQuery + background delivery → appka pošle surová data (úseky + tep) na server.
- **V2 (později): Garmin Health API** – vyžaduje schválení v Garmin Connect Developer Program (Adam si pak udělá živnosťák / IČO, landing page, privacy policy). Přinese Garmin sleep score, HRV, dech atd.

## Sleep score
Dokud není Garmin API, počítáme **vlastní skóre na serveru** ze surových dat (aby šlo přepočítat a nešlo podvádět). Je to dočasné řešení.

| Složka | Váha |
|---|---|
| Délka spánku (cíl 7–9 h) | 35 % |
| Kvalita fází (podíl deep + REM) | 25 % |
| Přerušovanost (počet a délka probuzení) | 15 % |
| Pravidelnost (odchylka usnutí od průměru) | 15 % |
| Tep ve spánku vs. osobní normál | 10 % |

Váhy jsou první odhad. Otevřená otázka: ve V2 ve výzvách dál vlastní skóre (férové napříč zařízeními), nebo appka jen pro Garmin a jeho skóre?

## Backend
- **Supabase** (PostgreSQL, Auth se Sign in with Apple, Storage na fotky a profilovky, Edge Functions, cron).
- Začínáme na Free (stačí na ~100+ uživatelů), na Pro (25 $/měs., kvůli zálohám) nejpozději před spuštěním pro cizí lidi. Free projekt se uspí po týdnu nečinnosti.
- Fotky zmenšovat na telefonu (~200 kB).
- Pravidla přístupu přes Row Level Security (spánek jsou zdravotní data – GDPR, HealthKit data nesmí do reklamy).
- Hlavní entity: uživatelé/profily, pozvánky, přátelství, noci + úseky fází, karty (komentář, tagy, fotka), komentáře, reakce, výzvy, účastníci, denní skóre ve výzvě, sázky/dluhy, achievementy.
- Serverové úlohy: výpočet skóre, zápis do výzev, kontrola achievementů, uzavírání výzev, týdenní recap, push notifikace (APNs).

## Otevřené otázky
- Název appky
- Férovost skóre ve V2 (viz výše)
- Kdy přejít na Supabase Pro
