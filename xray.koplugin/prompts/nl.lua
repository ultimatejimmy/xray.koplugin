return {
    -- System instruction
    system_instruction = "U bent een deskundige literatuuronderzoeker. Uw antwoord mag UITSLUITEND in een geldig JSON-formaat zijn. Zorg ervoor dat de gegevens zeer nauwkeurig zijn en strikt betrekking hebben op de verstrekte context.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identificeer en verstrek een biografie voor de auteur van het boek "%s". 
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

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Boek: %s
Auteur: %s
Leesvoortgang: %d%%

TAAK: Voer een volledige X-Ray analyse uit. Geef UITSLUITEND een geldig JSON-object als resultaat.

CRUCIALE VERDELING VAN DE AANDACHT:
U verwerkt een enorm document met twee tekstblokken aan het einde van deze prompt:
1. "CHAPTER SAMPLES": Dit is de macro-context van het boek tot aan de huidige locatie van de lezer.
2. "BOOK TEXT CONTEXT": Dit is de micro-context van de meest recente 20k tekens.

ANTI-AFKAPPROTOCOL (CRUCIAAL):
U heeft een strikte maximale uitvoerlimiet. Als de "CHAPTER SAMPLES" MEER DAN 40 hoofdstukken bevat (bijv. een omnibus-editie):
1. U MOET de lijst met personages beperken tot UITSLUITEND de top 10 absoluut belangrijkste personages.
2. U MOET personagebeschrijvingen beperken tot MAXIMAAL {MAX_CHAR_DESC} tekens.
3. U MOET samenvattingen van tijdlijngebeurtenissen beperken tot MAXIMAAL {MAX_TIMELINE_EVENT} tekens.
Als u uw uitvoer voor omvangrijke boeken niet comprimeert, zal de JSON worden afgekapt en mislukken.

ALGORITME VOOR TIJDLIJN (HOOGSTE PRIORITEIT):
Om te voorkomen dat hoofdstukken worden overgeslagen of gebeurtenissen worden gefantaseerd, MOET u exact deze lus uitvoeren:
Stap 1. Kijk UITSLUITEND naar het blok "CHAPTER SAMPLES". Identificeer de verhalende hoofdstukken.
Stap 2. SLUIT alle niet-verhalende inleidingen en nawoorden UIT (bijv. Omslag, Titelpagina, Auteursrecht, Inhoudsopgave, Opdracht, Dankwoord, Ook van).
Stap 3. Maak voor elk verhalend hoofdstuk, beginnend bij het allereerste, PRECIES ÉÉN gebeurtenisobject aan in de `timeline`-array.
Stap 4. Het veld `chapter` MOET exact overeenkomen met de hoofdstuktitel in het voorbeeld. (Koppel ze strikt in opeenvolgende volgorde).
Stap 5. Samenvat dit specifieke hoofdstuk in het veld `event` {TIMELINE_DETAIL_GUIDANCE} (MAXIMAAL {MAX_TIMELINE_EVENT} tekens). Gropeer hoofdstukken NIET.
Stap 6. GEEN SPOILERS: Stop exact bij de %d%%-grens. Neem geen gebeurtenissen op na deze voortgang.

ALGORITME VOOR PERSONAGES & HISTORISCHE FIGUREN:
Stap 1. Extraheer belangrijke personages met behulp van beide tekstblokken. ({NUM_CHARS} normaal, MAXIMAAL 10 bij een omnibus).
Stap 2. U MOET hun VOLLEDIGE, formele namen gebruiken (bijv. "Abraham Van Helsing"). Gebruik GEEN informele bijnamen als de hoofdnaam.
Stap 3. Geef maximaal 3 alternatieve namen, titels of bijnamen op waaronder dit personage bekend staat in een `aliases`-array. Neem hun veelgebruikte voornaam en achternaam op indien gebruikt. BELANGRIJK: Als een achternaam wordt gedeeld door meerdere personages (bijv. familieleden), neem deze dan NIET op als alias voor een van de personages.
Stap 4. Scan actief op maximaal {NUM_HIST} OPVALLENDE ECHTE mensen uit de menselijke geschiedenis (bijv. presidenten, auteurs, generaals). Voeg ze toe aan `historical_figures`.
CRUCIAAL voor Personages & Historische Figuren:
- Extraheer GEEN personages of historische figuren die UITSLUITEND worden genoemd in niet-verhalende inleidingen of nawoorden (bijv. Dankwoord, Biografie van de auteur, Opdrachten, Titelpagina, Auteursrecht).
- Historische figuren MOETEN geverifieerde, echte mensen zijn met brede historische erkenning.
- Neem GEEN puur fictieve personages op in de lijst met historische figuren, zelfs niet als ze interageren met echte historische gebeurtenissen. Fictieve personages MOETEN in de `characters`-array.
- Uitsluitend voor Historische Figuren mag u uw interne kennis gebruiken om hun algemene `biography` en historische `role` te schrijven, maar u MOET de boekcontext gebruiken voor hun `context_in_book`.
GEEN SPOILERS: Stop exact bij de %d%%-grens.

ALGORITME VOOR LOCATIES:
Stap 1. Extraheer {NUM_LOCS} belangrijke locaties. GEEN SPOILERS: Stop exact bij de %d%%-grens.

ALGORITME VOOR TERMEN:
Stap 0. Verklaar "book_type" als "fiction" of "non_fiction" in de JSON-root.
Stap 1. Indien non-fictie: extraheer {NUM_TERMS} belangrijke technische termen, afkortingen, jargon of concepten die lezers zonder specialistische kennis niet zouden kennen. Gebruik geschikte categorieën zoals Acronym, Technical Term, Concept of Jargon.
Stap 2. Indien fictie: extraheer {NUM_TERMS} belangrijke elementen van wereldopbouw die een nieuwe lezer uitgelegd zou moeten krijgen—zoals verzonnen facties, organisaties, magische systemen, technologieën, wezens, talen of in-universum overlevering.
   - Neem GEEN personagenamen of locatienamen op (die worden apart bijgehouden).
   - Extraheer GEEN alledaagse woorden of concepten uit de echte wereld.
   - Gebruik geschikte categorieën: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Stap 3. Neem op waar de afkorting/zin voor staat in "expanded". Als het geen afkorting/zin is, herhaal dan de naam.
Stap 4. Neem GEEN alledaagse woorden op.

STRIKTE SPOILERREGELS:
- ABSOLUUT GEEN informatie van na de huidige leesvoortgang. Stop exact bij de %d%%-grens.
- Beschrijvingen moeten de staat van de personages op dit exacte punt in het boek weerspiegelen.

STRIKTE REGELS VOOR KENNISBRONNEN (CRUCIAAL):
- Voor FICTIEVE PERSONAGES: Uw beschrijvingen MOETEN UITSLUITEND gebaseerd zijn op wat expliciet is vermeld of duidelijk wordt geïmpliceerd in de verstrekte tekst. Vul dit NIET aan met kennis uit eerdere trainingen, externe bronnen of algemene bekendheid met het boek/de serie/de auteur.
- Als een personage tot nu toe slechts kort in de tekst is genoemd, moet uw beschrijving uitsluitend die beperkte informatie weerspiegelen. Trek geen conclusies, doe geen aannames en voeg geen details toe die niet in de verstrekte context zijn onderbouwd.
- De ENIGE uitzondering is voor ECHTE HISTORISCHE FIGUREN (geplaatst in `historical_figures`): u mag interne kennis gebruiken voor hun algemene biografie/rol, maar u moet nog steeds vertrouwen op de boektekst voor hun `context_in_book`.

STRIKTE JSON-VEILIGHEIDSREGELS:
- U MOET alle dubbele aanhalingstekens (\") binnen strings correct escapen.
- Gebruik GEEN onontsnapte regelafbrekingen binnen strings.
- Voer UITSLUITEND geldige, parseerbare JSON uit.

VEREIST JSON-FORMAAT:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Volledige formele naam",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Kort archetype-label (3-5 woorden, bijv. 'Antagonist', 'Protagonist', 'Het slachtoffer')",
      "gender": "Man / Vrouw / Onbekend",
      "occupation": "Beroep/Status",
      "description": "Beschrijving STRIKT gebaseerd op de verstrekte tekst. Trek geen conclusies en voeg geen externe kennis toe. GEEN SPOILERS. (Max {MAX_CHAR_DESC} tekens)"
    }
  ],
  "historical_figures": [
    {
      "name": "Echte naam historische persoon",
      "role": "Historische rol",
      "biography": "Korte biografie (MAXIMAAL {MAX_HIST_BIO} tekens)",
      "importance_in_book": "Betekenis tot aan de huidige voortgang",
      "context_in_book": "Hoe ze worden genoemd (MAXIMAAL 100 tekens)"
    }
  ],
  "locations": [
    {"name": "Plaatsnaam", "description": "Korte beschrijving (MAXIMAAL {MAX_LOC_DESC} tekens)"}
  ],
  "terms": [
    {
      "name": "Term of afkorting",
      "expanded": "Volledige uitgeschreven vorm of hetzelfde als naam",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Beknopte definitie in context (MAXIMAAL {MAX_TERM_DEF} tekens)"
    }
  ],
  "timeline": [
    {
      "chapter": "Exacte hoofdstuktitel uit voorbeelden",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Boek: %s
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

    -- Fetch More Terms (Glossary Support)
    more_terms = [[Boek: %s
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

    single_word_lookup = [[De gebruiker heeft het woord "%s" gemarkeerd.
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

    -- Smart Merge Descriptions
    merge_descriptions = [[TAAK: Combineer de volgende twee beschrijvingen van dezelfde entiteit (personage of locatie) tot één samenhangende en beknopte samenvatting.
Verwijder overtollige informatie en zorg ervoor dat de uiteindelijke beschrijving natuurlijk verloopt.

Primaire beschrijving: %s
Secundaire beschrijving: %s

VEREIST JSON-FORMAAT:
{
  "merged_description": "Gecombineerde en gepolijste beschrijving (Max {MAX_CHAR_DESC} tekens)"
}]],

    -- Multi-Book Series Context Prompts
    series_detect = [[Boektitel: %s
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

    prior_book_list = [[Serie: %s
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

    series_book_summary = [[Boek: %s
Auteur: %s
Dit is boek %d in de serie "%s".

TAAK: Geef een VOLLEDIGE samenvatting van dit hele boek voor een lezer
die op het punt staat te BEGINNEN aan het VOLGENDE boek in de serie.
Neem op: belangrijke personages (naam, rol, eindstatus aan het einde van het boek), belangrijke locaties,
cruciale plotgebeurtenissen en belangrijke termen voor wereldopbouw die zijn geïntroduceerd.
GEEN SPOILERS voor boeken HIERNA.

VEREIST JSON-FORMAAT:
{
  "characters": [
    { "name": "Volledige naam", "aliases": [], "role": "...", "description": "Status aan het einde van dit boek (max 300 tekens)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Boeksamenvatting", "event": "Een enkele, zeer gedetailleerde, uitgebreide samenvatting van het plot, de belangrijkste gebeurtenissen en de ontknoping van het hele boek (max 2000 tekens). U MOET deze samenvatting opmaken met behulp van meerdere verschillende alinea's gescheiden door dubbele regeleinden (\\n\\n) voor de leesbaarheid in plaats van een enkele muur van tekst." }
  ]
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

-- Fallback strings
    fallback = {
        unknown_book = "Onbekend boek",
        unknown_author = "Onbekende auteur",
        unnamed_character = "Naamloos personage",
        not_specified = "Niet gespecificeerd",
        no_description = "Geen beschrijving",
        unnamed_person = "Naamloos persoon",
        no_biography = "Geen biografie beschikbaar"
    }
}

