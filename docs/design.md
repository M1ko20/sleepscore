# Design

Stav k 2026-11-06. Rozhodnuto s Adamem: **noční sportovní** směr, **jen tmavý režim**, **vlastní ikony, žádné emoji**. Inspirace: Whoop/Oura (datová, prémiová tma), Strava (feed a statistiky), BeReal/Locket (jen pro kamarády, minimum UI).

## Principy
1. **Čísla jsou hrdina.** Skóre, délka, bilance 12-3-1 – velké, tučné, sportovní. Zbytek ustupuje.
2. **Jedna barva na akci.** Všechno je černobílé, žlutá (`accent`) znamená „tohle je důležité / tvoje / vyhrál jsi“. Když je žlutá všude, nefunguje.
3. **Kamarádi, ne publikum.** Žádné počty followerů, žádné „trending“. Feed je malý a osobní jako BeReal.
4. **Drzý, ne roztomilý.** Texty krátké a suché. Appka si dělá legraci z tebe, ne z uživatele obecně.
5. **Méně UI.** Žádné dekorace, které nenesou informaci. Když jde prvek odstranit bez ztráty, odstraní se.

## Čemu se vyhnout (anti-slop)
- Žádné emoji v UI, v tlačítkách ani v textech appky. (Uživatelé si je do komentářů psát můžou.)
- Žádné fialovo-modré gradienty, „glow“, glassmorphism, blur přes všechno, třpytky, ✨.
- Žádné 3D ilustrace, maskoti, stock obrázky, „AI insight“ odznaky.
- Žádné stíny pod kartami – vrstvy se oddělují tónem pozadí a tenkou linkou.
- Žádné obecné texty: ~~„Tvoje spánková cesta začíná!“~~, ~~„Skvělá práce! 🎉“~~, ~~„Odemkni svůj potenciál“~~.
- Žádné semafory (zelená/oranžová/červená) na skóre. Skóre je číslo, ne varování.
- Konfety jen jednou: když vyhraješ souboj. Nikde jinde.
- Kontrola před každou obrazovkou: *Vypadala by takhle obrazovka v Whoopu nebo ve Stravě? Kdyby ne, proč?*

## Barvy
Jen tmavý režim. Tokeny v kódu (`Color.app.*`), nikde natvrdo hex.

| Token | Hex | Použití |
|---|---|---|
| `bg` | `#0B0D12` | pozadí obrazovek (černá do modra, „noc“) |
| `surface` | `#14171F` | karty, listy |
| `surfaceRaised` | `#1C2029` | vstupy, vybraný řádek, chipy |
| `hairline` | `#262B36` | oddělovače, obrysy |
| `textPrimary` | `#F2F1EC` | hlavní text (teplá bílá, ne čistá #FFF) |
| `textSecondary` | `#9AA0AB` | popisky, časy |
| `textTertiary` | `#5D636E` | neaktivní, osy grafů |
| `accent` | `#F5C542` | jediná akcentní barva – „pouliční lampa“ |
| `accentInk` | `#0B0D12` | text na žluté |
| `destructive` | `#FF5A4E` | jen mazání / zrušení |

Fáze spánku (hypnogram), od nejmělčí po nejhlubší:

| Fáze | Hex |
|---|---|
| Vzhůru | `#E8E4D8` |
| REM | `#7FB4FF` |
| Core (lehký) | `#3D6FD1` |
| Deep (hluboký) | `#2A4BB0` |
| Tep (linka) | `textPrimary` 40 % |

## Typografie
Systémové SF Pro, žádný vlastní font (rychlé, ostré, dynamic type zdarma).

| Styl | Font | Kde |
|---|---|---|
| `scoreXL` | SF Pro, 72 pt, Black, `.fontWidth(.condensed)`, monospaced digits | skóre na detailu, bilance na profilu |
| `scoreL` | 44 pt, Heavy, condensed | skóre na kartě ve feedu |
| `stat` | 22 pt, Bold, monospaced digits | délka, časy, průměry |
| `title` | 20 pt, Bold | názvy obrazovek, název karty |
| `body` | 16 pt, Regular | komentáře, texty |
| `label` | 11 pt, Semibold, VERZÁLKY, prostrkání +0,6 | popisky statistik („DÉLKA“, „USNUTÍ“) – sportovní styl |
| `caption` | 13 pt, Regular, `textSecondary` | časy, metadata |

Čísla vždy s `.monospacedDigit()`, ať neposkakují.

## Rozměry
- Mřížka 4 pt. Okraj obrazovky 16 pt. Mezera mezi kartami 12 pt.
- Rádius karet 14 pt, chipů a tlačítek 10 pt. Nic kulatějšího (žádné „pilulky“ všude).
- Dotykové cíle min. 44 × 44 pt.
- Ikony: SF Symbols, váha `.medium`, jednobarevné. Velikost 20 pt (navigace), 16 pt (v textu).

## Navigace
Tab bar se 3 položkami, bez popisků navíc:

```
┌─────────────────────────────────┐
│                                 │
│           (obsah)               │
│                                 │
├─────────────────────────────────┤
│   Feed      Výzvy      Profil   │
└─────────────────────────────────┘
```
- Přátelé a pozvánky jsou v Profilu (nejsou potřeba denně).
- Nová výzva = tlačítko vpravo nahoře v záložce Výzvy.
- Aktivní záložka = `textPrimary`, ostatní `textTertiary`. Žlutá jen jako tečka u záložky, když na tebe něco čeká (pozvánka do výzvy, nový komentář).

## Komponenty

### Karta noci (feed)
```
┌───────────────────────────────────┐
│ (○) Jakub                  07:14  │  avatar 28 pt, jméno, čas nahrání
│                                   │
│ Spal jsem jak dřevo               │  název (title), jen když ho vyplnil
│                                   │
│ 87          7 h 42     23:14      │  scoreL │ stat │ stat
│ SKÓRE       DÉLKA      USNUTÍ     │  label
│                                   │
│ ▔▔▁▁▂▂▁▔▁▁▂▂▂▁▁▔▔▁▁▂▂▁▁▔         │  mini hypnogram, výška 36 pt
│                                   │
│ ALKOHOL · VEČERNÍ TRÉNINK         │  tagy jako text (label), ne chipy
│                                   │
│ [zzz 4] [korbel 2]       [≡ 3]    │  reakce (ikona + počet), komentáře
└───────────────────────────────────┘
```
- Fotka (když je) nad čísly, poměr 4:5, rádius 10, bez filtru.
- Komentář autora pod názvem, max. 3 řádky, pak „víc“.
- Série se ukazuje jen od 3 nocí: malý text `SÉRIE 12` vedle času.
- Nový achievement za tu noc: jeden řádek nad reakcemi, ikona odznaku + název („Hlubinář“). Ne pop-up.

### Moje karta ráno
Nahoře ve feedu, stejná karta, ale s obrysem `accent` 1 pt a jedním řádkem navíc:
`Doplň název a tagy` → otevře úpravu. Po doplnění obrys zmizí.

### Karta výsledku výzvy (feed)
```
┌───────────────────────────────────┐
│ VÝZVA · 7 DNÍ                     │
│                                   │
│ ADAM            JAKUB             │
│ 81,4     :      76,2              │  vítěz textPrimary, poražený textSecondary
│ 5 dní           2 dny             │
│                                   │
│ Adam bere duši. Jakub platí pivo. │  jedna suchá věta
└───────────────────────────────────┘
```

### Reakce
Pět vlastních ikon, jeden styl (lineární, 1,5 pt tah, jako SF Symbols):

| Kód | Význam | Ikona |
|---|---|---|
| `sleeper` | spal jak dřevo | zavřené oko / „zzz“ |
| `zombie` | jsi zombie | ruka natažená dopředu |
| `beer` | pivo vyhrálo | korbel |
| `coffee` | potřebuješ kafe | hrnek |
| `crown` | král spánku | koruna |

- Ve feedu jen reakce, které někdo dal (ikona + počet), max. 3, zbytek „+2“.
- Dlouhý stisk na kartě / tlačítko → lišta s 5 ikonami. Moje reakce = žlutá.

### Hypnogram (detail)
```
VZHŮRU  ▆       ▆
REM        ███      ████      ███
CORE   ████   ██████    ██████   ███
DEEP       ████            ███
       23:14     01:00     03:00     05:00     07:02
       ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  tep (tenká linka)
```
- Schodový graf, každá fáze svůj řádek, úseky jako obdélníky s rádiusem 2 pt.
- Na ose jen začátek, konec a celé hodiny. Žádná mřížka.
- Tep jako tenká linka přes graf, osa vpravo jen min/max.
- Dotyk a tah = čas + fáze + tep v tom bodě.

### Odznaky (achievementy)
- Plochý šestiúhelník (ne 3D medaile), uvnitř SF Symbol nebo vlastní glyf.
- Získaný: obrys `accent`, glyf `textPrimary`; opakovaný má vpravo dole `×3`.
- Nezískaný: obrys `hairline`, glyf `textTertiary`, podmínka v detailu (ať je co honit).

### Duše (vitrína)
- Mřížka 4 sloupce. Duše = avatar poraženého v kroužku, desaturovaný, s datem pod ním.
- Víc duší od stejného člověka → jedna dlaždice s počtem `×4`.

### Tlačítka
- Primární: plné `accent`, text `accentInk`, výška 50 pt, rádius 10. Na obrazovce max. jedno.
- Sekundární: `surfaceRaised`, text `textPrimary`.
- Textové: jen `textSecondary`, bez podtržení.

## Obrazovky

### 1. Onboarding (pozvánka)
1. **Kód pozvánky** – jedno pole, velké písmo, 8 znaků. Nahoře: „Sem se dostaneš jen přes kamaráda.“
2. **Přihlášení** – Sign in with Apple (v dev buildu e-mail).
3. **Přezdívka a jméno** – kontrola dostupnosti přezdívky za běhu.
4. **Apple Health** – jedna obrazovka: co čteme (spánek, tep), co nikdy (nic dalšího, nic do reklamy), tlačítko Povolit.
5. Hotovo → feed s kartou toho, kdo tě pozval, a větou „První noc se ukáže zítra ráno.“

### 2. Feed
- Nahoře „Feed“ (title), vpravo zvoneček (`bell`, 44 × 44 pt). Nepřečtené = malý žlutý štítek s číslem (`accent`, text `accentInk`, max. „99+“).
- Moje dnešní karta (když je), pak karty přátel od nejnovější, karty výsledků výzev mezi nimi.
- Prázdný feed: „Zatím tu nikdo není. Pošli pozvánku.“ + sekundární tlačítko.
- Chybějící noc se nezobrazuje vůbec (žádné „Jakub dnes nespal“).

### 2b. Upozornění (zvoneček)
```
‹ Feed            Upozornění
─────────────────────────────────
(○) Cyril a 2 další reagují na    •
    tvoji noc.
    7:14
─────────────────────────────────
(☾) Tvoje noc: 78. Doplň komentář.
    6:52
─────────────────────────────────
(○) Adam tě vyzývá: 7 dní, pivo.
    včera
```
- Řádek: avatar aktéra 36 pt (u notifikací od appky glyf v kroužku `surfaceRaised`: `moon.zzz` karta, `hexagon` odznak, `chart.bar` recap, `flag.2.crossed` výzva), text `body` max. 3 řádky, čas `caption`. Oddělení tenkou linkou, bez karet.
- Nové = žlutá tečka 8 pt vpravo (jen při tomhle otevření; otevření výpisu označí vše jako přečtené).
- Klepnutí: karta, výzva, profil nebo recap. Prázdný stav: „Ticho. Až někdo zareaguje, uvidíš to tady.“
- Texty skládá server, sloveso v přítomném čase (nemusíme znát rod): „Bára jde do toho.“, „Adam přijímá žádost o přátelství.“

### 3. Detail noci
Shora: autor a datum → `scoreXL` + 3 statistiky (délka, usnutí, vstávání) → hypnogram → délky fází (4 vodorovné pruhy s minutami) → **rozpad skóre** (5 řádků: název složky, tenký pruh, číslo; vynechaná složka šedě „bez dat“) → tagy → fotka → komentáře.

### 4. Úprava karty (sheet)
Název (1 řádek), komentář, tagy (mřížka chipů `surfaceRaised`, vybraný = obrys `accent`), fotka (zmenšení na ~200 kB na telefonu). Uložit = primární tlačítko.

### 5. Výzvy
```
Výzvy                          [+]
─────────────────────────────────
ČEKÁ NA TEBE
  Jakub tě vyzval · 7 dní · pivo   [Přijmout] [Odmítnout]

BĚŽÍ
  Ty vs Jakub        81,4 : 76,2   den 4/7
  Partička (4)       2. místo      den 2/14

DLUHY
  Tomáš ti dluží     3× pivo
  Dlužíš Jakubovi    kafe          [Splaceno]

HOTOVÉ
  Ty vs Tomáš        výhra   12. 10.
```

### 6. Detail výzvy
- Hlavička jako plakát: jména, průměry (`scoreXL`), vyhrané dny.
- Mřížka dní: sloupec na den, řádek na hráče, v buňce skóre; vítěz dne `textPrimary`, ostatní `textSecondary`; chybějící noc `0` v `textTertiary` s poznámkou „dá se dohrát“.
- Sázka, typ, konec („končí v neděli ve 14:00“).
- Společný cíl: místo „vs“ jeden pruh průměru skupiny proti cíli.

### 7. Nová výzva (průvodce, 4 kroky)
Typ (duel / všichni proti všem / společný cíl) → soupeři (jen přátelé) → délka (7 / 14 / 30 / vlastní, min. 7) → sázka (volný text, nápověda „prohraný platí pivo“) + u společného cíle cílové skóre → Odeslat.

### 8. Výsledek výzvy (jednorázová obrazovka)
Otevře se po uzavření výzvy. Vítěz: velké „VÝHRA“, duše poraženého „letí“ do vitríny (jediná animace s konfetami v celé appce). Poražený: „PROHRA“, bez animace, jedna suchá věta („Příště dřív do postele.“). Tlačítko Odplata → nová výzva se stejným soupeřem.

### 9. Profil (můj)
```
(○)  Adam                       [⚙]
     @adam

12-3-1                    SÉRIE 12
VÝHRY-PROHRY-REMÍZY       nejlepší 31

PRŮMĚR 30 DNÍ   81   ·   7 h 18
─────────────────────────────────
VITRÍNA DUŠÍ                    9
(○)(○)(○)(○)
─────────────────────────────────
ODZNAKY                     14/22
⬡ ⬡ ⬡ ⬡ ⬡
─────────────────────────────────
PŘÁTELÉ (6)                     ›
POZVÁNKY · zbývá 2              ›
```

### 10. Profil přítele
Stejný, ale místo nastavení: **vzájemná bilance** nahoře („Ty vs Jakub 7-3“) a primární tlačítko **Vyzvat**.

### 11. Přátelé a pozvánky
- Hledání podle přezdívky, žádosti (přijmout/odmítnout), seznam přátel.
- Pozvánky: počet zbývajících, tlačítko Vytvořit kód → systémové sdílení s textem „Pojď se měřit ve spaní. Kód: K7MPQX2R“.

## Tón textů
Česky, tykání, krátce, sucho. Bez vykřičníků (max. jeden na obrazovku), bez emoji.

| Situace | Ano | Ne |
|---|---|---|
| Ranní notifikace | „Noc je tady. 87.“ | „Dobré ráno! Tvoje spánková data jsou připravena ✨“ |
| Špatná noc | „4 h 12. Zombie mód.“ | „Nevadí, zítra to bude lepší!“ |
| Výzva | „Jakub tě vyzval. 7 dní, prohraný platí pivo.“ | „Nová výzva čeká na tvou odpověď!“ |
| Prohra | „Jakub bere tvoji duši.“ | „Bohužel jsi tentokrát prohrál.“ |
| Chybějící noc ve výzvě | „Včera nic. Zatím 0, dá se dohrát.“ | „Zapomněl jsi synchronizovat zařízení.“ |
| Konec výzvy | „Zítra konec. Prohráváš o 3,2 bodu.“ | „Výzva se blíží ke konci, nevzdávej to!“ |
| Opakovaný odznak | „Hlubinář. Zase.“ | „Gratulujeme, opět jsi získal odznak!“ |

## Pohyb
- Výchozí systémové přechody. Pružina jen u reakce (lehký „pop“) a u počítání skóre (číslo naběhne při prvním zobrazení karty, 0,6 s).
- Žádné parallaxy, žádné pulzující prvky, žádné skeletony s třpytem – načítání = jemná šedá plocha.

## Přístupnost
- Kontrast textu min. 4,5:1 (`textSecondary` na `bg` = ~7:1).
- Dynamic type pro `body` a `caption`; čísla (`score*`) mají pevnou velikost, ale škálují do `.accessibility1`.
- VoiceOver: hypnogram čte souhrn („7 h 42 min, z toho hluboký spánek 1 h 10“).

## Otevřené
- Název appky a ikona appky.
- Vlastní glyfy reakcí a odznaků – nakreslit (zatím SF Symbols: `moon.zzz`, `hand.raised`, `mug`, `cup.and.saucer`, `crown`).
