#!/usr/bin/env python3
import os
import re
import sys
import hashlib

# Configuration
LANGUAGES_DIR = os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin', 'languages')
SOURCE_DIR = os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin')
MASTER_LANG = 'en'

# Narrow allowlist of keys that legitimately don't need translations (symbols, paths, brand names, etc.)
ALLOWLIST = {
    'mention_dismiss_btn',     # "✕"
    'mention_return_btn',      # "← Back"
    'mention_return_label',    # "← Back to p.%d"
    'merge_back',              # "← Back"
    'path',                    # "plugins/xray.koplugin"
    'current_language',        # "en" (or specific code)
    'menu_xray',               # "X-Ray" (brand name)
}

def get_md5(text):
    return hashlib.md5(text.encode('utf-8')).hexdigest()

def parse_po(file_path):
    entries = []
    current_entry = {'msgid': '', 'msgstr': '', 'comments': [], 'en_hash': None}
    current_field = None
    if not os.path.exists(file_path): return []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                if current_entry['msgid'] or current_entry['msgstr']:
                    entries.append(current_entry)
                    current_entry = {'msgid': '', 'msgstr': '', 'comments': [], 'en_hash': None}
                current_field = None
                continue
            if line.startswith('#'):
                current_entry['comments'].append(line)
                m = re.match(r'^#\s*en-hash:\s*([a-f0-9]+)$', line)
                if m:
                    current_entry['en_hash'] = m.group(1)
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

def check_translations():
    print("--- Checking Translation Sync Status ---")
    
    # 1. Scan Source for Used Keys
    used_keys = set()
    for root, _, files in os.walk(SOURCE_DIR):
        for file in files:
            if file.endswith('.lua'):
                with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    # Find loc:t("key")
                    matches = re.finditer(r'loc:t\([\"\']([^\"\']*)[\"\']', content)
                    for m in matches:
                        used_keys.add(m.group(1))
                    # Find fallbacks in localization_xray.lua
                    if 'localization_xray.lua' in file:
                        fb_matches = re.finditer(r'(\w+)\s*=\s*\"', content)
                        for m in fb_matches:
                            used_keys.add(m.group(1))

    print(f"Detected {len(used_keys)} keys in source code.")

    # Load English master translations to compute current hashes
    en_path = os.path.join(LANGUAGES_DIR, f'{MASTER_LANG}.po')
    if not os.path.exists(en_path):
        print(f"Error: Master translation file {en_path} not found!")
        sys.exit(1)
        
    en_entries = parse_po(en_path)
    en_map = {e['msgid']: e['msgstr'] for e in en_entries if e['msgid']}

    # 2. Check each .po file
    failed = False
    po_files = [f for f in os.listdir(LANGUAGES_DIR) if f.endswith('.po')]
    
    for file in sorted(po_files):
        if file.startswith(MASTER_LANG):
            continue
            
        path = os.path.join(LANGUAGES_DIR, file)
        entries = parse_po(path)
        existing_tr = {e['msgid']: e['msgstr'] for e in entries if e['msgid']}
        existing_hashes = {e['msgid']: e['en_hash'] for e in entries if e['msgid']}
        
        file_failed = False
        missing = []
        empty = []
        stale = []
        same_as_en = []
        
        for key in sorted(list(used_keys)):
            if key == "" or key == "language_name":
                continue
                
            en_val = en_map.get(key, key)
            current_val = existing_tr.get(key)
            stored_hash = existing_hashes.get(key)
            current_hash = get_md5(en_val)
            
            if current_val is None:
                missing.append(key)
                file_failed = True
            elif current_val == "":
                empty.append(key)
                file_failed = True
            elif stored_hash and stored_hash != current_hash:
                stale.append(f"{key} (hash mismatch: English changed from '{en_val}')")
                file_failed = True
            elif current_val == en_val and key not in ALLOWLIST:
                same_as_en.append(key)
        
        if file_failed:
            print(f"FAILED: {file}")
            if missing:
                print(f"  - Missing keys ({len(missing)}):")
                for k in missing: print(f"      * {k}")
            if empty:
                print(f"  - Empty translations ({len(empty)}):")
                for k in empty: print(f"      * {k}")
            if stale:
                print(f"  - Stale keys (English content updated since translation) ({len(stale)}):")
                for k in stale: print(f"      * {k}")
            failed = True
        else:
            print(f"PASSED: {file}")
            
        if same_as_en:
            print(f"  - WARNING: {len(same_as_en)} keys match the English value (might need translation):")
            for k in same_as_en:
                print(f"      * {k} = '{en_map.get(k)}'")

    if failed:
        print("\nError: Translation files are out of sync or stale compared to source code and English master.")
        print("Run 'python tools/sync_translations.py' (requires GEMINI_API_KEY) to auto-translate and re-sync.")
        sys.exit(1)
    
    print("\nAll translation files are correctly synchronized!")
    sys.exit(0)

if __name__ == "__main__":
    check_translations()

