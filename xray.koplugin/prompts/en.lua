return {
    -- System instruction
    system_instruction = "You are an expert literary researcher. Your response must be ONLY in valid JSON format. Ensure data is highly accurate and pertains strictly to the provided context.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identify and provide biography for the author of the book "%s". 
Metadata suggests the author is "%s". 

CRITICAL: Verify the author using the BOOK TEXT CONTEXT (if provided at the end of this prompt) to ensure 100%% accuracy and avoid incorrect identifications.

REQUIRED JSON FORMAT:
{
  "author": "Correct Full Name",
  "author_bio": "Comprehensive biography focusing on their literary career and major works.",
  "author_birth": "Birth Date, formatted based on local date format",
  "author_death": "Death Date, formatted based on local date format"
}]],

    -- Find Duplicates (for AI-Assisted Merge)
    find_duplicates = [[Book: %s
Author: %s
Reading Progress: %d%%

You are reviewing the following list of %s extracted from this book.
Your task is to identify any entries that appear to be the SAME entity listed under different names.

LIST:
%s

RULES:
- A duplicate exists when two entries clearly refer to the same entity (e.g., "The Grand Library" and "Grand Library", or "John" and "John Doe").
- Do NOT flag entries that are merely related or similar but distinct.
- Do NOT flag entries unless you are highly confident they are the same entity.
- If no duplicates exist, return an empty array.
- SPOILER RULE: Do not use knowledge from beyond %d%% reading progress.

REQUIRED JSON FORMAT:
{
  "duplicate_pairs": [
    {
      "primary": "Name of the entry to KEEP (the more complete or formal name)",
      "secondary": "Name of the entry to REMOVE",
      "reason": "Brief reason (max 100 chars)"
    }
  ]
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Book: %s
Author: %s
Reading Progress: %d%%

TASK: Perform a complete X-Ray analysis. Output ONLY a valid JSON object.

CRITICAL ATTENTION PARTITIONING:
You are processing a massive document with two text blocks provided at the end of this prompt:
1. "CHAPTER SAMPLES": This is the macro-context of the book up to the reader's current location.
2. "BOOK TEXT CONTEXT": This is the micro-context of the most recent 20k characters.

ANTI-TRUNCATION PROTOCOL (CRITICAL):
You have a strict maximum output limit. If the "CHAPTER SAMPLES" contains MORE THAN 40 chapters (e.g., an omnibus edition):
1. You MUST reduce the characters list to ONLY the top 10 absolute most important characters.
2. You MUST reduce character descriptions to MAX {MAX_CHAR_DESC} characters.
3. You MUST reduce timeline event summaries to MAX {MAX_TIMELINE_EVENT} characters.
Failure to compress your output for massive books will cause the JSON to truncate and fail.

ALGORITHM FOR TIMELINE (HIGHEST PRIORITY):
To prevent skipping chapters or hallucinating events, you MUST execute this exact loop:
Step 1. Look ONLY at the "CHAPTER SAMPLES" block. Identify the narrative chapters.
Step 2. EXCLUDE all non-narrative frontmatter and backmatter (e.g., Cover, Title Page, Copyright, Table of Contents, Dedication, Acknowledgments, Also By).
Step 3. For each narrative chapter, starting from the very first one, create EXACTLY ONE event object in the `timeline` array.
Step 4. The `chapter` field MUST exactly match the chapter header in the sample. (Map them strictly in sequential order).
Step 5. Summarize that specific chapter in the `event` field. {TIMELINE_DETAIL_GUIDANCE} Write between {MIN_TIMELINE_EVENT} and {MAX_TIMELINE_EVENT} characters. Do NOT write a shorter summary unless the chapter has almost no content. Do NOT group chapters.
Step 6. NO SPOILERS: Stop exactly at the %d%% mark. Do not include events past this progress.

ALGORITHM FOR CHARACTERS & HISTORICAL FIGURES:
Step 1. Extract important characters using both text blocks. ({NUM_CHARS} normal, MAX 10 if omnibus).
Step 2. You MUST use their FULL, formal names (e.g., "Abraham Van Helsing"). Do NOT use casual nicknames as the main name.
Step 3. Provide up to 3 alternative names, titles, or nicknames this character goes by in an `aliases` array. Include their common first name and last name if used. IMPORTANT: If a last name is shared by multiple characters (e.g., family members), DO NOT include it as an alias for either character.
Step 4. Actively scan for up to {NUM_HIST} NOTABLE REAL people from human history (e.g., Presidents, Authors, Generals). Add them to `historical_figures`.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
NO SPOILERS: Stop exactly at the %d%% mark.

ALGORITHM FOR LOCATIONS:
Step 1. Extract {NUM_LOCS} significant locations. NO SPOILERS: Stop exactly at the %d%% mark.

ALGORITHM FOR TERMS:
Step 0. Declare "book_type" as "fiction", "non_fiction", or "anthology" at the JSON root.
Step 1. If non_fiction: extract {NUM_TERMS} significant technical terms, acronyms, jargon, or concepts readers would not know without specialized knowledge. Use appropriate categories like Acronym, Technical Term, Concept, or Jargon.
Step 2. If fiction or anthology: extract {NUM_TERMS} significant world-building elements that a new reader would need explained—such as invented factions, organizations, magic systems, technologies, creatures, languages, or in-universe lore.
   - Do NOT include character names or location names (those are tracked separately).
   - DO NOT extract real-world common words or concepts.
   - Use appropriate categories: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Step 3. Include what the acronym/phrase stands for in "expanded". If not an acronym/phrase, repeat the name.
Step 4. DO NOT include common everyday words.

STRICT SPOILER RULES:
- ABSOLUTELY NO information from after the current reading progress. Stop exactly at the %d%% mark.
- Descriptions must reflect the characters' state at this exact point in the book.

STRICT KNOWLEDGE SOURCE RULES (CRITICAL):
- For FICTIONAL CHARACTERS: Your descriptions MUST be based SOLELY on what is explicitly stated or clearly implied in the provided text. Do NOT supplement with knowledge from prior training, external sources, or general awareness of the book/series/author.
- If a character has only been briefly mentioned in the text so far, your description must reflect that limited information only. Do NOT infer, assume, or add any detail not grounded in the provided context.
- The ONLY exception is for REAL HISTORICAL FIGURES (placed in `historical_figures`): you may use internal knowledge for their general biography/role, but still rely on the book text for their `context_in_book`.

STRICT JSON SAFETY RULES:
- You MUST properly escape all double quotes (\") inside strings.
- Do NOT use unescaped line breaks inside strings.
- Output ONLY valid, parseable JSON.

REQUIRED JSON FORMAT:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Full Formal Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Short archetype label (3-5 words, e.g. 'Antagonist', 'Protagonist', 'The Victim')",
      "gender": "Male / Female / Unknown",
      "occupation": "Job/Status",
      "description": "Description based STRICTLY on text provided. Do not infer or add external knowledge. NO SPOILERS. (Max {MAX_CHAR_DESC} chars)"
    }
  ],
  "historical_figures": [
    {
      "name": "Real Historical Person Name",
      "role": "Historical Role",
      "biography": "Short biography (MAX {MAX_HIST_BIO} chars)",
      "importance_in_book": "Significance up to current progress",
      "context_in_book": "How they are mentioned (MAX 100 chars)"
    }
  ],
  "locations": [
    {"name": "Place Name", "description": "Short desc (MAX {MAX_LOC_DESC} chars)"}
  ],
  "terms": [
    {
      "name": "Term or Acronym",
      "expanded": "Full expansion or same as name",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Concise definition in context (MAX {MAX_TERM_DEF} chars)"
    }
  ],
  "timeline": [
    {
      "chapter": "Exact Chapter Title from Samples",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
} ]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Book: %s
Author: %s
Reading Progress: %d%%

TASK: Extract EXACTLY 10 ADDITIONAL important characters from the text.
Return ONLY a valid JSON object.

CONCISENESS MANDATE (CRITICAL):
To avoid AI response truncation, keep character descriptions under {MAX_CHAR_DESC} characters.

CRITICAL INSTRUCTION:
Do NOT include any of the following characters, as they have already been extracted:
%s

STRICT SPOILER RULES:
- ABSOLUTELY NO information from after the current reading progress. Stop exactly at the %d%% mark.
- Descriptions must reflect the characters' state at this exact point in the book.

REQUIRED JSON FORMAT:
{
  "characters": [
    {
      "name": "Full Formal Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Short archetype label (3-5 words, e.g. 'Antagonist', 'Protagonist', 'The Victim')",
      "gender": "Male / Female / Unknown",
      "occupation": "Job/Status",
      "description": "Description based STRICTLY on text provided. Do not infer or add external knowledge. NO SPOILERS. (Max {MAX_CHAR_DESC} chars)"
    }
  ]
}]],

    -- Fetch More Terms (Glossary Support)
    more_terms = [[Book: %s
Author: %s
Reading Progress: %d%%

TASK: Extract EXACTLY 15 ADDITIONAL significant terms, acronyms, jargon, or concepts from the text.
- If this book is non-fiction: extract technical terms, concepts, acronyms, or jargon.
- If this book is fiction: extract world-building elements like factions, organizations, magic systems, technologies, creatures, languages, or in-universe lore.
Return ONLY a valid JSON object.

CONCISENESS MANDATE (CRITICAL):
To avoid AI response truncation, keep term definitions under {MAX_TERM_DEF} characters.

CRITICAL INSTRUCTION:
Do NOT include any of the following terms, as they have already been extracted:
%s

STRICT SPOILER RULES:
- ABSOLUTELY NO information from after the current reading progress. Stop exactly at the %d%% mark.

REQUIRED JSON FORMAT:
{
  "terms": [
    {
      "name": "Term or Acronym",
      "expanded": "Full expansion or same as name",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Concise definition in context (MAX {MAX_TERM_DEF} chars)"
    }
  ]
}]],

    single_word_lookup = [[The user highlighted the word "%s".
TASK: Determine if this word represents a Character, Location, Historical Figure, or Technical Term/Acronym in the book.

CRITICAL FOR CHARACTERS AND LOCATIONS: Use the provided "BOOK TEXT CONTEXT" to identify the entity. If the word is provided in a "SEARCH TARGET" or "DIRECT REFERENCE" hint, it IS present in the book at the current position. Do not reject it just because it isn't found exactly in the sub-sampled narrative text. Short names (as short as 2 letters, e.g. "Oz", "Al", "Jo") are valid and should be analyzed.
CRITICAL FOR FICTIONAL CHARACTERS: Describe ONLY what the provided book text reveals. Do NOT use prior training knowledge about this character, even if you recognize them from a well-known series. If the text only briefly mentions this character, your description must reflect that limited information.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
CRITICAL FOR TERMS: If the book is non-fiction, check if the word is a technical term, acronym, or key concept. For technical terms, concepts, or jargon: the term may appear in chapter samples rather than the immediate page context — treat it as valid if you can define it in the context of this book's subject. Only set `is_valid` to false if the phrase has absolutely no relevance to this book's subject matter.
If the word is NOT a character, location, historical figure, or technical term/concept, set `is_valid` to false.

REQUIRED JSON FORMAT:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Full Name",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Short archetype label (3-5 words, e.g. 'Antagonist', 'Protagonist', 'The Victim')",
    "gender": "Male/Female/Unknown",
    "occupation": "Occupation",
    "description": "Short description (MAX 250 chars)"
  },
  "error_message": ""
}

Note: If type is "location", the item should have "name" and "description". If type is "historical_figure", the item should have "name", "biography", and "role". If type is "term", the item should have "name", "expanded", "category", and "definition".

If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Short explanation why this is not a character or location."
}]],

    -- Smart Merge Descriptions
    merge_descriptions = [[TASK: Combine the following two descriptions of the same entity (character or location) into a single, cohesive, and concise summary.
Remove redundant information and ensure the final description flows naturally.

Primary Description: %s
Secondary Description: %s

REQUIRED JSON FORMAT:
{
  "merged_description": "Combined and polished description (Max {MAX_CHAR_DESC} chars)"
}]],

    book_type_detect = [[Book Title: %s
Author: %s
Series: %s
File Description/Subject Metadata: %s

TASK: Classify this book into exactly ONE of these book types based on its metadata and genre signals:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Return ONLY valid JSON:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Multi-Book Series Context Prompts
    series_detect = [[Book Title: %s
Author: %s

TASK: Determine if this book is part of a named series.
Return ONLY valid JSON:
{
  "is_series": true,
  "series_name": "The Wheel of Time",
  "book_index": 3,
  "total_books_known": 14
}
If this is NOT a series book, return:
{ "is_series": false }]],

    prior_book_list = [[Series: %s
Current Book Index: %d
Current Book Title: %s

TASK: List the titles (and authors if different from "%s") of books 1 through %d
that come BEFORE the current book in this series.
Return ONLY valid JSON:
{
  "prior_books": [
    { "index": 1, "title": "The Eye of the World", "author": "Robert Jordan" }
  ]
}]],

    series_book_summary = [[TARGET BOOK: %s
AUTHOR: %s
TARGET BOOK INDEX: %d
SERIES: %s

TASK:
Provide a COMPLETE recap of TARGET BOOK only, for a reader who has finished
TARGET BOOK and is about to start the next book in the series.

ABSOLUTE SPOILER BOUNDARY:
Knowledge cutoff is strictly the FINAL PAGE of TARGET BOOK (Book Index %d).
You may include facts established in TARGET BOOK or earlier books in this series.
You MUST NOT include, imply, hint at, foreshadow, or select details using knowledge from any later book.

FORBIDDEN LATER-BOOK INFORMATION:
- Later events, future fates, deaths, survivals, destinations, romances, alliances, conflicts, or betrayals.
- Later-book identities, true origins, secret parentage, aliases, alter egos, reincarnations, transformations, titles, or power advancements (e.g., do NOT mention if an essence joins another or is reborn in a future book).
- Revelations, confirmations, reinterpretations, twists, or world-building terminology introduced in later books.
- Retrospective foreshadowing or phrases such as "later", "eventually", "will become", "in subsequent books", or equivalent.
- Mentioning characters, concepts, organizations, or chronology from later books.

CHARACTER CUTOFF:
Describe every character strictly as known at the final page of TARGET BOOK.
Do NOT use aliases, roles, relationships, true identities, or statuses revealed in later books.

UNCERTAINTY RULE:
If you cannot confidently determine whether a fact or alias was established by the end of TARGET BOOK, OMIT IT.
Missing detail is far preferable to a future book spoiler.

FINAL AUDIT:
Before returning JSON, inspect every field (especially character descriptions and aliases) and purge anything dependent on knowledge from books after TARGET BOOK.

REQUIRED JSON FORMAT:
{
  "characters": [
    { "name": "Full Name", "aliases": [], "role": "...", "description": "Status at end of this book (max {MAX_CHAR_DESC} chars)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Book Summary", "event": "A single, highly detailed, comprehensive recap of the entire book's plot, main events, and resolution (max 2000 characters). You MUST format this recap using multiple distinct paragraphs separated by double newlines (\\n\\n) for readability instead of a single wall of text." }
  ]
}]] ,

    local_timeline_summary = [[TARGET BOOK: %s
AUTHOR: %s
TARGET BOOK INDEX: %d
SERIES: %s

TASK:
Using ONLY the verified chapter-by-chapter events provided below from TARGET BOOK, write a cohesive, comprehensive recap of the entire book's plot, key developments, and resolution.

STRICT GROUNDING CONSTRAINT:
- Ground your summary EXCLUSIVELY on the provided chapter events.
- Do NOT introduce facts, characters, events, or outcomes not described in these chapter events.
- NEVER mention or foreshadow events, deaths, or developments from later books in the series.

CHAPTER EVENTS:
%s

REQUIRED JSON FORMAT:
{
  "timeline": [
    { "chapter": "Book Summary", "event": "A single, highly detailed, comprehensive recap of the entire book's plot and resolution (max 2000 characters). You MUST format this recap using multiple distinct paragraphs separated by double newlines (\\n\\n) for readability instead of a single wall of text." }
  ]
}]],

    -- Single Chapter Delta Extraction (Sequential Horizon & Full Book Scan)
    chapter_delta = [[Book: %s
Author: %s
Analyzing Chapter: %s

TASK: Analyze ONLY this single chapter. Identify NEW entities introduced in this chapter, and DELTA UPDATES (state transitions) for existing entities.
Output ONLY a valid JSON object.

EXISTING KNOWN ENTITIES MANIFEST (Do NOT re-extract unless their role, status, or description evolved significantly):
%s

RULES:
1. STRICT SPOILER CONFINEMENT: Analyze ONLY the provided chapter text. Do NOT use any knowledge from future chapters or external sources.
2. CHARACTER DESCRIPTION DEPTH & SUBSTANCE (CRITICAL):
   - Grounded & Specific: Describe who the character is with concrete story facts—their background, distinct personality, profession, key relationships to other characters, and their specific role and personal stakes in the narrative.
   - Significant Narrative Context: Connect the character directly to the central mystery, plot conflict, or investigation in this book (e.g. what crimes or cases they are investigating, who hired them, key allies or adversaries, specific personal dilemmas or tensions).
   - NOT Overly General: Do NOT write generic trope blurbs (e.g. avoid empty phrasing like "a detective investigating complex cases"). Name the specific circumstances, connections, and stakes established in the text.
   - NO Trivial Errand Recaps: Do NOT write chronological logs of mundane daily activities or routine chores (e.g. do NOT recap trips to the grocery store, routine phone calls, or incidental scene-by-scene movements).
   - Character descriptions must be rich, vivid profiles summarizing who they are and their significance up to this point in the book.
3. HIGH THRESHOLD FOR CHARACTER UPDATES:
   - DO NOT create an update in `character_state_updates` simply because an existing character appeared, spoke, or performed routine actions in this chapter.
   - ONLY generate an update if there is a substantive, lasting transformation in their narrative arc, identity, relationships, employment, allegiance, or condition (e.g. killed, injured, arrested, betrayed, engaged, promoted, revealed to be the culprit, major secret or motive uncovered).
   - If an update IS justified, the updated `description` must be a rich, cumulative character overview that incorporates the new developments while retaining their core identity and established story context—NOT a summary of an isolated scene.
4. EVIDENCE: Provide a brief reference or quote excerpt from this chapter explaining why the update occurred.
5. TIMELINE: Provide exactly one event summary of the main plot actions in this chapter.

REQUIRED JSON FORMAT:
{
  "new_characters": [
    {
      "name": "Full Name",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Narrative role / importance (e.g. Protagonist, Private Investigator, Partner, Antagonist, Victim, Client, Suspect, Secondary Character, Minor Character)",
      "status": "alive",
      "description": "Rich, specific character description (background, relationships, narrative stakes). Avoid generic blurbs and trivial errand logs.",
      "evidence": "Short excerpt"
    }
  ],
  "character_state_updates": [
    {
      "name": "Name matching known manifest",
      "role": "Updated narrative role / importance (e.g. Protagonist, Partner, Antagonist, Secondary Character, etc.)",
      "status": "alive",
      "change": "One short sentence naming what changed since the previous state (e.g. 'Promoted to partner after the Shacklewell case')",
      "description": "Updated rich, cumulative character description reflecting their new status and story stakes",
      "evidence": "Short excerpt"
    }
  ],
  "new_locations": [
    {
      "name": "Location Name",
      "description": "Description of location",
      "evidence": "Short excerpt"
    }
  ],
  "location_state_updates": [
    {
      "name": "Name matching known manifest",
      "change": "One short sentence naming what changed (e.g. 'Destroyed during the battle of Oakhaven')",
      "description": "Updated evolved description",
      "evidence": "Short excerpt"
    }
  ],
  "new_terms": [
    {
      "name": "Term Name",
      "description": "Definition or lore explanation",
      "evidence": "Short excerpt"
    }
  ],
  "term_state_updates": [
    {
      "name": "Name matching known manifest",
      "change": "One short sentence naming what changed in understanding or usage",
      "description": "Updated definition",
      "evidence": "Short excerpt"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Summary of events in this chapter"
  }
}

CHAPTER TEXT:
%s]],

    -- Batch Multi-Chapter Delta Extraction (Batched Horizon & Full Book Scan)
    batch_chapter_delta = [[Book: %s
Author: %s
Chapters in this Batch: %s

TASK: Analyze the provided sequential batch of chapters in order.
For EACH chapter in the batch, identify:
1. NEW entities introduced in that chapter (characters, locations, terms).
2. DELTA UPDATES (state transitions) for existing known entities (from the manifest OR introduced in an earlier chapter of this batch) IF AND ONLY IF their role, status, allegiance, or narrative condition underwent a substantive, lasting transformation.
3. TIMELINE EVENT: A concise summary of the primary plot events occurring in that chapter.

Output ONLY a valid JSON object matching the required schema.

EXISTING KNOWN ENTITIES MANIFEST (from prior batches - do NOT re-extract unless their role, status, or description evolved significantly):
%s

RULES:
1. STRICT SPOILER CONFINEMENT & SEQUENTIAL PROGRESSION:
   - Analyze the chapters in sequential order.
   - For any chapter in this batch, do NOT incorporate knowledge from later chapters in the batch or from the rest of the book.
2. CHARACTER DESCRIPTION DEPTH & SUBSTANCE (CRITICAL):
   - Grounded & Specific: Describe who the character is with concrete story facts—their background, distinct personality, profession, key relationships to other characters, and their specific role and personal stakes in the narrative.
   - Significant Narrative Context: Connect the character directly to the central mystery, plot conflict, or investigation in this book (e.g. what crimes or cases they are investigating, who hired them, key allies or adversaries, specific personal dilemmas or tensions).
   - NOT Overly General: Do NOT write generic trope blurbs (e.g. avoid empty phrasing like "a detective investigating complex cases"). Name the specific circumstances, connections, and stakes established in the text.
   - NO Trivial Errand Recaps: Do NOT write chronological logs of mundane daily activities or routine chores (e.g. do NOT recap trips to the grocery store, routine phone calls, or incidental scene-by-scene movements).
   - Character descriptions must be rich, vivid profiles summarizing who they are and their significance up to this point in the book.
3. HIGH THRESHOLD FOR CHARACTER UPDATES:
   - DO NOT create an update in `character_state_updates` simply because an existing character appeared, spoke, or performed routine actions in a chapter.
   - ONLY generate an update if there is a substantive, lasting transformation in their narrative arc, identity, relationships, employment, allegiance, or condition (e.g. killed, injured, arrested, betrayed, engaged, promoted, revealed to be the culprit, major secret or motive uncovered).
   - If an update IS justified, the updated `description` must be a rich, cumulative character overview that incorporates the new developments while retaining their core identity and established story context—NOT a summary of an isolated scene.
4. EVIDENCE: Provide a brief reference or quote excerpt from that specific chapter explaining why the update occurred.
5. JSON SAFETY: Output strictly valid JSON. Properly escape double quotes inside strings.

REQUIRED JSON FORMAT:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Chapter Title",
      "timeline_event": "Summary of primary plot developments in this chapter.",
      "new_characters": [
        {
          "name": "Full Name",
          "aliases": ["Alias 1"],
          "role": "Narrative role / importance (e.g. Protagonist, Private Investigator, Partner, Antagonist, Victim, Client, Suspect, Secondary Character, Minor Character)",
          "status": "alive",
          "description": "Rich, specific character description (background, relationships, narrative stakes). Avoid generic blurbs and trivial errand logs.",
          "evidence": "Brief excerpt"
        }
      ],
      "character_state_updates": [
        {
          "name": "Name matching known manifest or character introduced in earlier chapter of this batch",
          "role": "Updated narrative role / importance (e.g. Protagonist, Partner, Antagonist, Secondary Character, etc.)",
          "status": "alive",
          "change": "One short sentence naming what changed since the previous state (e.g. 'Promoted to partner after the Shacklewell case')",
          "description": "Updated rich, cumulative character description reflecting their new status and story stakes",
          "evidence": "Brief excerpt"
        }
      ],
      "new_locations": [
        {
          "name": "Location Name",
          "description": "Description of location",
          "evidence": "Brief excerpt"
        }
      ],
      "location_state_updates": [
        {
          "name": "Name matching known manifest or location introduced in earlier chapter of this batch",
          "change": "One short sentence naming what changed (e.g. 'Destroyed during the battle of Oakhaven')",
          "description": "Updated description",
          "evidence": "Brief excerpt"
        }
      ],
      "new_terms": [
        {
          "name": "Term Name",
          "description": "Definition or lore explanation",
          "evidence": "Brief excerpt"
        }
      ],
      "term_state_updates": [
        {
          "name": "Name matching known manifest or term introduced in earlier chapter of this batch",
          "change": "One short sentence naming what changed in understanding or usage",
          "description": "Updated definition",
          "evidence": "Brief excerpt"
        }
      ]
    }
  ]
}

CHAPTER TEXTS IN THIS BATCH:
%s]],

    -- Anthology Structure Detection
    anthology_detect = [[Analyze the following book details and Table of Contents:

Title: %s
Author: %s
Subjects: %s
Description: %s

Table of Contents:
%s

Determine whether this work is:
1. "anthology" (a collection of independent short stories, essays, or novellas, each with its own self-contained narrative or cast, e.g. "The Adventures of Sherlock Holmes", "Dubliners", "Exhalation", "Men Without Women").
2. "novel" (a single unified novel divided into chapters, parts, or acts, e.g. "Pride and Prejudice", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (a multi-volume collection of full-length novels published together in one volume, e.g. "The Lord of the Rings: All Three Volumes", "The Complete Hitchhiker's Guide to the Galaxy", "Percy Jackson: Books 1-3").
4. "non_fiction" (a single non-fiction treatise, history, or academic book divided into chapters).

Return ONLY a JSON object with:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 to 1.0,
  "reasoning": "brief explanation (one sentence)"
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Unknown Book",
        unknown_author = "Unknown Author",
        unnamed_character = "Unnamed Character",
        not_specified = "Not Specified",
        no_description = "No Description",
        unnamed_person = "Unnamed Person",
        no_biography = "No Biography Available"
    }
}