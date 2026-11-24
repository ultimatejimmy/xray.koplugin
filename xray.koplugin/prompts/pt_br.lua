return {
    -- Author Only
    author_only = [[
Identifique e forneça a biografia do autor do livro "%s". 
Os metadatos sugerem que o autor é "%s". 
CRÍTICO: Verifique o autor usando o CONTEXTO DO TEXTO DO LIVRO (se fornecido no final desta mensagem) para garantir 100%% de precisão e evitar identificações incorretas.

FORMATO JSON REQUERIDO:
{
  "author": "Nome Completo Correto",
  "author_bio": "Biografia abrangente focada em sua carreira literária e principais obras.",
  "author_birth": "Data de nascimento, formatada de acordo com o formato de data local",
  "author_death": "Data de falecimento, formatada de acordo com o formato de data local"
}]],

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

    -- Comprehensive Xray
    comprehensive_xray = [[
Livro: %s
Autor: %s
Progresso de Leitura: %d%%

TAREFA: Realize uma análise completa de X-Ray. Forneça APENAS um objeto JSON válido.

PARTICIONAMENTO CRÍTICO DE ATENÇÃO:
Você está processando um documento extenso com dois blocos de texto fornecidos ao final deste comando:
1. "CHAPTER SAMPLES": Este é o macro-contexto do livro até a localização atual do leitor.
2. "BOOK TEXT CONTEXT": Este é o micro-contexto dos 20 mil caracteres mais recentes.

PROTOCOLO ANTI-TRUNCAMENTO (CRÍTICO):
Você tem um limite máximo estrito de saída. Se o bloco "CHAPTER SAMPLES" contiver MAIS DE 40 capítulos (ex: uma edição completa/omnibus):
1. Você DEVE reduzir a lista de personagens para APENAS os 10 personagens absolutamente mais importantes.
2. Você DEVE reduzir as descrições dos personagens para no MÁXIMO {MAX_CHAR_DESC} caracteres.
3. Você DEVE reduzir os resumos dos eventos da linha do tempo para no MÁXIMO {MAX_TIMELINE_EVENT} caracteres.
A falha em compactar sua saída para livros volumosos fará com que o JSON seja truncado e falhe.

ALGORITMO PARA LINHA DO TEMPO (PRIORIDADE MÁXIMA):
Para evitar pular capítulos ou alucinar eventos, você DEVE executar exatamente este loop:
Passo 1. Analise APENAS o bloco "CHAPTER SAMPLES". Identifique os capítulos narrativos.
Passo 2. EXCLUA todos os elementos não narrativos iniciais e finais (ex: Capa, Folha de Rosto, Direitos Autorais, Sumário, Dedicatória, Agradecimentos, Outras Obras).
Passo 3. Para cada capítulo narrativo, começando pelo primeiríssimo, crie EXATAMENTE UM objeto de evento na matriz `timeline`.
Passo 4. O campo `chapter` DEVE corresponder exatamente ao cabeçalho do capítulo na amostra. (Mapeie-os rigorosamente em ordem sequencial).
Passo 5. Resuma esse capítulo específico no campo `event`. {TIMELINE_DETAIL_GUIDANCE} Escreva entre {MIN_TIMELINE_EVENT} e {MAX_TIMELINE_EVENT} caracteres. NÃO escreva um resumo mais curto, a menos que o capítulo quase não tenha conteúdo. NÃO agrupe capítulos.
Passo 6. SEM SPOILERS: Pare exatamente na marca de %d%%. Não inclua eventos após este progresso.

ALGORITMO PARA PERSONAGENS E FIGURAS HISTÓRICAS:
Passo 1. Extraia personagens importantes usando ambos os blocos de texto. ({NUM_CHARS} no normal, no MÁXIMO 10 se for edição completa). Sempre inclua o personagem principal / protagonista pelo nome, mesmo em narrativas em primeira pessoa ("eu"/"meu") onde o nome deles apareça raramente.
Passo 2. Você DEVE usar seus nomes COMPLETOS e formais (ex: "Abraham Van Helsing"). NÃO use apelidos informais como o nome principal. Nunca mescle ou subordine um personagem a uma referência possessiva/relacional (ex: "Pai de Nick" e "Nick" são personagens distintos).
Passo 3. Forneça até 3 nomes alternativos, títulos ou apelidos pelos quais este personagem é conhecido em uma matriz `aliases`. Inclua o nome e sobrenome comuns se usados. IMPORTANTE: Se um sobrenome for compartilhado por vários personagens (ex: familiares), NÃO o inclua como um alias para nenhum deles.
Passo 4. Procure ativamente por até {NUM_HIST} pessoas REAIS NOTÁVEIS da história humana (ex: Presidentes, Autores, Generais). Adicione-as a `historical_figures`.
CRÍTICO para Personagens e Figuras Históricas:
- NÃO extraia personagens ou figuras históricas mencionados APENAS em elementos não narrativos iniciais ou finais (ex: Agradecimentos, Biografia do Autor, Dedicatórias, Folha de Rosto, Direitos Autorais).
- Figuras Históricas DEVEM ser pessoas verificadas do mundo real com amplo reconhecimento histórico.
- NÃO inclua personagens puramente fictícios na lista de figuras históricas, mesmo que interajam com eventos históricos reais. Personagens fictícios DEVEM ir para a matriz `characters`.
- APENAS para Figuras Históricas, você pode usar seu conhecimento interno para escrever sua biografia geral (`biography`) e papel histórico (`role`), mas ainda DEVE usar o contexto do livro para `context_in_book`.
SEM SPOILERS: Pare exatamente na marca de %d%%.

ALGORITMO PARA LOCALIZAÇÕES:
Passo 1. Extraia {NUM_LOCS} localizações significativas. SEM SPOILERS: Pare exatamente na marca de %d%%.

ALGORITMO PARA TERMOS:
Passo 0. Declare "book_type" como "fiction", "non_fiction" ou "anthology" na raiz do JSON.
Passo 1. Se non_fiction: extraia {NUM_TERMS} termos técnicos significativos, acrônimos, jargões ou conceitos que os leitores não saberiam sem conhecimento especializado. Use categorias apropriadas como Acronym, Technical Term, Concept ou Jargon.
Passo 2. Se fiction ou anthology: extraia {NUM_TERMS} elementos significativos de construção de mundo que um novo leitor precisaria que fossem explicados — como facções inventadas, organizações, sistemas de magia, tecnologias, criaturas, idiomas ou folclore (lore) do universo.
   - NÃO inclua nomes de personagens ou nomes de localizações (esses são rastreados separadamente).
   - NÃO extraia palavras ou conceitos comuns do mundo real.
   - Use categorias apropriadas: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Passo 3. Inclua o significado do acrônimo/frase em "expanded". Se não for um acrônimo/frase, repita o nome.
Passo 4. NÃO inclua palavras comuns do dia a dia.

REGRAS ESTRITAS DE SPOILER:
- ABSOLUTAMENTE NENHUMA informação de após o progresso de leitura atual. Pare exatamente na marca de %d%%.
- As descrições devem refletir o estado dos personagens neste ponto exato do livro.

REGRAS ESTRITAS DE FONTE DE CONHECIMENTO (CRÍTICO):
- Para PERSONAGENS FICTÍCIOS: Suas descrições DEVEM ser baseadas EXCLUSIVAMENTE no que está explicitamente declarado ou claramente implícito no texto fornecido. NÃO complemente com conhecimento de treinamento prévio, fontes externas ou consciência geral do livro/série/autor.
- Se um personagem foi apenas brevemente mencionado no texto até agora, sua descrição deve refletir apenas essa informação limitada. NÃO infira, assuma ou adicione qualquer detalhe que não esteja fundamentado no contexto fornecido.
- A ÚNICA exceção é para FIGURAS HISTÓRICAS REAIS (colocadas em `historical_figures`): você pode usar conhecimento interno para sua biografia/papel geral, mas ainda DEVE confiar no texto do livro para `context_in_book`.

REGRAS ESTRITAS DE SEGURANÇA JSON:
- Você DEVE escapar adequadamente todas as aspas duplas (\") dentro das strings.
- NÃO use quebras de linha não escapadas dentro das strings.
- Produza APENAS um JSON válido e analisável.

FORMATO JSON OBRIGATÓRIO:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Nome Formal Completo",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rótulo curto de arquétipo (3-5 palavras, ex: 'Antagonista', 'Protagonista', 'A Vítima')",
      "gender": "Masculino / Feminino / Desconhecido",
      "occupation": "Profissão/Status",
      "description": "Descrição baseada ESTRITAMENTE no texto fornecido. Não infira ou adicione conhecimento externo. SEM SPOILERS. (Máx {MAX_CHAR_DESC} carac.)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nome da Pessoa Histórica Real",
      "role": "Papel Histórico",
      "biography": "Biografia curta (MÁX {MAX_HIST_BIO} carac.)",
      "importance_in_book": "Significância até o progresso atual",
      "context_in_book": "Como são mencionados (MÁX 100 carac.)"
    }
  ],
  "locations": [
    {"name": "Nome do Local", "description": "Desc. curta (MÁX {MAX_LOC_DESC} carac.)"}
  ],
  "terms": [
    {
      "name": "Termo ou Acrônimo",
      "expanded": "Extensão completa ou igual ao nome",
      "category": "Acrônimo / Termo Técnico / Conceito / Jargão",
      "definition": "Definição concisa no contexto (MÁX {MAX_TERM_DEF} carac.)"
    }
  ],
  "timeline": [
    {
      "chapter": "Título Exato do Capítulo das Amostras",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Livro: %s
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

    -- More Terms
    more_terms = [[
Livro: %s
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

    -- Single Word Lookup
    single_word_lookup = [[
O usuário destacou a palavra "%s".
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

    -- Book Type Detect
    book_type_detect = [[
Título do Livro: %s
Autor: %s
Série: %s
Descrição do Arquivo/Metadados de Assunto: %s

TAREFA: Classifique este livro em exatamente UM destes tipos de livro com base em seus metadados e sinais de gênero:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Retorne APENAS um JSON válido:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Título do livro: %s
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

    -- Prior Book List
    prior_book_list = [[
Série: %s
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

    -- Series Book Summary
    series_book_summary = [[
LIVRO ALVO: %s
AUTOR: %s
ÍNDICE DO LIVRO ALVO: %d
SÉRIE: %s

TAREFA:
Forneça um resumo COMPLETO apenas do LIVRO ALVO, para um leitor que terminou o
LIVRO ALVO e está prestes a começar o próximo livro da série.

LIMITE ABSOLUTO DE SPOILER:
O limite de conhecimento é rigorosamente a PÁGINA FINAL do LIVRO ALVO (Índice do Livro %d).
Você pode incluir fatos estabelecidos no LIVRO ALVO ou em livros anteriores desta série.
Você NÃO DEVE incluir, sugerir, dar pistas, prever ou selecionar detalhes usando conhecimento de qualquer livro posterior.

INFORMAÇÕES PROIBIDAS DE LIVROS POSTERIORES:
- Eventos posteriores, destinos futuros, mortes, sobrevivências, destinos, romances, alianças, conflitos ou traições.
- Identidades de livros posteriores, origens verdadeiras, parentesco secreto, pseudônimos, alter egos, reencarnações, transformações, títulos ou avanços de poder (ex: NÃO mencione se uma essência se junta a outra ou renasce em um livro futuro).
- Revelações, confirmações, reinterpretações, reviravoltas ou terminologia de construção de mundo introduzida em livros posteriores.
- Prenúncios retrospectivos ou frases como "mais tarde", "eventualmente", "se tornará", "em livros subsequentes" ou equivalente.
- Menção de personagens, conceitos, organizações ou cronologia de livros posteriores.

LIMITE DE PERSONAGEM:
Descreva cada personagem estritamente como conhecido na página final do LIVRO ALVO.
NÃO use pseudônimos, papéis, relacionamentos, identidades verdadeiras ou status revelados em livros posteriores.

REGRA DE INCERTEZA:
Se você não puder determinar com confiança se um fato ou pseudônimo foi estabelecido até o final do LIVRO ALVO, OMITA-O.
A ausência de detalhes é preferível a um spoiler de um livro futuro.

AUDITORIA FINAL:
Antes de retornar o JSON, inspecione cada campo (especialmente descrições de personagens e pseudônimos) e remova qualquer coisa que dependa de conhecimento de livros após o LIVRO ALVO.

FORMATO JSON OBRIGATÓRIO:
{
  "characters": [
    { "name": "Nome Completo", "aliases": [], "role": "...", "description": "Status ao final deste livro (máx {MAX_CHAR_DESC} caracteres)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Resumo do Livro", "event": "Um resumo único, altamente detalhado e abrangente de todo o enredo, principais eventos e resolução do livro (máx. 2000 caracteres). Você DEVE formatar este resumo usando vários parágrafos distintos separados por quebras de linha duplas (\\n\\n) para facilitar a leitura em vez de um bloco de texto único." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
LIVRO ALVO: %s
AUTOR: %s
ÍNDICE DO LIVRO ALVO: %d
SÉRIE: %s

TAREFA:
Usando APENAS os eventos verificados capítulo a capítulo fornecidos abaixo do LIVRO ALVO, escreva um resumo coeso e abrangente de todo o enredo, principais desenvolvimentos e resolução do livro.

RESTRIÇÃO ESTRITA DE FUNDAMENTAÇÃO:
- Fundamente seu resumo EXCLUSIVAMENTE nos eventos dos capítulos fornecidos.
- NÃO introduza fatos, personagens, eventos ou resultados não descritos nestes eventos de capítulo.
- NUNCA mencione ou antecipe eventos, mortes ou desenvolvimentos de livros posteriores da série.

EVENTOS DOS CAPÍTULOS:
%s

FORMATO JSON OBRIGATÓRIO:
{
  "timeline": [
    { "chapter": "Resumo do Livro", "event": "Um resumo único, altamente detalhado e abrangente de todo o enredo e resolução do livro (máximo de 2000 caracteres). Você DEVE formatar este resumo usando vários parágrafos distintos separados por quebras de linha duplas (\\n\\n) para facilitar a leitura, em vez de um único bloco de texto." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Livro: %s
Autor: %s
Analisando o Capítulo: %s

TAREFA: Analise APENAS este capítulo individual. Identifique NOVAS entidades introduzidas neste capítulo e ATUALIZAÇÕES DELTA (transições de estado) para entidades existentes.
Produza APENAS um objeto JSON válido.

MANIFESTO DE ENTIDADES CONHECIDAS EXISTENTES (NÃO extraia novamente, a menos que o papel, status ou descrição delas tenha evoluído significativamente):
%s

REGRAS:
1. CONFINAMENTO RIGOROSO DE SPOILERS: Analise APENAS o texto do capítulo fornecido. NÃO utilize nenhum conhecimento de capítulos futuros ou fontes externas.
2. PROFUNDIDADE E SUBSTÂNCIA DA DESCRIÇÃO DA PERSONAGEM (CRÍTICO):
   - Embasada e Específica: Descreva quem é a personagem com fatos concretos da história — sua origem, personalidade distinta, profissão, relacionamentos principais com outras personagens e seu papel específico e interesses pessoais na narrativa.
   - Contexto Narrativo Significativo: Conecte a personagem diretamente ao mistério central, conflito do enredo ou investigação deste livro (ex.: quais crimes ou casos estão investigando, quem os contratou, aliados ou adversários principais, dilemas ou tensões pessoais específicos).
   - NÃO seja excessivamente genérico: NÃO escreva textos genéricos baseados em clichês (ex.: evite frases vazias como "um detetive investigando casos complexos"). Nomeie as circunstâncias, conexões e interesses específicos estabelecidos no texto.
   - SEM RESUMOS DE TAREFAS TRIVIAIS: NÃO escreva registros cronológicos de atividades diárias mundanas ou tarefas rotineiras (ex.: NÃO resuma idas ao supermercado, chamadas telefônicas de rotina ou movimentos incidentais cena a cena).
   - As descrições das personagens devem ser perfis ricos e vívidos que resumem quem elas são e sua importância até este ponto do livro.
3. ALTO LIMITE PARA ATUALIZAÇÕES DE PERSONAGENS:
   - NÃO crie uma atualização em `character_state_updates` simplesmente porque uma personagem existente apareceu, falou ou realizou ações de rotina neste capítulo.
   - APENAS gere uma atualização se houver uma transformação substantiva e duradoura em seu arco narrativo, identidade, relacionamentos, emprego, lealdade ou condição (ex.: morta, ferida, presa, traída, noiva, promovida, revelada como a culpada, segredo ou motivo importante descoberto).
   - Se uma atualização FOR justificada, a `description` atualizada deve ser uma visão geral rica e cumulativa da personagem que incorpore os novos desenvolvimentos e, ao mesmo tempo, mantenha sua identidade central e o contexto estabelecido da história — NÃO um resumo de uma cena isolada.
4. MARCADORES DE PÁGINA DENTRO DO CAPÍTULO ([PAGE N]) E FILTRAGEM ZERO SPOILER:
   - Os textos dos capítulos contêm marcadores [PAGE N] indicando a progressão das páginas.
   - Para `new_characters`, `new_locations` e `new_terms`: forneça "first_page" (número inteiro N do marcador [PAGE N] onde foi mencionado pela primeira vez), "intro_role" (para personagens) e "intro_description" (1-2 frases estritamente limitadas ao que se sabe em sua primeira introdução em [PAGE first_page] — com ZERO conhecimento de reviravoltas, segredos ou resultados posteriores que ocorram em páginas seguintes). Forneça também "page" (o marcador [PAGE N] onde a "description" cumulativa mais completa se aplica, normalmente a página final do capítulo).
   - Para `character_state_updates`, `location_state_updates` e `term_state_updates`: forneça "page" (número inteiro N do marcador [PAGE N] onde a revelação/transição se completa; NÃO revele fatos antes desta página).
5. EVIDÊNCIA: Forneça uma breve referência ou trecho de citação deste capítulo explicando por que a atualização ocorreu.
6. CRONOGRAMA: Forneça exatamente um resumo de evento das principais ações do enredo neste capítulo.

FORMATO JSON OBRIGATÓRIO:
{
  "new_characters": [
    {
      "name": "Nome Completo",
      "aliases": ["Pseudônimo 1", "Pseudônimo 2"],
      "first_page": 80,
      "intro_role": "Papel inicial (ex.: Escrivão da Vila, Estranho, Cliente)",
      "intro_description": "Impressão inicial de 1-2 frases estritamente na primeira introdução, sem spoilers das páginas seguintes.",
      "page": 99,
      "role": "Papel narrativo / importância (ex.: Protagonista, Investigador Particular, Parceiro, Antagonista, Vítima, Cliente, Suspeito, Personagem Secundária, Personagem Menor)",
      "status": "viva",
      "description": "Descrição rica e específica da personagem (origem, relacionamentos, interesses narrativos). Evite textos genéricos e registros de tarefas triviais.",
      "evidence": "Trecho curto"
    }
  ],
  "character_state_updates": [
    {
      "name": "Nome correspondente ao manifesto conhecido",
      "page": 95,
      "role": "Papel narrativo / importância atualizado (ex.: Protagonista, Parceiro, Antagonista, Personagem Secundária, etc.)",
      "status": "viva",
      "change": "Uma frase curta nomeando o que mudou desde o estado anterior (ex.: 'Promovido a sócio após o caso Shacklewell')",
      "description": "Descrição rica e cumulativa atualizada da personagem refletindo seu novo status e interesses na história",
      "evidence": "Trecho curto"
    }
  ],
  "new_locations": [
    {
      "name": "Nome do Local",
      "first_page": 80,
      "intro_description": "Impressão inicial na primeira menção.",
      "page": 99,
      "description": "Descrição do local",
      "evidence": "Trecho curto"
    }
  ],
  "location_state_updates": [
    {
      "name": "Nome correspondente ao manifesto conhecido",
      "page": 95,
      "change": "Uma frase curta nomeando o que mudou (ex.: 'Destruído durante a batalha de Oakhaven')",
      "description": "Descrição evoluída atualizada",
      "evidence": "Trecho curto"
    }
  ],
  "new_terms": [
    {
      "name": "Nome do Termo",
      "first_page": 80,
      "intro_description": "Definição inicial na primeira menção.",
      "page": 99,
      "description": "Definição ou explicação do lore",
      "evidence": "Trecho curto"
    }
  ],
  "term_state_updates": [
    {
      "name": "Nome correspondente ao manifesto conhecido",
      "page": 95,
      "change": "Uma frase curta nomeando o que mudou na compreensão ou uso",
      "description": "Definição atualizada",
      "evidence": "Trecho curto"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Resumo dos eventos neste capítulo"
  }
}

TEXTO DO CAPÍTULO:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Livro: %s
Autor: %s
Capítulos neste Lote: %s

TAREFA: Analise o lote sequencial de capítulos fornecido em ordem.
Para CADA capítulo do lote, identifique:
1. NOVAS entidades introduzidas nesse capítulo (personagens, locais, termos).
2. ATUALIZAÇÕES DELTA (transições de estado) para entidades conhecidas existentes (do manifesto OU introduzidas em um capítulo anterior deste lote) SE E SOMENTE SE seu papel, status, lealdade ou condição narrativa tiverem passado por uma transformação substantiva e duradoura.
3. EVENTO DA LINHA DO TEMPO: Um resumo conciso dos principais eventos do enredo ocorridos nesse capítulo.

Gere COMO SAÍDA APENAS um objeto JSON válido correspondente ao esquema exigido.

MANIFESTO DE ENTIDADES CONHECIDAS EXISTENTES (de lotes anteriores - NÃO re-extraia a menos que seu papel, status ou descrição tenham evoluído significativamente):
%s

REGRAS:
1. CONFINAMENTO RIGOROSO DE SPOILERS E PROGRESSÃO SEQUENCIAL:
   - Analise os capítulos em ordem sequencial.
   - Para qualquer capítulo deste lote, NÃO incorpore conhecimentos de capítulos posteriores do lote ou do restante do livro.
2. PROFUNDIDADE E SUBSTÂNCIA DA DESCRIÇÃO DO PERSONAGEM (CRÍTICO):
   - Embasada e Específica: Descreva quem é o personagem com fatos concretos da história—seu histórico, personalidade distinta, profissão, relacionamentos principais com outros personagens e seu papel específico e interesses pessoais na narrativa.
   - Contexto Narrativo Significativo: Conecte o personagem diretamente ao mistério central, conflito do enredo ou investigação neste livro (ex.: quais crimes ou casos estão investigando, quem os contratou, aliados ou adversários principais, dilemas pessoais ou tensões específicas).
   - NÃO Excessivamente Geral: NÃO escreva sinopses genéricas de clichês/tropos (ex.: evite frases vazias como "um detetive investigando casos complexos"). Nomeie as circunstâncias, conexões e interesses específicos estabelecidos no texto.
   - SEM RECAPITULAÇÕES DE TAREFAS TRIVIAIS: NÃO escreva registros cronológicos de atividades diárias mundanas ou tarefas de rotina (ex.: NÃO recapitule idas ao supermercado, chamadas telefônicas de rotina ou movimentos incidentais cena a cena).
   - As descrições dos personagens devem ser perfis ricos e vívidos, resumindo quem eles são e sua importância até este ponto do livro.
3. ALTO LIMIAR PARA ATUALIZAÇÕES DE PERSONAGENS:
   - NÃO crie uma atualização em `character_state_updates` simplesmente porque um personagem existente apareceu, falou ou realizou ações de rotina em um capítulo.
   - APENAS gere uma atualização se houver uma transformação substantiva e duradoura em seu arco narrativo, identidade, relacionamentos, emprego, lealdade ou condição (ex.: morto, ferido, preso, traído, noivo, promovido, revelado como o culpado, grande segredo ou motivação descobertos).
   - Se uma atualização FOR justificada, a `description` atualizada deve ser uma visão geral rica e cumulativa do personagem que incorpore os novos desdobramentos, mantendo sua identidade principal e o contexto estabelecido na história—NÃO um resumo de uma cena isolada.
4. MARCADORES DE PÁGINA INTRACAPÍTULO ([PAGE N]) E RESTRIÇÃO TOTAL DE SPOILERS:
   - Os textos dos capítulos contêm marcadores [PAGE N] indicando a progressão das páginas.
   - Para `new_characters`, `new_locations` e `new_terms`: forneça "first_page" (número inteiro N do marcador [PAGE N] onde é mencionado pela primeira vez), "intro_role" (para personagens) e "intro_description" (1 a 2 frases estritamente limitadas ao que se sabe em sua primeira introdução em [PAGE first_page]—com ZERO conhecimento de reviravoltas, segredos ou desfechos posteriores que ocorrem em páginas seguintes). Forneça também "page" (o marcador [PAGE N] onde a "description" cumulativa mais completa se aplica, normalmente a página final do capítulo).
   - Para `character_state_updates`, `location_state_updates` e `term_state_updates`: forneça "page" (número inteiro N do marcador [PAGE N] onde a revelação/transição se completa; NÃO revele fatos antes desta página).
5. EVIDÊNCIA: Forneça uma breve referência ou trecho de citação desse capítulo específico explicando por que a atualização ocorreu.
6. SEGURANÇA DO JSON: Gere como saída estritamente um JSON válido. Escape adequadamente as aspas duplas dentro das strings.

FORMATO JSON EXIGIDO:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Título do Capítulo",
      "timeline_event": "Resumo dos principais desdobramentos do enredo neste capítulo.",
      "new_characters": [
        {
          "name": "Nome Completo",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Papel inicial (ex.: Escrivão, Estranho, Cliente)",
          "intro_description": "Impressão inicial de 1 a 2 frases estritamente na primeira introdução, zero spoilers de páginas posteriores.",
          "page": 99,
          "role": "Papel / importância narrativa (ex.: Protagonista, Detetive Particular, Parceiro, Antagonista, Vítima, Cliente, Suspeito, Personagem Secundário, Personagem Menor)",
          "status": "alive",
          "description": "Descrição rica e específica do personagem (histórico, relacionamentos, interesses narrativos). Evite sinopses genéricas e registros de tarefas triviais.",
          "evidence": "Trecho breve"
        }
      ],
      "character_state_updates": [
        {
          "name": "Nome correspondente ao manifesto conhecido ou personagem introduzido em capítulo anterior deste lote",
          "page": 95,
          "role": "Papel / importância narrativa atualizados (ex.: Protagonista, Parceiro, Antagonista, Personagem Secundário, etc.)",
          "status": "alive",
          "change": "Uma frase curta nomeando o que mudou em relação ao estado anterior (ex.: 'Promovido a sócio após o caso Shacklewell')",
          "description": "Descrição rica e cumulativa atualizada do personagem refletindo seu novo status e interesses na história",
          "evidence": "Trecho breve"
        }
      ],
      "new_locations": [
        {
          "name": "Nome do Local",
          "first_page": 80,
          "intro_description": "Impressão inicial na primeira menção.",
          "page": 99,
          "description": "Descrição do local",
          "evidence": "Trecho breve"
        }
      ],
      "location_state_updates": [
        {
          "name": "Nome correspondente ao manifesto conhecido ou local introduzido em capítulo anterior deste lote",
          "page": 95,
          "change": "Uma frase curta nomeando o que mudou (ex.: 'Destruído durante a batalha de Oakhaven')",
          "description": "Descrição atualizada",
          "evidence": "Trecho breve"
        }
      ],
      "new_terms": [
        {
          "name": "Nome do Termo",
          "first_page": 80,
          "intro_description": "Definição inicial na primeira menção.",
          "page": 99,
          "description": "Definição ou explicação do lore",
          "evidence": "Trecho breve"
        }
      ],
      "term_state_updates": [
        {
          "name": "Nome correspondente ao manifesto conhecido ou termo introduzido em capítulo anterior deste lote",
          "page": 95,
          "change": "Uma frase curta nomeando o que mudou no entendimento ou uso",
          "description": "Definição atualizada",
          "evidence": "Trecho breve"
        }
      ]
    }
  ]
}

TEXTOS DOS CAPÍTULOS NESTE LOTE:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analise os seguintes detalhes do livro e o Sumário:

Título: %s
Autor: %s
Assuntos: %s
Descrição: %s

Sumário:
%s

Determine se esta obra é:
1. "anthology" (uma coleção de contos, ensaios ou novelas independentes, cada um com sua própria narrativa ou elenco autônomo, por exemplo, "As Aventuras de Sherlock Holmes", "Dublinenses", "Expiração", "Homens Sem Mulheres").
2. "novel" (um romance único e unificado dividido em capítulos, partes ou atos, por exemplo, "Orgulho e Preconceito", "Harry Potter", "Duna", "Carrie").
3. "novel_omnibus" (uma coleção de vários volumes de romances completos publicados juntos em um único volume, por exemplo, "O Senhor dos Anéis: Volume Único", "O Guia do Mochileiro das Galáxias: A Trilogia de Cinco", "Percy Jackson: Livros 1-3").
4. "non_fiction" (um único tratado de não ficção, livro de história ou acadêmico dividido em capítulos).

Retorne APENAS um objeto JSON com:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 a 1.0,
  "reasoning": "explicação breve (uma frase)"
}]],

    -- System instruction
    system_instruction = "Você é um pesquisador literário especialista. Sua resposta deve estar APENAS no formato JSON válido. Certifique-se de que os dados sejam altamente precisos e pertençam estritamente ao contexto fornecido.",

    -- Fallback strings
    fallback = {
        no_biography = "Biografia Não Disponível",
        no_description = "Sem Descrição",
        not_specified = "Não Especificado",
        unknown_author = "Autor Desconhecido",
        unknown_book = "Livro Desconhecido",
        unnamed_character = "Personagem Sem Nome",
        unnamed_person = "Pessoa Sem Nome"
    }
}
