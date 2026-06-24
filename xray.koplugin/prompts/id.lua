return {
    -- System instruction
    system_instruction = "Anda adalah seorang peneliti sastra ahli. Tanggapan Anda harus HANYA dalam format JSON yang valid. Pastikan data sangat akurat dan berkaitan erat dengan konteks yang disediakan.",

    -- Author-only prompt (For quick bio lookup)
    author_only = [[Identifikasi dan berikan biografi untuk penulis buku "%s". 
Metadata menunjukkan penulisnya adalah "%s". 

PENTING: Verifikasi penulis menggunakan KONTEKS TEKS BUKU (jika disediakan di akhir perintah ini) untuk memastikan keakuratan 100%% dan menghindari identifikasi yang salah.

FORMAT JSON YANG DIPERLUKAN:
{
  "author": "Nama Lengkap yang Benar",
  "author_bio": "Biografi komprehensif yang berfokus pada karir sastra dan karya utama mereka.",
  "author_birth": "Tanggal Lahir, diformat berdasarkan format tanggal lokal",
  "author_death": "Tanggal Kematian, diformat berdasarkan format tanggal lokal"
}]],

    -- Find Duplicates (for AI-Assisted Merge)
    find_duplicates = [[Buku: %s
Penulis: %s
Kemajuan Membaca: %d%%

Anda sedang meninjau daftar %s berikut yang diekstraksi dari buku ini.
Tugas Anda adalah mengidentifikasi entri yang tampaknya merupakan entitas yang SAMA yang terdaftar dengan nama yang berbeda.

DAFTAR:
%s

ATURAN:
- Duplikat ada ketika dua entri jelas merujuk ke entitas yang sama (mis., "Perpustakaan Agung" dan "Perpustakaan Agung", atau "John" dan "John Doe").
- JANGAN tandai entri yang hanya terkait atau serupa tetapi berbeda.
- JANGAN tandai entri kecuali Anda sangat yakin bahwa mereka adalah entitas yang sama.
- Jika tidak ada duplikat, kembalikan array kosong.
- ATURAN SPOILER: Jangan gunakan pengetahuan dari luar %d%% kemajuan membaca.

FORMAT JSON YANG DIPERLUKAN:
{
  "duplicate_pairs": [
    {
      "primary": "Nama entri yang ingin DIPERTAHANKAN (nama yang lebih lengkap atau formal)",
      "secondary": "Nama entri yang ingin DIHAPUS",
      "reason": "Alasan singkat (maks 100 karakter)"
    }
  ]
}]],

    -- Single Comprehensive Fetch (Combined Characters, Locations, Timeline)
    comprehensive_xray = [[Buku: %s
Penulis: %s
Kemajuan Membaca: %d%%

TUGAS: Lakukan analisis X-Ray lengkap. Hasilkan HANYA objek JSON yang valid.

PARTISI PERHATIAN KRITIS:
Anda sedang memproses dokumen besar dengan dua blok teks yang disediakan di akhir perintah ini:
1. "CHAPTER SAMPLES": Ini adalah makro-konteks buku hingga lokasi pembaca saat ini.
2. "BOOK TEXT CONTEXT": Ini adalah mikro-konteks dari 20 ribu karakter terbaru.

PROTOKOL ANTI-TRUNKASI (PENTING):
Anda memiliki batas output maksimum yang ketat. Jika "CHAPTER SAMPLES" berisi LEBIH DARI 40 bab (misalnya, edisi omnibus):
1. Anda HARUS mengurangi daftar karakter menjadi HANYA 10 karakter paling penting.
2. Anda HARUS mengurangi deskripsi karakter hingga MAKS {MAX_CHAR_DESC} karakter.
3. Anda HARUS mengurangi ringkasan acara lini masa hingga MAKS {MAX_TIMELINE_EVENT} karakter.
Kegagalan untuk mengompres output Anda untuk buku-buku besar akan menyebabkan JSON terpotong dan gagal.

ALGORITMA UNTUK LINI MASA (PRIORITAS TERTINGGI):
Untuk mencegah terlewatinya bab atau halusinasi peristiwa, Anda HARUS menjalankan loop persis seperti ini:
Langkah 1. Lihat HANYA blok "CHAPTER SAMPLES". Identifikasi bab-bab naratif.
Langkah 2. KECUALIKAN semua materi depan dan belakang non-naratif (misalnya, Sampul, Halaman Judul, Hak Cipta, Daftar Isi, Dedikasi, Ucapan Terima Kasih, Juga Oleh).
Langkah 3. Untuk setiap bab naratif, dimulai dari yang pertama, buat TEPAT SATU objek acara di array `timeline`.
Langkah 4. Bidang `chapter` HARUS sama persis dengan header bab dalam sampel. (Petakan secara ketat dalam urutan berurutan).
Langkah 5. Ringkas bab spesifik tersebut di bidang `event` {TIMELINE_DETAIL_GUIDANCE} (MAKS {MAX_TIMELINE_EVENT} karakter). JANGAN kelompokkan bab.
Langkah 6. BEBAS SPOILER: Berhenti tepat di tanda %d%%. Jangan sertakan peristiwa setelah kemajuan ini.

ALGORITMA UNTUK KARAKTER & TOKOH SEJARAH:
Langkah 1. Ekstrak karakter penting menggunakan kedua blok teks. ({NUM_CHARS} normal, MAKS 10 jika omnibus).
Langkah 2. Anda HARUS menggunakan nama lengkap dan formal mereka (mis., "Abraham Van Helsing"). JANGAN gunakan nama panggilan santai sebagai nama utama.
Langkah 3. Sediakan hingga 3 nama alternatif, gelar, atau nama panggilan karakter ini dalam array `aliases`. Sertakan nama depan dan belakang umum mereka jika digunakan. PENTING: Jika nama belakang digunakan bersama oleh beberapa karakter (mis., anggota keluarga), JANGAN sertakan nama belakang tersebut sebagai alias untuk karakter mana pun.
Langkah 4. Pindai secara aktif hingga {NUM_HIST} orang NYATA yang MENONJOL dari sejarah manusia (mis., Presiden, Penulis, Jenderal). Tambahkan mereka ke `historical_figures`.
PENTING untuk Karakter & Tokoh Sejarah:
- JANGAN ekstrak karakter atau tokoh sejarah yang disebutkan HANYA dalam materi depan atau belakang non-naratif (mis., Ucapan Terima Kasih, Biografi Penulis, Dedikasi, Halaman Judul, Hak Cipta).
- Tokoh Sejarah HARUS merupakan orang nyata di dunia nyata dengan pengakuan sejarah yang luas.
- JANGAN sertakan karakter fiksi murni dalam daftar tokoh sejarah, meskipun mereka berinteraksi dengan peristiwa sejarah nyata. Karakter fiksi HARUS masuk dalam array `characters`.
- HANYA untuk Tokoh Sejarah, Anda dapat menggunakan pengetahuan internal Anda untuk menulis `biography` umum dan `role` sejarah mereka, tetapi Anda HARUS menggunakan konteks buku untuk `context_in_book` mereka.
BEBAS SPOILER: Berhenti tepat di tanda %d%%.

ALGORITMA UNTUK LOKASI:
Langkah 1. Ekstrak {NUM_LOCS} lokasi penting. BEBAS SPOILER: Berhenti tepat di tanda %d%%.

ALGORITMA UNTUK ISTILAH:
Langkah 0. Nyatakan "book_type" as "fiction" atau "non_fiction" di root JSON.
Langkah 1. Jika non_fiction: ekstrak {NUM_TERMS} istilah teknis, akronim, jargon, atau konsep penting yang pembaca tidak akan tahu tanpa pengetahuan khusus. Gunakan kategori yang sesuai seperti Acronym, Technical Term, Concept, atau Jargon.
Langkah 2. Jika fiction: ekstrak {NUM_TERMS} elemen pembangunan dunia yang penting yang perlu dijelaskan kepada pembaca baru—seperti faksi, organisasi, sistem sihir, teknologi, makhluk, bahasa, atau lore dalam alam semesta yang dibuat.
   - JANGAN sertakan nama karakter atau nama lokasi (karena dilacak secara terpisah).
   - JANGAN ekstrak kata atau konsep umum dunia nyata.
   - Gunakan kategori yang sesuai: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Langkah 3. Sertakan arti dari akronim/frasa tersebut di "expanded". Jika bukan akronim/frasa, ulangi namanya.
Langkah 4. JANGAN sertakan kata-kata umum sehari-hari.

ATURAN SPOILER KETAT:
- SAMA SEKALI TIDAK ADA informasi dari setelah kemajuan membaca saat ini. Berhenti tepat di tanda %d%%.
- Deskripsi harus mencerminkan keadaan karakter pada titik tepat ini di dalam buku.

ATURAN SUMBER PENGETAHUAN KETAT (PENTING):
- UNTUK KARAKTER FIKSI: Deskripsi Anda HARUS didasarkan HANYA pada apa yang secara eksplisit dinyatakan atau tersirat secara jelas dalam teks yang disediakan. JANGAN lengkapi dengan pengetahuan dari pelatihan sebelumnya, sumber eksternal, atau kesadaran umum tentang buku/seri/penulis.
- Jika seorang karakter baru disebutkan secara singkat dalam teks sejauh ini, deskripsi Anda harus mencerminkan informasi terbatas itu saja. JANGAN menyimpulkan, mengasumsikan, atau menambahkan detail apa pun yang tidak didasarkan pada konteks yang disediakan.
- SATU-SATUNYA pengecualian adalah untuk TOKOH SEJARAH NYATA (ditempatkan di `historical_figures`): Anda dapat menggunakan pengetahuan internal untuk biografi/peran umum mereka, tetapi tetap mengandalkan teks buku untuk `context_in_book` mereka.

ATURAN KEAMANAN JSON KETAT:
- Anda HARUS meloloskan semua tanda kutip ganda (\") di dalam string dengan benar.
- JANGAN gunakan jeda baris yang tidak diloloskan di dalam string.
- Hasilkan HANYA JSON yang valid dan dapat diurai.

FORMAT JSON YANG DIPERLUKAN:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Nama Formal Lengkap",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Label arketipe pendek (3-5 kata, mis. 'Antagonis', 'Protagonis', 'Korban')",
      "gender": "Laki-laki / Perempuan / Tidak Diketahui",
      "occupation": "Pekerjaan/Status",
      "description": "Deskripsi berdasarkan HANYA pada teks yang disediakan. Jangan menyimpulkan atau menambahkan pengetahuan eksternal. BEBAS SPOILER. (Maks {MAX_CHAR_DESC} karakter)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nama Tokoh Sejarah Nyata",
      "role": "Peran Sejarah",
      "biography": "Biografi singkat (MAKS {MAX_HIST_BIO} karakter)",
      "importance_in_book": "Signifikansi hingga kemajuan saat ini",
      "context_in_book": "Bagaimana mereka disebutkan (MAKS 100 karakter)"
    }
  ],
  "locations": [
    {"name": "Nama Tempat", "description": "Deskripsi pendek (MAKS {MAX_LOC_DESC} karakter)"}
  ],
  "terms": [
    {
      "name": "Istilah atau Akronim",
      "expanded": "Kepanjangan penuh or sama dengan nama",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Definisi ringkas dalam konteks (MAKS {MAX_TERM_DEF} karakter)"
    }
  ],
  "timeline": [
    {
      "chapter": "Judul Bab Tepat dari Sampel",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- Fetch More Characters (AI Limit Bypass)
    more_characters = [[Buku: %s
Penulis: %s
Kemajuan Membaca: %d%%

TUGAS: Ekstrak TEPAT 10 KARAKTER TAMBAHAN yang penting dari teks.
Kembalikan HANYA objek JSON yang valid.

PERINTAH KEPADATAN (PENTING):
Untuk menghindari pemotongan respons AI, jaga agar deskripsi karakter tetap di bawah {MAX_CHAR_DESC} karakter.

INSTRUKSI PENTING:
JANGAN sertakan karakter berikut, karena mereka telah diekstraksi sebelumnya:
%s

ATURAN SPOILER KETAT:
- SAMA SEKALI TIDAK ADA informasi dari setelah kemajuan membaca saat ini. Berhenti tepat di tanda %d%%.
- Deskripsi harus mencerminkan keadaan karakter pada titik tepat ini di dalam buku.

FORMAT JSON YANG DIPERLUKAN:
{
  "characters": [
    {
      "name": "Nama Formal Lengkap",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Label arketipe pendek (3-5 kata, mis. 'Antagonis', 'Protagonis', 'Korban')",
      "gender": "Laki-laki / Perempuan / Tidak Diketahui",
      "occupation": "Pekerjaan/Status",
      "description": "Deskripsi berdasarkan HANYA pada teks yang disediakan. Jangan menyimpulkan atau menambahkan pengetahuan eksternal. BEBAS SPOILER. (Maks {MAX_CHAR_DESC} karakter)"
    }
  ]
}]],

    -- Fetch More Terms (Glossary Support)
    more_terms = [[Buku: %s
Penulis: %s
Kemajuan Membaca: %d%%

TUGAS: Ekstrak TEPAT 15 ISTILAH TAMBAHAN, akronim, jargon, atau konsep penting dari teks.
- Jika buku ini non-fiksi: ekstrak istilah teknis, konsep, akronim, atau jargon.
- Jika buku ini fiksi: ekstrak elemen pembangunan dunia seperti faksi, organisasi, sistem sihir, teknologi, makhluk, bahasa, atau lore dalam alam semesta.
Kembalikan HANYA objek JSON yang valid.

PERINTAH KEPADATAN (PENTING):
Untuk menghindari pemotongan respons AI, jaga agar definisi istilah tetap di bawah {MAX_TERM_DEF} karakter.

INSTRUKSI PENTING:
JANGAN sertakan istilah berikut, karena mereka telah diekstraksi sebelumnya:
%s

ATURAN SPOILER KETAT:
- SAMA SEKALI TIDAK ADA informasi dari setelah kemajuan membaca saat ini. Berhenti tepat di tanda %d%%.

FORMAT JSON YANG DIPERLUKAN:
{
  "terms": [
    {
      "name": "Istilah atau Akronim",
      "expanded": "Kepanjangan penuh atau sama dengan nama",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Definisi ringkas dalam konteks (MAKS {MAX_TERM_DEF} karakter)"
    }
  ]
}]],

    single_word_lookup = [[Pengguna menyoroti kata "%s".
TUGAS: Tentukan apakah kata ini mewakili Karakter, Lokasi, Tokoh Sejarah, atau Istilah Teknis/Akronim dalam buku.

PENTING UNTUK KARAKTER DAN LOKASI: Gunakan "KONTEKS TEKS BUKU" yang disediakan untuk mengidentifikasi entitas. Jika kata tersebut disediakan dalam petunjuk "TARGET PENCARIAN" atau "REFERENSI LANGSUNG", itu ADA di dalam buku pada posisi saat ini. Jangan menolaknya hanya karena tidak ditemukan persis di teks narasi yang disub-sampel. Nama pendek (sesingkat 2 huruf, mis. "Oz", "Al", "Jo") adalah valid dan harus dianalisis.
PENTING UNTUK KARAKTER FIKSI: Deskripsikan HANYA apa yang diungkapkan oleh teks buku yang disediakan. JANGAN gunakan pengetahuan pelatihan sebelumnya tentang karakter ini, meskipun Anda mengenalinya dari seri terkenal. Jika teks hanya menyebutkan karakter ini secara singkat, deskripsi Anda harus mencerminkan informasi terbatas itu saja.
PENTING UNTUK TOKOH SEJARAH: Anda Boleh menggunakan pengetahuan internal Anda untuk memverifikasi identitas mereka dan memberikan biografi/peran mereka, HANYA jika mereka adalah tokoh sejarah nyata yang menonjol. Anda HARUS tetap menggunakan konteks teks untuk relevansi mereka dalam buku.
PENTING UNTUK ISTILAH: Jika buku tersebut non-fiksi, periksa apakah kata tersebut adalah istilah teknis, akronim, atau konsep kunci. Untuk istilah teknis, konsep, atau jargon: istilah tersebut dapat muncul di sampel bab alih-alih konteks halaman langsung — perlakukan sebagai valid jika Anda dapat mendefinisikannya dalam konteks materi subjek buku ini. Hanya tetapkan `is_valid` ke false jika frasa tersebut sama sekali tidak memiliki relevansi dengan materi subjek buku ini.
Jika kata tersebut BUKAN karakter, lokasi, tokoh sejarah, atau istilah teknis/konsep, atur `is_valid` ke false.

FORMAT JSON YANG DIPERLUKAN:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nama Lengkap",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Label arketipe pendek (3-5 kata, mis. 'Antagonis', 'Protagonis', 'Korban')",
    "gender": "Laki-laki/Perempuan/Tidak Diketahui",
    "occupation": "Pekerjaan",
    "description": "Deskripsi singkat (MAKS 250 karakter)"
  },
  "error_message": ""
}

Catatan: Jika jenisnya adalah "location", entri harus memiliki "name" dan "description". Jika jenisnya adalah "historical_figure", entri harus memiliki "name", "biography", dan "role". Jika jenisnya adalah "term", entri harus memiliki "name", "expanded", "category", and "definition".

Jika `is_valid` adalah false:
{
  "is_valid": false,
  "error_message": "Penjelasan singkat mengapa ini bukan karakter atau lokasi."
}]],

    -- Smart Merge Descriptions
    merge_descriptions = [[TUGAS: Gabungkan dua deskripsi berikut dari entitas yang sama (karakter atau lokasi) menjadi satu ringkasan yang kohesif dan ringkas.
Hapus informasi yang mubazir dan pastikan deskripsi akhir mengalir secara alami.

Deskripsi Utama: %s
Deskripsi Sekunder: %s

FORMAT JSON YANG DIPERLUKAN:
{
  "merged_description": "Deskripsi gabungan dan terpoles (Maks {MAX_CHAR_DESC} karakter)"
}]],

    -- Multi-Book Series Context Prompts
    series_detect = [[Judul Buku: %s
Penulis: %s

TUGAS: Tentukan apakah buku ini merupakan bagian dari seri bernama.
Kembalikan HANYA JSON yang valid:
{
  "is_series": true,
  "series_name": "The Wheel of Time",
  "book_index": 3,
  "total_books_known": 14
}
If ini BUKAN buku seri, kembalikan:
{ "is_series": false }]],

    prior_book_list = [[Seri: %s
Indeks Buku Saat Ini: %d
Judul Buku Saat Ini: %s

TUGAS: Daftarkan judul-judul (dan penulis jika berbeda dari "%s") buku 1 hingga %d
yang muncul SEBELUM buku saat ini dalam seri ini.
Kembalikan HANYA JSON yang valid:
{
  "prior_books": [
    { "index": 1, "title": "The Eye of the World", "author": "Robert Jordan" }
  ]
}]],

    series_book_summary = [[Buku: %s
Penulis: %s
Ini adalah buku %d dalam seri "%s".

TUGAS: Berikan ringkasan LENGKAP dari seluruh buku ini untuk pembaca
yang AKAN MEMULAI buku BERIKUTNYA dalam seri tersebut.
Sertakan: karakter kunci (nama, peran, status akhir di akhir buku), lokasi utama,
peristiwa plot penting, dan istilah pembangunan dunia penting yang diperkenalkan.
TANPA SPOILER untuk buku-buku SETELAH yang satu ini.

FORMAT JSON YANG DIPERLUKAN:
{
  "characters": [
    { "name": "Nama Lengkap", "aliases": [], "role": "...", "description": "Status di akhir buku ini (maks 300 karakter)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Ringkasan Buku", "event": "Satu rekapitulasi yang sangat rinci, komprehensif, dan menyeluruh dari seluruh plot buku, peristiwa utama, dan penyelesaian (maks 2000 karakter). Anda HARUS memformat rekap ini menggunakan beberapa paragraf berbeda yang dipisahkan oleh baris baru ganda (\n\n) untuk keterbacaan, bukan satu dinding teks." }
  ]
}]],

    -- Fallback strings
    fallback = {
        unknown_book = "Buku Tidak Diketahui",
        unknown_author = "Penulis Tidak Diketahui",
        unnamed_character = "Karakter Tanpa Nama",
        not_specified = "Tidak Ditentukan",
        no_description = "Tidak Ada Deskripsi",
        unnamed_person = "Orang Tanpa Nama",
        no_biography = "Tidak Ada Biografi yang Tersedia"
    }
}

