return {
    -- Author Only
    author_only = [[
Azonosítsa és adja meg a(z) "%s" című könyv szerzőjének életrajzát. 
A metaadatok szerint a szerző "%s". 

FONTOS: Ellenőrizze a szerzőt a KÖNYVSZÖVEG KONTEXTUS (ha meg van adva a prompt végén) segítségével a 100%%-os pontosság biztosítása és a téves azonosítások elkerülése érdekében.

ELVÁRT JSON FORMÁTUM:
{
  "author": "Pontos teljes név",
  "author_bio": "Átfogó életrajz, különös tekintettel az irodalmi karrierre és a főbb művekre.",
  "author_birth": "Születési dátum, a helyi dátumformátumnak megfelelően formázva",
  "author_death": "Halálozási dátum, a helyi dátumformátumnak megfelelően formázva"
}]],

    -- Find Duplicates
    find_duplicates = [[
Könyv: %s
Szerző: %s
Olvasási haladás: %d%%

Ön a könyvből kinyert %s alábbi listáját tekinti át.
Az Ön feladata, hogy azonosítsa azokat a bejegyzéseket, amelyek ugyanarra az entitásra vonatkoznak, de eltérő néven szerepelnek.

LISTA:
%s

SZABÁLYOK:
- Duplikátumról beszélünk, ha két bejegyzés egyértelműen ugyanarra az entitásra utal (pl. "A Nagy Könyvtár" és "Nagy Könyvtár", vagy "John" és "John Doe").
- NE jelöljön meg olyan bejegyzéseket, amelyek csak kapcsolódnak egymáshoz vagy hasonlóak, de egyértelműen különállóak.
- NE jelöljön meg bejegyzéseket, hacsak nem biztos benne, hogy ugyanarról az entitásról van szó.
- Ha nincsenek duplikátumok, adjon vissza egy üres tömböt.
- SPOILERSZABÁLY: Ne használjon a(z) %d%%-os olvasási haladáson túli információt.

ELVÁRT JSON FORMÁTUM:
{
  "duplicate_pairs": [
    {
      "primary": "A MEGŐRZENDŐ bejegyzés neve (a teljesebb vagy hivatalosabb név)",
      "secondary": "Az ELTÁVOLÍTANDÓ bejegyzés neve",
      "reason": "Rövid indoklás (max. 100 karakter)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Book: %s
Author: %s
Reading Progress: %d%%

TASK: Perform a complete X-Ray analysis. Output ONLY a valid JSON object.

CRITICAL ATTENTION PARTITIONING:
You are processing a massive document with two text blocks provided at the end of this prompt:
1. "CHAPTER SAMPLES": This is the macro-context of the book up to the reader's current location.
2. "BOOK TEXT CONTEXT": This is the micro-context of the most recent 20k characters.

ANTI-TRUNCATION PROTOCOL (CRITICAL):
You have a strict maximum output limit. If the "CHAPTER SAMPLES" contains MORE THAN 40 chapters (e.g., an omnibus edition):
1. You MUST reduce the characters list to ONLY the top 10 absolute most important characters.
2. You MUST reduce character descriptions to MAX {MAX_CHAR_DESC} characters.
3. You MUST reduce timeline event summaries to MAX {MAX_TIMELINE_EVENT} characters.
Failure to compress your output for massive books will cause the JSON to truncate and fail.

ALGORITHM FOR TIMELINE (HIGHEST PRIORITY):
To prevent skipping chapters or hallucinating events, you MUST execute this exact loop:
Step 1. Look ONLY at the "CHAPTER SAMPLES" block. Identify the narrative chapters.
Step 2. EXCLUDE all non-narrative frontmatter and backmatter (e.g., Cover, Title Page, Copyright, Table of Contents, Dedication, Acknowledgments, Also By).
Step 3. For each narrative chapter, starting from the very first one, create EXACTLY ONE event object in the `timeline` array.
Step 4. The `chapter` field MUST exactly match the chapter header in the sample. (Map them strictly in sequential order).
Step 5. Summarize that specific chapter in the `event` field. {TIMELINE_DETAIL_GUIDANCE} Write between {MIN_TIMELINE_EVENT} and {MAX_TIMELINE_EVENT} characters. Do NOT write a shorter summary unless the chapter has almost no content. Do NOT group chapters.
Step 6. NO SPOILERS: Stop exactly at the %d%% mark. Do not include events past this progress.

ALGORITHM FOR CHARACTERS & HISTORICAL FIGURES:
Step 1. Extract important characters using both text blocks. ({NUM_CHARS} normal, MAX 10 if omnibus). Always include the main character / protagonist by name, even in first-person POV ("I"/"me") narratives where their name appears infrequently.
Step 2. You MUST use their FULL, formal names (e.g., "Abraham Van Helsing"). Do NOT use casual nicknames as the main name. Never merge or subsume a character under a possessive/relational reference (e.g., "Nicks Dad" and "Nick" are separate characters).
Step 3. Provide up to 3 alternative names, titles, or nicknames this character goes by in an `aliases` array. Include their common first name and last name if used. IMPORTANT: If a last name is shared by multiple characters (e.g., family members), DO NOT include it as an alias for either character.
Step 4. Actively scan for up to {NUM_HIST} NOTABLE REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
NO SPOILERS: Stop exactly at the %d%% mark.

ALGORITHM FOR LOCATIONS:
Step 1. Extract {NUM_LOCS} significant locations. NO SPOILERS: Stop exactly at the %d%% mark.

ALGORITHM FOR TERMS:
Step 0. Declare "book_type" as "fiction", "non_fiction", or "anthology" at the JSON root.
Step 1. If non_fiction: extract {NUM_TERMS} significant technical terms, acronyms, jargon, or concepts readers would not know without specialized knowledge. Use appropriate categories like Acronym, Technical Term, Concept, or Jargon.
Step 2. If fiction or anthology: extract {NUM_TERMS} significant world-building elements that a new reader would need explained—such as invented factions, organizations, magic systems, technologies, creatures, languages, or in-universe lore.
   - Do NOT include character names or location names (those are tracked separately).
   - DO NOT extract real-world common words or concepts.
   - Use appropriate categories: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Step 3. Include what the acronym/phrase stands for in "expanded". If not an acronym/phrase, repeat the name.
Step 4. DO NOT include common everyday words.

STRICT SPOILER RULES:
- ABSOLUTELY NO information from after the current reading progress. Stop exactly at the %d%% mark.
- Descriptions must reflect the characters' state at this exact point in the book.

STRICT KNOWLEDGE SOURCE RULES (CRITICAL):
- For FICTIONAL CHARACTERS: Your descriptions MUST be based SOLELY on what is explicitly stated or clearly implied in the provided text. Do NOT supplement with knowledge from prior training, external sources, or general awareness of the book/series/author.
- If a character has only been briefly mentioned in the text so far, your description must reflect that limited information only. Do NOT infer, assume, or add any detail not grounded in the provided context.
- The ONLY exception is for REAL HISTORICAL FIGURES (placed in `historical_figures`): you may use internal knowledge for their general biography/role, but still rely on the book text for their `context_in_book`.

STRICT JSON SAFETY RULES:
- You MUST properly escape all double quotes (") inside strings.
- Do NOT use unescaped line breaks inside strings.
- Output ONLY valid, parseable JSON.

REQUIRED JSON FORMAT:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Teljes hivatalos név",
      "aliases": ["Álnév 1", "Álnév 2"],
      "role": "Rövid archetípus címke (3-5 szó, pl. 'Antagonista', 'Főszereplő', 'Áldozat')",
      "gender": "Férfi / Nő / Ismeretlen",
      "occupation": "Foglalkozás/Státusz",
      "description": "Leírás KIZÁRÓLAG a megadott szöveg alapján. Ne következtess és ne adj hozzá külső tudást. SPOILERMENTES. (Max {MAX_CHAR_DESC} karakter)"
    }
  ],
  "historical_figures": [
    {
      "name": "Valódi történelmi személy neve",
      "role": "Történelmi szerep",
      "biography": "Rövid életrajz (MAX {MAX_HIST_BIO} karakter)",
      "importance_in_book": "Jelentőség a jelenlegi haladásig",
      "context_in_book": "Hogyan említik őket (MAX 100 karakter)"
    }
  ],
  "locations": [
    {"name": "Helyszín neve", "description": "Rövid leírás (MAX {MAX_LOC_DESC} karakter)"}
  ],
  "terms": [
    {
      "name": "Kifejezés vagy betűszó",
      "expanded": "Teljes feloldás vagy megegyezik a névvel",
      "category": "Betűszó / Szakmai kifejezés / Koncepció / Zsargon",
      "definition": "Tömör definíció a kontextusban (MAX {MAX_TERM_DEF} karakter)"
    }
  ],
  "timeline": [
    {
      "chapter": "Pontos fejezetcím a mintákból",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Könyv: %s
Szerző: %s
Olvasási haladás: %d%%

FELADAT: Nyerjen ki PONTOSAN 10 TOVÁBBI fontos szereplőt a szövegből.
KIZÁRÓLAG egy érvényes JSON objektumot adjon vissza.

TÖMÖRSÉGI MANDÁTUM (KRITIKUS):
Az AI válasz csonkításának elkerülése érdekében tartsa a szereplők leírását {MAX_CHAR_DESC} karakter alatt.

KRITIKUS UTASÍTÁS:
NE szerepeltesse a következő szereplők egyikét sem, mivel ezek már ki lettek nyerve:
%s

SZIGORÚ SPOILERSZABÁLYOK:
- ABSZOLÚT SEMMILYEN információ a jelenlegi olvasási haladás utáni részekből. Álljon meg pontosan a(z) %d%%-os jelnél.
- A leírásoknak a szereplők pontosan ezen ponton lévő állapotát kell tükrözniük a könyvben.

ELVÁRT JSON FORMÁTUM:
{
  "characters": [
    {
      "name": "Teljes hivatalos név",
      "aliases": ["Álnév 1", "Álnév 2"],
      "role": "Rövid archetípus címke (3-5 szó, pl. 'Antagonista', 'Protagonista', 'Áldozat')",
      "gender": "Férfi / Nő / Ismeretlen",
      "occupation": "Foglalkozás/Státusz",
      "description": "A leírás SZIGORÚAN a megadott szövegen alapul. Ne következtessen és ne adjon hozzá külső tudást. SEMMI SPOILER. (Max {MAX_CHAR_DESC} karakter)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Könyv: %s
Szerző: %s
Olvasási haladás: %d%%

FELADAT: Nyerjen ki PONTOSAN 15 TOVÁBBI jelentős kifejezést, akronimát, jargont vagy fogalmat a szövegből.
- Ha ez a könyv ismeretterjesztő (non-fiction): nyerjen ki technikai kifejezéseket, fogalmakat, akronimákat vagy jargont.
- Ha ez a könyv fiktív (fiction): nyerjen ki világépítési elemeket, mint például faksziókat, szervezeteket, mágiarendszereket, technológiákat, lényeket, nyelveket vagy univerzumbeli lore-t.
KIZÁRÓLAG egy érvényes JSON objektumot adjon vissza.

TÖMÖRSÉGI MANDÁTUM (KRITIKUS):
Az AI válasz csonkításának elkerülése érdekében tartsa a kifejezés-definíciókat {MAX_TERM_DEF} karakter alatt.

KRITIKUS UTASÍTÁS:
NE szerepeltesse az alábbi kifejezések egyikét sem, mivel ezeket már kinyertük:
%s

SZIGORÚ SPOILERSZABÁLYOK:
- ABSZOLÚT SEMMILYEN információ a jelenlegi olvasási haladás utáni részekből. Álljon meg pontosan a(z) %d%%-os jelnél.

ELVÁRT JSON FORMÁTUM:
{
  "terms": [
    {
      "name": "Kifejezés vagy Akronima",
      "expanded": "Teljes kibontás vagy ugyanaz, mint a név",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Definíció ringkas a kontextusban (MAX {MAX_TERM_DEF} karakter)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
A felhasználó kijelölte a(z) "%s" szót.
FELADAT: Határozza meg, hogy ez a szó Szereplőt, Helyszínt vagy Történelmi alakot jelöl-e a könyvben.

CRITICAL FOR CHARACTERS AND LOCATIONS: Use ONLY the provided "BOOK TEXT CONTEXT". Outside knowledge is strictly forbidden. Do not hallucinate.
KRITIKUS KITALÁLT SZEREPLŐK ESETÉBEN: KIZÁRÓLAG azt írja le, amit a megadott könyvszöveg feltár. NE használjon korábbi tréningekből származó ismereteket erről a szereplőről, még akkor sem, ha felismeri őt egy ismert sorozatból. Ha a szöveg csak röviden említi ezt a szereplőt, a leírásnak ezt a korlátozott információt kell tükröznie.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
Ha a szó a szövegben NEM szereplő, helyszín vagy történelmi alak, állítsa az `is_valid` mezőt false-ra.

ELVÁRT JSON FORMÁTUM:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Teljes név",
    "aliases": ["Álnév 1", "Álnév 2"],
    "role": "Rövid archetípus címke (3-5 szó, pl. 'Antagonista', 'Protagonista', 'Áldozat')",
    "gender": "Férfi/Nő/Ismeretlen",
    "occupation": "Foglalkozás",
    "description": "Rövid leírás (MAX 250 karakter)"
  },
  "error_message": ""
}

Megjegyzés: Ha a típus "location", az elemnek "name" és "description" mezőket kell tartalmaznia. Ha a típus "historical_figure", az elemnek "name", "biography" és "role" mezőket kell tartalmaznia.

Ha az `is_valid` értéke false:
{
  "is_valid": false,
  "error_message": "Rövid magyarázat, hogy miért nem szereplő vagy helyszín ez."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
FELADAT: Kombinálja a következő két leírást ugyanarról az entitásról (szereplőről vagy helyszínről) egyetlen, összefüggő és tömör összefoglalóvá.
Távolítsa el a felesleges információkat, és biztosítsa, hogy a végső leírás természetesen folyjon.

Elsődleges leírás: %s
Másodlagos leírás: %s

ELVÁRT JSON FORMÁTUM:
{
  "merged_description": "Összevont és csiszolt leírás (Max {MAX_CHAR_DESC} karakter)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Könyv címe: %s
Szerző: %s
Sorozat: %s
Fájlleírás/Tárgyi metaadatok: %s

FELADAT: Sorolja be ezt a könyvet pontosan EGYETLEN kategóriába az alábbi könyvtípusok közül a metaadatai és műfaji jelzései alapján:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Kizárólag érvényes JSON-t adjon vissza:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Könyv címe: %s
Szerző: %s

FELADAT: Határozza meg, hogy ez a könyv egy nevezett sorozat része-e.
Kizárólag érvényes JSON-t adjon vissza:
{
  "is_series": true,
  "series_name": "Az Idő Kereke",
  "book_index": 3,
  "total_books_known": 14
}
Ha ez NEM sorozatkönyv, adjon vissza:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Sorozat: %s
Jelenlegi könyv indexe: %d
Jelenlegi könyv címe: %s

FELADAT: Listázza az 1. és %d. közötti könyvek címeit (és szerzőit, ha különböznek ettől: "%s"),
amelyek a sorozat jelenlegi könyve ELŐTT jelentek meg.
Kizárólag érvényes JSON-t adjon vissza:
{
  "prior_books": [
    { "index": 1, "title": "A Világ Szeme", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
CÉLKÖNYV: %s
SZERZŐ: %s
CÉLKÖNYV INDEXE: %d
SOROZAT: %s

FELADAT:
Készíts TELJES összefoglalót KIZÁRÓLAG a CÉLKÖNYVRŐL egy olyan olvasó számára, aki befejezte a CÉLKÖNYVET, és éppen elkezdené a sorozat következő könyvét.

ABSZOLÚT SPOILER-HATÁR:
A tudásanyag szigorúan a CÉLKÖNYV UTOLSÓ OLDALÁIG terjed (Könyv indexe: %d).
A CÉLKÖNYVBEN vagy a sorozat korábbi könyveiben tisztázott tényeket beleveheted.
TILOS bármilyen információt felhasználni, sejtetni, előrevetíteni vagy részleteket kiválasztani a későbbi könyvekből szerzett tudás alapján.

TILTOTT KÉSŐBBI KÖNYVBELI INFORMÁCIÓK:
- Későbbi események, jövőbeli sorsok, halálesetek, túlélések, úti célok, szerelmek, szövetségek, konfliktusok vagy árulások.
- Későbbi könyvekben felfedett identitások, valódi származások, titkos szülők, álnevek, alteregók, reinkarnációk, átalakulások, címek vagy erőnléti fejlődések (pl. NE említsd meg, ha egy esszencia egy másikhoz csatlakozik, vagy újjászületik egy későbbi könyvben).
- Későbbi könyvekben bevezetett felfedezések, megerősítések, újragondolások, fordulatok vagy világépítési terminológia.
- Visszatekintő előreutalások vagy olyan kifejezések, mint „később”, „végül”, „lesz belőle”, „a későbbi könyvekben” vagy ezekkel egyenértékű megfogalmazások.
- Későbbi könyvekből származó szereplők, koncepciók, szervezetek vagy kronológia említése.

SZEREPLŐKRE VONATKOZÓ KORLÁTOZÁS:
Minden szereplőt szigorúan úgy írj le, ahogyan a CÉLKÖNYV utolsó oldalán ismertek.
NE használj olyan álneveket, szerepeket, kapcsolatokat, valódi identitásokat vagy státuszokat, amelyek csak későbbi könyvekben derülnek ki.

BIZONYTALANSÁGI SZABÁLY:
Ha nem tudod magabiztosan megállapítani, hogy egy tényt vagy álnevet a CÉLKÖNYV végéig tisztáztak-e, HAGYD KI.
A hiányzó részlet sokkal jobb, mint egy jövőbeli könyvből származó spoiler.

VÉGSŐ ELLENŐRZÉS:
A JSON visszaküldése előtt vizsgáld meg az összes mezőt (különösen a szereplők leírását és álneveit), és távolíts el mindent, ami a CÉLKÖNYV utáni könyvekből származó tudáson alapul.

ELŐÍRT JSON FORMÁTUM:
{
  "characters": [
    { "name": "Teljes név", "aliases": [], "role": "...", "description": "Státusz e könyv végén (max. {MAX_CHAR_DESC} karakter)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Álnév 1", "Álnév 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Könyv összefoglalása", "event": "Egyetlen, rendkívül részletes, átfogó összefoglaló a teljes könyv cselekményéről, főbb eseményeiről és feloldásáról (max. 2000 karakter). Ezt az összefoglalót az olvashatóság érdekében egyetlen egybefüggő szövegtömb helyett több különálló, dupla sortöréssel (\\n\\n) elválasztott bekezdésre KELL tagolnod." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
CÉLKÖNYV: %s
SZERZŐ: %s
CÉLKÖNYV INDEXE: %d
SOROZAT: %s

FELADAT:
KIZÁRÓLAG a CÉLKÖNYV alább megadott, ellenőrzött fejezetről fejezetre haladó eseményei alapján írj egy összefüggő, átfogó összefoglalót a teljes könyv cselekményéről, a legfontosabb fejleményekről és a kimenetelről.

SZIGORÚ FORRÁSHOZ KÖTÉSI KÖVETELMÉNY:
- Az összefoglalót KIZÁRÓLAG a megadott fejezeteseményekre alapozd.
- NE mutass be olyan tényeket, szereplőket, eseményeket vagy kimeneteleket, amelyek nem szerepelnek ezekben a fejezeteseményekben.
- SOHA ne említs vagy vetíts előre a sorozat későbbi könyveiből származó eseményeket, haláleseteket vagy fejleményeket.

FEJEZETESEMÉNYEK:
%s

ELŐÍRT JSON FORMÁTUM:
{
  "timeline": [
    { "chapter": "Könyv összefoglaló", "event": "Egyetlen, rendkívül részletes, átfogó összefoglaló a teljes könyv cselekményéről és a kimenetelről (max. 2000 karakter). Ezt az összefoglalót az olvashatóság érdekében KÖTELEZŐ több különálló, dupla újsorral (\\n\\n) elválasztott bekezdésre tagolnod egyetlen tömör szövegtömb helyett." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Könyv: %s
Szerző: %s
Elemzett fejezet: %s

FELADAT: KIZÁRÓLAG ezt az egyetlen fejezetet elemezze. Azonosítsa az ebben a fejezetben bevezetett ÚJ entitásokat, és a meglévő entitásokra vonatkozó FRISSÍTÉSEKET (állapotváltozásokat).
KIZÁRÓLAG érvényes JSON-objektumot adjon meg kimenetként.

MÁR ISMERT ENTITÁSOK JEGYZÉKE (NE bontsa ki őket újra, kivéve, ha a szerepük, állapotuk vagy leírásuk jelentősen változott):
%s

SZABÁLYOK:
1. SZIGORÚ SPOILERKORLÁTOZÁS: KIZÁRÓLAG a megadott fejezetszöveget elemezze. NE használjon semmilyen információt a későbbi fejezetekből vagy külső forrásokból.
2. KARAKTERLEÍRÁS MÉLYSÉGE ÉS TARTALMA (KRITIKUS):
   - Alapos és specifikus: Írja le, ki a karakter konkrét történeti tényekkel—háttérrel, egyedi személyiséggel, foglalkozással, más szereplőkhöz fűződő kulcsfontosságú kapcsolataival, valamint a narratívában betöltött konkrét szerepével és személyes tétjével.
   - Jelentős narratív kontextus: Kapcsolja a karaktert közvetlenül a könyv központi rejtélyéhez, a cselekmény konfliktusához vagy a nyomozáshoz (pl. milyen bűncselekményeket vagy ügyeket vizsgálnak, ki bérelte fel őket, kik a fő szövetségeseik vagy ellenfeleik, milyen konkrét személyes dilemmáik vagy feszültségeik vannak).
   - NEM túlzottan általános: NE írjon általános közhelyeket (pl. kerülje az olyan üres megfogalmazásokat, mint "egy detektív, aki komplex ügyekben nyomoz"). Nevezze meg a szövegben meghatározott konkrét körülményeket, kapcsolatokat és téteket.
   - NE LEGYENEK TRIVIÁLIS ESEMÉNYÖSSZEFOGLALÓK: NE írjon időrendi naplót a hétköznapi napi tevékenységekről vagy rutinintéznivalókról (pl. NE foglalja össze az élelmiszerbolti vásárlásokat, a rutinszerű telefonhívásokat vagy a mellékes, jelenetről jelenetre történő mozgásokat).
   - A karakterleírásoknak gazdag, szemléletes profiloknak kell lenniük, amelyek összefoglalják, hogy kik ők, és milyen jelentőséggel bírnak a könyv adott pontjáig.
3. MAGAS KÜSZÖBÉRTÉK A KARAKTERFRISSÍTÉSEKNÉL:
   - NE hozzon létre frissítést a `character_state_updates` tömbben csak azért, mert egy meglévő karakter megjelent, megszólalt vagy rutinműveleteket hajtott végre ebben a fejezetben.
   - CSUPÁN akkor hozzon létre frissítést, ha lényegi, tartós változás történik a narratív ívükben, identitásukban, kapcsolataikban, munkájukban, lojalitásukban vagy állapotukban (pl. megölték, megsérült, letartóztatták, elárulták, eljegyezték, előléptették, kiderült róla, hogy ő a tettes, vagy fény derült egy fontos titkára/indítékára).
   - Ha a frissítés indokolt, a frissített `description` egy gazdag, kumulatív karakteráttekintés kell legyen, amely magában foglalja az új fejleményeket, miközben megtartja az alapvető identitást és a már megalapozott történeti kontextust—NEM pedig egy elszigetelt jelenet összefoglalója.
4. FEJEZETEN BELÜLI OLDALJELÖLŐK ([PAGE N]) ÉS ZERO-SPOILER KORLÁTOZÁS:
   - A fejezetszövegek [PAGE N] jelölőket tartalmaznak, amelyek az oldalak haladását jelzik.
   - A `new_characters`, `new_locations` és `new_terms` esetében adja meg a következőket: "first_page" (az az N egész szám a [PAGE N] jelölőből, ahol először említik őket), "intro_role" (karaktereknél), és "intro_description" (1-2 mondat, amely szigorúan arra korlátozódik, ami az első említéskor a [PAGE first_page] oldalon ismert—NULLA tudással a későbbi oldalakon előforduló fordulatokról, titkokról vagy kimenetelekről). Adja meg a "page" értéket is (az a [PAGE N] jelölő, ahol a teljesebb kumulatív "description" érvényes, jellemzően a fejezet utolsó oldala).
   - A `character_state_updates`, `location_state_updates` és `term_state_updates` esetében adja meg a "page" értéket (az az N egész szám a [PAGE N] jelölőből, ahol a felfedés/átmenet befejeződik; NE fedjen fel tényeket ezelőtt az oldal előtt).
5. BIZONYÍTÉK (EVIDENCE): Adjon meg egy rövid hivatkozást vagy idézetrészletet ebből a fejezetből, amely megmagyarázza, miért történt a frissítés.
6. IDŐVONAL (TIMELINE): Adjon meg pontosan egy eseményösszefoglalót a fejezet fő cselekményeiről.

ELVÁRT JSON FORMÁTUM:
{
  "new_characters": [
    {
      "name": "Teljes név",
      "aliases": ["Álnév 1", "Álnév 2"],
      "first_page": 80,
      "intro_role": "Kezdeti szerep (pl. falusi jegyző, idegen, ügyfél)",
      "intro_description": "Kezdeti 1-2 mondatos benyomás szigorúan az első bemutatáskor, nulla spoiler a későbbi oldalakról.",
      "page": 99,
      "role": "Narratív szerep / fontosság (pl. főhős, magánnyomozó, társ, ellenfél, áldozat, ügyfél, gyanúsított, mellékszereplő, epizódszereplő)",
      "status": "él",
      "description": "Részletes, konkrét karakterleírás (háttér, kapcsolatok, narratív tétek). Kerülje az általános közhelyeket és a triviális intéznivalók naplózását.",
      "evidence": "Rövid idézet"
    }
  ],
  "character_state_updates": [
    {
      "name": "Az ismert jegyzéknek megfelelő név",
      "page": 95,
      "role": "Frissített narratív szerep / fontosság (pl. főhős, társ, ellenfél, mellékszereplő stb.)",
      "status": "él",
      "change": "Egy rövid mondat megnevezve, mi változott a korábbi állapothoz képest (pl. 'Előléptették társsá a Shacklewell-ügy után')",
      "description": "Frissített, részletes, kumulatív karakterleírás, amely tükrözi az új állapotot és a történetbeli téteket",
      "evidence": "Rövid idézet"
    }
  ],
  "new_locations": [
    {
      "name": "Helyszín neve",
      "first_page": 80,
      "intro_description": "Kezdeti benyomás az első említéskor.",
      "page": 99,
      "description": "A helyszín leírása",
      "evidence": "Rövid idézet"
    }
  ],
  "location_state_updates": [
    {
      "name": "Az ismert jegyzéknek megfelelő név",
      "page": 95,
      "change": "Egy rövid mondat megnevezve, mi változott (pl. 'Elpusztult az oakhaveni csata során')",
      "description": "Frissített, kibővült leírás",
      "evidence": "Rövid idézet"
    }
  ],
  "new_terms": [
    {
      "name": "Kifejezés neve",
      "first_page": 80,
      "intro_description": "Kezdeti meghatározás az első említéskor.",
      "page": 99,
      "description": "Definíció vagy világépítési magyarázat",
      "evidence": "Rövid idézet"
    }
  ],
  "term_state_updates": [
    {
      "name": "Az ismert jegyzéknek megfelelő név",
      "page": 95,
      "change": "Egy rövid mondat megnevezve, mi változott a megértésben vagy a használatban",
      "description": "Frissített definíció",
      "evidence": "Rövid idézet"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "A fejezet eseményeinek összefoglalása"
  }
}

FEJEZETSZÖVEG:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Könyv: %s
Szerző: %s
Fejezetek ebben a kötegben: %s

FELADAT: Elemzed a megadott fejezetköteget egymás utáni sorrendben.
A köteg MINDEN EGYES fejezetére vonatkozóan határozd meg a következőket:
1. Az abban a fejezetben bevezetett ÚJ entitások (karakterek, helyszínek, kifejezések).
2. DELTA FRISSÍTÉSEK (állapotátmenetek) a már ismert entitásokhoz (a manifesztumból VAGY a jelen köteg egy korábbi fejezetéből), FELTÉVE ÉS CSAKIS AKKOR, HA a szerepük, státuszuk, hűségük vagy narratív állapotuk lényegi, tartós átalakuláson ment keresztül.
3. IDŐVONAL-ESEMÉNY: A fejezetben történő elsődleges cselekményesemények tömör összefoglalása.

Kizárólag a kívánt sémának megfelelő, érvényes JSON-objektumot adj meg kimenetként.

MÁR ISMERT ENTITÁSOK MANIFESZTUMA (a korábbi kötegekből – NE emeld ki őket újra, kivéve ha a szerepük, státuszuk vagy leírásuk jelentősen megváltozott):
%s

SZABÁLYOK:
1. SZIGORÚ SPOILERKORLÁTOZÁS ÉS SEKVENCIÁLIS HALADÁS:
   - A fejezeteket egymás utáni sorrendben elemezd.
   - A köteg bármely fejezeténél NE használj fel olyan információkat, amelyek a köteg későbbi fejezeteiből vagy a könyv többi részéből származnak.
2. KARAKTERLEÍRÁS MÉLYSÉGE ÉS TARTALMA (KRITIKUS):
   - Megalapozott és konkrét: Írd le, ki a karakter konkrét történeti tényekkel—a hátterét, egyedi személyiségét, foglalkozását, más karakterekhez fűződő főbb kapcsolatait, valamint a narratívában betöltött konkrét szerepét és személyes tétjeit.
   - Jelentős narratív kontextus: Kapcsold a karaktert közvetlenül a könyv központi rejtélyéhez, cselekményi konfliktusához vagy nyomozásához (pl. milyen bűncselekményeket vagy ügyeket vizsgálnak, ki bérelte fel őket, kik a fő szövetségeseik vagy ellenfeleik, milyen konkrét személyes dilemmáik vagy feszültségeik vannak).
   - NE legyen túlságosan általános: NE írj sablonos blurböket (pl. kerüld az olyan üres megfogalmazásokat, mint „egy detektív, aki komplex ügyeket vizsgál”). Nevezd meg a szövegben megalapozott konkrét körülményeket, kapcsolatokat és téteket.
   - NE legyenek benne lényegtelen napi teendők összefoglalói: NE írj időrendi naplót a hétköznapi napi tevékenységekről vagy rutinintézésekről (pl. NE foglald össze az élelmiszerbolti látogatásokat, a rutin telefonhívásokat vagy a jelenetről jelenetre történő mellékes mozgásokat).
   - A karakterleírásoknak gazdag, szemléletes profiloknak kell lenniük, amelyek összefoglalják, hogy kicsoda a karakter, és mekkora a jelentősége a könyv adott pontjáig.
3. MAGAS KÜSZÖB A KARAKTERFRISSÍTÉSEKNÉL:
   - NE hozz létre frissítést a `character_state_updates` tömbben pusztán azért, mert egy létező karakter megjelent, megszólalt vagy rutinintézkedéseket hajtott végre egy fejezetben.
   - CSAK AKKOR hozz létre frissítést, ha lényegi, tartós átalakulás történik a narratív ívükben, identitásukban, kapcsolataikban, foglalkozásukban, hűségükben vagy állapotukban (pl. megölték, megsérült, letartóztatták, elárulták, eljegyezték, előléptették, kiderült róla, hogy ő a tettes, vagy fény derült egy fő titkára/indítékára).
   - Ha a frissítés indokolt, a frissített `description` mezőnek egy gazdag, kumulatív karakteráttekintésnek kell lennie, amely magában foglalja az új fejleményeket, miközben megtartja a karakter alapvető identitását és a már kialakult történetbeli kontextust – NE egy izolált jelenet összefoglalása legyen.
4. FEJEZETEN BELÜLI OLDALJELÖLŐK ([PAGE N]) ÉS ZERO-SPOILER KORLÁTOZÁS:
   - A fejezetszövegek [PAGE N] jelölőket tartalmaznak, amelyek az oldalak haladását jelzik.
   - A `new_characters`, `new_locations` és `new_terms` mezőknél add meg a "first_page" értéket (az N egész számot a [PAGE N] jelölőből, ahol először említik), az "intro_role" értéket (karaktereknél), valamint az "intro_description" értéket (1-2 mondat, amely szigorúan arra korlátozódik, ami a legelső említéskor a [PAGE first_page] oldalon ismert – NULLA tudással a későbbi oldalakon előforduló fordulatokról, titkokról vagy kimenetelekről). Add meg a "page" értéket is (a [PAGE N] jelölőt, ahol a teljesebb, kumulatív "description" érvényes, jellemzően a fejezet utolsó oldalát).
   - A `character_state_updates`, `location_state_updates` és `term_state_updates` mezőknél add meg a "page" értéket (az N egész számot a [PAGE N] jelölőből, ahol a felfedés/átmenet teljessé válik; NE fedj fel tényeket ezen oldal előtt).
5. BIZONYÍTÉK: Adj meg egy rövid hivatkozást vagy idézetrészletet az adott fejezetből, amely megmagyarázza, miért történt a frissítés.
6. JSON BIZTONSÁG: Kizárólag érvényes JSON-t adj meg kimenetként. Megfelelően készítsd elő a dupla idézőjeleket a karakterláncokon belül (escape-elés).

ELVÁRT JSON FORMÁTUM:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Fejezet címe",
      "timeline_event": "A fejezet főbb cselekményfejleményeinek összefoglalása.",
      "new_characters": [
        {
          "name": "Teljes név",
          "aliases": ["Álnév 1"],
          "first_page": 80,
          "intro_role": "Kezdeti szerep (pl. falusi írnok, idegen, ügyfél)",
          "intro_description": "Kezdeti 1-2 mondatos benyomás szigorúan az első bemutatáskor, nulla spoiler a későbbi oldalakról.",
          "page": 99,
          "role": "Narratív szerep / fontosság (pl. főhős, magánnyomozó, társ, ellenfél, áldozat, ügyfél, gyanúsított, mellékszereplő, epizodista)",
          "status": "alive",
          "description": "Részletes, konkrét karakterleírás (háttér, kapcsolatok, narratív tétek). Kerüld az általános leírásokat és a lényegtelen napi teendők naplózását.",
          "evidence": "Rövid idézet"
        }
      ],
      "character_state_updates": [
        {
          "name": "Az ismert manifesztumnak vagy a köteg egy korábbi fejezetében bevezetett karakternek megfelelő név",
          "page": 95,
          "role": "Frissített narratív szerep / fontosság (pl. főhős, társ, ellenfél, mellékszereplő stb.)",
          "status": "alive",
          "change": "Egy rövid mondat megnevezve, mi változott az előző állapothoz képest (pl. 'Előléptették társsá a Shacklewell-ügy után')",
          "description": "Frissített részletes, kumulatív karakterleírás, amely tükrözi az új státuszukat és a történetbeli tétet",
          "evidence": "Rövid idézet"
        }
      ],
      "new_locations": [
        {
          "name": "Helyszín neve",
          "first_page": 80,
          "intro_description": "Kezdeti benyomás az első említéskor.",
          "page": 99,
          "description": "A helyszín leírása",
          "evidence": "Rövid idézet"
        }
      ],
      "location_state_updates": [
        {
          "name": "Az ismert manifesztumnak vagy a köteg egy korábbi fejezetében bevezetett helyszínnek megfelelő név",
          "page": 95,
          "change": "Egy rövid mondat megnevezve, mi változott (pl. 'Elpusztult az oakhaveni csata során')",
          "description": "Frissített leírás",
          "evidence": "Rövid idézet"
        }
      ],
      "new_terms": [
        {
          "name": "Kifejezés neve",
          "first_page": 80,
          "intro_description": "Kezdeti meghatározás az első említéskor.",
          "page": 99,
          "description": "Meghatározás vagy háttértörténeti magyarázat",
          "evidence": "Rövid idézet"
        }
      ],
      "term_state_updates": [
        {
          "name": "Az ismert manifesztumnak vagy a köteg egy korábbi fejezetében bevezetett kifejezésnek megfelelő név",
          "page": 95,
          "change": "Egy rövid mondat megnevezve, mi változott a megértésben vagy a használatban",
          "description": "Frissített meghatározás",
          "evidence": "Rövid idézet"
        }
      ]
    }
  ]
}

A KÖTEGBEN LÉVŐ FEJEZETSZÖVEGEK:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Elemezze az alábbi könyvadatokat és tartalomjegyzéket:

Cím: %s
Szerző: %s
Témák: %s
Leírás: %s

Tartalomjegyzék:
%s

Határozza meg, hogy ez a mű:
1. "anthology" (önálló novellák, esszék vagy kisregények gyűjteménye, amelyek mindegyike saját, lezárt történettel vagy szereplőgárdával rendelkezik, pl. „Sherlock Holmes kalandjai”, „Dublini emberek”, „Kilégzés”, „Férfiak nők nélkül”).
2. "novel" (egységes regény, amely fejezetekre, részekre vagy felvonásokra tagolódik, pl. „Büszkeség és balítélet”, „Harry Potter”, „Dűne”, „Carrie”).
3. "novel_omnibus" (többkötetes gyűjtemény, amely teljes terjedelmű regényeket tartalmaz egyetlen kötetben kiadva, pl. „A Gyűrűk Ura: Mindhárom kötet”, „Galaxis útikalauz stopposoknak – A teljes sorozat”, „Percy Jackson: 1–3. könyv”).
4. "non_fiction" (egyetlen fejezetekre osztott ismeretterjesztő értekezés, történelmi mű vagy tudományos szakkönyv).

Kizárólag egy JSON-objektumot adjon vissza a következőkkel:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 és 1.0 között,
  "reasoning": "rövid magyarázat (egy mondat)"
}]],

    -- System instruction
    system_instruction = "Ön egy tapasztalt irodalmi kutató. Válaszának KIZÁRÓLAG érvényes JSON formátumban kell lennie. Győződjön meg arról, hogy az adatok rendkívül pontosak, és szigorúan a megadott kontextusra vonatkoznak.",

    -- Fallback strings
    fallback = {
        no_biography = "Nem áll rendelkezésre életrajz",
        no_description = "Nincs leírás",
        not_specified = "Nincs megadva",
        unknown_author = "Ismeretlen szerző",
        unknown_book = "Ismeretlen könyv",
        unnamed_character = "Névtelen szereplő",
        unnamed_person = "Névtelen személy"
    }
}
