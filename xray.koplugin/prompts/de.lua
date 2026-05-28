return {
    -- System instruction
    system_instruction = "Sie sind ein erfahrener Literaturforscher. Ihre Antwort muss AUSSCHLIESSLICH im gültigen JSON-Format erfolgen. Stellen Sie sicher, dass die Daten hochpräzise sind und sich strikt auf den bereitgestellten Kontext beziehen.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identifizieren und erstellen Sie eine Biografie für den Autor des Buches "%s". 
Die Metadaten deuten darauf hin, dass der Autor "%s" ist. 

WICHTIG: Überprüfen Sie den Autor anhand des BUCHTEXT-KONTEXTES (falls am Ende dieses Prompts angegeben), um eine 100%%ige Genauigkeit zu gewährleisten und Fehlidentifikationen zu vermeiden.

ERFORDERLICHES JSON-FORMAT:
{
  "author": "Vollständiger korrekter Name",
  "author_bio": "Umfassende Biografie mit Schwerpunkt auf der literarischen Karriere und den Hauptwerken.",
  "author_birth": "Geburtsdatum, formatiert nach lokalem Datumsformat",
  "author_death": "Sterbedatum, formatiert nach lokalem Datumsformat"
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Buch: %s
Autor: %s
Lesefortschritt: %d%%

AUFGABE: Führen Sie eine vollständige X-Ray-Analyse durch. Geben Sie NUR ein gültiges JSON-Objekt aus.

KRITISCHE AUFMERKSAMKEITSPARTITIONIERUNG:
Sie verarbeiten ein umfangreiches Dokument mit zwei Textblöcken am Ende dieses Prompts:
1. "CHAPTER SAMPLES": Dies ist der Makro-Kontext des Buches bis zum aktuellen Standort des Lesers.
2. "BOOK TEXT CONTEXT": Dies ist der Mikro-Kontext der letzten 20.000 Zeichen.

ANTI-TRUNKIERUNGSPROTOKOLL (WICHTIG):
Sie haben ein striktes maximales Ausgabelimit. Wenn die "CHAPTER SAMPLES" MEHR ALS 40 Kapitel enthalten (z. B. eine Sammelausgabe):
1. Sie MÜSSEN die Liste der Charaktere auf NUR die 10 absolut wichtigsten Charaktere reduzieren.
2. Sie MÜSSEN die Beschreibungen der Charaktere auf MAX. {MAX_CHAR_DESC} Zeichen reduzieren.
3. Sie MÜSSEN die Zusammenfassungen der Timeline-Ereignisse auf MAX. {MAX_TIMELINE_EVENT} Zeichen reduzieren.
Ein Versäumnis, Ihre Ausgabe für massive Bücher zu komprimieren, führt dazu, dass das JSON abgeschnitten wird und fehlschlägt.

ALGORITHMUS FÜR DIE TIMELINE (HÖCHSTE PRIORITÄT):
Um das Überspringen von Kapiteln oder Halluzinationen von Ereignissen zu verhindern, MÜSSEN Sie genau diese Schleife ausführen:
Schritt 1. Schauen Sie NUR in den Block "CHAPTER SAMPLES". Identifizieren Sie die erzählenden Kapitel.
Schritt 2. SCHLIESSEN Sie alle nicht-erzählenden Vorspann- und Nachspann-Elemente AUS (z. B. Cover, Titelseite, Copyright, Inhaltsverzeichnis, Widmung, Danksagung, Auch von).
Schritt 3. Erstellen Sie für jedes erzählende Kapitel, beginnend mit dem allerersten, GENAU EIN Ereignisobjekt im Array `timeline`.
Schritt 4. Das Feld `chapter` MUSS exakt mit der Kapitelüberschrift in der Stichprobe übereinstimmen. (Ordnen Sie diese strikt in sequentieller Reihenfolge zu).
Schritt 5. Fassen Sie dieses spezifische Kapitel im Feld `event` zusammen (MAX. {MAX_TIMELINE_EVENT} Zeichen). Gruppieren Sie KEINE Kapitel.
Schritt 6. KEINE SPOILER: Hören Sie genau bei der %d%%-Marke auf. Beziehen Sie keine Ereignisse nach diesem Fortschritt ein.

ALGORITHMUS FÜR CHARAKTERE & HISTORISCHE PERSONEN:
Schritt 1. Extrahieren Sie wichtige Charaktere aus beiden Textblöcken. ({NUM_CHARS} normale, MAX. 10 bei Sammelausgaben).
Schritt 2. Sie MÜSSEN deren VOLLSTÄNDIGEN, formellen Namen verwenden (z. B. "Abraham Van Helsing"). Verwenden Sie KEINE lockeren Spitznamen als Hauptnamen.
Schritt 3. Geben Sie bis zu 3 alternative Namen, Titel oder Spitznamen an, unter denen dieser Charakter bekannt ist, in einem Array `aliases`. Schließen Sie den üblichen Vornamen und Nachnamen ein, falls sie verwendet werden. WICHTIG: Wenn ein Nachname von mehreren Charakteren (z. B. Familienmitgliedern) geteilt wird, schließen Sie ihn für keinen der Charaktere als Alias ein.
Schritt 4. Suchen Sie aktiv nach bis zu {NUM_HIST} BEDEUTENDEN REALEN Personen der Menschheitsgeschichte (z. B. Präsidenten, Autoren, Generäle). Fügen Sie diese zu `historical_figures` hinzu.
WICHTIG für Charaktere & historische Personen:
- Extrahieren Sie KEINE Charaktere oder historischen Personen, die NUR in nicht-erzählerischen Vorspann- oder Nachspann-Elementen erwähnt werden (z. B. Danksagungen, Autorenbiografie, Widmungen, Titelseite, Copyright).
- Historische Personen MÜSSEN verifizierte reale Personen mit weitverbreiteter historischer Anerkennung sein.
- Schließen Sie KEINE rein fiktiven Charaktere in die Liste der historischen Personen ein, selbst wenn sie mit realen historischen Ereignissen interagieren. Fiktive Charaktere MÜSSEN in das `characters`-Array aufgenommen werden.
- NUR für historische Personen dürfen Sie Ihr internes Wissen verwenden, um deren allgemeine `biography` und historische `role` zu schreiben, aber Sie MÜSSEN den Buchkontext für deren `context_in_book` verwenden.
KEINE SPOILER: Hören Sie genau bei der %d%%-Marke auf.

ALGORITHMUS FÜR ORTE:
Schritt 1. Extrahieren Sie {NUM_LOCS} bedeutende Orte. KEINE SPOILER: Hören Sie genau bei der %d%%-Marke auf.

ALGORITHMUS FÜR BEGRIFFE:
Schritt 0. Deklarieren Sie "book_type" als "fiction" oder "non_fiction" im JSON-Stammverzeichnis.
Schritt 1. Falls non_fiction: Extrahieren Sie {NUM_TERMS} wichtige Fachbegriffe, Akronyme, Jargon oder Konzepte, die Leser ohne Fachwissen wahrscheinlich nicht kennen würden. Verwenden Sie passende Kategorien wie Acronym, Technical Term, Concept oder Jargon.
Schritt 2. Falls fiction: Extrahieren Sie {NUM_TERMS} bedeutende Elemente des Weltenbaus (World-building), die ein neuer Leser erklärt bekommen müsste – wie erfundene Fraktionen, Organisationen, Magiesysteme, Technologien, Kreaturen, Sprachen oder in-universe Lore.
   - Schließen Sie KEINE Charakter- oder Ortsnamen ein (diese werden separat erfasst).
   - Extrahieren Sie KEINE alltäglichen Wörter oder Konzepte der realen Welt.
   - Verwenden Sie passende Kategorien: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Schritt 3. Geben Sie in "expanded" an, wofür das Akronym/die Phrase steht. Wenn es kein Akronym/keine Phrase ist, wiederholen Sie den Namen.
Schritt 4. Schließen Sie KEINE alltäglichen Wörter ein.

STRIKTE SPOILER-REGELN:
- ABSOLUT KEINE Informationen nach dem aktuellen Lesefortschritt. Hören Sie genau bei der %d%%-Marke auf.
- Beschreibungen müssen den Zustand der Charaktere genau an diesem Punkt im Buch widerspiegeln.

STRIKTE REGELN ZUR WISSENSQUELLE (WICHTIG):
- FÜR FIKTIVE CHARAKTERE: Ihre Beschreibungen MÜSSEN AUSSCHLIESSLICH auf dem basieren, was im bereitgestellten Text explizit angegeben oder eindeutig impliziert ist. Ergänzen Sie dies NICHT durch Wissen aus früherem Training, externen Quellen oder allgemeiner Kenntnis des Buches/der Serie/des Autors.
- Wenn ein Charakter im bisherigen Text nur kurz erwähnt wurde, darf Ihre Beschreibung nur diese begrenzte Information widerspiegeln. Ziehen Sie KEINE Schlussfolgerungen, machen Sie keine Annahmen und fügen Sie keine Details hinzu, die nicht im bereitgestellten Kontext begründet sind.
- Die EINZIGE Ausnahme gilt für REALE HISTORISCHE PERSONEN (unter `historical_figures`): Sie dürfen internes Wissen für deren allgemeine Biografie/Rolle verwenden, müssen sich jedoch für deren `context_in_book` weiterhin auf den Buchtext verlassen.

STRIKTE JSON-SICHERHEITSREGELN:
- Sie MÜSSEN alle doppelten Anführungszeichen (\") innerhalb von Strings ordnungsgemäß escapen.
- Verwenden Sie KEINE unescaped Zeilenumbrüche innerhalb von Strings.
- Geben Sie NUR gültiges, parsbares JSON aus.

ERFORDERLICHES JSON-FORMAT:
{
  "characters": [
    {
      "name": "Vollständiger formeller Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rolle bis zum aktuellen Fortschritt",
      "gender": "Männlich / Weiblich / Unbekannt",
      "occupation": "Beruf/Status",
      "description": "Beschreibung basiert STRIKT auf dem bereitgestellten Text. Keine Schlussfolgerungen oder externes Wissen hinzufügen. KEINE SPOILER. (Max {MAX_CHAR_DESC} Zeichen)"
    }
  ],
  "historical_figures": [
    {
      "name": "Name der realen historischen Person",
      "role": "Historische Rolle",
      "biography": "Kurze Biografie (MAX. {MAX_HIST_BIO} Zeichen)",
      "importance_in_book": "Bedeutung bis zum aktuellen Fortschritt",
      "context_in_book": "Wie sie erwähnt werden (MAX. 100 Zeichen)"
    }
  ],
  "locations": [
    {"name": "Name des Ortes", "description": "Kurzbeschreibung (MAX. {MAX_LOC_DESC} Zeichen)"}
  ],
  "terms": [
    {
      "name": "Fachbegriff oder Akronym",
      "expanded": "Vollständige Form oder identisch mit Name",
      "category": "Akronym / Fachbegriff / Konzept / Jargon",
      "definition": "Präzise Definition im Kontext (MAX. {MAX_TERM_DEF} Zeichen)"
    }
  ],
  "timeline": [
    {
      "chapter": "Exakter Kapiteltitel aus den Stichproben",
      "event": "Wichtiges erzählerisches Ereignis aus diesem Kapitel (Max. {MAX_TIMELINE_EVENT} Zeichen)"
    }
  ]
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Buch: %s
Autor: %s
Lesefortschritt: %d%%

AUFGABE: Extrahieren Sie GENAU 10 ZUSÄTZLICHE wichtige Charaktere aus dem Text.
Geben Sie NUR ein gültiges JSON-Objekt aus.

PRÄZISIONS-MANDAT (WICHTIG):
Um eine Kürzung der AI-Antwort zu vermeiden, halten Sie die Charakterbeschreibungen unter {MAX_CHAR_DESC} Zeichen.

KRITISCHE ANWEISUNG:
Schließen Sie KEINEN der folgenden Charaktere ein, da diese bereits extrahiert wurden:
%s

STRIKTE SPOILER-REGELN:
- ABSOLUT KEINE Informationen nach dem aktuellen Lesefortschritt. Hören Sie genau bei der %d%%-Marke auf.
- Beschreibungen müssen den Zustand der Charaktere genau an diesem Punkt im Buch widerspiegeln.

ERFORDERLICHES JSON-FORMAT:
{
  "characters": [
    {
      "name": "Vollständiger formeller Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rolle bis zum aktuellen Fortschritt",
      "gender": "Männlich / Weiblich / Unbekannt",
      "occupation": "Beruf/Status",
      "description": "Beschreibung basiert STRIKT auf dem bereitgestellten Text. Keine Schlussfolgerungen oder externes Wissen hinzufügen. KEINE SPOILER. (Max {MAX_CHAR_DESC} Zeichen)"
    }
  ]
}]],

    -- Fetch More Terms (Glossary Support)
    more_terms = [[Buch: %s
Autor: %s
Lesefortschritt: %d%%

AUFGABE: Extrahieren Sie GENAU 15 ZUSÄTZLICHE bedeutende Begriffe, Akronyme, Jargon oder Konzepte aus dem Text.
- Wenn dieses Buch Sachliteratur (Non-fiction) ist: Extrahieren Sie Fachbegriffe, Konzepte, Akronyme oder Jargon.
- Wenn dieses Buch Belletristik (Fiction) ist: Extrahieren Sie Elemente des Weltenbaus (World-building) wie Fraktionen, Organisationen, Magiesysteme, Technologien, Kreaturen, Sprachen oder in-universe Lore.
Geben Sie NUR ein gültiges JSON-Objekt aus.

PRÄZISIONS-MANDAT (WICHTIG):
Um eine Kürzung der AI-Antwort zu vermeiden, halten Sie die Begriffsdefinitionen unter {MAX_TERM_DEF} Zeichen.

KRITISCHE ANWEISUNG:
Schließen Sie KEINEN der folgenden Begriffe ein, da diese bereits extrahiert wurden:
%s

STRIKTE SPOILER-REGELN:
- ABSOLUT KEINE Informationen nach dem aktuellen Lesefortschritt. Hören Sie genau bei der %d%%-Marke auf.

ERFORDERLICHES JSON-FORMAT:
{
  "terms": [
    {
      "name": "Fachbegriff oder Akronym",
      "expanded": "Vollständige Form oder identisch mit Name",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Fachbegriff / Konzept / Jargon",
      "definition": "Präzise Definition im Kontext (MAX. {MAX_TERM_DEF} Zeichen)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[Der Benutzer hat das Wort "%s" hervorgehoben.
AUFGABE: Bestimmen Sie, ob es sich bei diesem Wort um einen Charakter, einen Ort, eine historische Figur oder einen Fachbegriff/Akronym im Buch handelt.
 
WICHTIG FÜR CHARAKTERE UND ORTE: Verwenden Sie AUSSCHLIESSLICH den bereitgestellten "BOOK TEXT CONTEXT". Externes Wissen ist streng verboten. Keine Halluzinationen.
WICHTIG FÜR FIKTIVE CHARAKTERE: Beschreiben Sie NUR das, was der bereitgestellte Buchtext offenbart. Verwenden Sie KEIN Vorwissen aus Ihrem Training über diesen Charakter, selbst wenn Sie ihn aus einer bekannten Serie wiedererkennen. Wenn der Text diesen Charakter nur kurz erwähnt, muss Ihre Beschreibung diese begrenzte Information widerspiegeln.
WICHTIG FÜR HISTORISCHE PERSONEN: Sie DÜRFEN Ihr internes Wissen verwenden, um deren Identität zu verifizieren und deren Biografie/Rolle anzugeben, ABER NUR, wenn es sich um eine reale, bedeutende historische Person handelt. Sie MÜSSEN dennoch den Textkontext für deren Relevanz im Buch verwenden.
CRITICAL FOR TERMS: Wenn das Buch ein Sachbuch ist, prüfen Sie, ob das Wort ein Fachbegriff, Akronym oder Schlüsselkonzept ist. Geben Sie die Definition im Kontext an.
Wenn das Wort im Text KEIN Charakter, Ort, historische Figur oder Fachbegriff ist, setzen Sie `is_valid` auf false.
 
ERFORDERLICHES JSON-FORMAT:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Vollständiger Name",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Rolle",
    "gender": "Männlich/Weiblich/Unbekannt",
    "occupation": "Beruf",
    "description": "Kurze Beschreibung (max. 250 Zeichen)"
  },
  "error_message": ""
}
 
Hinweis: Wenn der Typ "location" ist, muss das Element "name" und "description" enthalten. Wenn der Typ "historical_figure" ist, muss das Element "name", "biography" und "role" enthalten. Wenn der Typ "term" ist, muss das Element "name", "expanded", "category" und "definition" enthalten.
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Kurze Erklärung, warum dies kein Charakter oder Ort ist."
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Unbekanntes Buch",
        unknown_author = "Unbekannter Autor",
        unnamed_character = "Unbenannter Charakter",
        not_specified = "Nicht angegeben",
        no_description = "Keine Beschreibung",
        unnamed_person = "Unbenannte Person",
        no_biography = "Keine Biografie verfügbar"
    }
}
