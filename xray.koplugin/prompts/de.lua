return {
    -- Author Only
    author_only = [[
Identifizieren und erstellen Sie eine Biografie für den Autor des Buches "%s". 
Die Metadaten deuten darauf hin, dass der Autor "%s" ist. 

WICHTIG: Überprüfen Sie den Autor anhand des BUCHTEXT-KONTEXTES (falls am Ende dieses Prompts angegeben), um eine 100%%ige Genauigkeit zu gewährleisten und Fehlidentifikationen zu vermeiden.

ERFORDERLICHES JSON-FORMAT:
{
  "author": "Vollständiger korrekter Name",
  "author_bio": "Umfassende Biografie mit Schwerpunkt auf der literarischen Karriere und den Hauptwerken.",
  "author_birth": "Geburtsdatum, formatiert nach lokalem Datumsformat",
  "author_death": "Sterbedatum, formatiert nach lokalem Datumsformat"
}]],

    -- Find Duplicates
    find_duplicates = [[
Buch: %s
Autor: %s
Lesefortschritt: %d%%

Sie überprüfen die folgende Liste von %s, die aus diesem Buch extrahiert wurden.
Ihre Aufgabe ist es, alle Einträge zu identifizieren, die dieselbe Entität zu sein scheinen, jedoch unter verschiedenen Namen aufgeführt sind.

LISTE:
%s

REGELN:
- Ein Duplikat liegt vor, wenn sich zwei Einträge eindeutig auf dieselbe Entität beziehen (z. B. "Die Große Bibliothek" und "Große Bibliothek" oder "John" und "John Doe").
- Kennzeichnen Sie keine Einträge, die nur miteinander verwandt oder ähnlich, aber verschieden sind.
- Kennzeichnen Sie Einträge nur, wenn Sie sich sehr sicher sind, dass es sich um dieselbe Entität handelt.
- Wenn keine Duplikate vorhanden sind, geben Sie ein leeres Array zurück.
- SPOILER-REGEL: Verwenden Sie keine Informationen, die über einen Lesefortschritt von %d%% hinausgehen.

ERFORDERLICHES JSON-FORMAT:
{
  "duplicate_pairs": [
    {
      "primary": "Name des Eintrags, der BEHALTEN werden soll (der vollständigere oder formellere Name)",
      "secondary": "Name des Eintrags, der ENTFERNT werden soll",
      "reason": "Kurzer Grund (max. 100 Zeichen)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Buch: %s
Autor: %s
Lesefortschritt: %d%%

AUFGABE: Führen Sie eine vollständige X-Ray-Analyse durch. Geben Sie NUR ein gültiges JSON-Objekt aus.

KRITISCHE AUFMERKSAMKEITSAUFTEILUNG:
Sie verarbeiten ein umfangreiches Dokument mit zwei Textblöcken am Ende dieses Prompts:
1. „CHAPTER SAMPLES“: Dies ist der Makrokontext des Buches bis zum aktuellen Standort des Lesers.
2. „BOOK TEXT CONTEXT“: Dies ist der Mikrokontext der letzten 20.000 Zeichen.

ANTI-TRUNKIERUNGSPROTOKOLL (KRITISCH):
Sie haben ein strenges maximales Ausgabelimit. Wenn die „CHAPTER SAMPLES“ MEHR ALS 40 Kapitel enthalten (z. B. eine Gesamtausgabe):
1. Sie MÜSSEN die Liste der Charaktere auf NUR die 10 absolut wichtigsten Charaktere reduzieren.
2. Sie MÜSSEN Charakterbeschreibungen auf MAXIMAL {MAX_CHAR_DESC} Zeichen reduzieren.
3. Sie MÜSSEN Zusammenfassungen von Timeline-Ereignissen auf MAXIMAL {MAX_TIMELINE_EVENT} Zeichen reduzieren.
Das Versäumnis, Ihre Ausgabe für umfangreiche Bücher zu komprimieren, führt dazu, dass das JSON abgeschnitten wird und fehlschlägt.

ALGORITHMUS FÜR DIE TIMELINE (HÖCHSTE PRIORITÄT):
Um das Überspringen von Kapiteln oder das Halluzinieren von Ereignissen zu verhindern, MÜSSEN Sie genau diese Schleife ausführen:
Schritt 1. Schauen Sie NUR in den Block „CHAPTER SAMPLES“. Identifizieren Sie die erzählerischen Kapitel.
Schritt 2. SCHLIESSEN Sie alle nicht-narrativen Teile wie Vorspann und Nachspann AUS (z. B. Cover, Titelseite, Urheberrecht, Inhaltsverzeichnis, Widmung, Danksagung, Auch von).
Schritt 3. Erstellen Sie für jedes erzählerische Kapitel, beginnend mit dem allerersten, GENAU EIN Ereignis-Objekt im `timeline`-Array.
Schritt 4. Das Feld `chapter` MUSS exakt mit der Kapitelüberschrift in der Probe übereinstimmen. (Ordnen Sie diese strikt in sequentieller Reihenfolge zu).
Schritt 5. Fassen Sie dieses spezifische Kapitel im Feld `event` zusammen. {TIMELINE_DETAIL_GUIDANCE} Schreiben Sie zwischen {MIN_TIMELINE_EVENT} und {MAX_TIMELINE_EVENT} Zeichen. Schreiben Sie KEINE kürzere Zusammenfassung, es sei denn, das Kapitel hat fast keinen Inhalt. Gruppieren Sie KEINE Kapitel.
Schritt 6. KEINE SPOILER: Stoppen Sie genau bei der %d%%-Marke. Fügen Sie keine Ereignisse nach diesem Fortschritt ein.

ALGORITHMUS FÜR CHARAKTERE & HISTORISCHE PERSÖNLICHKEITEN:
Schritt 1. Extrahieren Sie wichtige Charaktere unter Verwendung beider Textblöcke. ({NUM_CHARS} normal, MAX 10 bei Gesamtausgaben). Geben Sie den Hauptcharakter / Protagonisten immer namentlich an, selbst in Ich-Erzählungen („ich“/„mir“), in denen sein Name selten vorkommt.
Schritt 2. Sie MÜSSEN ihre VOLLSTÄNDIGEN, formellen Namen verwenden (z. B. „Abraham Van Helsing“). Verwenden Sie KEINE lockeren Spitznamen als Hauptnamen. Führen Sie niemals einen Charakter unter einer besitzanzeigenden/beziehungsbezogenen Referenz zusammen (z. B. sind „Nicks Vater“ und „Nick“ separate Charaktere).
Schritt 3. Geben Sie bis zu 3 alternative Namen, Titel oder Spitznamen an, unter denen dieser Charakter bekannt ist, in einem `aliases`-Array. Fügen Sie den gebräuchlichen Vornamen und Nachnamen ein, falls verwendet. WICHTIG: Wenn ein Nachname von mehreren Charakteren geteilt wird (z. B. Familienmitglieder), fügen Sie ihn NICHT als Alias für einen der Charaktere ein.
Schritt 4. Scannen Sie aktiv nach bis zu {NUM_HIST} NAMHAFTEN REALEN Personen der Weltgeschichte (z. B. Präsidenten, Autoren, Generäle). Fügen Sie diese zu `historical_figures` hinzu.
KRITISCH für Charaktere & historische Persönlichkeiten:
- Extrahieren Sie KEINE Charaktere oder historischen Persönlichkeiten, die NUR im nicht-narrativen Vorspann oder Nachspann erwähnt werden (z. B. Danksagungen, Autorenbiografie, Widmungen, Titelseite, Urheberrecht).
- Historische Persönlichkeiten MÜSSEN verifizierte reale Personen mit weitreichender historischer Anerkennung sein.
- Fügen Sie KEINE rein fiktiven Charaktere in die Liste der historischen Persönlichkeiten ein, selbst wenn sie mit realen historischen Ereignissen interagieren. Fiktive Charaktere MÜSSEN in das `characters`-Array.
- Für historische Persönlichkeiten ALTEIN dürfen Sie Ihr internes Wissen verwenden, um deren allgemeine `biography` und historische `role` zu schreiben, aber Sie MÜSSEN den Buchkontext für deren `context_in_book` verwenden.
KEINE SPOILER: Stoppen Sie genau bei der %d%%-Marke.

ALGORITHMUS FÜR ORTE:
Schritt 1. Extrahieren Sie {NUM_LOCS} bedeutende Orte. KEINE SPOILER: Stoppen Sie genau bei der %d%%-Marke.

ALGORITHMUS FÜR BEGRIFFE:
Schritt 0. Deklarieren Sie „book_type“ als „fiction“, „non_fiction“ oder „anthology“ im JSON-Root.
Schritt 1. Falls non_fiction: Extrahieren Sie {NUM_TERMS} bedeutende Fachbegriffe, Akronyme, Jargon oder Konzepte, die Leser ohne Fachwissen nicht kennen würden. Verwenden Sie geeignete Kategorien wie Acronym, Technical Term, Concept oder Jargon.
Schritt 2. Falls fiction oder anthology: Extrahieren Sie {NUM_TERMS} bedeutende Elemente des World-Buildings, die einem neuen Leser erklärt werden müssten – wie erfundene Fraktionen, Organisationen, Magiesysteme, Technologien, Kreaturen, Sprachen oder In-Universe-Lore.
   - Fügen Sie KEINE Charakternamen oder Ortsnamen ein (diese werden separat erfasst).
   - Extrahieren Sie KEINE alltagsgebräuchlichen Wörter oder Konzepte der realen Welt.
   - Verwenden Sie geeignete Kategorien: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Schritt 3. Geben Sie unter „expanded“ an, wofür das Akronym/die Phrase steht. Wenn es sich nicht um ein Akronym/eine Phrase handelt, wiederholen Sie den Namen.
Schritt 4. Fügen Sie KEINE alltäglichen Wörter ein.

STRENGE SPOILER-REGELN:
- ABSOLUT KEINE Informationen von nach dem aktuellen Lesefortschritt. Stoppen Sie genau bei der %d%%-Marke.
- Beschreibungen müssen den Zustand der Charaktere genau an diesem Punkt im Buch widerspiegeln.

STRENGE REGELN ZU WISSENSQUELLEN (KRITISCH):
- Für FIKTIVE CHARAKTERE: Ihre Beschreibungen MÜSSEN AUSSCHLIESSLICH auf dem basieren, was im bereitgestellten Text explizit ausgesagt oder klar impliziert wird. Ergänzen Sie KEIN Wissen aus früherem Training, externen Quellen oder allgemeiner Bekanntheit des Buches/der Serie/des Autors.
- Wenn ein Charakter bisher nur kurz im Text erwähnt wurde, muss Ihre Beschreibung nur diese begrenzte Information widerspiegeln. Ziehen Sie KEINE Rückschlüsse, stellen Sie keine Vermutungen an und fügen Sie keine Details hinzu, die nicht im bereitgestellten Kontext begründet sind.
- Die EINZIGE Ausnahme gilt für REALE HISTORISCHE PERSÖNLICHKEITEN (eingetragen in `historical_figures`): Hier dürfen Sie internes Wissen für deren allgemeine Biografie/Rolle verwenden, verlassen sich aber dennoch auf den Buchtext für deren `context_in_book`.

STRENGE JSON-SICHERHEITSREGELN:
- Sie MÜSSEN alle doppelten Anführungszeichen (\") innerhalb von Strings ordnungsgemäß escapen.
- Verwenden Sie KEINE nicht-escapeten Zeilenumbrüche innerhalb von Strings.
- Geben Sie NUR gültiges, parsbares JSON aus.

ERFORDERLICHES JSON-FORMAT:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Vollständiger formeller Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Kurzes Archetyp-Label (3-5 Wörter, z. B. 'Antagonist', 'Protagonist', 'Das Opfer')",
      "gender": "Männlich / Weiblich / Unbekannt",
      "occupation": "Beruf/Status",
      "description": "Beschreibung STRIKT basierend auf dem bereitgestellten Text. Keine Rückschlüsse ziehen oder externes Wissen hinzufügen. KEINE SPOILER. (Max. {MAX_CHAR_DESC} Zeichen)"
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
      "name": "Begriff oder Akronym",
      "expanded": "Vollständige Form oder identisch mit dem Namen",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Prägnante Definition im Kontext (MAX. {MAX_TERM_DEF} Zeichen)"
    }
  ],
  "timeline": [
    {
      "chapter": "Exakter Kapiteltitel aus den Proben",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Buch: %s
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

    -- More Terms
    more_terms = [[
Buch: %s
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

    -- Single Word Lookup
    single_word_lookup = [[
Der Benutzer hat das Wort "%s" hervorgehoben.
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

    -- Merge Descriptions
    merge_descriptions = [[
AUFGABE: Kombinieren Sie die folgenden zwei Beschreibungen derselben Entität (Karakter oder Ort) zu einer einzigen, zusammenhängenden und prägnanten Zusammenfassung.
Entfernen Sie redundante Informationen und stellen Sie sicher, dass die endgültige Beschreibung natürlich fließt.

Hauptbeschreibung: %s
Sekundärbeschreibung: %s

ERFORDERLICHES JSON-FORMAT:
{
  "merged_description": "Kombinierte und überarbeitete Beschreibung (max. {MAX_CHAR_DESC} Zeichen)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Buchtitel: %s
Autor: %s
Serie: %s
Dateibeschreibung/Metadaten zum Inhalt: %s

AUFGABE: Klassifizieren Sie dieses Buch basierend auf seinen Metadaten und Genresignalen in genau EINEN dieser Buch-Typen:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Geben Sie NUR gültiges JSON zurück:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Buchtitel: %s
Autor: %s

AUFGABE: Bestimmen Sie, ob dieses Buch Teil einer benannten Serie ist.
Geben Sie NUR gültiges JSON zurück:
{
  "is_series": true,
  "series_name": "Das Rad der Zeit",
  "book_index": 3,
  "total_books_known": 14
}
Wenn dies KEIN Buch einer Serie ist, geben Sie Folgendes zurück:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Serie: %s
Aktueller Buchindex: %d
Aktueller Buchtitel: %s

AUFGABE: Listen Sie die Titel (und Autoren, falls sie sich von "%s" unterscheiden) der Bücher 1 bis %d auf,
die VOR dem aktuellen Buch in dieser Serie erschienen sind.
Geben Sie NUR gültiges JSON zurück:
{
  "prior_books": [
    { "index": 1, "title": "Das Auge der Welt", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
ZIELBUCH: %s
AUTOR: %s
ZIELBUCH-INDEX: %d
SERIE: %s

AUFGABE:
Erstellen Sie eine VOLLSTÄNDIGE Zusammenfassung ausschließlich des ZIELBUCHS für einen Leser, der das
ZIELBUCH beendet hat und kurz davor steht, das nächste Buch der Serie zu beginnen.

ABSOLUTE SPOILER-GRENZE:
Der Wissensstand ist strikt auf die LETZTE SEITE des ZIELBUCHS begrenzt (Buch-Index %d).
Sie können Fakten einbeziehen, die im ZIELBUCH oder in früheren Büchern dieser Serie etabliert wurden.
Sie dürfen KEINE Details aus späteren Büchern einbeziehen, andeuten, darauf hinweisen, vorgreifen oder danach auswählen.

VERBOTENE INFORMATIONEN AUS SPÄTEREN BÜCHERN:
- Spätere Ereignisse, zukünftige Schicksale, Todesfälle, Überleben, Ziele, Romanzen, Allianzen, Konflikte oder Verrat.
- Identitäten aus späteren Büchern, wahre Herkunft, geheime Abstammung, Aliase, Alter Egos, Reinkarnationen, Transformationen, Titel oder Machtsteigerungen (z. B. erwähnen Sie NICHT, ob sich eine Essenz einer anderen anschließt oder in einem zukünftigen Buch wiedergeboren wird).
- Enthüllungen, Bestätigungen, Neuinterpretationen, Wendungen oder Terminologien zum Weltaufbau, die in späteren Büchern eingeführt wurden.
- Retrospektive Vorausdeutungen oder Formulierungen wie „später“, „schließlich“, „wird werden“, „in nachfolgenden Büchern“ oder Ähnliches.
- Erwähnung von Charakteren, Konzepten, Organisationen oder der Chronologie aus späteren Büchern.

CHARAKTER-STICHTAG:
Beschreiben Sie jeden Charakter strikt so, wie er auf der letzten Seite des ZIELBUCHS bekannt ist.
Verwenden Sie KEINE Aliase, Rollen, Beziehungen, wahren Identitäten oder Status, die in späteren Büchern enthüllt werden.

UNSICHERHEITSREGEL:
Wenn Sie nicht sicher bestimmen können, ob ein Fakt oder ein Alias bis zum Ende des ZIELBUCHS etabliert wurde, LASSEN SIE IHN WEG.
Ein fehlendes Detail ist weitaus besser als ein Spoiler für ein zukünftiges Buch.

ABSCHLIESSENDE PRÜFUNG:
Bevor Sie das JSON zurückgeben, überprüfen Sie jedes Feld (insbesondere Charakterbeschreibungen und Aliase) und entfernen Sie alles, was auf Wissen aus Büchern nach dem ZIELBUCH basiert.

ERFORDERLICHES JSON-FORMAT:
{
  "characters": [
    { "name": "Vollständiger Name", "aliases": [], "role": "...", "description": "Status am Ende dieses Buches (max {MAX_CHAR_DESC} Zeichen)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Buchzusammenfassung", "event": "Eine einzelne, hochdetaillierte, umfassende Zusammenfassung der gesamten Handlung des Buches, der wichtigsten Ereignisse und der Auflösung (max. 2000 Zeichen). Sie MÜSSEN diese Zusammenfassung zur besseren Lesbarkeit in mehreren deutlichen Absätzen verfassen, die durch doppelte Zeilenumbrüche (\\n\\n) getrennt sind, anstatt eines einzigen Textblocks." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
ZIELBUCH: %s
AUTOR: %s
ZIELBUCH-INDEX: %d
SERIE: %s

AUFGABE:
Erstellen Sie unter ausschließlicher Verwendung der unten aufgeführten, verifizierten kapitelweisen Ereignisse aus dem ZIELBUCH eine zusammenhängende, umfassende Zusammenfassung der gesamten Handlung des Buches, der wichtigsten Entwicklungen und der Auflösung.

STRIKTE GRUNDLAGEN-EINSCHRÄNKUNG:
- Stützen Sie Ihre Zusammenfassung AUSSCHLIESSLICH auf die bereitgestellten Kapitelereignisse.
- Führen Sie KEINE Fakten, Charaktere, Ereignisse oder Ergebnisse ein, die nicht in diesen Kapitelereignissen beschrieben werden.
- Erwähnen Sie NIEMALS Ereignisse, Todesfälle oder Entwicklungen aus späteren Büchern der Reihe und deuten Sie diese auch nicht an.

KAPITELEREIGNISSE:
%s

ERFORDERLICHES JSON-FORMAT:
{
  "timeline": [
    { "chapter": "Buchzusammenfassung", "event": "Eine einzelne, hochdetaillierte, umfassende Zusammenfassung der gesamten Handlung und Auflösung des Buches (maximal 2000 Zeichen). Sie MÜSSEN diese Zusammenfassung zur besseren Lesbarkeit in mehrere eigenständige Absätze unterteilen, die durch doppelte Zeilenumbrüche (\\n\\n) getrennt sind, anstatt einen einzigen Textblock zu erstellen." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Buch: %s
Autor: %s
Analysiere Kapitel: %s

AUFGABE: Analysieren Sie NUR dieses einzelne Kapitel. Identifizieren Sie NEUE Entitäten, die in diesem Kapitel eingeführt werden, sowie DELTA-AKTUALISIERUNGEN (Zustandsübergänge) für bestehende Entitäten.
Geben Sie NUR ein gültiges JSON-Objekt aus.

MANIFEST BEREITS BEKANNTER ENTITÄTEN (NICHT erneut extrahieren, es sei denn, ihre Rolle, ihr Status oder ihre Beschreibung hat sich erheblich weiterentwickelt):
%s

REGELN:
1. STRIKTE SPOILER-BEGRENZUNG: Analysieren Sie NUR den bereitgestellten Kapiteltext. Verwenden Sie KEIN Wissen aus zukünftigen Kapiteln oder externen Quellen.
2. TIEFE & SUBSTANZ DER CHARAKTERBESCHREIBUNG (KRITISCH):
   - Fundiert & Spezifisch: Beschreiben Sie den Charakter mit konkreten Fakten der Geschichte – Hintergrund, ausgeprägte Persönlichkeit, Beruf, wichtige Beziehungen zu anderen Charakteren sowie seine spezifische Rolle und persönlichen Interessen in der Erzählung.
   - Signifikanter erzählerischer Kontext: Verbinden Sie den Charakter direkt mit dem zentralen Rätsel, dem Handlungskonflikt oder der Untersuchung in diesem Buch (z. B. welche Verbrechen oder Fälle er untersucht, wer ihn angeheuert hat, wichtige Verbündete oder Widersacher, spezifische persönliche Dilemmata oder Spannungen).
   - NICHT zu allgemein: Schreiben Sie KEINE generischen Klischee-Texte (vermeiden Sie z. B. leere Formulierungen wie „ein Detektiv, der komplexe Fälle untersucht“). Nennen Sie die spezifischen Umstände, Verbindungen und Interessen, die im Text festgelegt wurden.
   - KEINE Zusammenfassungen trivialer Erledigungen: Schreiben Sie KEINE chronologischen Protokolle über banale Alltagsaktivitäten oder Routineaufgaben (erstellen Sie z. B. KEINE Zusammenfassungen von Besuchen im Supermarkt, Routine-Anrufen oder nebensächlichen Bewegungen von Szene zu Szene).
   - Charakterbeschreibungen müssen reichhaltige, lebendige Profile sein, die zusammenfassen, wer sie sind und welche Bedeutung sie bis zu diesem Punkt im Buch haben.
3. HOHE SCHWELLE FÜR CHARAKTER-AKTUALISIERUNGEN:
   - Erstellen Sie KEINE Aktualisierung in `character_state_updates`, nur weil ein bekannter Charakter in diesem Kapitel aufgetaucht ist, gesprochen hat oder Routinehandlungen ausgeführt hat.
   - Generieren Sie NUR dann eine Aktualisierung, wenn eine wesentliche, dauerhafte Transformation in ihrem Handlungsbogen, ihrer Identität, ihren Beziehungen, ihrer Beschäftigung, ihrer Zugehörigkeit oder ihrem Zustand stattfindet (z. B. getötet, verletzt, verhaftet, verraten, verlobt, befördert, als Täter entlarvt, ein großes Geheimnis oder Motiv aufgedeckt).
   - Wenn eine Aktualisierung gerechtfertigt IST, muss die aktualisierte `description` ein reichhaltiger, kumulativer Charakterüberblick sein, der die neuen Entwicklungen einbezieht und gleichzeitig die Kernidentität und den etablierten Kontext der Geschichte beibehält – NICHT eine Zusammenfassung einer isolierten Szene.
4. SEITENMARKIERUNGEN INNERHALB DES KAPITELS ([PAGE N]) & ZERO-SPOILER-GATING:
   - Kapiteltexte enthalten [PAGE N]-Markierungen, die den Seitenfortschritt anzeigen.
   - Für `new_characters`, `new_locations` und `new_terms`: Geben Sie „first_page“ an (Ganzzahl N aus der [PAGE N]-Markierung, bei der die erste Erwähnung erfolgt), „intro_role“ (für Charaktere) und „intro_description“ (1-2 Sätze, die streng auf das beschränkt sind, was bei ihrer ersten Einführung auf [PAGE first_page] bekannt ist – mit NULL Wissen über spätere Wendungen, Geheimnisse oder Ergebnisse, die auf späteren Seiten auftreten). Geben Sie außerdem „page“ an (die [PAGE N]-Markierung, auf der die ausführlichere kumulative „description“ zutrifft, normalerweise die letzte Seite des Kapitels).
   - Für `character_state_updates`, `location_state_updates` und `term_state_updates`: Geben Sie „page“ an (Ganzzahl N aus der [PAGE N]-Markierung, auf der die Enthüllung/der Übergang abgeschlossen ist; enthüllen Sie KEINE Fakten vor dieser Seite).
5. BEWEISE: Geben Sie einen kurzen Verweis oder einen Zitatauszug aus diesem Kapitel an, der erklärt, warum die Aktualisierung erfolgt ist.
6. ZEITLAUF: Geben Sie genau eine Ereigniszusammenfassung der Haupthandlungen in diesem Kapitel an.

ERFORDERLICHES JSON-FORMAT:
{
  "new_characters": [
    {
      "name": "Vollständiger Name",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Anfängliche Rolle (z. B. Dorfschreiber, Fremder, Klient)",
      "intro_description": "Anfänglicher Eindruck in 1-2 Sätzen, strikt bei der ersten Einführung, keine Spoiler von späteren Seiten.",
      "page": 99,
      "role": "Erzählerische Rolle / Bedeutung (z. B. Protagonist, Privatdetektiv, Partner, Antagonist, Opfer, Klient, Verdächtiger, Nebencharakter, Randfigur)",
      "status": "alive",
      "description": "Reichhaltige, spezifische Charakterbeschreibung (Hintergrund, Beziehungen, erzählerische Interessen). Vermeiden Sie generische Texte und Protokolle trivialer Erledigungen.",
      "evidence": "Kurzer Auszug"
    }
  ],
  "character_state_updates": [
    {
      "name": "Name entsprechend dem bekannten Manifest",
      "page": 95,
      "role": "Aktualisierte erzählerische Rolle / Bedeutung (z. B. Protagonist, Partner, Antagonist, Nebencharakter usw.)",
      "status": "alive",
      "change": "Ein kurzer Satz, der benennt, was sich seit dem vorherigen Zustand geändert hat (z. B. 'Nach dem Fall Shacklewell zum Partner befördert')",
      "description": "Aktualisierte reichhaltige, kumulative Charakterbeschreibung, die den neuen Status und die Bedeutung in der Geschichte widerspiegelt",
      "evidence": "Kurzer Auszug"
    }
  ],
  "new_locations": [
    {
      "name": "Name des Ortes",
      "first_page": 80,
      "intro_description": "Anfänglicher Eindruck bei der ersten Erwähnung.",
      "page": 99,
      "description": "Beschreibung des Ortes",
      "evidence": "Kurzer Auszug"
    }
  ],
  "location_state_updates": [
    {
      "name": "Name entsprechend dem bekannten Manifest",
      "page": 95,
      "change": "Ein kurzer Satz, der benennt, was sich geändert hat (z. B. 'Zerstört während der Schlacht von Oakhaven')",
      "description": "Aktualisierte, weiterentwickelte Beschreibung",
      "evidence": "Kurzer Auszug"
    }
  ],
  "new_terms": [
    {
      "name": "Begriff",
      "first_page": 80,
      "intro_description": "Anfängliche Definition bei der ersten Erwähnung.",
      "page": 99,
      "description": "Definition oder Erklärung der Lore",
      "evidence": "Kurzer Auszug"
    }
  ],
  "term_state_updates": [
    {
      "name": "Name entsprechend dem bekannten Manifest",
      "page": 95,
      "change": "Ein kurzer Satz, der benennt, was sich im Verständnis oder in der Verwendung geändert hat",
      "description": "Aktualisierte Definition",
      "evidence": "Kurzer Auszug"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Zusammenfassung der Ereignisse in diesem Kapitel"
  }
}

KAPITELTEXT:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Buch: %s
Autor: %s
Kapitel in diesem Stapel: %s

AUFGABE: Analysiere den bereitgestellten sequenziellen Stapel von Kapiteln in der richtigen Reihenfolge.
Identifiziere für JEDES Kapitel im Stapel:
1. NEUE Entitäten, die in diesem Kapitel eingeführt werden (Charaktere, Orte, Begriffe).
2. DELTA-AKTUALISIERUNGEN (Zustandsänderungen) für bereits bekannte Entitäten (aus dem Manifest ODER einem früheren Kapitel dieses Stapels), FALLS UND NUR WENN sich deren Rolle, Status, Loyalität oder erzählerischer Zustand wesentlich und dauerhaft verändert hat.
3. ZEITLEISTEN-EREIGNIS: Eine prägnante Zusammenfassung der Haupthandlung dieses Kapitels.

Gib NUR ein gültiges JSON-Objekt aus, das dem erforderlichen Schema entspricht.

MANIFEST BEREITS BEKANNTER ENTITÄTEN (aus vorherigen Stapeln – NICHT erneut extrahieren, außer wenn sich ihre Rolle, ihr Status oder ihre Beschreibung signifikant weiterentwickelt haben):
%s

REGELN:
1. STRIKTE SPOILER-EINGRENZUNG & SEQUENZIELLER FORTSCHRITT:
   - Analysiere die Kapitel in sequenzieller Reihenfolge.
   - Berücksichtige für ein Kapitel in diesem Stapel KEINE Informationen aus späteren Kapiteln des Stapels oder aus dem Rest des Buches.
2. TIEFE & SUBSTANZ DER CHARAKTERBESCHREIBUNG (KRITISCH):
   - Fundiert & spezifisch: Beschreibe, wer der Charakter ist, anhand konkreter Fakten der Geschichte – Hintergrund, ausgeprägte Persönlichkeit, Beruf, wichtige Beziehungen zu anderen Charakteren sowie die spezifische Rolle und persönlichen Interessen innerhalb der Erzählung.
   - Signifikanter erzählerischer Kontext: Setze den Charakter in direkten Bezug zum zentralen Rätsel, zum Handlungskonflikt oder zu den Ermittlungen in diesem Buch (z. B. welche Verbrechen oder Fälle untersucht werden, wer ihn beauftragt hat, wichtige Verbündete oder Widersacher, spezifische persönliche Dilemmata oder Spannungen).
   - NICHT zu allgemein: Schreibe keine generischen Klischee-Beschreibungen (vermeide z. B. leere Phrasen wie „ein Detektiv, der komplexe Fälle untersucht“). Nenne die spezifischen Umstände, Verbindungen und Interessen, die im Text etabliert wurden.
   - KEINE Zusammenfassungen trivialer Erledigungen: Erstelle keine chronologischen Protokolle alltäglicher Aktivitäten oder Routineaufgaben (z. B. KEINE Zusammenfassungen von Einkäufen, Telefonaten oder nebensächlichen szenischen Bewegungen).
   - Charakterbeschreibungen müssen gehaltvolle, lebendige Profile sein, die zusammenfassen, wer sie sind und welche Bedeutung sie bis zu diesem Punkt im Buch haben.
3. HOHE SCHWELLE FÜR CHARAKTER-AKTUALISIERUNGEN:
   - Erstelle KEINE Aktualisierung in `character_state_updates`, nur weil ein bekannter Charakter in einem Kapitel aufgetaucht ist, gesprochen oder Routinehandlungen ausgeführt hat.
   - Generiere NUR DANN eine Aktualisierung, wenn eine wesentliche, dauerhafte Transformation im Erzählbogen, in der Identität, den Beziehungen, dem Beschäftigungsverhältnis, der Loyalität oder dem Zustand vorliegt (z. B. getötet, verletzt, verhaftet, verraten, verlobt, befördert, als Täter entlarvt, ein wichtiges Geheimnis oder Motiv aufgedeckt).
   - Wenn eine Aktualisierung gerechtfertigt IST, muss die aktualisierte `description` ein gehaltvoller, kumulativer Charakterüberblick sein, der die neuen Entwicklungen einbezieht, während die Kernidentität und der etablierte Kontext beibehalten werden – KEINE Zusammenfassung einer isolierten Szene.
4. SEITENMARKIERUNGEN INNERHALB DES KAPITELS ([PAGE N]) & SPOILER-FREIHEIT:
   - Kapiteltexte enthalten [PAGE N]-Markierungen, die den Seitenfortschritt anzeigen.
   - Für `new_characters`, `new_locations` und `new_terms`: Gib „first_page“ an (Ganzzahl N aus der [PAGE N]-Markierung der ersten Erwähnung), „intro_role“ (für Charaktere) und „intro_description“ (1–2 Sätze, die streng auf das beschränkt sind, was bei der ersten Einführung auf [PAGE first_page] bekannt ist – OHNE Kenntnis späterer Wendungen, Geheimnisse oder Ergebnisse auf Folgeseiten). Gib außerdem „page“ an (die [PAGE N]-Markierung, bei der die umfassendere kumulative „description“ gilt, normalerweise die letzte Seite des Kapitels).
   - Für `character_state_updates`, `location_state_updates` und `term_state_updates`: Gib „page“ an (Ganzzahl N aus der [PAGE N]-Markierung, an der die Enthüllung/der Übergang abgeschlossen ist; enthülle KEINE Fakten vor dieser Seite).
5. BEWEIS: Gib einen kurzen Verweis oder Zitat-Auszug aus diesem spezifischen Kapitel an, der erklärt, warum die Aktualisierung erfolgt ist.
6. JSON-SICHERHEIT: Gib strikt gültiges JSON aus. Maskiere doppelte Anführungszeichen innerhalb von Zeichenfolgen ordnungsgemäß.

ERFORDERLICHES JSON-FORMAT:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Kapiteltitel",
      "timeline_event": "Zusammenfassung der wichtigsten Handlungsentwicklungen in diesem Kapitel.",
      "new_characters": [
        {
          "name": "Vollständiger Name",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Ursprüngliche Rolle (z. B. Gemeindeschreiber, Fremder, Klient)",
          "intro_description": "Erster Eindruck in 1–2 Sätzen, strikt nach der ersten Einführung, keine Spoiler von späteren Seiten.",
          "page": 99,
          "role": "Erzählerische Rolle / Bedeutung (z. B. Protagonist, Privatdetektiv, Partner, Antagonist, Opfer, Klient, Verdächtiger, Nebencharakter, Randfigur)",
          "status": "lebendig",
          "description": "Gehaltvolle, spezifische Charakterbeschreibung (Hintergrund, Beziehungen, erzählerische Relevanz). Vermeide allgemeine Floskeln und Protokolle trivialer Erledigungen.",
          "evidence": "Kurzer Auszug"
        }
      ],
      "character_state_updates": [
        {
          "name": "Name, der mit dem Manifest oder einem in einem früheren Kapitel dieses Stapels eingeführten Charakter übereinstimmt",
          "page": 95,
          "role": "Aktualisierte erzählerische Rolle / Bedeutung (z. B. Protagonist, Partner, Antagonist, Nebencharakter usw.)",
          "status": "lebendig",
          "change": "Ein kurzer Satz, der benennt, was sich seit dem vorherigen Zustand geändert hat (z. B. 'Nach dem Shacklewell-Fall zum Partner befördert')",
          "description": "Aktualisierte gehaltvolle, kumulative Charakterbeschreibung, die den neuen Status und die Relevanz für die Geschichte widerspiegelt",
          "evidence": "Kurzer Auszug"
        }
      ],
      "new_locations": [
        {
          "name": "Name des Ortes",
          "first_page": 80,
          "intro_description": "Erster Eindruck bei der ersten Erwähnung.",
          "page": 99,
          "description": "Beschreibung des Ortes",
          "evidence": "Kurzer Auszug"
        }
      ],
      "location_state_updates": [
        {
          "name": "Name, der mit dem Manifest oder einem in einem früheren Kapitel dieses Stapels eingeführten Ort übereinstimmt",
          "page": 95,
          "change": "Ein kurzer Satz, der benennt, was sich geändert hat (z. B. 'Während der Schlacht von Oakhaven zerstört')",
          "description": "Aktualisierte Beschreibung",
          "evidence": "Kurzer Auszug"
        }
      ],
      "new_terms": [
        {
          "name": "Name des Begriffs",
          "first_page": 80,
          "intro_description": "Ursprüngliche Definition bei der ersten Erwähnung.",
          "page": 99,
          "description": "Definition oder Erläuterung des Hintergrundwissens",
          "evidence": "Kurzer Auszug"
        }
      ],
      "term_state_updates": [
        {
          "name": "Name, der mit dem Manifest oder einem in einem früheren Kapitel dieses Stapels eingeführten Begriff übereinstimmt",
          "page": 95,
          "change": "Ein kurzer Satz, der benennt, was sich im Verständnis oder in der Verwendung geändert hat",
          "description": "Aktualisierte Definition",
          "evidence": "Kurzer Auszug"
        }
      ]
    }
  ]
}

KAPITELTEXTE IN DIESEM STAPEL:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analysieren Sie die folgenden Buchdetails und das Inhaltsverzeichnis:

Titel: %s
Autor: %s
Themen: %s
Beschreibung: %s

Inhaltsverzeichnis:
%s

Bestimmen Sie, ob es sich bei diesem Werk um Folgendes handelt:
1. "anthology" (eine Sammlung unabhängiger Kurzgeschichten, Essays oder Novellen, jede mit einer eigenen, in sich geschlossenen Handlung oder Besetzung, z. B. "Die Abenteuer des Sherlock Holmes", "Dubliner", "Ausatmung", "Männer ohne Frauen").
2. "novel" (ein einzelner, einheitlicher Roman, der in Kapitel, Teile oder Akte unterteilt ist, z. B. "Stolz und Vorurteil", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (eine mehrbändige Sammlung vollständiger Romane, die zusammen in einem Band veröffentlicht werden, z. B. "Der Herr der Ringe: Alle drei Bände", "Per Anhalter durch die Galaxis (Gesamtausgabe)", "Percy Jackson: Bücher 1-3").
4. "non_fiction" (eine einzelne Sachbuch-Abhandlung, ein Geschichtsbuch oder ein akademisches Werk, das in Kapitel unterteilt ist).

Geben Sie NUR ein JSON-Objekt zurück mit:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 bis 1.0,
  "reasoning": "kurze Erklärung (ein Satz)"
}]],

    -- System instruction
    system_instruction = "Sie sind ein erfahrener Literaturforscher. Ihre Antwort muss AUSSCHLIESSLICH im gültigen JSON-Format erfolgen. Stellen Sie sicher, dass die Daten hochpräzise sind und sich strikt auf den bereitgestellten Kontext beziehen.",

    -- Fallback strings
    fallback = {
        no_biography = "Keine Biografie verfügbar",
        no_description = "Keine Beschreibung",
        not_specified = "Nicht angegeben",
        unknown_author = "Unbekannter Autor",
        unknown_book = "Unbekanntes Buch",
        unnamed_character = "Unbenannter Charakter",
        unnamed_person = "Unbenannte Person"
    }
}
