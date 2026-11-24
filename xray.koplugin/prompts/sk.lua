return {
    -- Author Only
    author_only = [[
Identifikuj autora knihy "%s" a uveď jeho životopis.
Metadáta naznačujú, že autorom je "%s".

KRITICKÉ: Over autora pomocou "BOOK TEXT CONTEXT" (kontext textu knihy, ak je uvedený na konci tejto výzvy), aby si zaistil 100%% presnosť a vyhol sa nesprávnej identifikácii.

POŽADOVANÝ FORMÁT JSON:
{
  "author": "Správne celé meno",
  "author_bio": "Podrobný životopis so zameraním na literárnu kariéru a hlavné diela.",
  "author_birth": "Dátum narodenia vo formáte podľa miestnych zvyklostí",
  "author_death": "Dátum úmrtia vo formáte podľa miestnych zvyklostí"
}]],

    -- Find Duplicates
    find_duplicates = [[
Kniha: %s
Autor: %s
Postup čítania: %d%%

Kontroluješ nasledujúci zoznam (%s) získaný z tejto knihy.
Tvojou úlohou je nájsť položky, ktoré zjavne predstavujú TÚ ISTÚ entitu uvedenú pod rôznymi menami.

ZOZNAM:
%s

PRAVIDLÁ:
- Duplikát existuje, keď dve položky jednoznačne označujú tú istú entitu (napr. "Veľká knižnica" a "Knižnica", alebo "Ján" a "Ján Novák").
- NEOZNAČUJ položky, ktoré sú iba príbuzné alebo podobné, ale odlišné.
- NEOZNAČUJ položky, pokiaľ si nie si veľmi istý, že ide o tú istú entitu.
- Ak neexistujú žiadne duplikáty, vráť prázdne pole.
- PRAVIDLO SPOILEROV: Nepoužívaj znalosti za hranicou %d%% postupu čítania.

POŽADOVANÝ FORMÁT JSON:
{
  "duplicate_pairs": [
    {
      "primary": "Meno položky, ktorá ZOSTANE (úplnejšie alebo formálnejšie meno)",
      "secondary": "Meno položky, ktorá sa ODSTRÁNI",
      "reason": "Krátky dôvod (max. 100 znakov)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Kniha: %s
Autor: %s
Postup čítania: %d%%

ÚLOHA: Vykonaj kompletnú analýzu X-Ray. Vráť IBA platný objekt JSON.

KRITICKÉ ROZDELENIE POZORNOSTI:
Spracúvaš rozsiahly dokument, pričom na konci tejto výzvy sú dva textové bloky:
1. "CHAPTER SAMPLES" (ukážky kapitol): Makrokontext knihy až po aktuálne miesto čitateľa.
2. "BOOK TEXT CONTEXT" (kontext textu knihy): Mikrokontext posledných 20 tisíc znakov.

PROTOKOL PROTI SKRÁTENIU (KRITICKÉ):
Máš prísny limit dĺžky výstupu. Ak "CHAPTER SAMPLES" obsahuje VIAC AKO 40 kapitol (napr. súborné vydanie):
1. MUSÍŠ zúžiť zoznam postáv IBA na 10 absolútne najdôležitejších postáv.
2. MUSÍŠ skrátiť popisy postáv na MAX. {MAX_CHAR_DESC} znakov.
3. MUSÍŠ skrátiť zhrnutia udalostí na časovej osi na MAX. {MAX_TIMELINE_EVENT} znakov.
Ak výstup pri rozsiahlych knihách neskrátiš, JSON sa oreže a spracovanie zlyhá.

ALGORITMUS PRE ČASOVÚ OS (NAJVYŠŠIA PRIORITA):
Aby si nevynechal kapitoly ani si nevymýšľal udalosti, MUSÍŠ vykonať presne tento cyklus:
Krok 1. Pozri sa IBA na blok "CHAPTER SAMPLES". Urči kapitoly s dejom.
Krok 2. VYLÚČ všetky úvodné a záverečné časti bez deja (napr. obálka, titulná strana, copyright, obsah, venovanie, poďakovanie, ďalšie diela autora).
Krok 3. Pre každú kapitolu s dejom, počnúc úplne prvou, vytvor PRESNE JEDEN objekt udalosti v poli `timeline`.
Krok 4. Pole `chapter` sa MUSÍ presne zhodovať s nadpisom kapitoly v ukážke. (Priraďuj ich striktne v poradí.)
Krok 5. Zhrň danú kapitolu v poli `event`. {TIMELINE_DETAIL_GUIDANCE} Napíš {MIN_TIMELINE_EVENT} až {MAX_TIMELINE_EVENT} znakov. NEPÍŠ kratšie zhrnutie, pokiaľ kapitola nemá takmer žiadny obsah. NESPÁJAJ kapitoly.
Krok 6. ŽIADNE SPOILERY: Skonči presne na hranici %d%%. Nezahŕňaj udalosti za týmto postupom.

ALGORITMUS PRE POSTAVY A HISTORICKÉ OSOBNOSTI:
Krok 1. Získaj dôležité postavy z oboch textových blokov. ({NUM_CHARS} bežne, MAX. 10 pri súbornom vydaní).
Krok 2. MUSÍŠ používať ich CELÉ, formálne mená (napr. "Abraham Van Helsing"). NEPOUŽÍVAJ ako hlavné meno neformálne prezývky.
Krok 3. Uveď najviac 3 alternatívne mená, tituly alebo prezývky postavy v poli `aliases`. Zahrň bežne používané krstné meno a priezvisko, ak sa používajú. DÔLEŽITÉ: Ak priezvisko zdieľa viac postáv (napr. členovia rodiny), NEUVÁDZAJ ho ako alias pri žiadnej z nich.
Krok 4. Aktívne vyhľadaj najviac {NUM_HIST} VÝZNAMNÝCH SKUTOČNÝCH osôb z ľudských dejín (napr. prezidenti, spisovatelia, generáli). Pridaj ich do `historical_figures`.
KRITICKÉ pre postavy a historické osobnosti:
- NEZÍSKAVAJ postavy ani historické osobnosti spomenuté IBA v úvodných alebo záverečných častiach bez deja (napr. poďakovanie, životopis autora, venovanie, titulná strana, copyright).
- Historické osobnosti MUSIA byť overené skutočné osoby so širokým historickým uznaním.
- NEZARAĎUJ čisto fiktívne postavy do zoznamu historických osobností, ani keď sa zúčastňujú skutočných historických udalostí. Fiktívne postavy MUSIA patriť do poľa `characters`.
- IBA pri historických osobnostiach môžeš na napísanie všeobecného `biography` a historickej `role` použiť vlastné znalosti, ale pre `context_in_book` MUSÍŠ použiť kontext knihy.
ŽIADNE SPOILERY: Skonči presne na hranici %d%%.

ALGORITMUS PRE MIESTA:
Krok 1. Získaj {NUM_LOCS} významných miest. ŽIADNE SPOILERY: Skonči presne na hranici %d%%.

ALGORITMUS PRE POJMY:
Krok 0. V koreni JSON uveď "book_type" ako "fiction" (beletria) alebo "non_fiction" (odborná literatúra).
Krok 1. Ak ide o non_fiction: získaj {NUM_TERMS} významných odborných pojmov, skratiek, žargónu alebo konceptov, ktoré by čitateľ bez odborných znalostí nepoznal. Použi vhodné kategórie ako Skratka, Odborný pojem, Koncept alebo Žargón.
Krok 2. Ak ide o fiction: získaj {NUM_TERMS} významných prvkov sveta príbehu, ktoré by novému čitateľovi bolo treba vysvetliť — napríklad vymyslené frakcie, organizácie, magické systémy, technológie, tvory, jazyky alebo reálie sveta.
   - NEZAHŔŇAJ mená postáv ani názvy miest (tie sa sledujú samostatne).
   - NEZÍSKAVAJ bežné slová alebo koncepty zo skutočného sveta.
   - Použi vhodné kategórie: Frakcia, Magický systém, Technológia, Tvor, Organizácia, Reálie, Jazyk.
Krok 3. Do "expanded" uveď, čo skratka/fráza znamená. Ak nejde o skratku/frázu, zopakuj názov.
Krok 4. NEZAHŔŇAJ bežné každodenné slová.

PRÍSNE PRAVIDLÁ SPOILEROV:
- ABSOLÚTNE ŽIADNE informácie spoza aktuálneho postupu čítania. Skonči presne na hranici %d%%.
- Popisy musia zodpovedať stavu postáv presne v tomto bode knihy.

PRÍSNE PRAVIDLÁ ZDROJA ZNALOSTÍ (KRITICKÉ):
- Pre FIKTÍVNE POSTAVY: Tvoje popisy MUSIA vychádzať VÝLUČNE z toho, čo je v poskytnutom texte výslovne uvedené alebo jasne naznačené. NEDOPĹŇAJ znalosti z predchádzajúceho trénovania, externých zdrojov ani všeobecné povedomie o knihe/sérii/autorovi.
- Ak bola postava v texte zatiaľ spomenutá iba letmo, tvoj popis musí odrážať iba tieto obmedzené informácie. NEVYVODZUJ, NEPREDPOKLADAJ ani NEPRIDÁVAJ žiadne podrobnosti, ktoré nemajú oporu v poskytnutom kontexte.
- JEDINOU výnimkou sú SKUTOČNÉ HISTORICKÉ OSOBNOSTI (uvedené v `historical_figures`): pre ich všeobecný životopis/rolu môžeš použiť vlastné znalosti, ale pre `context_in_book` sa stále opieraj o text knihy.

PRÍSNE PRAVIDLÁ BEZPEČNOSTI JSON:
- MUSÍŠ správne escapovať všetky dvojité úvodzovky (\") vnútri reťazcov.
- NEPOUŽÍVAJ neescapované zalomenia riadkov vnútri reťazcov.
- Vráť IBA platný, spracovateľný JSON.
- Všetky textové hodnoty píš po slovensky; názvy kľúčov JSON nechaj bez zmeny.

POŽADOVANÝ FORMÁT JSON:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Celé formálne meno",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krátke označenie archetypu (3–5 slov, napr. 'Antagonista', 'Protagonista', 'Obeť')",
      "gender": "Muž / Žena / Neznáme",
      "occupation": "Povolanie/postavenie",
      "description": "Popis PRÍSNE podľa poskytnutého textu. Nevyvodzuj ani nepridávaj externé znalosti. ŽIADNE SPOILERY. (Max. {MAX_CHAR_DESC} znakov)"
    }
  ],
  "historical_figures": [
    {
      "name": "Meno skutočnej historickej osoby",
      "role": "Historická rola",
      "biography": "Krátky životopis (MAX. {MAX_HIST_BIO} znakov)",
      "importance_in_book": "Význam po aktuálny postup čítania",
      "context_in_book": "Ako je v knihe spomenutá (MAX. 100 znakov)"
    }
  ],
  "locations": [
    {"name": "Názov miesta", "description": "Krátky popis (MAX. {MAX_LOC_DESC} znakov)"}
  ],
  "terms": [
    {
      "name": "Pojem alebo skratka",
      "expanded": "Celý význam alebo rovnaké ako názov",
      "category": "Skratka / Odborný pojem / Koncept / Žargón",
      "definition": "Stručná definícia v kontexte (MAX. {MAX_TERM_DEF} znakov)"
    }
  ],
  "timeline": [
    {
      "chapter": "Presný názov kapitoly z ukážok",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Kniha: %s
Autor: %s
Postup čítania: %d%%

ÚLOHA: Získaj z textu PRESNE 10 ĎALŠÍCH dôležitých postáv.
Vráť IBA platný objekt JSON.

POŽIADAVKA NA STRUČNOSŤ (KRITICKÉ):
Aby sa odpoveď AI neorezala, udrž popisy postáv pod {MAX_CHAR_DESC} znakov.

KRITICKÝ POKYN:
NEZAHŔŇAJ žiadnu z nasledujúcich postáv, pretože už boli získané:
%s

PRÍSNE PRAVIDLÁ SPOILEROV:
- ABSOLÚTNE ŽIADNE informácie spoza aktuálneho postupu čítania. Skonči presne na hranici %d%%.
- Popisy musia zodpovedať stavu postáv presne v tomto bode knihy.

POŽADOVANÝ FORMÁT JSON:
{
  "characters": [
    {
      "name": "Celé formálne meno",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krátke označenie archetypu (3–5 slov, napr. 'Antagonista', 'Protagonista', 'Obeť')",
      "gender": "Muž / Žena / Neznáme",
      "occupation": "Povolanie/postavenie",
      "description": "Popis PRÍSNE podľa poskytnutého textu. Nevyvodzuj ani nepridávaj externé znalosti. ŽIADNE SPOILERY. (Max. {MAX_CHAR_DESC} znakov)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Kniha: %s
Autor: %s
Postup čítania: %d%%

ÚLOHA: Získaj z textu PRESNE 15 ĎALŠÍCH významných pojmov, skratiek, žargónu alebo konceptov.
- Ak ide o odbornú literatúru: získaj odborné pojmy, koncepty, skratky alebo žargón.
- Ak ide o beletriu: získaj prvky sveta príbehu, ako sú frakcie, organizácie, magické systémy, technológie, tvory, jazyky alebo reálie sveta.
Vráť IBA platný objekt JSON.

POŽIADAVKA NA STRUČNOSŤ (KRITICKÉ):
Aby sa odpoveď AI neorezala, udrž definície pojmov pod {MAX_TERM_DEF} znakov.

KRITICKÝ POKYN:
NEZAHŔŇAJ žiadny z nasledujúcich pojmov, pretože už boli získané:
%s

PRÍSNE PRAVIDLÁ SPOILEROV:
- ABSOLÚTNE ŽIADNE informácie spoza aktuálneho postupu čítania. Skonči presne na hranici %d%%.

POŽADOVANÝ FORMÁT JSON:
{
  "terms": [
    {
      "name": "Pojem alebo skratka",
      "expanded": "Celý význam alebo rovnaké ako názov",
      "category": "Frakcia / Magický systém / Technológia / Tvor / Organizácia / Reálie / Jazyk / Skratka / Odborný pojem / Koncept / Žargón",
      "definition": "Stručná definícia v kontexte (MAX. {MAX_TERM_DEF} znakov)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
Používateľ označil slovo "%s".
ÚLOHA: Urči, či toto slovo v knihe predstavuje postavu, miesto, historickú osobnosť alebo odborný pojem/skratku.

KRITICKÉ PRE POSTAVY A MIESTA: Na identifikáciu entity použi poskytnutý "BOOK TEXT CONTEXT". Ak je slovo uvedené v náznaku "SEARCH TARGET" alebo "DIRECT REFERENCE", v knihe na aktuálnej pozícii SA NACHÁDZA. Neodmietaj ho len preto, že sa nenachádza presne v navzorkovanom texte deja. Krátke mená (už od 2 písmen, napr. "Oz", "Al", "Jo") sú platné a treba ich analyzovať. Slovo môže byť v skloňovanom tvare (napr. "Petrovi" pre postavu "Peter") — v `name` vždy uveď základný tvar (1. pád).
KRITICKÉ PRE FIKTÍVNE POSTAVY: Opíš IBA to, čo odhaľuje poskytnutý text knihy. NEPOUŽÍVAJ znalosti o tejto postave z predchádzajúceho trénovania, ani keď ju poznáš zo známej série. Ak text postavu spomína iba letmo, tvoj popis musí odrážať iba tieto obmedzené informácie.
KRITICKÉ PRE HISTORICKÉ OSOBNOSTI: Na overenie totožnosti a uvedenie životopisu/role MÔŽEŠ použiť vlastné znalosti, IBA ak ide o skutočnú, významnú historickú osobnosť. Pre ich význam v knihe MUSÍŠ stále použiť kontext textu.
KRITICKÉ PRE POJMY: Ak ide o odbornú literatúru, over, či je slovo odborný pojem, skratka alebo kľúčový koncept. Odborné pojmy, koncepty alebo žargón sa môžu vyskytovať skôr v ukážkach kapitol než v kontexte aktuálnej strany — považuj ich za platné, ak ich vieš definovať v kontexte témy tejto knihy. `is_valid` nastav na false iba vtedy, ak fráza nemá absolútne žiadny vzťah k téme tejto knihy.
Ak slovo NIE JE postava, miesto, historická osobnosť ani odborný pojem/koncept, nastav `is_valid` na false.
Všetky textové hodnoty píš po slovensky; názvy kľúčov JSON a hodnoty poľa "type" nechaj bez zmeny.

POŽADOVANÝ FORMÁT JSON:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Celé meno",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Krátke označenie archetypu (3–5 slov, napr. 'Antagonista', 'Protagonista', 'Obeť')",
    "gender": "Muž/Žena/Neznáme",
    "occupation": "Povolanie",
    "description": "Krátky popis (MAX. 250 znakov)"
  },
  "error_message": ""
}

Poznámka: Ak je type "location", item má obsahovať "name" a "description". Ak je type "historical_figure", item má obsahovať "name", "biography" a "role". Ak je type "term", item má obsahovať "name", "expanded", "category" a "definition".

Ak je `is_valid` false:
{
  "is_valid": false,
  "error_message": "Krátke vysvetlenie, prečo nejde o postavu ani miesto."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
ÚLOHA: Spoj nasledujúce dva popisy tej istej entity (postavy alebo miesta) do jedného súdržného a stručného zhrnutia.
Odstráň nadbytočné informácie a zabezpeč, aby výsledný popis plynul prirodzene.

Hlavný popis: %s
Vedľajší popis: %s

POŽADOVANÝ FORMÁT JSON:
{
  "merged_description": "Spojený a uhladený popis (max. {MAX_CHAR_DESC} znakov)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Názov knihy: %s
Autor: %s
Séria: %s
Popis súboru/metadáta témy: %s

ÚLOHA: Zaraď túto knihu na základe metadát a signálov žánru presne do JEDNÉHO z týchto typov kníh:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Vráť IBA platný JSON:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Názov knihy: %s
Autor: %s

ÚLOHA: Urči, či je táto kniha súčasťou pomenovanej série.
Vráť IBA platný JSON:
{
  "is_series": true,
  "series_name": "Koleso času",
  "book_index": 3,
  "total_books_known": 14
}
Ak kniha NIE JE súčasťou série, vráť:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Séria: %s
Poradie aktuálnej knihy: %d
Názov aktuálnej knihy: %s

ÚLOHA: Vypíš názvy (a autorov, ak sa líšia od "%s") kníh 1 až %d,
ktoré v tejto sérii predchádzajú aktuálnej knihe.
Vráť IBA platný JSON:
{
  "prior_books": [
    { "index": 1, "title": "Oko sveta", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
CIEĽOVÁ KNIHA: %s
AUTOR: %s
PORADIE CIEĽOVEJ KNIHY: %d
SÉRIA: %s

ÚLOHA:
Poskytni ÚPLNÉ zhrnutie IBA CIEĽOVEJ KNIHY pre čitateľa, ktorý CIEĽOVÚ KNIHU dočítal
a chystá sa začať ďalšiu knihu série.

ABSOLÚTNA HRANICA SPOILEROV:
Hranicou znalostí je výlučne POSLEDNÁ STRANA CIEĽOVEJ KNIHY (poradie knihy %d).
Môžeš zahrnúť fakty zavedené v CIEĽOVEJ KNIHE alebo v skorších knihách tejto série.
NESMIEŠ zahrnúť, naznačiť, narážať na, predznamenať ani vyberať podrobnosti na základe znalostí z akejkoľvek neskoršej knihy.

ZAKÁZANÉ INFORMÁCIE Z NESKORŠÍCH KNÍH:
- Neskoršie udalosti, budúce osudy, úmrtia, prežitia, ciele, romance, spojenectvá, konflikty alebo zrady.
- Totožnosti, skutočný pôvod, tajné rodičovstvo, aliasy, alter egá, reinkarnácie, premeny, tituly alebo rast schopností z neskorších kníh (napr. NESPOMÍNAJ, či sa podstata spojí s inou alebo sa v budúcej knihe znovuzrodí).
- Odhalenia, potvrdenia, nové výklady, zvraty alebo pojmy sveta zavedené v neskorších knihách.
- Spätné predznamenávanie alebo frázy ako "neskôr", "nakoniec", "stane sa", "v ďalších knihách" a podobné.
- Spomínanie postáv, konceptov, organizácií alebo chronológie z neskorších kníh.

HRANICA PRE POSTAVY:
Každú postavu opíš výlučne tak, ako je známa na poslednej strane CIEĽOVEJ KNIHY.
NEPOUŽÍVAJ aliasy, roly, vzťahy, skutočné totožnosti ani stavy odhalené v neskorších knihách.

PRAVIDLO NEISTOTY:
Ak nevieš s istotou určiť, či bol fakt alebo alias zavedený do konca CIEĽOVEJ KNIHY, VYNECHAJ HO.
Chýbajúca podrobnosť je oveľa lepšia než spoiler z budúcej knihy.

ZÁVEREČNÁ KONTROLA:
Pred vrátením JSON skontroluj každé pole (najmä popisy postáv a aliasy) a odstráň všetko, čo závisí od znalostí z kníh po CIEĽOVEJ KNIHE.

Všetky textové hodnoty píš po slovensky; názvy kľúčov JSON nechaj bez zmeny.

POŽADOVANÝ FORMÁT JSON:
{
  "characters": [
    { "name": "Celé meno", "aliases": [], "role": "...", "description": "Stav na konci tejto knihy (max. {MAX_CHAR_DESC} znakov)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Zhrnutie knihy", "event": "Jedno veľmi podrobné, komplexné zhrnutie deja celej knihy, hlavných udalostí a rozuzlenia (max. 2000 znakov). Toto zhrnutie MUSÍŠ kvôli čitateľnosti rozdeliť do viacerých samostatných odsekov oddelených dvojitým zalomením riadka (\\n\\n), nie do jedného súvislého bloku textu." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
CIEĽOVÁ KNIHA: %s
AUTOR: %s
PORADIE CIEĽOVEJ KNIHY: %d
SÉRIA: %s

ÚLOHA:
S použitím IBA nižšie uvedených overených udalostí CIEĽOVEJ KNIHY po kapitolách napíš súdržné, komplexné zhrnutie deja celej knihy, kľúčového vývoja a rozuzlenia.

PRÍSNE OBMEDZENIE NA ZDROJ:
- Zhrnutie zakladaj VÝLUČNE na poskytnutých udalostiach kapitol.
- NEPRIDÁVAJ fakty, postavy, udalosti ani výsledky, ktoré v týchto udalostiach kapitol nie sú opísané.
- NIKDY nespomínaj ani nepredznamenávaj udalosti, úmrtia či vývoj z neskorších kníh série.

UDALOSTI KAPITOL:
%s

POŽADOVANÝ FORMÁT JSON:
{
  "timeline": [
    { "chapter": "Zhrnutie knihy", "event": "Jedno veľmi podrobné, komplexné zhrnutie deja celej knihy a jej rozuzlenia (max. 2000 znakov). Toto zhrnutie MUSÍŠ kvôli čitateľnosti rozdeliť do viacerých samostatných odsekov oddelených dvojitým zalomením riadka (\\n\\n), nie do jedného súvislého bloku textu." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Kniha: %s
Autor: %s
Analyzovaná kapitola: %s

ÚLOHA: Analyzuj IBA túto jedinú kapitolu. Identifikuj NOVÉ entity predstavené v tejto kapitole a ROZDIELOVÉ AKTUALIZÁCIE (zmeny stavu) pre existujúce entity.
Vráť IBA platný objekt JSON.

ZOZNAM UŽ ZNÁMYCH ENTÍT (NEVYŤAHUJ ich znova, pokiaľ sa ich rola, stav alebo popis výrazne nevyvinuli):
%s

PRAVIDLÁ:
1. PRÍSNE OBMEDZENIE SPOILEROV: Analyzuj IBA poskytnutý text kapitoly. NEPOUŽÍVAJ žiadne znalosti z budúcich kapitol ani z externých zdrojov.
2. HĹBKA A OBSAŽNOSŤ POPISOV POSTÁV (KRITICKÉ):
   - Podložené a konkrétne: Opíš, kto postava je, pomocou konkrétnych faktov z príbehu — jej zázemie, výrazná osobnosť, povolanie, kľúčové vzťahy k iným postavám, ako aj jej konkrétna úloha a osobné stávky v deji.
   - Významný naratívny kontext: Prepoj postavu priamo s ústrednou záhadou, dejovým konfliktom alebo vyšetrovaním v tejto knihe (napr. aké zločiny alebo prípady vyšetruje, kto si ju najal, kľúčoví spojenci alebo protivníci, konkrétne osobné dilemy či napätia).
   - NIE príliš všeobecné: NEPÍŠ všeobecné klišé (napr. vyhni sa prázdnym frázam ako „detektív vyšetrujúci zložité prípady“). Pomenuj konkrétne okolnosti, väzby a stávky ustanovené v texte.
   - ŽIADNE zhrnutia bežných pochôdzok: NEPÍŠ chronologické záznamy všedných denných činností alebo rutinných úloh (napr. NEZHRŇUJ nákupy v obchode, rutinné telefonáty ani nepodstatné presuny zo scény na scénu).
   - Popisy postáv musia byť bohaté, živé profily zhŕňajúce, kto sú a aký je ich význam až po tento bod knihy.
3. VYSOKÝ PRAH PRE AKTUALIZÁCIE POSTÁV:
   - NEVYTVÁRAJ aktualizáciu v `character_state_updates` len preto, že sa existujúca postava v tejto kapitole objavila, prehovorila alebo vykonala rutinné úkony.
   - Aktualizáciu vytvor IBA vtedy, ak došlo k podstatnej, trvalej premene v jej príbehovej línii, identite, vzťahoch, zamestnaní, lojalite alebo stave (napr. zabitá, zranená, zatknutá, zradená, zasnúbená, povýšená, odhalená ako páchateľ, odhalené veľké tajomstvo alebo motív).
   - Ak JE aktualizácia opodstatnená, aktualizovaný `description` musí byť bohatým, kumulatívnym prehľadom postavy, ktorý zahŕňa nový vývoj a zároveň zachováva jej základnú identitu a ustanovený kontext príbehu — NIE zhrnutím jednej izolovanej scény.
4. ZNAČKY STRÁN V RÁMCI KAPITOLY ([PAGE N]) A FILTROVANIE S NULOVÝMI SPOILERMI:
   - Texty kapitol obsahujú značky [PAGE N] označujúce postup strán.
   - Pre `new_characters`, `new_locations` a `new_terms`: uveď "first_page" (celé číslo N zo značky [PAGE N], kde bola entita prvýkrát spomenutá), "intro_role" (pre postavy) a "intro_description" (1–2 vety prísne obmedzené na to, čo je známe pri prvom predstavení na [PAGE first_page] — s NULOVOU znalosťou neskorších zvratov, tajomstiev alebo výsledkov na ďalších stranách). Uveď tiež "page" (značku [PAGE N], kde platí úplnejší kumulatívny "description", zvyčajne posledná strana kapitoly).
   - Pre `character_state_updates`, `location_state_updates` a `term_state_updates`: uveď "page" (celé číslo N zo značky [PAGE N], kde sa odhalenie/prechod završuje; NEODHAĽUJ fakty pred touto stranou).
5. DÔKAZ: Uveď krátky odkaz alebo úryvok citátu z tejto kapitoly vysvetľujúci, prečo k aktualizácii došlo.
6. ČASOVÁ OS: Uveď presne jedno zhrnutie udalostí hlavného deja v tejto kapitole.

Všetky textové hodnoty píš po slovensky; názvy kľúčov JSON nechaj bez zmeny.

POŽADOVANÝ FORMÁT JSON:
{
  "new_characters": [
    {
      "name": "Celé meno",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Počiatočná rola (napr. Obecný pisár, Cudzinec, Klient)",
      "intro_description": "Počiatočný dojem v 1–2 vetách prísne pri prvom predstavení, nulové spoilery z neskorších strán.",
      "page": 99,
      "role": "Dejová rola / dôležitosť (napr. Protagonista, Súkromný detektív, Partner, Antagonista, Obeť, Klient, Podozrivý, Vedľajšia postava, Epizódna postava)",
      "status": "alive",
      "description": "Bohatý, konkrétny popis postavy (zázemie, vzťahy, dejové stávky). Vyhni sa všeobecným frázam a záznamom bežných pochôdzok.",
      "evidence": "Krátky úryvok"
    }
  ],
  "character_state_updates": [
    {
      "name": "Meno zodpovedajúce známemu zoznamu",
      "page": 95,
      "role": "Aktualizovaná dejová rola / dôležitosť (napr. Protagonista, Partner, Antagonista, Vedľajšia postava atď.)",
      "status": "alive",
      "change": "Jedna krátka veta pomenúvajúca, čo sa zmenilo od predchádzajúceho stavu (napr. 'Povýšený na partnera po prípade Shacklewell')",
      "description": "Aktualizovaný bohatý, kumulatívny popis postavy odrážajúci jej nový stav a príbehové stávky",
      "evidence": "Krátky úryvok"
    }
  ],
  "new_locations": [
    {
      "name": "Názov miesta",
      "first_page": 80,
      "intro_description": "Počiatočný dojem pri prvej zmienke.",
      "page": 99,
      "description": "Popis miesta",
      "evidence": "Krátky úryvok"
    }
  ],
  "location_state_updates": [
    {
      "name": "Meno zodpovedajúce známemu zoznamu",
      "page": 95,
      "change": "Jedna krátka veta pomenúvajúca, čo sa zmenilo (napr. 'Zničené počas bitky o Oakhaven')",
      "description": "Aktualizovaný vyvinutý popis",
      "evidence": "Krátky úryvok"
    }
  ],
  "new_terms": [
    {
      "name": "Názov pojmu",
      "first_page": 80,
      "intro_description": "Počiatočná definícia pri prvej zmienke.",
      "page": 99,
      "description": "Definícia alebo vysvetlenie sveta",
      "evidence": "Krátky úryvok"
    }
  ],
  "term_state_updates": [
    {
      "name": "Meno zodpovedajúce známemu zoznamu",
      "page": 95,
      "change": "Jedna krátka veta pomenúvajúca, čo sa zmenilo v chápaní alebo používaní",
      "description": "Aktualizovaná definícia",
      "evidence": "Krátky úryvok"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Zhrnutie udalostí v tejto kapitole"
  }
}

TEXT KAPITOLY:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Kniha: %s
Autor: %s
Kapitoly v tejto dávke: %s

ÚLOHA: Analyzuj poskytnutú postupnú dávku kapitol v správnom poradí.
Pre KAŽDÚ kapitolu v dávke identifikuj:
1. NOVÉ entity predstavené v danej kapitole (postavy, miesta, pojmy).
2. ROZDIELOVÉ AKTUALIZÁCIE (zmeny stavu) pre už známe entity (zo zoznamu ALEBO predstavené v skoršej kapitole tejto dávky), AK A IBA AK ich rola, stav, lojalita alebo dejové postavenie prešli podstatnou, trvalou premenou.
3. UDALOSŤ ČASOVEJ OSI: Stručné zhrnutie hlavných dejových udalostí, ku ktorým v danej kapitole došlo.

Vráť IBA platný objekt JSON zodpovedajúci požadovanej schéme.

ZOZNAM UŽ ZNÁMYCH ENTÍT (z predchádzajúcich dávok — NEVYŤAHUJ ich znova, pokiaľ sa ich rola, stav alebo popis výrazne nevyvinuli):
%s

PRAVIDLÁ:
1. PRÍSNE OBMEDZENIE SPOILEROV A POSTUPNÝ PRIEBEH:
   - Analyzuj kapitoly v postupnom poradí.
   - Pre žiadnu kapitolu v tejto dávke NEPOUŽÍVAJ znalosti z neskorších kapitol dávky ani zo zvyšku knihy.
2. HĹBKA A OBSAŽNOSŤ POPISOV POSTÁV (KRITICKÉ):
   - Podložené a konkrétne: Opíš, kto postava je, pomocou konkrétnych faktov z príbehu — jej zázemie, výrazná osobnosť, povolanie, kľúčové vzťahy k iným postavám, ako aj jej konkrétna úloha a osobné stávky v deji.
   - Významný naratívny kontext: Prepoj postavu priamo s ústrednou záhadou, dejovým konfliktom alebo vyšetrovaním v tejto knihe (napr. aké zločiny alebo prípady vyšetruje, kto si ju najal, kľúčoví spojenci alebo protivníci, konkrétne osobné dilemy či napätia).
   - NIE príliš všeobecné: NEPÍŠ všeobecné klišé (napr. vyhni sa prázdnym frázam ako „detektív vyšetrujúci zložité prípady“). Pomenuj konkrétne okolnosti, väzby a stávky ustanovené v texte.
   - ŽIADNE zhrnutia bežných pochôdzok: NEPÍŠ chronologické záznamy všedných denných činností alebo rutinných úloh (napr. NEZHRŇUJ nákupy v obchode, rutinné telefonáty ani nepodstatné presuny zo scény na scénu).
   - Popisy postáv musia byť bohaté, živé profily zhŕňajúce, kto sú a aký je ich význam až po tento bod knihy.
3. VYSOKÝ PRAH PRE AKTUALIZÁCIE POSTÁV:
   - NEVYTVÁRAJ aktualizáciu v `character_state_updates` len preto, že sa existujúca postava v kapitole objavila, prehovorila alebo vykonala rutinné úkony.
   - Aktualizáciu vytvor IBA vtedy, ak došlo k podstatnej, trvalej premene v jej príbehovej línii, identite, vzťahoch, zamestnaní, lojalite alebo stave (napr. zabitá, zranená, zatknutá, zradená, zasnúbená, povýšená, odhalená ako páchateľ, odhalené veľké tajomstvo alebo motív).
   - Ak JE aktualizácia opodstatnená, aktualizovaný `description` musí byť bohatým, kumulatívnym prehľadom postavy, ktorý zahŕňa nový vývoj a zároveň zachováva jej základnú identitu a ustanovený kontext príbehu — NIE zhrnutím jednej izolovanej scény.
4. ZNAČKY STRÁN V RÁMCI KAPITOLY ([PAGE N]) A FILTROVANIE S NULOVÝMI SPOILERMI:
   - Texty kapitol obsahujú značky [PAGE N] označujúce postup strán.
   - Pre `new_characters`, `new_locations` a `new_terms`: uveď "first_page" (celé číslo N zo značky [PAGE N], kde bola entita prvýkrát spomenutá), "intro_role" (pre postavy) a "intro_description" (1–2 vety prísne obmedzené na to, čo je známe pri prvom predstavení na [PAGE first_page] — s NULOVOU znalosťou neskorších zvratov, tajomstiev alebo výsledkov na ďalších stranách). Uveď tiež "page" (značku [PAGE N], kde platí úplnejší kumulatívny "description", zvyčajne posledná strana kapitoly).
   - Pre `character_state_updates`, `location_state_updates` a `term_state_updates`: uveď "page" (celé číslo N zo značky [PAGE N], kde sa odhalenie/prechod završuje; NEODHAĽUJ fakty pred touto stranou).
5. DÔKAZ: Uveď krátky odkaz alebo úryvok citátu z príslušnej kapitoly vysvetľujúci, prečo k aktualizácii došlo.
6. BEZPEČNOSŤ JSON: Vráť prísne platný JSON. Správne escapuj dvojité úvodzovky v reťazcoch.

Všetky textové hodnoty píš po slovensky; názvy kľúčov JSON nechaj bez zmeny.

POŽADOVANÝ FORMÁT JSON:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Názov kapitoly",
      "timeline_event": "Zhrnutie hlavného dejového vývoja v tejto kapitole.",
      "new_characters": [
        {
          "name": "Celé meno",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Počiatočná rola (napr. Obecný pisár, Cudzinec, Klient)",
          "intro_description": "Počiatočný dojem v 1–2 vetách prísne pri prvom predstavení, nulové spoilery z neskorších strán.",
          "page": 99,
          "role": "Dejová rola / dôležitosť (napr. Protagonista, Súkromný detektív, Partner, Antagonista, Obeť, Klient, Podozrivý, Vedľajšia postava, Epizódna postava)",
          "status": "alive",
          "description": "Bohatý, konkrétny popis postavy (zázemie, vzťahy, dejové stávky). Vyhni sa všeobecným frázam a záznamom bežných pochôdzok.",
          "evidence": "Krátky úryvok"
        }
      ],
      "character_state_updates": [
        {
          "name": "Meno zodpovedajúce známemu zoznamu alebo postave predstavenej v skoršej kapitole tejto dávky",
          "page": 95,
          "role": "Aktualizovaná dejová rola / dôležitosť (napr. Protagonista, Partner, Antagonista, Vedľajšia postava atď.)",
          "status": "alive",
          "change": "Jedna krátka veta pomenúvajúca, čo sa zmenilo od predchádzajúceho stavu (napr. 'Povýšený na partnera po prípade Shacklewell')",
          "description": "Aktualizovaný bohatý, kumulatívny popis postavy odrážajúci jej nový stav a príbehové stávky",
          "evidence": "Krátky úryvok"
        }
      ],
      "new_locations": [
        {
          "name": "Názov miesta",
          "first_page": 80,
          "intro_description": "Počiatočný dojem pri prvej zmienke.",
          "page": 99,
          "description": "Popis miesta",
          "evidence": "Krátky úryvok"
        }
      ],
      "location_state_updates": [
        {
          "name": "Meno zodpovedajúce známemu zoznamu alebo miestu predstavenému v skoršej kapitole tejto dávky",
          "page": 95,
          "change": "Jedna krátka veta pomenúvajúca, čo sa zmenilo (napr. 'Zničené počas bitky o Oakhaven')",
          "description": "Aktualizovaný popis",
          "evidence": "Krátky úryvok"
        }
      ],
      "new_terms": [
        {
          "name": "Názov pojmu",
          "first_page": 80,
          "intro_description": "Počiatočná definícia pri prvej zmienke.",
          "page": 99,
          "description": "Definícia alebo vysvetlenie sveta",
          "evidence": "Krátky úryvok"
        }
      ],
      "term_state_updates": [
        {
          "name": "Meno zodpovedajúce známemu zoznamu alebo pojmu predstavenému v skoršej kapitole tejto dávky",
          "page": 95,
          "change": "Jedna krátka veta pomenúvajúca, čo sa zmenilo v chápaní alebo používaní",
          "description": "Aktualizovaná definícia",
          "evidence": "Krátky úryvok"
        }
      ]
    }
  ]
}

TEXTY KAPITOL V TEJTO DÁVKE:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analyzuj nasledujúce podrobnosti o knihe a obsah:

Názov: %s
Autor: %s
Témy: %s
Popis: %s

Obsah:
%s

Urči, či je toto dielo:
1. "anthology" (zbierka nezávislých poviedok, esejí alebo noviel, z ktorých každá má vlastný samostatný príbeh alebo obsadenie, napr. „Dobrodružstvá Sherlocka Holmesa“, „Dublinčania“, „Výdych“, „Muži bez žien“).
2. "novel" (jeden ucelený román rozdelený do kapitol, častí alebo dejstiev, napr. „Pýcha a predsudok“, „Harry Potter“, „Duna“, „Carrie“).
3. "novel_omnibus" (viaczväzková zbierka plnohodnotných románov vydaných spolu v jednom zväzku, napr. „Pán prsteňov: Všetky tri zväzky“, „Stopárov sprievodca galaxiou: Kompletné vydanie“, „Percy Jackson: Knihy 1–3“).
4. "non_fiction" (samostatné náučné dielo, historická alebo akademická kniha rozdelená na kapitoly).

Vráť IBA objekt JSON s týmito poľami:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 až 1.0,
  "reasoning": "stručné vysvetlenie (jedna veta)"
}]],

    -- System instruction
    system_instruction = "Si expert na literárny výskum. Tvoja odpoveď musí byť VÝLUČNE v platnom formáte JSON. Zabezpeč, aby boli údaje veľmi presné a týkali sa výhradne poskytnutého kontextu.",

    -- Fallback strings
    fallback = {
        no_biography = "Životopis nie je k dispozícii",
        no_description = "Bez popisu",
        not_specified = "Neuvedené",
        unknown_author = "Neznámy autor",
        unknown_book = "Neznáma kniha",
        unnamed_character = "Nepomenovaná postava",
        unnamed_person = "Nepomenovaná osoba"
    }
}
