return {
    -- System instruction
    system_instruction = "You are an expert literary researcher. Your response must be ONLY in valid JSON format. Ensure data is highly accurate and pertains strictly to the provided context.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identify and provide biography for the author of the book "%s". 
Metadata suggests the author is "%s". 
1
CRITICAL: Verify the author using the BOOK TEXT CONTEXT (if provided at the end of this prompt) to ensure 100% accuracy and avoid incorrect identifications.

REQUIRED JSON FORMAT:
{
  "author": "Correct Full Name",
  "author_bio": "Comprehensive biography focusing on their literary career and major works.",
  "author_birth": "Birth Date, formatted based on local date format",
  "author_death": "Death Date, formatted based on local date format"
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
Step 5. Summarize that specific chapter in the `event` field (MAX {MAX_TIMELINE_EVENT} chars). Do NOT group chapters.
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
Step 0. Declare "book_type" as "fiction" or "non_fiction" at the JSON root.
Step 1. If non_fiction: extract {NUM_TERMS} significant technical terms, acronyms, jargon, or concepts readers would not know without specialized knowledge. Use appropriate categories like Acronym, Technical Term, Concept, or Jargon.
Step 2. If fiction: extract {NUM_TERMS} significant world-building elements that a new reader would need explained—such as invented factions, organizations, magic systems, technologies, creatures, languages, or in-universe lore.
   - Do NOT include character names or location names (those are tracked separately).
   - DO NOT extract real-world common words or concepts.
   - Use appropriate categories: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Step 3. Include what the acronym/phrase stands for in "expanded". If not an acronym/phrase, repeat the name.
Step 4. DO NOT include common everyday words.

STRICT SPOILER RULES:
- ABSOLUTELY NO information from after the current reading progress. Stop exactly at the %d%% mark.
- Descriptions must reflect the characters' state at this exact point in the book.

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
      "description": "Deep analysis with details from the text so far. NO SPOILERS. (Max {MAX_CHAR_DESC} chars)"
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
      "event": "Key narrative event from this chapter (Max {MAX_TIMELINE_EVENT} chars)"
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
      "description": "Deep analysis with details from the text so far. NO SPOILERS. (Max {MAX_CHAR_DESC} chars)"
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
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
CRITICAL FOR TERMS: If the book is non-fiction, check if the word is a technical term, acronym, or key concept. Provide its definition in context.
If the word is NOT a character, location, historical figure, or technical term, set `is_valid` to false.

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