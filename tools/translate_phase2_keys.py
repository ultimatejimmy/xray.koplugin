#!/usr/bin/env python3
import os
import re

LANGUAGES_DIR = os.path.join(os.path.dirname(__file__), '..', 'xray.koplugin', 'languages')

TRANSLATIONS = {
    "ar": {
        "unit_style_preview_title": "معاينة النمط",
        "unit_underline_solid": "صلب",
        "unit_underline_wavy": "متموج",
        "unit_underline_invisible": "غير مرئي",
        "unit_intensity_light": "فاتح",
        "unit_intensity_medium": "متوسط",
        "unit_intensity_dark": "داكن",
        "unit_timeout_never": "أبداً",
        "unit_underline_style_label": "نمط التسطير",
        "unit_underline_thickness_label": "سمك التسطير",
        "unit_underline_intensity_label": "كثافة التسطير",
        "unit_tooltip_timeout_label": "مهلة تلميح الأدوات"
    },
    "de": {
        "unit_style_preview_title": "STIL-VORSCHAU",
        "unit_underline_solid": "Durchgehend",
        "unit_underline_wavy": "Wellig",
        "unit_underline_invisible": "Unsichtbar",
        "unit_intensity_light": "Hell",
        "unit_intensity_medium": "Mittel",
        "unit_intensity_dark": "Dunkel",
        "unit_timeout_never": "Nie",
        "unit_underline_style_label": "Unterstreichungsstil",
        "unit_underline_thickness_label": "Unterstreichungsdicke",
        "unit_underline_intensity_label": "Unterstreichungsintensität",
        "unit_tooltip_timeout_label": "Tooltip-Timeout"
    },
    "es": {
        "unit_style_preview_title": "VISTA PREVIA DE ESTILO",
        "unit_underline_solid": "Sólido",
        "unit_underline_wavy": "Ondulado",
        "unit_underline_invisible": "Invisible",
        "unit_intensity_light": "Claro",
        "unit_intensity_medium": "Medio",
        "unit_intensity_dark": "Oscuro",
        "unit_timeout_never": "Nunca",
        "unit_underline_style_label": "Estilo de subrayado",
        "unit_underline_thickness_label": "Grosor del subrayado",
        "unit_underline_intensity_label": "Intensidad del subrayado",
        "unit_tooltip_timeout_label": "Duración del aviso"
    },
    "fr": {
        "unit_style_preview_title": "APERÇU DU STYLE",
        "unit_underline_solid": "Continu",
        "unit_underline_wavy": "Ondulé",
        "unit_underline_invisible": "Invisible",
        "unit_intensity_light": "Clair",
        "unit_intensity_medium": "Moyen",
        "unit_intensity_dark": "Sombre",
        "unit_timeout_never": "Jamais",
        "unit_underline_style_label": "Style de soulignement",
        "unit_underline_thickness_label": "Épaisseur du soulignement",
        "unit_underline_intensity_label": "Intensité du soulignement",
        "unit_tooltip_timeout_label": "Délai de l'infobulle"
    },
    "hu": {
        "unit_style_preview_title": "STÍLUS ELŐNÉZET",
        "unit_underline_solid": "Folytonos",
        "unit_underline_wavy": "Hullámos",
        "unit_underline_invisible": "Láthatatlan",
        "unit_intensity_light": "Világos",
        "unit_intensity_medium": "Közepes",
        "unit_intensity_dark": "Sötét",
        "unit_timeout_never": "Soha",
        "unit_underline_style_label": "Aláhúzási stílus",
        "unit_underline_thickness_label": "Aláhúzás vastagsága",
        "unit_underline_intensity_label": "Aláhúzás intenzitása",
        "unit_tooltip_timeout_label": "Eszköztipp ideje"
    },
    "id": {
        "unit_style_preview_title": "PRATINJAU GAYA",
        "unit_underline_solid": "Padat",
        "unit_underline_wavy": "Bergelombang",
        "unit_underline_invisible": "Tak Terlihat",
        "unit_intensity_light": "Terang",
        "unit_intensity_medium": "Sedang",
        "unit_intensity_dark": "Gelap",
        "unit_timeout_never": "Jangan Pernah",
        "unit_underline_style_label": "Gaya Garis Bawah",
        "unit_underline_thickness_label": "Ketebalan Garis Bawah",
        "unit_underline_intensity_label": "Intensitas Garis Bawah",
        "unit_tooltip_timeout_label": "Batas Waktu Tooltip"
    },
    "it": {
        "unit_style_preview_title": "ANTEPRIMA STILE",
        "unit_underline_solid": "Solido",
        "unit_underline_wavy": "Ondulato",
        "unit_underline_invisible": "Invisibile",
        "unit_intensity_light": "Chiaro",
        "unit_intensity_medium": "Medio",
        "unit_intensity_dark": "Scuro",
        "unit_timeout_never": "Mai",
        "unit_underline_style_label": "Stile sottolineatura",
        "unit_underline_thickness_label": "Spessore sottolineatura",
        "unit_underline_intensity_label": "Intensità sottolineatura",
        "unit_tooltip_timeout_label": "Timeout info"
    },
    "nl": {
        "unit_style_preview_title": "STIJLVOORBEELD",
        "unit_underline_solid": "Ononderbroken",
        "unit_underline_wavy": "Golvend",
        "unit_underline_invisible": "Onzichtbaar",
        "unit_intensity_light": "Licht",
        "unit_intensity_medium": "Middel",
        "unit_intensity_dark": "Donker",
        "unit_timeout_never": "Nooit",
        "unit_underline_style_label": "Onderstreepstijl",
        "unit_underline_thickness_label": "Onderstreepdikte",
        "unit_underline_intensity_label": "Onderstreepintensiteit",
        "unit_tooltip_timeout_label": "Tooltip time-out"
    },
    "pl": {
        "unit_style_preview_title": "PODGLĄD STYLU",
        "unit_underline_solid": "Ciągła",
        "unit_underline_wavy": "Falista",
        "unit_underline_invisible": "Niewidoczna",
        "unit_intensity_light": "Jasna",
        "unit_intensity_medium": "Średnia",
        "unit_intensity_dark": "Ciemna",
        "unit_timeout_never": "Nigdy",
        "unit_underline_style_label": "Styl podkreślenia",
        "unit_underline_thickness_label": "Grubość podkreślenia",
        "unit_underline_intensity_label": "Intensywność podkreślenia",
        "unit_tooltip_timeout_label": "Czas podpowiedzi"
    },
    "pt_br": {
        "unit_style_preview_title": "PRÉ-VISUALIZAÇÃO DE ESTILO",
        "unit_underline_solid": "Sólido",
        "unit_underline_wavy": "Ondulado",
        "unit_underline_invisible": "Invisível",
        "unit_intensity_light": "Claro",
        "unit_intensity_medium": "Médio",
        "unit_intensity_dark": "Escuro",
        "unit_timeout_never": "Nunca",
        "unit_underline_style_label": "Estilo do sublinhado",
        "unit_underline_thickness_label": "Espessura do sublinhado",
        "unit_underline_intensity_label": "Intensidade do sublinhado",
        "unit_tooltip_timeout_label": "Tempo limite da dica"
    },
    "ru": {
        "unit_style_preview_title": "ПРЕДПРОСМОТР СТИЛЯ",
        "unit_underline_solid": "Сплошная",
        "unit_underline_wavy": "Волнистая",
        "unit_underline_invisible": "Невидимая",
        "unit_intensity_light": "Светлая",
        "unit_intensity_medium": "Средняя",
        "unit_intensity_dark": "Темная",
        "unit_timeout_never": "Никогда",
        "unit_underline_style_label": "Стиль подчеркивания",
        "unit_underline_thickness_label": "Толщина подчеркивания",
        "unit_underline_intensity_label": "Интенсивность подчеркивания",
        "unit_tooltip_timeout_label": "Время подсказки"
    },
    "sr": {
        "unit_style_preview_title": "ПРЕГЛЕД СТИЛА",
        "unit_underline_solid": "Непрекидна",
        "unit_underline_wavy": "Таласаста",
        "unit_underline_invisible": "Невидљива",
        "unit_intensity_light": "Светла",
        "unit_intensity_medium": "Средња",
        "unit_intensity_dark": "Тамна",
        "unit_timeout_never": "Никад",
        "unit_underline_style_label": "Стил подвлачења",
        "unit_underline_thickness_label": "Дебљина подвлачења",
        "unit_underline_intensity_label": "Интензитет подвлачења",
        "unit_tooltip_timeout_label": "Време објашњења"
    },
    "tr": {
        "unit_style_preview_title": "STİL ÖNİZLEME",
        "unit_underline_solid": "Düz",
        "unit_underline_wavy": "Dalgalı",
        "unit_underline_invisible": "Görünmez",
        "unit_intensity_light": "Açık",
        "unit_intensity_medium": "Orta",
        "unit_intensity_dark": "Koyu",
        "unit_timeout_never": "Asla",
        "unit_underline_style_label": "Altı Çizili Stili",
        "unit_underline_thickness_label": "Altı Çizili Kalınlığı",
        "unit_underline_intensity_label": "Altı Çizili Yoğunluğu",
        "unit_tooltip_timeout_label": "İpucu Zamanı"
    },
    "uk": {
        "unit_style_preview_title": "ПЕРЕГЛЯД СТИЛЮ",
        "unit_underline_solid": "Суцільна",
        "unit_underline_wavy": "Хвиляста",
        "unit_underline_invisible": "Невидима",
        "unit_intensity_light": "Світла",
        "unit_intensity_medium": "Середня",
        "unit_intensity_dark": "Темна",
        "unit_timeout_never": "Ніколи",
        "unit_underline_style_label": "Стиль підкреслення",
        "unit_underline_thickness_label": "Товщина підкреслення",
        "unit_underline_intensity_label": "Інтенсивність підкреслення",
        "unit_tooltip_timeout_label": "Час підказки"
    },
    "zh_CN": {
        "unit_style_preview_title": "样式预览",
        "unit_underline_solid": "实线",
        "unit_underline_wavy": "波浪线",
        "unit_underline_invisible": "不可见",
        "unit_intensity_light": "淡",
        "unit_intensity_medium": "中",
        "unit_intensity_dark": "深",
        "unit_timeout_never": "从不",
        "unit_underline_style_label": "下划线样式",
        "unit_underline_thickness_label": "下划线粗细",
        "unit_underline_intensity_label": "下划线深浅",
        "unit_tooltip_timeout_label": "提示框超时"
    }
}

def parse_po(file_path):
    entries = []
    current_entry = {'msgid': '', 'msgstr': '', 'comments': []}
    current_field = None
    if not os.path.exists(file_path): return []
    with open(file_path, 'r', encoding='utf-8') as f:
        for line in f:
            line_str = line.strip()
            if not line_str:
                if current_entry['msgid'] or current_entry['msgstr']:
                    entries.append(current_entry)
                    current_entry = {'msgid': '', 'msgstr': '', 'comments': []}
                current_field = None
                continue
            if line_str.startswith('#'):
                current_entry['comments'].append(line_str)
            elif line_str.startswith('msgid '):
                m = re.match(r'^msgid "(.*)"$', line_str)
                if m:
                    current_entry['msgid'] = m.group(1)
                current_field = 'msgid'
            elif line_str.startswith('msgstr '):
                m = re.match(r'^msgstr "(.*)"$', line_str)
                if m:
                    current_entry['msgstr'] = m.group(1)
                current_field = 'msgstr'
            elif line_str.startswith('"'):
                m = re.match(r'^"(.*)"$', line_str)
                if m:
                    if current_field == 'msgid':
                        current_entry['msgid'] += m.group(1)
                    elif current_field == 'msgstr':
                        current_entry['msgstr'] += m.group(1)
        if current_entry['msgid'] or current_entry['msgstr']:
            entries.append(current_entry)
    return entries

def save_po(file_path, entries):
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write('msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n\n')
        for entry in entries:
            if not entry['msgid']: continue
            for comment in entry['comments']:
                f.write(f"{comment}\n")
            escaped_id = entry['msgid'].replace('"', '\\"')
            escaped_str = entry['msgstr'].replace('"', '\\"')
            f.write(f'msgid "{escaped_id}"\nmsgstr "{escaped_str}"\n\n')

def main():
    print("--- Translating Phase 2 Keys ---")
    for file in os.listdir(LANGUAGES_DIR):
        if file.endswith('.po') and not file.startswith('en'):
            lang_code = file.split('.')[0]
            if lang_code not in TRANSLATIONS:
                continue
            
            path = os.path.join(LANGUAGES_DIR, file)
            entries = parse_po(path)
            
            updated = False
            for entry in entries:
                msgid = entry['msgid']
                if msgid in TRANSLATIONS[lang_code]:
                    entry['msgstr'] = TRANSLATIONS[lang_code][msgid]
                    updated = True
            
            if updated:
                save_po(path, entries)
                print(f"Updated translations in {file}")

if __name__ == '__main__':
    main()
