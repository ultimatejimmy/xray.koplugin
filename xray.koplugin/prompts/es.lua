return {
    -- Instrucción del sistema
    system_instruction = "Eres un experto investigador literario. Tu respuesta debe estar ÚNICAMENTE en formato JSON válido. Asegúrate de que los datos sean altamente precisos y pertenezcan estrictamente al contexto proporcionado.",

    -- Mensaje solo para el autor (Para búsqueda rápida de biografía)
    author_only = [[Identifica y proporciona una biografía del autor del libro "%s". 
Los metadatos sugieren que el autor es "%s". 

CRÍTICO: Verifica el autor utilizando el CONTEXTO DEL TEXTO DEL LIBRO (si se proporciona al final de este mensaje) para garantizar el 100%% de precisión y evitar identificaciones incorrectas.

FORMATO JSON REQUERIDO:
{
  "author": "Nombre Completo Correcto",
  "author_bio": "Biografía exhaustiva centrada en su carrera literaria y obras principales.",
  "author_birth": "Fecha de nacimiento, formateada según el formato de fecha local",
  "author_death": "Fecha de fallecimiento, formateada según el formato de fecha local"
}]],

    -- Obtención integral única (Personajes, ubicaciones y línea de tiempo combinados)
    comprehensive_xray = [[Libro: %s
Autor: %s
Progreso de lectura: %d%%

TAREA: Realiza un análisis X-Ray completo. Devuelve ÚNICAMENTE un objeto JSON válido.

PARTICIÓN CRÍTICA DE ATENCIÓN:
Estás procesando un documento masivo con dos bloques de texto proporcionados al final de esta instrucción:
1. "CHAPTER SAMPLES" (Muestras de capítulos): Este es el macrocontexto del libro hasta la ubicación actual del lector.
2. "BOOK TEXT CONTEXT" (Contexto del texto del libro): Este es el microcontexto de los últimos 20,000 caracteres.

PROTOCOLO ANTI-TRUNCAMIENTO (CRÍTICO):
Tienes un límite máximo de salida estricto. Si las "CHAPTER SAMPLES" contienen MÁS DE 40 capítulos (ej. una edición ómnibus):
1. DEBES reducir la lista de personajes a ÚNICAMENTE los 10 personajes más importantes.
2. DEBES reducir las descripciones de los personajes a un MÁXIMO de {MAX_CHAR_DESC} caracteres.
3. DEBES reducir los resúmenes de eventos de la línea de tiempo a un MÁXIMO de {MAX_TIMELINE_EVENT} caracteres.
Si no comprimes tu salida para libros masivos, el JSON se truncará y fallará.

ALGORITMO PARA LA LÍNEA DE TIEMPO (MÁXIMA PRIORIDAD):
Para evitar saltar capítulos o alucinar eventos, DEBES ejecutar este bucle exacto:
Paso 1. Mira ÚNICAMENTE el bloque "CHAPTER SAMPLES". Identifica los capítulos narrativos.
Paso 2. EXCLUYE todo el material inicial y final no narrativo (ej., Portada, Página de título, Derechos de autor, Índice, Dedicatoria, Agradecimientos, También de).
Paso 3. Para cada capítulo narrativo, comenzando desde el primero, crea EXACTAMENTE UN objeto de evento en la matriz `timeline`.
Paso 4. El campo `chapter` DEBE coincidir exactamente con el encabezado del capítulo en la muestra. (Mapéalos estrictamente en orden secuencial).
Paso 5. Resume ese capítulo específico en el campo `event` {TIMELINE_DETAIL_GUIDANCE} (MÁX {MAX_TIMELINE_EVENT} caracteres). NO agrupes capítulos.
Paso 6. SIN SPOILERS: Detente exactamente en la marca del %d%%. No incluyas eventos más allá de este progreso.

ALGORITMO PARA PERSONAJES Y FIGURAS HISTÓRICAS:
Paso 1. Extrae personajes importantes usando ambos bloques de texto. ({NUM_CHARS} normal, MÁXIMO 10 si es ómnibus).
Paso 2. DEBES usar sus nombres completos y formales (ej. "Abraham Van Helsing"). NO uses apodos informales como nombre principal.
Paso 3. Proporciona hasta 3 nombres alternativos, títulos o apodos por los que se conozca a este personaje en una matriz `aliases`. Incluye su nombre y apellido comunes si se usan. IMPORTANTE: Si un apellido es compartido por varios personajes (ej., miembros de la familia), NO lo incluyas como alias para ninguno de ellos.
Paso 4. Busca activamente hasta {NUM_HIST} personas REALES NOTABLES de la historia humana (ej., Presidentes, Autores, Generales). Añádelos a `historical_figures`.
CRÍTICO para Personajes y Figuras Históricas:
- NO extraigas personajes o figuras históricas mencionadas ÚNICAMENTE en material no narrativo inicial o final (ej., Agradecimientos, Biografía del autor, Dedicatorias, Página de título, Derechos de autor).
- Las Figuras Históricas DEBEN ser personas reales del mundo real con reconocimiento histórico generalizado.
- NO incluyas personajes puramente ficticios en la lista de figuras históricas, incluso si interactúan con eventos históricos reales. Los personajes ficticios DEBEN ir en la matriz `characters`.
- ÚNICAMENTE para las Figuras Históricas, puedes usar tu conocimiento interno para escribir su `biography` general y su `role` histórico, pero DEBES usar el contexto del libro para su `context_in_book`.
SIN SPOILERS: Detente exactamente en la marca del %d%%.

ALGORITMO PARA UBICACIONES:
Paso 1. Extrae de {NUM_LOCS} ubicaciones significativas. SIN SPOILERS: Detente exactamente en la marca del %d%%.

ALGORITMO PARA TÉRMINOS:
Paso 0. Declara "book_type" como "fiction" o "non_fiction" en la raíz del JSON.
Paso 1. Si non_fiction: extrae {NUM_TERMS} términos técnicos, acrónimos, jerga o conceptos importantes que los lectores probablemente no conocerían sin conocimientos especializados. Usa categorías apropiadas como Acronym, Technical Term, Concept, o Jargon.
Paso 2. Si fiction: extrae {NUM_TERMS} elementos significativos de la construcción del mundo que un nuevo lector necesitaría que se le explicaran, como facciones inventadas, organizaciones, sistemas de magia, tecnologías, criaturas, idiomas o lore del universo.
   - NO incluyas nombres de personajes ni nombres de ubicaciones (se rastrean por separado).
   - NO extraigas palabras o conceptos comunes del mundo real.
   - Usa categorías apropiadas: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Paso 3. Incluye lo que significa el acrónimo/frase en "expanded". Si no es un acrónimo/frase, repite el nombre.
Paso 4. NO incluyas palabras comunes de todos los días.

REGLAS ESTRICTAS SOBRE SPOILERS:
- ABSOLUTAMENTE NINGUNA información posterior al progreso de lectura actual. Detente exactamente en la marca del %d%%.
- Las descripciones deben reflejar el estado de los personajes en este punto exacto del libro.

REGLAS ESTRICTAS SOBRE FUENTES DE CONOCIMIENTO (CRÍTICO):
- PARA PERSONAJES DE FICCIÓN: Tus descripciones DEBEN basarse ÚNICAMENTE en lo que está explícitamente indicado o claramente implícito en el texto proporcionado. NO complementes con conocimientos de entrenamientos previos, fuentes externas o conocimiento general del libro/serie/autor.
- Si un personaje solo ha sido mencionado brevemente en el texto hasta ahora, tu descripción debe reflejar únicamente esa información limitada. NO infieras, asumas ni añadas ningún detalle que no esté respaldado por el contexto proporcionado.
- La ÚNICA excepción es para FIGURAS HISTÓRICAS REALES (colocadas en `historical_figures`): puedes usar el conocimiento interno para su biografía/papel general, pero debes seguir dependiendo del texto del libro para su `context_in_book`.

REGLAS ESTRICTAS DE SEGURIDAD JSON:
- DEBES escapar correctamente todas las comillas dobles (\") dentro de las cadenas.
- NO uses saltos de línea sin escapar dentro de las cadenas.
- Genera ÚNICAMENTE JSON válido y analizable.

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
  ],
  "historical_figures": [
    {
      "name": "Nombre de la Persona Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografía breve (MÁX {MAX_HIST_BIO} caracteres)",
      "importance_in_book": "Significancia hasta el progreso actual",
      "context_in_book": "Cómo se mencionan (MÁX 100 caracteres)"
    }
  ],
  "locations": [
    {"name": "Nombre del Lugar", "description": "Descripción breve (MÁX {MAX_LOC_DESC} caracteres)"}
  ],
  "terms": [
    {
      "name": "Término o Acrónimo",
      "expanded": "Expansión completa o igual al nombre",
      "category": "Acrónimo / Término Técnico / Concepto / Jerga",
      "definition": "Definición concisa en contexto (MÁX {MAX_TERM_DEF} caracteres)"
    }
  ],
  "timeline": [
    {
      "chapter": "Título exacto del capítulo de las muestras",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
} ]],

    -- Obtención de más personajes (Bypass del límite de IA)
    more_characters = [[Libro: %s
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

    -- Obtención de más términos (Soporte para Glosario)
    more_terms = [[Libro: %s
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

    -- Targeted Single Word Lookup
    single_word_lookup = [[El usuario ha resaltado la palabra "%s".
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

    -- Multi-Book Series Context Prompts
    series_detect = [[Título del libro: %s
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

    prior_book_list = [[Serie: %s
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

    series_book_summary = [[Libro: %s
Autor: %s
Este es el libro %d de la serie "%s".

TAREA: Proporcione un resumen COMPLETO de todo este libro para un lector
que está A PUNTO DE COMENZAR el SIGUIENTE libro de la serie.
Incluya: personajes clave (nombre, función, estado final al final del libro), ubicaciones principales,
eventos críticos de la trama y términos importantes de construcción del mundo presentados.
SIN SPOILERS para libros MÁS ALLÁ de este.

FORMATO JSON REQUERIDO:
{
  "characters": [
    { "name": "Nombre completo", "aliases": [], "role": "...", "description": "Estado al final de este libro (máx. 300 caracteres)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Resumen del libro", "event": "Un resumen único, muy detallado y completo de la trama, los eventos principales y la resolución de todo el libro (máx. 2000 caracteres). DEBE formatear este resumen usando múltiples párrafos distintos separados por dos saltos de línea (\\n\\n) para mayor legibilidad en lugar de un único bloque de texto. You MUST format this recap using multiple distinct paragraphs separated by double newlines (\\n\\n) for readability instead of a single wall of text." }
  ]
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

-- Cadenas de respaldo
    fallback = {
        unknown_book = "Libro desconocido",
        unknown_author = "Autor desconocido",
        unnamed_character = "Personaje sin nombre",
        not_specified = "No especificado",
        no_description = "Sin descripción",
        unnamed_person = "Persona sin nombre",
        no_biography = "Biografía no disponible"
    }
}

