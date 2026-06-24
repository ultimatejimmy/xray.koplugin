return {
    -- Instrução do sistema
    system_instruction = "Você é um pesquisador literário especialista. Sua resposta deve estar APENAS no formato JSON válido. Certifique-se de que os dados sejam altamente precisos e pertençam estritamente ao contexto fornecido.",

    -- Mensagem apenas para o autor (Para busca rápida de biografia)
    author_only = [[Identifique e forneça a biografia do autor do livro "%s". 
Os metadatos sugerem que o autor é "%s". 
CRÍTICO: Verifique o autor usando o CONTEXTO DO TEXTO DO LIVRO (se fornecido no final desta mensagem) para garantir 100%% de precisão e evitar identificações incorretas.

FORMATO JSON REQUERIDO:
{
  "author": "Nome Completo Correto",
  "author_bio": "Biografia abrangente focada em sua carreira literária e principais obras.",
  "author_birth": "Data de nascimento, formatada de acordo com o formato de data local",
  "author_death": "Data de falecimento, formatada de acordo com o formato de data local"
}]],

    -- Busca Abrangente Única (Personagens, Locais e Cronologia combinados)
    comprehensive_xray = [[Livro: %s
Autor: %s
Progresso de Leitura: %d%%

TAREFA: Realize uma análise X-Ray completa. Retorne APENAS um objeto JSON válido.

PARTICIONAMENTO CRÍTICO DE ATENÇÃO:
Você está processando um documento massivo com dois blocos de texto fornecidos ao final desta instrução:
1. "CHAPTER SAMPLES" (Amostras de capítulos): Este é o macrocontexto do livro até a localização atual do leitor.
2. "BOOK TEXT CONTEXT" (Contexto do texto do livro): Este é o microcontexto dos últimos 20.000 caracteres.

PROTOCOLO ANTI-TRUNCAMENTO (CRÍTICO): Você tem um limite máximo de saída estrito. Se as "CHAPTER SAMPLES" contiverem MAIS DE 40 capítulos (ex: uma edição omnibus):
1. Você DEVE reduzir a lista de personagens para APENAS os 10 personagens mais importantes.
2. Você DEVE reduzir as descrições dos personagens para no MÁXIMO {MAX_CHAR_DESC} caracteres.
3. Você DEVE reduzir os resumos dos eventos da cronologia para no MÁXIMO {MAX_TIMELINE_EVENT} caracteres.
A falha em comprimir sua saída para livros massivos fará com que o JSON seja truncado e falhe.

ALGORITMO PARA CRONOLOGIA (PRIORIDADE MÁXIMA):
Para evitar pular capítulos ou alucinar eventos, você DEVE executar este loop exato:
Passo 1. Olhe APENAS para o bloco "CHAPTER SAMPLES". Identifique os capítulos narrativos.
Passo 2. EXCLUA todo o material pré-textual e pós-textual não narrativo (ex: Capa, Folha de Rosto, Direitos Autorais, Índice, Dedicatória, Agradecimentos, Também por).
Passo 3. Para cada capítulo narrativo, começando do primeiríssimo, crie EXATAMENTE UM objeto de evento no array `timeline`.
Passo 4. O campo `chapter` DEVE corresponder exatamente ao cabeçalho do capítulo na amostra. (Mapeie-os estritamente em ordem sequencial).
Passo 5. Resuma esse capítulo específico no campo `event` {TIMELINE_DETAIL_GUIDANCE} (MÁX {MAX_TIMELINE_EVENT} caracteres). NÃO agrupe capítulos.
Passo 6. SEM SPOILERS: Pare exatamente na marca de %d%%. Não inclua eventos após este progresso.

ALGORITMO PARA PERSONAGENS E FIGURAS HISTÓRICAS:
Passo 1. Extraia personagens importantes usando ambos os blocos de texto. ({NUM_CHARS} normal, no MÁXIMO 10 se for omnibus).
Passo 2. Você DEVE usar seus nomes completos e formais (ex: "Abraham Van Helsing"). NÃO use apelidos informais como o nome principal.
Passo 3. Forneça até 3 nomes alternativos, títulos ou apelidos pelos quais este personagem é conhecido em um array `aliases`. Inclua seu primeiro nome e sobrenome comuns se usados. IMPORTANTE: Se um sobrenome for compartilhado por vários personagens (ex: membros da família), NÃO o inclua como alias para nenhum dos personagens.
Step 4. Actively scan for up to {NUM_HIST} NOTABLE REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
SEM SPOILERS: Pare exatamente na marca de %d%%.

ALGORITMO PARA LOCAIS:
Passo 1. Extraia de {NUM_LOCS} locais significativos. SEM SPOILERS: Pare exatamente na marca de %d%%.

ALGORITMO PARA TERMOS E CONCEITOS:
Passo 0: No nó raiz do JSON, declare "book_type" como "fiction" ou "non_fiction".
Passo 1: Se o livro for de não ficção: Extraia {NUM_TERMS} termos técnicos, acrônimos, jargões ou conceitos importantes. Use categorias apropriadas como Acronym, Technical Term, Concept ou Jargon.
Passo 2: Se o livro for de ficção: Extraia {NUM_TERMS} elementos significativos de construção de mundo (World-building) que um novo leitor precisaria que fossem explicados – tais como facções inventadas, organizações, sistemas de magia, tecnologias, criaturas, idiomas ou lore do universo.
   - NÃO inclua nomes de personagens ou locais (esses são rastreados separadamente).
   - NÃO extraia palavras ou conceitos comuns do mundo real.
   - Use categorias apropriadas: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Passo 3: No campo "expanded", inclua a expansão completa para acrônimos/expressões. Se não for um acrônimo/expressão, repita o nome.
Passo 4: NÃO inclua palavras comuns do dia a dia.

REGRAS ESTRITAS DE SPOILER:
- ABSOLUTAMENTE NENHUMA informação após o progresso de leitura atual. Pare exatamente na marca de %d%%.
- As descrições devem refletir o estado dos personagens neste exato ponto do livro.

REGRAS ESTRITAS DE FONTE DE CONHECIMENTO (CRÍTICO):
- PARA PERSONAGENS DE FICÇÃO: Suas descrições DEVEM ser baseadas EXCLUSIVAMENTE no que está explicitamente declarado ou claramente implícito no texto fornecido. NÃO complemente com conhecimento de treinamentos anteriores, fontes externas ou conhecimento geral do livro/série/autor.
- Se um personagem foi apenas mencionado brevemente no texto até agora, sua descrição deve refletir apenas essa informação limitada. NÃO infira, assuma ou adicione qualquer detalhe não fundamentado no contexto fornecido.
- A ÚNICA exceção é para FIGURAS HISTÓRICAS REAIS (colocadas em `historical_figures`): você pode usar conhecimento interno para sua biografia/papel geral, mas ainda deve depender do texto do livro para seu `context_in_book`.

REGRAS ESTRITAS DE SEGURANÇA JSON:
- Você DEVE escapar corretamente todas as aspas duplas (\") dentro das strings.
- NÃO use quebras de linha não escapadas dentro das strings.
- Retorne APENAS um JSON válido e analisável.

FORMATO JSON REQUERIDO:
{
  "book_type": "non_fiction",
  "characters": [
    {
      "name": "Nome Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Papel até o progresso atual",
      "gender": "Masculino / Feminino / Desconhecido",
      "occupation": "Profissão/Status",
      "description": "Descrição baseada ESTRITAMENTE no texto fornecido. Não infira ou adicione conhecimento externo. SEM SPOILERS. (Máx {MAX_CHAR_DESC} caracteres)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nome da Pessoa Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografia curta (MÁX {MAX_HIST_BIO} caracteres)",
      "importance_in_book": "Significância até o progresso atual",
      "context_in_book": "Como são mencionados (MÁX 100 caracteres)"
    }
  ],
  "locations": [
    {"name": "Nome do Local", "description": "Descrição curta (MÁX {MAX_LOC_DESC} caracteres)"}
  ],
  "terms": [
    {
      "name": "Termo ou Acrônimo",
      "expanded": "Expansão completa ou igual ao nome",
      "category": "Acrônimo / Termo Técnico / Conceito / Jargão",
      "definition": "Definição concisa no contexto (MÁX {MAX_TERM_DEF} caracteres)"
    }
  ],
  "timeline": [
    {
      "chapter": "Título Exato do Capítulo das Amostras",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
} ]],

    -- Buscar mais personagens (Bypass do limite de IA)
    more_characters = [[Livro: %s
Autor: %s
Progresso de Leitura: %d%%

TAREFA: Extraia EXATAMENTE 10 personagens importantes ADICIONAIS do texto.
Retorne APENAS um objeto JSON válido.

MANDATO DE CONCISÃO (CRÍTICO):
Para evitar o truncamento da resposta da IA, mantenha as descrições dos personagens com menos de {MAX_CHAR_DESC} caracteres.

INSTRUÇÃO CRÍTICA:
NÃO inclua nenhum dos seguintes personagens, pois eles já foram extraídos:
%s

REGRAS ESTRITAS DE SPOILER:
- ABSOLUTAMENTE NENHUMA informação após o progresso de leitura atual. Pare exatamente na marca de %d%%.
- As descrições devem refletir o estado dos personagens neste exato ponto do livro.

FORMATO JSON REQUERIDO:
{
  "characters": [
    {
      "name": "Nome Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Papel até o progresso atual",
      "gender": "Masculino / Feminino / Desconhecido",
      "occupation": "Profissão/Status",
      "description": "Descrição baseada ESTRITAMENTE no texto fornecido. Não infira ou adicione conhecimento externo. SEM SPOILERS. (Máx {MAX_CHAR_DESC} caracteres)"
    }
  ]
}]],

    -- Buscar mais termos (Suporte para Glossário)
    more_terms = [[Livro: %s
Autor: %s
Progresso de Leitura: %d%%

TAREFA: Extraia EXATAMENTE 15 termos, acrônimos, jargões ou conceitos significativos ADICIONAIS do texto.
- Se este livro for de não ficção: extraia termos técnicos, conceitos, acrônimos ou jargões.
- Se este livro for de ficção: extraia elementos de construção de mundo (world-building) como facções, organizações, sistemas de magia, tecnologias, criaturas, idiomas ou lore do universo.
Retorne APENAS um objeto JSON válido.

MANDATO DE CONCISÃO (CRÍTICO):
Para evitar o truncamento da resposta da IA, mantenha as definições dos termos com menos de {MAX_TERM_DEF} caracteres.

INSTRUÇÃO CRÍTICA:
NÃO inclua nenhum dos seguintes termos, pois eles já foram extraídos:
%s

REGRAS ESTRITAS DE SPOILER:
- ABSOLUTAMENTE NENHUMA informação após o progresso de leitura atual. Pare exatamente na marca de %d%%.

FORMATO JSON REQUERIDO:
{
  "terms": [
    {
      "name": "Termo ou Acrônimo",
      "expanded": "Expansão completa ou igual ao nome",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acrônimo / Termo Técnico / Conceito / Jargão",
      "definition": "Definição concisa no contexto (MÁX {MAX_TERM_DEF} caracteres)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[O usuário destacou a palavra "%s".
TAREFA: Determine se esta palavra é um Personagem, Local, Figura Histórica ou Termo Técnico/Acrônimo no livro.
 
CRITICAL FOR CHARACTERS AND LOCATIONS: Use ONLY the provided "BOOK TEXT CONTEXT". Outside knowledge is strictly forbidden. Do not hallucinate.
CRÍTICO PARA PERSONAGENS DE FICÇÃO: Descreva APENAS o que o texto do livro fornecido revela. NÃO use conhecimento prévio do seu treinamento sobre este personagem, mesmo se você o reconhecer de uma série conhecida. Se o texto apenas menciona brevemente este personagem, sua descrição deve refletir essa informação limitada.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
CRITICAL FOR TERMS: Se o livro for de não ficção, verifique se a palavra é um termo técnico, um acrônimo ou um conceito-chave. Forneça sua definição no contexto.
Se a palavra NÃO for um personagem, local, figura histórica ou termo técnico no texto, defina `is_valid` como false.
 
FORMATO JSON OBRIGATÓRIO:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nome completo",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Papel",
    "gender": "Masculino/Feminino/Desconhecido",
    "occupation": "Ocupação",
    "description": "Breve descrição (máx. 250 caracteres)"
  },
  "error_message": ""
}
 
Nota: se o tipo for "location", o item deve ter "name" e "description". Se o tipo for "historical_figure", o item deve ter "name", "biography" e "role".
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Breve explicação de por que isso não é um personagem nem um local."
}
]],

    -- Strings de reserva (Fallback)
        -- Find Duplicates
    find_duplicates = [[
Livro: %s
Autor: %s
Progresso de leitura: %d%%

Você está revisando a seguinte lista de %s extraídos deste livro.
Sua tarefa é identificar quaisquer entradas que pareçam ser a MESMA entidade listada sob nomes diferentes.

LISTA:
%s

REGRAS:
- Um duplicado existe quando duas entradas se referem claramente à mesma entidade (por exemplo, "A Grande Biblioteca" e "Grande Biblioteca", ou "John" e "John Doe").
- NÃO marque entradas que sejam meramente relacionadas ou semelhantes, mas distintas.
- NÃO marque entradas a menos que tenha certeza absoluta de que são a mesma entidade.
- Se não existirem duplicatas, retorne um array vazio.
- REGRA DE SPOILER: Não use conhecimento além de %d%% de progresso de leitura.

FORMATO JSON EXIGIDO:
{
  "duplicate_pairs": [
    {
      "primary": "Nome da entrada a MANTER (o nome mais completo ou formal)",
      "secondary": "Nome da entrada a REMOVER",
      "reason": "Breve motivo (máx 100 caracteres)"
    }
  ]
}]],

    -- Merge Descriptions
    merge_descriptions = [[
TAREFA: Combine as seguintes duas descrições da mesma entidade (personagem ou local) em um resumo único, coeso e conciso.
Remova informações redundantes e garanta que a descrição final flua naturalmente.

Descrição principal: %s
Descrição secundária: %s

FORMATO JSON EXIGIDO:
{
  "merged_description": "Descrição combinada e polida (Máx {MAX_CHAR_DESC} caracteres)"
}]],

-- Multi-Book Series Context Prompts
    series_detect = [[Título do livro: %s
Autor: %s

TAREFA: Determine se este livro faz parte de uma série nomeada.
Retorne APENAS um JSON válido:
{
  "is_series": true,
  "series_name": "A Roda do Tempo",
  "book_index": 3,
  "total_books_known": 14
}
Se este NÃO for um livro de série, retorne:
{ "is_series": false }]],

    prior_book_list = [[Série: %s
Índice do livro atual: %d
Título do livro atual: %s

TAREFA: Liste os títulos (e autores se diferentes de "%s") dos livros de 1 a %d
que vêm ANTES do livro atual nesta série.
Retorne APENAS um JSON válido:
{
  "prior_books": [
    { "index": 1, "title": "O Olho do Mundo", "author": "Robert Jordan" }
  ]
}]],

    series_book_summary = [[Livro: %s
Autor: %s
Este é o livro %d da série "%s".

TAREFA: Forneça um resumo COMPLETO de todo este livro para um leitor
que está PRESTES A COMEÇAR o PRÓXIMO livro da série.
Inclua: personagens principais (nome, papel, estado final no fim do livro), locais principais,
eventos críticos da trama e termos importantes de construção de mundo introduzidos.
SEM SPOILERS para livros ALÉM deste.

FORMATO JSON EXIGIDO:
{
  "characters": [
    { "name": "Nome Completo", "aliases": [], "role": "...", "description": "Status no final deste livro (máx. 300 caracteres)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Resumo do Livro", "event": "Um resumo único, altamente detalhado e completo em vários parágrafos do enredo do livro inteiro, principais eventos e desfecho (máx. 2000 caracteres) You MUST format this recap using multiple distinct paragraphs separated by double newlines (\\n\\n) for readability instead of a single wall of text." }
  ]
}]],

    fallback = {
        unknown_book = "Livro Desconhecido",
        unknown_author = "Autor Desconhecido",
        unnamed_character = "Personagem Sem Nome",
        not_specified = "Não Especificado",
        no_description = "Sem Descrição",
        unnamed_person = "Pessoa Sem Nome",
        no_biography = "Biografia Não Disponível"
    }
}

