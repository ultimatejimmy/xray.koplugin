return {
    -- System instruction
    system_instruction = "你是一位资深的文学研究专家。你的回复必须仅采用有效的 JSON 格式。确保数据高度准确，且严格符合提供的上下文。",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[识别并提供书籍 "%s" 作者的简介。
元数据表明作者是 "%s"。

关键提示：请务必结合“书籍文本上下文”（如果本提示末尾有提供）来核实作者，以确保 100%% 的准确性，避免身份识别错误。

要求的 JSON 格式：
{
  "author": "正确的全名",
  "author_bio": "详尽的简介，侧重于其文学职业生涯和主要作品。",
  "author_birth": "出生日期，根据本地日期格式进行格式化",
  "author_death": "逝世日期，根据本地日期格式进行格式化"
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[书名：%s
作者：%s
阅读进度：%d%%

任务：进行完整的 X-Ray 分析。仅输出一个有效的 JSON 对象。

关键注意力分配：
你正在处理一个庞大的文档，本提示末尾提供了两个文本块：
1. "CHAPTER SAMPLES"（章节样本）：这是书籍到读者当前位置为止的大致上下文。
2. "BOOK TEXT CONTEXT"（书籍文本上下文）：这是最后 20,000 个字符的微观上下文。

防截断协议（关键）：
你有严格的最大输出限制。如果 "CHAPTER SAMPLES" 包含超过 40 个章节（例如：合集本）：
1. 你必须将角色列表缩减为仅包含最重要的 10 个核心角色。
2. 你必须将角色描述缩减至最多 {MAX_CHAR_DESC} 个字符。
3. 你必须将时间线事件总结缩减至最多 {MAX_TIMELINE_EVENT} 个字符。
若不为超大书籍压缩输出，将导致 JSON 截断并失败。

时间线算法（最高优先级）：
为了防止跳过章节或产生虚构事件，你必须执行以下循环：
步骤 1：仅查看 "CHAPTER SAMPLES" 块。识别叙事性章节。
步骤 2：排除所有非叙事性的前言和后记（例如：封面、扉页、版权页、目录、献词、致谢等）。
步骤 3：针对每个叙事性章节，从第一章开始，在 `timeline` 数组中创建一个对应的事件对象。
步骤 4：`chapter` 字段必须与样本中的章节标题完全匹配。（按顺序严格映射）。
步骤 5：在 `event` 字段中总结该特定章节（最多 {MAX_TIMELINE_EVENT} 个字符）。不要合并章节。
步骤 6：严禁剧透：严格停止在 %d%% 进度处。不要包含超过此进度的事件。

角色与历史人物算法：
步骤 1：结合两个文本块提取重要角色。（普通书籍 {NUM_CHARS} 个，合集本最多 10 个）。
步骤 2：你必须使用他们的正式全名（例如："Abraham Van Helsing"）。不要使用非正式昵称作为主名称。
步骤 3：在一个 `aliases` 数组中提供该角色最多 3 个备用名称、头衔或昵称。如果使用，请包含他们常用的名字和姓氏。重要提示：如果一个姓氏被多个角色（例如家庭成员）共享，请不要将其作为任何角色的别名。
步骤 4：积极扫描最多 {NUM_HIST} 位人类历史上的著名真实人物（例如：总统、作家、将军）。将他们添加到 `historical_figures`。
角色与历史人物的关键提示：
- 不要提取仅在非叙事性的前言或后记（例如：致谢、作者简介、献词、扉页、版权页）中提到的角色或历史人物。
- 历史人物必须是经过验证的、具有广泛历史认可度的现实世界人物。
- 不要将纯虚构角色包含在历史人物列表中，即使他们与真实历史事件有互动。虚构角色必须进入 `characters` 数组。
- 仅针对历史人物，你可以使用你的内部知识来撰写他们的通用 `biography` 和历史 `role`，但你必须使用书籍上下文来描述他们在书中的相关性 `context_in_book`。
严禁剧透：严格停止在 %d%% 进度处。

地点算法：
步骤 1：提取 {NUM_LOCS} 个重要地点。严禁剧透：严格停止在 %d%% 进度处。

术语与概念算法：
步骤 0：在 JSON 根节点声明 "book_type" 为 "fiction"（虚构）或 "non_fiction"（非虚构）。
步骤 1：如果是非虚构类书籍：提取 {NUM_TERMS} 个重要的技术术语、缩写、行业术语或概念。使用合适的类别，如 Acronym、Technical Term、Concept 或 Jargon。
步骤 2：如果是虚构类书籍：提取 {NUM_TERMS} 个重要的世界构建（World-building）元素，这些元素是新读者需要解释的——例如虚构的阵营、组织、魔法系统、技术、生物、语言或宇宙设定（Lore）。
   - 不要包含角色名称或地点名称（这些是单独跟踪的）。
   - 不要提取现实世界的普通词汇或概念。
   - 使用合适的类别：Faction, Magic System, Technology, Creature, Organization, Lore, Language。
步骤 3：在 "expanded" 中包含缩写/短语的全称。如果不是缩写/短语，则重复名称。
步骤 4：不要包含日常普通词汇。

严格剧透规则：
- 绝对禁止包含当前阅读进度之后的信息。严格停止在 %d%% 进度处。
- 描述必须反映角色在书籍当前进度的状态。

严格 JSON 安全规则：
- 你必须对字符串内部的所有双引号 (\") 进行正确转义。
- 不要在字符串内部使用未转义的换行符。
- 仅输出有效的、可解析的 JSON。

要求的 JSON 格式：
{
  "characters": [
    {
      "name": "正式全名",
      "aliases": ["别名 1", "别名 2"],
      "role": "到当前进度为止的角色定位",
      "gender": "男 / 女 / 未知",
      "occupation": "职业/身份",
      "description": "结合目前为止的文本进行深度分析。严禁剧透。（最多 {MAX_CHAR_DESC} 个字符）"
    }
  ],
  "historical_figures": [
    {
      "name": "真实历史人物姓名",
      "role": "历史角色",
      "biography": "简短传记（最多 {MAX_HIST_BIO} 个字符）",
      "importance_in_book": "到目前为止在书中的重要性",
      "context_in_book": "提及方式（最多 100 个字符）"
    }
  ],
    "locations": [
      {"name": "地点名称", "description": "简短描述（最多 {MAX_LOC_DESC} 个字符）"}
    ],
    "terms": [
      {
        "name": "术语或缩写",
        "expanded": "全称或与名称相同",
        "category": "缩写 / 技术术语 / 概念 / 行业术语",
        "definition": "结合上下文的简要定义（最多 {MAX_TERM_DEF} 个字符）"
      }
    ],
    "timeline": [
    {
      "chapter": "样本中的准确章节标题",
      "event": "该章节的关键叙事事件（最多 {MAX_TIMELINE_EVENT} 个字符）"
    }
  ]
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[书名：%s
作者：%s
阅读进度：%d%%

任务：从文本中额外提取 10 个重要的角色。
仅返回一个有效的 JSON 对象。

简洁指令（关键）：
为避免 AI 回复被截断，请将角色描述保持在 {MAX_CHAR_DESC} 个字符以内。

关键提示：
不要包含以下角色，因为他们已经提取过了：
%s

严格剧透规则：
- 绝对禁止包含当前阅读进度之后的信息。严格停止在 %d%% 进度处。
- 描述必须反映角色在书籍当前进度的状态。

要求的 JSON 格式：
{
  "characters": [
    {
      "name": "正式全名",
      "aliases": ["别名 1", "别名 2"],
      "role": "到当前进度为止的角色定位",
      "gender": "男 / 女 / 未知",
      "occupation": "职业/身份",
      "description": "结合目前为止的文本进行深度分析。严禁剧透。（最多 {MAX_CHAR_DESC} 个字符）"
    }
  ]
}]],

    -- 获取更多术语（术语表支持）
    more_terms = [[书名：%s
作者：%s
阅读进度：%d%%

任务：从文本中额外提取 15 个重要的术语、缩写、行业术语或概念。
- 如果本书是非虚构类书籍：提取技术术语、概念、缩写或行业术语。
- 如果本书是虚构类书籍：提取世界构建（world-building）元素，如阵营、组织、魔法系统、技术、生物、语言或宇宙设定（lore）。
仅返回一个有效的 JSON 对象。

简洁指令（关键）：
为避免 AI 回复被截断，请将术语定义保持在 {MAX_TERM_DEF} 个字符以内。

关键提示：
不要包含以下术语，因为他们已经提取过了：
%s

严格剧透规则：
- 绝对禁止包含当前阅读进度之后的信息。严格停止在 %d%% 进度处。

要求的 JSON 格式：
{
  "terms": [
    {
      "name": "术语或缩写",
      "expanded": "全称或与名称相同",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / 缩写 / 技术术语 / 概念 / 行业术语",
      "definition": "结合上下文的简要定义（最多 {MAX_TERM_DEF} 个字符）"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[用户选中了单词 "%s"。
任务：判断该单词是否为书中的人物、地点、历史人物或技术术语/缩写。
 
关键提示（人物与地点）：仅使用提供的“书籍文本上下文”。严禁使用外部知识。不要产生虚构。
关键提示（历史人物）：你可以使用你的内部知识来核实他们的身份并提供简介/角色，但前提是他们必须是真实的、著名的历史人物。你仍需使用文本上下文来描述他们在书中的相关性。
关键提示（术语）：如果书籍是非虚构类的，请核实该词是否为技术术语、缩写或关键概念。提供其在上下文中的定义。
如果该单词在文本中不是人物、地点、历史人物或技术术语，请将 `is_valid` 设置为 false。
 
要求的 JSON 格式：
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "全名",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "角色/定位",
    "gender": "男/女/未知",
    "occupation": "职业",
    "description": "简短描述（最多 250 个字符）"
  },
  "error_message": ""
}
 
注意：如果类型是 "location"，则 item 应包含 "name" 和 "description"。如果类型是 "historical_figure"，则 item 应包含 "name", "biography", 和 "role"。
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "简要说明为什么这不是人物或地点。"
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "未知书籍",
        unknown_author = "未知作者",
        unnamed_character = "未命名角色",
        not_specified = "未指定",
        no_description = "无描述",
        unnamed_person = "未命名人物",
        no_biography = "暂无简介"
    }
}
