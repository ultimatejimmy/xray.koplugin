# Localization Rule

Whenever you modify translation keys in the Lua code (e.g., adding or removing `self.loc:t("key")`), you MUST run the synchronization tool to keep the `.po` files consistent.

**Command (Windows/PowerShell):**
```powershell
python tools/sync_translations.py
```

1. `en.po` (Master) is updated with new keys found in the Lua source.
2. All other languages (`de.po`, `es.po`, `fr.po`, `ru.po`, `tr.po`, etc.) are synchronized with the Master.
3. Existing translations are preserved while new keys are added as placeholders.

## Automated Translations and Auditing
A zero-dependency developer utility script `tools/translate_all.py` is available to perform automated translations using Gemini and audit all translation files.

### 1. Audit Format Mismatches & Placeholders
Before committing changes to any translation or prompt file, run the audit tool to verify that all variable placeholders (like `%s`, `%d`, `%1$s`) and braced tags (like `{MAX_CHAR_DESC}`) match the English master source. This prevents runtime string formatting crashes.

**Audit Command:**
```powershell
python tools/translate_all.py --audit <lang_code>
```
*Example:* `python tools/translate_all.py --audit id`

### 2. Auto-Translate Missing Keys
To automatically translate missing/new keys in `.po` and `.lua` prompt templates via Gemini API, set the `GEMINI_API_KEY` environment variable and run the translate mode:

**Translation Command:**
```powershell
python tools/translate_all.py --translate <lang_code> "<Language_Name>"
```
*Example:* `python tools/translate_all.py --translate id "Bahasa Indonesia"`

## AI Prompts Workflow
The AI prompts are stored in `xray.koplugin/prompts/*.lua`. 

Whenever you modify the logic or structure of an AI prompt (e.g., `comprehensive_xray` in `en.lua`):
1.  Apply the changes to the English version first.
2.  Use the `tools/translate_all.py` tool to synchronize, translate, or audit other language templates.
3.  Ensure that all **variable placeholders** (`%s`, `%d`, `%%`) and **JSON keys** remain identical across all languages to avoid parsing errors.
4.  Verify that the "ALGORITHM" and "PROTOCOL" sections are translated accurately to maintain AI steering performance in all regions.

