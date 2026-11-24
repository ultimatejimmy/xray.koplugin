#!/usr/bin/env python3
import os
import re
import sys

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

import sync_translations

# UTF-8 stdout/stderr reconfiguration
if sys.version_info >= (3, 7):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

PLUGIN_DIR = os.path.abspath(os.path.join(TOOLS_DIR, '..', 'xray.koplugin'))
LANGUAGES_DIR = os.path.join(PLUGIN_DIR, 'languages')
SOURCE_DIR = PLUGIN_DIR

UI_WIDGET_PATTERNS = [
    r'TextWidget:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'TextBoxWidget:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'Button:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'InputDialog:new\s*\{[^}]*?title\s*=\s*"([^"]+)"',
    r'InputDialog:new\s*\{[^}]*?description\s*=\s*"([^"]+)"',
    r'InfoMessage:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
    r'ConfirmBox:new\s*\{[^}]*?text\s*=\s*"([^"]+)"',
]

ENCODING_SENSITIVE_KEYS = {
    'progress_please_wait',
}

decode_po_string = sync_translations.decode_po_string
encode_po_string = sync_translations.encode_po_string
format_specifiers = sync_translations.format_specifiers


def discover_languages():
    languages = {}
    for file in sorted(os.listdir(LANGUAGES_DIR)):
        if file.endswith('.po') and file != 'en.po':
            lang_code = file[:-3]
            path = os.path.join(LANGUAGES_DIR, file)
            lang_name = lang_code.capitalize()
            entries = sync_translations.parse_po(path)
            for e in entries:
                if e['msgid'] == '':
                    m = re.search(r'Language-Team:\s*(.+)', e['msgstr'])
                    if m:
                        lang_name = m.group(1).strip()
            languages[lang_code] = lang_name
    return languages


def scan_unwrapped_ui_strings():
    unwrapped = []
    for root, dirs, files in os.walk(SOURCE_DIR):
        dirs[:] = [d for d in sorted(dirs) if d not in ('languages', 'tools', 'spec', 'prompts')]
        for file in sorted(files):
            if file.endswith('.lua') and file != 'localization_xray.lua':
                file_path = os.path.join(root, file)
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    for pat in UI_WIDGET_PATTERNS:
                        for m in re.finditer(pat, content):
                            val = m.group(1)
                            if (len(val) > 2 and not val.endswith('.svg') and not val.endswith('.png')
                                    and not val.endswith('.ttf') and not val.startswith('%')
                                    and not val.startswith('http://') and not val.startswith('https://')
                                    and not val.startswith('www.')):
                                unwrapped.append((file, val))
    return unwrapped


def extract_keys_from_lua():
    res = sync_translations.extract_keys_from_lua()
    if isinstance(res, tuple):
        return res[0]
    return res


def parse_po(file_path):
    entries = sync_translations.parse_po(file_path)
    return {e['msgid']: e['msgstr'] for e in entries}


def run_audit():
    print("==================================================")
    print("       X-RAY TRANSLATION & UI STRING AUDITOR      ")
    print("==================================================\n")

    unwrapped_ui = scan_unwrapped_ui_strings()
    if unwrapped_ui:
        print(f"⚠️ Warning: Found {len(unwrapped_ui)} potentially un-wrapped UI string literals:")
        for fn, s in unwrapped_ui[:10]:
            print(f"   [{fn}] \"{s}\"")
        print()
    else:
        print("✅ 0 Un-wrapped UI String Literals Found!\n")

    used_keys = extract_keys_from_lua()
    print(f"Total Unique Translation Keys Extracted from Lua Source: {len(used_keys)}\n")

    en_path = os.path.join(LANGUAGES_DIR, 'en.po')
    en_entries = parse_po(en_path)
    en_entries.pop("", None)

    missing_in_en = used_keys - set(en_entries.keys())
    if missing_in_en:
        print(f"❌ English Master (en.po) is missing {len(missing_in_en)} keys: {sorted(missing_in_en)}\n")
    else:
        print(f"✅ English Master (en.po) Key Parity: 100% ({len(en_entries)} keys)!\n")

    print("--- Target Language Parity & Completeness Audit ---")
    total_issues = len(missing_in_en)

    for lang_code, lang_name in sorted(discover_languages().items()):
        po_path = os.path.join(LANGUAGES_DIR, f"{lang_code}.po")
        entries = parse_po(po_path)
        entries.pop("", None)

        missing = []
        empty = []
        same_as_en = []
        spec_mismatch = []

        for key in sorted(en_entries.keys()):
            if key == 'language_name':
                continue
            val = entries.get(key, "")
            en_val = en_entries.get(key, key)
            allowed_same = sync_translations.is_allowed_identical(lang_code, key)
            if key not in entries:
                missing.append(key)
            elif not val or val.strip() == "" or (val == key and not allowed_same):
                empty.append(key)
            elif "???" in val and not allowed_same:
                empty.append(key)
            elif key in ENCODING_SENSITIVE_KEYS and "?" in val:
                empty.append(key)
            elif en_val != "" and val == en_val and not allowed_same:
                same_as_en.append(key)
            else:
                en_pl, en_br = sync_translations.extract_placeholders(en_val)
                tr_pl, tr_br = sync_translations.extract_placeholders(val)
                if en_pl != tr_pl or en_br != tr_br:
                    spec_mismatch.append(key)

        issues_count = len(missing) + len(empty) + len(same_as_en) + len(spec_mismatch)
        if issues_count > 0:
            total_issues += issues_count
            print(f"❌ {lang_code}.po ({lang_name}): {len(entries)}/{len(en_entries)} keys | {len(missing)} missing | {len(empty)} empty | {len(same_as_en)} identical-to-EN | {len(spec_mismatch)} format mismatches")
        else:
            print(f"✅ {lang_code}.po ({lang_name}): 100% complete ({len(entries)}/{len(en_entries)} keys)")

    print("\n==================================================")
    if total_issues == 0 and len(unwrapped_ui) == 0:
        print("     AUDIT PASSED: 100% MULTILINGUAL PARITY!       ")
    else:
        print(f"     AUDIT FINISHED: {total_issues + len(unwrapped_ui)} ISSUES REPORTED          ")
    print("==================================================")
    return total_issues + len(unwrapped_ui)


if __name__ == "__main__":
    sys.exit(run_audit())
