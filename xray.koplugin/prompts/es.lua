return {
    -- Author Only
    author_only = [[
Identifica y proporciona una biografía del autor del libro "%s". 
Los metadatos sugieren que el autor es "%s". 

CRÍTICO: Verifica el autor utilizando el CONTEXTO DEL TEXTO DEL LIBRO (si se proporciona al final de este mensaje) para garantizar el 100%% de precisión y evitar identificaciones incorrectas.

FORMATO JSON REQUERIDO:
{
  "author": "Nombre Completo Correcto",
  "author_bio": "Biografía exhaustiva centrada en su carrera literaria y obras principales.",
  "author_birth": "Fecha de nacimiento, formateada según el formato de fecha local",
  "author_death": "Fecha de fallecimiento, formateada según el formato de fecha local"
}]],

    -- Find Duplicates
    find_duplicates = [[
Libro: %s
Autor: %s
Progreso de lectura: %d%%

Está revisando la siguiente lista de %s extraídos de este libro.
Su tarea es identificar las entradas que parezcan ser la MISMA entidad enumerada bajo diferentes nombres.

LISTA:
%s

REGLAS:
- Existe un duplicado cuando dos entradas se refieren claramente a la misma entidad (por ejemplo, "La Gran Biblioteca" y "Gran Biblioteca", o "John" y "John Doe").
- NO marque entradas que sean simplemente relacionadas o similares pero distintas.
- NO marque entradas a menos que esté muy seguro de que son la misma entidad.
- Si no existen duplicados, devuelva un array vacío.
- REGLA DE SPOILER: No utilice información que vaya más allá del %d%% del progreso de lectura.

FORMATO JSON REQUERIDO:
{
  "duplicate_pairs": [
    {
      "primary": "Nombre de la entrada a CONSERVAR (el nombre más completo o formal)",
      "secondary": "Nombre de la entrada a ELIMINAR",
      "reason": "Razón breve (máx. 100 caracteres)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Libro: %s
Autor: %s
Progreso de lectura: %d%%

TAREA: Realizar un análisis de X-Ray completo. Generar ÚNICAMENTE un objeto JSON válido.

PARTICIÓN DE ATENCIÓN CRÍTICA:
Estás procesando un documento masivo con dos bloques de texto proporcionados al final de este prompt:
1. "CHAPTER SAMPLES": Este es el macro-contexto del libro hasta la ubicación actual del lector.
2. "BOOK TEXT CONTEXT": Este es el micro-contexto de los últimos 20,000 caracteres.

PROTOCOLO ANTI-TRUNCAMIENTO (CRÍTICO):
Tienes un límite estricto de salida máxima. Si "CHAPTER SAMPLES" contiene MÁS DE 40 capítulos (por ejemplo, una edición ómnibus):
1. DEBES reducir la lista de personajes ÚNICAMENTE a los 10 personajes absolutamente más importantes.
2. DEBES reducir las descripciones de los personajes a un MÁXIMO de {MAX_CHAR_DESC} caracteres.
3. DEBES reducir los resúmenes de eventos de la cronología a un MÁXIMO de {MAX_TIMELINE_EVENT} caracteres.
El no comprimir tu salida para libros masivos causará que el JSON se trunque y falle.

ALGORITMO PARA LA CRONOLOGÍA (MÁXIMA PRIORIDAD):
Para evitar omitir capítulos o alucinar eventos, DEBES ejecutar este bucle exacto:
Paso 1. Observa ÚNICAMENTE el bloque "CHAPTER SAMPLES". Identifica los capítulos narrativos.
Paso 2. EXCLUYE todo el material preliminar y final no narrativo (por ejemplo: Portada, Portadilla, Copyright, Índice, Dedicatoria, Agradecimientos, Otras obras de).
Paso 3. Por cada capítulo narrativo, comenzando desde el primero, crea EXACTAMENTE UN objeto de evento en el arreglo `timeline`.
Paso 4. El campo `chapter` DEBE coincidir exactamente con el encabezado del capítulo en la muestra. (Mapearlos estrictamente en orden secuencial).
Paso 5. Resume ese capítulo específico en el campo `event`. {TIMELINE_DETAIL_GUIDANCE} Escribe entre {MIN_TIMELINE_EVENT} y {MAX_TIMELINE_EVENT} caracteres. NO escribas un resumen más corto a menos que el capítulo casi no tenga contenido. NO agrupes capítulos.
Paso 6. SIN SPOILERS: Detente exactamente en la marca del %d%%. No incluyas eventos posteriores a este progreso.

ALGORITMO PARA PERSONAJES Y FIGURAS HISTÓRICAS:
Paso 1. Extrae personajes importantes utilizando ambos bloques de texto. ({NUM_CHARS} normales, MÁXIMO 10 si es ómnibus). Incluye siempre al personaje principal / protagonista por su nombre, incluso en narrativas en primera persona ("yo"/"mí") donde su nombre aparezca con poca frecuencia.
Paso 2. DEBES usar sus nombres COMPLETOS y formales (por ejemplo, "Abraham Van Helsing"). NO uses apodos informales como nombre principal. Nunca fusiones o incluyas a un personaje bajo una referencia posesiva/relacional (por ejemplo, "Papá de Nick" y "Nick" son personajes separados).
Paso 3. Proporciona hasta 3 nombres alternativos, títulos o apodos que este personaje utilice en un arreglo `aliases`. Incluye su nombre de pila y apellido comunes si se utilizan. IMPORTANTE: Si varios personajes comparten un apellido (por ejemplo, miembros de una familia), NO lo incluyas como un alias para ninguno de los personajes.
Paso 4. Escanea activamente hasta {NUM_HIST} personas REALES NOTABLES de la historia humana (por ejemplo, Presidentes, Autores, Generales). Agrégalos a `historical_figures`.
CRÍTICO para Personajes y Figuras Históricas:
- NO extraigas personajes o figuras históricas mencionadas ÚNICAMENTE en material preliminar o final no narrativo (por ejemplo, Agradecimientos, Biografía del autor, Dedicatorias, Portadilla, Copyright).
- Las Figuras Históricas DEBEN ser personas del mundo real verificadas con un reconocimiento histórico generalizado.
- NO incluyas personajes puramente ficticios en la lista de figuras históricas, incluso si interactúan con eventos históricos reales. Los personajes ficticios DEBEN ir en el arreglo `characters`.
- ÚNICAMENTE para las Figuras Históricas, puedes usar tu conocimiento interno para escribir su `biography` general y su `role` histórico, pero DEBES usar el contexto del libro para su `context_in_book`.
SIN SPOILERS: Detente exactamente en la marca del %d%%.

ALGORITMO PARA UBICACIONES:
Paso 1. Extrae {NUM_LOCS} ubicaciones significativas. SIN SPOILERS: Detente exactamente en la marca del %d%%.

ALGORITMO PARA TÉRMINOS:
Paso 0. Declara "book_type" como "fiction", "non_fiction", o "anthology" en la raíz del JSON.
Paso 1. Si es non_fiction: extrae {NUM_TERMS} términos técnicos, acrónimos, jerga o conceptos significativos que los lectores no conocerían sin un conocimiento especializado. Utiliza categorías apropiadas como Acronym, Technical Term, Concept, o Jargon.
Paso 2. Si es fiction o anthology: extrae {NUM_TERMS} elementos significativos de construcción de mundo (world-building) que un nuevo lector necesitaría que se le expliquen—tales como facciones inventadas, organizaciones, sistemas de magia, tecnologías, criaturas, idiomas o lore del universo.
   - NO incluyas nombres de personajes ni nombres de ubicaciones (esos se rastrean por separado).
   - DO NOT extraigas palabras o conceptos comunes del mundo real.
   - Utiliza categorías apropiadas: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Paso 3. Incluye lo que el acrónimo/frase representa en "expanded". Si no es un acrónimo/frase, repite el nombre.
Paso 4. NO incluyas palabras cotidianas comunes.

REGLAS ESTRICTAS SOBRE SPOILERS:
- ABSOLUTAMENTE NINGUNA información posterior al progreso de lectura actual. Detente exactamente en la marca del %d%%.
- Las descripciones deben reflejar el estado de los personajes en este punto exacto del libro.

REGLAS ESTRICTAS SOBRE LA FUENTE DE CONOCIMIENTO (CRÍTICO):
- Para PERSONAJES FICTICIOS: Tus descripciones DEBEN basarse ÚNICAMENTE en lo que se indica explícitamente o se implica claramente en el texto proporcionado. NO complementes con conocimientos de entrenamiento previo, fuentes externas o conocimiento general del libro/serie/autor.
- Si un personaje solo ha sido mencionado brevemente en el texto hasta ahora, tu descripción debe reflejar únicamente esa información limitada. NO infieras, asumas ni añadas ningún detalle que no esté fundamentado en el contexto proporcionado.
- La ÚNICA excepción es para FIGURAS HISTÓRICAS REALES (ubicadas en `historical_figures`): puedes usar tu conocimiento interno para su biografía/rol general, pero aun así DEBES basarte en el texto del libro para su `context_in_book`.

REGLAS ESTRICTAS DE SEGURIDAD JSON:
- DEBES escapar adecuadamente todas las comillas dobles (\") dentro de las cadenas.
- NO uses saltos de línea sin escapar dentro de las cadenas.
- Genera ÚNICAMENTE un JSON válido y procesable.

FORMATO JSON REQUERIDO:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Nombre formal completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Etiqueta corta de arquetipo (3-5 palabras, p. ej. 'Antagonista', 'Protagonista', 'La víctima')",
      "gender": "Masculino / Femenino / Desconocido",
      "occupation": "Trabajo/Estado",
      "description": "Descripción basada ESTRICTAMENTE en el texto proporcionado. No infieras ni añadas conocimiento externo. SIN SPOILERS. (Máx {MAX_CHAR_DESC} caracteres)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nombre de la persona histórica real",
      "role": "Rol histórico",
      "biography": "Biografía corta (MÁX {MAX_HIST_BIO} caracteres)",
      "importance_in_book": "Importancia hasta el progreso actual",
      "context_in_book": "Cómo se mencionan (MÁX 100 caracteres)"
    }
  ],
  "locations": [
    {"name": "Nombre del lugar", "description": "Descripción corta (MÁX {MAX_LOC_DESC} caracteres)"}
  ],
  "terms": [
    {
      "name": "Término o acrónimo",
      "expanded": "Expansión completa o igual al nombre",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Definición concisa en contexto (MÁX {MAX_TERM_DEF} caracteres)"
    }
  ],
  "timeline": [
    {
      "chapter": "Título exacto del capítulo de las muestras",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Libro: %s
Autor: %s
Progreso de lectura: %d%%

TAREA: Extrae EXACTAMENTE 10 personajes importantes ADICIONALES del texto.
Devuelve ÚNICAMENTE un objeto JSON válido.

MANDATO DE BREVEDAD (CRÍTICO):
Para evitar el truncamiento de la respuesta de la IA, mantén las descripciones de los personajes por debajo de los {MAX_CHAR_DESC} caracteres.

INSTRUCCIÓN CRÍTICA:
NO incluyas ninguno de los siguientes personajes, ya que ya han sido extraídos:
%s

REGLAS ESTRICTAS SOBRE SPOILERS:
- ABSOLUTAMENTE NINGUNA información posterior al progreso de lectura actual. Detente exactamente en la marca del %d%%.
- Las descripciones deben reflejar el estado de los personajes en este punto exacto del libro.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nombre Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Papel hasta el progreso actual",
      "gender": "Masculino / Femenino / Desconocido",
      "occupation": "Trabajo/Estado",
      "description": "Descripción basada ESTRICTAMENTE en el texto proporcionado. No infieras ni añadas conocimientos externos. SIN SPOILERS. (Máx {MAX_CHAR_DESC} caracteres)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Libro: %s
Autor: %s
Progreso de lectura: %d%%

TAREA: Extrae EXACTAMENTE 15 términos, acrónimos, jerga o conceptos significativos ADICIONALES del texto.
- Si este libro es de no ficción: extrae términos técnicos, conceptos, acrónimos o jerga.
- Si este libro es de ficción: extrae elementos de construcción de mundos como facciones, organizaciones, sistemas de magia, tecnologías, criaturas, idiomas o lore del universo.
Devuelve ÚNICAMENTE un objeto JSON válido.

MANDATO DE BREVEDAD (CRÍTICO):
Para evitar el truncamiento de la respuesta de la IA, mantén las definiciones de los términos por debajo de {MAX_TERM_DEF} caracteres.

INSTRUCCIÓN CRÍTICA:
NO incluyas ninguno de los siguientes términos, ya que ya han sido extraídos:
%s

REGLAS ESTRICTAS SOBRE SPOILERS:
- ABSOLUTAMENTE NINGUNA información posterior al progreso de lectura actual. Detente exactamente en la marca del %d%%.

FORMATO JSON REQUERIDO:
{
  "terms": [
    {
      "name": "Término o Acrónimo",
      "expanded": "Expansión completa o igual al nombre",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Definición concisa en contexto (MÁX {MAX_TERM_DEF} caracteres)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
El usuario ha resaltado la palabra "%s".
TAREA: Determine si esta palabra es un Personaje, Lugar, Figura Histórica o Término Técnico/Acrónimo en el libro.
 
CRÍTICO PARA PERSONAJES Y UBICACIONES: Usa ÚNICAMENTE el "BOOK TEXT CONTEXT" proporcionado. El conocimiento externo está estrictamente prohibido. No alucines.
CRÍTICO PARA PERSONAJES DE FICCIÓN: Describe ÚNICAMENTE lo que revela el texto del libro proporcionado. NO uses conocimiento previo de tu entrenamiento sobre este personaje, incluso si lo reconoces de una serie conocida. Si el texto solo menciona brevemente a este personaje, tu descripción debe reflejar esa información limitada.
CRÍTICO PARA FIGURAS HISTÓRICAS: PUEDES usar tu conocimiento interno para verificar su identidad y proporcionar su biografía/papel, SOLO si son una figura histórica real y notable. AÚN ASÍ DEBES usar el contexto del texto para su relevancia en el libro.
CRITICAL FOR TERMS: Si el libro es de no ficción, verifica si la palabra es un término técnico, un acrónimo o un concepto clave. Proporciona su definición en el contexto.
Si la palabra NO es un personaje, lugar, figura histórica o término técnico en el texto, establezca `is_valid` en false.
 
FORMATO JSON REQUERIDO:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nombre completo",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Papel",
    "gender": "Masculino/Femenino/Desconocido",
    "occupation": "Ocupación",
    "description": "Breve descripción (máx. 250 caracteres)"
  },
  "error_message": ""
}
 
Nota: si el tipo es "location", el elemento debe tener "name" and "description". Si el tipo es "historical_figure", el elemento debe tener "name", "biography" y "role". Si el tipo es "term", el elemento debe tener "name", "expanded", "category" y "definition".
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Breve explicación de por qué esto no es un personaje ni un lugar."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
TAREA: Combine las siguientes dos descripciones de la misma entidad (personaje o ubicación) en un solo resumen cohesivo y conciso.
Elimine la información redundante y asegúrese de que la descripción final fluya de forma natural.

Descripción principal: %s
Descripción secundaria: %s

FORMATO JSON REQUERIDO:
{
  "merged_description": "Descripción combinada y pulida (Máx. {MAX_CHAR_DESC} caracteres)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Título del libro: %s
Autor: %s
Serie: %s
Descripción del archivo/Metadatos del asunto: %s

TAREA: Clasifica este libro en EXACTAMENTE UNO de estos tipos de libros según sus metadatos y señales de género:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Devuelve ÚNICAMENTE un JSON válido:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Título del libro: %s
Autor: %s

TAREA: Determine si este libro es parte de una serie nombrada.
Devuelva SOLAMENTE JSON válido:
{
  "is_series": true,
  "series_name": "La Rueda del Tiempo",
  "book_index": 3,
  "total_books_known": 14
}
Si este NO es un libro de serie, devuelva:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Serie: %s
Índice del libro actual: %d
Título del libro actual: %s

TAREA: Enumere los títulos (y autores si son diferentes de "%s") de los libros del 1 al %d
que vienen ANTES del libro actual en esta serie.
Devuelva SOLAMENTE JSON válido:
{
  "prior_books": [
    { "index": 1, "title": "El Ojo del Mundo", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
LIBRO OBJETIVO: %s
AUTOR: %s
ÍNDICE DEL LIBRO OBJETIVO: %d
SERIE: %s

TAREA:
Proporcionar un resumen COMPLETO únicamente del LIBRO OBJETIVO, para un lector que ha terminado el LIBRO OBJETIVO y está a punto de comenzar el siguiente libro de la serie.

LÍMITE ABSOLUTO DE SPOILERS:
El punto de corte del conocimiento es estrictamente la ÚLTIMA PÁGINA del LIBRO OBJETIVO (Índice del libro %d).
Puede incluir hechos establecidos en el LIBRO OBJETIVO o en libros anteriores de esta serie.
NO DEBE incluir, dar a entender, sugerir, presagiar o seleccionar detalles utilizando conocimientos de ningún libro posterior.

INFORMACIÓN PROHIBIDA DE LIBROS POSTERIORES:
- Eventos posteriores, destinos futuros, muertes, supervivencias, destinos, romances, alianzas, conflictos o traiciones.
- Identidades de libros posteriores, orígenes verdaderos, parentesco secreto, alias, álter egos, reencarnaciones, transformaciones, títulos o avances de poder (por ejemplo, NO mencione si una esencia se une a otra o renace en un libro futuro).
- Revelaciones, confirmaciones, reinterpretaciones, giros o terminología de construcción de mundo introducida en libros posteriores.
- Presagios retrospectivos o frases como "más tarde", "eventualmente", "se convertirá", "en libros subsiguientes" o equivalentes.
- Mencionar personajes, conceptos, organizaciones o cronología de libros posteriores.

LÍMITE DE PERSONAJE:
Describa a cada personaje estrictamente como se conoce en la página final del LIBRO OBJETIVO.
NO utilice alias, roles, relaciones, identidades verdaderas o estados revelados en libros posteriores.

REGLA DE INCERTIDUMBRE:
Si no puede determinar con confianza si un hecho o alias se estableció al final del LIBRO OBJETIVO, OMÍTALO.
Es preferible la falta de detalles a un spoiler de un libro futuro.

AUDITORÍA FINAL:
Antes de devolver el JSON, inspeccione cada campo (especialmente las descripciones de personajes y los alias) y elimine cualquier cosa que dependa del conocimiento de los libros posteriores al LIBRO OBJETIVO.

FORMATO JSON REQUERIDO:
{
  "characters": [
    { "name": "Nombre completo", "aliases": [], "role": "...", "description": "Estado al final de este libro (máx. {MAX_CHAR_DESC} caracteres)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Resumen del libro", "event": "Un resumen único, muy detallado y completo de toda la trama del libro, los eventos principales y la resolución (máx. 2000 caracteres). DEBE formatear este resumen utilizando varios párrafos distintos separados por saltos de línea dobles (\\n\\n) para facilitar la lectura en lugar de un único bloque de texto." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
LIBRO OBJETIVO: %s
AUTOR: %s
ÍNDICE DEL LIBRO OBJETIVO: %d
SERIE: %s

TAREA:
Utilizando ÚNICAMENTE los eventos verificados capítulo por capítulo proporcionados a continuación de LIBRO OBJETIVO, escribe un resumen cohesivo y exhaustivo de toda la trama del libro, los acontecimientos clave y su resolución.

RESTRICCIÓN ESTRICTA DE FUNDAMENTACIÓN:
- Basa tu resumen EXCLUSIVAMENTE en los eventos de los capítulos proporcionados.
- NO introduzcas hechos, personajes, eventos o resultados que no se describan en estos eventos de los capítulos.
- NUNCA menciones ni anticipes eventos, muertes o acontecimientos de libros posteriores de la serie.

EVENTOS DE LOS CAPÍTULOS:
%s

FORMATO JSON REQUERIDO:
{
  "timeline": [
    { "chapter": "Resumen del libro", "event": "Un único resumen altamente detallado y exhaustivo de toda la trama y resolución del libro (máximo 2000 caracteres). DEBES dar formato a este resumen utilizando varios párrafos distintos separados por dobles saltos de línea (\\n\\n) para facilitar la lectura en lugar de un único bloque de texto." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Libro: %s
Autor: %s
Analizando capítulo: %s

TAREA: Analiza ÚNICAMENTE este capítulo. Identifica NUEVAS entidades presentadas en este capítulo y ACTUALIZACIONES DE DELTA (transiciones de estado) para entidades existentes.
Genera ÚNICAMENTE un objeto JSON válido.

MANIFIESTO DE ENTIDADES CONOCIDAS EXISTENTES (NO las vuelvas a extraer a menos que su función, estado o descripción hayan evolucionado significativamente):
%s

REGLAS:
1. CONFINAMIENTO ESTRICTO DE SPOILERS: Analiza ÚNICAMENTE el texto del capítulo proporcionado. NO utilices ningún conocimiento de capítulos futuros ni de fuentes externas.
2. PROFUNDIDAD Y SUSTANCIA EN LA DESCRIPCIÓN DE PERSONAJES (CRÍTICO):
   - Fundamentada y específica: Describe quién es el personaje con hechos concretos de la historia: sus antecedentes, personalidad distintiva, profesión, relaciones clave con otros personajes y su función específica e intereses personales en la narrativa.
   - Contexto narrativo significativo: Conecta al personaje directamente con el misterio central, el conflicto de la trama o la investigación en este libro (por ejemplo, qué crímenes o casos están investigando, quién los contrató, aliados o adversarios clave, dilemas personales o tensiones específicas).
   - NO ser excesivamente general: NO escribas descripciones genéricas basadas en arquetipos (por ejemplo, evita frases vacías como "un detective que investiga casos complejos"). Nombra las circunstancias específicas, las conexiones y los intereses establecidos en el texto.
   - SIN resúmenes de tareas triviales: NO escribas registros cronológicos de actividades cotidianas mundanas o tareas rutinarias (por ejemplo, NO resumas viajes al supermercado, llamadas telefónicas rutinarias o movimientos incidentales escena por escena).
   - Las descripciones de los personajes deben ser perfiles ricos y vívidos que resuman quiénes son y su importancia hasta este punto del libro.
3. UMBRAL ALTO PARA ACTUALIZACIONES DE PERSONAJES:
   - NO crees una actualización en `character_state_updates` simplemente porque un personaje existente apareció, habló o realizó acciones rutinarias en este capítulo.
   - SOLO genera una actualización si hay una transformación sustancial y duradera en su arco narrativo, identidad, relaciones, empleo, lealtad o condición (por ejemplo: muere, resulta herido, es arrestado, traicionado, se compromete, es ascendido, se revela que es el culpable, o se descubre un secreto o motivo importante).
   - Si una actualización ESTÁ justificada, la `description` actualizada debe ser una visión general rica y acumulativa del personaje que incorpore los nuevos desarrollos mientras mantiene su identidad principal y el contexto de la historia establecido; NO un resumen de una escena aislada.
4. MARCADORES DE PÁGINA DENTRO DEL CAPÍTULO ([PAGE N]) Y FILTRADO DE CERO SPOILERS:
   - Los textos del capítulo contienen marcadores [PAGE N] que indican el progreso de las páginas.
   - Para `new_characters`, `new_locations` y `new_terms`: proporciona "first_page" (número entero N del marcador [PAGE N] donde se menciona por primera vez), "intro_role" (para personajes) e "intro_description" (1-2 oraciones estrictamente limitadas a lo que se sabe en su primera mención en [PAGE first_page], con CERO conocimiento de giros, secretos o resultados posteriores que ocurran en páginas siguientes). También proporciona "page" (el marcador [PAGE N] donde se aplica la "description" acumulativa más completa, normalmente la página final del capítulo).
   - Para `character_state_updates`, `location_state_updates` y `term_state_updates`: proporciona "page" (número entero N del marcador [PAGE N] donde se completa la revelación/transición; NO reveles hechos antes de esta página).
5. EVIDENCIA: Proporciona una breve referencia o fragmento de cita de este capítulo que explique por qué ocurrió la actualización.
6. CRONOLOGÍA (TIMELINE): Proporciona exactamente un resumen del evento de las principales acciones de la trama en este capítulo.

FORMATO JSON REQUERIDO:
{
  "new_characters": [
    {
      "name": "Nombre completo",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Función inicial (p. ej., empleado del pueblo, extraño, cliente)",
      "intro_description": "Impresión inicial de 1 a 2 oraciones estrictamente en la primera mención, cero spoilers de páginas posteriores.",
      "page": 99,
      "role": "Función narrativa / importancia (p. ej., protagonista, investigador privado, socio, antagonista, víctima, cliente, sospechoso, personaje secundario, personaje menor)",
      "status": "vivo",
      "description": "Descripción rica y específica del personaje (antecedentes, relaciones, intereses narrativos). Evita textos genéricos y registros de tareas triviales.",
      "evidence": "Fragmento corto"
    }
  ],
  "character_state_updates": [
    {
      "name": "Nombre que coincida con el manifiesto conocido",
      "page": 95,
      "role": "Función narrativa / importancia actualizada (p. ej., protagonista, socio, antagonista, personaje secundario, etc.)",
      "status": "vivo",
      "change": "Una oración corta que indique qué cambió desde el estado anterior (p. ej., 'Ascendido a socio tras el caso Shacklewell')",
      "description": "Descripción rica y acumulativa del personaje actualizada que refleje su nuevo estado e intereses en la historia",
      "evidence": "Fragmento corto"
    }
  ],
  "new_locations": [
    {
      "name": "Nombre de la ubicación",
      "first_page": 80,
      "intro_description": "Impresión inicial en la primera mención.",
      "page": 99,
      "description": "Descripción de la ubicación",
      "evidence": "Fragmento corto"
    }
  ],
  "location_state_updates": [
    {
      "name": "Nombre que coincida con el manifiesto conocido",
      "page": 95,
      "change": "Una oración corta que nombre qué cambió (p. ej., 'Destruido durante la batalla de Oakhaven')",
      "description": "Descripción evolucionada actualizada",
      "evidence": "Fragmento corto"
    }
  ],
  "new_terms": [
    {
      "name": "Nombre del término",
      "first_page": 80,
      "intro_description": "Definición inicial en la primera mención.",
      "page": 99,
      "description": "Definición o explicación de trasfondo (lore)",
      "evidence": "Fragmento corto"
    }
  ],
  "term_state_updates": [
    {
      "name": "Nombre que coincida con el manifiesto conocido",
      "page": 95,
      "change": "Una oración corta que nombre qué cambió en la comprensión o el uso",
      "description": "Definición actualizada",
      "evidence": "Fragmento corto"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Resumen de los eventos de este capítulo"
  }
}

TEXTO DEL CAPÍTULO:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Libro: %s
Autor: %s
Capítulos en este lote: %s

TAREA: Analice el lote secuencial de capítulos proporcionado en orden.
Para CADA capítulo del lote, identifique:
1. NUEVAS entidades introducidas en ese capítulo (personajes, ubicaciones, términos).
2. ACTUALIZACIONES DELTA (transiciones de estado) para entidades conocidas existentes (del manifiesto O introducidas en un capítulo anterior de este lote) SI Y SOLO SI su rol, estado, lealtad o condición narrativa experimentaron una transformación sustancial y duradera.
3. EVENTO DE LA CRONOLOGÍA: Un resumen conciso de los eventos principales de la trama que ocurren en ese capítulo.

Genere ÚNICAMENTE un objeto JSON válido que coincida con el esquema requerido.

MANIFIESTO DE ENTIDADES CONOCIDAS EXISTENTES (de lotes anteriores - NO las extraiga de nuevo a menos que su rol, estado o descripción hayan evolucionado significativamente):
%s

REGLAS:
1. CONFINAMIENTO ESTRICTO DE SPOILERS Y PROGRESIÓN SECUENCIAL:
   - Analice los capítulos en orden secuencial.
   - Para cualquier capítulo de este lote, NO incorpore conocimientos de capítulos posteriores del lote ni del resto del libro.
2. PROFUNDIDAD Y SUSTANCIA DE LA DESCRIPCIÓN DEL PERSONAJE (CRÍTICO):
   - Basado en hechos y específico: Describa quién es el personaje con hechos concretos de la historia: sus antecedentes, personalidad distintiva, profesión, relaciones clave con otros personajes y su rol específico y lo que está en juego para ellos en la narrativa.
   - Contexto narrativo significativo: Conecte al personaje directamente con el misterio central, el conflicto de la trama o la investigación de este libro (p. ej., qué crímenes o casos están investigando, quién los contrató, aliados o adversarios clave, dilemas o tensiones personales específicas).
   - NO ser excesivamente general: NO escriba descripciones genéricas de tropos (p. ej., evite frases vacías como "un detective que investiga casos complejos"). Mencione las circunstancias específicas, las conexiones y lo que está en juego según se establece en el texto.
   - NO incluir resúmenes de tareas triviales: NO escriba registros cronológicos de actividades cotidianas mundanas o tareas rutinarias (p. ej., NO resuma viajes al supermercado, llamadas telefónicas de rutina o movimientos incidentales escena por escena).
   - Las descripciones de los personajes deben ser perfiles ricos y vívidos que resuman quiénes son y su importancia hasta este punto del libro.
3. UMBRAL ALTO PARA ACTUALIZACIONES DE PERSONAJES:
   - NO cree una actualización en `character_state_updates` simplemente porque un personaje existente apareció, habló o realizó acciones rutinarias en un capítulo.
   - SOLO genere una actualización si hay una transformación sustancial y duradera en su arco narrativo, identidad, relaciones, empleo, lealtad o condición (p. ej., murió, resultó herido, arrestado, traicionado, comprometido, ascendido, se reveló que era el culpable, se descubrió un secreto o motivo importante).
   - Si una actualización ESTÁ justificada, la `description` actualizada debe ser una visión general rica y acumulativa del personaje que incorpore los nuevos desarrollos mientras mantiene su identidad principal y el contexto de la historia establecido, NO un resumen de una escena aislada.
4. MARCADORES DE PÁGINA DENTRO DEL CAPÍTULO ([PAGE N]) Y FILTRADO DE CERO SPOILERS:
   - Los textos de los capítulos contienen marcadores [PAGE N] que indican la progresión de la página.
   - Para `new_characters`, `new_locations` y `new_terms`: proporcione "first_page" (número entero N del marcador [PAGE N] donde se menciona por primera vez), "intro_role" (para personajes) e "intro_description" (1-2 oraciones estrictamente limitadas a lo que se conoce en su primera introducción en [PAGE first_page], con CERO conocimiento de giros, secretos o resultados posteriores que ocurran en páginas posteriores). También proporcione "page" (el marcador [PAGE N] donde se aplica la "description" acumulativa más completa, generalmente la última página del capítulo).
   - Para `character_state_updates`, `location_state_updates` y `term_state_updates`: proporcione "page" (número entero N del marcador [PAGE N] donde se completa la revelación/transición; NO revele hechos antes de esta página).
5. EVIDENCIA: Proporcione una breve referencia o fragmento de cita de ese capítulo específico que explique por qué ocurrió la actualización.
6. SEGURIDAD DE JSON: Genere estrictamente JSON válido. Escape adecuadamente las comillas dobles dentro de las cadenas.

FORMATO JSON REQUERIDO:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Título del capítulo",
      "timeline_event": "Resumen de los principales desarrollos de la trama en este capítulo.",
      "new_characters": [
        {
          "name": "Nombre completo",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Rol inicial (p. ej., Secretario del pueblo, Desconocido, Cliente)",
          "intro_description": "Impresión inicial de 1-2 oraciones estrictamente en la primera introducción, cero spoilers de páginas posteriores.",
          "page": 99,
          "role": "Rol narrativo / importancia (p. ej., Protagonista, Investigador privado, Socio, Antagonista, Víctima, Cliente, Sospechoso, Personaje secundario, Personaje menor)",
          "status": "vivo",
          "description": "Descripción rica y específica del personaje (antecedentes, relaciones, lo que está en juego en la narrativa). Evite descripciones genéricas y registros de tareas triviales.",
          "evidence": "Breve fragmento"
        }
      ],
      "character_state_updates": [
        {
          "name": "Nombre que coincida con el manifiesto conocido o personaje introducido en un capítulo anterior de este lote",
          "page": 95,
          "role": "Rol narrativo / importancia actualizado (p. ej., Protagonista, Socio, Antagonista, Personaje secundario, etc.)",
          "status": "vivo",
          "change": "Una oración corta que mencione qué cambió desde el estado anterior (p. ej., 'Ascendido a socio después del caso Shacklewell')",
          "description": "Descripción de personaje rica y acumulativa actualizada que refleje su nuevo estado y lo que está en juego en la historia",
          "evidence": "Breve fragmento"
        }
      ],
      "new_locations": [
        {
          "name": "Nombre de la ubicación",
          "first_page": 80,
          "intro_description": "Impresión inicial en la primera mención.",
          "page": 99,
          "description": "Descripción de la ubicación",
          "evidence": "Breve fragmento"
        }
      ],
      "location_state_updates": [
        {
          "name": "Nombre que coincida con el manifiesto conocido o ubicación introducida en un capítulo anterior de este lote",
          "page": 95,
          "change": "Una oración corta que mencione qué cambió (p. ej., 'Destruido durante la batalla de Oakhaven')",
          "description": "Descripción actualizada",
          "evidence": "Breve fragmento"
        }
      ],
      "new_terms": [
        {
          "name": "Nombre del término",
          "first_page": 80,
          "intro_description": "Definición inicial en la primera mención.",
          "page": 99,
          "description": "Definición o explicación del trasfondo",
          "evidence": "Breve fragmento"
        }
      ],
      "term_state_updates": [
        {
          "name": "Nombre que coincida con el manifiesto conocido o término introducido en un capítulo anterior de este lote",
          "page": 95,
          "change": "Una oración corta que mencione qué cambió en la comprensión o el uso",
          "description": "Definición actualizada",
          "evidence": "Breve fragmento"
        }
      ]
    }
  ]
}

TEXTOS DE CAPÍTULOS EN ESTE LOTE:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analiza los siguientes detalles del libro y el índice:

Título: %s
Autor: %s
Temas: %s
Descripción: %s

Índice:
%s

Determina si esta obra es:
1. "anthology" (una colección de cuentos, ensayos o novelas cortas independientes, cada uno con su propia narrativa o elenco autónomo, p. ej., "Las aventuras de Sherlock Holmes", "Dublineses", "Exhalación", "Hombres sin mujeres").
2. "novel" (una única novela unificada dividida en capítulos, partes o actos, p. ej., "Orgullo y prejuicio", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (una colección de varios volúmenes de novelas completas publicadas juntas en un solo volumen, p. ej., "El Señor de los Anillos: Los tres volúmenes", "Guía del autoestopista galáctico: La serie completa", "Percy Jackson: Libros 1-3").
4. "non_fiction" (un único tratado de no ficción, historia o libro académico dividido en capítulos).

Devuelve ÚNICAMENTE un objeto JSON con:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 a 1.0,
  "reasoning": "explicación breve (una oración)"
}]],

    -- System instruction
    system_instruction = "Eres un experto investigador literario. Tu respuesta debe estar ÚNICAMENTE en formato JSON válido. Asegúrate de que los datos sean altamente precisos y pertenezcan estrictamente al contexto proporcionado.",

    -- Fallback strings
    fallback = {
        no_biography = "Biografía no disponible",
        no_description = "Sin descripción",
        not_specified = "No especificado",
        unknown_author = "Autor desconocido",
        unknown_book = "Libro desconocido",
        unnamed_character = "Personaje sin nombre",
        unnamed_person = "Persona sin nombre"
    }
}
