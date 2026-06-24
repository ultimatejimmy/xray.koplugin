return {
    -- System instruction
    system_instruction = "Sei un esperto ricercatore letterario. La tua risposta deve essere SOLO in formato JSON valido. Garantire che i dati siano estremamente accurati e pertinenti al contesto fornito.",

    -- Author Only
    author_only = [[
Identificare e fornire la biografia dell'autore del libro "%s". 
I metadati suggeriscono che l'autore è "%s". 
1
CRITICO: verificare l'autore utilizzando il CONTESTO DEL TESTO DEL LIBRO (se fornito alla fine di questo messaggio) per garantire una precisione del 100%% ed evitare identificazioni errate.

FORMATO JSON RICHIESTO:
{
  "author": "Nome completo corretto",
  "author_bio": "Biografia completa incentrata sulla loro carriera letteraria e sulle opere principali.",
  "author_birth": "Data di nascita, formattata in base al formato data locale",
  "author_death": "Data di morte, formattata in base al formato data locale"
}]],

    -- Find Duplicates
    find_duplicates = [[
Libro: %s
Autore: %s
Avanzamento nella lettura: %d%%

Stai rivedendo il seguente elenco di %s estratti da questo libro.
Il tuo compito è identificare tutte le voci che sembrano essere la STESSA entità elencata con nomi diversi.

ELENCO:
%s

REGOLE:
- Esiste un duplicato quando due voci si riferiscono chiaramente alla stessa entità (ad esempio, "The Grand Library" e "Grand Library", o "John" e "John Doe").
- NON contrassegnare voci semplicemente correlate o simili ma distinte.
- NON contrassegnare le voci a meno che non si sia assolutamente certi che si tratti della stessa entità.
- Se non esistono duplicati, restituisce un array vuoto.
- REGOLA SPOILER: non utilizzare conoscenze provenienti da oltre il %d%% dei progressi di lettura.

FORMATO JSON RICHIESTO:
{
  "duplicate_pairs": [
    {
      "primary": "Nome della voce in KEEP (il nome più completo o formale)",
      "secondary": "Nome della voce da RIMUOVERE",
      "motivo": "Motivo breve (max 100 caratteri)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Libro: %s
Autore: %s
Avanzamento nella lettura: %d%%

COMPITO: eseguire un'analisi radiografica completa. Genera SOLO un oggetto JSON valido.

PARTIZIONAMENTO DELL'ATTENZIONE CRITICA:
Stai elaborando un documento di grandi dimensioni con due blocchi di testo forniti alla fine di questo prompt:
1. "ESEMPI DI CAPITOLO": Questo è il macrocontesto del libro fino alla posizione attuale del lettore.
2. "CONTESTO DEL TESTO DEL LIBRO": Questo è il micro-contesto dei 20k caratteri più recenti.

PROTOCOLLO ANTI-TRONCAMENTO (CRITICO):
Hai un limite massimo di produzione rigoroso. Se gli "ESEMPI DI CAPITOLO" contengono PIÙ DI 40 capitoli (ad esempio, un'edizione omnibus):
1. DEVI ridurre l'elenco dei caratteri SOLO ai primi 10 caratteri più importanti in assoluto.
2. DEVI ridurre le descrizioni dei caratteri a MAX {MAX_CHAR_DESC} caratteri.
3. DEVI ridurre i riepiloghi degli eventi della sequenza temporale a MAX {MAX_TIMELINE_EVENT} caratteri.
La mancata compressione dell'output per libri di grandi dimensioni causerà il troncamento e il fallimento del JSON.

ALGORITMO PER LA TIMELINE (PRIORITÀ PIÙ ALTA):
Per evitare di saltare capitoli o eventi allucinanti, DEVI eseguire esattamente questo ciclo:
Passaggio 1. Guarda SOLO il blocco "CAMPIONI CAPITOLO". Identificare i capitoli narrativi.
Passaggio 2. ESCLUDERE tutto il frontespizio e il sottofondo non narrativo (ad esempio copertina, frontespizio, copyright, sommario, dedica, ringraziamenti, anche di).
Passaggio 3. Per ogni capitolo narrativo, a partire dal primo, crea ESATTAMENTE UN oggetto evento nell'array `timeline`.
Passo 4. Il campo "capitolo" DEVE corrispondere esattamente all'intestazione del capitolo nell'esempio. (Mappali rigorosamente in ordine sequenziale).
Passaggio 5. Riassumi il capitolo specifico nel campo "evento" {TIMELINE_DETAIL_GUIDANCE} (caratteri MAX {MAX_TIMELINE_EVENT}). NON raggruppare i capitoli.
Passaggio 6. NESSUN SPOILER: fermati esattamente al segno %d%%. Non includere eventi oltre questo progresso.

ALGORITMO PER PERSONAGGI E FIGURE STORICHE:
Passaggio 1. Estrai i caratteri importanti utilizzando entrambi i blocchi di testo. ({NUM_CHARS} normale, MAX 10 se omnibus).
Passaggio 2. DEVI utilizzare i nomi COMPLETI e formali (ad esempio "Abraham Van Helsing"). NON utilizzare soprannomi casuali come nome principale.
Passaggio 3. Fornisci fino a 3 nomi, titoli o soprannomi alternativi che questo carattere utilizza in un array "alias". Includere il nome e il cognome comuni, se utilizzati. IMPORTANTE: se un cognome è condiviso da più personaggi (ad esempio, membri della famiglia), NON includerlo come alias per nessuno dei personaggi.
Passaggio 4. Cerca attivamente fino a {NUM_HIST} persone REALI NOTABILI della storia umana (ad es. Presidenti, Autori, Generali). Aggiungili a "figure_storiche".
CRITICA per Personaggi e Figure Storiche:
- NON estrarre personaggi o figure storiche menzionati SOLO in copertine o retroscena non narrativi (ad es. Ringraziamenti, biografia dell'autore, dediche, frontespizio, copyright).
- I personaggi storici DEVONO essere persone verificate del mondo reale con un ampio riconoscimento storico.
- NON includere personaggi puramente immaginari nell'elenco dei personaggi storici, anche se interagiscono con eventi storici reali. I personaggi immaginari DEVONO andare nell'array `characters`.
- SOLO per i personaggi storici, puoi utilizzare la tua conoscenza interna per scrivere la loro "biografia" generale e il loro "ruolo" storico, ma DEVI utilizzare il contesto del libro per il loro "contesto_nel_libro".
NESSUN SPOILER: fermati esattamente al segno %d%%.

ALGORITMO PER LE LOCALITÀ:
Passaggio 1. Estrai {NUM_LOCS} posizioni significative. NESSUN SPOILER: fermati esattamente al segno %d%%.

ALGORITMO PER I TERMINI:
Passaggio 0. Dichiara "book_type" come "fiction" o "non_fiction" nella root JSON.
Passaggio 1. Se non_fiction: estrai {NUM_TERMS} termini tecnici significativi, acronimi, gergo o concetti che i lettori non conoscerebbero senza una conoscenza specializzata. Utilizza categorie appropriate come acronimo, termine tecnico, concetto o gergo.
Passaggio 2. Se finzione: estrai {NUM_TERMS} elementi significativi della costruzione del mondo che un nuovo lettore avrebbe bisogno di spiegare, come fazioni inventate, organizzazioni, sistemi magici, tecnologie, creature, linguaggi o tradizioni nell'universo.
   - NON includere nomi di personaggi o nomi di luoghi (quelli vengono tracciati separatamente).
   - NON estrarre parole o concetti comuni del mondo reale.
   - Utilizza le categorie appropriate: Fazione, Sistema magico, Tecnologia, Creatura, Organizzazione, Conoscenza, Linguaggio.
Passaggio 3. Includere il significato dell'acronimo/frase in "espanso". Se non è un acronimo/una frase, ripetere il nome.
Passaggio 4. NON includere parole comuni di tutti i giorni.

REGOLE RIGOROSE PER LO SPOILER:
- ASSOLUTAMENTE NESSUNA informazione successiva all'avanzamento della lettura corrente. Fermati esattamente al segno %d%%.
- Le descrizioni devono riflettere lo stato dei personaggi in questo punto esatto del libro.

REGOLE RIGOROSE SULLA FONTE DELLA CONOSCENZA (CRITICA):
- Per PERSONAGGI DI NATURA: le tue descrizioni DEVONO basarsi ESCLUSIVAMENTE su ciò che è esplicitamente dichiarato o chiaramente implicito nel testo fornito. NON integrare con conoscenze derivanti da formazione precedente, fonti esterne o conoscenza generale del libro/serie/autore.
- Se finora un personaggio è stato menzionato solo brevemente nel testo, la tua descrizione deve riflettere solo quell'informazione limitata. NON dedurre, assumere o aggiungere dettagli non radicati nel contesto fornito.
- L'UNICA eccezione riguarda le FIGURE STORICHE REALI (inserite in "figure_storiche"): puoi utilizzare la conoscenza interna per la loro biografia/ruolo generale, ma fare comunque affidamento sul testo del libro per il loro "contesto_nel_libro".

RIGOROSE REGOLE DI SICUREZZA JSON:
- DEVI eseguire correttamente l'escape di tutte le virgolette doppie (\") all'interno delle stringhe.
- NON utilizzare interruzioni di riga senza caratteri di escape all'interno delle stringhe.
- Output SOLO JSON valido e analizzabile.

FORMATO JSON RICHIESTO:
{
  "book_type": "narrativa",
  "caratteri": [
    {
      "name": "Nome formale completo",
      "alias": ["Alias 1", "Alias 2"],
      "role": "Etichetta archetipo breve (3-5 parole, ad esempio 'Antagonista', 'Protagonista', 'La Vittima')",
      "genere": "Uomo/Donna/Sconosciuto",
      "occupazione": "Lavoro/Stato",
      "description": "Descrizione basata STRETTAMENTE sul testo fornito. Non dedurre o aggiungere conoscenze esterne. NESSUN SPOILER. (Numero massimo di {MAX_CHAR_DESC} caratteri)"
    }
  ],
  "figure_storiche": [
    {
      "name": "Nome di persona storica reale",
      "ruolo": "Ruolo storico",
      "biografia": "Breve biografia (MAX {MAX_HIST_BIO} caratteri)",
      "importance_in_book": "Importanza fino ai progressi attuali",
      "context_in_book": "Come vengono menzionati (MAX 100 caratteri)"
    }
  ],
  "località": [
    {"name": "Nome del luogo", "description": "Descrizione breve (MAX {MAX_LOC_DESC} caratteri)"}
  ],
  "termini": [
    {
      "nome": "Termine o acronimo",
      "expanded": "Espansione completa o uguale al nome",
      "category": "Acronimo / Termine tecnico / Concetto / Gergo",
      "definition": "Definizione concisa nel contesto (MAX {MAX_TERM_DEF} caratteri)"
    }
  ],
  "cronologia": [
    {
      "chapter": "Titolo esatto del capitolo dagli esempi",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Libro: %s
Autore: %s
Avanzamento nella lettura: %d%%

COMPITO: Estrai ESATTAMENTE 10 ULTERIORI caratteri importanti dal testo.
Restituisce SOLO un oggetto JSON valido.

MANDATO DI CONCISIONE (CRITICO):
Per evitare il troncamento della risposta AI, mantieni le descrizioni dei caratteri sotto i caratteri {MAX_CHAR_DESC}.

ISTRUZIONE CRITICA:
NON includere nessuno dei seguenti caratteri, poiché sono già stati estratti:
%s

REGOLE RIGOROSE PER LO SPOILER:
- ASSOLUTAMENTE NESSUNA informazione successiva all'avanzamento della lettura corrente. Fermati esattamente al segno %d%%.
- Le descrizioni devono riflettere lo stato dei personaggi in questo punto esatto del libro.

FORMATO JSON RICHIESTO:
{
  "caratteri": [
    {
      "name": "Nome formale completo",
      "alias": ["Alias 1", "Alias 2"],
      "role": "Etichetta archetipo breve (3-5 parole, ad esempio 'Antagonista', 'Protagonista', 'La Vittima')",
      "genere": "Uomo/Donna/Sconosciuto",
      "occupazione": "Lavoro/Stato",
      "description": "Descrizione basata RIGOROSAMENTE sul testo fornito. Non dedurre o aggiungere conoscenze esterne. NO SPOILER. (Max {MAX_CHAR_DESC} caratteri)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Libro: %s
Autore: %s
Avanzamento nella lettura: %d%%

COMPITO: Estrarre ESATTAMENTE 15 ULTERIORI termini significativi, acronimi, termini tecnici o concetti dal testo.
- Se questo libro non è narrativa: estrai termini tecnici, concetti, acronimi o gergo.
- Se questo libro è finzione: estrai elementi di costruzione del mondo come fazioni, organizzazioni, sistemi magici, tecnologie, creature, linguaggi o tradizioni nell'universo.
Restituisce SOLO un oggetto JSON valido.

MANDATO DI CONCISIONE (CRITICO):
Per evitare il troncamento della risposta AI, mantieni le definizioni dei termini sotto {MAX_TERM_DEF} caratteri.

ISTRUZIONE CRITICA:
NON includere nessuno dei seguenti termini, poiché sono già stati estratti:
%s

REGOLE RIGOROSE PER LO SPOILER:
- ASSOLUTAMENTE NESSUNA informazione successiva all'avanzamento della lettura corrente. Fermati esattamente al segno %d%%.

FORMATO JSON RICHIESTO:
{
  "termini": [
    {
      "nome": "Termine o acronimo",
      "expanded": "Espansione completa o uguale al nome",
      "category": "Fazione / Sistema magico / Tecnologia / Creatura / Organizzazione / Storia / Linguaggio / Acronimo / Termine tecnico / Concetto / Gergo",
      "definition": "Definizione concisa nel contesto (MAX {MAX_TERM_DEF} caratteri)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
L'utente ha evidenziato la parola "%s".
COMPITO: Determinare se questa parola rappresenta un personaggio, un luogo, una figura storica o un termine/acronimo tecnico nel libro.

FONDAMENTALE PER PERSONAGGI E LUOGHI: utilizzare il "CONTESTO DEL TESTO DEL LIBRO" fornito per identificare l'entità. Se la parola è fornita in un suggerimento "TARGET DI RICERCA" o "RIFERIMENTO DIRETTO", è presente nel libro nella posizione corrente. Non rifiutatelo solo perché non si trova esattamente nel testo narrativo sottocampionato. I nomi brevi (fino a 2 lettere, ad esempio "Oz", "Al", "Jo") sono validi e devono essere analizzati.
CRITICO PER I PERSONAGGI DI NATURA: Descrivi SOLO ciò che rivela il testo del libro fornito. NON utilizzare la conoscenza precedente della formazione su questo personaggio, anche se lo riconosci da una serie famosa. Se il testo menziona solo brevemente questo personaggio, la tua descrizione deve riflettere tale informazione limitata.
CRITICO PER FIGURE STORICHE: PUOI usare la tua conoscenza interna per verificare la loro identità e fornire la loro biografia/ruolo, SOLO se sono una figura storica reale e notevole. DEVI comunque utilizzare il contesto del testo per la loro rilevanza nel libro.
CRITICO PER I TERMINI: se il libro è saggistica, controlla se la parola è un termine tecnico, un acronimo o un concetto chiave. Per termini tecnici, concetti o gergo: il termine può apparire negli esempi di capitoli anziché nel contesto immediato della pagina: trattalo come valido se puoi definirlo nel contesto dell'argomento di questo libro. Imposta "is_valid" su false solo se la frase non ha assolutamente alcuna rilevanza per l'argomento di questo libro.
Se la parola NON è un carattere, un luogo, una figura storica o un termine/concetto tecnico, imposta "is_valid" su false.

FORMATO JSON RICHIESTO:
{
  "is_valid": vero,
  "tipo": "carattere",
  "articolo": {
    "nome": "Nome completo",
    "alias": ["Alias 1", "Alias 2"],
    "role": "Etichetta archetipo breve (3-5 parole, ad esempio 'Antagonista', 'Protagonista', 'La Vittima')",
    "genere": "Uomo/Donna/Sconosciuto",
    "occupazione": "Occupazione",
    "description": "Breve descrizione (MAX 250 caratteri)"
  },
  "messaggio_errore": ""
}

Nota: se il tipo è "posizione", l'elemento deve avere "nome" e "descrizione". Se il tipo è "figura_storica", l'elemento deve avere "nome", "biografia" e "ruolo". Se il tipo è "termine", l'elemento deve avere "nome", "espanso", "categoria" e "definizione".

Se "is_valid" è falso:
{
  "is_valid": falso,
  "error_message": "Breve spiegazione del motivo per cui questo non è un personaggio o un luogo."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
COMPITO: Combina le seguenti due descrizioni della stessa entità (personaggio o luogo) in un unico riepilogo, coerente e conciso.
Rimuovi le informazioni ridondanti e assicurati che la descrizione finale scorra in modo naturale.

Descrizione principale: %s
Descrizione secondaria: %s

FORMATO JSON RICHIESTO:
{
  "merged_description": "Descrizione combinata e ottimizzata (max {MAX_CHAR_DESC} caratteri)"
}]],

    -- Series Detect
    series_detect = [[
Titolo del libro: %s
Autore: %s

COMPITO: Determina se questo libro fa parte di una serie con nome.
Restituisci SOLO JSON valido:
{
  "is_series": vero,
  "series_name": "La ruota del tempo",
  "indice_libro": 3,
  "total_books_known": 14
}
Se questo NON è un libro di serie, restituisci:
{ "è_serie": falso }]],

    -- Prior Book List
    prior_book_list = [[
Serie: %s
Indice dei libri correnti: %d
Titolo del libro corrente: %s

COMPITO: Elenca i titoli (e gli autori se diversi da "%s") dei libri da 1 a %d
che vengono PRIMA del libro attuale di questa serie.
Restituisci SOLO JSON valido:
{
  "libri_precedenti": [
    { "index": 1, "title": "L'occhio del mondo", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
Libro: %s
Autore: %s
Questo è il libro %d della serie "%s".

COMPITO: Fornire un riepilogo COMPLETO dell'intero libro per un lettore
che sta per iniziare il prossimo libro della serie.
Includere: personaggi chiave (nome, ruolo, stato finale alla fine del libro), luoghi principali,
eventi critici della trama e introdotti termini importanti per la costruzione del mondo.
NESSUN SPOILER per i libri OLTRE questo.

FORMATO JSON RICHIESTO:
{
  "caratteri": [
    { "name": "Nome completo", "aliases": [], "role": "...", "description": "Stato alla fine di questo libro (max 300 caratteri)" }
  ],
  "località": [
    { "nome": "...", "descrizione": "..." }
  ],
  "termini": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "cronologia": [
    { "capitolo": "Riepilogo del libro", "evento": "Un riepilogo unico, altamente dettagliato e completo della trama dell'intero libro, degli eventi principali e della risoluzione (massimo 2000 caratteri). DEVI formattare questo riepilogo utilizzando più paragrafi distinti separati da doppi ritorni a capo (\\n\\n) per la leggibilità invece di un unico muro di testo." }
  ]
}]],

    -- Fallback strings
    fallback = {
        no_biography = "Nessuna biografia disponibile",
        no_description = "Nessuna descrizione",
        not_specified = "Non specificato",
        unknown_author = "Autore sconosciuto",
        unknown_book = "Libro sconosciuto",
        unnamed_character = "Personaggio senza nome",
        unnamed_person = "Persona senza nome"
    }
}

