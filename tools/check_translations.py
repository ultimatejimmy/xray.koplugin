#!/usr/bin/env python3
import os
import sys

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

import sync_translations as st

LANGUAGES_DIR = st.LANGUAGES_DIR
SOURCE_DIR = st.SOURCE_DIR
MASTER_LANG = st.MASTER_LANG
ALLOWLIST = st.ALLOWLIST
LANG_ALLOWLIST = st.LANG_ALLOWLIST
parse_po = st.parse_po
get_md5 = st.get_md5


def check_translations():
    print("--- Checking Translation Sync Status ---")

    # 1. Scan Source for Used Keys
    used_keys, _, _ = st.extract_keys_from_lua(SOURCE_DIR)
    print(f"Detected {len(used_keys)} keys in source code.")

    # Load English master translations to compute current hashes
    en_path = os.path.join(LANGUAGES_DIR, f'{MASTER_LANG}.po')
    if not os.path.exists(en_path):
        print(f"Error: Master translation file {en_path} not found!")
        sys.exit(1)

    en_entries = parse_po(en_path)
    en_map = {e['msgid']: e['msgstr'] for e in en_entries if e['msgid']}

    missing_in_en = sorted(k for k in used_keys if k not in en_map)
    if missing_in_en:
        print(f"FAILED: {MASTER_LANG}.po is missing {len(missing_in_en)} keys:")
        for k in missing_in_en:
            print(f"      * {k}")
        sys.exit(1)

    # 2. Check each .po file
    failed = False
    po_files = sorted(f for f in os.listdir(LANGUAGES_DIR) if f.endswith('.po') and f != f'{MASTER_LANG}.po')

    for file in po_files:
        lang_code = file[:-3]
        path = os.path.join(LANGUAGES_DIR, file)
        entries = parse_po(path)
        existing_tr = {e['msgid']: e['msgstr'] for e in entries if e['msgid']}
        existing_hashes = {e['msgid']: e['en_hash'] for e in entries if e['msgid']}

        file_failed = False
        missing = []
        empty = []
        stale = []
        same_as_en = []
        placeholder_mismatch = []

        for key in sorted(used_keys):
            if key == "" or key == "language_name":
                continue

            en_val = en_map.get(key, key)
            current_val = existing_tr.get(key)
            stored_hash = existing_hashes.get(key)
            current_hash = st.get_en_hash(en_val)

            if current_val is None:
                missing.append(key)
                file_failed = True
            elif current_val == "" or ((current_val == key or "???" in current_val) and not st.is_allowed_identical(lang_code, key)):
                empty.append(key)
                file_failed = True
            elif stored_hash and stored_hash != current_hash:
                stale.append(f"{key} (hash mismatch: English changed from '{en_val}')")
                file_failed = True
            elif en_val != "" and current_val == en_val and not st.is_allowed_identical(lang_code, key):
                same_as_en.append(key)
                file_failed = True
            else:
                en_pl, en_br = st.extract_placeholders(en_val)
                tr_pl, tr_br = st.extract_placeholders(current_val)
                if en_pl != tr_pl or en_br != tr_br:
                    placeholder_mismatch.append(f"{key} (expected {en_pl}/{en_br}, got {tr_pl}/{tr_br})")
                    file_failed = True

        if file_failed:
            print(f"FAILED: {file}")
            if missing:
                print(f"  - Missing keys ({len(missing)}):")
                for k in missing:
                    print(f"      * {k}")
            if empty:
                print(f"  - Empty or key-fallback translations ({len(empty)}):")
                for k in empty:
                    print(f"      * {k}")
            if stale:
                print(f"  - Stale keys (English content updated since translation) ({len(stale)}):")
                for k in stale:
                    print(f"      * {k}")
            if same_as_en:
                print(f"  - Untranslated keys matching English ({len(same_as_en)}):")
                for k in same_as_en:
                    print(f"      * {k} = '{en_map.get(k)}'")
            if placeholder_mismatch:
                print(f"  - Placeholder mismatches ({len(placeholder_mismatch)}):")
                for k in placeholder_mismatch:
                    print(f"      * {k}")
            failed = True
        else:
            print(f"PASSED: {file}")

    if failed:
        print("\nError: Translation files are out of sync, stale, or contain untranslated English strings.")
        print("Run 'python tools/sync_translations.py' (requires GEMINI_API_KEY) to auto-translate and re-sync.")
        sys.exit(1)

    print("\nAll translation files are correctly synchronized!")
    sys.exit(0)


if __name__ == "__main__":
    check_translations()
