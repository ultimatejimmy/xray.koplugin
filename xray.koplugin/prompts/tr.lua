return {
    -- Sistem talimatı
    system_instruction = "Uzman bir edebiyat araştırmacısısın. Cevabın SADECE geçerli JSON formatında olmalıdır. Verilerin yüksek derecede doğru olduğundan ve kesinlikle sağlanan bağlamla ilgili olduğundan emin ol.",

    -- Sadece yazar için istem (Hızlı biyografi araması için)
    author_only = [["%s" kitabının yazarını belirle ve biyografisini sun. 
Üstveriler yazarın "%s" olduğunu gösteriyor. 
KRİTİK: %100 doğruluk sağlamak ve hatalı kimlik tespitlerini önlemek için yazarı KİTAP METNİ BAĞLAMI (bu istemin sonunda verilmişse) kullanarak doğrula.

GEREKLİ JSON FORMATI:
{
  "author": "Doğru Tam İsim",
  "author_bio": "Edebi kariyerine ve başlıca eserlerine odaklanan kapsamlı biyografi.",
  "author_birth": "Doğum Tarihi, yerel tarih formatına göre biçimlendirilmiş",
  "author_death": "Ölüm Tarihi, yerel tarih formatına göre biçimlendirilmiş"
}]],

    -- Tek Kapsamlı Getirme (Karakterler, Mekanlar, Zaman Çizelgesi Birleşik)
    comprehensive_xray = [[Kitap: %s
Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: Tam bir X-Ray analizi yap. SADECE geçerli bir JSON objesi döndür.

KRİTİK DİKKAT BÖLÜMLEMESİ:
Bu istemin sonunda sağlanan iki metin bloğunu işliyorsunuz:
1. "CHAPTER SAMPLES" (Bölüm Örnekleri): Okuyucunun mevcut konumuna kadar olan kitabın makro bağlamıdır.
2. "BOOK TEXT CONTEXT" (Kitap Metni Bağlamı): En son 20.000 karakterlik mikro bağlamdır.

ANTI-TRUNCATION PROTOKOLÜ (KRİTİK):
Katı bir maksimum çıktı sınırınız var. Eğer "CHAPTER SAMPLES" 40'tan FAZLA bölüm içeriyorsa (örn. bir omnibus baskısı):
1. Karakter listesini SADECE en önemli ilk 10 karakterle sınırlamalısınız.
2. Karakter açıklamalarını MAKSİMUM {MAX_CHAR_DESC} karakterle sınırlamalısınız.
3. Zaman çizelgesi olay özetlerini MAKSİMUM {MAX_TIMELINE_EVENT} karakterle sınırlamalısınız.
Çıktınızı devasa kitaplar için sıkıştırmazsanız, JSON kesilecek ve hata verecektir.

ZAMAN ÇİZELGESİ İÇİN ALGORİTMA (EN YÜKSEK ÖNCELİK):
Bölüm atlamayı veya olay uydurmayı önlemek için, bu döngüyü tam olarak uygulamalısınız:
Adım 1. SADECE "CHAPTER SAMPLES" bloğuna bak. Anlatı bölümlerini belirle.
Adım 2. Anlatı olmayan tüm ön madde ve arka maddeleri HARİÇ TUT (örn., Kapak, Başlık Sayfası, Telif Hakkı, İçindekiler, İthaf, Teşekkür, Ayrıca Yazan).
Adım 3. Her anlatı bölümü için, en ilk bölümden başlayarak, `timeline` dizisinde TAM OLARAK BİR olay objesi oluştur.
Adım 4. `chapter` alanı, örnekteki bölüm başlığıyla tam olarak eşleşmelidir. (Bunları kesinlikle sıralı düzende eşle).
Adım 5. Bu özel bölümü `event` alanında özetle {TIMELINE_DETAIL_GUIDANCE} (MAKS {MAX_TIMELINE_EVENT} karakter). Bölümleri GRUPLANDIRMA.
Adım 6. SPOILER YOK: Tam olarak %%%d noktasında dur. Bu ilerlemeden sonraki olayları dahil etme.

KARAKTERLER VE TARİHİ KİŞİLER İÇİN ALGORİTMA:
Adım 1. Her iki metin bloğunu da kullanarak önemli karakterleri çıkar. (Normalde {NUM_CHARS}, omnibus ise MAKSİMUM 10).
Adım 2. Karakterlerin TAM resmi isimlerini kullanmalısın (örn. "Abraham Van Helsing"). Gündelik takma adları ana isim olarak kullanma.
Adım 3. Bu karakterin bilindiği 3 adede kadar alternatif isim, unvan veya takma adı bir `aliases` dizisinde sağla. Kullanılıyorsa ortak adlarını ve soyadlarını dahil et. ÖNEMLİ: Eğer bir soyadı birden fazla karakter (örn. aile üyeleri) tarafından paylaşılıyorsa, bunu hiçbir karakter için bir takma ad olarak dahil ETME.
Adım 4. İnsanlık tarihinden en fazla {NUM_HIST} ÖNEMLİ GERÇEK kişiyi aktif olarak tara (örn., Başkanlar, Yazarlar, Generaller). Bunları `historical_figures` dizisine ekle.
CRITICAL for Characters & Historical Figures:
- DO NOT extract characters or historical figures mentioned ONLY in non-narrative frontmatter or backmatter (e.g., Acknowledgments, Author Bio, Dedications, Title Page, Copyright).
- Historical Figures MUST be verified real-world people with widespread historical recognition.
- DO NOT include purely fictional characters in the historical figures list, even if they interact with real historical events. Fictional characters MUST go in the `characters` array.
- For Historical Figures ONLY, you may use your internal knowledge to write their general `biography` and historical `role`, but you MUST use the book context for their `context_in_book`.
SPOILER YOK: Tam olarak %%%d noktasında dur.

MEKANLAR İÇİN ALGORİTMA:
Adım 1. {NUM_LOCS} önemli mekanı çıkar. SPOILER YOK: Tam olarak %%%d noktasında dur.

TERİMLER VE KAVRAMLAR ALGORİTMASI:
Adım 0: JSON kök düğümünde "book_type"ı "fiction" (kurgu) veya "non_fiction" (kurgu dışı) olarak belirtin.
Adım 1: Kitap kurgu dışı ise: {NUM_TERMS} önemli teknik terim, kısaltma, jargon veya kavram çıkarın. Acronym, Technical Term, Concept veya Jargon gibi uygun kategorileri kullanın.
Adım 2: Kitap kurgu ise: Yeni bir okuyucunun açıklanmasına ihtiyaç duyabileceği – uydurulmuş gruplar, organizasyonlar, büyü sistemleri, teknolojiler, yaratıklar, diller veya evren içi lore gibi – {NUM_TERMS} önemli dünya kurma (World-building) unsuru çıkarın.
   - Karakter isimlerini veya mekan isimlerini dahil ETMEYİN (bunlar ayrı olarak takip edilir).
   - Gerçek dünyaya ait yaygın kelimeleri veya kavramları çıkarmayın.
   - Uygun kategorileri kullanın: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Adım 3: "expanded" alanında, kısaltmalar/ifadeler için tam açılımı ekleyin. Kısaltma/ifade değilse, adı tekrarlayın.
Adım 4: Günlük yaygın kelimeleri dahil ETMEYİN.

KESİN SPOILER KURALLARI:
- Mevcut okuma ilerlemesinden sonrası hakkında KESİNLİKLE hiçbir bilgi verme. Tam olarak %%%d noktasında dur.
- Açıklamalar karakterlerin kitabın tam bu noktasındaki durumunu yansıtmalıdır.

KESİN BİLGİ KAYNAĞI KURALLARI (KRİTİK):
- KURGU KARAKTERLER İÇİN: Açıklamalarınız KESİNLİKLE yalnızca sağlanan metinde açıkça belirtilen veya net bir şekilde ima edilen bilgilere dayanmalıdır. Önceki eğitimlerden, harici kaynaklardan veya kitap/seri/yazar hakkındaki genel bilgilerinize dayanarak ekleme yapmayın.
- Bir karakterden şu ana kadar metinde yalnızca kısaca bahsedildiyse, açıklamanız yalnızca bu sınırlı bilgiyi yansıtmalıdır. Sağlanan bağlama dayanmayan hiçbir ayrıntıyı tahmin etmeyin, varsaymayın veya eklemeyin.
- TEK istisna GERÇEK TARİHİ KİŞİLER içindir (`historical_figures` dizisinde yer alan): genel biyografileri/rolleri için dahili bilginizi kullanabilirsiniz, ancak kitaptaki rollerini (`context_in_book`) açıklamak için yine kitap metnine dayanmalısınız.

KESİN JSON GÜVENLİK KURALLARI:
- Dizeler içindeki tüm çift tırnakları (\") düzgün şekilde kaçırmalısın.
- Dizeler içinde kaçırılmamış satır sonları KULLANMAYIN.
- SADECE geçerli, ayrıştırılabilir JSON döndürün.

GEREKLİ JSON FORMATI:
{
  "book_type": "non_fiction",
  "characters": [
    {
      "name": "Tam Resmi İsim",
      "aliases": ["Takma Ad 1", "Takma Ad 2"],
      "role": "Mevcut ilerlemeye kadar olan rolü",
      "gender": "Erkek / Kadın / Bilinmiyor",
      "occupation": "Meslek/Durum",
      "description": "Açıklama KESİNLİKLE sağlanan metne dayanmalıdır. Çıkarım yapmayın veya harici bilgi eklemeyin. SPOILER YOK. (Maks {MAX_CHAR_DESC} karakter)"
    }
  ],
  "historical_figures": [
    {
      "name": "Gerçek Tarihi Kişi Adı",
      "role": "Tarihi Rolü",
      "biography": "Kısa biyografi (MAKS {MAX_HIST_BIO} karakter)",
      "importance_in_book": "Mevcut ilerlemeye kadar olan önemi",
      "context_in_book": "Nasıl bahsediliyor (MAKS 100 karakter)"
    }
  ],
  "locations": [
    {"name": "Mekan Adı", "description": "Kısa açıklama (MAKS {MAX_LOC_DESC} karakter)"}
  ],
  "terms": [
    {
      "name": "Terim veya Kısaltma",
      "expanded": "Tam açılım veya adla aynı",
      "category": "Kısaltma / Teknik Terim / Kavram / Jargon",
      "definition": "Bağlam içinde kısa tanım (MAKS {MAX_TERM_DEF} karakter)"
    }
  ],
  "timeline": [
    {
      "chapter": "Örneklerdeki Tam Bölüm Başlığı",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
} ]],

    -- Daha fazla karakter getir (AI Limitini Aş)
    more_characters = [[Kitap: %s
Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: Metinden TAM OLARAK 10 EK önemli karakter çıkar.
SADECE geçerli bir JSON objesi döndür.

ÖZET MANDATI (KRİTİK):
AI yanıtının kesilmesini önlemek için karakter açıklamalarını {MAX_CHAR_DESC} karakterin altında tutun.

KRİTİK TALİMAT:
Daha önceden çıkarıldıkları için aşağıdaki karakterleri KESİNLİKLE dahil etme:
%s

KESİN SPOILER KURALLARI:
- Mevcut okuma ilerlemesinden sonrası hakkında KESİNLİKLE hiçbir bilgi verme. Tam olarak %%%d noktasında dur.
- Açıklamalar karakterlerin kitabın tam bu noktasındaki durumunu yansıtmalıdır.

GEREKLİ JSON FORMATI:
{
  "characters": [
    {
      "name": "Tam Resmi İsim",
      "aliases": ["Takma Ad 1", "Takma Ad 2"],
      "role": "Mevcut ilerlemeye kadar olan rolü",
      "gender": "Erkek / Kadın / Bilinmiyor",
      "occupation": "Meslek/Durum",
      "description": "Açıklama KESİNLİKLE sağlanan metne dayanmalıdır. Çıkarım yapmayın veya harici bilgi eklemeyin. SPOILER YOK. (Maks {MAX_CHAR_DESC} karakter)"
    }
  ]
}]],

    -- Daha fazla terim getir (Sözlük Desteği)
    more_terms = [[Kitap: %s
Yazar: %s
Okuma İlerlemesi: %%%d

GÖREV: Metinden TAM OLARAK 15 EK önemli terim, kısaltma, jargon veya kavram çıkarın.
- Bu kitap kurgu dışı ise: teknik terimler, kavramlar, kısaltmalar veya jargon çıkarın.
- Bu kitap kurgu ise: gruplar, organizasyonlar, büyü sistemleri, teknolojiler, yaratıklar, diller veya evren içi lore gibi dünya kurma (world-building) unsurlarını çıkarın.
SADECE geçerli bir JSON objesi döndür.

ÖZET MANDATI (KRİTİK):
AI yanıtının kesilmesini önlemek için terim tanımlarını {MAX_TERM_DEF} karakterin altında tutun.

KRİTİK TALİMAT:
Daha önceden çıkarıldıkları için aşağıdaki terimleri KESİNLİKLE dahil etme:
%s

KESİN SPOILER KURALLARI:
- Mevcut okuma ilerlemesinden sonrası hakkında KESİNLİKLE hiçbir bilgi verme. Tam olarak %%%d noktasında dur.

GEREKLİ JSON FORMATI:
{
  "terms": [
    {
      "name": "Terim veya Kısaltma",
      "expanded": "Tam açılım veya adla aynı",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Kısaltma / Teknik Terim / Kavram / Jargon",
      "definition": "Bağlam içinde kısa tanım (MAKS {MAX_TERM_DEF} karakter)"
    }
  ]
}]],

    -- Targeted Single Word Lookup
    single_word_lookup = [[Kullanıcı "%s" kelimesini vurguladı.
GÖREV: Bu kelimenin kitaptaki bir Karakter, Konum, Tarihi Figür veya Teknik Terim/Kısaltma olup olmadığını belirleyin.
 
CRITICAL FOR CHARACTERS AND LOCATIONS: Use ONLY the provided "BOOK TEXT CONTEXT". Outside knowledge is strictly forbidden. Do not hallucinate.
KURGU KARAKTERLER İÇİN KRİTİK: YALNIZCA sağlanan kitap metninin ortaya koyduğu şeyleri açıklayın. Tanınmış bir seriden tanısanız bile, bu karakter hakkında eğitiminizden gelen ön bilgileri kullanmayın. Metin bu karakterden yalnızca kısaca bahsediyorsa, açıklamanız bu sınırlı bilgiyi yansıtmalıdır.
CRITICAL FOR HISTORICAL FIGURES: You MAY use your internal knowledge to verify their identity and provide their biography/role, ONLY if they are a real, notable historical figure. You MUST still use the text context for their relevance in the book.
CRITICAL FOR TERMS: Kitap kurgu dışı ise, kelimenin teknik bir terim, kısaltma veya anahtar kavram olup olmadığını doğrulayın. Bağlam içindeki tanımını sağlayın.
Kelime metinde bir karakter, konum, tarihi figür veya teknik terim DEĞİLSE, `is_valid` değerini false yapın.
 
GEREKLİ JSON FORMATI:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Tam ad",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Rol",
    "gender": "Erkek/Kadın/Bilinmiyor",
    "occupation": "Meslek",
    "description": "Kısa açıklama (maks. 250 karakter)"
  },
  "error_message": ""
}
 
Not: eğer tür "location" ise, öğede "name" ve "description" olmalıdır. Eğer tür "historical_figure" ise, öğede "name", "biography" ve "role" olmalıdır.
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Bunun neden bir karakter veya konum olmadığına dair kısa bir açıklama."
}
]],

    -- Yedek dizeler (Fallback)
        -- Find Duplicates
    find_duplicates = [[
Kitap: %s
Yazar: %s
Okuma Durumu: %d%%

Bu kitaptan çıkarılan aşağıdaki %s listesini inceliyorsunuz.
Göreviniz, farklı adlar altında listelenen AYNI varlığa ait gibi görünen girdileri belirlemektir.

LİSTE:
%s

KURALLAR:
- İki girdinin açıkça aynı varlığa atıfta bulunması durumunda bir yinelenen varlık söz konusudur (örneğin, "Büyük Kütüphane" ve "Büyük Kütüphane" veya "John" ve "John Doe").
- Yalnızca ilişkili veya benzer olan ancak farklı olan girdileri işaretlemeyin.
- Aynı varlık olduğundan son derece emin olmadığınız sürece girdileri işaretlemeyin.
- Yinelenen varlık yoksa, boş bir dizi döndürün.
- SPOILER KURALI: Okuma durumunun %d%% ötesindeki bilgileri kullanmayın.

GEREKLİ JSON BİÇİMİ:
{
  "duplicate_pairs": [
    {
      "primary": "KORUNACAK girdinin adı (daha eksiksiz veya resmi olan ad)",
      "secondary": "KALDIRILACAK girdinin adı",
      "reason": "Kısa neden (en fazla 100 karakter)"
    }
  ]
}]],

    -- Merge Descriptions
    merge_descriptions = [[
GÖREV: Aynı varlığın (karakter veya konum) aşağıdaki iki açıklamasını tek, tutarlı ve kısa bir özette birleştirin.
Gereksiz bilgileri kaldırın ve nihai açıklamanın doğal bir şekilde akmasını sağlayın.

Birincil Açıklama: %s
İkincil Açıklama: %s

GEREKLİ JSON BİÇİMİ:
{
  "merged_description": "Birleştirilmiş ve cilalanmış açıklama (En fazla {MAX_CHAR_DESC} karakter)"
}]],

-- Multi-Book Series Context Prompts
    series_detect = [[Kitap Adı: %s
Yazar: %s

GÖREV: Bu kitabın adlandırılmış bir serinin parçası olup olmadığını belirleyin.
SADECE geçerli bir JSON döndürün:
{
  "is_series": true,
  "series_name": "Zaman Çarkı",
  "book_index": 3,
  "total_books_known": 14
}
Eğer bu bir seri kitabı DEĞİLSE, şunu döndürün:
{ "is_series": false }]],

    prior_book_list = [[Seri: %s
Mevcut Kitap İndeksi: %d
Mevcut Kitap Başlığı: %s

GÖREV: Bu seride mevcut kitaptan ÖNCE gelen 1. kitaptan %d. kitaba kadar olan
kitapların adlarını (ve "%s" yazardan farklıysa yazarlarını) listeleyin.
SADECE geçerli bir JSON döndürün:
{
  "prior_books": [
    { "index": 1, "title": "Dünyanın Gözü", "author": "Robert Jordan" }
  ]
}]],

    series_book_summary = [[Kitap: %s
Yazar: %s
Bu, "%s" serisindeki %d. kitaptır.

GÖREV: Serideki BİR SONRAKİ kitaba BAŞLAMAK ÜZERE olan bir okuyucu için
bu kitabın TAMAMINI kapsayan bir özet sağlayın.
Şunları ekleyin: ana karakterler (ad, rol, kitap sonundaki durumları), ana mekanlar,
kritik olay örgüsü gelişmeleri ve tanıtılan önemli dünya oluşturma terimleri.
Bu kitabın ÖTESİNDEKİ kitaplar için SPOILER İÇERMESİN.

GEREKLİ JSON FORMATI:
{
  "characters": [
    { "name": "Tam Adı", "aliases": [], "role": "...", "description": "Bu kitabın sonundaki durumu (en fazla 300 karakter)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Kitap Özeti", "event": "Tüm kitabın olay örgüsünü, ana olaylarını ve sonucunu içeren, birkaç paragraftan oluşan tek, son derece ayrıntılı ve kapsamlı bir özet (en fazla 2000 karakter) You MUST format this recap using multiple distinct paragraphs separated by double newlines (\\n\\n) for readability instead of a single wall of text." }
  ]
}]],

    fallback = {
        unknown_book = "Bilinmeyen Kitap",
        unknown_author = "Bilinmeyen Yazar",
        unnamed_character = "İsimsiz Karakter",
        not_specified = "Belirtilmemiş",
        no_description = "Açıklama Yok",
        unnamed_person = "İsimsiz Kişi",
        no_biography = "Biyografi Mevcut Değil"
    }
}

