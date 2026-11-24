return {
    -- Author Only
    author_only = [[
Identifikasi dan berikan biografi untuk penulis buku "%s". 
Metadata menunjukkan penulisnya adalah "%s". 

PENTING: Verifikasi penulis menggunakan KONTEKS TEKS BUKU (jika disediakan di akhir perintah ini) untuk memastikan keakuratan 100%% dan menghindari identifikasi yang salah.

FORMAT JSON YANG DIPERLUKAN:
{
  "author": "Nama Lengkap yang Benar",
  "author_bio": "Biografi komprehensif yang berfokus pada karir sastra dan karya utama mereka.",
  "author_birth": "Tanggal Lahir, diformat berdasarkan format tanggal lokal",
  "author_death": "Tanggal Kematian, diformat berdasarkan format tanggal lokal"
}]],

    -- Find Duplicates
    find_duplicates = [[
Buku: %s
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

    -- Comprehensive Xray
    comprehensive_xray = [[
Buku: %s
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
Langkah 5. Ringkas bab spesifik tersebut di bidang `event`. {TIMELINE_DETAIL_GUIDANCE} Tulis antara {MIN_TIMELINE_EVENT} dan {MAX_TIMELINE_EVENT} karakter. JANGAN tulis ringkasan yang lebih pendek kecuali bab tersebut hampir tidak memiliki konten. JANGAN kelompokkan bab.
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

    -- More Characters
    more_characters = [[
Buku: %s
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

    -- More Terms
    more_terms = [[
Buku: %s
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

    -- Single Word Lookup
    single_word_lookup = [[
Pengguna menyoroti kata "%s".
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

    -- Merge Descriptions
    merge_descriptions = [[
TUGAS: Gabungkan dua deskripsi berikut dari entitas yang sama (karakter atau lokasi) menjadi satu ringkasan yang kohesif dan ringkas.
Hapus informasi yang mubazir dan pastikan deskripsi akhir mengalir secara alami.

Deskripsi Utama: %s
Deskripsi Sekunder: %s

FORMAT JSON YANG DIPERLUKAN:
{
  "merged_description": "Deskripsi gabungan dan terpoles (Maks {MAX_CHAR_DESC} karakter)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Judul Buku: %s
Penulis: %s
Seri: %s
Deskripsi File/Metadata Subjek: %s

TUGAS: Klasifikasikan buku ini ke dalam tepat SATU dari jenis buku berikut berdasarkan metadata dan sinyal genrenya:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Kembalikan HANYA JSON yang valid:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Judul Buku: %s
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

    -- Prior Book List
    prior_book_list = [[
Seri: %s
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

    -- Series Book Summary
    series_book_summary = [[
BUKU TARGET: %s
PENULIS: %s
INDEKS BUKU TARGET: %d
SERI: %s

TUGAS:
Berikan rekap LENGKAP khusus untuk BUKU TARGET saja, bagi pembaca yang telah selesai membaca
BUKU TARGET dan akan memulai buku berikutnya dalam seri ini.

BATAS SPOILER MUTLAK:
Batas pengetahuan secara ketat adalah HALAMAN TERAKHIR dari BUKU TARGET (Indeks Buku %d).
Anda boleh menyertakan fakta yang telah ditetapkan dalam BUKU TARGET atau buku-buku sebelumnya dalam seri ini.
Anda DILARANG menyertakan, menyiratkan, memberi petunjuk, membayangi (foreshadow), atau memilih detail menggunakan pengetahuan dari buku-buku selanjutnya.

INFORMASI BUKU SELANJUTNYA YANG DILARANG:
- Peristiwa di masa depan, nasib akhir, kematian, kelangsungan hidup, tujuan akhir, romansa, aliansi, konflik, atau pengkhianatan di buku selanjutnya.
- Identitas di buku selanjutnya, asal-usul sejati, silsilah rahasia, alias, alter ego, reinkarnasi, transformasi, gelar, atau peningkatan kekuatan (misalnya, JANGAN sebutkan jika suatu esensi bergabung dengan yang lain atau terlahir kembali di buku mendatang).
- Pengungkapan, konfirmasi, interpretasi ulang, plot twist, atau terminologi pembangunan dunia yang diperkenalkan di buku-buku selanjutnya.
- Petunjuk retrospektif (foreshadowing) atau frasa seperti "nanti", "pada akhirnya", "akan menjadi", "di buku-buku berikutnya", atau yang setara.
- Menyebutkan karakter, konsep, organisasi, atau kronologi dari buku-buku selanjutnya.

BATAS KARAKTER:
Deskripsikan setiap karakter secara ketat sebagaimana diketahui pada halaman terakhir BUKU TARGET.
JANGAN gunakan alias, peran, hubungan, identitas sejati, atau status yang baru terungkap di buku-buku selanjutnya.

ATURAN KETIDAKPASTIAN:
Jika Anda tidak dapat menentukan dengan yakin apakah suatu fakta atau alias sudah ditetapkan sebelum akhir BUKU TARGET, HILANGKAN SAJA.
Kekurangan detail jauh lebih baik daripada membocorkan spoiler buku mendatang.

AUDIT AKHIR:
Sebelum mengembalikan JSON, periksa setiap bidang (terutama deskripsi dan alias karakter) dan hapus apa pun yang bergantung pada pengetahuan dari buku-buku setelah BUKU TARGET.

FORMAT JSON YANG DIPERLUKAN:
{
  "characters": [
    { "name": "Nama Lengkap", "aliases": [], "role": "...", "description": "Status di akhir buku ini (maks {MAX_CHAR_DESC} karakter)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Ringkasan Buku", "event": "Satu rekapitulasi yang sangat rinci dan komprehensif mengenai seluruh alur cerita buku, peristiwa utama, dan penyelesaiannya (maks 2000 karakter). Anda HARUS memformat rekap ini menggunakan beberapa paragraf terpisah yang dipisahkan oleh baris baru ganda (\\n\\n) agar mudah dibaca, bukan satu blok teks yang padat." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
BUKU TARGET: %s
PENULIS: %s
INDEKS BUKU TARGET: %d
SERI: %s

TUGAS:
Dengan HANYA menggunakan peristiwa bab demi bab yang terverifikasi di bawah ini dari BUKU TARGET, tulis rekap yang kohesif dan komprehensif tentang keseluruhan alur cerita buku, perkembangan penting, dan penyelesaiannya.

BATASAN SUMBER KETAT:
- Dasarkan ringkasan Anda SECARA EKSKLUSIF pada peristiwa bab yang disediakan.
- JANGAN memperkenalkan fakta, karakter, peristiwa, atau hasil yang tidak dijelaskan dalam peristiwa bab ini.
- JANGAN PERNAH menyebutkan atau membayangi peristiwa, kematian, atau perkembangan dari buku-buku selanjutnya dalam seri ini.

PERISTIWA BAB:
%s

FORMAT JSON YANG DIPERLUKAN:
{
  "timeline": [
    { "chapter": "Ringkasan Buku", "event": "Satu rekapitulasi yang sangat rinci dan komprehensif mengenai seluruh alur cerita buku dan penyelesaiannya (maks 2000 karakter). Anda HARUS memformat rekap ini menggunakan beberapa paragraf terpisah yang dipisahkan oleh baris baru ganda (\\n\\n) agar mudah dibaca, bukan satu blok teks yang padat." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Buku: %s
Penulis: %s
Menganalisis Bab: %s

TUGAS: Analisis HANYA satu bab ini saja. Identifikasi entitas BARU yang diperkenalkan dalam bab ini, serta PEMBARUAN DELTA (transisi status) untuk entitas yang sudah ada.
Hasilkan HANYA objek JSON yang valid.

MANIFES ENTITAS YANG SUDAH DIKETAHUI (JANGAN ekstrak ulang kecuali peran, status, atau deskripsinya berkembang secara signifikan):
%s

ATURAN:
1. PEMBATASAN SPOILER KETAT: Analisis HANYA teks bab yang disediakan. JANGAN gunakan pengetahuan apa pun dari bab-bab mendatang atau sumber eksternal.
2. KEDALAMAN & SUBSTANSI DESKRIPSI KARAKTER (PENTING):
   - Berdasar & Spesifik: Jelaskan siapa karakter tersebut dengan fakta cerita yang konkret—latar belakangnya, kepribadian yang menonjol, profesinya, hubungan utama dengan karakter lain, serta peran spesifik dan taruhan pribadinya dalam narasi.
   - Konteks Naratif yang Signifikan: Hubungkan karakter secara langsung dengan misteri utama, konflik plot, atau investigasi dalam buku ini (mis., kejahatan atau kasus apa yang sedang diselidiki, siapa yang mempekerjakannya, sekutu atau musuh utama, dilema atau ketegangan pribadi yang spesifik).
   - JANGAN Terlalu Umum: JANGAN tulis kalimat klise yang generik (mis., hindari ungkapan kosong seperti "seorang detektif yang menyelidiki kasus rumit"). Sebutkan keadaan, koneksi, dan taruhan spesifik yang ditetapkan dalam teks.
   - TANPA Rekap Tugas Sepele: JANGAN tulis catatan kronologis dari aktivitas harian yang biasa atau pekerjaan rutin (mis., JANGAN rekap perjalanan ke toko kelontong, panggilan telepon rutin, atau pergerakan adegan demi adegan yang tidak penting).
   - Deskripsi karakter harus menjadi profil yang kaya dan hidup yang merangkum siapa mereka dan signifikansi mereka hingga titik ini dalam buku.
3. AMBANG BATAS TINGGI UNTUK PEMBARUAN KARAKTER:
   - JANGAN buat pembaruan di `character_state_updates` hanya karena karakter yang sudah ada muncul, berbicara, atau melakukan tindakan rutin di bab ini.
   - HANYA hasilkan pembaruan jika ada transformasi substantif yang bertahan lama dalam alur naratif, identitas, hubungan, pekerjaan, kesetiaan, atau kondisi mereka (mis., terbunuh, terluka, ditangkap, dikhianati, bertunangan, dipromosikan, terungkap sebagai pelaku, rahasia besar atau motif terungkap).
   - Jika pembaruan MEMANG dibenarkan, `description` yang diperbarui harus berupa tinjauan karakter kumulatif yang kaya yang menggabungkan perkembangan baru sambil mempertahankan identitas inti dan konteks cerita mereka yang sudah mapan—BUKAN ringkasan dari satu adegan terisolasi.
4. PENANDA HALAMAN INTRA-BAB ([PAGE N]) & PEMBATASAN BEBAS SPOILER:
   - Teks bab berisi penanda [PAGE N] yang menunjukkan perkembangan halaman.
   - Untuk `new_characters`, `new_locations`, dan `new_terms`: berikan "first_page" (bilangan bulat N dari penanda [PAGE N] tempat pertama kali disebutkan), "intro_role" (untuk karakter), dan "intro_description" (1-2 kalimat yang dibatasi secara ketat pada apa yang diketahui saat pertama kali diperkenalkan di [PAGE first_page]—dengan NOL pengetahuan tentang plot twist, rahasia, atau hasil yang terjadi di halaman berikutnya). Berikan juga "page" (penanda [PAGE N] tempat "description" kumulatif yang lebih lengkap berlaku, biasanya halaman terakhir bab).
   - Untuk `character_state_updates`, `location_state_updates`, dan `term_state_updates`: berikan "page" (bilangan bulat N dari penanda [PAGE N] tempat pengungkapan/transisi selesai; JANGAN ungkapkan fakta sebelum halaman ini).
5. BUKTI: Berikan referensi singkat atau kutipan cuplikan dari bab ini yang menjelaskan mengapa pembaruan terjadi.
6. LINI MASA: Berikan tepat satu ringkasan peristiwa tentang aksi plot utama dalam bab ini.

FORMAT JSON YANG DIPERLUKAN:
{
  "new_characters": [
    {
      "name": "Nama Lengkap",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Peran awal (mis. Petugas Desa, Orang Asing, Klien)",
      "intro_description": "Kesan awal 1-2 kalimat secara ketat saat perkenalan pertama, tanpa spoiler dari halaman selanjutnya.",
      "page": 99,
      "role": "Peran naratif / tingkat kepentingan (mis. Protagonis, Detektif Swasta, Rekan, Antagonis, Korban, Klien, Tersangka, Karakter Sekunder, Karakter Minor)",
      "status": "alive",
      "description": "Deskripsi karakter yang kaya dan spesifik (latar belakang, hubungan, taruhan naratif). Hindari kalimat umum dan catatan aktivitas sepele.",
      "evidence": "Kutipan singkat"
    }
  ],
  "character_state_updates": [
    {
      "name": "Nama yang cocok dengan manifes yang diketahui",
      "page": 95,
      "role": "Peran naratif / tingkat kepentingan yang diperbarui (mis. Protagonis, Rekan, Antagonis, Karakter Sekunder, dll.)",
      "status": "alive",
      "change": "Satu kalimat pendek yang menyebutkan apa yang berubah sejak status sebelumnya (mis. 'Dipromosikan menjadi rekan setelah kasus Shacklewell')",
      "description": "Deskripsi karakter kumulatif yang kaya dan diperbarui yang mencerminkan status baru dan taruhan cerita mereka",
      "evidence": "Kutipan singkat"
    }
  ],
  "new_locations": [
    {
      "name": "Nama Lokasi",
      "first_page": 80,
      "intro_description": "Kesan awal saat pertama kali disebutkan.",
      "page": 99,
      "description": "Deskripsi lokasi",
      "evidence": "Kutipan singkat"
    }
  ],
  "location_state_updates": [
    {
      "name": "Nama yang cocok dengan manifes yang diketahui",
      "page": 95,
      "change": "Satu kalimat pendek yang menyebutkan apa yang berubah (mis. 'Hancur selama pertempuran Oakhaven')",
      "description": "Deskripsi yang telah berkembang dan diperbarui",
      "evidence": "Kutipan singkat"
    }
  ],
  "new_terms": [
    {
      "name": "Nama Istilah",
      "first_page": 80,
      "intro_description": "Definisi awal saat pertama kali disebutkan.",
      "page": 99,
      "description": "Definisi atau penjelasan lore",
      "evidence": "Kutipan singkat"
    }
  ],
  "term_state_updates": [
    {
      "name": "Nama yang cocok dengan manifes yang diketahui",
      "page": 95,
      "change": "Satu kalimat pendek yang menyebutkan apa yang berubah dalam pemahaman atau penggunaan",
      "description": "Definisi yang diperbarui",
      "evidence": "Kutipan singkat"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Ringkasan peristiwa dalam bab ini"
  }
}

TEKS BAB:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Buku: %s
Penulis: %s
Bab dalam Batch ini: %s

TUGAS: Analisis batch bab berurutan yang disediakan secara terurut.
Untuk SETIAP bab dalam batch, identifikasi:
1. Entitas BARU yang diperkenalkan dalam bab tersebut (karakter, lokasi, istilah).
2. PEMBARUAN DELTA (transisi status) untuk entitas yang sudah diketahui (dari manifes ATAU diperkenalkan pada bab sebelumnya dalam batch ini) JIKA DAN HANYA JIKA peran, status, kesetiaan, atau kondisi naratif mereka mengalami transformasi substantif yang bertahan lama.
3. PERISTIWA LINI MASA: Ringkasan singkat dari peristiwa plot utama yang terjadi dalam bab tersebut.

Hasilkan HANYA objek JSON yang valid yang sesuai dengan skema yang diperlukan.

MANIFES ENTITAS YANG SUDAH DIKETAHUI (dari batch sebelumnya - JANGAN ekstrak ulang kecuali peran, status, atau deskripsinya berkembang secara signifikan):
%s

ATURAN:
1. PEMBATASAN SPOILER KETAT & PROGRESI BERURUTAN:
   - Analisis bab-bab secara berurutan.
   - Untuk bab mana pun dalam batch ini, JANGAN masukkan pengetahuan dari bab-bab berikutnya dalam batch atau dari sisa buku.
2. KEDALAMAN & SUBSTANSI DESKRIPSI KARAKTER (PENTING):
   - Berdasar & Spesifik: Jelaskan siapa karakter tersebut dengan fakta cerita yang konkret—latar belakangnya, kepribadian yang menonjol, profesinya, hubungan utama dengan karakter lain, serta peran spesifik dan taruhan pribadinya dalam narasi.
   - Konteks Naratif yang Signifikan: Hubungkan karakter secara langsung dengan misteri utama, konflik plot, atau investigasi dalam buku ini (mis., kejahatan atau kasus apa yang sedang diselidiki, siapa yang mempekerjakannya, sekutu atau musuh utama, dilema atau ketegangan pribadi yang spesifik).
   - JANGAN Terlalu Umum: JANGAN tulis kalimat klise yang generik (mis., hindari ungkapan kosong seperti "seorang detektif yang menyelidiki kasus rumit"). Sebutkan keadaan, koneksi, dan taruhan spesifik yang ditetapkan dalam teks.
   - TANPA Rekap Tugas Sepele: JANGAN tulis catatan kronologis dari aktivitas harian yang biasa atau pekerjaan rutin (mis., JANGAN rekap perjalanan ke toko kelontong, panggilan telepon rutin, atau pergerakan adegan demi adegan yang tidak penting).
   - Deskripsi karakter harus menjadi profil yang kaya dan hidup yang merangkum siapa mereka dan signifikansi mereka hingga titik ini dalam buku.
3. AMBANG BATAS TINGGI UNTUK PEMBARUAN KARAKTER:
   - JANGAN buat pembaruan di `character_state_updates` hanya karena karakter yang sudah ada muncul, berbicara, atau melakukan tindakan rutin dalam sebuah bab.
   - HANYA hasilkan pembaruan jika ada transformasi substantif yang bertahan lama dalam alur naratif, identitas, hubungan, pekerjaan, kesetiaan, atau kondisi mereka (mis., terbunuh, terluka, ditangkap, dikhianati, bertunangan, dipromosikan, terungkap sebagai pelaku, rahasia besar atau motif terungkap).
   - Jika pembaruan MEMANG dibenarkan, `description` yang diperbarui harus berupa tinjauan karakter kumulatif yang kaya yang menggabungkan perkembangan baru sambil mempertahankan identitas inti dan konteks cerita mereka yang sudah mapan—BUKAN ringkasan dari satu adegan terisolasi.
4. PENANDA HALAMAN INTRA-BAB ([PAGE N]) & PEMBATASAN BEBAS SPOILER:
   - Teks bab berisi penanda [PAGE N] yang menunjukkan perkembangan halaman.
   - Untuk `new_characters`, `new_locations`, dan `new_terms`: berikan "first_page" (bilangan bulat N dari penanda [PAGE N] tempat pertama kali disebutkan), "intro_role" (untuk karakter), dan "intro_description" (1-2 kalimat yang dibatasi secara ketat pada apa yang diketahui saat pertama kali diperkenalkan di [PAGE first_page]—dengan NOL pengetahuan tentang plot twist, rahasia, atau hasil yang terjadi di halaman berikutnya). Berikan juga "page" (penanda [PAGE N] tempat "description" kumulatif yang lebih lengkap berlaku, biasanya halaman terakhir bab).
   - Untuk `character_state_updates`, `location_state_updates`, dan `term_state_updates`: berikan "page" (bilangan bulat N dari penanda [PAGE N] tempat pengungkapan/transisi selesai; JANGAN ungkapkan fakta sebelum halaman ini).
5. BUKTI: Berikan referensi singkat atau kutipan cuplikan dari bab spesifik tersebut yang menjelaskan mengapa pembaruan terjadi.
6. KEAMANAN JSON: Hasilkan JSON yang valid secara ketat. Loloskan tanda kutip ganda di dalam string dengan benar.

FORMAT JSON YANG DIPERLUKAN:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Judul Bab",
      "timeline_event": "Ringkasan perkembangan plot utama dalam bab ini.",
      "new_characters": [
        {
          "name": "Nama Lengkap",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Peran awal (mis. Petugas Desa, Orang Asing, Klien)",
          "intro_description": "Kesan awal 1-2 kalimat secara ketat saat perkenalan pertama, tanpa spoiler dari halaman selanjutnya.",
          "page": 99,
          "role": "Peran naratif / tingkat kepentingan (mis. Protagonis, Detektif Swasta, Rekan, Antagonis, Korban, Klien, Tersangka, Karakter Sekunder, Karakter Minor)",
          "status": "alive",
          "description": "Deskripsi karakter yang kaya dan spesifik (latar belakang, hubungan, taruhan naratif). Hindari kalimat umum dan catatan aktivitas sepele.",
          "evidence": "Cuplikan singkat"
        }
      ],
      "character_state_updates": [
        {
          "name": "Nama yang cocok dengan manifes yang diketahui atau karakter yang diperkenalkan di bab sebelumnya dalam batch ini",
          "page": 95,
          "role": "Peran naratif / tingkat kepentingan yang diperbarui (mis. Protagonis, Rekan, Antagonis, Karakter Sekunder, dll.)",
          "status": "alive",
          "change": "Satu kalimat pendek yang menyebutkan apa yang berubah sejak status sebelumnya (mis. 'Dipromosikan menjadi rekan setelah kasus Shacklewell')",
          "description": "Deskripsi karakter kumulatif yang kaya dan diperbarui yang mencerminkan status baru dan taruhan cerita mereka",
          "evidence": "Cuplikan singkat"
        }
      ],
      "new_locations": [
        {
          "name": "Nama Lokasi",
          "first_page": 80,
          "intro_description": "Kesan awal saat pertama kali disebutkan.",
          "page": 99,
          "description": "Deskripsi lokasi",
          "evidence": "Cuplikan singkat"
        }
      ],
      "location_state_updates": [
        {
          "name": "Nama yang cocok dengan manifes yang diketahui atau lokasi yang diperkenalkan di bab sebelumnya dalam batch ini",
          "page": 95,
          "change": "Satu kalimat pendek yang menyebutkan apa yang berubah (mis. 'Hancur selama pertempuran Oakhaven')",
          "description": "Deskripsi yang diperbarui",
          "evidence": "Cuplikan singkat"
        }
      ],
      "new_terms": [
        {
          "name": "Nama Istilah",
          "first_page": 80,
          "intro_description": "Definisi awal saat pertama kali disebutkan.",
          "page": 99,
          "description": "Definisi atau penjelasan lore",
          "evidence": "Cuplikan singkat"
        }
      ],
      "term_state_updates": [
        {
          "name": "Nama yang cocok dengan manifes yang diketahui atau istilah yang diperkenalkan di bab sebelumnya dalam batch ini",
          "page": 95,
          "change": "Satu kalimat pendek yang menyebutkan apa yang berubah dalam pemahaman atau penggunaan",
          "description": "Definisi yang diperbarui",
          "evidence": "Cuplikan singkat"
        }
      ]
    }
  ]
}

TEKS BAB DALAM BATCH INI:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analisis detail buku dan Daftar Isi berikut ini:

Judul: %s
Penulis: %s
Subjek: %s
Deskripsi: %s

Daftar Isi:
%s

Tentukan apakah karya ini adalah:
1. "anthology" (kumpulan cerita pendek, esai, atau novela yang berdiri sendiri, masing-masing dengan narasi atau jajaran tokohnya sendiri, mis. "The Adventures of Sherlock Holmes", "Dubliners", "Exhalation", "Men Without Women").
2. "novel" (satu novel utuh yang dibagi menjadi bab, bagian, atau babak, mis. "Pride and Prejudice", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (kumpulan multi-volume dari novel-novel utuh yang diterbitkan bersama dalam satu volume, mis. "The Lord of the Rings: All Three Volumes", "The Complete Hitchhiker's Guide to the Galaxy", "Percy Jackson: Books 1-3").
4. "non_fiction" (satu karya non-fiksi, sejarah, atau buku akademis yang dibagi menjadi bab-bab).

Kembalikan HANYA objek JSON dengan format:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 to 1.0,
  "reasoning": "penjelasan singkat (satu kalimat)"
}]],

    -- System instruction
    system_instruction = "Anda adalah seorang peneliti sastra ahli. Tanggapan Anda harus HANYA dalam format JSON yang valid. Pastikan data sangat akurat dan berkaitan erat dengan konteks yang disediakan.",

    -- Fallback strings
    fallback = {
        no_biography = "Tidak Ada Biografi yang Tersedia",
        no_description = "Tidak Ada Deskripsi",
        not_specified = "Tidak Ditentukan",
        unknown_author = "Penulis Tidak Diketahui",
        unknown_book = "Buku Tidak Diketahui",
        unnamed_character = "Karakter Tanpa Nama",
        unnamed_person = "Orang Tanpa Nama"
    }
}
