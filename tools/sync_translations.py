#!/usr/bin/env python3
import os
import re
import sys
import json
import urllib.request
import time

# Configuration
if sys.version_info >= (3, 7):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

LANGUAGES_DIR = os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin', 'languages')
SOURCE_DIR = os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin')
MASTER_LANG = 'en'

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
                if m:
                    current_entry['msgid'] = m.group(1)
                current_field = 'msgid'
            elif line.startswith('msgstr '):
                m = re.match(r'^msgstr "(.*)"$', line)
                if m:
                    current_entry['msgstr'] = m.group(1)
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

def save_po(file_path, lang_name, lang_code, keys, translations, fallback_map):
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(f'msgid ""\nmsgstr ""\n"Language-Team: {lang_name}\\n"\n"Language: {lang_code}\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n')
        for key in sorted(keys):
            if not key: continue
            if lang_code == 'en':
                val = translations.get(key) or fallback_map.get(key) or key
            else:
                val = translations.get(key, "")
            escaped_val = val.replace('\n', '\\n').replace('"', '\\"')
            f.write(f'msgid "{key}"\nmsgstr "{escaped_val}"\n\n')

def get_gemini_key():
    return os.environ.get("GEMINI_API_KEY")

def call_gemini(prompt):
    import urllib.error
    key = get_gemini_key()
    if not key: return None
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key={key}"
    headers = {"Content-Type": "application/json"}
    data = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseMimeType": "application/json"}
    }
    
    req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
    
    max_retries = 3
    backoff = 2
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req) as response:
                res_data = json.loads(response.read().decode('utf-8'))
                text = res_data['candidates'][0]['content']['parts'][0]['text']
                time.sleep(1.0)  # Safe rate limit spacer
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
                time.sleep(sleep_time)
            else:
                print(f"API Error calling Gemini: {e}")
                return None
        except Exception as e:
            print(f"API Error: {e}")
            return None
    return None

def translate_batch(untranslated, lang_name):
    prompt = f"""You are a professional translator. Translate the following key-value pairs for a KOReader e-reader plugin UI into {lang_name}.
Keep translations short, clear, and natural for e-reader menus.

Format rules:
1. Maintain placeholders like %s or %d exactly.
2. Return ONLY a valid JSON object matching the format:
{{
  "translations": {{
    "key1": "translated_val1",
    "key2": "translated_val2"
  }}
}}
Do not add markdown blocks or explanations.

Keys and English values:
{json.dumps(untranslated, indent=2)}
"""
    result = call_gemini(prompt)
    if result and "translations" in result:
        return result["translations"]
    return {}

def sync():
    print("--- Starting Translation Sync ---")
    
    # 1. Scan Source for Used Keys
    used_keys = {} # key -> default_string
    for root, _, files in os.walk(SOURCE_DIR):
        for file in files:
            if file.endswith('.lua'):
                with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    matches = re.finditer(r'loc:t\([\"\']([^\"\']*)[\"\'](?:,\s*.*?)?\)(?:\s*or\s*([\"\'])(.*?)\2)?', content, re.DOTALL)
                    for m in matches:
                        used_keys[m.group(1)] = m.group(3) or used_keys.get(m.group(1), "")
                    if 'localization_xray.lua' in file:
                        fb_matches = re.finditer(r'(\w+)\s*=\s*\"(.*?)\"', content)
                        for m in fb_matches:
                            used_keys[m.group(1)] = m.group(2)

    print(f"Found {len(used_keys)} keys in source code.")

    # 2. Update English Master
    en_path = os.path.join(LANGUAGES_DIR, f'{MASTER_LANG}.po')
    en_entries = parse_po(en_path)
    en_existing = {e['msgid']: e['msgstr'] for e in en_entries if e['msgid']}
    
    en_final = {}
    for key in used_keys:
        code_fallback = used_keys.get(key, "")
        en_final[key] = (code_fallback if code_fallback else en_existing.get(key)) or key
    
    save_po(en_path, 'English', 'en', en_final.keys(), en_final, used_keys)
    print(f"Updated {MASTER_LANG}.po")

    has_gemini = get_gemini_key() is not None
    if not has_gemini:
        print("Warning: GEMINI_API_KEY environment variable not set. New keys will use English fallbacks.")

    # 3. Update Other Languages
    for file in os.listdir(LANGUAGES_DIR):
        if file.endswith('.po') and not file.startswith(MASTER_LANG):
            lang_code = file.split('.')[0]
            path = os.path.join(LANGUAGES_DIR, file)
            entries = parse_po(path)
            
            # Extract Language Name from header
            lang_name = lang_code.capitalize()
            for e in entries:
                if e['msgid'] == '':
                    m = re.search(r'Language-Team: (.*?)\\n', e['msgstr'])
                    if m: lang_name = m.group(1)
            
            existing_tr = {e['msgid']: e['msgstr'] for e in entries if e['msgid'] and e['msgstr']}
            
            # Find missing or untranslated keys
            # A key needs translation if it is missing or is empty
            untranslated = {}
            for key in en_final:
                if key != 'language_name' and key != "":
                    current_val = existing_tr.get(key, "")
                    if current_val == "" or current_val == key:
                        untranslated[key] = en_final[key]
            
            # Run auto-translation if Gemini key is available and there are untranslated keys
            if has_gemini and untranslated:
                print(f"Auto-translating {len(untranslated)} keys for {lang_name} ({lang_code})...")
                translated = translate_batch(untranslated, lang_name)
                for k, v in translated.items():
                    existing_tr[k] = v
            
            # Save po file
            save_po(path, lang_name, lang_code, en_final.keys(), existing_tr, en_final)
            
            missing_count = len([k for k in en_final if k not in existing_tr or existing_tr[k] == ""])
            if lang_code == 'en': missing_count = 0
            print(f"Updated {file} ({missing_count} keys need translation)")

    print("--- Sync Complete ---")

if __name__ == "__main__":
    sync()
