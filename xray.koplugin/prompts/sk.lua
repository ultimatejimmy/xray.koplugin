return {
    -- System instruction
    system_instruction = "Si expert na literárny výskum. Tvoja odpoveď musí byť VÝLUČNE v platnom formáte JSON. Zabezpeč, aby boli údaje veľmi presné a týkali sa výhradne poskytnutého kontextu.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identifikuj autora knihy "%s" a uveď jeho životopis.
Metadáta naznačujú, že autorom je "%s".

KRITICKÉ: Over autora pomocou "BOOK TEXT CONTEXT" (kontext textu knihy, ak je uvedený na konci tejto výzvy), aby si zaistil 100%% presnosť a vyhol sa nesprávnej identifikácii.

POŽADOVANÝ FORMÁT JSON:
{
  "author": "Správne celé meno",
  "author_bio": "Podrobný životopis so zameraním na literárnu kariéru a hlavné diela.",
  "author_birth": "Dátum narodenia vo formáte podľa miestnych zvyklostí",
  "author_death": "Dátum úmrtia vo formáte podľa miestnych zvyklostí"
}]],

    -- Find Duplicates (for AI-Assisted Merge)
    find_duplicates = [[Kniha: %s
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

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Kniha: %s
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
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Kniha: %s
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

    -- Fetch More Terms (Glossary Support)
    more_terms = [[Kniha: %s
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

    single_word_lookup = [[Používateľ označil slovo "%s".
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

    -- Smart Merge Descriptions
    merge_descriptions = [[ÚLOHA: Spoj nasledujúce dva popisy tej istej entity (postavy alebo miesta) do jedného súdržného a stručného zhrnutia.
Odstráň nadbytočné informácie a zabezpeč, aby výsledný popis plynul prirodzene.

Hlavný popis: %s
Vedľajší popis: %s

POŽADOVANÝ FORMÁT JSON:
{
  "merged_description": "Spojený a uhladený popis (max. {MAX_CHAR_DESC} znakov)"
}]],

    book_type_detect = [[Názov knihy: %s
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

    -- Multi-Book Series Context Prompts
    series_detect = [[Názov knihy: %s
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

    prior_book_list = [[Séria: %s
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

    series_book_summary = [[CIEĽOVÁ KNIHA: %s
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
}]] ,

    local_timeline_summary = [[CIEĽOVÁ KNIHA: %s
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

    -- Fallback strings
    fallback = {
        unknown_book = "Neznáma kniha",
        unknown_author = "Neznámy autor",
        unnamed_character = "Nepomenovaná postava",
        not_specified = "Neuvedené",
        no_description = "Bez popisu",
        unnamed_person = "Nepomenovaná osoba",
        no_biography = "Životopis nie je k dispozícii"
    }
}
