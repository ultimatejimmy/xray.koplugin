#!/usr/bin/env python3
import os
import re
import sys
import json
import urllib.request

# Configuration
if sys.version_info >= (3, 7):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGUAGES_DIR = os.path.join(BASE_DIR, 'xray.koplugin', 'languages')
PROMPTS_DIR = os.path.join(BASE_DIR, 'xray.koplugin', 'prompts')

def get_gemini_key():
    return os.environ.get("GEMINI_API_KEY")

def call_gemini(prompt):
    import time
    import urllib.error
    key = get_gemini_key()
    if not key:
        print("Error: GEMINI_API_KEY environment variable not set. Cannot run automated translations.")
        sys.exit(1)
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent?key={key}"
    headers = {"Content-Type": "application/json"}
    data = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseMimeType": "application/json"}
    }
    
    req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
    
    max_retries = 6
    backoff = 2
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req) as response:
                res_data = json.loads(response.read().decode('utf-8'))
                text = res_data['candidates'][0]['content']['parts'][0]['text']
                time.sleep(10.0)  # Space out requests to avoid rate limits
                text_stripped = text.strip()
                first_brace = text_stripped.find('{')
                last_brace = text_stripped.rfind('}')
                if first_brace != -1 and last_brace != -1:
                    json_str = text_stripped[first_brace:last_brace+1]
                    return json.loads(json_str)
                return json.loads(text_stripped)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < max_retries - 1:
                sleep_time = backoff ** attempt + 2
                print(f"Gemini API returned code {e.code}. Retrying in {sleep_time} seconds (attempt {attempt + 1}/{max_retries})...")
                time.sleep(sleep_time)
            else:
                print(f"API Error calling Gemini: {e}")
                sys.exit(1)
        except Exception as e:
            print(f"API Error calling Gemini: {e}")
            sys.exit(1)

# PO File Parser & Generator
def parse_po(file_path):
    entries = []
    current_entry = {'msgid': '', 'msgstr': '', 'comments': []}
    current_field = None
    if not os.path.exists(file_path): return []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                if current_entry['msgid'] or current_entry['msgstr']:
                    entries.append(current_entry)
                    current_entry = {'msgid': '', 'msgstr': '', 'comments': []}
                current_field = None
                continue
            if line.startswith('#'):
                current_entry['comments'].append(line)
            elif line.startswith('msgid '):
                m = re.match(r'^msgid "(.*)"$', line)
                if m: current_entry['msgid'] = m.group(1)
                current_field = 'msgid'
            elif line.startswith('msgstr '):
                m = re.match(r'^msgstr "(.*)"$', line)
                if m: current_entry['msgstr'] = m.group(1)
                current_field = 'msgstr'
            elif line.startswith('"'):
                m = re.match(r'^"(.*)"$', line)
                if m:
                    if current_field == 'msgid':
                        current_entry['msgid'] += m.group(1)
                    elif current_field == 'msgstr':
                        current_entry['msgstr'] += m.group(1)
        if current_entry['msgid'] or current_entry['msgstr']:
            entries.append(current_entry)
    return entries

def save_po(file_path, lang_name, lang_code, keys, translations):
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(f'msgid ""\nmsgstr ""\n"Language-Team: {lang_name}\\n"\n"Language: {lang_code}\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n')
        for key in sorted(keys):
            if not key: continue
            val = translations.get(key, "")
            # Ensure escaped newlines
            escaped_val = val.replace('\n', '\\n').replace('"', '\\"')
            f.write(f'msgid "{key}"\nmsgstr "{escaped_val}"\n\n')

# Lua Prompts Parser & Generator
def parse_lua_prompts(file_path):
    if not os.path.exists(file_path): return {}
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Extract keys and values inside the return { ... }
    # A simple but reliable parser for the prompt structures
    prompts = {}
    
    # 1. First extract fallback table
    fallback_match = re.search(r'fallback\s*=\s*\{(.*?)\}', content, re.DOTALL)
    if fallback_match:
        fb_dict = {}
        for m in re.finditer(r'(\w+)\s*=\s*"(.*?)"', fallback_match.group(1)):
            fb_dict[m.group(1)] = m.group(2)
        prompts['fallback'] = fb_dict
        
    # 2. Extract standard string values
    for m in re.finditer(r'(\w+)\s*=\s*"(.*?)"', content):
        if m.group(1) != 'fallback':
            prompts[m.group(1)] = m.group(2)
            
    # 3. Extract block string values [[ ... ]]
    for m in re.finditer(r'(\w+)\s*=\s*\[\[(.*?)\]\]', content, re.DOTALL):
        prompts[m.group(1)] = m.group(2).strip()
        
    return prompts

def save_lua_prompts(file_path, prompts):
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write("return {\n")
        # System instruction
        if 'system_instruction' in prompts:
            f.write(f'    -- System instruction\n    system_instruction = "{prompts["system_instruction"]}",\n\n')
            
        # Write large block prompts
        blocks = ['author_only', 'find_duplicates', 'comprehensive_xray', 'more_characters', 'more_terms', 'single_word_lookup', 'merge_descriptions', 'series_detect', 'prior_book_list', 'series_book_summary']
        for block in blocks:
            if block in prompts:
                title_comment = block.replace('_', ' ').title()
                f.write(f'    -- {title_comment}\n    {block} = [[\n{prompts[block]}]],\n\n')
                
        # Write fallback table
        if 'fallback' in prompts:
            f.write('    -- Fallback strings\n    fallback = {\n')
            fb = prompts['fallback']
            fb_keys = sorted(fb.keys())
            for idx, k in enumerate(fb_keys):
                comma = "," if idx < len(fb_keys) - 1 else ""
                f.write(f'        {k} = "{fb[k]}"{comma}\n')
            f.write('    }\n')
            
        f.write("}\n")

# Validation / Placeholders Auditing
def extract_placeholders(text):
    # Match positional formats first (like %1$s, %2$d)
    pos_formats = re.findall(r'%\d+\$[-+ #0]?\d*\.?\d*[cdeEfgGiouuxXsqp%]', text)
    # Remove positional formats from text to prevent double-matching or partial matching
    clean_text = re.sub(r'%\d+\$[-+ #0]?\d*\.?\d*[cdeEfgGiouuxXsqp%]', '', text)
    # Match standard formats in clean text
    lua_formats = re.findall(r'%[-+ #0]?\d*\.?\d*[cdeEfgGiouuxXsqp%]', clean_text)
    
    braced_tags = re.findall(r'\{[A-Z_0-9]+\}', text)
    
    # Normalize positional formats to standard format (strip index like "1$")
    normalized_pos = [re.sub(r'%(\d+)\$', '%', f) for f in pos_formats]
    
    # Combine and filter out escaped percent signs (%%)
    all_formats = [f for f in (lua_formats + normalized_pos) if f != '%%']
    
    return sorted(all_formats), sorted(braced_tags)

def audit_language(lang_code):
    print(f"=== Auditing Language: {lang_code} ===")
    
    # 1. Audit .po file
    en_po_path = os.path.join(LANGUAGES_DIR, 'en.po')
    target_po_path = os.path.join(LANGUAGES_DIR, f'{lang_code}.po')
    
    en_po = parse_po(en_po_path)
    target_po = parse_po(target_po_path)
    
    en_po_dict = {e['msgid']: e['msgstr'] for e in en_po if e['msgid']}
    target_po_dict = {e['msgid']: e['msgstr'] for e in target_po if e['msgid']}
    
    po_errors = 0
    missing_po_keys = []
    
    for key, en_val in en_po_dict.items():
        if key not in target_po_dict or not target_po_dict[key]:
            missing_po_keys.append(key)
            continue
        
        tr_val = target_po_dict[key]
        
        # Check placeholders
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
            print(f"  ... and {len(missing_po_keys)-10} more.")
            
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
    print(f"PO File: {len(missing_po_keys)} missing keys, {po_errors} placeholder errors.")
    print(f"LUA File: {len(missing_lua_keys)} missing blocks/keys, {lua_errors} placeholder errors.")
    
    if po_errors > 0 or lua_errors > 0 or missing_po_keys or missing_lua_keys:
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
    
    # 1. Translate PO Keys
    missing_po = {}
    for key, val in en_po_dict.items():
        if key not in target_po_dict or not target_po_dict[key] or target_po_dict[key] == key:
            if key != 'language_name':
                missing_po[key] = val

    if missing_po:
        print(f"Translating {len(missing_po)} UI string keys...")
        keys_list = list(missing_po.keys())
        batch_size = 25
        for i in range(0, len(keys_list), batch_size):
            batch_keys = keys_list[i:i+batch_size]
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
            # Save incrementally to prevent losing progress on rate limits
            target_po_dict['language_name'] = lang_name
            save_po(target_po_path, lang_name, lang_code, en_po_dict.keys(), target_po_dict)
            print(f"Saved batch progress to {target_po_path}")
                
        target_po_dict['language_name'] = lang_name
        save_po(target_po_path, lang_name, lang_code, en_po_dict.keys(), target_po_dict)
        print(f"Saved translated UI strings to {target_po_path}")
    else:
        print("All UI strings already translated.")

    # 2. Translate LUA Prompts
    en_lua_path = os.path.join(PROMPTS_DIR, 'en.lua')
    target_lua_path = os.path.join(PROMPTS_DIR, f'{lang_code}.lua')
    
    en_lua = parse_lua_prompts(en_lua_path)
    target_lua = parse_lua_prompts(target_lua_path) if os.path.exists(target_lua_path) else {}
    
    missing_lua = {}
    for k, v in en_lua.items():
        if k == 'fallback':
            if 'fallback' not in target_lua: target_lua['fallback'] = {}
            for fb_k, fb_v in v.items():
                if fb_k not in target_lua['fallback']:
                    missing_lua[f"fallback.{fb_k}"] = fb_v
            continue
        if k not in target_lua:
            missing_lua[k] = v
            
    if missing_lua:
        print(f"Translating {len(missing_lua)} AI Prompt templates...")
        for k, v in missing_lua.items():
            prompt = f"""You are a literary and localization expert. Translate the following X-Ray AI prompt template/instruction or fallback string into {lang_name}.

CRITICAL guidelines:
1. Maintain all placeholders like %s, %d, %1$d, etc. EXACTLY.
2. Maintain all curly braces keys like {{MAX_CHAR_DESC}}, {{NUM_CHARS}}, {{MAX_TIMELINE_EVENT}} EXACTLY.
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
                
        save_lua_prompts(target_lua_path, target_lua)
        print(f"Saved translated prompt templates to {target_lua_path}")
    else:
        print("All LUA prompts already translated.")

def get_supported_languages():
    languages = {}
    for file in os.listdir(LANGUAGES_DIR):
        if file.endswith('.po') and file != 'en.po':
            lang_code = file.split('.')[0]
            path = os.path.join(LANGUAGES_DIR, file)
            lang_name = lang_code.capitalize()
            entries = parse_po(path)
            for e in entries:
                if e['msgid'] == '':
                    m = re.search(r'Language-Team: (.*?)\\n', e['msgstr'])
                    if m: lang_name = m.group(1)
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
