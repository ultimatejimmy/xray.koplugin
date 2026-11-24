#!/usr/bin/env python3
import os
import re
import sys
import json
import time
import urllib.request
import urllib.error

# Configuration
if sys.version_info >= (3, 7):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

import sync_translations as st

BASE_DIR = os.path.dirname(TOOLS_DIR)
LANGUAGES_DIR = os.path.join(BASE_DIR, 'xray.koplugin', 'languages')
PROMPTS_DIR = os.path.join(BASE_DIR, 'xray.koplugin', 'prompts')


def get_gemini_key():
    return os.environ.get("GEMINI_API_KEY")


def call_gemini(prompt):
    key = get_gemini_key()
    if not key:
        print("Error: GEMINI_API_KEY environment variable not set. Cannot run automated translations.")
        sys.exit(1)

    primary = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash-lite")
    fallback_models = []
    for m in (
        primary,
        "gemini-3.5-flash-lite",
        "gemini-3.1-flash-lite",
        "gemini-3.1-flash-lite-preview",
        "gemini-flash-lite-latest",
        "gemini-3.8-flash",
        "gemini-4-argon",
        "gemini-4-hydrogen",
        "gemini-3.7-flash",
    ):
        if m not in fallback_models:
            fallback_models.append(m)

    headers = {"Content-Type": "application/json"}
    data = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseMimeType": "application/json"},
    }
    encoded_data = json.dumps(data).encode('utf-8')

    max_retries = 2
    for model in fallback_models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
        req = urllib.request.Request(url, data=encoded_data, headers=headers, method='POST')
        for attempt in range(max_retries):
            try:
                with urllib.request.urlopen(req, timeout=90) as response:
                    res_data = json.loads(response.read().decode('utf-8'))
                    text = res_data['candidates'][0]['content']['parts'][0]['text']
                    time.sleep(1.0)  # Gentle pacing between requests
                    text_stripped = text.strip()
                    first_brace = text_stripped.find('{')
                    last_brace = text_stripped.rfind('}')
                    if first_brace != -1 and last_brace != -1:
                        json_str = text_stripped[first_brace:last_brace + 1]
                        return json.loads(json_str)
                    return json.loads(text_stripped)
            except urllib.error.HTTPError as e:
                err_body = ""
                try:
                    err_body = e.read().decode('utf-8', errors='ignore')
                except Exception:
                    pass
                if e.code == 404 or (e.code == 429 and "PerDay" in err_body):
                    print(f"Model {model} unavailable ({e.code}), switching to next model...")
                    break
                if e.code in (429, 500, 502, 503, 504):
                    if attempt < max_retries - 1:
                        retry_after = e.headers.get('Retry-After') if e.code == 429 else None
                        default_wait = 8 if e.code == 429 else 2
                        sleep_time = int(retry_after) if retry_after and retry_after.isdigit() else default_wait
                        print(f"Gemini API ({model}) returned code {e.code}. Retrying in {sleep_time}s (attempt {attempt + 1}/{max_retries})...")
                        time.sleep(sleep_time)
                    else:
                        print(f"Model {model} exhausted retries on HTTP {e.code}, trying fallback...")
                        break
                else:
                    print(f"API Error calling Gemini ({model}): {e}")
                    sys.exit(1)
            except Exception as e:
                if attempt < max_retries - 1:
                    print(f"API Error calling Gemini ({model}: {e}). Retrying in 2s...")
                    time.sleep(2)
                else:
                    print(f"Model {model} failed ({e}), trying fallback...")
                    break
    print("API Error: All Gemini fallback models failed.")
    sys.exit(1)


# PO File Parser & Generator (delegated to sync_translations for consistency)
parse_po = st.parse_po
extract_placeholders = st.extract_placeholders


def save_po(file_path, lang_name, lang_code, keys, translations, en_final=None):
    if en_final is None:
        en_po_path = os.path.join(LANGUAGES_DIR, 'en.po')
        en_entries = parse_po(en_po_path)
        en_final = {e['msgid']: e['msgstr'] for e in en_entries if e['msgid']}
    st.save_po(file_path, lang_name, lang_code, keys, translations, en_final, en_final)


# Lua Prompts Parser & Generator
def parse_lua_prompts(file_path):
    if not os.path.exists(file_path):
        return {}
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    prompts = {}

    # 1. Extract fallback table first and remove it before top-level string scan
    fallback_match = re.search(r'fallback\s*=\s*\{(.*?)\}', content, re.DOTALL)
    content_without_fallback = content
    if fallback_match:
        fb_dict = {}
        for m in re.finditer(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', fallback_match.group(1)):
            fb_dict[m.group(1)] = st.decode_po_string(m.group(2))
        prompts['fallback'] = fb_dict
        content_without_fallback = content[:fallback_match.start()] + content[fallback_match.end():]

    # 2. Extract block string values [[ ... ]] or [=[ ... ]=]
    stripped_for_short = content_without_fallback
    for m in re.finditer(r'(\w+)\s*=\s*\[(=*)\[(.*?)\]\2\]', content_without_fallback, re.DOTALL):
        prompts[m.group(1)] = m.group(3).strip()
        stripped_for_short = stripped_for_short.replace(m.group(0), '')

    # 3. Extract top-level short string values
    for m in re.finditer(r'(\w+)\s*=\s*"((?:[^"\\]|\\.)*)"', stripped_for_short):
        if m.group(1) != 'fallback':
            prompts[m.group(1)] = st.decode_po_string(m.group(2))

    return prompts


def _lua_long_string(text):
    eq = ''
    while f']{eq}]' in text:
        eq += '='
    return f'[{eq}[\n{text}]{eq}]'


def save_lua_prompts(file_path, prompts, reference_prompts=None):
    if reference_prompts is None:
        en_lua_path = os.path.join(PROMPTS_DIR, 'en.lua')
        if os.path.exists(en_lua_path) and os.path.abspath(file_path) != os.path.abspath(en_lua_path):
            reference_prompts = parse_lua_prompts(en_lua_path)
        else:
            reference_prompts = {}

    # Determine key order from reference_prompts (en.lua), then any extra keys in prompts
    ordered_keys = [k for k in reference_prompts.keys() if k != 'fallback' and k in prompts]
    for k in prompts.keys():
        if k != 'fallback' and k not in ordered_keys:
            ordered_keys.append(k)

    short_keys = {
        'system_instruction', 'unknown_book', 'unknown_author', 'unnamed_character',
        'not_specified', 'no_description', 'unnamed_person', 'no_biography',
    }

    with open(file_path, 'w', encoding='utf-8', newline='\n') as f:
        f.write("return {\n")
        for key in ordered_keys:
            val = prompts[key]
            if key in short_keys and '\n' not in val:
                escaped = st.encode_po_string(val)
                title_comment = "System instruction" if key == "system_instruction" else key.replace('_', ' ').title()
                f.write(f'    -- {title_comment}\n    {key} = "{escaped}",\n\n')
            else:
                title_comment = key.replace('_', ' ').title()
                f.write(f'    -- {title_comment}\n    {key} = {_lua_long_string(val)},\n\n')

        if 'fallback' in prompts:
            f.write('    -- Fallback strings\n    fallback = {\n')
            fb = prompts['fallback']
            fb_keys = sorted(fb.keys())
            for idx, k in enumerate(fb_keys):
                comma = "," if idx < len(fb_keys) - 1 else ""
                f.write(f'        {k} = "{st.encode_po_string(fb[k])}"{comma}\n')
            f.write('    }\n')

        f.write("}\n")


def audit_language(lang_code):
    print(f"=== Auditing Language: {lang_code} ===")

    en_po_path = os.path.join(LANGUAGES_DIR, 'en.po')
    target_po_path = os.path.join(LANGUAGES_DIR, f'{lang_code}.po')

    en_po = parse_po(en_po_path)
    target_po = parse_po(target_po_path)

    en_po_dict = {e['msgid']: e['msgstr'] for e in en_po if e['msgid']}
    target_po_dict = {e['msgid']: e['msgstr'] for e in target_po if e['msgid']}

    po_errors = 0
    missing_po_keys = []
    same_as_en_keys = []

    for key, en_val in en_po_dict.items():
        if key == 'language_name':
            continue
        if key not in target_po_dict or not target_po_dict[key] or target_po_dict[key] == key:
            missing_po_keys.append(key)
            continue

        tr_val = target_po_dict[key]
        if tr_val == en_val and not st.is_allowed_identical(lang_code, key):
            same_as_en_keys.append(key)

        en_pl, en_br = extract_placeholders(en_val)
        tr_pl, tr_br = extract_placeholders(tr_val)

        if en_pl != tr_pl:
            print(f"PO Format Mismatch for key '{key}':")
            print(f"  EN: {repr(en_val)} (Placeholders: {en_pl})")
            print(f"  TR: {repr(tr_val)} (Placeholders: {tr_pl})")
            po_errors += 1

        if en_br != tr_br:
            print(f"PO Braced Tag Mismatch for key '{key}':")
            print(f"  EN: {repr(en_val)} (Braced Tags: {en_br})")
            print(f"  TR: {repr(tr_val)} (Braced Tags: {tr_br})")
            po_errors += 1

    if missing_po_keys:
        print(f"Missing {len(missing_po_keys)} PO keys:")
        for k in missing_po_keys[:10]:
            print(f"  - {k}")
        if len(missing_po_keys) > 10:
            print(f"  ... and {len(missing_po_keys) - 10} more.")

    if same_as_en_keys:
        print(f"Untranslated (identical to EN) {len(same_as_en_keys)} PO keys:")
        for k in same_as_en_keys[:10]:
            print(f"  - {k} = {repr(en_po_dict[k])}")
        if len(same_as_en_keys) > 10:
            print(f"  ... and {len(same_as_en_keys) - 10} more.")

    # 2. Audit prompt templates (.lua)
    en_lua_path = os.path.join(PROMPTS_DIR, 'en.lua')
    target_lua_path = os.path.join(PROMPTS_DIR, f'{lang_code}.lua')

    lua_errors = 0
    missing_lua_keys = []

    if os.path.exists(target_lua_path):
        en_lua = parse_lua_prompts(en_lua_path)
        target_lua = parse_lua_prompts(target_lua_path)

        for key, en_val in en_lua.items():
            if key == 'fallback':
                for fb_k, fb_en_val in en_val.items():
                    if fb_k not in target_lua.get('fallback', {}):
                        missing_lua_keys.append(f"fallback.{fb_k}")
                        continue
                    fb_tr_val = target_lua['fallback'][fb_k]
                    en_pl, en_br = extract_placeholders(fb_en_val)
                    tr_pl, tr_br = extract_placeholders(fb_tr_val)
                    if en_pl != tr_pl or en_br != tr_br:
                        print(f"LUA Fallback Format Mismatch for key '{fb_k}':")
                        print(f"  EN: {repr(fb_en_val)}")
                        print(f"  TR: {repr(fb_tr_val)}")
                        lua_errors += 1
                continue

            if key not in target_lua:
                missing_lua_keys.append(key)
                continue

            tr_val = target_lua[key]
            en_pl, en_br = extract_placeholders(en_val)
            tr_pl, tr_br = extract_placeholders(tr_val)

            if en_pl != tr_pl:
                print(f"LUA Prompt Placeholders Mismatch for block '{key}':")
                print(f"  EN: {en_pl}")
                print(f"  TR: {tr_pl}")
                lua_errors += 1

            if en_br != tr_br:
                print(f"LUA Prompt Braced Tags Mismatch for block '{key}':")
                print(f"  EN: {en_br}")
                print(f"  TR: {tr_br}")
                lua_errors += 1
    else:
        print(f"LUA prompt file {lang_code}.lua does not exist.")
        missing_lua_keys = ["All prompt keys"]

    if missing_lua_keys:
        print(f"Missing {len(missing_lua_keys)} LUA keys/blocks: {missing_lua_keys}")

    print("\n--- Audit Summary ---")
    print(f"PO File: {len(missing_po_keys)} missing keys, {len(same_as_en_keys)} identical-to-EN keys, {po_errors} placeholder errors.")
    print(f"LUA File: {len(missing_lua_keys)} missing blocks/keys, {lua_errors} placeholder errors.")

    if po_errors > 0 or lua_errors > 0 or missing_po_keys or same_as_en_keys or missing_lua_keys:
        return False
    return True


# Automated Translation
def translate_language(lang_code, lang_name):
    print(f"=== Translating to {lang_name} ({lang_code}) ===")

    en_po_path = os.path.join(LANGUAGES_DIR, 'en.po')
    target_po_path = os.path.join(LANGUAGES_DIR, f'{lang_code}.po')

    en_po = parse_po(en_po_path)
    target_po = parse_po(target_po_path) if os.path.exists(target_po_path) else []

    en_po_dict = {e['msgid']: e['msgstr'] for e in en_po if e['msgid']}
    target_po_dict = {e['msgid']: e['msgstr'] for e in target_po if e['msgid']}
    target_hashes = {e['msgid']: e['en_hash'] for e in target_po if e['msgid']}

    # 1. Translate PO Keys
    missing_po = st.find_untranslated_keys(lang_code, en_po_dict, target_po_dict, target_hashes)

    if missing_po:
        print(f"Translating {len(missing_po)} UI string keys...")
        keys_list = list(missing_po.keys())
        batch_size = 25
        for i in range(0, len(keys_list), batch_size):
            batch_keys = keys_list[i:i + batch_size]
            batch_dict = {k: missing_po[k] for k in batch_keys}

            prompt = f"""You are a localization expert translating the user interface of a reading plugin called "X-Ray" (inspired by Kindle X-Ray) for KOReader.
Translate the following English key-value strings into {lang_name}.

CRITICAL rules:
1. Retain all format specifiers such as %s, %d, %1$s, %2$d, etc. exactly in the translated output.
2. Retain all literal escaped newlines (\\n) and tabs (\\t) exactly.
3. Keep the translation concise, natural, and suited for a mobile e-reader display.
4. Return ONLY a valid JSON object mapping the keys to their translated values. Do not wrap in markdown code blocks.

Strings to translate:
{json.dumps(batch_dict, indent=2)}
"""
            translated_batch = call_gemini(prompt)
            for k, v in translated_batch.items():
                target_po_dict[k] = v
            target_po_dict['language_name'] = lang_name
            save_po(target_po_path, lang_name, lang_code, en_po_dict.keys(), target_po_dict, en_po_dict)
            print(f"Saved batch progress to {target_po_path}")

        target_po_dict['language_name'] = lang_name
        save_po(target_po_path, lang_name, lang_code, en_po_dict.keys(), target_po_dict, en_po_dict)
        print(f"Saved translated UI strings to {target_po_path}")
    else:
        print("All UI strings already translated.")

    # 2. Translate LUA Prompts (missing OR placeholder/tag mismatched)
    en_lua_path = os.path.join(PROMPTS_DIR, 'en.lua')
    target_lua_path = os.path.join(PROMPTS_DIR, f'{lang_code}.lua')

    en_lua = parse_lua_prompts(en_lua_path)
    target_lua = parse_lua_prompts(target_lua_path) if os.path.exists(target_lua_path) else {}

    missing_lua = {}
    for k, v in en_lua.items():
        if k == 'fallback':
            if 'fallback' not in target_lua:
                target_lua['fallback'] = {}
            for fb_k, fb_v in v.items():
                if fb_k not in target_lua['fallback']:
                    missing_lua[f"fallback.{fb_k}"] = fb_v
                else:
                    en_pl, en_br = extract_placeholders(fb_v)
                    tr_pl, tr_br = extract_placeholders(target_lua['fallback'][fb_k])
                    if en_pl != tr_pl or en_br != tr_br:
                        missing_lua[f"fallback.{fb_k}"] = fb_v
            continue
        if k not in target_lua:
            missing_lua[k] = v
        else:
            en_pl, en_br = extract_placeholders(v)
            tr_pl, tr_br = extract_placeholders(target_lua[k])
            if en_pl != tr_pl or en_br != tr_br:
                missing_lua[k] = v

    if missing_lua:
        print(f"Translating {len(missing_lua)} AI Prompt templates...")
        for k, v in missing_lua.items():
            prompt = f"""You are a literary and localization expert. Translate the following X-Ray AI prompt template/instruction or fallback string into {lang_name}.

CRITICAL guidelines:
1. Maintain all placeholders like %s, %d, %1$d, %%%% etc. EXACTLY (including every %%d, %%s, and literal %%%%!).
2. Maintain all curly braces keys like {{MAX_CHAR_DESC}}, {{MIN_TIMELINE_EVENT}}, {{MAX_TIMELINE_EVENT}}, {{TIMELINE_DETAIL_GUIDANCE}}, {{TIMELINE_EXAMPLE}}, {{NUM_CHARS}}, {{NUM_HIST}}, {{NUM_LOCS}}, {{NUM_TERMS}} EXACTLY.
3. Keep the formatting, list numbering, and headers (like ALGORITHM, RULES) in the exact same format.
4. Translate all descriptions, role titles, guidance text, and JSON comments in the prompt templates naturally and professionally into {lang_name}.
5. Do NOT translate JSON key names (like "duplicate_pairs", "primary", "secondary", "reason", "is_series", "characters") inside JSON template formats.
6. Return ONLY a valid JSON object with the format:
{{
  "translation": "<Your translated prompt text here>"
}}
Do not add any markdown blocks or formatting.

English text to translate:
{v}
"""
            translated_result = call_gemini(prompt)
            tr_text = translated_result["translation"]

            if k.startswith("fallback."):
                fb_key = k.split(".")[1]
                target_lua['fallback'][fb_key] = tr_text
            else:
                target_lua[k] = tr_text

            save_lua_prompts(target_lua_path, target_lua, en_lua)

        save_lua_prompts(target_lua_path, target_lua, en_lua)
        print(f"Saved translated prompt templates to {target_lua_path}")
    else:
        print("All LUA prompts already translated.")


def get_supported_languages():
    languages = {}
    for file in os.listdir(LANGUAGES_DIR):
        if file.endswith('.po') and file != 'en.po':
            lang_code = file[:-3]
            path = os.path.join(LANGUAGES_DIR, file)
            lang_name = lang_code.capitalize()
            entries = parse_po(path)
            for e in entries:
                if e['msgid'] == '':
                    m = re.search(r'Language-Team:\s*(.+)', e['msgstr'])
                    if m:
                        lang_name = m.group(1).strip()
            languages[lang_code] = lang_name
    return languages


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage:")
        print("  python tools/translate_all.py --audit <lang_code>|all")
        print("  python tools/translate_all.py --translate <lang_code>|all [Language_Name]")
        print("Examples:")
        print("  python tools/translate_all.py --audit all")
        print("  python tools/translate_all.py --translate id \"Bahasa Indonesia\"")
        print("  python tools/translate_all.py --translate all")
        sys.exit(1)

    mode = sys.argv[1]
    lang = sys.argv[2]

    if mode == '--audit':
        if lang == 'all':
            supported = get_supported_languages()
            all_success = True
            for code in sorted(supported.keys()):
                success = audit_language(code)
                if not success:
                    all_success = False
            sys.exit(0 if all_success else 1)
        else:
            success = audit_language(lang)
            sys.exit(0 if success else 1)

    elif mode == '--translate':
        if lang == 'all':
            supported = get_supported_languages()
            for code, name in sorted(supported.items()):
                translate_language(code, name)
        else:
            if len(sys.argv) < 4:
                print("Error: Language Name is required for translation of a single language.")
                sys.exit(1)
            name = sys.argv[3]
            translate_language(lang, name)
    else:
        print(f"Unknown mode: {mode}")
        sys.exit(1)
