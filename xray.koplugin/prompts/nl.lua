return {
    -- Author Only
    author_only = [[
Identificeer en verstrek een biografie voor de auteur van het boek "%s". 
De metadata suggereert dat de auteur "%s" is. 
1
CRITICAL: Verifieer de auteur met behulp van de BOEKTEKST-CONTEXT (indien verstrekt aan het einde van deze prompt) om 100%% nauwkeurigheid te garanderen en onjuiste identificaties te voorkomen.

VEREIST JSON-FORMAAT:
{
  "author": "Correcte volledige naam",
  "author_bio": "Uitgebreide biografie gericht op hun literaire carrière en belangrijkste werken.",
  "author_birth": "Geboortedatum, geformatteerd op basis van de lokale datumnotatie",
  "author_death": "Sterfdatum, geformatteerd op basis van de lokale datumnotatie"
}]],

    -- Find Duplicates
    find_duplicates = [[
Boek: %s
Auteur: %s
Leesvoortgang: %d%%

U bekijkt de volgende lijst van %s die uit dit boek zijn geëxtraheerd.
Het is uw taak om vermeldingen te identificeren die dezelfde entiteit lijken te zijn, maar onder verschillende namen worden vermeld.

LIJST:
%s

REGELS:
- Er is sprake van een duplicaat wanneer twee vermeldingen duidelijk naar dezelfde entiteit verwijzen (bijv. "De Grote Bibliotheek" and "Grote Bibliotheek", of "John" and "John Doe").
- Markeer geen vermeldingen die alleen gerelateerd of vergelijkbaar zijn, maar toch verschillend.
- Markeer vermeldingen alleen als u er zeer zeker van bent dat het om dezelfde entiteit gaat.
- Als er geen duplicaten bestaan, retourneer dan een lege array.
- SPOILERREGEL: Gebruik geen kennis van voorbij %d%% leesvoortgang.

VEREIST JSON-FORMAT:
{
  "duplicate_pairs": [
    {
      "primary": "Naam van de vermelding die BEHOUDEN moet worden (de meer volledige of formele naam)",
      "secondary": "Naam van de vermelding die VERWIJDERD moet worden",
      "reason": "Korte reden (max. 100 tekens)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Boek: %s
Auteur: %s
Leesvoortgang: %d%%

TAAK: Voer een volledige X-Ray-analyse uit. Geef ALLEEN een geldig JSON-object als output.

CRUCIALE AANDACHTSVERDELING:
Je verwerkt een massaal document met twee tekstblokken die aan het einde van deze prompt worden verstrekt:
1. "CHAPTER SAMPLES": Dit is de macrocontext van het boek tot de huidige locatie van de lezer.
2. "BOOK TEXT CONTEXT": Dit is de microcontext van de meest recente 20k tekens.

ANTI-AFKAPPROTOCOL (CRUCIAAL):
Je hebt een strikte maximale outputlimiet. Als de "CHAPTER SAMPLES" MEER DAN 40 hoofdstukken bevat (bijv. een omnibus-editie):
1. MOET je de lijst met personages beperken tot ALLEEN de top 10 absoluut belangrijkste personages.
2. MOET je de beschrijvingen van personages beperken tot MAXIMAAL {MAX_CHAR_DESC} tekens.
3. MOET je de samenvattingen van gebeurtenissen op de tijdlijn beperken tot MAXIMAAL {MAX_TIMELINE_EVENT} tekens.
Als je de output voor massale boeken niet comprimeert, zal de JSON worden afgekocht en mislukken.

ALGORITME VOOR TIJDLIN (HOOGSTE PRIORITEIT):
Om te voorkomen dat er hoofdstukken worden overgeslagen of gebeurtenissen worden gefantaseerd, MOET je exact deze lus uitvoeren:
Stap 1. Kijk ALLEEN naar het blok "CHAPTER SAMPLES". Identificeer de narratieve hoofdstukken.
Stap 2. SLUIT alle niet-narratieve voorwerk- en nawerkteksten UIT (bijv. Omslag, Titelpagina, Copyright, Inhoudsopgave, Opdracht, Dankwoord, Ook van de auteur).
Stap 3. Maak voor elk narratief hoofdstuk, beginnend bij de allereerste, EXACT ÉÉN event-object aan in de `timeline`-array.
Stap 4. Het veld `chapter` MOET exact overeenkomen met de hoofdstuktitel in de sample. (Koppel ze strikt in chronologische volgorde).
Stap 5. Vat dat specifieke hoofdstuk samen in het veld `event`. {TIMELINE_DETAIL_GUIDANCE} Schrijf tussen {MIN_TIMELINE_EVENT} en {MAX_TIMELINE_EVENT} tekens. Schrijf GEEN kortere samenvatting tenzij het hoofdstuk bijna geen inhoud heeft. Groepeer hoofdstukken NIET.
Stap 6. GEEN SPOILERS: Stop exact bij het punt %d%%. Voeg geen gebeurtenissen toe voorbij deze voortgang.

ALGORITME VOOR PERSONAGES & HISTORISCHE FIGUREN:
Stap 1. Extraheer belangrijke personages met behulp van beide tekstblokken. ({NUM_CHARS} normaal, MAX 10 bij een omnibus). Vermeld altijd het hoofdpersonage / de protagonist bij naam, zelfs in ik-perspectief-verhalen ("ik"/"mij") waarin hun naam zelden voorkomt.
Stap 2. Je MOET hun VOLLEDIGE, formele namen gebruiken (bijv. "Abraham Van Helsing"). Gebruik GEEN informele bijnamen als hoofdnaam. Samenvoegen of onderbrengen van een personage onder een bezittelijke/relationele verwijzing is NOOIT toegestaan (bijv. "Vader van Nick" en "Nick" zijn afzonderlijke personages).
Stap 3. Geef maximaal 3 alternatieve namen, titels of bijnamen op waarmee dit personage bekendstaat in een `aliases`-array. Neem hun gebruikelijke voornaam en achternaam op indien gebruikt. BELANGRIJK: Als een achternaam door meerdere personages wordt gedeeld (bijv. familieleden), voeg deze dan NIET toe als een alias voor een van de personages.
Stap 4. Scan actief op maximaal {NUM_HIST} OPMERKELIJKE ECHTE mensen uit de menselijke geschiedenis (bijv. presidenten, auteurs, generaals). Voeg ze toe aan `historical_figures`.
CRUCIAAL voor Personages & Historische Figuren:
- Extraheer GEEN personages of historische figuren die ALLEEN worden genoemd in niet-narratieve voor- of nawerkteksten (bijv. Dankwoord, Auteursbiografie, Opdrachten, Titelpagina, Copyright).
- Historische figuren MOETEN geverifieerde echte mensen zijn met brede historische bekendheid.
- Neem GEEN puur fictieve personages op in de lijst met historische figuren, zelfs als ze interactie hebben met echte historische gebeurtenissen. Fictieve personages MOETEN in de `characters`-array.
- ALLEEN voor Historische Figuren mag je je interne kennis gebruiken om hun algemene `biography` en historische `role` te schrijven, maar je MOET de boekcontext gebruiken voor hun `context_in_book`.
GEEN SPOILERS: Stop exact bij het punt %d%%.

ALGORITME VOOR LOCATIES:
Stap 1. Extraheer {NUM_LOCS} belangrijke locaties. GEEN SPOILERS: Stop exact bij het punt %d%%.

ALGORITME VOOR TERMEN:
Stap 0. Declareer "book_type" als "fiction", "non_fiction" of "anthology" in de JSON-root.
Stap 1. Indien non_fiction: extraheer {NUM_TERMS} belangrijke technische termen, acroniemen, jargon of concepten die lezers niet zouden kennen zonder gespecialiseerde kennis. Gebruik geschikte categorieën zoals Acronym, Technical Term, Concept of Jargon.
Stap 2. Indien fiction of anthology: extraheer {NUM_TERMS} belangrijke world-buildingelementen die voor een nieuwe lezer uitgelegd moeten worden—zoals verzonnen facties, organisaties, magiesystemen, technologieën, wezens, talen of in-universe lore.
   - Voeg GEEN namen van personages of locaties toe (die worden afzonderlijk bijgehouden).
   - Extraheer GEEN alledaagse woorden of concepten uit de echte wereld.
   - Gebruik geschikte categorieën: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Stap 3. Vermeld waar het acroniem/de uitdrukking voor staat in "expanded". Herhaal de naam als het geen acroniem/uitdrukking is.
Stap 4. Neem GEEN alledaagse woorden op.

STRIKTE SPOILERREGELS:
- ABSOLUUT GEEN informatie van na de huidige leesvoortgang. Stop exact bij het punt %d%%.
- Beschrijvingen moeten de staat van de personages op exact dit punt in het boek weerspiegelen.

STRIKTE KENNISBRONREGELS (CRUCIAAL):
- Voor FICTIEVE PERSONAGES: Je beschrijvingen MOETEN UITSLUITEND gebaseerd zijn op wat expliciet vermeld staat of duidelijk geïmpliceerd wordt in de verstrekte tekst. Vul NIET aan met kennis uit eerdere training, externe bronnen of algemene bekendheid met het boek/de serie/de auteur.
- Als een personage tot nu toe slechts vluchtig in de tekst is genoemd, mag je beschrijving alleen die beperkte informatie weerspiegelen. Leid NIETS af, neem NIETS aan en voeg GEEN details toe die niet in de verstrekte context zijn onderbouwd.
- De ENIGE uitzondering is voor ECHTE HISTORISCHE FIGUREN (geplaatst in `historical_figures`): je mag interne kennis gebruiken voor hun algemene biografie/rol (`biography`/`role`), maar moet nog steeds vertrouwen op de boektekst voor hun `context_in_book`.

STRIKTE JSON-VEILIGHEIDSREGELS:
- Je MOET alle dubbele aanhalingstekens (") binnen strings correct escapen.
- Gebruik GEEN niet-geëscapete regeleinden binnen strings.
- Geef ALLEEN geldige, parseerbare JSON als output.

VEREIST JSON-FORMAT:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Volledige formele naam",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Korte archetype-aanduiding (3-5 woorden, bijv. 'Antagonist', 'Protagonist', 'Het slachtoffer')",
      "gender": "Man / Vrouw / Onbekend",
      "occupation": "Beroep/Status",
      "description": "Beschrijving STRIKT gebaseerd op de verstrekte tekst. Leid niets af en voeg geen externe kennis toe. GEEN SPOILERS. (Max {MAX_CHAR_DESC} tekens)"
    }
  ],
  "historical_figures": [
    {
      "name": "Naam van echte historische persoon",
      "role": "Historische rol",
      "biography": "Korte biografie (MAX {MAX_HIST_BIO} tekens)",
      "importance_in_book": "Betekenis tot aan huidige voortgang",
      "context_in_book": "Hoe ze worden genoemd (MAX 100 tekens)"
    }
  ],
  "locations": [
    {"name": "Plaatsnaam", "description": "Korte beschrijving (MAX {MAX_LOC_DESC} tekens)"}
  ],
  "terms": [
    {
      "name": "Term of acroniem",
      "expanded": "Volledige betekenis of hetzelfde als naam",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Beknopte definitie in context (MAX {MAX_TERM_DEF} tekens)"
    }
  ],
  "timeline": [
    {
      "chapter": "Exacte hoofdstuktitel uit de samples",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Boek: %s
Auteur: %s
Leesvoortgang: %d%%

TAAK: Extraheer EXACT 10 AANVULLENDE belangrijke personages uit de tekst.
Geef UITSLUITEND een geldig JSON-object als resultaat.

EIS VAN BEKNOPTHEID (CRUCIAAL):
Om afkapping van het AI-antwoord te voorkomen, dient u de personagebeschrijvingen onder {MAX_CHAR_DESC} tekens te houden.

CRUCIALE INSTRUCTIE:
Neem GEEN van de volgende personages op, aangezien deze al zijn geëxtraheerd:
%s

STRIKTE SPOILERREGELS:
- ABSOLUT GEEN informatie van na de huidige leesvoortgang. Stop exact bij de %d%%-grens.
- Beschrijvingen moeten de staat van de personages op dit exacte punt in het boek weerspiegelen.

VEREIST JSON-FORMAAT:
{
  "characters": [
    {
      "name": "Volledige formele naam",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Kort archetype-label (3-5 woorden, bijv. 'Antagonist', 'Protagonist', 'Het slachtoffer')",
      "gender": "Man / Vrouw / Onbekend",
      "occupation": "Beroep/Status",
      "description": "Beschrijving STRIKT gebaseerd op de verstrekte tekst. Trek geen conclusies en voeg geen externe kennis toe. GEEN SPOILERS. (Max {MAX_CHAR_DESC} tekens)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Boek: %s
Auteur: %s
Leesvoortgang: %d%%

TAAK: Extraheer EXACT 15 AANVULLENDE belangrijke termen, afkortingen, jargon of concepten uit de tekst.
- Als dit boek non-fictie is: extraheer technische termen, concepten, afkortingen of jargon.
- Als dit boek fictie is: extraheer elementen van wereldopbouw zoals facties, organisaties, magische systemen, technologieën, wezens, talen of in-universum overlevering.
Geef UITSLUITEND een geldig JSON-object als resultaat.

EIS VAN BEKNOPTHEID (CRUCIAAL):
Om afkapping van het AI-antwoord te voorkomen, dient u de definities van termen onder {MAX_TERM_DEF} tekens te houden.

CRUCIALE INSTRUCTIE:
Neem GEEN van de volgende termen op, aangezien deze al zijn geëxtraheerd:
%s

STRIKTE SPOILERREGELS:
- ABSOLUT GEEN informatie van na de huidige leesvoortgang. Stop exact bij de %d%%-grens.

VEREIST JSON-FORMAAT:
{
  "terms": [
    {
      "name": "Term of afkorting",
      "expanded": "Volledige uitgeschreven vorm of hetzelfde als naam",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Beknopte definitie in context (MAXIMAAL {MAX_TERM_DEF} tekens)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
De gebruiker heeft het woord "%s" gemarkeerd.
TAAK: Bepaal of dit woord een Personage, Locatie, Historische Figuur of Technische Term/Afkorting in het boek vertegenwoordigt.

CRUCIAAL VOOR PERSONAGES EN LOCATIES: Gebruik de verstrekte "BOOK TEXT CONTEXT" om de entiteit te identificeren. Als het woord is voorzien van een "SEARCH TARGET" of "DIRECT REFERENCE" hint, is het aanwezig in het boek op de huidige positie. Wijs het niet af alleen omdat het niet exact in de sub-gesamplede verhalende tekst wordt gevonden. Korte namen (zo kort als 2 letters, bijv. "Oz", "Al", "Jo") zijn geldig en moeten worden geanalyseerd.
CRUCIAAL VOOR FICTIEVE PERSONAGES: Beschrijf UITSLUITEND wat de verstrekte boektekst onthult. Gebruik GEEN voorafgaande trainingskennis over dit personage, zelfs niet als u ze herkent uit een bekende serie. Als de tekst dit personage tot nu toe slechts kort noemt, moet uw beschrijving die beperkte informatie weerspiegelen.
CRUCIAAL VOOR HISTORISCHE FIGUREN: U MAG uw interne kennis gebruiken om hun identiteit te verifiëren en hun biografie/rol te verstrekken, UITSLUITEND als ze een echte, opvallende historische figuur zijn. U MOET nog steeds de tekstcontext gebruiken voor hun relevantie in het boek.
CRUCIAAL VOOR TERMEN: Als het boek non-fictie is, controleer dan of het woord een technische term, afkorting of sleutelconcept is. Geef de definitie in context.
Als het woord GEEN personage, locatie, historische figuur of technische term is, stelt u `is_valid` in op false.

VEREIST JSON-FORMAAT:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Volledige naam",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Kort archetype-label (3-5 woorden, bijv. 'Antagonist', 'Protagonist', 'Het slachtoffer')",
    "gender": "Man/Vrouw/Onbekend",
    "occupation": "Beroep",
    "description": "Korte beschrijving (MAXIMAAL 250 tekens)"
  },
  "error_message": ""
}

Opmerking: Als het type "location" is, moet het item "name" en "description" bevatten. Als het type "historical_figure" is, moet het item "name", "biography" en "role" bevatten. Als het type "term" is, moet het item "name", "expanded", "category" en "definition" bevatten.

Als `is_valid` false is:
{
  "is_valid": false,
  "error_message": "Korte uitleg waarom dit geen personage of locatie is."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
TAAK: Combineer de volgende twee beschrijvingen van dezelfde entiteit (personage of locatie) tot één samenhangende en beknopte samenvatting.
Verwijder overtollige informatie en zorg ervoor dat de uiteindelijke beschrijving natuurlijk verloopt.

Primaire beschrijving: %s
Secundaire beschrijving: %s

VEREIST JSON-FORMAAT:
{
  "merged_description": "Gecombineerde en gepolijste beschrijving (Max {MAX_CHAR_DESC} tekens)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Boektitel: %s
Auteur: %s
Serie: %s
Bestandsbeschrijving/Onderwerpmetadata: %s

TAAK: Classificeer dit boek in exact ÉÉN van deze boektypen op basis van de metadata en genresignalen:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Geef ALLEEN geldige JSON terug:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Boektitel: %s
Auteur: %s

TAAK: Bepaal of dit boek deel uitmaakt van een benoemde serie.
Geef UITSLUITEND geldige JSON als resultaat:
{
  "is_series": true,
  "series_name": "Het Rad des Tijds",
  "book_index": 3,
  "total_books_known": 14
}
Als dit GEEN serieboek is, geef dan als resultaat:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Serie: %s
Huidige boekindex: %d
Huidige boektitel: %s

TAAK: Lijst de titels (en auteurs indien verschillend van "%s") op van boeken 1 tot en met %d
die VOORAFGAAN aan het huidige boek in deze serie.
Geef UITSLUITEND geldige JSON als resultaat:
{
  "prior_books": [
    { "index": 1, "title": "Het Oog van de Wereld", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
DOELBOEK: %s
AUTEUR: %s
DOELBOEKINDEX: %d
SERIE: %s

TAAK:
Geef UITSLUITEND een VOLLEDIGE samenvatting van DOELBOEK, voor een lezer die DOELBOEK uit heeft en op het punt staat te beginnen aan het volgende boek in de serie.

ABSOLUTE SPOILERGRENS:
Kennisgrens is strikt de LAATSTE PAGINA van DOELBOEK (Boekindex %d).
Je mag feiten opnemen die zijn vastgesteld in DOELBOEK of eerdere boeken in deze serie.
Je MAG GEEN details opnemen, impliceren, hierop zinspelen, vooruitwijzen of selecteren met gebruik van kennis uit een later boek.

VERBODEN INFORMATIE UIT LATERE BOEKEN:
- Latere gebeurtenissen, toekomstige lotgevallen, sterfgevallen, overlevingen, bestemmingen, romances, bondgenootschappen, conflicten of verraad.
- Identiteiten uit latere boeken, ware oorsprong, geheime afkomst, schuilnamen, alter ego's, reïncarnaties, transformaties, titels of krachtsontwikkelingen (bijv. vermeld NIET of een essentie zich bij een andere voegt of herboren wordt in een volgend boek).
- Onthullingen, bevestigingen, herinterpretaties, wendingen of wereldopbouw-terminologie die in latere boeken wordt geïntroduceerd.
- Retrospectieve vooruitwijzingen of zinnen zoals "later", "uiteindelijk", "zal worden", "in latere boeken" of gelijkwaardig.
- Het vermelden van personages, concepten, organisaties of chronologie uit latere boeken.

PERSONAGEGRENS:
Beschrijf elk personage strikt zoals bekend op de laatste pagina van DOELBOEK.
Gebruik GEEN schuilnamen, rollen, relaties, ware identiteiten of statussen die in latere boeken worden onthuld.

ONZEKERHEIDSREGEL:
Als je niet met zekerheid kunt vaststellen of een feit of schuilnaam aan het einde van DOELBOEK is vastgesteld, LAAT HET DAN WEG.
Het ontbreken van een detail is veruit te verkiezen boven een spoiler voor een toekomstig boek.

EINDCONTROLE:
Inspecteer elk veld (vooral personagebeschrijvingen en schuilnamen) voordat je JSON retourneert en verwijder alles wat afhankelijk is van kennis uit boeken na DOELBOEK.

VEREIST JSON-FORMAAT:
{
  "characters": [
    { "name": "Full Name", "aliases": [], "role": "...", "description": "Status aan het einde van dit boek (max {MAX_CHAR_DESC} tekens)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Boeksamenvatting", "event": "Eén enkele, zeer gedetailleerde, uitgebreide samenvatting van het gehele plot van het boek, de belangrijkste gebeurtenissen en de ontknoping (max 2000 tekens). Je MOET deze samenvatting opmaken met behulp van meerdere afzonderlijke alinea's gescheiden door dubbele regeleinden (\\n\\n) voor de leesbaarheid in plaats van één enkele muur van tekst." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
DOELBOEK: %s
AUTEUR: %s
DOELBOEKINDEX: %d
SERIE: %s

OPDRACHT:
Schrijf met GEBRUIK VAN ALLEEN de onderstaande geverifieerde gebeurtenissen per hoofdstuk uit DOELBOEK een samenhangende, volledige samenvatting van de gehele plot, de belangrijkste ontwikkelingen en de ontknoping van het boek.

STRIKTE KADERBEPERKING:
- Baseer je samenvatting UITSLUITEND op de verstrekte hoofdstukgebeurtenissen.
- Introduceer GEEN feiten, personages, gebeurtenissen of uitkomsten die niet in deze hoofdstukgebeurtenissen worden beschreven.
- Vermeld of zinspeel NOOIT op gebeurtenissen, sterfgevallen of ontwikkelingen uit latere boeken in de serie.

HOOFDSTUKGEBEURTENISSEN:
%s

VEREIST JSON-FORMAAT:
{
  "timeline": [
    { "chapter": "Boeksamenvatting", "event": "Eén enkele, zeer gedetailleerde, volledige samenvatting van de gehele plot en ontknoping van het boek (maximaal 2000 tekens). Je MOET deze samenvatting opmaken met meerdere afzonderlijke alinea's gescheiden door dubbele nieuwe regels (\\n\\n) voor de leesbaarheid in plaats van één grote muur van tekst." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Boek: %s
Auteur: %s
Hoofdstuk analyseren: %s

TAAK: Analyseer UITSLUITEND dit enkele hoofdstuk. Identificeer NIEUWE entiteiten die in dit hoofdstuk worden geïntroduceerd, en DELTA-UPDATES (toestandsovergangen) voor bestaande entiteiten.
Geef UITSLUITEND een geldig JSON-object output.

MANIFEST VAN BESTAANDE BEKENDE ENTITEITEN (Niet opnieuw extraheren tenzij hun rol, status of beschrijving aanzienlijk is geëvolueerd):
%s

REGELS:
1. STRIKTE BEPERKING TOT SPOILERS: Analyseer UITSLUITEND de opgegeven hoofdstuktekst. Gebruik GEEN enkele kennis uit toekomstige hoofdstukken of externe bronnen.
2. DIEPTE EN SUBSTANTIE VAN PERSONAGEBESCHRIJVING (CRUCIAAL):
   - Onderbouwd & Specifiek: Beschrijf wie het personage is met concrete verhaalfeiten—hun achtergrond, unieke persoonlijkheid, beroep, belangrijkste relaties met andere personages, en hun specifieke rol en persoonlijke belangen in het verhaal.
   - Significante Narratieve Context: Verbind het personage rechtstreeks met het centrale mysterie, het plotconflict of het onderzoek in dit boek (bijv. welke misdrijven of zaken ze onderzoeken, wie hen heeft ingehuurd, belangrijke bondgenoten of tegenstanders, specifieke persoonlijke dilemma's of spanningen).
   - NIET Te Algemeen: Schrijf GEEN generieke clichématige samenvattingen (vermijd bijv. lege frasen zoals "een rechercheur die complexe zaken onderzoekt"). Noem de specifieke omstandigheden, connecties en belangen die in de tekst zijn vastgesteld.
   - GEEN Samenvattingen van Alledaagse Beslommeringen: Schrijf GEEN chronologische logboeken van alledaagse activiteiten of routineklusjes (vat bijv. GEEN uitstapjes naar de supermarkt, routineuze telefoontjes of incidentele verplaatsingen van scène tot scène samen).
   - Personagebeschrijvingen moeten rijke, levendige profielen zijn die samenvatten wie ze zijn en wat hun betekenis is tot aan dit punt in het boek.
3. HOGE DREMPEL VOOR UPDATES VAN PERSONAGES:
   - Maak GEEN update aan in `character_state_updates` louter omdat een bestaand personage in dit hoofdstuk verscheen, sprak of routinehandelingen uitvoerde.
   - Genereer ALLEEN een update als er sprake is van een substantiële, blijvende transformatie in hun narratieve arc, identiteit, relaties, werk, loyaliteit of toestand (bijv. gedood, gewond, gearresteerd, verraden, verloofd, gepromoveerd, onthuld als de schuldige, of als er een groot geheim of motief is ontdekt).
   - Als een update WEL gerechtvaardigd is, moet de bijgewerkte `description` een rijk, cumulatief personage-overzicht zijn waarin de nieuwe ontwikkelingen zijn verwerkt, terwijl hun kernidentiteit en de reeds vastgestelde verhaalcontext behouden blijven—dus GEEN samenvatting van een geïsoleerde scène.
4. PAGINAMARKERINGEN BINNEN HOOFDSTUKKEN ([PAGE N]) & NUL SPOILER-BEPERKING:
   - Hoofdstukteksten bevatten [PAGE N]-markeringen die de paginavoortgang aangeven.
   - Geef voor `new_characters`, `new_locations` en `new_terms`: "first_page" (geheel getal N uit de [PAGE N]-markering waar de entiteit voor het eerst wordt genoemd), "intro_role" (voor personages) en "intro_description" (1-2 zinnen strikt beperkt tot wat bekend is bij hun eerste introductie op [PAGE first_page]—met absoluut NUL kennis van latere wendingen, geheimen of uitkomsten op latere pagina's). Geef ook "page" (de [PAGE N]-markering waar de uitgebreidere cumulatieve "description" van toepassing is, typisch de laatste pagina van het hoofdstuk).
   - Geef voor `character_state_updates`, `location_state_updates` en `term_state_updates`: "page" (geheel getal N uit de [PAGE N]-markering waar de onthulling/transitie is voltooid; onthul GEEN feiten vóór deze pagina).
5. BEWIJS: Geef een korte verwijzing of een geciteerd fragment uit dit hoofdstuk uit waarin wordt uitgelegd waarom de update heeft plaatsgevonden.
6. TIJDLIN: Geef precies één gebeurtenissamenvatting van de belangrijkste plotacties in dit hoofdstuk.

VEREIST JSON-FORMAAT:
{
  "new_characters": [
    {
      "name": "Volledige naam",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Initiële rol (bijv. Dorpsklerk, Vreemdeling, Cliënt)",
      "intro_description": "Initiële impressie van 1-2 zinnen strikt bij de eerste introductie, nul spoilers van latere pagina's.",
      "page": 99,
      "role": "Narratieve rol / belang (bijv. Protagonist, Privédetective, Partner, Antagonist, Slachtoffer, Cliënt, Verdachte, Secundair personage, Bijfiguur)",
      "status": "alive",
      "description": "Rijke, specifieke personagebeschrijving (achtergrond, relaties, narratieve belangen). Vermijd generieke blurbs en samenvattingen van alledaagse beslommeringen.",
      "evidence": "Kort fragment"
    }
  ],
  "character_state_updates": [
    {
      "name": "Naam die overeenkomt met bekende manifest",
      "page": 95,
      "role": "Bijgewerkte narratieve rol / belang (bijv. Protagonist, Partner, Antagonist, Secundair personage, etc.)",
      "status": "alive",
      "change": "Eén korte zin waarin staat wat er is veranderd sinds de vorige toestand (bijv. 'Gepromoveerd tot partner na de Shacklewell-zaak')",
      "description": "Bijgewerkte rijke, cumulatieve personagebeschrijving die hun nieuwe status en verhaalbelangen weerspiegelt",
      "evidence": "Kort fragment"
    }
  ],
  "new_locations": [
    {
      "name": "Locatienaam",
      "first_page": 80,
      "intro_description": "Initiële impressie bij eerste vermelding.",
      "page": 99,
      "description": "Beschrijving van locatie",
      "evidence": "Kort fragment"
    }
  ],
  "location_state_updates": [
    {
      "name": "Naam die overeenkomt met bekende manifest",
      "page": 95,
      "change": "Eén korte zin waarin staat wat er is veranderd (bijv. 'Verwoest tijdens de slag om Oakhaven')",
      "description": "Bijgewerkte geëvolueerde beschrijving",
      "evidence": "Kort fragment"
    }
  ],
  "new_terms": [
    {
      "name": "Termnaam",
      "first_page": 80,
      "intro_description": "Initiële definitie bij eerste vermelding.",
      "page": 99,
      "description": "Definitie of lore-uitleg",
      "evidence": "Kort fragment"
    }
  ],
  "term_state_updates": [
    {
      "name": "Naam die overeenkomt met bekende manifest",
      "page": 95,
      "change": "Eén korte zin waarin staat wat er is veranderd in begrip of gebruik",
      "description": "Bijgewerkte definitie",
      "evidence": "Kort fragment"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Samenvatting van gebeurtenissen in dit hoofdstuk"
  }
}

HOOFDSTUKTEKST:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Boek: %s
Auteur: %s
Hoofdstukken in deze batch: %s

TAAK: Analyseer de opgegeven opeenvolgende batch hoofdstukken in volgorde.
Identificeer voor ELK hoofdstuk in de batch:
1. NIEUWE entiteiten die in dat hoofdstuk worden geïntroduceerd (personages, locaties, termen).
2. DELTA-UPDATES (toestandsveranderingen) voor bestaande bekende entiteiten (uit het manifest OF geïntroduceerd in een eerder hoofdstuk van deze batch) ALS EN SLECHTS ALS hun rol, status, loyaliteit of narratieve toestand een substantiële, blijvende verandering heeft ondergaan.
3. TIMELINE EVENT: Een beknopte samenvatting van de belangrijkste gebeurtenissen in het verhaal van dat hoofdstuk.

Genereer ALLEEN een geldig JSON-object dat voldoet aan het vereiste schema.

MANIFEST VAN BESTAANDE BEKENDE ENTITEITEN (uit eerdere batches - NIET opnieuw extraheren tenzij hun rol, status of beschrijving aanzienlijk is geëvolueerd):
%s

REGELS:
1. STRIKTE SPOILERBEPERKING & OPEENVOLGENDE PROGRESSIE:
   - Analyseer de hoofdstukken in chronologische volgorde.
   - Gebruik voor een hoofdstuk in deze batch GEEN kennis uit latere hoofdstukken in de batch of uit de rest van het boek.
2. DIEPGANG & SUBSTANTIE VAN PERSONAGEBESCHRIJVINGEN (CRICIAAL):
   - Gecentreerd & Specifiek: Beschrijf wie het personage is met concrete feiten uit het verhaal—hun achtergrond, unieke persoonlijkheid, beroep, belangrijke relaties met andere personages, en hun specifieke rol en persoonlijke belangen in het verhaal.
   - Significante narratieve context: Verbind het personage rechtstreeks met het centrale mysterie, het plotconflict of het onderzoek in dit boek (bijv. welke misdrijven of zaken ze onderzoeken, wie hen heeft ingehuurd, belangrijke bondgenoten of tegenstanders, specifieke persoonlijke dilemma's of spanningen).
   - NIET te algemeen: Schrijf GEEN generieke clichébeschrijvingen (vermijd bijv. lege frasen zoals "een rechercheur die complexe zaken onderzoekt"). Noem de specifieke omstandigheden, connecties en belangen die in de tekst zijn vastgelegd.
   - GEEN samenvattingen van alledaagse handelingen: Schrijf GEEN chronologische logboeken van alledaagse activiteiten of routineklusjes (vat bijv. GEEN tripjes naar de supermarkt, routineuze telefoontjes of bijkomstige verplaatsingen van scène tot scène samen).
   - Personagebeschrijvingen moeten rijke, levendige profielen zijn die samenvatten wie ze zijn en wat hun betekenis is tot aan dit punt in het boek.
3. HOGE DREMPEL VOOR UPDATES VAN PERSONAGES:
   - Maak NIET zomaar een update aan in `character_state_updates` omdat een bestaand personage in een hoofdstuk verscheen, sprak of routinehandelingen uitvoerde.
   - Genereer ALLEEN een update als er sprake is van een substantiële, blijvende verandering in hun verhaallijn, identiteit, relaties, werk, loyaliteit of toestand (bijv. gedood, gewond, gearresteerd, verraden, verloofd, gepromoveerd, ontmaskerd als de dader, een groot geheim of motief onthuld).
   - Als een update WEL gerechtvaardigd is, moet de bijgewerkte `description` een rijk, cumulatief overzicht van het personage zijn dat de nieuwe ontwikkelingen bevat en tegelijkertijd hun kernidentiteit en gevestigde verhaalcontext behoudt—GEEN samenvatting van een geïsoleerde scène.
4. PAGINAMARKERINGEN IN HET HOOFDSTUK ([PAGE N]) & NUL-SPOILER-BEPERKING:
   - Hoofdstukteksten bevatten [PAGE N]-markeringen die de paginavoortgang aangeven.
   - Voor `new_characters`, `new_locations` en `new_terms`: geef "first_page" (geheel getal N uit de [PAGE N]-markering waar de entiteit voor het eerst wordt genoemd), "intro_role" (voor personages), en "intro_description" (1-2 zinnen die zich strikt beperken tot wat bekend is bij hun eerste introductie op [PAGE first_page]—met NUL kennis van latere wendingen, geheimen of uitkomsten op latere pagina's). Geef ook "page" (de [PAGE N]-markering waarop de volledigere cumulatieve "description" van toepassing is, meestal de laatste pagina van het hoofdstuk).
   - Voor `character_state_updates`, `location_state_updates` en `term_state_updates`: geef "page" (geheel getal N uit de [PAGE N]-markering waar de onthulling/transitie is voltooid; onthul GEEN feiten vóór deze pagina).
5. BEWIJS: Geef een korte referentie of een geciteerd fragment uit dat specifieke hoofdstuk waarin wordt uitgelegd waarom de update heeft plaatsgevonden.
6. JSON-VEILIGHEID: Voer uitsluitend geldige JSON uit. Escape dubbele quotes in strings op de juiste wijze.

VEREIST JSON-FORMAT:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Hoofdstuktitel",
      "timeline_event": "Samenvatting van de belangrijkste ontwikkelingen in de plot van dit hoofdstuk.",
      "new_characters": [
        {
          "name": "Volledige naam",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Aanvankelijke rol (bijv. Dorpsambtenaar, Vreemdeling, Cliënt)",
          "intro_description": "Eerste indruk in 1-2 zinnen strikt bij de eerste introductie, nul spoilers van latere pagina's.",
          "page": 99,
          "role": "Narratieve rol / belang (bijv. Protagonist, Privédetective, Partner, Antagonist, Slachtoffer, Cliënt, Verdachte, Secundair personage, Bijfiguur)",
          "status": "alive",
          "description": "Rijke, specifieke beschrijving van het personage (achtergrond, relaties, belangen in het verhaal). Vermijd generieke clichés en samenvattingen van alledaagse handelingen.",
          "evidence": "Kort fragment"
        }
      ],
      "character_state_updates": [
        {
          "name": "Naam die overeenkomt met bekend manifest of personage dat in een eerder hoofdstuk van deze batch is geïntroduceerd",
          "page": 95,
          "role": "Bijgewerkte narratieve rol / belang (bijv. Protagonist, Partner, Antagonist, Secundair personage, enz.)",
          "status": "alive",
          "change": "Eén korte zin waarin wordt benoemd wat er is veranderd sinds de vorige toestand (bijv. 'Gepromoveerd tot partner na de Shacklewell-zaak')",
          "description": "Bijgewerkte rijke, cumulatieve personagebeschrijving waarin de nieuwe ontwikkelingen en belangen in het verhaal tot uiting komen",
          "evidence": "Kort fragment"
        }
      ],
      "new_locations": [
        {
          "name": "Locatienaam",
          "first_page": 80,
          "intro_description": "Eerste indruk bij eerste vermelding.",
          "page": 99,
          "description": "Beschrijving van de locatie",
          "evidence": "Kort fragment"
        }
      ],
      "location_state_updates": [
        {
          "name": "Naam die overeenkomt met bekend manifest of locatie die in een eerder hoofdstuk van deze batch is geïntroduceerd",
          "page": 95,
          "change": "Eén korte zin waarin wordt benoemd wat er is veranderd (bijv. 'Verwoest tijdens de slag om Oakhaven')",
          "description": "Bijgewerkte beschrijving",
          "evidence": "Kort fragment"
        }
      ],
      "new_terms": [
        {
          "name": "Termnaam",
          "first_page": 80,
          "intro_description": "Aanvankelijke definitie bij eerste vermelding.",
          "page": 99,
          "description": "Definitie of uitleg van lore",
          "evidence": "Kort fragment"
        }
      ],
      "term_state_updates": [
        {
          "name": "Naam die overeenkomt met bekend manifest of term die in een eerder hoofdstuk van deze batch is geïntroduceerd",
          "page": 95,
          "change": "Eén korte zin waarin wordt benoemd wat er is veranderd in begrip of gebruik",
          "description": "Bijgewerkte definitie",
          "evidence": "Kort fragment"
        }
      ]
    }
  ]
}

HOOFDSTUKTEKSTEN IN DEZE BATCH:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analyseer de volgende boekdetails en inhoudsopgave:

Titel: %s
Auteur: %s
Onderwerpen: %s
Beschrijving: %s

Inhoudsopgave:
%s

Bepaal of dit werk het volgende is:
1. "anthology" (een verzameling onafhankelijke korte verhalen, essays of novelles, elk met een eigen afgeronde verhaallijn of personages, bijv. "The Adventures of Sherlock Holmes", "Dubliners", "Exhalation", "Men Without Women").
2. "novel" (één samenhangende roman onderverdeeld in hoofdstukken, delen of bedrijven, bijv. "Pride and Prejudice", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (een meerdelige verzameling van volledige romans die samen in één band zijn uitgegeven, bijv. "The Lord of the Rings: All Three Volumes", "The Complete Hitchhiker's Guide to the Galaxy", "Percy Jackson: Books 1-3").
4. "non_fiction" (één non-fictieverhandeling, geschiedkundig werk of academisch boek onderverdeeld in hoofdstukken).

Retourneer ALLEEN een JSON-object met:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 tot 1.0,
  "reasoning": "korte uitleg (één zin)"
}]],

    -- System instruction
    system_instruction = "U bent een deskundige literatuuronderzoeker. Uw antwoord mag UITSLUITEND in een geldig JSON-formaat zijn. Zorg ervoor dat de gegevens zeer nauwkeurig zijn en strikt betrekking hebben op de verstrekte context.",

    -- Fallback strings
    fallback = {
        no_biography = "Geen biografie beschikbaar",
        no_description = "Geen beschrijving",
        not_specified = "Niet gespecificeerd",
        unknown_author = "Onbekende auteur",
        unknown_book = "Onbekend boek",
        unnamed_character = "Naamloos personage",
        unnamed_person = "Naamloos persoon"
    }
}
