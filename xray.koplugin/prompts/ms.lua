return {
    -- Arahan sistem
    system_instruction = "Anda ialah seorang penyelidik sastera yang pakar. Jawapan anda mestilah HANYA dalam format JSON yang sah. Pastikan data adalah sangat tepat dan berpandukan konteks yang diberikan.",

    -- Prom pengarang sahaja (Untuk carian biografi pantas)
    author_only = [[Kenal pasti dan berikan biografi untuk pengarang buku "%s".
Metadata mencadangkan pengarangnya ialah "%s".

KRITIKAL: Sahkan pengarang menggunakan KONTEKS TEKS BUKU (jika disediakan di akhir prom ini) untuk memastikan ketepatan 100%% dan mengelakkan pengenalpastian yang salah.

FORMAT JSON YANG DIPERLUKAN:
{
  "author": "Nama Penuh Sebenar",
  "author_bio": "Biografi komprehensif yang menumpukan pada kerjaya sastera dan karya utama mereka.",
  "author_birth": "Tarikh Lahir, diformatkan mengikut format tarikh tempatan",
  "author_death": "Tarikh Kematian, diformatkan mengikut format tarikh tempatan"
}]],

    -- Cari Pendua (untuk Gabungan Berbantukan AI)
    find_duplicates = [[Buku: %s
Pengarang: %s
Kemajuan Bacaan: %d%%

Anda sedang menyemak senarai %s berikut yang diekstrak daripada buku ini.
Tugas anda ialah mengenal pasti sebarang entri yang jelas merujuk kepada entitas yang SAMA di bawah nama yang berbeza.

SENARAI:
%s

PERATURAN:
- Pendua wujud apabila dua entri jelas merujuk kepada entiti yang sama (cth., "Perpustakaan Besar" dan "The Grand Library", atau "John" dan "John Doe").
- JANGAN tandai entri yang sekadar berkait atau serupa tetapi berbeza orang (cth., "Nick" dan "Ayah Nick" atau "John" dan "Bapa John" ialah dua individu berbeza).
- JANGAN tandai entri melainkan anda sangat yakin bahawa ia adalah entiti yang sama.
- Jika tiada pendua wujud, pulangkan tatasusunan kosong.
- PERATURAN SPOILER: Jangan gunakan pengetahuan melangkaui %d%% kemajuan bacaan.

FORMAT JSON YANG DIPERLUKAN:
{
  "duplicate_pairs": [
    {
      "primary": "Nama entri untuk DIKEKALKAN (nama yang lebih lengkap atau rasmi)",
      "secondary": "Nama entri untuk DIPADAMKAN",
      "reason": "Sebab ringkas (maksimum 100 aksara)"
    }
  ]
}]],

    -- Pengambilan Komprehensif Tunggal (Watak, Lokasi, Garis Masa Gabungan)
    comprehensive_xray = [[Buku: %s
Pengarang: %s
Kemajuan Bacaan: %d%%

TUGASAN: Lakukan analisis X-Ray yang lengkap. Hasilkan HANYA objek JSON yang sah.

PEMBAHAGIAN PERHATIAN KRITIKAL:
Anda sedang memproses dokumen besar dengan dua blok teks yang disediakan di akhir prom ini:
1. "CHAPTER SAMPLES": Ini ialah konteks makro buku sehingga lokasi semasa pembaca.
2. "BOOK TEXT CONTEXT": Ini ialah konteks mikro daripada 20k aksara terkini.

PROTOKOL ANTI-PEMOTONGAN (KRITIKAL):
Anda mempunyai had output maksimum yang ketat. Jika "CHAPTER SAMPLES" mengandungi LEBIH DARIPADA 40 bab (cth., edisi omnibus):
1. Anda MESTI mengurangkan senarai watak kepada HANYA 10 watak paling penting.
2. Anda MESTI mengehadkan penerangan watak kepada MAKSIMUM {MAX_CHAR_DESC} aksara.
3. Anda MESTI mengehadkan ringkasan peristiwa garis masa kepada MAKSIMUM {MAX_TIMELINE_EVENT} aksara.
Kegagalan memampatkan output untuk buku yang besar akan menyebabkan JSON terpotong dan gagal.

ALGORITMA UNTUK GARIS MASA (KEUTAMAAN TERTINGGI):
Untuk mengelakkan bab terlangkau atau peristiwa rekaan, anda MESTI melaksanakan gelung tepat ini:
Langkah 1. Lihat HANYA pada blok "CHAPTER SAMPLES". Kenal pasti bab-bab naratif.
Langkah 2. KECUALIKAN semua bahagian bukan naratif di awal dan akhir buku (cth., Kulit, Halaman Judul, Hak Cipta, Isi Kandungan, Dedikasi, Penghargaan, Karya Lain).
Langkah 3. Bagi setiap bab naratif, bermula dari yang pertama, cipta TEPAT SATU objek peristiwa dalam tatasusunan `timeline`.
Langkah 4. Medan `chapter` MESTI sepadan tepat dengan tajuk bab dalam sampel (susun mengikut turutan).
Langkah 5. Ringkaskan bab tersebut dalam medan `event`. {TIMELINE_DETAIL_GUIDANCE} Tulis antara {MIN_TIMELINE_EVENT} hingga {MAX_TIMELINE_EVENT} aksara. JANGAN tulis ringkasan yang lebih pendek melainkan bab itu hampir tiada kandungan. JANGAN gabungkan bab.
Langkah 6. BEBAS SPOILER: Berhenti tepat pada tanda %d%%. Jangan sertakan peristiwa selepas kemajuan ini.

ALGORITMA UNTUK WATAK & TOKOH SEJARAH:
Langkah 1. Ekstrak watak penting menggunakan kedua-dua blok teks ({NUM_CHARS} biasa, MAKSIMUM 10 jika omnibus). Sentiasa sertakan watak utama / protagonis mengikut nama, walaupun dalam naratif sudut pandang orang pertama ("aku"/"saya") di mana nama mereka jarang disebut.
Langkah 2. Anda MESTI menggunakan nama PENUH dan rasmi mereka (cth., "Abraham Van Helsing"). JANGAN gunakan nama panggilan biasa sebagai nama utama. Jangan sekali-kali menggabungkan atau meletakkan watak di bawah rujukan hubungan/milik (cth., "Ayah Nick" dan "Nick" ialah dua watak berasingan).
Langkah 3. Sediakan sehingga 3 nama alternatif, gelaran, atau nama panggilan watak ini dalam tatasusunan `aliases`. Sertakan nama pertama dan nama keluarga biasa jika digunakan. PENTING: Jika nama keluarga dikongsi oleh beberapa watak (cth., ahli keluarga), JANGAN sertakannya sebagai alias untuk mana-mana watak.
Langkah 4. Imbas secara aktif sehingga {NUM_HIST} tokoh NYATA TERKENAL daripada sejarah manusia (cth., Presiden, Pengarang, Jeneral). Tambah mereka ke `historical_figures`.
KRITIKAL untuk Watak & Tokoh Sejarah:
- JANGAN ekstrak watak atau tokoh sejarah yang disebut HANYA dalam bahagian awal/akhir bukan naratif (cth., Penghargaan, Biografi Pengarang, Dedikasi, Halaman Judul, Hak Cipta).
- Tokoh Sejarah MESTILAH individu nyata dalam dunia sebenar yang mempunyai pengiktirafan sejarah yang luas.
- JANGAN masukkan watak fiksyen tulen ke dalam senarai tokoh sejarah, walaupun mereka berinteraksi dengan peristiwa sejarah sebenar. Watak fiksyen MESTI diletakkan dalam tatasusunan `characters`.
- Untuk Tokoh Sejarah SAHAJA, anda boleh menggunakan pengetahuan dalaman anda untuk menulis `biography` umum dan `role` sejarah mereka, tetapi anda MESTI menggunakan konteks buku untuk `context_in_book` mereka.
BEBAS SPOILER: Berhenti tepat pada tanda %d%%.

ALGORITMA UNTUK LOKASI:
Langkah 1. Ekstrak {NUM_LOCS} lokasi penting. BEBAS SPOILER: Berhenti tepat pada tanda %d%%.

ALGORITMA UNTUK ISTILAH:
Langkah 0. Nyatakan "book_type" sebagai "fiction", "non_fiction", atau "anthology" di akar JSON.
Langkah 1. Jika non_fiction: ekstrak {NUM_TERMS} istilah teknikal, akronim, jargon, atau konsep penting yang sukar difahami pembaca tanpa pengetahuan khusus. Gunakan kategori yang sesuai seperti Akronim, Istilah Teknikal, Konsep, atau Jargon.
Langkah 2. Jika fiction atau anthology: ekstrak {NUM_TERMS} elemen pembinaan dunia yang penting yang perlu dijelaskan kepada pembaca baharu—seperti puak rekaan, organisasi, sistem sihir, teknologi, makhluk, bahasa, atau lore alam cerita.
   - JANGAN sertakan nama watak atau nama lokasi (kerana dijejak secara berasingan).
   - JANGAN ekstrak perkataan atau konsep biasa dunia sebenar.
   - Gunakan kategori yang sesuai: Puak, Sistem Sihir, Teknologi, Makhluk, Organisasi, Lore, Bahasa.
Langkah 3. Sertakan maksud penuh akronim/frasa dalam "expanded". Jika bukan akronim/frasa, ulangi namanya.
Langkah 4. JANGAN sertakan kata-kata harian yang biasa.

PERATURAN SPOILER KETAT:
- SAMA SEKALI TIADA maklumat selepas kemajuan bacaan semasa. Berhenti tepat pada tanda %d%%.
- Penerangan mesti mencerminkan keadaan watak tepat pada tahap ini dalam buku.

PERATURAN SUMBER PENGETAHUAN KETAT (KRITIKAL):
- Untuk WATAK FIKSYEN: Penerangan anda MESTI berdasarkan SEMATA-MATA apa yang dinyatakan secara eksplisit atau tersirat dengan jelas dalam teks yang disediakan. JANGAN tambah dengan pengetahuan daripada latihan terdahulu, sumber luar, atau pengetahuan umum tentang buku/siri/pengarang.
- Jika seseorang watak hanya disebut secara ringkas setakat ini dalam teks, penerangan anda mesti mencerminkan maklumat terhad itu sahaja. JANGAN membuat andaian atau menambah butiran yang tiada dalam konteks yang diberikan.
- SATU-SATUNYA pengecualian ialah untuk TOKOH SEJARAH NYATA (diletakkan dalam `historical_figures`): anda boleh menggunakan pengetahuan dalaman untuk biografi/peranan umum mereka, tetapi tetap gunakan teks buku untuk `context_in_book` mereka.

PERATURAN KESELAMATAN JSON KETAT:
- Anda MESTI melepaskan (escape) semua tanda petik berganda (\") di dalam rentetan dengan betul.
- JANGAN gunakan pemisah baris tanpa escape di dalam rentetan.
- Hasilkan HANYA JSON yang sah dan boleh dihuraikan.

FORMAT JSON YANG DIPERLUKAN:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Nama Rasmi Penuh",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Label arketip ringkas (3-5 patah perkataan, cth. 'Antagonis', 'Protagonis', 'Mangsa')",
      "gender": "Lelaki / Perempuan / Tidak Diketahui",
      "occupation": "Pekerjaan/Status",
      "description": "Penerangan berdasarkan SEMATA-MATA teks yang disediakan. Jangan tambah pengetahuan luar. BEBAS SPOILER. (Maks {MAX_CHAR_DESC} aksara)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nama Tokoh Sejarah Sebenar",
      "role": "Peranan Sejarah",
      "biography": "Biografi ringkas (MAKS {MAX_HIST_BIO} aksara)",
      "importance_in_book": "Kepentingan hingga kemajuan semasa",
      "context_in_book": "Bagaimana mereka disebut (MAKS 100 aksara)"
    }
  ],
  "locations": [
    {"name": "Nama Tempat", "description": "Penerangan ringkas (MAKS {MAX_LOC_DESC} aksara)"}
  ],
  "terms": [
    {
      "name": "Istilah atau Akronim",
      "expanded": "Maksud penuh atau sama seperti nama",
      "category": "Akronim / Istilah Teknikal / Konsep / Jargon",
      "definition": "Definisi ringkas dalam konteks (MAKS {MAX_TERM_DEF} aksara)"
    }
  ],
  "timeline": [
    {
      "chapter": "Tajuk Bab Tepat daripada Sampel",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
} ]],

    -- Ambil Lebih Banyak Watak
    more_characters = [[Buku: %s
Pengarang: %s
Kemajuan Bacaan: %d%%

TUGASAN: Ekstrak TEPAT 10 WATAK TAMBAHAN yang penting daripada teks.
Pulangkan HANYA objek JSON yang sah.

ARAHAN KERINGKASAN (KRITIKAL):
Untuk mengelakkan respons AI terpotong, pastikan penerangan watak di bawah {MAX_CHAR_DESC} aksara.

ARAHAN KRITIKAL:
JANGAN sertakan mana-mana watak berikut kerana ia telah diekstrak:
%s

PERATURAN SPOILER KETAT:
- SAMA SEKALI TIADA maklumat selepas kemajuan bacaan semasa. Berhenti tepat pada tanda %d%%.
- Penerangan mesti mencerminkan keadaan watak tepat pada tahap ini dalam buku.

FORMAT JSON YANG DIPERLUKAN:
{
  "characters": [
    {
      "name": "Nama Rasmi Penuh",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Label arketip ringkas (3-5 patah perkataan, cth. 'Antagonis', 'Protagonis', 'Mangsa')",
      "gender": "Lelaki / Perempuan / Tidak Diketahui",
      "occupation": "Pekerjaan/Status",
      "description": "Penerangan berdasarkan SEMATA-MATA teks yang disediakan. Jangan tambah pengetahuan luar. BEBAS SPOILER. (Maks {MAX_CHAR_DESC} aksara)"
    }
  ]
}]],

    -- Ambil Lebih Banyak Istilah
    more_terms = [[Buku: %s
Pengarang: %s
Kemajuan Bacaan: %d%%

TUGASAN: Ekstrak TEPAT 15 ISTILAH TAMBAHAN, akronim, jargon, atau konsep penting daripada teks.
- Jika buku ini bukan fiksyen: ekstrak istilah teknikal, konsep, akronim, atau jargon.
- Jika buku ini fiksyen: ekstrak elemen pembinaan dunia seperti puak, organisasi, sistem sihir, teknologi, makhluk, bahasa, atau lore alam cerita.
Pulangkan HANYA objek JSON yang sah.

ARAHAN KERINGKASAN (KRITIKAL):
Untuk mengelakkan respons AI terpotong, pastikan definisi istilah di bawah {MAX_TERM_DEF} aksara.

ARAHAN KRITIKAL:
JANGAN sertakan mana-mana istilah berikut kerana ia telah diekstrak:
%s

PERATURAN SPOILER KETAT:
- SAMA SEKALI TIADA maklumat selepas kemajuan bacaan semasa. Berhenti tepat pada tanda %d%%.

FORMAT JSON YANG DIPERLUKAN:
{
  "terms": [
    {
      "name": "Istilah atau Akronim",
      "expanded": "Maksud penuh atau sama seperti nama",
      "category": "Puak / Sistem Sihir / Teknologi / Makhluk / Organisasi / Lore / Bahasa / Akronim / Istilah Teknikal / Konsep / Jargon",
      "definition": "Definisi ringkas dalam konteks (MAKS {MAX_TERM_DEF} aksara)"
    }
  ]
}]],

    single_word_lookup = [[Pengguna menyorot perkataan "%s".
TUGASAN: Tentukan sama ada perkataan ini mewakili Watak, Lokasi, Tokoh Sejarah, atau Istilah Teknikal/Akronim dalam buku.

KRITIKAL UNTUK WATAK DAN LOKASI: Gunakan "BOOK TEXT CONTEXT" yang disediakan untuk mengenal pasti entiti. Jika perkataan ini diberikan dalam petunjuk "SEARCH TARGET" atau "DIRECT REFERENCE", ia MEMANG wujud dalam buku pada kedudukan semasa. Jangan menolaknya hanya kerana ia tidak dijumpai secara tepat dalam petikan teks naratif yang disampel. Nama pendek (sependek 2 huruf, cth. "Oz", "Al", "Jo") adalah sah dan mesti dianalisis.
KRITIKAL UNTUK WATAK FIKSYEN: Terangkan HANYA apa yang didedahkan oleh teks buku yang disediakan. JANGAN gunakan pengetahuan latihan terdahulu mengenai watak ini walaupun anda mengenalinya daripada siri terkenal. Jika teks hanya menyebut watak ini secara ringkas, penerangan anda mesti mencerminkan maklumat terhad itu sahaja.
KRITIKAL UNTUK TOKOH SEJARAH: Anda BOLEH menggunakan pengetahuan dalaman untuk mengesahkan identiti serta memberikan biografi/peranan mereka, HANYA jika mereka merupakan tokoh sejarah sebenar yang terkenal. Anda masih MESTI menggunakan konteks teks untuk kerelevanan mereka dalam buku.
KRITIKAL UNTUK ISTILAH: Jika buku ini bukan fiksyen, semak sama ada perkataan itu ialah istilah teknikal, akronim, atau konsep utama. Bagi istilah teknikal, konsep, atau jargon: istilah tersebut mungkin muncul dalam sampel bab dan bukannya konteks halaman serta-merta — anggap sebagai sah jika anda boleh mentakrifkannya dalam konteks subjek buku ini. Hanya tetapkan `is_valid` kepada false jika frasa itu sama sekali tiada kaitan dengan subjek buku ini.
Jika perkataan ini BUKAN watak, lokasi, tokoh sejarah, atau istilah teknikal/konsep, tetapkan `is_valid` kepada false.

FORMAT JSON YANG DIPERLUKAN:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nama Penuh",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Label arketip ringkas (3-5 patah perkataan, cth. 'Antagonis', 'Protagonis', 'Mangsa')",
    "gender": "Lelaki/Perempuan/Tidak Diketahui",
    "occupation": "Pekerjaan",
    "description": "Penerangan ringkas (MAKS 250 aksara)"
  },
  "error_message": ""
}

Nota: Jika jenisnya ialah "location", item mesti mempunyai "name" dan "description". Jika jenisnya ialah "historical_figure", item mesti mempunyai "name", "biography", dan "role". Jika jenisnya ialah "term", item mesti mempunyai "name", "expanded", "category", dan "definition".

Jika `is_valid` ialah false:
{
  "is_valid": false,
  "error_message": "Penjelasan ringkas mengapa ini bukan watak atau lokasi."
}]],

    -- Gabung Penerangan Pintar
    merge_descriptions = [[TUGASAN: Gabungkan kedua-dua penerangan berikut bagi entiti yang sama (watak atau lokasi) menjadi satu ringkasan yang padu dan ringkas.
Buang maklumat yang berulang dan pastikan penerangan akhir mengalir secara semula jadi.

Penerangan Utama: %s
Penerangan Sekunder: %s

FORMAT JSON YANG DIPERLUKAN:
{
  "merged_description": "Penerangan gabungan yang digilap (Maks {MAX_CHAR_DESC} aksara)"
}]],

    book_type_detect = [[Tajuk Buku: %s
Pengarang: %s
Siri: %s
Metadata Penerangan/Subjek Fail: %s

TUGASAN: Kelaskan buku ini kepada tepat SATU jenis buku berikut berdasarkan metadata dan isyarat genrenya:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Pulangkan HANYA JSON yang sah:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Prom Konteks Siri Pelbagai Buku
    series_detect = [[Tajuk Buku: %s
Pengarang: %s

TUGASAN: Tentukan sama ada buku ini ialah sebahagian daripada suatu siri bernama.
Pulangkan HANYA JSON yang sah:
{
  "is_series": true,
  "series_name": "The Wheel of Time",
  "book_index": 3,
  "total_books_known": 14
}
Jika ini BUKAN buku bersiri, pulangkan:
{ "is_series": false }]],

    prior_book_list = [[Siri: %s
Indeks Buku Semasa: %d
Tajuk Buku Semasa: %s

TUGASAN: Senaraikan tajuk-tajuk (dan pengarang jika berbeza daripada "%s") bagi buku 1 hingga %d
yang hadir SEBELUM buku semasa dalam siri ini.
Pulangkan HANYA JSON yang sah:
{
  "prior_books": [
    { "index": 1, "title": "The Eye of the World", "author": "Robert Jordan" }
  ]
}]],

    series_book_summary = [[BUKU SASARAN: %s
PENGARANG: %s
INDEKS BUKU SASARAN: %d
SIRI: %s

TUGASAN:
Sediakan rumusan LENGKAP bagi BUKU SASARAN sahaja, untuk pembaca yang telah menamatkan
BUKU SASARAN dan akan memulakan buku seterusnya dalam siri ini.

SEMPADAN SPOILER MUTLAK:
Had pengetahuan adalah tepat pada HALAMAN TERAKHIR BUKU SASARAN (Indeks Buku %d).
Anda boleh menyertakan fakta yang telah dibuktikan dalam BUKU SASARAN atau buku terdahulu dalam siri ini.
Anda MESTI TIDAK menyertakan, membayangkan, memberi petunjuk, atau memilih butiran menggunakan pengetahuan daripada mana-mana buku terkemudian.

MAKLUMAT BUKU TERKEMUDIAN YANG DILARANG:
- Peristiwa akan datang, nasib masa depan, kematian, kelangsungan hidup, destinasi, percintaan, pakatan, konflik, atau pengkhianatan.
- Identiti masa depan, asal-usul rahsia, keturunan rahsia, alias, alter ego, penjelmaan semula, transformasi, gelaran, atau peningkatan kuasa daripada buku kemudian.
- Pendedahan, pengesahan, tafsiran semula, kejutan plot, atau istilah pembinaan dunia yang diperkenalkan dalam buku terkemudian.
- Bayangan retrospektif atau frasa seperti "kemudian kelak", "akhirnya", "akan menjadi", "dalam buku seterusnya", atau yang seumpamanya.
- Menyebut watak, konsep, organisasi, atau kronologi daripada buku terkemudian.

HAD WATAK:
Terangkan setiap watak secara ketat setakat yang diketahui pada halaman terakhir BUKU SASARAN.
JANGAN gunakan alias, peranan, hubungan, identiti sebenar, atau status yang hanya didedahkan dalam buku terkemudian.

PERATURAN KETIDAKPASTIAN:
Jika anda tidak pasti sama ada sesuatu fakta atau alias telah didedahkan sebelum tamat BUKU SASARAN, ABAIKANNYA.
Kekurangan butiran jauh lebih baik daripada spoiler buku masa depan.

AUDIT AKHIR:
Sebelum memulangkan JSON, periksa setiap medan (terutamanya penerangan watak dan alias) dan buang apa-apa yang bergantung pada pengetahuan buku selepas BUKU SASARAN.

FORMAT JSON YANG DIPERLUKAN:
{
  "characters": [
    { "name": "Nama Penuh", "aliases": [], "role": "...", "description": "Status pada penghujung buku ini (maks {MAX_CHAR_DESC} aksara)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Ringkasan Buku", "event": "Satu rumusan tunggal yang sangat terperinci dan menyeluruh bagi keseluruhan plot, peristiwa utama, dan peleraian buku ini (maksimum 2000 aksara). Anda MESTI memformat rumusan ini menggunakan beberapa perenggan berasingan yang dipisahkan oleh dua baris baharu (\\n\\n) agar mudah dibaca." }
  ]
}]],

    local_timeline_summary = [[BUKU SASARAN: %s
PENGARANG: %s
INDEKS BUKU SASARAN: %d
SIRI: %s

TUGASAN:
Menggunakan HANYA peristiwa bab demi bab yang disahkan di bawah daripada BUKU SASARAN, tulis satu rumusan yang padu dan menyeluruh mengenai keseluruhan plot, perkembangan utama, dan peleraian buku ini.

KEKANGAN ASAS KETAT:
- Asaskan ringkasan anda SECARA EKSKLUSIF pada peristiwa bab yang diberikan.
- JANGAN perkenalkan fakta, watak, peristiwa, atau hasil yang tidak dihuraikan dalam peristiwa bab ini.
- JANGAN SEKALI-KALI menyebut atau membayangkan peristiwa, kematian, atau perkembangan daripada buku terkemudian dalam siri ini.

PERISTIWA BAB:
%s

FORMAT JSON YANG DIPERLUKAN:
{
  "timeline": [
    { "chapter": "Ringkasan Buku", "event": "Satu rumusan tunggal yang sangat terperinci dan menyeluruh bagi keseluruhan plot dan peleraian buku ini (maksimum 2000 aksara). Anda MESTI memformat rumusan ini menggunakan beberapa perenggan berasingan yang dipisahkan oleh dua baris baharu (\\n\\n) agar mudah dibaca." }
  ]
}]],

    -- Pengekstrakan Delta Bab Tunggal (Horizon Berjujukan & Imbasan Penuh Buku)
    chapter_delta = [[Buku: %s
Pengarang: %s
Menganalisis Bab: %s

TUGASAN: Analisis HANYA bab tunggal ini. Kenal pasti entiti BAHARU yang diperkenalkan dalam bab ini, dan KEMASKINI DELTA (peralihan keadaan) bagi entiti sedia ada.
Hasilkan HANYA objek JSON yang sah.

SENARAI ENTITI DIKETAHUI SEDIA ADA (JANGAN ekstrak semula melainkan peranan, status, atau penerangan mereka berubah secara ketara):
%s

PERATURAN:
1. SEKATAN SPOILER KETAT: Analisis HANYA teks bab yang diberikan. JANGAN gunakan sebarang pengetahuan daripada bab akan datang atau sumber luar.
2. KEDALAMAN & ISI PENERANGAN WATAK (KRITIKAL):
   - Berasas & Spesifik: Terangkan siapa watak itu dengan fakta cerita yang konkrit—latar belakang, keperibadian, pekerjaan, hubungan utama dengan watak lain, serta peranan dan kepentingan peribadi mereka dalam naratif.
   - Konteks Naratif Penting: Hubungkan watak terus kepada misteri utama, konflik plot, atau penyiasatan dalam buku ini.
   - JANGAN Terlalu Umum: Elakkan ungkapan klise kosong. Nyatakan keadaan, hubungan, dan taruhan khusus yang ditetapkan dalam teks.
   - TIADA Catatan Urusan Harian Remeh: JANGAN tulis log kronologi aktiviti harian biasa yang tidak penting.
   - Penerangan watak mestilah profil yang kaya dan jelas merangkumkan siapa mereka serta kepentingan mereka setakat tahap ini dalam buku.
3. AMBANG TINGGI UNTUK KEMASKINI WATAK:
   - JANGAN cipta kemas kini dalam `character_state_updates` hanya kerana watak sedia ada muncul, bercakap, atau melakukan tindakan rutin dalam bab ini.
   - HANYA jana kemas kini jika terdapat transformasi besar yang berkekalan dalam arka naratif, identiti, hubungan, pekerjaan, kesetiaan, atau keadaan mereka (cth. terbunuh, cedera, ditangkap, dikhianati, dinaikkan pangkat, rahsia besar terbongkar).
   - Jika kemas kini WAJAR dilakukan, `description` yang dikemas kini mestilah gambaran kumulatif yang menggabungkan perkembangan baharu sambil mengekalkan identiti teras mereka—BUKAN ringkasan satu adegan terpencil.
4. PENANDA HALAMAN DALAM BAB ([PAGE N]) & PINTU SIFAR SPOILER:
   - Teks bab mengandungi penanda [PAGE N] yang menunjukkan perkembangan halaman.
   - Untuk `new_characters`, `new_locations`, dan `new_terms`: berikan "first_page" (integer N daripada penanda [PAGE N] tempat mula-mula disebut), "intro_role" (untuk watak), dan "intro_description" (1-2 ayat yang dihadkan ketat kepada apa yang diketahui pada pengenalan pertama di [PAGE first_page]—tanpa SEBARANG pengetahuan kejutan atau hasil pada halaman kemudian). Sertakan juga "page" (penanda [PAGE N] di mana "description" penuh terpakai, biasanya halaman terakhir bab).
   - Untuk `character_state_updates`, `location_state_updates`, dan `term_state_updates`: berikan "page" (integer N daripada penanda [PAGE N] tempat peralihan selesai; JANGAN dedahkan fakta sebelum halaman ini).
5. BUKTI: Berikan petikan ringkas daripada bab ini yang menjelaskan sebab kemas kini berlaku.
6. GARIS MASA: Berikan tepat satu ringkasan peristiwa tindakan plot utama dalam bab ini.

FORMAT JSON YANG DIPERLUKAN:
{
  "new_characters": [
    {
      "name": "Nama Penuh",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Peranan awal (cth. Kerani Kampung, Orang Asing, Pelanggan)",
      "intro_description": "Tanggapan awal 1-2 ayat secara ketat pada pengenalan pertama, sifar spoiler daripada halaman kemudian.",
      "page": 99,
      "role": "Peranan naratif / kepentingan (cth. Protagonis, Penyiasat, Antagonis, Watak Sekunder)",
      "status": "alive",
      "description": "Penerangan watak yang kaya dan khusus berdasarkan teks.",
      "evidence": "Petikan ringkas"
    }
  ],
  "character_state_updates": [
    {
      "name": "Nama yang sepadan dengan senarai sedia ada",
      "page": 95,
      "role": "Peranan naratif yang dikemas kini",
      "status": "alive",
      "change": "Satu ayat pendek menyatakan apa yang berubah sejak keadaan sebelumnya",
      "description": "Penerangan kumulatif watak yang dikemas kini mencerminkan status baharu mereka",
      "evidence": "Petikan ringkas"
    }
  ],
  "new_locations": [
    {
      "name": "Nama Lokasi",
      "first_page": 80,
      "intro_description": "Tanggapan awal pada sebutan pertama.",
      "page": 99,
      "description": "Penerangan lokasi",
      "evidence": "Petikan ringkas"
    }
  ],
  "location_state_updates": [
    {
      "name": "Nama yang sepadan dengan senarai sedia ada",
      "page": 95,
      "change": "Satu ayat pendek menyatakan apa yang berubah",
      "description": "Penerangan terkini yang berkembang",
      "evidence": "Petikan ringkas"
    }
  ],
  "new_terms": [
    {
      "name": "Nama Istilah",
      "first_page": 80,
      "intro_description": "Definisi awal pada sebutan pertama.",
      "page": 99,
      "description": "Definisi atau penjelasan lore",
      "evidence": "Petikan ringkas"
    }
  ],
  "term_state_updates": [
    {
      "name": "Nama yang sepadan dengan senarai sedia ada",
      "page": 95,
      "change": "Satu ayat pendek menyatakan perubahan kefahaman atau penggunaan",
      "description": "Definisi dikemas kini",
      "evidence": "Petikan ringkas"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Ringkasan peristiwa dalam bab ini"
  }
}

TEKS BAB:
%s]],

    -- Pengekstrakan Delta Berbilang Bab Berkumpulan
    batch_chapter_delta = [[Buku: %s
Pengarang: %s
Bab dalam Kumpulan Ini: %s

TUGASAN: Analisis kumpulan bab berjujukan yang diberikan mengikut turutan.
Bagi SETIAP bab dalam kumpulan, kenal pasti:
1. Entiti BAHARU yang diperkenalkan dalam bab itu (watak, lokasi, istilah).
2. KEMASKINI DELTA (peralihan keadaan) bagi entiti diketahui sedia ada (daripada senarai ATAU yang diperkenalkan dalam bab lebih awal kumpulan ini) HANYA JIKA peranan, status, kesetiaan, atau keadaan naratif mereka mengalami transformasi besar yang berkekalan.
3. PERISTIWA GARIS MASA: Ringkasan padat perkembangan plot utama yang berlaku dalam bab tersebut.

Pulangkan HANYA objek JSON yang sah mengikut skema yang diperlukan.

SENARAI ENTITI DIKETAHUI SEDIA ADA (daripada kumpulan terdahulu - JANGAN ekstrak semula melainkan peranan, status, atau penerangan mereka berubah secara ketara):
%s

PERATURAN:
1. SEKATAN SPOILER KETAT & TURUTAN BERJUJUKAN:
   - Analisis bab mengikut turutan berjujukan.
   - Bagi mana-mana bab dalam kumpulan ini, JANGAN sertakan pengetahuan daripada bab terkemudian atau bahagian lain buku.
2. KEDALAMAN & ISI PENERANGAN WATAK (KRITIKAL):
   - Berasas & Spesifik dengan fakta cerita konkrit, perhubungan utama, pekerjaan, dan taruhan naratif.
   - Elakkan ungkapan umum kosong atau log aktiviti rutin remeh.
3. AMBANG TINGGI UNTUK KEMASKINI WATAK:
   - HANYA jana kemas kini dalam `character_state_updates` apabila berlaku transformasi besar yang berkekalan.
4. PENANDA HALAMAN DALAM BAB ([PAGE N]) & PINTU SIFAR SPOILER:
   - Berikan "first_page", "intro_role", "intro_description" (tanpa spoiler halaman kemudian), dan "page" untuk entiti baharu, serta "page" untuk kemas kini keadaan.
5. BUKTI: Berikan petikan ringkas daripada bab berkenaan yang menjelaskan kemas kini.
6. KESELAMATAN JSON: Hasilkan JSON yang sah secara ketat dan lepaskan (escape) tanda petik berganda di dalam rentetan.

FORMAT JSON YANG DIPERLUKAN:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Tajuk Bab",
      "timeline_event": "Ringkasan perkembangan plot utama dalam bab ini.",
      "new_characters": [
        {
          "name": "Nama Penuh",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Peranan awal",
          "intro_description": "Tanggapan awal 1-2 ayat secara ketat pada pengenalan pertama, sifar spoiler.",
          "page": 99,
          "role": "Peranan naratif / kepentingan",
          "status": "alive",
          "description": "Penerangan watak yang kaya dan khusus.",
          "evidence": "Petikan ringkas"
        }
      ],
      "character_state_updates": [
        {
          "name": "Nama yang sepadan dengan senarai atau bab terdahulu",
          "page": 95,
          "role": "Peranan naratif dikemas kini",
          "status": "alive",
          "change": "Satu ayat pendek menyatakan apa yang berubah",
          "description": "Penerangan kumulatif watak yang dikemas kini",
          "evidence": "Petikan ringkas"
        }
      ],
      "new_locations": [
        {
          "name": "Nama Lokasi",
          "first_page": 80,
          "intro_description": "Tanggapan awal pada sebutan pertama.",
          "page": 99,
          "description": "Penerangan lokasi",
          "evidence": "Petikan ringkas"
        }
      ],
      "location_state_updates": [
        {
          "name": "Nama yang sepadan dengan senarai atau bab terdahulu",
          "page": 95,
          "change": "Satu ayat pendek menyatakan apa yang berubah",
          "description": "Penerangan dikemas kini",
          "evidence": "Petikan ringkas"
        }
      ],
      "new_terms": [
        {
          "name": "Nama Istilah",
          "first_page": 80,
          "intro_description": "Definisi awal pada sebutan pertama.",
          "page": 99,
          "description": "Definisi atau penjelasan lore",
          "evidence": "Petikan ringkas"
        }
      ],
      "term_state_updates": [
        {
          "name": "Nama yang sepadan dengan senarai atau bab terdahulu",
          "page": 95,
          "change": "Satu ayat pendek menyatakan perubahan kefahaman atau penggunaan",
          "description": "Definisi dikemas kini",
          "evidence": "Petikan ringkas"
        }
      ]
    }
  ]
}

TEKS BAB DALAM KUMPULAN INI:
%s]],

    -- Pengesanan Struktur Antologi
    anthology_detect = [[Analisis butiran buku dan Isi Kandungan berikut:

Tajuk: %s
Pengarang: %s
Subjek: %s
Penerangan: %s

Isi Kandungan:
%s

Tentukan sama ada karya ini ialah:
1. "anthology" (koleksi cerpen, esei, atau novela berasingan, masing-masing dengan naratif atau barisan watak tersendiri).
2. "novel" (sebuah novel tunggal yang dibahagikan kepada bab, bahagian, atau babak).
3. "novel_omnibus" (koleksi pelbagai jilid novel panjang yang diterbitkan bersama dalam satu buku).
4. "non_fiction" (karya bukan fiksyen, sejarah, atau buku akademik tunggal yang dibahagikan kepada bab).

Pulangkan HANYA objek JSON dengan:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 hingga 1.0,
  "reasoning": "penjelasan ringkas (satu ayat)"
}]],

    -- Rentetan sandaran
    fallback = {
        unknown_book = "Buku Tidak Diketahui",
        unknown_author = "Pengarang Tidak Diketahui",
        unnamed_character = "Watak Tanpa Nama",
        not_specified = "Tidak Dinyatakan",
        no_description = "Tiada Penerangan",
        unnamed_person = "Individu Tanpa Nama",
        no_biography = "Tiada Biografi Tersedia"
    }
}
