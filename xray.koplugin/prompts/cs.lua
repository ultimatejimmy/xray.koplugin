return {
    -- System instruction
    system_instruction = "Jsi expert na literární výzkum. Tvoje odpověď musí být VÝHRADNĚ v platném formátu JSON. Zajisti, aby byly údaje velmi přesné a týkaly se výhradně poskytnutého kontextu.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identifikuj autora knihy "%s" a uveď jeho životopis.
Metadata naznačují, že autorem je "%s".

KRITICKÉ: Ověř autora pomocí "BOOK TEXT CONTEXT" (kontext textu knihy, pokud je uveden na konci této výzvy), abys zajistil 100%% přesnost a vyhnul se nesprávné identifikaci.

POŽADOVANÝ FORMÁT JSON:
{
  "author": "Správné celé jméno",
  "author_bio": "Podrobný životopis se zaměřením na literární kariéru a hlavní díla.",
  "author_birth": "Datum narození ve formátu podle místních zvyklostí",
  "author_death": "Datum úmrtí ve formátu podle místních zvyklostí"
}]],

    -- Find Duplicates (for AI-Assisted Merge)
    find_duplicates = [[Kniha: %s
Autor: %s
Postup čtení: %d%%

Kontroluješ následující seznam (%s) získaný z této knihy.
Tvým úkolem je najít položky, které zjevně představují TUTÉŽ entitu uvedenou pod různými jmény.

SEZNAM:
%s

PRAVIDLA:
- Duplikát existuje, když dvě položky jednoznačně označují tutéž entitu (např. "Velká knihovna" a "Knihovna", nebo "Jan" a "Jan Novák").
- NEOZNAČUJ položky, které jsou pouze příbuzné nebo podobné, ale odlišné.
- NEOZNAČUJ položky, pokud si nejsi velmi jistý, že jde o tutéž entitu.
- Pokud neexistují žádné duplikáty, vrať prázdné pole.
- PRAVIDLO SPOILERŮ: Nepoužívej znalosti za hranicí %d%% postupu čtení.

POŽADOVANÝ FORMÁT JSON:
{
  "duplicate_pairs": [
    {
      "primary": "Jméno položky, která ZŮSTANE (úplnější nebo formálnější jméno)",
      "secondary": "Jméno položky, která bude ODSTRANĚNA",
      "reason": "Krátký důvod (max. 100 znaků)"
    }
  ]
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Kniha: %s
Autor: %s
Postup čtení: %d%%

ÚKOL: Proveď kompletní analýzu X-Ray. Vrať POUZE platný objekt JSON.

KRITICKÉ ROZDĚLENÍ POZORNOSTI:
Zpracováváš rozsáhlý dokument, přičemž na konci této výzvy jsou dva textové bloky:
1. "CHAPTER SAMPLES" (ukázky kapitol): Makrokontext knihy až po aktuální místo čtenáře.
2. "BOOK TEXT CONTEXT" (kontext textu knihy): Mikrokontext posledních 20 tisíc znaků.

PROTOKOL PROTI ZKRÁCENÍ (KRITICKÉ):
Máš přísný limit délky výstupu. Pokud "CHAPTER SAMPLES" obsahuje VÍCE NEŽ 40 kapitol (např. souborné vydání):
1. MUSÍŠ zúžit seznam postav POUZE na 10 absolutně nejdůležitějších postav.
2. MUSÍŠ zkrátit popisy postav na MAX. {MAX_CHAR_DESC} znaků.
3. MUSÍŠ zkrátit shrnutí událostí na časové ose na MAX. {MAX_TIMELINE_EVENT} znaků.
Pokud výstup u rozsáhlých knih nezkrátíš, JSON se ořízne a zpracování selže.

ALGORITMUS PRO ČASOVOU OSU (NEJVYŠŠÍ PRIORITA):
Abys nevynechal kapitoly ani si nevymýšlel události, MUSÍŠ provést přesně tento cyklus:
Krok 1. Podívej se POUZE na blok "CHAPTER SAMPLES". Urči kapitoly s dějem.
Krok 2. VYLUČ všechny úvodní a závěrečné části bez děje (např. obálka, titulní strana, copyright, obsah, věnování, poděkování, další díla autora).
Krok 3. Pro každou kapitolu s dějem, počínaje úplně první, vytvoř PŘESNĚ JEDEN objekt události v poli `timeline`.
Krok 4. Pole `chapter` se MUSÍ přesně shodovat s nadpisem kapitoly v ukázce. (Přiřazuj je striktně v pořadí.)
Krok 5. Shrň danou kapitolu v poli `event`. {TIMELINE_DETAIL_GUIDANCE} Napiš {MIN_TIMELINE_EVENT} až {MAX_TIMELINE_EVENT} znaků. NEPIŠ kratší shrnutí, pokud kapitola nemá téměř žádný obsah. NESPOJUJ kapitoly.
Krok 6. ŽÁDNÉ SPOILERY: Skonči přesně na hranici %d%%. Nezahrnuj události za tímto postupem.

ALGORITMUS PRO POSTAVY A HISTORICKÉ OSOBNOSTI:
Krok 1. Získej důležité postavy z obou textových bloků. ({NUM_CHARS} běžně, MAX. 10 u souborného vydání).
Krok 2. MUSÍŠ používat jejich CELÁ, formální jména (např. "Abraham Van Helsing"). NEPOUŽÍVEJ jako hlavní jméno neformální přezdívky.
Krok 3. Uveď nejvýše 3 alternativní jména, tituly nebo přezdívky postavy v poli `aliases`. Zahrň běžně používané křestní jméno a příjmení, pokud se používají. DŮLEŽITÉ: Pokud příjmení sdílí více postav (např. členové rodiny), NEUVÁDĚJ ho jako alias u žádné z nich.
Krok 4. Aktivně vyhledej nejvýše {NUM_HIST} VÝZNAMNÝCH SKUTEČNÝCH osob z lidských dějin (např. prezidenti, spisovatelé, generálové). Přidej je do `historical_figures`.
KRITICKÉ pro postavy a historické osobnosti:
- NEZÍSKÁVEJ postavy ani historické osobnosti zmíněné POUZE v úvodních nebo závěrečných částech bez děje (např. poděkování, životopis autora, věnování, titulní strana, copyright).
- Historické osobnosti MUSÍ být ověřené skutečné osoby se širokým historickým uznáním.
- NEZAŘAZUJ čistě fiktivní postavy do seznamu historických osobností, ani když se účastní skutečných historických událostí. Fiktivní postavy MUSÍ patřit do pole `characters`.
- POUZE u historických osobností můžeš k napsání obecného `biography` a historické `role` použít vlastní znalosti, ale pro `context_in_book` MUSÍŠ použít kontext knihy.
ŽÁDNÉ SPOILERY: Skonči přesně na hranici %d%%.

ALGORITMUS PRO MÍSTA:
Krok 1. Získej {NUM_LOCS} významných míst. ŽÁDNÉ SPOILERY: Skonči přesně na hranici %d%%.

ALGORITMUS PRO POJMY:
Krok 0. V kořeni JSON uveď "book_type" jako "fiction" (beletrie) nebo "non_fiction" (odborná literatura).
Krok 1. Pokud jde o non_fiction: získej {NUM_TERMS} významných odborných pojmů, zkratek, žargonu nebo konceptů, které by čtenář bez odborných znalostí neznal. Použij vhodné kategorie jako Zkratka, Odborný pojem, Koncept nebo Žargon.
Krok 2. Pokud jde o fiction: získej {NUM_TERMS} významných prvků světa příběhu, které by bylo potřeba novému čtenáři vysvětlit — například vymyšlené frakce, organizace, magické systémy, technologie, tvory, jazyky nebo reálie světa.
   - NEZAHRNUJ jména postav ani názvy míst (ty se sledují samostatně).
   - NEZÍSKÁVEJ běžná slova nebo koncepty ze skutečného světa.
   - Použij vhodné kategorie: Frakce, Magický systém, Technologie, Tvor, Organizace, Reálie, Jazyk.
Krok 3. Do "expanded" uveď, co zkratka/fráze znamená. Pokud nejde o zkratku/frázi, zopakuj název.
Krok 4. NEZAHRNUJ běžná každodenní slova.

PŘÍSNÁ PRAVIDLA SPOILERŮ:
- ABSOLUTNĚ ŽÁDNÉ informace za aktuálním postupem čtení. Skonči přesně na hranici %d%%.
- Popisy musí odpovídat stavu postav přesně v tomto bodě knihy.

PŘÍSNÁ PRAVIDLA ZDROJE ZNALOSTÍ (KRITICKÉ):
- Pro FIKTIVNÍ POSTAVY: Tvoje popisy MUSÍ vycházet VÝHRADNĚ z toho, co je v poskytnutém textu výslovně uvedeno nebo jasně naznačeno. NEDOPLŇUJ znalosti z předchozího trénování, externích zdrojů ani obecné povědomí o knize/sérii/autorovi.
- Pokud byla postava v textu zatím zmíněna jen letmo, tvůj popis musí odrážet pouze tyto omezené informace. NEVYVOZUJ, NEPŘEDPOKLÁDEJ ani NEPŘIDÁVEJ žádné podrobnosti, které nemají oporu v poskytnutém kontextu.
- JEDINOU výjimkou jsou SKUTEČNÉ HISTORICKÉ OSOBNOSTI (uvedené v `historical_figures`): pro jejich obecný životopis/roli můžeš použít vlastní znalosti, ale pro `context_in_book` se stále opírej o text knihy.

PŘÍSNÁ PRAVIDLA BEZPEČNOSTI JSON:
- MUSÍŠ správně escapovat všechny dvojité uvozovky (\") uvnitř řetězců.
- NEPOUŽÍVEJ neescapovaná zalomení řádků uvnitř řetězců.
- Vrať POUZE platný, zpracovatelný JSON.
- Všechny textové hodnoty piš česky; názvy klíčů JSON ponech beze změny.

POŽADOVANÝ FORMÁT JSON:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Celé formální jméno",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krátké označení archetypu (3–5 slov, např. 'Antagonista', 'Protagonista', 'Oběť')",
      "gender": "Muž / Žena / Neznámé",
      "occupation": "Povolání/postavení",
      "description": "Popis PŘÍSNĚ podle poskytnutého textu. Nevyvozuj ani nepřidávej externí znalosti. ŽÁDNÉ SPOILERY. (Max. {MAX_CHAR_DESC} znaků)"
    }
  ],
  "historical_figures": [
    {
      "name": "Jméno skutečné historické osoby",
      "role": "Historická role",
      "biography": "Krátký životopis (MAX. {MAX_HIST_BIO} znaků)",
      "importance_in_book": "Význam po aktuální postup čtení",
      "context_in_book": "Jak je v knize zmíněna (MAX. 100 znaků)"
    }
  ],
  "locations": [
    {"name": "Název místa", "description": "Krátký popis (MAX. {MAX_LOC_DESC} znaků)"}
  ],
  "terms": [
    {
      "name": "Pojem nebo zkratka",
      "expanded": "Celý význam nebo stejné jako název",
      "category": "Zkratka / Odborný pojem / Koncept / Žargon",
      "definition": "Stručná definice v kontextu (MAX. {MAX_TERM_DEF} znaků)"
    }
  ],
  "timeline": [
    {
      "chapter": "Přesný název kapitoly z ukázek",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Kniha: %s
Autor: %s
Postup čtení: %d%%

ÚKOL: Získej z textu PŘESNĚ 10 DALŠÍCH důležitých postav.
Vrať POUZE platný objekt JSON.

POŽADAVEK NA STRUČNOST (KRITICKÉ):
Aby se odpověď AI neořízla, udrž popisy postav pod {MAX_CHAR_DESC} znaků.

KRITICKÝ POKYN:
NEZAHRNUJ žádnou z následujících postav, protože již byly získány:
%s

PŘÍSNÁ PRAVIDLA SPOILERŮ:
- ABSOLUTNĚ ŽÁDNÉ informace za aktuálním postupem čtení. Skonči přesně na hranici %d%%.
- Popisy musí odpovídat stavu postav přesně v tomto bodě knihy.

POŽADOVANÝ FORMÁT JSON:
{
  "characters": [
    {
      "name": "Celé formální jméno",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krátké označení archetypu (3–5 slov, např. 'Antagonista', 'Protagonista', 'Oběť')",
      "gender": "Muž / Žena / Neznámé",
      "occupation": "Povolání/postavení",
      "description": "Popis PŘÍSNĚ podle poskytnutého textu. Nevyvozuj ani nepřidávej externí znalosti. ŽÁDNÉ SPOILERY. (Max. {MAX_CHAR_DESC} znaků)"
    }
  ]
}]],

    -- Fetch More Terms (Glossary Support)
    more_terms = [[Kniha: %s
Autor: %s
Postup čtení: %d%%

ÚKOL: Získej z textu PŘESNĚ 15 DALŠÍCH významných pojmů, zkratek, žargonu nebo konceptů.
- Pokud jde o odbornou literaturu: získej odborné pojmy, koncepty, zkratky nebo žargon.
- Pokud jde o beletrii: získej prvky světa příběhu, jako jsou frakce, organizace, magické systémy, technologie, tvorové, jazyky nebo reálie světa.
Vrať POUZE platný objekt JSON.

POŽADAVEK NA STRUČNOST (KRITICKÉ):
Aby se odpověď AI neořízla, udrž definice pojmů pod {MAX_TERM_DEF} znaků.

KRITICKÝ POKYN:
NEZAHRNUJ žádný z následujících pojmů, protože již byly získány:
%s

PŘÍSNÁ PRAVIDLA SPOILERŮ:
- ABSOLUTNĚ ŽÁDNÉ informace za aktuálním postupem čtení. Skonči přesně na hranici %d%%.

POŽADOVANÝ FORMÁT JSON:
{
  "terms": [
    {
      "name": "Pojem nebo zkratka",
      "expanded": "Celý význam nebo stejné jako název",
      "category": "Frakce / Magický systém / Technologie / Tvor / Organizace / Reálie / Jazyk / Zkratka / Odborný pojem / Koncept / Žargon",
      "definition": "Stručná definice v kontextu (MAX. {MAX_TERM_DEF} znaků)"
    }
  ]
}]],

    single_word_lookup = [[Uživatel označil slovo "%s".
ÚKOL: Urči, zda toto slovo v knize představuje postavu, místo, historickou osobnost nebo odborný pojem/zkratku.

KRITICKÉ PRO POSTAVY A MÍSTA: K identifikaci entity použij poskytnutý "BOOK TEXT CONTEXT". Pokud je slovo uvedeno v nápovědě "SEARCH TARGET" nebo "DIRECT REFERENCE", v knize na aktuální pozici SE NACHÁZÍ. Neodmítej ho jen proto, že se nenachází přesně ve vzorkovaném textu děje. Krátká jména (už od 2 písmen, např. "Oz", "Al", "Jo") jsou platná a je třeba je analyzovat. Slovo může být ve skloňovaném tvaru (např. "Petrovi" pro postavu "Petr") — v `name` vždy uveď základní tvar (1. pád).
KRITICKÉ PRO FIKTIVNÍ POSTAVY: Popiš POUZE to, co odhaluje poskytnutý text knihy. NEPOUŽÍVEJ znalosti o této postavě z předchozího trénování, ani když ji znáš ze známé série. Pokud text postavu zmiňuje jen letmo, tvůj popis musí odrážet pouze tyto omezené informace.
KRITICKÉ PRO HISTORICKÉ OSOBNOSTI: K ověření totožnosti a uvedení životopisu/role MŮŽEŠ použít vlastní znalosti, POUZE pokud jde o skutečnou, významnou historickou osobnost. Pro jejich význam v knize MUSÍŠ stále použít kontext textu.
KRITICKÉ PRO POJMY: Pokud jde o odbornou literaturu, ověř, zda je slovo odborný pojem, zkratka nebo klíčový koncept. Odborné pojmy, koncepty nebo žargon se mohou vyskytovat spíše v ukázkách kapitol než v kontextu aktuální strany — považuj je za platné, pokud je dokážeš definovat v kontextu tématu této knihy. `is_valid` nastav na false pouze tehdy, pokud fráze nemá absolutně žádný vztah k tématu této knihy.
Pokud slovo NENÍ postava, místo, historická osobnost ani odborný pojem/koncept, nastav `is_valid` na false.
Všechny textové hodnoty piš česky; názvy klíčů JSON a hodnoty pole "type" ponech beze změny.

POŽADOVANÝ FORMÁT JSON:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Celé jméno",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Krátké označení archetypu (3–5 slov, např. 'Antagonista', 'Protagonista', 'Oběť')",
    "gender": "Muž/Žena/Neznámé",
    "occupation": "Povolání",
    "description": "Krátký popis (MAX. 250 znaků)"
  },
  "error_message": ""
}

Poznámka: Pokud je type "location", item má obsahovat "name" a "description". Pokud je type "historical_figure", item má obsahovat "name", "biography" a "role". Pokud je type "term", item má obsahovat "name", "expanded", "category" a "definition".

Pokud je `is_valid` false:
{
  "is_valid": false,
  "error_message": "Krátké vysvětlení, proč nejde o postavu ani místo."
}]],

    -- Smart Merge Descriptions
    merge_descriptions = [[ÚKOL: Spoj následující dva popisy téže entity (postavy nebo místa) do jednoho soudržného a stručného shrnutí.
Odstraň nadbytečné informace a zajisti, aby výsledný popis plynul přirozeně.

Hlavní popis: %s
Vedlejší popis: %s

POŽADOVANÝ FORMÁT JSON:
{
  "merged_description": "Spojený a uhlazený popis (max. {MAX_CHAR_DESC} znaků)"
}]],

    book_type_detect = [[Název knihy: %s
Autor: %s
Série: %s
Popis souboru/metadata tématu: %s

ÚKOL: Zařaď tuto knihu na základě metadat a signálů žánru přesně do JEDNOHO z těchto typů knih:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Vrať POUZE platný JSON:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Multi-Book Series Context Prompts
    series_detect = [[Název knihy: %s
Autor: %s

ÚKOL: Urči, zda je tato kniha součástí pojmenované série.
Vrať POUZE platný JSON:
{
  "is_series": true,
  "series_name": "Kolo času",
  "book_index": 3,
  "total_books_known": 14
}
Pokud kniha NENÍ součástí série, vrať:
{ "is_series": false }]],

    prior_book_list = [[Série: %s
Pořadí aktuální knihy: %d
Název aktuální knihy: %s

ÚKOL: Vypiš názvy (a autory, pokud se liší od "%s") knih 1 až %d,
které v této sérii předcházejí aktuální knize.
Vrať POUZE platný JSON:
{
  "prior_books": [
    { "index": 1, "title": "Oko světa", "author": "Robert Jordan" }
  ]
}]],

    series_book_summary = [[CÍLOVÁ KNIHA: %s
AUTOR: %s
POŘADÍ CÍLOVÉ KNIHY: %d
SÉRIE: %s

ÚKOL:
Poskytni ÚPLNÉ shrnutí POUZE CÍLOVÉ KNIHY pro čtenáře, který CÍLOVOU KNIHU dočetl
a chystá se začít další knihu série.

ABSOLUTNÍ HRANICE SPOILERŮ:
Hranicí znalostí je výhradně POSLEDNÍ STRANA CÍLOVÉ KNIHY (pořadí knihy %d).
Můžeš zahrnout fakta zavedená v CÍLOVÉ KNIZE nebo v dřívějších knihách této série.
NESMÍŠ zahrnout, naznačit, narážet na, předznamenat ani vybírat podrobnosti na základě znalostí z jakékoli pozdější knihy.

ZAKÁZANÉ INFORMACE Z POZDĚJŠÍCH KNIH:
- Pozdější události, budoucí osudy, úmrtí, přežití, cíle, romance, spojenectví, konflikty nebo zrady.
- Totožnosti, skutečný původ, tajné rodičovství, aliasy, alter ega, reinkarnace, proměny, tituly nebo růst schopností z pozdějších knih (např. NEZMIŇUJ, zda se podstata spojí s jinou nebo se v budoucí knize znovuzrodí).
- Odhalení, potvrzení, nové výklady, zvraty nebo pojmy světa zavedené v pozdějších knihách.
- Zpětné předznamenávání nebo fráze jako "později", "nakonec", "stane se", "v dalších knihách" a podobné.
- Zmiňování postav, konceptů, organizací nebo chronologie z pozdějších knih.

HRANICE PRO POSTAVY:
Každou postavu popiš výhradně tak, jak je známa na poslední straně CÍLOVÉ KNIHY.
NEPOUŽÍVEJ aliasy, role, vztahy, skutečné totožnosti ani stavy odhalené v pozdějších knihách.

PRAVIDLO NEJISTOTY:
Pokud nedokážeš s jistotou určit, zda byl fakt nebo alias zaveden do konce CÍLOVÉ KNIHY, VYNECH HO.
Chybějící podrobnost je mnohem lepší než spoiler z budoucí knihy.

ZÁVĚREČNÁ KONTROLA:
Před vrácením JSON zkontroluj každé pole (zejména popisy postav a aliasy) a odstraň vše, co závisí na znalostech z knih po CÍLOVÉ KNIZE.

Všechny textové hodnoty piš česky; názvy klíčů JSON ponech beze změny.

POŽADOVANÝ FORMÁT JSON:
{
  "characters": [
    { "name": "Celé jméno", "aliases": [], "role": "...", "description": "Stav na konci této knihy (max. {MAX_CHAR_DESC} znaků)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Shrnutí knihy", "event": "Jedno velmi podrobné, komplexní shrnutí děje celé knihy, hlavních událostí a rozuzlení (max. 2000 znaků). Toto shrnutí MUSÍŠ kvůli čitelnosti rozdělit do více samostatných odstavců oddělených dvojitým zalomením řádku (\\n\\n), ne do jednoho souvislého bloku textu." }
  ]
}]] ,

    local_timeline_summary = [[CÍLOVÁ KNIHA: %s
AUTOR: %s
POŘADÍ CÍLOVÉ KNIHY: %d
SÉRIE: %s

ÚKOL:
S použitím POUZE níže uvedených ověřených událostí CÍLOVÉ KNIHY po kapitolách napiš soudržné, komplexní shrnutí děje celé knihy, klíčového vývoje a rozuzlení.

PŘÍSNÉ OMEZENÍ NA ZDROJ:
- Shrnutí zakládej VÝHRADNĚ na poskytnutých událostech kapitol.
- NEPŘIDÁVEJ fakta, postavy, události ani výsledky, které v těchto událostech kapitol nejsou popsány.
- NIKDY nezmiňuj ani nepředznamenávej události, úmrtí či vývoj z pozdějších knih série.

UDÁLOSTI KAPITOL:
%s

POŽADOVANÝ FORMÁT JSON:
{
  "timeline": [
    { "chapter": "Shrnutí knihy", "event": "Jedno velmi podrobné, komplexní shrnutí děje celé knihy a jejího rozuzlení (max. 2000 znaků). Toto shrnutí MUSÍŠ kvůli čitelnosti rozdělit do více samostatných odstavců oddělených dvojitým zalomením řádku (\\n\\n), ne do jednoho souvislého bloku textu." }
  ]
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Neznámá kniha",
        unknown_author = "Neznámý autor",
        unnamed_character = "Nepojmenovaná postava",
        not_specified = "Neuvedeno",
        no_description = "Bez popisu",
        unnamed_person = "Nepojmenovaná osoba",
        no_biography = "Životopis není k dispozici"
    }
}
