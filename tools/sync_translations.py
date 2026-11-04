#!/usr/bin/env python3
import os
import re
import sys
import json
import urllib.request
import time
import hashlib

# Configuration
if sys.version_info >= (3, 7):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

LANGUAGES_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin', 'languages'))
SOURCE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin'))
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

def decode_po_string(s):
    if not s: return ""
    return s.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\')

def encode_po_string(s):
    if not s: return ""
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def format_specifiers(s):
    if not s: return []
    return re.findall(r'%[0-9]*\$?[a-zA-Z]', s)

def extract_keys_from_lua(source_dir=None):
    src = source_dir or SOURCE_DIR
    used_keys = {}  # key -> default_string
    fallback_map = {}
    for root, _, files in os.walk(src):
        if 'languages' in root or 'tools' in root or 'spec' in root:
            continue
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
                            fallback_map[m.group(1)] = m.group(2)
    used_keys.pop("", None)
    return set(used_keys.keys()), fallback_map, used_keys

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
                # Parse English content hash comment
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

def save_po(file_path, lang_name, lang_code, keys, translations, fallback_map, en_final):
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(f'msgid ""\nmsgstr ""\n"Language-Team: {lang_name}\\n"\n"Language: {lang_code}\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n')
        for key in sorted(keys):
            if not key: continue
            if lang_code == 'en':
                val = translations.get(key) or fallback_map.get(key) or key
            else:
                val = translations.get(key, "")
            escaped_val = val.replace('\n', '\\n').replace('"', '\\"')
            
            # For non-English languages, write the hash of the English value we translated from
            if lang_code != 'en':
                en_val = en_final.get(key, "")
                if en_val:
                    f.write(f'# en-hash: {get_md5(en_val)}\n')
            f.write(f'msgid "{key}"\nmsgstr "{escaped_val}"\n\n')

def get_gemini_key():
    return os.environ.get("GEMINI_API_KEY")

def call_gemini(prompt):
    import urllib.error
    key = get_gemini_key()
    if not key: return None
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={key}"
    headers = {"Content-Type": "application/json"}
    data = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseMimeType": "application/json"}
    }
    
    req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
    
    max_retries = 3
    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                res_data = json.loads(response.read().decode('utf-8'))
                text = res_data['candidates'][0]['content']['parts'][0]['text']
                text_stripped = text.strip()
                first_brace = text_stripped.find('{')
                last_brace = text_stripped.rfind('}')
                if first_brace != -1 and last_brace != -1:
                    json_str = text_stripped[first_brace:last_brace+1]
                    return json.loads(json_str)
                return json.loads(text_stripped)
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < max_retries - 1:
                # For 429, respect Retry-After header if present, otherwise use backoff
                if e.code == 429:
                    retry_after = e.headers.get('Retry-After')
                    sleep_time = int(retry_after) if retry_after else 10 * (attempt + 1)
                else:
                    sleep_time = 10 * (attempt + 1)
                print(f"  - HTTP {e.code}, waiting {sleep_time}s before retry {attempt + 1}/{max_retries - 1}...")
                time.sleep(sleep_time)
            else:
                print(f"API Error calling Gemini: {e}")
                return None
        except urllib.error.URLError as e:
            # Covers socket timeouts and connection errors
            print(f"API Connection Error (timeout or network): {e}")
            if attempt < max_retries - 1:
                time.sleep(5)
            else:
                return None
        except Exception as e:
            print(f"API Error: {e}")
            return None
    return None

def translate_all_gemini(all_untranslated, lang_names, max_pairs=50):
    """
    Translates all untranslated keys across all languages in batches.
    all_untranslated: {lang_code: {key: en_val}}
    lang_names: {lang_code: lang_name}
    """
    # Flatten all translation targets to batch them
    flat_pairs = []
    for lang_code, keys in all_untranslated.items():
        for key, en_val in keys.items():
            flat_pairs.append((lang_code, key, en_val))
            
    if not flat_pairs:
        return {}
        
    all_results = {} # lang_code -> {key: translated_val}
    
    # Process flat_pairs in chunks
    for i in range(0, len(flat_pairs), max_pairs):
        chunk = flat_pairs[i:i+max_pairs]
        
        # Group by language code within this chunk to present clean prompt input
        batch_dict = {}
        for lang_code, key, en_val in chunk:
            if lang_code not in batch_dict:
                batch_dict[lang_code] = []
            batch_dict[lang_code].append({"key": key, "english": en_val})
            
        targets = []
        for lang_code, strings in batch_dict.items():
            name = lang_names.get(lang_code, lang_code.capitalize())
            targets.append({
                "language_code": lang_code,
                "language_name": name,
                "strings": strings
            })
            
        prompt = f"""You are a professional translator and localization expert. Translate the following English key-value pairs for a KOReader e-reader plugin UI into their respective target languages.

For each target language, you will receive its language name, language code, and a list of key-value pairs where the values are in English. Translate the English values into the target language, keeping them short, clear, and natural for e-reader menus.

CRITICAL rules:
1. Retain all format specifiers such as %s, %d, %1$s, %2$d, etc. exactly in the translated output.
2. Retain all literal escaped newlines (\\n) and tabs (\\t) exactly.
3. Keep the translation concise, natural, and suited for a mobile e-reader display.
4. Return ONLY a valid JSON object matching this exact schema:
{{
  "translations": {{
    "<language_code>": {{
      "key_name": "translated_value"
    }}
  }}
}}
Do not add markdown blocks, explanations, or backticks.

Target languages and strings to translate:
{json.dumps(targets, indent=2)}
"""
        print(f"  - Requesting translations for batch {i // max_pairs + 1} ({len(chunk)} strings)...")
        result = call_gemini(prompt)
        
        if result and "translations" in result:
            translations = result["translations"]
            for lang_code, tr_map in translations.items():
                if lang_code not in all_results:
                    all_results[lang_code] = {}
                for k, v in tr_map.items():
                    all_results[lang_code][k] = v
        else:
            print(f"  - WARNING: Batch {i // max_pairs + 1} failed or returned invalid response.")
            
        # Short rate-limiting recovery sleep between batches (if multiple exist)
        if i + max_pairs < len(flat_pairs):
            time.sleep(2.0)
            
    return all_results

def manual_translate_languages(all_untranslated, lang_names, all_existing_tr):
    """
    Prompts the user interactively in the terminal to translate keys.
    """
    print("\n=== Interactive Manual Translation ===")
    print("For each language, you can type translations. Press Enter to skip a key.")
    print("Type 'exit' to stop translating and save all progress so far.")
    
    for lang_code in sorted(all_untranslated.keys()):
        keys = all_untranslated[lang_code]
        lang_name = lang_names.get(lang_code, lang_code.capitalize())
        
        print(f"\n--- {lang_name} ({lang_code}) - {len(keys)} keys need translation ---")
        try:
            choice = input(f"Translate keys for {lang_name}? [Y/n/skip-all]: ").strip().lower()
        except (KeyboardInterrupt, EOFError):
            print("\nExiting manual translation mode.")
            break
            
        if choice in ('skip-all', 's'):
            print("Skipping all remaining languages.")
            break
        elif choice == 'n':
            print(f"Skipping {lang_name}.")
            continue
            
        existing_tr = all_existing_tr.get(lang_code, {})
        aborted = False
        
        for idx, (key, en_val) in enumerate(keys.items(), 1):
            print(f"\n[{idx}/{len(keys)}] Key: {key}")
            print(f"      English: {en_val}")
            curr = existing_tr.get(key, "")
            if curr:
                print(f"      Current: {curr}")
            try:
                val = input("      Translation: ").strip()
            except (KeyboardInterrupt, EOFError):
                print("\nExiting manual translation mode.")
                aborted = True
                break
                
            if val.lower() == 'exit':
                print("Exiting manual translation mode.")
                aborted = True
                break
                
            if val:
                existing_tr[key] = val
                print(f"      Saved: {val}")
            else:
                print("      Skipped.")
                
        if aborted:
            break

def sync():
    import argparse
    parser = argparse.ArgumentParser(description="Synchronize and translate KOReader X-Ray plugin localizations.")
    parser.add_argument("-m", "--mode", choices=["auto", "manual", "skip"], help="Translation mode: auto (Gemini), manual (interactive CLI), or skip.")
    args = parser.parse_args()

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
    
    save_po(en_path, 'English', 'en', en_final.keys(), en_final, used_keys, en_final)
    print(f"Updated {MASTER_LANG}.po")

    # 3. Read and Prepare other languages
    lang_files = [f for f in os.listdir(LANGUAGES_DIR) if f.endswith('.po') and not f.startswith(MASTER_LANG)]
    
    lang_names = {}
    all_existing_tr = {}
    all_existing_hashes = {}
    all_untranslated = {}
    
    for file in lang_files:
        lang_code = file.split('.')[0]
        path = os.path.join(LANGUAGES_DIR, file)
        entries = parse_po(path)
        
        # Extract Language Name from header
        lang_name = lang_code.capitalize()
        for e in entries:
            if e['msgid'] == '':
                m = re.search(r'Language-Team: (.*?)\\n', e['msgstr'])
                if m: lang_name = m.group(1)
        
        lang_names[lang_code] = lang_name
        
        existing_tr = {e['msgid']: e['msgstr'] for e in entries if e['msgid'] and e['msgstr']}
        existing_hashes = {e['msgid']: e['en_hash'] for e in entries if e['msgid']}
        
        all_existing_tr[lang_code] = existing_tr
        all_existing_hashes[lang_code] = existing_hashes
        
        # Find missing or untranslated/stale keys
        untranslated = {}
        for key in en_final:
            if key != 'language_name' and key != "":
                current_val = existing_tr.get(key, "")
                en_val = en_final.get(key, "")
                stored_hash = existing_hashes.get(key)
                current_hash = get_md5(en_val) if en_val else None
                
                is_missing = (current_val == "")
                is_fallback = (current_val == key and key not in ALLOWLIST)
                is_stale = (stored_hash and current_hash and stored_hash != current_hash)
                
                if is_missing or is_fallback or is_stale:
                    untranslated[key] = en_val
                    
        if untranslated:
            all_untranslated[lang_code] = untranslated

    # Intercept and translate known keys locally to bypass Gemini API requirement
    local_translations = {
        "ar": {
                "unit_scanning_book": "جاري مسح الكتاب بحثًا عن الوحدات...",
                "unit_scanning_title": "X-Ray: محول الوحدات",
                "btn_paste": "لصق",
                "import_file_not_found": "لم يتم العثور على ملف xray_key.txt في الدليل الجذري أو مجلد الإعدادات.",
                "import_file_success": "تم استيراد %d مفتاح API بنجاح من %s!",
                "key_status_err": "[ERR] فشل: %s",
                "key_status_not_set": "[--] غير مهيأ",
                "key_status_ok": "[OK] متصل (%d مللي ثانية)",
                "menu_import_file": "استيراد المفاتيح من xray_key.txt",
                "menu_paste_clipboard": "لصق مفتاح %s من الحافظة",
                "menu_test_key": "اختبار الاتصال",
                "menu_validate_all_keys": "اختبار والتحقق من جميع مفاتيح API",
                "menu_web_setup": "إعداد مفتاح API عبر الهاتف / الحاسوب (رمز QR)",
                "paste_clipboard_confirm": "هل تريد استخدام مفتاح API الموجود في الحافظة لـ %s؟",
                "testing_api_keys": "جاري اختبار اتصالات مفاتيح API...",
                "validate_keys_title": "حالة والتحقق من مفاتيح API",
                "web_setup_msg": "1. اتصل بنفس شبكة Wi-Fi على هاتفك/حاسوبك.\n2. امسح رمز QR هذا أو زر:\n\n%s\n\n3. الصق مفتاح API واضغط حفظ.",
                "web_setup_no_wifi": "شبكة Wi-Fi غير متصلة. يرجى الاتصال بشبكة Wi-Fi لاستخدام الإعداد عبر الويب.",
                "web_setup_success": "تم استلام وحفظ مفتاح API لـ %s بنجاح!",
                "web_setup_title": "الاتصال عبر الهاتف / الحاسوب"
        },
        "de": {
                "unit_scanning_book": "Buch wird nach Einheiten gescannt...",
                "unit_scanning_title": "X-Ray: Einheitenumrechner",
                "btn_paste": "Einfügen",
                "import_file_not_found": "Keine xray_key.txt Datei im Speicher-Stammverzeichnis oder Einstellungsverzeichnis gefunden.",
                "import_file_success": "%d API-Schlüssel erfolgreich aus %s importiert!",
                "key_status_err": "[ERR] Fehlgeschlagen: %s",
                "key_status_not_set": "[--] Nicht konfiguriert",
                "key_status_ok": "[OK] Verbunden (%d ms)",
                "menu_import_file": "Schlüssel aus xray_key.txt importieren",
                "menu_paste_clipboard": "%s-Schlüssel aus Zwischenablage einfügen",
                "menu_test_key": "Verbindung testen",
                "menu_validate_all_keys": "Alle API-Schlüssel testen & validieren",
                "menu_web_setup": "API-Schlüssel über Smartphone / PC einrichten (QR-Code)",
                "paste_clipboard_confirm": "Den in der Zwischenablage gefundenen API-Schlüssel für %s verwenden?",
                "testing_api_keys": "API-Schlüsselverbindungen werden getestet...",
                "validate_keys_title": "API-Schlüssel-Status & Validierung",
                "web_setup_msg": "1. Verbinden Sie Ihr Smartphone/PC mit demselben WLAN.\n2. Scannen Sie diesen QR-Code oder öffnen Sie:\n\n%s\n\n3. Fügen Sie Ihren API-Schlüssel ein und tippen Sie auf Speichern.",
                "web_setup_no_wifi": "WLAN ist getrennt. Bitte stellen Sie eine WLAN-Verbindung her, um das Web-Setup zu nutzen.",
                "web_setup_success": "API-Schlüssel für %s empfangen und gespeichert!",
                "web_setup_title": "Über Smartphone / PC verbinden"
        },
        "en": {
                "unit_scanning_book": "Scanning book for units...",
                "unit_scanning_title": "X-Ray: Unit Converter",
                "btn_paste": "Paste",
                "import_file_not_found": "No xray_key.txt file found in storage root or settings directory.",
                "import_file_success": "Successfully imported %d API key(s) from %s!",
                "key_status_err": "[ERR] Failed: %s",
                "key_status_not_set": "[--] Not configured",
                "key_status_ok": "[OK] Connected (%d ms)",
                "menu_import_file": "Import Keys from xray_key.txt",
                "menu_paste_clipboard": "Paste %s Key from Clipboard",
                "menu_test_key": "Test Connection",
                "menu_validate_all_keys": "Test & Validate All API Keys",
                "menu_web_setup": "Set API Key from Phone / PC (QR Code)",
                "paste_clipboard_confirm": "Use the API key found in clipboard for %s?",
                "testing_api_keys": "Testing API key connections...",
                "validate_keys_title": "API Key Status & Validation",
                "web_setup_msg": "1. Connect your phone/PC to the same Wi-Fi.\n2. Scan this QR code or visit:\n\n%s\n\n3. Paste your API key and tap Save.",
                "web_setup_no_wifi": "Wi-Fi is disconnected. Please connect to Wi-Fi to use Web Setup.",
                "web_setup_success": "API key for %s received and saved!",
                "web_setup_title": "Connect via Phone / PC"
        },
        "es": {
                "unit_scanning_book": "Escaneando el libro en busca de unidades...",
                "unit_scanning_title": "X-Ray: Conversor de unidades",
                "btn_paste": "Pegar",
                "import_file_not_found": "No se encontró el archivo xray_key.txt en la raíz del almacenamiento ni en los ajustes.",
                "import_file_success": "¡Se importaron correctamente %d clave(s) API desde %s!",
                "key_status_err": "[ERR] Error: %s",
                "key_status_not_set": "[--] No configurado",
                "key_status_ok": "[OK] Conectado (%d ms)",
                "menu_import_file": "Importar claves desde xray_key.txt",
                "menu_paste_clipboard": "Pegar clave de %s del portapapeles",
                "menu_test_key": "Probar conexión",
                "menu_validate_all_keys": "Probar y validar todas las claves API",
                "menu_web_setup": "Configurar clave API desde móvil / PC (código QR)",
                "paste_clipboard_confirm": "¿Usar la clave API encontrada en el portapapeles para %s?",
                "testing_api_keys": "Probando conexiones de claves API...",
                "validate_keys_title": "Estado y validación de claves API",
                "web_setup_msg": "1. Conecta tu móvil/PC a la misma red Wi-Fi.\n2. Escanea este código QR o visita:\n\n%s\n\n3. Pega tu clave API y pulsa Guardar.",
                "web_setup_no_wifi": "Wi-Fi desconectado. Conéctate a una red Wi-Fi para usar la configuración web.",
                "web_setup_success": "¡Clave API para %s recibida y guardada!",
                "web_setup_title": "Conectar mediante móvil / PC"
        },
        "fr": {
                "unit_scanning_book": "Analyse du livre pour les unités...",
                "unit_scanning_title": "X-Ray: Convertisseur d'unités",
                "btn_paste": "Coller",
                "import_file_not_found": "Aucun fichier xray_key.txt trouvé à la racine du stockage ou des paramètres.",
                "import_file_success": "%d clé(s) API importée(s) avec succès depuis %s !",
                "key_status_err": "[ERR] Échec : %s",
                "key_status_not_set": "[--] Non configuré",
                "key_status_ok": "[OK] Connecté (%d ms)",
                "menu_import_file": "Importer les clés depuis xray_key.txt",
                "menu_paste_clipboard": "Coller la clé %s depuis le presse-papiers",
                "menu_test_key": "Tester la connexion",
                "menu_validate_all_keys": "Tester et valider toutes les clés API",
                "menu_web_setup": "Configurer la clé API via smartphone / PC (QR Code)",
                "paste_clipboard_confirm": "Utiliser la clé API trouvée dans le presse-papiers pour %s ?",
                "testing_api_keys": "Test des connexions aux clés API...",
                "validate_keys_title": "Statut et validation des clés API",
                "web_setup_msg": "1. Connectez votre smartphone/PC au même réseau Wi-Fi.\n2. Scannez ce QR code ou visitez :\n\n%s\n\n3. Collez votre clé API et appuyez sur Enregistrer.",
                "web_setup_no_wifi": "Le Wi-Fi est déconnecté. Veuillez vous connecter au Wi-Fi pour utiliser la configuration web.",
                "web_setup_success": "Clé API pour %s reçue et enregistrée !",
                "web_setup_title": "Connexion via smartphone / PC"
        },
        "hu": {
                "unit_scanning_book": "Könyv pásztázása mértékegységekért...",
                "unit_scanning_title": "X-Ray: Mértékegység-átváltó",
                "btn_paste": "Beillesztés",
                "import_file_not_found": "Nem található xray_key.txt fájl a gyökérkönyvtárban vagy a beállításoknál.",
                "import_file_success": "Sikeresen importálva %d API kulcs a(z) %s fájlból!",
                "key_status_err": "[ERR] Sikertelen: %s",
                "key_status_not_set": "[--] Nincs konfigurálva",
                "key_status_ok": "[OK] Csatlakozva (%d ms)",
                "menu_import_file": "Kulcsok importálása az xray_key.txt fájlból",
                "menu_paste_clipboard": "%s kulcs beillesztése a vágólapról",
                "menu_test_key": "Kapcsolat tesztelése",
                "menu_validate_all_keys": "Minden API kulcs tesztelése és érvényesítése",
                "menu_web_setup": "API kulcs beállítása telefonról / PC-ről (QR-kód)",
                "paste_clipboard_confirm": "Használja a vágólapon található API kulcsot a(z) %s szolgáltatáshoz?",
                "testing_api_keys": "API kulcs kapcsolatok tesztelése...",
                "validate_keys_title": "API kulcsok állapota és érvényesítése",
                "web_setup_msg": "1. Csatlakoztassa telefonját/PC-jét ugyanahhoz a Wi-Fi-hez.\n2. Olvassa be ezt a QR-kódot vagy látogasson el ide:\n\n%s\n\n3. Illessze be az API kulcsot, majd koppintson a Mentésre.",
                "web_setup_no_wifi": "Wi-Fi lekapcsolva. A webes beállításhoz kérjük, csatlakozzon Wi-Fi hálózathoz.",
                "web_setup_success": "A(z) %s API kulcsa sikeresen fogadva és mentve!",
                "web_setup_title": "Csatlakozás telefonról / PC-ről"
        },
        "id": {
                "unit_scanning_book": "Memindai buku untuk unit...",
                "unit_scanning_title": "X-Ray: Konverter Satuan",
                "btn_paste": "Tempel",
                "import_file_not_found": "Berkas xray_key.txt tidak ditemukan di penyimpanan utama atau direktori pengaturan.",
                "import_file_success": "Berhasil mengimpor %d kunci API dari %s!",
                "key_status_err": "[ERR] Gagal: %s",
                "key_status_not_set": "[--] Belum dikonfigurasi",
                "key_status_ok": "[OK] Terhubung (%d ms)",
                "menu_import_file": "Impor Kunci dari xray_key.txt",
                "menu_paste_clipboard": "Tempel Kunci %s dari Papan Klip",
                "menu_test_key": "Uji Sambungan",
                "menu_validate_all_keys": "Uji & Validasi Semua Kunci API",
                "menu_web_setup": "Atur Kunci API dari Ponsel / PC (Kode QR)",
                "paste_clipboard_confirm": "Gunakan kunci API dari papan klip untuk %s?",
                "testing_api_keys": "Menguji koneksi kunci API...",
                "validate_keys_title": "Status & Validasi Kunci API",
                "web_setup_msg": "1. Sambungkan ponsel/PC Anda ke Wi-Fi yang sama.\n2. Pindai kode QR ini atau kunjungi:\n\n%s\n\n3. Tempel kunci API dan ketuk Simpan.",
                "web_setup_no_wifi": "Wi-Fi terputus. Harap sambungkan ke Wi-Fi untuk menggunakan Pengaturan Web.",
                "web_setup_success": "Kunci API untuk %s berhasil diterima dan disimpan!",
                "web_setup_title": "Hubungkan via Ponsel / PC"
        },
        "it": {
                "unit_scanning_book": "Scansione del libro per le unità...",
                "unit_scanning_title": "X-Ray: Convertitore di unità",
                "btn_paste": "Incolla",
                "import_file_not_found": "Nessun file xray_key.txt trovato nella root di memoria o nella cartella impostazioni.",
                "import_file_success": "Importate con successo %d chiave/i API da %s!",
                "key_status_err": "[ERR] Fallito: %s",
                "key_status_not_set": "[--] Non configurato",
                "key_status_ok": "[OK] Connesso (%d ms)",
                "menu_import_file": "Importa chiavi da xray_key.txt",
                "menu_paste_clipboard": "Incolla chiave %s dagli appunti",
                "menu_test_key": "Testa connessione",
                "menu_validate_all_keys": "Testa e convalida tutte le chiavi API",
                "menu_web_setup": "Imposta chiave API da smartphone / PC (codice QR)",
                "paste_clipboard_confirm": "Utilizzare la chiave API trovata negli appunti per %s?",
                "testing_api_keys": "Test delle connessioni delle chiavi API in corso...",
                "validate_keys_title": "Stato e convalida chiavi API",
                "web_setup_msg": "1. Connetti smartphone/PC alla stessa rete Wi-Fi.\n2. Scansiona questo codice QR o visita:\n\n%s\n\n3. Incolla la tua chiave API e tocca Salva.",
                "web_setup_no_wifi": "Wi-Fi disconnesso. Connettiti al Wi-Fi per utilizzare la configurazione web.",
                "web_setup_success": "Chiave API per %s ricevuta e salvata!",
                "web_setup_title": "Connetti via smartphone / PC"
        },
        "ja": {
                "unit_scanning_book": "書籍の単位をスキャン中...",
                "unit_scanning_title": "X-Ray: 単位コンバーター",
                "btn_paste": "貼り付け",
                "import_file_not_found": "ストレージルートまたは設定ディレクトリに xray_key.txt が見つかりません。",
                "import_file_success": "%2$s から %1$d 個のAPIキーを正常にインポートしました！",
                "key_status_err": "[ERR] 失敗: %s",
                "key_status_not_set": "[--] 未設定",
                "key_status_ok": "[OK] 接続完了 (%d ms)",
                "menu_import_file": "xray_key.txt からキーをインポート",
                "menu_paste_clipboard": "クリップボードから %s キーを貼り付け",
                "menu_test_key": "接続テスト",
                "menu_validate_all_keys": "すべてのAPIキーをテスト＆検証",
                "menu_web_setup": "スマホ / PC からAPIキーを設定 (QRコード)",
                "paste_clipboard_confirm": "クリップボードのAPIキーを %s に使用しますか？",
                "testing_api_keys": "APIキー接続をテスト中...",
                "validate_keys_title": "APIキーの状態と検証",
                "web_setup_msg": "1. スマホ/PCを同じWi-Fiに接続してください。\n2. このQRコードをスキャンするか以下にアクセスしてください:\n\n%s\n\n3. APIキーを貼り付けて「保存」をタップします。",
                "web_setup_no_wifi": "Wi-Fiが切断されています。Web設定を使用するにはWi-Fiに接続してください。",
                "web_setup_success": "%s のAPIキーを受信して保存しました！",
                "web_setup_title": "スマホ / PC から接続"
        },
        "nl": {
                "unit_scanning_book": "Boek scannen op eenheden...",
                "unit_scanning_title": "X-Ray: Eenhedenomrekenaar",
                "btn_paste": "Plakken",
                "import_file_not_found": "Geen xray_key.txt-bestand gevonden in opslaghoofdmap of instellingenmap.",
                "import_file_success": "Succesvol %d API-sleutel(s) geïmporteerd uit %s!",
                "key_status_err": "[ERR] Mislukt: %s",
                "key_status_not_set": "[--] Niet geconfigureerd",
                "key_status_ok": "[OK] Verbonden (%d ms)",
                "menu_import_file": "Sleutels importeren uit xray_key.txt",
                "menu_paste_clipboard": "%s-sleutel plakken van klembord",
                "menu_test_key": "Verbinding testen",
                "menu_validate_all_keys": "Alle API-sleutels testen & valideren",
                "menu_web_setup": "API-sleutel instellen via telefoon / pc (QR-code)",
                "paste_clipboard_confirm": "De API-sleutel van het klembord gebruiken voor %s?",
                "testing_api_keys": "API-sleutelverbindingen testen...",
                "validate_keys_title": "API-sleutelstatus & validatie",
                "web_setup_msg": "1. Verbind je telefoon/pc met dezelfde wifi.\n2. Scan deze QR-code of ga naar:\n\n%s\n\n3. Plak je API-sleutel en tik op Opslaan.",
                "web_setup_no_wifi": "Wifi is verbroken. Maak verbinding met wifi om Web Setup te gebruiken.",
                "web_setup_success": "API-sleutel voor %s ontvangen en opgeslagen!",
                "web_setup_title": "Verbinden via telefoon / pc"
        },
        "pl": {
                "unit_scanning_book": "Skanowanie książki pod kątem jednostek...",
                "unit_scanning_title": "X-Ray: Konwerter jednostek",
                "btn_paste": "Wklej",
                "import_file_not_found": "Nie znaleziono pliku xray_key.txt w katalogu głównym pamięci ani w ustawieniach.",
                "import_file_success": "Pomyślnie zaimportowano %d klucz(y) API z %s!",
                "key_status_err": "[ERR] Niepowodzenie: %s",
                "key_status_not_set": "[--] Nieskonfigurowane",
                "key_status_ok": "[OK] Połączono (%d ms)",
                "menu_import_file": "Importuj klucze z xray_key.txt",
                "menu_paste_clipboard": "Wklej klucz %s ze schowka",
                "menu_test_key": "Testuj połączenie",
                "menu_validate_all_keys": "Testuj i waliduj wszystkie klucze API",
                "menu_web_setup": "Ustaw klucz API z telefonu / PC (kod QR)",
                "paste_clipboard_confirm": "Użyć klucza API znalezionego w schowku dla %s?",
                "testing_api_keys": "Testowanie połączeń kluczy API...",
                "validate_keys_title": "Status i walidacja kluczy API",
                "web_setup_msg": "1. Połącz telefon/PC z tą samą siecią Wi-Fi.\n2. Zeskanuj ten kod QR lub wejdź na:\n\n%s\n\n3. Wklej klucz API i dotknij Zapisz.",
                "web_setup_no_wifi": "Wi-Fi jest odłączone. Połącz się z Wi-Fi, aby użyć konfiguracji przez przeglądarkę.",
                "web_setup_success": "Klucz API dla %s został odebrany i zapisany!",
                "web_setup_title": "Połącz przez telefon / PC"
        },
        "pt_br": {
                "unit_scanning_book": "Escaneando o livro em busca de unidades...",
                "unit_scanning_title": "X-Ray: Conversor de unidades",
                "btn_paste": "Colar",
                "import_file_not_found": "Nenhum arquivo xray_key.txt encontrado na raiz do armazenamento ou nas configurações.",
                "import_file_success": "%d chave(s) de API importada(s) com sucesso de %s!",
                "key_status_err": "[ERR] Falhou: %s",
                "key_status_not_set": "[--] Não configurado",
                "key_status_ok": "[OK] Conectado (%d ms)",
                "menu_import_file": "Importar chaves de xray_key.txt",
                "menu_paste_clipboard": "Colar chave de %s da área de transferência",
                "menu_test_key": "Testar conexão",
                "menu_validate_all_keys": "Testar e validar todas as chaves de API",
                "menu_web_setup": "Configurar chave de API via celular / PC (código QR)",
                "paste_clipboard_confirm": "Usar a chave de API encontrada na área de transferência para %s?",
                "testing_api_keys": "Testando conexões das chaves de API...",
                "validate_keys_title": "Status e validação de chaves de API",
                "web_setup_msg": "1. Conecte seu celular/PC ao mesmo Wi-Fi.\n2. Escaneie este código QR ou acesse:\n\n%s\n\n3. Cole sua chave de API e toque em Salvar.",
                "web_setup_no_wifi": "Wi-Fi desconectado. Conecte-se ao Wi-Fi para usar a configuração via web.",
                "web_setup_success": "Chave de API para %s recebida e salva!",
                "web_setup_title": "Conectar via celular / PC"
        },
        "ru": {
                "unit_scanning_book": "Сканирование книги на наличие единиц...",
                "unit_scanning_title": "X-Ray: Конвертер величин",
                "btn_paste": "Вставить",
                "import_file_not_found": "Файл xray_key.txt не найден в корневом каталоге или папке настроек.",
                "import_file_success": "Успешно импортировано %d ключ(ей) API из %s!",
                "key_status_err": "[ERR] Ошибка: %s",
                "key_status_not_set": "[--] Не настроено",
                "key_status_ok": "[OK] Подключено (%d мс)",
                "menu_import_file": "Импортировать ключи из xray_key.txt",
                "menu_paste_clipboard": "Вставить ключ %s из буфера обмена",
                "menu_test_key": "Проверить соединение",
                "menu_validate_all_keys": "Проверить и валидировать все ключи API",
                "menu_web_setup": "Настроить ключ API через телефон / ПК (QR-код)",
                "paste_clipboard_confirm": "Использовать ключ API из буфера обмена для %s?",
                "testing_api_keys": "Проверка соединений по ключам API...",
                "validate_keys_title": "Статус и валидация ключей API",
                "web_setup_msg": "1. Подключите телефон/ПК к той же сети Wi-Fi.\n2. Отсканируйте этот QR-код или перейдите по адресу:\n\n%s\n\n3. Вставьте ключ API и нажмите Сохранить.",
                "web_setup_no_wifi": "Wi-Fi отключен. Подключитесь к Wi-Fi для веб-настройки.",
                "web_setup_success": "Ключ API для %s получен и сохранен!",
                "web_setup_title": "Подключение через телефон / ПК",
                "highlight_menu_btn": "Меню выделения",
                "xray_mode_button_label": "Кнопка в меню (по умолчанию)",
                "xray_mode_auto_popup_label": "Авто-всплывание при выделении",
                "xray_mode_about": "Управляет интеграцией X-Ray с выделением текста при чтении:\n\n• [B]Кнопка в меню:[/B] добавляет кнопку «X-Ray» в словарь и меню выделения KOReader.\n• [B]Авто-всплывание при выделении:[/B] мгновенно открывает X-Ray при выборе слова или имени с данными X-Ray, пропуская меню выделения. Если данных нет, открывается обычное меню. Используйте кнопку «Меню выделения» в окне для перехода к выделению или словарю.\n• [B]Отключено:[/B] скрывает кнопки поиска X-Ray в тексте."
        },
        "sk": {
                "highlight_menu_btn": "Ponuka zvýraznenia",
                "xray_mode_button_label": "Tlačidlo v ponuke (predvolené)",
                "xray_mode_auto_popup_label": "Automatické vyskakovacie okno pri zvýraznení",
                "xray_mode_about": "Riadi integráciu X-Ray s výberom textu pri čítaní:\n\n• [B]Tlačidlo v ponuke:[/B] Pridá tlačidlo „X-Ray“ do slovníka a ponuky zvýraznenia KOReaderu.\n• [B]Automatické vyskakovacie okno pri zvýraznení:[/B] Okamžite otvorí X-Ray, keď vyberiete slovo alebo meno s údajmi X-Ray, čím preskočí ponuku zvýraznenia. Ak sa žiadne údaje nezhodujú, zobrazí sa bežná ponuka. Tlačidlo „Ponuka zvýraznenia“ v okne môžete kedykoľvek použiť na zvýraznenie alebo vyhľadanie v slovníku.\n• [B]Zakázané:[/B] Skryje tlačidlá vyhľadávania X-Ray v texte."
        },
        "sr": {
                "unit_scanning_book": "Скенирање књиге за јединице...",
                "unit_scanning_title": "X-Ray: Конвертор јединица",
                "btn_paste": "Налепи",
                "import_file_not_found": "Датотека xray_key.txt није пронађена у корену меморије или директоријуму подешавања.",
                "import_file_success": "Успешно увезено %d API кључ(ева) из %s!",
                "key_status_err": "[ERR] Неуспешно: %s",
                "key_status_not_set": "[--] Није подешено",
                "key_status_ok": "[OK] Повезано (%d ms)",
                "menu_import_file": "Увези кључеве из xray_key.txt",
                "menu_paste_clipboard": "Налепи %s кључ из оставе",
                "menu_test_key": "Тестирај везу",
                "menu_validate_all_keys": "Тестирај и потврди све API кључеве",
                "menu_web_setup": "Подеси API кључ преко телефона / рачунара (QR код)",
                "paste_clipboard_confirm": "Користити API кључ из оставе за %s?",
                "testing_api_keys": "Тестирање веза са API кључевима...",
                "validate_keys_title": "Статус и верификација API кључева",
                "web_setup_msg": "1. Повежите телефон/рачунар на исти Wi-Fi.\n2. Скенирајте овај QR код или посетите:\n\n%s\n\n3. Налепите API кључ и додирните Сачувај.",
                "web_setup_no_wifi": "Wi-Fi је искључен. Повежите се на Wi-Fi да бисте користили веб подешавање.",
                "web_setup_success": "API кључ за %s је примљен и сачуван!",
                "web_setup_title": "Повезивање преко телефона / рачунара",
                "highlight_menu_btn": "Мени истицања",
                "xray_mode_button_label": "Дугме у менију (подразумевано)",
                "xray_mode_auto_popup_label": "Аутоматски искачући прозор при истицању",
                "xray_mode_about": "Контролише интеграцију X-Ray функције са избором текста током читања:\n\n• [B]Дугме у менију:[/B] Додаје дугме „X-Ray“ у речник и мени истицања KOReader-а.\n• [B]Аутоматски искачући прозор при истицању:[/B] Одмах отвара X-Ray када изаберете реч или име које има X-Ray податке, прескачући мени истицања. Ако подаци не постоје, приказује се обичан мени. Дугме „Мени истицања“ у прозору можете користити за претрагу речника или истицање.\n• [B]Онемогућено:[/B] Скрива дугмад за X-Ray у тексту."
        },
        "tr": {
                "unit_scanning_book": "Kitap birimler için taranıyor...",
                "unit_scanning_title": "X-Ray: Birim Dönüştürücü",
                "btn_paste": "Yapıştır",
                "import_file_not_found": "Depolama kök dizininde veya ayarlar klasöründe xray_key.txt dosyası bulunamadı.",
                "import_file_success": "%2$s dosyasından %1$d API anahtarı başarıyla içe aktarıldı!",
                "key_status_err": "[ERR] Başarısız: %s",
                "key_status_not_set": "[--] Yapılandırılmadı",
                "key_status_ok": "[OK] Bağlandı (%d ms)",
                "menu_import_file": "xray_key.txt dosyasından anahtarları içe aktar",
                "menu_paste_clipboard": "Panodan %s anahtarını yapıştır",
                "menu_test_key": "Bağlantıyı Test Et",
                "menu_validate_all_keys": "Tüm API Anahtarlarını Test Et ve Doğrula",
                "menu_web_setup": "Telefondan / PC'den API Anahtarı Ayarla (QR Kod)",
                "paste_clipboard_confirm": "Panodaki API anahtarı %s için kullanılsın mı?",
                "testing_api_keys": "API anahtarı bağlantıları test ediliyor...",
                "validate_keys_title": "API Anahtarı Durumu ve Doğrulama",
                "web_setup_msg": "1. Telefonunuzu/PC'nizi aynı Wi-Fi ağına bağlayın.\n2. Bu QR kodunu tarayın veya şu adrese gidin:\n\n%s\n\n3. API anahtarınızı yapıştırıp Kaydet'e dokunun.",
                "web_setup_no_wifi": "Wi-Fi bağlantısı kesildi. Web kurulumunu kullanmak için lütfen Wi-Fi'ye bağlanın.",
                "web_setup_success": "%s için API anahtarı alındı ve kaydedildi!",
                "web_setup_title": "Telefon / PC ile Bağlan",
                "highlight_menu_btn": "Vurgulama Menüsü",
                "xray_mode_button_label": "Menüde Düğme (Varsayılan)",
                "xray_mode_auto_popup_label": "Vurgulamada Otomatik Açılır Pencere",
                "xray_mode_about": "Okuma sırasında X-Ray'in metin seçimiyle nasıl entegre olacağını kontrol eder:\n\n• [B]Menüde Düğme:[/B] KOReader'ın sözlük ve vurgulama menülerine bir 'X-Ray' düğmesi ekler.\n• [B]Vurgulamada Otomatik Açılır Pencere:[/B] X-Ray verisi olan bir kelime veya isim seçtiğinizde vurgulama menüsünü atlayarak hemen X-Ray penceresini açar. Eşleşen veri yoksa normal menü gösterilir. Sözlükte aramak veya vurgulamak için pencere içindeki 'Vurgulama Menüsü' düğmesini dilediğiniz zaman kullanabilirsiniz.\n• [B]Devre Dışı:[/B] Metin içi X-Ray arama düğmelerini gizler."
        },
        "uk": {
                "unit_scanning_book": "Сканування книги на наявність одиниць...",
                "unit_scanning_title": "X-Ray: Конвертер величин",
                "btn_paste": "Вставити",
                "import_file_not_found": "Файл xray_key.txt не знайдено в кореневому каталозі або папці налаштувань.",
                "import_file_success": "Успішно імпортовано %d ключ(ів) API з %s!",
                "key_status_err": "[ERR] Помилка: %s",
                "key_status_not_set": "[--] Не налаштовано",
                "key_status_ok": "[OK] Підключено (%d мс)",
                "menu_import_file": "Імпортувати ключі з xray_key.txt",
                "menu_paste_clipboard": "Вставити ключ %s з буфера обміну",
                "menu_test_key": "Перевірити з'єднання",
                "menu_validate_all_keys": "Перевірити та валідувати всі ключі API",
                "menu_web_setup": "Налаштувати ключ API через телефон / ПК (QR-код)",
                "paste_clipboard_confirm": "Використати ключ API з буфера обміну для %s?",
                "testing_api_keys": "Перевірка з'єднань ключів API...",
                "validate_keys_title": "Статус та валідація ключів API",
                "web_setup_msg": "1. Підключіть телефон/ПК до тієї ж мережі Wi-Fi.\n2. Відскануйте цей QR-код або перейдіть за адресою:\n\n%s\n\n3. Вставте ключ API та натисніть Зберегти.",
                "web_setup_no_wifi": "Wi-Fi вимкнено. Будь ласка, підключіться до Wi-Fi для веб-налаштування.",
                "web_setup_success": "Ключ API для %s отримано та збережено!",
                "web_setup_title": "Підключення через телефон / ПК",
                "highlight_menu_btn": "Меню виділення",
                "xray_mode_button_label": "Кнопка в меню (типово)",
                "xray_mode_auto_popup_label": "Авто-виринання при виділенні",
                "xray_mode_about": "Керує інтеграцією X-Ray із виділенням тексту під час читання:\n\n• [B]Кнопка в меню:[/B] додає кнопку «X-Ray» до словника та меню виділення KOReader.\n• [B]Авто-виринання при виділенні:[/B] миттєво відкриває X-Ray при виборі слова або імені з даними X-Ray, оминаючи меню виділення. Якщо даних немає, відкривається звичайне меню. Використовуйте кнопку «Меню виділення» у вікні для переходу до виділення або словника.\n• [B]Вимкнено:[/B] приховує кнопки пошуку X-Ray у тексті."
        },
        "zh_CN": {
                "unit_scanning_book": "正在扫描图书中的单位...",
                "unit_scanning_title": "X-Ray: 单位转换器",
                "btn_paste": "粘贴",
                "import_file_not_found": "在存储根目录或设置目录中未找到 xray_key.txt 文件。",
                "import_file_success": "已成功从 %2$s 导入 %1$d 个 API 密钥！",
                "key_status_err": "[ERR] 失败：%s",
                "key_status_not_set": "[--] 未配置",
                "key_status_ok": "[OK] 已连接（%d 毫秒）",
                "menu_import_file": "从 xray_key.txt 导入密钥",
                "menu_paste_clipboard": "从剪贴板粘贴 %s 密钥",
                "menu_test_key": "测试连接",
                "menu_validate_all_keys": "测试并验证所有 API 密钥",
                "menu_web_setup": "通过手机 / 电脑配置 API 密钥（二维码）",
                "paste_clipboard_confirm": "是否将剪贴板中的 API 密钥用于 %s？",
                "testing_api_keys": "正在测试 API 密钥连接...",
                "validate_keys_title": "API 密钥状态与验证",
                "web_setup_msg": "1. 将手机/电脑连接到同一 Wi-Fi 网络。\n2. 扫描此二维码或访问：\n\n%s\n\n3. 粘贴 API 密钥并点击保存。",
                "web_setup_no_wifi": "Wi-Fi 未连接。请连接 Wi-Fi 后使用网页配置。",
                "web_setup_success": "已成功接收并保存 %s 的 API 密钥！",
                "web_setup_title": "通过手机 / 电脑连接",
                "welcome_opt_skip_title": "暂时跳过 (仅使用离线功能)",
                "welcome_opt_skip_desc": "无需 AI，使用本地字数统计、阅读指标及已缓存的系列信息。",
                "ai_scan": "AI 扫描",
                "ask_later": "稍后询问",
                "confirm": "确认",
                "later": "稍后",
                "manual_pick": "手动挑选",
                "merge_button": "合并",
                "new_feature": "新功能",
                "pair_rejected": "已标记此配对不是重复项。",
                "read_more": "阅读更多",
                "reason": "原因",
                "reject_pair": "拒绝",
                "review": "查看",
                "skip": "跳过",
                "stop": "停止",
                "unit_action_configure": "配置设置...",
                "unit_action_disable": "停用功能",
                "unit_action_keep": "保持启用 (默认)",
                "highlight_menu_btn": "高亮菜单",
                "xray_mode_button_label": "菜单按钮 (默认)",
                "xray_mode_auto_popup_label": "划词即弹 X-Ray",
                "xray_mode_about": "控制阅读时划词或选择文本与 X-Ray 的联动方式：\n\n• [B]菜单按钮：[/B]在 KOReader 词典和划词菜单中添加“X-Ray”按钮。\n• [B]划词即弹 X-Ray：[/B]当选择包含 X-Ray 数据的词语或角色名时，跳过划词菜单直接弹出 X-Ray 窗口。若无匹配数据，则显示常规菜单。可在弹窗内随时点击“高亮菜单”进行常规划线高亮或查词典。\n• [B]停用：[/B]隐藏文中选词的 X-Ray 按钮。"
        }
}
    for lang_code, keys in list(all_untranslated.items()):
        if lang_code in local_translations:
            for k in list(keys.keys()):
                if k in local_translations[lang_code]:
                    val = local_translations[lang_code][k]
                    all_existing_tr[lang_code][k] = val
                    del keys[k]
            if not keys:
                del all_untranslated[lang_code]

    # 4. Handle Translations
    mode = args.mode
    has_gemini = get_gemini_key() is not None
    is_interactive = sys.stdin.isatty()
    
    if all_untranslated:
        print("\nMissing or stale translations detected:")
        for lang_code, keys in sorted(all_untranslated.items()):
            name = lang_names.get(lang_code, lang_code.capitalize())
            print(f"  - {name} ({lang_code}): {len(keys)} key(s)")
            
        if not mode:
            if is_interactive:
                print("\nChoose translation method:")
                opt_auto = "[1] Auto-translate with Gemini API" if has_gemini else "[1] (Disabled - GEMINI_API_KEY not set) Auto-translate with Gemini"
                print(f"  {opt_auto}")
                print("  [2] Interactively translate in console")
                print("  [3] Skip translations (leave as fallback/empty)")
                try:
                    choice = input("Enter choice [1/2/3] (default 3): ").strip()
                except (KeyboardInterrupt, EOFError):
                    choice = "3"
                if choice == "1" and has_gemini:
                    mode = "auto"
                elif choice == "2":
                    mode = "manual"
                else:
                    mode = "skip"
            else:
                mode = "auto" if has_gemini else "skip"
                print(f"\nNon-interactive shell. Defaulting to mode: {mode}")
                
        if mode == "auto":
            if not has_gemini:
                print("\nError: GEMINI_API_KEY environment variable is not set. Cannot run auto-translation.")
                if is_interactive:
                    print("Falling back to manual translation mode...")
                    mode = "manual"
                else:
                    print("Skipping translation.")
                    mode = "skip"
                    
        if mode == "auto":
            print(f"\nAuto-translating using Gemini API...")
            translations = translate_all_gemini(all_untranslated, lang_names)
            # Apply translations
            for lang_code, tr_map in translations.items():
                if lang_code in all_existing_tr:
                    for k, v in tr_map.items():
                        all_existing_tr[lang_code][k] = v
                        
        elif mode == "manual":
            manual_translate_languages(all_untranslated, lang_names, all_existing_tr)
            
        elif mode == "skip":
            print("\nSkipping translations. Saving updated keys with fallbacks.")
    else:
        print("\nAll translation files are up to date.")

    # 5. Save all files
    for file in lang_files:
        lang_code = file.split('.')[0]
        path = os.path.join(LANGUAGES_DIR, file)
        lang_name = lang_names[lang_code]
        existing_tr = all_existing_tr[lang_code]
        
        save_po(path, lang_name, lang_code, en_final.keys(), existing_tr, en_final, en_final)
        
        missing_count = len([k for k in en_final if k not in existing_tr or existing_tr[k] == ""])
        print(f"Updated {file} ({missing_count} keys need translation)")

    print("--- Sync Complete ---")

if __name__ == "__main__":
    sync()

