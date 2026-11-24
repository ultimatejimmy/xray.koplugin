return {
    -- Author Only
    author_only = [[
Identifikuj autora knihy "%s" a uveď jeho životopis.
Metadata naznačují, že autorem je "%s".

KRITICKÉ: Ověř autora pomocí "BOOK TEXT CONTEXT" (kontext textu knihy, pokud je uveden na konci této výzvy), abys zajistil 100%% přesnost a vyhnul se nesprávné identifikaci.

POŽADOVANÝ FORMÁT JSON:
{
  "author": "Správné celé jméno",
  "author_bio": "Podrobný životopis se zaměřením na literární kariéru a hlavní díla.",
  "author_birth": "Datum narození ve formátu podle místních zvyklostí",
  "author_death": "Datum úmrtí ve formátu podle místních zvyklostí"
}]],

    -- Find Duplicates
    find_duplicates = [[
Kniha: %s
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

    -- Comprehensive Xray
    comprehensive_xray = [[
Kniha: %s
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
}]],

    -- More Characters
    more_characters = [[
Kniha: %s
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

    -- More Terms
    more_terms = [[
Kniha: %s
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

    -- Single Word Lookup
    single_word_lookup = [[
Uživatel označil slovo "%s".
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

    -- Merge Descriptions
    merge_descriptions = [[
ÚKOL: Spoj následující dva popisy téže entity (postavy nebo místa) do jednoho soudržného a stručného shrnutí.
Odstraň nadbytečné informace a zajisti, aby výsledný popis plynul přirozeně.

Hlavní popis: %s
Vedlejší popis: %s

POŽADOVANÝ FORMÁT JSON:
{
  "merged_description": "Spojený a uhlazený popis (max. {MAX_CHAR_DESC} znaků)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Název knihy: %s
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

    -- Series Detect
    series_detect = [[
Název knihy: %s
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

    -- Prior Book List
    prior_book_list = [[
Série: %s
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

    -- Series Book Summary
    series_book_summary = [[
CÍLOVÁ KNIHA: %s
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
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
CÍLOVÁ KNIHA: %s
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

    -- Chapter Delta
    chapter_delta = [[
Kniha: %s
Autor: %s
Analýza kapitoly: %s

ÚKOL: Analyzujte POUZE tuto jedinou kapitolu. Identifikujte NOVÉ entity představené v této kapitole a DELTA AKTUALIZACE (změny stavu) u stávajících entit.
Výstupem musí být POUZE platný objekt JSON.

SEZNAM STÁVAJÍCÍCH ZNÁMÝCH ENTIT (NEPROVÁDĚJTE opětnou extrakci, pokud se jejich role, stav nebo popis výrazně nevyvinuly):
%s

PRAVIDLA:
1. STRIKTNÍ OMEZENÍ SPOILERŮ: Analyzujte POUZE text poskytnuté kapitoly. NEPOUŽÍVEJTE žádné znalosti z budoucích kapitol ani z vnějších zdrojů.
2. HLOUBKA A SUBSTANCE POPISU POSTAV (KRITICKÉ):
   - Uzemněné a konkrétní: Popište, kdo postava je, pomocí konkrétních příběhových faktů — jejich minulosti, osobité osobnosti, profese, klíčových vztahů k jiným postavám a jejich konkrétní role a osobních sázek v příběhu.
   - Významný kontext vyprávění: Propojte postavu přímo s ústřední záhadou, zápletkovým konfliktem nebo vyšetřováním v této knize (např. jaké zločiny nebo případy vyšetřuje, kdo si ji najal, klíčoví spojenci nebo protivníci, konkrétní osobní dilemata nebo napětí).
   - NEPŮSOBIT příliš obecně: NEPÍŠTE obecné klišé popisy (např. vyhněte se prázdným formulacím typu „detektiv vyšetřující složité případy“). Pojmenujte konkrétní okolnosti, vazby a sázky stanovené v textu.
   - ŽÁDNÉ shrnování všedních pochůzek: NEPÍŠTE chronologické záznamy běžných denních činností nebo rutinních prací (např. NESHRNUJTE cesty do obchodu, rutinní telefonáty nebo vedlejší pohyby scéna po scéně).
   - Popisy postav musí být bohaté, živé profily shrnující, kdo jsou a jaký mají dosavadní význam v knize.
3. VYSOKÝ PRÁH PRO AKTUALIZACE POSTAV:
   - NEVYTVÁŘEJTE aktualizaci v `character_state_updates` pouze proto, že se stávající postava v této kapitole objevila, promluvila nebo prováděla rutinní úkony.
   - Aktualizaci generujte POUZE tehdy, pokud dojde k podstatné, trvalé proměně v jejich příběhové linii, identitě, vztazích, zaměstnání, loajalitě nebo stavu (např. zabit/a, zraněn/a, zatčen/a, zrazen/a, zasnouben/a, povýšen/a, odhalen/a jako pachatel, odhalení velkého tajemství nebo motivu).
   - Pokud JE aktualizace opodstatněná, aktualizovaný `description` musí být bohatým, kumulativním přehledem postavy, který zahrnuje nový vývoj a zároveň zachovává její základní identitu a zavedený kontext příběhu — NIKOLI shrnutím izolované scény.
4. ZNAČKY STRÁNEK UVNITŘ KAPITOLY ([PAGE N]) A STRIKTNÍ OMEZENÍ SPOILERŮ:
   - Texty kapitol obsahují značky [PAGE N] označující postup stránek.
   - Pro `new_characters`, `new_locations` a `new_terms`: uveďte "first_page" (celé číslo N ze značky [PAGE N], kde byla entita poprvé zmíněna), "intro_role" (pro postavy) a "intro_description" (1-2 věty přísně omezené na to, co je známo při prvním představení na [PAGE first_page] — s NULOVOU znalostí pozdějších zvratů, tajemství nebo výsledků na dalších stránkách). Uveďte také "page" (značku [PAGE N], kde platí úplnější kumulativní "description", obvykle poslední stránku kapitoly).
   - Pro `character_state_updates`, `location_state_updates` a `term_state_updates`: uveďte "page" (celé číslo N ze značky [PAGE N], kde je odhalení/přechod dokončen; NEODHALUJTE fakta před touto stránkou).
5. DŮKAZY: Uveďte krátký odkaz nebo citovaný výňatek z této kapitoly vysvětlující, proč k aktualizaci došlo.
6. ČASOVÁ OSA: Uveďte přesně jedno shrnutí událostí hlavního děje v této kapitole.

POŽADOVANÝ FORMÁT JSON:
{
  "new_characters": [
    {
      "name": "Celé jméno",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Počáteční role (např. Obecní písař, Cizinec, Klient)",
      "intro_description": "Počáteční dojem v 1-2 větách přísně při prvním představení, nulové spoilery z pozdějších stránek.",
      "page": 99,
      "role": "Příběhová role / význam (např. Hlavní postava, Soukromý detektiv, Partner, Antagonista, Oběť, Klient, Podezřelý, Vedlejší postava, Epizodní postava)",
      "status": "alive",
      "description": "Bohatý, konkrétní popis postavy (zázemí, vztahy, příběhové sázky). Vyhněte se obecným popisům a záznamům všedních pochůzek.",
      "evidence": "Krátký výňatek"
    }
  ],
  "character_state_updates": [
    {
      "name": "Jméno odpovídající známému seznamu",
      "page": 95,
      "role": "Aktualizovaná příběhová role / význam (např. Hlavní postava, Partner, Antagonista, Vedlejší postava atd.)",
      "status": "alive",
      "change": "Jedna krátká věta pojmenovávající, co se změnilo od předchozího stavu (např. 'Povýšen na partnera po případu Shacklewell')",
      "description": "Aktualizovaný bohatý, kumulativní popis postavy odrážející její nový stav a příběhové sázky",
      "evidence": "Krátký výňatek"
    }
  ],
  "new_locations": [
    {
      "name": "Název místa",
      "first_page": 80,
      "intro_description": "První dojem při první zmínce.",
      "page": 99,
      "description": "Popis místa",
      "evidence": "Krátký výňatek"
    }
  ],
  "location_state_updates": [
    {
      "name": "Jméno odpovídající známému seznamu",
      "page": 95,
      "change": "Jedna krátká věta pojmenovávající, co se změnilo (např. 'Zničeno během bitvy o Oakhaven')",
      "description": "Aktualizovaný vyvinutý popis",
      "evidence": "Krátký výňatek"
    }
  ],
  "new_terms": [
    {
      "name": "Název pojmu",
      "first_page": 80,
      "intro_description": "Počáteční definice při první zmínce.",
      "page": 99,
      "description": "Definice nebo vysvětlení reálií",
      "evidence": "Krátký výňatek"
    }
  ],
  "term_state_updates": [
    {
      "name": "Jméno odpovídající známému seznamu",
      "page": 95,
      "change": "Jedna krátká věta pojmenovávající, co se změnilo v chápání nebo použití",
      "description": "Aktualizovaná definice",
      "evidence": "Krátký výňatek"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Shrnutí událostí v této kapitole"
  }
}

TEXT KAPITOLY:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Kniha: %s
Autor: %s
Kapitoly v této dávce: %s

ÚKOL: Analyzujte poskytnutou sekvenční dávku kapitol popořadě.
Pro KAŽDOU kapitolu v dávce určete:
1. NOVÉ entity představené v dané kapitole (postavy, lokace, pojmy).
2. ZMĚNY STAVU (přechody stavu) u stávajících známých entit (z přehledu NEBO představených v dřívější kapitole této dávky) POUZE A JEDINĚ TEHDY, pokud jejich role, stav, loajalita nebo narativní situace prošly podstatnou a trvalou proměnou.
3. UDÁLOST NA ČASOVÉ OSE: Stručné shrnutí hlavních dějových událostí v dané kapitole.

Na výstupu uveďte POUZE platný JSON objekt odpovídající požadovanému schématu.

PŘEHLED STÁVAJÍCÍCH ZNÁMÝCH ENTIT (z předchozích dávek – NEEXTRAHUJTE znovu, pokud se jejich role, stav nebo popis výrazně nevyvinuly):
%s

PRAVIDLA:
1. STRIKTNÍ OMEZENÍ SPOILERŮ A SEKVENČNÍ POSTUP:
   - Analyzujte kapitoly v sekvenčním pořadí.
   - U jakékoli kapitoly v této dávce NEZAHRNUJTE poznatky z pozdějších kapitol v dávce ani ze zbytku knihy.
2. HLOUBKA A PODSTATA POPISU POSTAVY (KRITICKÉ):
   - Ukotvenost a specifičnost: Popište, kdo postava je, pomocí konkrétních faktů z příběhu – její zázemí, osobitá osobnost, profese, klíčové vztahy k ostatním postavám a její konkrétní role a osobní sázky v vyprávění.
   - Významný narativní kontext: Propojte postavu přímo s ústřední záhadou, zápletkovým konfliktem nebo vyšetřováním v této knize (např. jaké zločiny nebo případy vyšetřuje, kdo si ji najal, klíčoví spojenci nebo protivníci, konkrétní osobní dilemata nebo napětí).
   - NEPÍŠTE příliš obecně: NEPSAT obecné klišé popisy (např. vyhněte se prázdným formulacím typu "detektiv vyšetřující složité případy"). Pojmenujte konkrétní okolnosti, spojení a sázky stanovené v textu.
   - ŽÁDNÉ shrnování triviálních pochůzek: NEPSAT chronologické záznamy všedních denních činností nebo rutinních prací (např. NESHROMAŽĎUJTE výlety do obchodu, rutinní telefonáty nebo náhodné pohyby scénu po scéně).
   - Popisy postav musí být bohaté, živé profily shrnující, kdo tyto postavy jsou a jaký mají význam až do tohoto místa v knize.
3. VYSOKÝ PRÁH PRO AKTUALIZACE POSTAV:
   - NEVYTVÁŘEJTE aktualizaci v `character_state_updates` jen proto, že se stávající postava v kapitole objevila, promluvila nebo prováděla rutinní úkony.
   - Aktualizaci generujte POUZE v případě, že dojde k podstatné, trvalé proměně v její narativní linii, identitě, vztazích, zaměstnání, loajalitě nebo stavu (např. zabita, zraněna, zatčena, zrazena, zasnoubena, povýšena, odhalena jako pachatel, odhaleno zásadní tajemství nebo motiv).
   - Pokud JE aktualizace opodstatněná, aktualizovaný popis `description` musí být bohatým, kumulativním přehledem postavy, který zahrnuje nový vývoj a zároveň zachovává její základní identitu a zavedený kontext příběhu – NIKOLI shrnutím izolované scény.
4. ZNAČKY STRÁNEK UVNITŘ KAPITOLY ([PAGE N]) A ZÁKAZ SPOILERŮ:
   - Texty kapitol obsahují značky [PAGE N] označující postup stránek.
   - Pro `new_characters`, `new_locations` a `new_terms`: uveďte "first_page" (celé číslo N ze značky [PAGE N], kde byla entita poprvé zmíněna), "intro_role" (pro postavy) a "intro_description" (1–2 věty striktně omezené na to, co je známo při prvním představení na [PAGE first_page] – s NULOVOU znalostí pozdějších zvratů, tajemství nebo výsledků z následujících stránek). Dále uveďte "page" (značku [PAGE N], kde platí úplnější kumulativní "description", obvykle poslední stránku kapitoly).
   - Pro `character_state_updates`, `location_state_updates` a `term_state_updates`: uveďte "page" (celé číslo N ze značky [PAGE N], kde je odhalení/přechod dokončen; NEODHALUJTE fakta před touto stránkou).
5. DŮKAZY: Uveďte stručnou referenci nebo citaci z dané konkrétní kapitoly vysvětlující, proč k aktualizaci došlo.
6. BEZPEČNOST JSON: Na výstupu uveďte striktně platný JSON. Uvnitř řetězců správně používejte únikové znaky pro uvozovky.

POŽADOVANÝ FORMÁT JSON:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Název kapitoly",
      "timeline_event": "Shrnutí hlavního vývoje děje v této kapitole.",
      "new_characters": [
        {
          "name": "Jméno a příjmení",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Počáteční role (např. Obecní úředník, Cizinec, Klient)",
          "intro_description": "Počáteční dojem v 1–2 větách striktně při prvním představení, žádné spoilery z pozdějších stránek.",
          "page": 99,
          "role": "Narativní role / význam (např. Hlavní postava, Soukromý detektiv, Partner, Antagonista, Oběť, Klient, Podezřelý, Vedlejší postava, Epizodní postava)",
          "status": "alive",
          "description": "Bohatý, konkrétní popis postavy (zázemí, vztahy, narativní sázky). Vyhněte se obecným popisům a záznamům triviálních pochůzek.",
          "evidence": "Stručný výňatek"
        }
      ],
      "character_state_updates": [
        {
          "name": "Jméno odpovídající známému přehledu nebo postavě představené v dřívější kapitole této dávky",
          "page": 95,
          "role": "Aktualizovaná narativní role / význam (např. Hlavní postava, Partner, Antagonista, Vedlejší postava atd.)",
          "status": "alive",
          "change": "Jedna krátká věta pojmenovávající, co se změnilo od předchozího stavu (např. 'Povýšen na partnera po případu Shacklewell')",
          "description": "Aktualizovaný bohatý, kumulativní popis postavy odrážející její nový stav a sázky v příběhu",
          "evidence": "Stručný výňatek"
        }
      ],
      "new_locations": [
        {
          "name": "Název lokace",
          "first_page": 80,
          "intro_description": "Počáteční dojem při první zmínce.",
          "page": 99,
          "description": "Popis lokace",
          "evidence": "Stručný výňatek"
        }
      ],
      "location_state_updates": [
        {
          "name": "Jméno odpovídající známému přehledu nebo lokaci představené v dřívější kapitole této dávky",
          "page": 95,
          "change": "Jedna krátká věta pojmenovávající, co se změnilo (např. 'Zničeno během bitvy o Oakhaven')",
          "description": "Aktualizovaný popis",
          "evidence": "Stručný výňatek"
        }
      ],
      "new_terms": [
        {
          "name": "Název pojmu",
          "first_page": 80,
          "intro_description": "Počáteční definice při první zmínce.",
          "page": 99,
          "description": "Definice nebo vysvětlení kontextu/světa",
          "evidence": "Stručný výňatek"
        }
      ],
      "term_state_updates": [
        {
          "name": "Jméno odpovídající známému přehledu nebo pojmu představenému v dřívější kapitole této dávky",
          "page": 95,
          "change": "Jedna krátká věta pojmenovávající, co se změnilo v chápání nebo použití",
          "description": "Aktualizovaná definice",
          "evidence": "Stručný výňatek"
        }
      ]
    }
  ]
}

TEXTY KAPITOL V TÉTO DÁVCE:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Proanalyzujte následující podrobnosti o knize a obsah:

Název: %s
Autor: %s
Témata: %s
Popis: %s

Obsah:
%s

Určete, zda je toto dílo:
1. "anthology" (sbírka nezávislých povídek, esejů nebo novel, z nichž každá má svůj vlastní samostatný příběh nebo postavy, např. "Dobrodružství Sherlocka Holmese", "Dubliňané", "Výdech", "Muži bez žen").
2. "novel" (jediný ucelený román rozdělený do kapitol, částí nebo dějství, např. "Pýcha a předsudek", "Harry Potter", "Duna", "Carrie").
3. "novel_omnibus" (vícesvazková sbírka ucelených románů vydaných společně v jednom svazku, např. "Pán prstenů: Všechny tři svazky", "Stopařův průvodce Po Galaxii: Kompletní vydání", "Percy Jackson: Knihy 1–3").
4. "non_fiction" (samostatné pojednání z oblasti literatury faktu, historie nebo akademická kniha rozdělená do kapitol).

Vraťte POUZE JSON objekt ve tvaru:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 až 1.0,
  "reasoning": "stručné vysvětlení (jedna věta)"
}]],

    -- System instruction
    system_instruction = "Jsi expert na literární výzkum. Tvoje odpověď musí být VÝHRADNĚ v platném formátu JSON. Zajisti, aby byly údaje velmi přesné a týkaly se výhradně poskytnutého kontextu.",

    -- Fallback strings
    fallback = {
        no_biography = "Životopis není k dispozici",
        no_description = "Bez popisu",
        not_specified = "Neuvedeno",
        unknown_author = "Neznámý autor",
        unknown_book = "Neznámá kniha",
        unnamed_character = "Nepojmenovaná postava",
        unnamed_person = "Nepojmenovaná osoba"
    }
}
