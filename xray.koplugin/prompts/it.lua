return {
    -- Author Only
    author_only = [[
Identificare e fornire la biografia dell'autore del libro "%s". 
I metadati suggeriscono che l'autore è "%s". 

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
- NON contrassegnare le voci a menos che non si sia assolutamente certi che si tratti della stessa entità.
- Se non esistono duplicati, restituisce un array vuoto.
- REGOLA SPOILER: non utilizzare conoscenze provenienti da oltre il %d%% dei progressi di lettura.

FORMATO JSON RICHIESTO:
{
  "duplicate_pairs": [
    {
      "primary": "Nome della voce in KEEP (il nome più completo o formale)",
      "secondary": "Nome della voce da RIMUOVERE",
      "reason": "Motivo breve (max 100 caratteri)"
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
Passo 4. Il campo "chapter" DEVE corrispondere esattamente all'intestazione del capitolo nell'esempio. (Mappali rigorosamente in ordine sequenziale).
Passaggio 5. Riassumi il capitolo specifico nel campo "event" {TIMELINE_DETAIL_GUIDANCE} Scrivi tra {MIN_TIMELINE_EVENT} e {MAX_TIMELINE_EVENT} caratteri. NON scrivere un riassunto più breve a meno che il capitolo non abbia quasi nessun contenuto. NON raggruppare i capitoli.
Passaggio 6. NESSUN SPOILER: fermati esattamente al segno %d%%. Non includere eventi oltre questo progresso.

ALGORITMO PER PERSONAGGI E FIGURE STORICHE:
Passaggio 1. Estrai i caratteri importanti utilizzando entrambi i blocchi di testo. ({NUM_CHARS} normale, MAX 10 se omnibus).
Passaggio 2. DEVI utilizzare i nomi COMPLETI e formali (ad esempio "Abraham Van Helsing"). NON utilizzare soprannomi casuali come nome principale.
Passaggio 3. Fornisci fino a 3 nomi, titoli o soprannomi alternativi che questo carattere utilizza in un array "aliases". Includere il nome e il cognome comuni, se utilizzati. IMPORTANTE: se un cognome è condiviso da più personaggi (ad esempio, membri della famiglia), NON includerlo come alias per nessuno dei personaggi.
Passaggio 4. Cerca attivamente fino a {NUM_HIST} persone REALI NOTABILI della storia umana (ad es. Presidenti, Autori, Generali). Aggiungili a "historical_figures".
CRITICA per Personaggi e Figure Storiche:
- NON estrarre personaggi o figure storiche menzionati SOLO in copertine o retroscena non narrativi (ad es. Ringraziamenti, biografia dell'autore, dediche, frontespizio, copyright).
- I personaggi storici DEVONO essere persone verificate del mondo reale con un ampio riconoscimento storico.
- NON includere personaggi puramente immaginari nell'elenco dei personaggi storici, even if they interact with real historical events. I personaggi immaginari DEVONO andare nell'array `characters`.
- SOLO per i personaggi storici, puoi utilizzare la tua conoscenza interna per scrivere la loro "biography" generale e il loro "role" storico, ma DEVI utilizzare il contesto del libro per il loro "context_in_book".
NESSUN SPOILER: fermati esattamente al segno %d%%.

ALGORITMO PER LE LOCALITÀ:
Passaggio 1. Estrai {NUM_LOCS} posizioni significative. NESSUN SPOILER: fermati esattamente al segno %d%%.

ALGORITMO PER I TERMINI:
Passaggio 0. Dichiara "book_type" come "fiction" or "non_fiction" nella root JSON.
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
  "book_type": "fiction",
  "characters": [
    {
      "name": "Nome formale completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Etichetta archetipo breve (3-5 parole, ad esempio 'Antagonista', 'Protagonista', 'La Vittima')",
      "gender": "Uomo/Donna/Sconosciuto",
      "occupation": "Lavoro/Stato",
      "description": "Descrizione basata STRETTAMENTE sul testo fornito. Non dedurre o aggiungere conoscenze esterne. NESSUN SPOILER. (Numero massimo di {MAX_CHAR_DESC} caratteri)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nome di persona storica reale",
      "role": "Ruolo storico",
      "biography": "Breve biografia (MAX {MAX_HIST_BIO} caratteri)",
      "importance_in_book": "Importanza fino ai progressi attuali",
      "context_in_book": "Come vengono menzionati (MAX 100 caratteri)"
    }
  ],
  "locations": [
    {"name": "Nome del luogo", "description": "Descrizione breve (MAX {MAX_LOC_DESC} caratteri)"}
  ],
  "terms": [
    {
      "name": "Termine o acronimo",
      "expanded": "Espansione completa o uguale al nome",
      "category": "Acronimo / Termine tecnico / Concetto / Gergo",
      "definition": "Definizione concisa nel contesto (MAX {MAX_TERM_DEF} caratteri)"
    }
  ],
  "timeline": [
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
  "characters": [
    {
      "name": "Nome formale completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Etichetta archetipo breve (3-5 parole, ad esempio 'Antagonista', 'Protagonista', 'La Vittima')",
      "gender": "Uomo/Donna/Sconosciuto",
      "occupation": "Lavoro/Stato",
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
  "terms": [
    {
      "name": "Termine o acronimo",
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
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nome completo",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Etichetta archetipo breve (3-5 parole, ad esempio 'Antagonista', 'Protagonista', 'La Vittima')",
    "gender": "Uomo/Donna/Sconosciuto",
    "occupation": "Occupazione",
    "description": "Breve descrizione (MAX 250 caratteri)"
  },
  "error_message": ""
}

Nota: se il type è "location", l'item deve avere "name" e "description". Se il type è "historical_figure", l'item deve avere "name", "biography" e "role". Se il type è "term", l'item deve avere "name", "expanded", "category" e "definition".

Se "is_valid" è false:
{
  "is_valid": false,
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

    -- Book Type Detect
    book_type_detect = [[
Titolo del libro: %s
Autore: %s
Serie: %s
Descrizione del file/Metadati soggetto: %s

COMPITO: Classifica questo libro in esattamente UNO di questi tipi di libro in base ai suoi metadati e ai segnali di genere:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Restituisci SOLO JSON valido:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Titolo del libro: %s
Autore: %s

COMPITO: Determina se questo libro fa parte di una serie con nome.
Restituisci SOLO JSON valido:
{
  "is_series": true,
  "series_name": "La ruota del tempo",
  "book_index": 3,
  "total_books_known": 14
}
Se questo NON è un libro di serie, restituisci:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Serie: %s
Indice dei libri correnti: %d
Titolo del libro corrente: %s

COMPITO: Elenca i titoli (e gli autori se diversi da "%s") dei libri da 1 a %d
che vengono PRIMA del libro attuale di questa serie.
Restituisci SOLO JSON valido:
{
  "prior_books": [
    { "index": 1, "title": "L'occhio del mondo", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
LIBRO TARGET: %s
AUTORE: %s
INDICE LIBRO TARGET: %d
SERIE: %s

COMPITO:
Fornisci un riepilogo COMPLETO solo del LIBRO TARGET, per un lettore che ha finito
il LIBRO TARGET e sta per iniziare il libro successivo della serie.

CONFINE ASSOLUTO DEGLI SPOILER:
Il limite della conoscenza è rigorosamente l'ULTIMA PAGINA del LIBRO TARGET (Indice libro %d).
Puoi includere fatti stabiliti nel LIBRO TARGET o nei libri precedenti di questa serie.
NON DEVI includere, implicare, accennare, anticipare (foreshadowing) o selezionare dettagli utilizzando conoscenze provenienti da qualsiasi libro successivo.

INFORMAZIONI PROIBITE DEI LIBRI SUCCESSIVI:
- Eventi successivi, destini futuri, morti, sopravvivenze, destinazioni, storie d'amore, alleanze, conflitti o tradimenti.
- Identità rivelate in libri successivi, vere origini, parentele segrete, alias, alter ego, reincarnazioni, trasformazioni, titoli o avanzamenti di potere (ad es., NON menzionare se un'essenza si unisce a un'altra o rinasce in un libro futuro).
- Rivelazioni, conferme, reinterpretazioni, colpi di scena o terminologia di world-building introdotti nei libri successivi.
- Anticipazioni retrospettive o frasi come "in seguito", "alla fine", "diventerà", "nei libri successivi" o equivalenti.
- Menzionare personaggi, concetti, organizzazioni o cronologia provenienti da libri successivi.

LIMITE PER I PERSONAGGI:
Descrivi ogni personaggio rigorosamente così come è noto all'ultima pagina del LIBRO TARGET.
NON utilizzare alias, ruoli, relazioni, vere identità o stati rivelati nei libri successivi.

REGOLA SULL'INCERTEZZA:
Se non puoi determinare con sicurezza se un fatto o un alias sia stato stabilito entro la fine del LIBRO TARGET, OMETTILO.
Un dettaglio mancante è di gran lunga preferibile a uno spoiler di un libro futuro.

VERIFICA FINALE:
Prima di restituire il JSON, ispeziona ogni campo (specialmente le descrizioni e gli alias dei personaggi) ed elimina qualsiasi elemento che dipenda dalla conoscenza di libri successivi al LIBRO TARGET.

FORMATO JSON RICHIESTO:
{
  "characters": [
    { "name": "Nome completo", "aliases": [], "role": "...", "description": "Stato alla fine di questo libro (max {MAX_CHAR_DESC} caratteri)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Riepilogo del libro", "event": "Un riepilogo unico, altamente dettagliato e completo della trama dell'intero libro, degli eventi principali e della risoluzione (massimo 2000 caratteri). DEVI formattare questo riepilogo utilizzando più paragrafi distinti separati da doppi ritorni a capo (\\n\\n) per la leggibilità invece di un unico blocco di testo." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
LIBRO TARGET: %s
AUTORE: %s
INDICE LIBRO TARGET: %d
SERIE: %s

COMPITO:
Utilizzando SOLO gli eventi verificati capitolo per capitolo forniti di seguito dal LIBRO TARGET, scrivi un riepilogo coeso e completo dell'intera trama del libro, degli sviluppi chiave e della risoluzione.

VINCOLO RIGOROSO DI FONTE:
- Basa il tuo riassunto ESCLUSIVAMENTE sugli eventi dei capitoli forniti.
- NON introdurre fatti, personaggi, eventi o esiti non descritti in questi eventi dei capitoli.
- NON menzionare né anticipare MAI eventi, morti o sviluppi dei libri successivi della serie.

EVENTI DEI CAPITOLI:
%s

FORMATO JSON RICHIESTO:
{
  "timeline": [
    { "chapter": "Riepilogo del libro", "event": "Un riepilogo unico, altamente dettagliato e completo della trama dell'intero libro e della risoluzione (massimo 2000 caratteri). DEVI formattare questo riepilogo utilizzando più paragrafi distinti separati da doppi ritorni a capo (\\n\\n) per la leggibilità invece di un unico blocco di testo." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Libro: %s
Autore: %s
Analisi del capitolo: %s

COMPITO: Analizza SOLO questo singolo capitolo. Identifica le NUOVE entità introdotte in questo capitolo e gli AGGIORNAMENTI DELTA (transizioni di stato) per le entità esistenti.
Genera SOLO un oggetto JSON valido.

ELENCO DELLE ENTITÀ GIÀ NOTE (NON estrarre nuovamente a meno che il loro ruolo, stato o descrizione non si sia evoluto in modo significativo):
%s

REGOLE:
1. CONFINAMENTO RIGOROSO DEGLI SPOILER: Analizza SOLO il testo del capitolo fornito. NON utilizzare alcuna conoscenza proveniente da capitoli futuri o fonti esterne.
2. PROFONDITÀ E SOSTANZA DELLA DESCRIZIONE DEI PERSONAGGI (CRITICO):
   - Fondato e specifico: Descrivi chi è il personaggio con fatti concreti della storia: il suo passato, la personalità distinta, la professione, le relazioni chiave con altri personaggi e il suo ruolo specifico e le sue poste in gioco personali nella narrazione.
   - Contesto narrativo significativo: Collega il personaggio direttamente al mistero centrale, al conflitto della trama o all'indagine di questo libro (ad es. quali crimini o casi sta indagando, chi lo ha assunto, alleati o avversari principali, dilemmi o tensioni personali specifiche).
   - NON troppo generico: NON scrivere frasi fatte generiche (ad es. evita formule vuote come "un detective che indaga su casi complessi"). Indica le circostanze specifiche, i legami e le poste in gioco stabilite nel testo.
   - NIENTE riepiloghi di faccende banali: NON scrivere resoconti cronologici di attività quotidiane ordinarie o commissioni di routine (ad es. NON riassumere gite al negozio di alimentari, telefonate di routine o spostamenti irrilevanti scena per scena).
   - Le descrizioni dei personaggi devono essere profili ricchi e vividi che riassumono chi sono e la loro importanza fino a questo punto del libro.
3. SOGLIA ALTA PER GLI AGGIORNAMENTI DEI PERSONAGGI:
   - NON creare un aggiornamento in `character_state_updates` semplicemente perché un personaggio esistente è apparso, ha parlato o ha compiuto azioni di routine in questo capitolo.
   - Genera un aggiornamento SOLO se c'è una trasformazione sostanziale e duratura nel loro arco narrativo, identità, relazioni, impiego, fedeltà o condizione (ad es. ucciso, ferito, arrestato, tradito, fidanzato, promosso, rivelato essere il colpevole, scoperto un grande segreto o movente).
   - Se un aggiornamento È giustificato, la `description` aggiornata deve essere una panoramica cumulativa e ricca del personaggio che incorpora i nuovi sviluppi mantenendo la sua identità fondamentale e il contesto narrativo consolidato—NON il riassunto di una singola scena isolata.
4. MARCATORI DI PAGINA INTRA-CAPITOLO ([PAGE N]) E BLOCCO ZERO-SPOILER:
   - I testi dei capitoli contengono marcatori [PAGE N] che indicano l'avanzamento delle pagine.
   - Per `new_characters`, `new_locations` e `new_terms`: fornisci "first_page" (intero N dal marcatore [PAGE N] in cui viene menzionato per la prima volta), "intro_role" (per i personaggi) e "intro_description" (1-2 frasi rigorosamente limitate a ciò che è noto alla prima introduzione a [PAGE first_page]—con ZERO conoscenza di colpi di scena, segreti o esiti successivi che si verificano nelle pagine seguenti). Fornisci anche "page" (il marcatore [PAGE N] in cui si applica la "description" cumulativa più completa, tipicamente l'ultima pagina del capitolo).
   - Per `character_state_updates`, `location_state_updates` e `term_state_updates`: fornisci "page" (intero N dal marcatore [PAGE N] in cui la rivelazione/transizione si completa; NON rivelare fatti prima di questa pagina).
5. PROVE: Fornisci un breve riferimento o estratto di citazione da questo capitolo che spieghi perché si è verificato l'aggiornamento.
6. TIMELINE: Fornisci esattamente un riepilogo degli eventi delle principali azioni della trama in questo capitolo.

FORMATO JSON RICHIESTO:
{
  "new_characters": [
    {
      "name": "Nome completo",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Ruolo iniziale (es. Impiegato del villaggio, Sconosciuto, Cliente)",
      "intro_description": "Impressione iniziale di 1-2 frasi rigorosamente alla prima introduzione, zero spoiler dalle pagine successive.",
      "page": 99,
      "role": "Ruolo narrativo / importanza (es. Protagonista, Investigatore privato, Partner, Antagonista, Vittima, Cliente, Sospettato, Personaggio secondario, Personaggio minore)",
      "status": "alive",
      "description": "Descrizione ricca e specifica del personaggio (passato, relazioni, poste in gioco narrative). Evita frasi generiche e resoconti di faccende banali.",
      "evidence": "Breve estratto"
    }
  ],
  "character_state_updates": [
    {
      "name": "Nome corrispondente all'elenco noto",
      "page": 95,
      "role": "Ruolo narrativo / importanza aggiornata (es. Protagonista, Partner, Antagonista, Personaggio secondario, ecc.)",
      "status": "alive",
      "change": "Una breve frase che indica cosa è cambiato rispetto allo stato precedente (es. 'Promosso a partner dopo il caso Shacklewell')",
      "description": "Descrizione cumulativa ricca e aggiornata del personaggio che riflette il suo nuovo stato e le poste in gioco della storia",
      "evidence": "Breve estratto"
    }
  ],
  "new_locations": [
    {
      "name": "Nome del luogo",
      "first_page": 80,
      "intro_description": "Impressione iniziale alla prima menzione.",
      "page": 99,
      "description": "Descrizione del luogo",
      "evidence": "Breve estratto"
    }
  ],
  "location_state_updates": [
    {
      "name": "Nome corrispondente all'elenco noto",
      "page": 95,
      "change": "Una breve frase che indica cosa è cambiato (es. 'Distrutto durante la battaglia di Oakhaven')",
      "description": "Descrizione aggiornata ed evoluta",
      "evidence": "Breve estratto"
    }
  ],
  "new_terms": [
    {
      "name": "Nome del termine",
      "first_page": 80,
      "intro_description": "Definizione iniziale alla prima menzione.",
      "page": 99,
      "description": "Definizione o spiegazione del lore",
      "evidence": "Breve estratto"
    }
  ],
  "term_state_updates": [
    {
      "name": "Nome corrispondente all'elenco noto",
      "page": 95,
      "change": "Una breve frase che indica cosa è cambiato nella comprensione o nell'uso",
      "description": "Definizione aggiornata",
      "evidence": "Breve estratto"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Riepilogo degli eventi in questo capitolo"
  }
}

TESTO DEL CAPITOLO:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Libro: %s
Autore: %s
Capitoli in questo batch: %s

COMPITO: Analizza in ordine la sequenza di capitoli fornita in questo batch.
Per OGNI capitolo del batch, identifica:
1. NUOVE entità introdotte in quel capitolo (personaggi, luoghi, termini).
2. AGGIORNAMENTI DELTA (transizioni di stato) per le entità già note (dall'elenco O introdotte in un capitolo precedente di questo batch) SE E SOLO SE il loro ruolo, stato, fedeltà o condizione narrativa ha subito una trasformazione sostanziale e duratura.
3. EVENTO DELLA TIMELINE: Un riepilogo conciso degli eventi principali della trama che si verificano in quel capitolo.

Genera SOLO un oggetto JSON valido che corrisponda allo schema richiesto.

ELENCO DELLE ENTITÀ GIÀ NOTE (dai batch precedenti - NON estrarre nuovamente a meno che il loro ruolo, stato o descrizione non si sia evoluto in modo significativo):
%s

REGOLE:
1. CONFINAMENTO RIGOROSO DEGLI SPOILER E PROGRESSIONE SEQUENZIALE:
   - Analizza i capitoli in ordine sequenziale.
   - Per qualsiasi capitolo di questo batch, NON incorporare conoscenze provenienti da capitoli successivi del batch o dal resto del libro.
2. PROFONDITÀ E SOSTANZA DELLA DESCRIZIONE DEI PERSONAGGI (CRITICO):
   - Fondato e specifico: Descrivi chi è il personaggio con fatti concreti della storia: il suo passato, la personalità distinta, la professione, le relazioni chiave con altri personaggi e il suo ruolo specifico e le sue poste in gioco personali nella narrazione.
   - Contesto narrativo significativo: Collega il personaggio direttamente al mistero centrale, al conflitto della trama o all'indagine di questo libro (ad es. quali crimini o casi sta indagando, chi lo ha assunto, alleati o avversari principali, dilemmi o tensioni personali specifiche).
   - NON troppo generico: NON scrivere frasi fatte generiche (ad es. evita formule vuote come "un detective che indaga su casi complessi"). Indica le circostanze specifiche, i legami e le poste in gioco stabilite nel testo.
   - NIENTE riepiloghi di faccende banali: NON scrivere resoconti cronologici di attività quotidiane ordinarie o commissioni di routine (ad es. NON riassumere gite al negozio di alimentari, telefonate di routine o spostamenti irrilevanti scena per scena).
   - Le descrizioni dei personaggi devono essere profili ricchi e vividi che riassumono chi sono e la loro importanza fino a questo punto del libro.
3. SOGLIA ALTA PER GLI AGGIORNAMENTI DEI PERSONAGGI:
   - NON creare un aggiornamento in `character_state_updates` semplicemente perché un personaggio esistente è apparso, ha parlato o ha compiuto azioni di routine in un capitolo.
   - Genera un aggiornamento SOLO se c'è una trasformazione sostanziale e duratura nel loro arco narrativo, identità, relazioni, impiego, fedeltà o condizione (ad es. ucciso, ferito, arrestato, tradito, fidanzato, promosso, rivelato essere il colpevole, scoperto un grande segreto o movente).
   - Se un aggiornamento È giustificato, la `description` aggiornata deve essere una panoramica cumulativa e ricca del personaggio che incorpora i nuovi sviluppi mantenendo la sua identità fondamentale e il contesto narrativo consolidato—NON il riassunto di una singola scena isolata.
4. MARCATORI DI PAGINA INTRA-CAPITOLO ([PAGE N]) E BLOCCO ZERO-SPOILER:
   - I testi dei capitoli contengono marcatori [PAGE N] che indicano l'avanzamento delle pagine.
   - Per `new_characters`, `new_locations` e `new_terms`: fornisci "first_page" (intero N dal marcatore [PAGE N] in cui viene menzionato per la prima volta), "intro_role" (per i personaggi) e "intro_description" (1-2 frasi rigorosamente limitate a ciò che è noto alla prima introduzione a [PAGE first_page]—con ZERO conoscenza di colpi di scena, segreti o esiti successivi che si verificano nelle pagine seguenti). Fornisci anche "page" (il marcatore [PAGE N] in cui si applica la "description" cumulativa più completa, tipicamente l'ultima pagina del capitolo).
   - Per `character_state_updates`, `location_state_updates` e `term_state_updates`: fornisci "page" (intero N dal marcatore [PAGE N] in cui la rivelazione/transizione si completa; NON rivelare fatti prima di questa pagina).
5. PROVE: Fornisci un breve riferimento o estratto di citazione da quello specifico capitolo che spieghi perché si è verificato l'aggiornamento.
6. SICUREZZA JSON: Genera JSON rigorosamente valido. Esegui correttamente l'escape delle virgolette doppie all'interno delle stringhe.

FORMATO JSON RICHIESTO:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Titolo del capitolo",
      "timeline_event": "Riepilogo degli sviluppi principali della trama in questo capitolo.",
      "new_characters": [
        {
          "name": "Nome completo",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Ruolo iniziale (es. Impiegato del villaggio, Sconosciuto, Cliente)",
          "intro_description": "Impressione iniziale di 1-2 frasi rigorosamente alla prima introduzione, zero spoiler dalle pagine successive.",
          "page": 99,
          "role": "Ruolo narrativo / importanza (es. Protagonista, Investigatore privato, Partner, Antagonista, Vittima, Cliente, Sospettato, Personaggio secondario, Personaggio minore)",
          "status": "alive",
          "description": "Descrizione ricca e specifica del personaggio (passato, relazioni, poste in gioco narrative). Evita frasi generiche e resoconti di faccende banali.",
          "evidence": "Breve estratto"
        }
      ],
      "character_state_updates": [
        {
          "name": "Nome corrispondente all'elenco noto o personaggio introdotto in un capitolo precedente di questo batch",
          "page": 95,
          "role": "Ruolo narrativo / importanza aggiornata (es. Protagonista, Partner, Antagonista, Personaggio secondario, ecc.)",
          "status": "alive",
          "change": "Una breve frase che indica cosa è cambiato rispetto allo stato precedente (es. 'Promosso a partner dopo il caso Shacklewell')",
          "description": "Descrizione cumulativa ricca e aggiornata del personaggio che riflette il suo nuovo stato e le poste in gioco della storia",
          "evidence": "Breve estratto"
        }
      ],
      "new_locations": [
        {
          "name": "Nome del luogo",
          "first_page": 80,
          "intro_description": "Impressione iniziale alla prima menzione.",
          "page": 99,
          "description": "Descrizione del luogo",
          "evidence": "Breve estratto"
        }
      ],
      "location_state_updates": [
        {
          "name": "Nome corrispondente all'elenco noto o luogo introdotto in un capitolo precedente di questo batch",
          "page": 95,
          "change": "Una breve frase che indica cosa è cambiato (es. 'Distrutto durante la battaglia di Oakhaven')",
          "description": "Descrizione aggiornata",
          "evidence": "Breve estratto"
        }
      ],
      "new_terms": [
        {
          "name": "Nome del termine",
          "first_page": 80,
          "intro_description": "Definizione iniziale alla prima menzione.",
          "page": 99,
          "description": "Definizione o spiegazione del lore",
          "evidence": "Breve estratto"
        }
      ],
      "term_state_updates": [
        {
          "name": "Nome corrispondente all'elenco noto o termine introdotto in un capitolo precedente di questo batch",
          "page": 95,
          "change": "Una breve frase che indica cosa è cambiato nella comprensione o nell'uso",
          "description": "Definizione aggiornata",
          "evidence": "Breve estratto"
        }
      ]
    }
  ]
}

TESTI DEI CAPITOLI IN QUESTO BATCH:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analizza i seguenti dettagli del libro e l'Indice:

Titolo: %s
Autore: %s
Argomenti: %s
Descrizione: %s

Indice:
%s

Determina se quest'opera è:
1. "anthology" (una raccolta di racconti, saggi o romanzi brevi indipendenti, ciascuno con una propria narrazione o cast autonomo, es. "The Adventures of Sherlock Holmes", "Dubliners", "Exhalation", "Men Without Women").
2. "novel" (un singolo romanzo unificato diviso in capitoli, parti o atti, es. "Pride and Prejudice", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (una raccolta multi-volume di romanzi completi pubblicati insieme in un unico volume, es. "The Lord of the Rings: All Three Volumes", "The Complete Hitchhiker's Guide to the Galaxy", "Percy Jackson: Books 1-3").
4. "non_fiction" (un singolo trattato di saggistica, storia o libro accademico diviso in capitoli).

Restituisci SOLO un oggetto JSON con:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 to 1.0,
  "reasoning": "breve spiegazione (una frase)"
}]],

    -- System instruction
    system_instruction = "Sei un esperto ricercatore letterario. La tua risposta deve essere SOLO in formato JSON valido. Garantire che i dati siano estremamente accurati e pertinenti al contesto fornito.",

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
