#!/usr/bin/env python3
import os
import re
import sys
import json
import urllib.request
import time

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGUAGES_DIR = os.path.join(BASE_DIR, 'xray.koplugin', 'languages')

if sys.version_info >= (3, 7):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

NEW_KEYS = {
    "unit_style_preview_title",
    "unit_underline_solid",
    "unit_underline_wavy",
    "unit_underline_invisible",
    "unit_intensity_light",
    "unit_intensity_medium",
    "unit_intensity_dark",
    "unit_timeout_never",
    "unit_underline_style_label",
    "unit_underline_thickness_label",
    "unit_underline_intensity_label",
    "unit_tooltip_timeout_label"
}

def get_gemini_key():
    return os.environ.get("GEMINI_API_KEY")

def call_gemini(prompt):
    import urllib.error
    key = get_gemini_key()
    if not key:
        print("Error: GEMINI_API_KEY environment variable not set.")
        sys.exit(1)
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent?key={key}"
    headers = {"Content-Type": "application/json"}
    data = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseMimeType": "application/json"}
    }
    
    req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
    
    max_retries = 5
    backoff = 2
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req) as response:
                res_data = json.loads(response.read().decode('utf-8'))
                text = res_data['candidates'][0]['content']['parts'][0]['text']
                time.sleep(2.0)  # Rate limiting safety
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
                print(f"Gemini API returned code {e.code}. Retrying in {sleep_time} seconds...")
                time.sleep(sleep_time)
            else:
                print(f"API Error calling Gemini: {e}")
                sys.exit(1)
        except Exception as e:
            print(f"API Error: {e}")
            sys.exit(1)

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
            escaped_val = val.replace('\n', '\\n').replace('"', '\\"')
            f.write(f'msgid "{key}"\nmsgstr "{escaped_val}"\n\n')

def translate_new_keys():
    print("=== Translating New Unit Converter Keys ===")
    en_po_path = os.path.join(LANGUAGES_DIR, 'en.po')
    en_po = parse_po(en_po_path)
    en_po_dict = {e['msgid']: e['msgstr'] for e in en_po if e['msgid']}
    
    po_files = [f for f in os.listdir(LANGUAGES_DIR) if f.endswith('.po') and not f.startswith('en')]
    
    for file in po_files:
        lang_code = file.split('.')[0]
        path = os.path.join(LANGUAGES_DIR, file)
        entries = parse_po(path)
        
        # Get language name
        lang_name = lang_code.capitalize()
        for e in entries:
            if not e['msgid'] and 'Language-Team:' in e['msgstr']:
                m = re.search(r'Language-Team:\s*(.*?)\\n', e['msgstr'])
                if m: lang_name = m.group(1)
        
        target_po_dict = {e['msgid']: e['msgstr'] for e in entries if e['msgid']}
        
        # Find which of the 24 new keys are untranslated
        untranslated = {}
        for key in NEW_KEYS:
            if key in en_po_dict:
                current_val = target_po_dict.get(key, "")
                # If target value is missing or identical to English value, we need to translate it
                if current_val == "" or current_val == en_po_dict[key] or current_val == key:
                    untranslated[key] = en_po_dict[key]
        
        if untranslated:
            print(f"\nTranslating {len(untranslated)} keys for {lang_name} ({lang_code})...")
            
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
                for k, v in result["translations"].items():
                    target_po_dict[k] = v
                    print(f"  {k} -> {v}")
                
                # Save po file
                save_po(path, lang_name, lang_code, target_po_dict.keys(), target_po_dict)
                print(f"Saved {file}")
            else:
                print(f"Failed to translate for {lang_name}")
        else:
            print(f"All keys already translated for {lang_name}")

if __name__ == "__main__":
    translate_new_keys()
