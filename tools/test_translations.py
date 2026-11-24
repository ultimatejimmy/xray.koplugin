import os
import sys
import tempfile
import unittest

TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
if TOOLS_DIR not in sys.path:
    sys.path.insert(0, TOOLS_DIR)

import sync_translations as st
import translate_all as ta


class TestTranslationTooling(unittest.TestCase):
    def test_po_round_trip_escaping_is_idempotent(self):
        samples = [
            'Simple text',
            'Line 1\nLine 2\tTabbed',
            'Button "Find Mentions" and \\backslash\\path',
            'Mixed "quotes", \\n literal slash-n, and\nreal newline',
        ]
        for s in samples:
            encoded = st.encode_po_string(s)
            decoded = st.decode_po_string(encoded)
            self.assertEqual(decoded, s)

        with tempfile.TemporaryDirectory() as tmp:
            po_path = os.path.join(tmp, 'it.po')
            en_final = {'k1': 'Say "Hi"\nNext', 'k2': 'Back\\slash'}
            tr = {'k1': 'Dì "Ciao"\nDopo', 'k2': 'Barra\\inversa'}

            st.save_po(po_path, 'Italian', 'it', en_final.keys(), tr, en_final, en_final)
            with open(po_path, 'rb') as f:
                first_bytes = f.read()

            parsed = {e['msgid']: e['msgstr'] for e in st.parse_po(po_path) if e['msgid']}
            self.assertEqual(parsed, tr)

            st.save_po(po_path, 'Italian', 'it', en_final.keys(), parsed, en_final, en_final)
            with open(po_path, 'rb') as f:
                second_bytes = f.read()
            self.assertEqual(first_bytes, second_bytes)

    def test_english_fallback_detection_and_en_hash_guard(self):
        en_final = {
            'ai_scan': 'AI Scan',
            'ok': 'OK',
            'no': 'No',
            'evolution_title': 'Story Arc: %s',
            'import_file_success': 'Imported %d from %s',
        }
        existing_tr = {
            'ai_scan': 'AI Scan',                  # Untranslated English value
            'ok': 'OK',                            # Universal ALLOWLIST
            'no': 'No',                            # Spanish LANG_ALLOWLIST cognate
            'evolution_title': 'Evolución',        # Missing %s placeholder
            'import_file_success': '%2$s: %1$d',   # Valid positional reorder
        }
        # Even if stored hashes all match English, ai_scan and evolution_title must be flagged
        existing_hashes = {k: st.get_en_hash(v) for k, v in en_final.items()}

        untranslated = st.find_untranslated_keys('es', en_final, existing_tr, existing_hashes)
        self.assertEqual(set(untranslated.keys()), {'ai_scan', 'evolution_title'})

        with tempfile.TemporaryDirectory() as tmp:
            po_path = os.path.join(tmp, 'es.po')
            st.save_po(po_path, 'Spanish', 'es', en_final.keys(), existing_tr, en_final, en_final)
            parsed = {e['msgid']: e for e in st.parse_po(po_path) if e['msgid']}
            self.assertIsNone(parsed['ai_scan']['en_hash'])
            self.assertIsNotNone(parsed['ok']['en_hash'])
            self.assertIsNotNone(parsed['no']['en_hash'])

    def test_extract_keys_precedence_and_multiline_and_prompts_skip(self):
        with tempfile.TemporaryDirectory() as tmp:
            prompts_dir = os.path.join(tmp, 'prompts')
            os.makedirs(prompts_dir)
            with open(os.path.join(prompts_dir, 'en.lua'), 'w', encoding='utf-8') as f:
                f.write('return { dummy = [[loc:t("fake_prompt_key")]] }\n')

            with open(os.path.join(tmp, 'localization_xray.lua'), 'w', encoding='utf-8') as f:
                f.write(
                    'local fallbacks = {\n'
                    '    fetching_author = "Fetching author info from %s...",\n'
                    '    series_context_prompt_text = "Book %d of %s (%d)",\n'
                    '}\n'
                )
            with open(os.path.join(tmp, 'xray_fetch.lua'), 'w', encoding='utf-8') as f:
                f.write(
                    'local a = self.loc:t("fetching_author", "AI") or "Fetching Author..."\n'
                    'local b = self.loc:t("brand_new_key") or "Brand New"\n'
                )
            with open(os.path.join(tmp, 'xray_series_ui.lua'), 'w', encoding='utf-8') as f:
                f.write(
                    'local c = self.loc:t(\n'
                    '    "series_context_prompt_text",\n'
                    '    idx, name, count\n'
                    ')\n'
                )
            with open(os.path.join(tmp, 'xray_updater.lua'), 'w', encoding='utf-8') as f:
                f.write('local d = t("updater_only_key")\n')

            keys, fallback_map, inline = st.extract_keys_from_lua(tmp)
            self.assertNotIn('fake_prompt_key', keys)
            self.assertIn('series_context_prompt_text', keys)
            self.assertIn('updater_only_key', keys)
            self.assertEqual(fallback_map['fetching_author'], 'Fetching author info from %s...')
            self.assertEqual(inline['fetching_author'], 'Fetching author info from %s...')
            self.assertEqual(inline['brand_new_key'], 'Brand New')

    def test_lua_prompts_parse_and_save_preserves_all_blocks(self):
        en_lua_path = os.path.join(ta.PROMPTS_DIR, 'en.lua')
        en_prompts = ta.parse_lua_prompts(en_lua_path)

        # Fallback keys must stay inside 'fallback' and not leak to top-level
        self.assertIn('fallback', en_prompts)
        self.assertNotIn('unknown_book', en_prompts)
        self.assertIn('unknown_book', en_prompts['fallback'])

        for block in ('book_type_detect', 'local_timeline_summary', 'chapter_delta', 'batch_chapter_delta', 'anthology_detect'):
            self.assertIn(block, en_prompts)

        with tempfile.TemporaryDirectory() as tmp:
            out_path = os.path.join(tmp, 'xx.lua')
            sample = dict(en_prompts)
            sample['book_type_detect'] = 'Test with ]] brackets'
            ta.save_lua_prompts(out_path, sample, en_prompts)
            reloaded = ta.parse_lua_prompts(out_path)
            self.assertEqual(set(reloaded.keys()), set(en_prompts.keys()))
            self.assertEqual(reloaded['book_type_detect'], 'Test with ]] brackets')
            self.assertEqual(reloaded['anthology_detect'], en_prompts['anthology_detect'])


if __name__ == '__main__':
    unittest.main()
