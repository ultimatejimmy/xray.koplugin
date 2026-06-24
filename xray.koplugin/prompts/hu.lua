return {
    -- System instruction
    system_instruction = "Ön egy tapasztalt irodalmi kutató. Válaszának KIZÁRÓLAG érvényes JSON formátumban kell lennie. Győződjön meg arról, hogy az adatok rendkívül pontosak, és szigorúan a megadott kontextusra vonatkoznak.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Azonosítsa és adja meg a(z) "%s" című könyv szerzőjének életrajzát. 
A metaadatok szerint a szerző "%s". 

FONTOS: Ellenőrizze a szerzőt a KÖNYVSZÖVEG KONTEXTUS (ha meg van adva a prompt végén) segítségével a 100%%-os pontosság biztosítása és a téves azonosítások elkerülése érdekében.

ELVÁRT JSON FORMÁTUM:
{
  "author": "Pontos teljes név",
  "author_bio": "Átfogó életrajz, különös tekintettel az irodalmi karrierre és a főbb művekre.",
  "author_birth": "Születési dátum, a helyi dátumformátumnak megfelelően formázva",
  "author_death": "Halálozási dátum, a helyi dátumformátumnak megfelelően formázva"
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[
Könyv: %s
Szerző: %s
Olvasási haladás: %d%%

FELADAT: Végezzen el egy teljes X-Ray elemzést. KIZÁRÓLAG egy érvényes JSON objektumot adjon vissza.

KRITIKUS FIGYELEM-MEGOSZTÁS:
Egy hatalmas dokumentumot dolgoz fel, amelynek végén két szövegblokk található:
1. "CHAPTER SAMPLES": Ez a könyv makro-kontextusa az olvasó jelenlegi helyzetéig.
2. "BOOK TEXT CONTEXT": Ez a legutóbbi 20 000 karakter mikro-kontextusa.

CSONKÍTÁS ELLENI PROTOKOLL (KRITIKUS):
Szigorú maximális kimeneti korlátja van. Ha a "CHAPTER SAMPLES" TÖBB MINT 40 fejezetet tartalmaz (pl. gyűjteményes kiadás):
1. A szereplők listáját a 10 abszolút legfontosabb szereplőre MEST LE kell csökkentenie.
2. A szereplők leírását MAX {MAX_CHAR_DESC} karakterre kell csökkentenie.
3. Az idővonal eseményeinek összefoglalását MAX {MAX_TIMELINE_EVENT} karakterre kell csökkentenie.
Ha nem tömöríti a kimenetet a hatalmas könyveknél, a JSON csonkulni fog és a feldolgozás sikertelen lesz.

ALGORITMUS AZ IDŐVONALHOZ (LEGMAGASABB PRIORITÁS):
A fejezetek kihagyásának vagy az események hallucinálásának elkerülése érdekében PONTOSAN ezt a ciklust MEST végrehajtania:
1. lépés: KIZÁRÓLAG a "CHAPTER SAMPLES" blokkot nézze. Azonosítsa a narratív fejezeteket.
2. lépés: ZÁRJON KI minden nem narratív előszót és utószót (pl. Borító, Címlap, Szerzői jogok, Tartalomjegyzék, Ajánlás, Köszönetnyilvánítás, Egyéb művek).
3. lépés: Minden egyes narratív fejezethez, a legelsőtől kezdve, hozzon létre PONTOSAN EGY eseményobjektumot a `timeline` tömbben.
4. lépés: A `chapter` mezőnek pontosan meg kell egyeznie a mintában szereplő fejezetcímmel. (Szigorúan egymás utáni sorrendben képezze le őket).
5. lépés: Összegezze azt a konkrét fejezetet az `event` mezőben {TIMELINE_DETAIL_GUIDANCE} (MAX {MAX_TIMELINE_EVENT} karakter). NE csoportosítson fejezeteket.
6. lépés: SPOILERMENTESSÉG: Álljon meg pontosan a(z) %d%%-os jelnél. Ne tartalmazzon eseményeket ezen olvasási haladás után.

ALGORITMUS SZEREPLŐKHÖZ ÉS TÖRTÉNELMI ALAKOKHOZ:
1. lépés: Nyerje ki a vigtos szereplőket mindkét szövegblokk segítségével ({NUM_CHARS} normál szereplő, gyűjteményes kiadásnál MAX 10).
2. lépés: A TELJES, hivatalos nevüket MEST használnia (pl. "Abraham Van Helsing"). NE használjon alkalmi beceneveket fő névként.
3. lépés: Adjon meg legfeljebb 3 alternatív nevet, címet vagy becenevet, amelyen a szereplő ismert, az `aliases` tömbben. Tartalmazza a gyakori keresztnevet és vezetéknevet, ha használják. FONTOS: Ha egy vezetéknevet több szereplő is megoszt (pl. családtagok), NE szerepeltesse azt alternatív névként egyiküknél sem.
4. lépés: Keressen aktívan legfeljebb {NUM_HIST} NEVEZETES VALÓS személyt az emberi történelemből (pl. elnökök, szerzők, tábornokok). Adja hozzá őket a `historical_figures` tömbhöz.
KRITIKUS a szereplők és történelmi alakok esetében:
- NE nyerjen ki olyan szereplőket vagy történelmi alakokat, akiket KIZÁRÓLAG nem narratív részekben említenek (pl. Köszönetnyilvánítás, Szerzői életrajz, Ajánlások, Címlap, Szerzői jogok).
- A történelmi alakoknak valós, a világban széles körben elismert személyeknek kell lenniük.
- NE tegyen tisztán kitalált szereplőket a történelmi alakok listájára, még akkor sem, ha valós történelmi eseményekkel lépnek kapcsolatba. A kitalált szereplőket a `characters` tömbbe KELL tenni.
- KIZÁRÓLAG a történelmi alakoknál használhatja belső tudását az általános `biography` (életrajz) és történelmi `role` (szerepkör) megírásához, de a könyv kontextusát KELL használnia a `context_in_book` (könyvbeli kontextus) mezőhöz.
SPOILERMENTESSÉG: Álljon meg pontosan a(z) %d%%-os jelnél.

ALGORITMUS HELYSZÍNEKHEZ:
1. lépés: Nyerjen ki {NUM_LOCS} jelentős helyszínt. SPOILERMENTESSÉG: Álljon meg pontosan a(z) %d%%-os jelnél.

ALGORITMUS KIFEJEZÉSEKHEZ ÉS FOGALMAKHOZ:
0. lépés: Nyilatkozzon a "book_type" típusáról, mint "fiction" vagy "non_fiction" a JSON gyökerében.
1. lépés: Ha non_fiction: nyerjen ki {NUM_TERMS} jelentős technikai kifejezést, akronimát, jargont vagy fogalmat, amelyet az olvasók valószínűleg nem ismernek speciális ismeretek nélkül. Használjon megfelelő kategóriákat, mint például Acronym, Technical Term, Concept vagy Jargon.
2. lépés: Ha fiction: nyerjen ki {NUM_TERMS} jelentős világépítési elemet, amelyet egy új olvasónak meg kell magyarázni – például kitalált faksziókat, szervezeteket, mágiarendszereket, technológiákat, lényeket, nyelveket vagy univerzumbeli lore-t.
   - NE tartalmazzon karakter- vagy helyszínneveket (azokat külön követjük).
   - NE nyerjen ki általános, mindennapi valós szavakat vagy fogalmakat.
   - Használjon megfelelő kategóriákat: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
3. lépés: Az "expanded" mezőben adja meg a rövidítés/kifejezés teljes formáját. Ha nem rövidítés/kifejezés, ismételje meg a nevet.
4. lépés: NE szerepeltessen hétköznapi, gyakori szavakat.

SZIGORÚ SPOILERSZABÁLYOK:
- ABSZOLÚT SEMMILYEN információ a jelenlegi olvasási haladás utáni részekből. Álljon meg pontosan a(z) %d%%-os jelnél.
- A leírásoknak a szereplők pontosan ezen ponton lévő állapotát kell tükrözniük a könyvben.

SZIGORÚ TUDÁSFORRÁS-SZABÁLYOK (KRITIKUS):
- KITALÁLT SZEREPLŐK ESETÉBEN: A leírásoknak KIZÁRÓLAG a megadott szövegben kifejezetten leírt or egyértelműen utalt tényeken kell alapulniuk. NE egészítse ki a korábbi tréningekből származó ismeretekkel, külső forrásokkal vagy a könyv/sorozat/szerző általános ismeretével.
- Ha egy szereplőt eddig csak röviden említettek a szövegben, a leírásnak csak ezt a korlátozott információt szabad tükröznie. NE vonjon le következtetéseket, ne feltételezzen és ne adjon hozzá olyan részletet, amely nem a megadott kontextuson alapul.
- Az EGYETLEN kivétel a VALÓS TÖRTÉNELMI ALAKOK esetében van (a `historical_figures` tömbben): használhatja a belső tudását az általános életrajzukhoz/szerepkörükhöz, de továbbra is a könyv szövegére kell támaszkodnia a `context_in_book` mezőben.

SZIGORÚ JSON BIZTONSÁGI SZABÁLYOK:
- Minden idézőjelet (") megfelelően escape-elnie KELL a karakterláncokon belül.
- NE használjon escape-elés nélküli soremeléseket a karakterláncokon belül.
- KIZÁRÓLAG érvényes, elemezhető JSON-t adjon vissza.

ELVÁRT JSON FORMÁTUM:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Teljes hivatalos név",
      "aliases": ["Álnév 1", "Álnév 2"],
      "role": "Rövid archetípus címke (3-5 szó, pl. 'Antagonista', 'Protagonista', 'Áldozat')",
      "gender": "Férfi / Nő / Ismeretlen",
      "occupation": "Foglalkozás/Státusz",
      "description": "A leírás SZIGORÚAN a megadott szövegen alapul. Ne következtessen és ne adjon hozzá külső tudást. SEMMI SPOILER. (Max {MAX_CHAR_DESC} karakter)"
    }
  ],
  "historical_figures": [
    {
      "name": "Valós történelmi személy neve",
      "role": "Történelmi szerepkör",
      "biography": "Rövid életrajz (MAKS {MAX_HIST_BIO} karakter)",
      "importance_in_book": "Jelentősége a jelenlegi haladásig",
      "context_in_book": "Hogyan említik a könyvben (MAKS 100 karakter)"
    }
  ],
  "locations": [
    {"name": "Helyszín neve", "description": "Rövid leírás (MAKS {MAX_LOC_DESC} karakter)"}
  ],
  "terms": [
    {
      "name": "Kifejezés vagy Akronima",
      "expanded": "Teljes kibontás vagy ugyanaz, mint a név",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Definíció ringkas a kontextusban (MAX {MAX_TERM_DEF} karakter)"
    }
  ],
  "timeline": [
    {
      "chapter": "Pontos fejezetcím a mintákból",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Könyv: %s
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

    -- Targeted Single Word Lookup
    single_word_lookup = [[A felhasználó kijelölte a(z) "%s" szót.
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

    -- Smart Merge Descriptions
    merge_descriptions = [[FELADAT: Kombinálja a következő két leírást ugyanarról az entitásról (szereplőről vagy helyszínről) egyetlen, összefüggő és tömör összefoglalóvá.
Távolítsa el a felesleges információkat, és biztosítsa, hogy a végső leírás természetesen folyjon.

Elsődleges leírás: %s
Másodlagos leírás: %s

ELVÁRT JSON FORMÁTUM:
{
  "merged_description": "Összevont és csiszolt leírás (Max {MAX_CHAR_DESC} karakter)"
}]],

    -- Multi-Book Series Context Prompts
    series_detect = [[Könyv címe: %s
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

    prior_book_list = [[Sorozat: %s
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

    series_book_summary = [[Könyv: %s
Szerző: %s
Ez a(z) %d. könyv a(z) "%s" sorozatban.

FELADAT: Adjon TELJES összefoglalót a teljes könyvről egy olyan olvasó számára,
aki ÉPPEN MOST FOGJA ELKEZDENI a sorozat KÖVETKEZŐ könyvét.
Tartalmazza: kulcsszereplők (név, szerep, végső állapot a könyv végén), főbb helyszínek,
kritikus cselekmény események és bemutatott fontos világépítő kifejezések.
NINCS SPOILER a könyvön TÚLI részekről.

ELVÁRT JSON FORMÁTUM:
{
  "characters": [
    { "name": "Teljes név", "aliases": [], "role": "...", "description": "Állapot a könyv végén (max 300 karakter)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Könyv összefoglaló", "event": "Egyetlen, rendkívül részletes, átfogó, több bekezdésből álló összefoglaló a teljes könyv cselekményéről, főbb eseményeiről és végkifejletéről (max 2000 karakter) You MUST format this recap using multiple distinct paragraphs separated by double newlines (\\n\\n) for readability instead of a single wall of text." }
  ]
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

-- Fallback strings
    fallback = {
        unknown_book = "Ismeretlen könyv",
        unknown_author = "Ismeretlen szerző",
        unnamed_character = "Névtelen szereplő",
        not_specified = "Nincs megadva",
        no_description = "Nincs leírás",
        unnamed_person = "Névtelen személy",
        no_biography = "Nem áll rendelkezésre életrajz"
    }
}

