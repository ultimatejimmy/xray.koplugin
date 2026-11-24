return {
    -- Author Only
    author_only = [[
"%s" kitabının yazarını belirle ve biyografisini sun. 
Üstveriler yazarın "%s" olduğunu gösteriyor. 
KRİTİK: %100 doğruluk sağlamak ve hatalı kimlik tespitlerini önlemek için yazarı KİTAP METNİ BAĞLAMI (bu istemin sonunda verilmişse) kullanarak doğrula.

GEREKLİ JSON FORMATI:
{
  "author": "Doğru Tam İsim",
  "author_bio": "Edebi kariyerine ve başlıca eserlerine odaklanan kapsamlı biyografi.",
  "author_birth": "Doğum Tarihi, yerel tarih formatına göre biçimlendirilmiş",
  "author_death": "Ölüm Tarihi, yerel tarih formatına göre biçimlendirilmiş"
}]],

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

    -- Comprehensive Xray
    comprehensive_xray = [[
Kitap: %s
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
Adım 5. Bu özel bölümü `event` alanında özetle. {TIMELINE_DETAIL_GUIDANCE} {MIN_TIMELINE_EVENT} ile {MAX_TIMELINE_EVENT} karakter arasında yaz. Bölümde neredeyse hiç içerik olmadığı sürece daha kısa bir özet YAZMA. Bölümleri GRUPLANDIRMA.
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
}]],

    -- More Characters
    more_characters = [[
Kitap: %s
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

    -- More Terms
    more_terms = [[
Kitap: %s
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

    -- Single Word Lookup
    single_word_lookup = [[
Kullanıcı "%s" kelimesini vurguladı.
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

    -- Book Type Detect
    book_type_detect = [[
Kitap Adı: %s
Yazar: %s
Seri: %s
Dosya Açıklaması/Konu Üstverileri: %s

GÖREV: Bu kitabı üstverilerine ve tür sinyallerine göre şu kitap türlerinden tam olarak BİRİNE sınıflandırın:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

SADECE geçerli JSON döndürün:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Kitap Adı: %s
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

    -- Prior Book List
    prior_book_list = [[
Seri: %s
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

    -- Series Book Summary
    series_book_summary = [[
HEDEF KİTAP: %s
YAZAR: %s
HEDEF KİTAP İNDEKSİ: %d
SERİ: %s

GÖREV:
Yalnızca HEDEF KİTABI bitirmiş ve serideki bir sonraki kitaba başlamak üzere olan
bir okuyucu için yalnızca HEDEF KİTABIN TAM bir özetini sağlayın.

KESİN SPOILER SINIRI:
Bilgi sınırı kesinlikle HEDEF KİTABIN SON SAYFASIDIR (Kitap İndeksi %d).
HEDEF KİTAPTA veya bu serideki daha önceki kitaplarda ortaya konan gerçekleri dahil edebilirsiniz.
Daha sonraki herhangi bir kitaptan alınan bilgileri kullanarak ayrıntıları dahil ETMEMELİ, ima ETMEMELİ, ipucu VERMEMELİ, önceden haber VERMEMELİ veya seçmemelisiniz.

YASAKLI SONRAKİ KİTAP BİLGİLERİ:
- Sonraki olaylar, gelecekteki kaderler, ölümler, hayatta kalmalar, varış yerleri, aşklar, ittifaklar, çatışmalar veya ihanetler.
- Sonraki kitaplardaki kimlikler, gerçek kökenler, gizli soy, takma adlar, ikinci kişilikler, reenkarnasyonlar, dönüşümler, unvanlar veya güç yükselmeleri (örneğin, bir özün başka birine katılıp katılmadığından veya gelecekteki bir kitapta yeniden doğup doğmadığından bahsetmeyin).
- Sonraki kitaplarda tanıtılan ifşalar, doğrulamalar, yeniden yorumlamalar, ters köşeler veya dünya kurma terminolojisi.
- Geriye dönük önceden haber verme veya "daha sonra", "nihayetinde", "olacak", "sonraki kitaplarda" ya da benzeri ifadeler.
- Sonraki kitaplardan karakterlerden, kavramlardan, organizasyonlardan veya kronolojiden bahsetmek.

KARAKTER SINIRI:
Her karakteri kesinlikle HEDEF KİTABIN son sayfasında bilindiği şekliyle tanımlayın.
Sonraki kitaplarda ortaya çıkan takma adları, rolleri, ilişkileri, gerçek kimlikleri veya durumları KULLANMAYIN.

BELİRSİZLİK KURALI:
Bir gerçeğin veya takma adın HEDEF KİTABIN sonuna kadar kesinleşip kesinleşmediğini güvenle belirleyemiyorsanız, ONU ATLAYIN.
Eksik bir ayrıntı, gelecekteki bir kitabın spoiler'ından çok daha iyidir.

SON DENETİM:
JSON döndürmeden önce her alanı (özellikle karakter açıklamalarını ve takma adları) inceleyin ve HEDEF KİTAPTAN sonraki kitaplardan gelen bilgilere dayanan her şeyi temizleyin.

GEREKLİ JSON FORMATI:
{
  "characters": [
    { "name": "Tam Adı", "aliases": [], "role": "...", "description": "Bu kitabın sonundaki durumu (maks {MAX_CHAR_DESC} karakter)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Takma Ad 1", "Takma Ad 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Kitap Özeti", "event": "Tüm kitabın olay örgüsünü, ana olaylarını ve sonucunu içeren tek, son derece ayrıntılı, kapsamlı bir özet (maks 2000 karakter). Okunabilirlik için bu özeti tek bir metin bloğu yerine çift satır sonlarıyla (\\n\\n) ayrılmış birden fazla belirgin paragraf kullanarak biçimlendirmelisiniz." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
HEDEF KİTAP: %s
YAZAR: %s
HEDEF KİTAP İNDEKSİ: %d
SERİ: %s

GÖREV:
YALNIZCA aşağıda sağlanan HEDEF KİTAPTAN doğrulanmış bölüm bazlı olayları kullanarak, tüm kitabın olay örgüsünün, kilit gelişmelerinin ve sonucunun tutarlı, kapsamlı bir özetini yazın.

KESİN DAYANAK KISITLAMASI:
- Özetinizi MÜNHASIRAN sağlanan bölüm olaylarına dayandırın.
- Bu bölüm olaylarında açıklanmayan gerçekleri, karakterleri, olayları veya sonuçları dahil ETMEYİN.
- Serideki sonraki kitaplardan olaylardan, ölümlerden veya gelişmelerden ASLA bahsetmeyin veya bunları ima etmeyin.

BÖLÜM OLAYLARI:
%s

GEREKLİ JSON FORMATI:
{
  "timeline": [
    { "chapter": "Kitap Özeti", "event": "Tüm kitabın olay örgüsünü ve sonucunu içeren tek, son derece ayrıntılı, kapsamlı bir özet (maks 2000 karakter). Okunabilirlik için bu özeti tek bir metin bloğu yerine çift satır sonlarıyla (\\n\\n) ayrılmış birden fazla belirgin paragraf kullanarak biçimlendirmelisiniz." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Kitap: %s
Yazar: %s
İncelenen Bölüm: %s

GÖREV: YALNIZCA bu tek bölümü analiz edin. Bu bölümde tanıtılan YENİ varlıkları ve mevcut varlıklar için DELTA GÜNCELLEMELERİNİ (durum geçişlerini) belirleyin.
SADECE geçerli bir JSON nesnesi döndürün.

MEVCUT BİLİNEN VARLIKLAR LİSTESİ (Rolleri, durumları veya açıklamaları önemli ölçüde gelişmediği sürece yeniden çıkarmayın):
%s

KURALLAR:
1. KESİN SPOILER SINIRLAMASI: YALNIZCA sağlanan bölüm metnini analiz edin. Gelecek bölümlerden veya harici kaynaklardan herhangi bir bilgi KULLANMAYIN.
2. KARAKTER AÇIKLAMASI DERİNLİĞİ VE ÖZÜ (KRİTİK):
   - Temelli ve Özgül: Karakterin kim olduğunu somut hikaye gerçekleriyle tanımlayın—geçmişi, belirgin kişiliği, mesleği, diğer karakterlerle kilit ilişkileri ve anlatıdaki özgül rolü ile kişisel çıkarları.
   - Önemli Anlatı Bağlamı: Karakteri doğrudan bu kitaptaki merkezi gizem, olay örgüsü çatışması veya soruşturmayla ilişkilendirin (ör. hangi suçları veya davaları araştırdıkları, onları kimin tuttuğu, kilit müttefikler veya rakipler, özgül kişisel ikilemler veya gerilimler).
   - Aşırı Genel OLMAMALI: Genel klişe ifadeler yazmayın (ör. "karmaşık davaları araştıran bir dedektif" gibi boş ifadelerden kaçının). Metinde ortaya konan özgül koşulları, bağlantıları ve çıkarları adlandırın.
   - Önemsiz Günlük İş Özetleri YOK: Sıradan günlük aktivitelerin veya rutin işlerin kronolojik kayıtlarını yazmayın (ör. market alışverişlerini, rutin telefon görüşmelerini veya sahneden sahneye önemsiz hareketleri özetlemeyin).
   - Karakter açıklamaları, kim olduklarını ve kitabın bu noktasına kadar olan önemlerini özetleyen zengin, canlı profiller olmalıdır.
3. KARAKTER GÜNCELLEMELERİ İÇİN YÜKSEK EŞİK:
   - Mevcut bir karakter yalnızca bu bölümde göründüğü, konuştuğu veya rutin eylemler gerçekleştirdiği için `character_state_updates` içinde bir güncelleme OLUŞTURMAYIN.
   - YALNIZCA anlatı yaylarında, kimliklerinde, ilişkilerinde, işlerinde, bağlılıklarında veya durumlarında önemli, kalıcı bir dönüşüm varsa bir güncelleme oluşturun (ör. öldürüldü, yaralandı, tutuklandı, ihanete uğradı, nişanlandı, terfi etti, suçlu olduğu ortaya çıktı, büyük bir sır veya saik açığa çıktı).
   - Bir güncelleme gerekliyse, güncellenen `description` izole bir sahnenin özeti DEĞİL, temel kimliklerini ve yerleşik hikaye bağlamını korurken yeni gelişmeleri içeren zengin, kümülatif bir karakter genel bakışı olmalıdır.
4. BÖLÜM İÇİ SAYFA İŞARETLEYİCİLERİ ([PAGE N]) VE SIFIR SPOILER KISITLAMASI:
   - Bölüm metinleri sayfa ilerlemesini gösteren [PAGE N] işaretleyicileri içerir.
   - `new_characters`, `new_locations` ve `new_terms` için: "first_page" (ilk bahsedildiği [PAGE N] işaretleyicisindeki N tam sayısı), "intro_role" (karakterler için) ve "intro_description" ([PAGE first_page] sayfasındaki ilk tanıtımlarında bilinenlerle kesinlikle sınırlı 1-2 cümle—sonraki sayfalarda gerçekleşen sonraki ters köşeler, sırlar veya sonuçlar hakkında SIFIR bilgi ile) sağlayın. Ayrıca daha kapsamlı kümülatif "description" alanının geçerli olduğu "page" ([PAGE N] işaretleyicisi, genellikle bölümün son sayfası) değerini sağlayın.
   - `character_state_updates`, `location_state_updates` ve `term_state_updates` için: "page" (açığa çıkmanın/geçişin tamamlandığı [PAGE N] işaretleyicisindeki N tam sayısı; bu sayfadan önce gerçekleri açıklamayın) sağlayın.
5. KANIT: Güncellemenin neden gerçekleştiğini açıklayan bu bölümden kısa bir referans veya alıntı parçası sağlayın.
6. ZAMAN ÇİZELGESİ: Bu bölümdeki ana olay örgüsü eylemlerinin tam olarak bir olay özetini sağlayın.

GEREKLİ JSON FORMATI:
{
  "new_characters": [
    {
      "name": "Tam Adı",
      "aliases": ["Takma Ad 1", "Takma Ad 2"],
      "first_page": 80,
      "intro_role": "İlk rolü (ör. Köy Katibi, Yabancı, Müşteri)",
      "intro_description": "İlk tanıtımda kesinlikle 1-2 cümlelik ilk izlenim, sonraki sayfalardan sıfır spoiler.",
      "page": 99,
      "role": "Anlatı rolü / önemi (ör. Başkahraman, Özel Dedektif, Ortak, Başkarakter Karşıtı, Kurban, Müşteri, Şüpheli, İkincil Karakter, Yan Karakter)",
      "status": "alive",
      "description": "Zengin, özgül karakter açıklaması (geçmiş, ilişkiler, anlatı çıkarları). Genel ifadelerden ve önemsiz iş kayıtlarından kaçının.",
      "evidence": "Kısa alıntı"
    }
  ],
  "character_state_updates": [
    {
      "name": "Bilinen listeyle eşleşen ad",
      "page": 95,
      "role": "Güncellenmiş anlatı rolü / önemi (ör. Başkahraman, Ortak, Başkarakter Karşıtı, İkincil Karakter vb.)",
      "status": "alive",
      "change": "Önceki durumdan bu yana neyin değiştiğini belirten tek kısa cümle (ör. 'Shacklewell davasından sonra ortaklığa terfi etti')",
      "description": "Yeni durumlarını ve hikaye çıkarlarını yansıtan güncellenmiş zengin, kümülatif karakter açıklaması",
      "evidence": "Kısa alıntı"
    }
  ],
  "new_locations": [
    {
      "name": "Mekan Adı",
      "first_page": 80,
      "intro_description": "İlk bahsedildiğindeki ilk izlenim.",
      "page": 99,
      "description": "Mekanın açıklaması",
      "evidence": "Kısa alıntı"
    }
  ],
  "location_state_updates": [
    {
      "name": "Bilinen listeyle eşleşen ad",
      "page": 95,
      "change": "Neyin değiştiğini belirten tek kısa cümle (ör. 'Oakhaven savaşı sırasında yok edildi')",
      "description": "Güncellenmiş gelişmiş açıklama",
      "evidence": "Kısa alıntı"
    }
  ],
  "new_terms": [
    {
      "name": "Terim Adı",
      "first_page": 80,
      "intro_description": "İlk bahsedildiğindeki ilk tanım.",
      "page": 99,
      "description": "Tanım veya evren açıklaması",
      "evidence": "Kısa alıntı"
    }
  ],
  "term_state_updates": [
    {
      "name": "Bilinen listeyle eşleşen ad",
      "page": 95,
      "change": "Anlayış veya kullanımda neyin değiştiğini belirten tek kısa cümle",
      "description": "Güncellenmiş tanım",
      "evidence": "Kısa alıntı"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Bu bölümdeki olayların özeti"
  }
}

BÖLÜM METNİ:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Kitap: %s
Yazar: %s
Bu Gruptaki Bölümler: %s

GÖREV: Sağlanan sıralı bölüm grubunu sırayla analiz edin.
Gruptaki HER bölüm için şunları belirleyin:
1. O bölümde tanıtılan YENİ varlıklar (karakterler, mekanlar, terimler).
2. Mevcut bilinen varlıklar için (listeden VEYA bu grubun daha önceki bir bölümünde tanıtılmış olan) YALNIZCA rolleri, durumları, bağlılıkları veya anlatı koşulları önemli, kalıcı bir dönüşüm geçirdiyse DELTA GÜNCELLEMELERİ (durum geçişleri).
3. ZAMAN ÇİZELGESİ OLAYI: O bölümde gerçekleşen ana olay örgüsü olaylarının kısa ve öz bir özeti.

Gerekli şemayla eşleşen SADECE geçerli bir JSON nesnesi döndürün.

MEVCUT BİLİNEN VARLIKLAR LİSTESİ (önceki gruplardan - rolleri, durumları veya açıklamaları önemli ölçüde gelişmediği sürece yeniden çıkarmayın):
%s

KURALLAR:
1. KESİN SPOILER SINIRLAMASI VE SIRALI İLERLEME:
   - Bölümleri sıralı düzende analiz edin.
   - Bu gruptaki herhangi bir bölüm için, gruptaki sonraki bölümlerden veya kitabın geri kalanından gelen bilgileri dahil ETMEYİN.
2. KARAKTER AÇIKLAMASI DERİNLİĞİ VE ÖZÜ (KRİTİK):
   - Temelli ve Özgül: Karakterin kim olduğunu somut hikaye gerçekleriyle tanımlayın—geçmişi, belirgin kişiliği, mesleği, diğer karakterlerle kilit ilişkileri ve anlatıdaki özgül rolü ile kişisel çıkarları.
   - Önemli Anlatı Bağlamı: Karakteri doğrudan bu kitaptaki merkezi gizem, olay örgüsü çatışması veya soruşturmayla ilişkilendirin (ör. hangi suçları veya davaları araştırdıkları, onları kimin tuttuğu, kilit müttefikler veya rakipler, özgül kişisel ikilemler veya gerilimler).
   - Aşırı Genel OLMAMALI: Genel klişe ifadeler yazmayın (ör. "karmaşık davaları araştıran bir dedektif" gibi boş ifadelerden kaçının). Metinde ortaya konan özgül koşulları, bağlantıları ve çıkarları adlandırın.
   - Önemsiz Günlük İş Özetleri YOK: Sıradan günlük aktivitelerin veya rutin işlerin kronolojik kayıtlarını yazmayın (ör. market alışverişlerini, rutin telefon görüşmelerini veya sahneden sahneye önemsiz hareketleri özetlemeyin).
   - Karakter açıklamaları, kim olduklarını ve kitabın bu noktasına kadar olan önemlerini özetleyen zengin, canlı profiller olmalıdır.
3. KARAKTER GÜNCELLEMELERİ İÇİN YÜKSEK EŞİK:
   - Mevcut bir karakter yalnızca bu bölümde göründüğü, konuştuğu veya rutin eylemler gerçekleştirdiği için `character_state_updates` içinde bir güncelleme OLUŞTURMAYIN.
   - YALNIZCA anlatı yaylarında, kimliklerinde, ilişkilerinde, işlerinde, bağlılıklarında veya durumlarında önemli, kalıcı bir dönüşüm varsa bir güncelleme oluşturun (ör. öldürüldü, yaralandı, tutuklandı, ihanete uğradı, nişanlandı, terfi etti, suçlu olduğu ortaya çıktı, büyük bir sır veya saik açığa çıktı).
   - Bir güncelleme gerekliyse, güncellenen `description` izole bir sahnenin özeti DEĞİL, temel kimliklerini ve yerleşik hikaye bağlamını korurken yeni gelişmeleri içeren zengin, kümülatif bir karakter genel bakışı olmalıdır.
4. BÖLÜM İÇİ SAYFA İŞARETLEYİCİLERİ ([PAGE N]) VE SIFIR SPOILER KISITLAMASI:
   - Bölüm metinleri sayfa ilerlemesini gösteren [PAGE N] işaretleyicileri içerir.
   - `new_characters`, `new_locations` ve `new_terms` için: "first_page" (ilk bahsedildiği [PAGE N] işaretleyicisindeki N tam sayısı), "intro_role" (karakterler için) ve "intro_description" ([PAGE first_page] sayfasındaki ilk tanıtımlarında bilinenlerle kesinlikle sınırlı 1-2 cümle—sonraki sayfalarda gerçekleşen sonraki ters köşeler, sırlar veya sonuçlar hakkında SIFIR bilgi ile) sağlayın. Ayrıca daha kapsamlı kümülatif "description" alanının geçerli olduğu "page" ([PAGE N] işaretleyicisi, genellikle bölümün son sayfası) değerini sağlayın.
   - `character_state_updates`, `location_state_updates` ve `term_state_updates` için: "page" (açığa çıkmanın/geçişin tamamlandığı [PAGE N] işaretleyicisindeki N tam sayısı; bu sayfadan önce gerçekleri açıklamayın) sağlayın.
5. KANIT: Güncellemenin neden gerçekleştiğini açıklayan o belirli bölümden kısa bir referans veya alıntı parçası sağlayın.
6. JSON GÜVENLİĞİ: Kesinlikle geçerli JSON döndürün. Dizeler içindeki çift tırnakları düzgün şekilde kaçırın.

GEREKLİ JSON FORMATI:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Bölüm Başlığı",
      "timeline_event": "Bu bölümdeki ana olay örgüsü gelişmelerinin özeti.",
      "new_characters": [
        {
          "name": "Tam Adı",
          "aliases": ["Takma Ad 1"],
          "first_page": 80,
          "intro_role": "İlk rolü (ör. Köy Katibi, Yabancı, Müşteri)",
          "intro_description": "İlk tanıtımda kesinlikle 1-2 cümlelik ilk izlenim, sonraki sayfalardan sıfır spoiler.",
          "page": 99,
          "role": "Anlatı rolü / önemi (ör. Başkahraman, Özel Dedektif, Ortak, Başkarakter Karşıtı, Kurban, Müşteri, Şüpheli, İkincil Karakter, Yan Karakter)",
          "status": "alive",
          "description": "Zengin, özgül karakter açıklaması (geçmiş, ilişkiler, anlatı çıkarları). Genel ifadelerden ve önemsiz iş kayıtlarından kaçının.",
          "evidence": "Kısa alıntı"
        }
      ],
      "character_state_updates": [
        {
          "name": "Bilinen listeyle veya bu grubun daha önceki bir bölümünde tanıtılan karakterle eşleşen ad",
          "page": 95,
          "role": "Güncellenmiş anlatı rolü / önemi (ör. Başkahraman, Ortak, Başkarakter Karşıtı, İkincil Karakter vb.)",
          "status": "alive",
          "change": "Önceki durumdan bu yana neyin değiştiğini belirten tek kısa cümle (ör. 'Shacklewell davasından sonra ortaklığa terfi etti')",
          "description": "Yeni durumlarını ve hikaye çıkarlarını yansıtan güncellenmiş zengin, kümülatif karakter açıklaması",
          "evidence": "Kısa alıntı"
        }
      ],
      "new_locations": [
        {
          "name": "Mekan Adı",
          "first_page": 80,
          "intro_description": "İlk bahsedildiğindeki ilk izlenim.",
          "page": 99,
          "description": "Mekanın açıklaması",
          "evidence": "Kısa alıntı"
        }
      ],
      "location_state_updates": [
        {
          "name": "Bilinen listeyle veya bu grubun daha önceki bir bölümünde tanıtılan mekanla eşleşen ad",
          "page": 95,
          "change": "Neyin değiştiğini belirten tek kısa cümle (ör. 'Oakhaven savaşı sırasında yok edildi')",
          "description": "Güncellenmiş açıklama",
          "evidence": "Kısa alıntı"
        }
      ],
      "new_terms": [
        {
          "name": "Terim Adı",
          "first_page": 80,
          "intro_description": "İlk bahsedildiğindeki ilk tanım.",
          "page": 99,
          "description": "Tanım veya evren açıklaması",
          "evidence": "Kısa alıntı"
        }
      ],
      "term_state_updates": [
        {
          "name": "Bilinen listeyle veya bu grubun daha önceki bir bölümünde tanıtılan terimle eşleşen ad",
          "page": 95,
          "change": "Anlayış veya kullanımda neyin değiştiğini belirten tek kısa cümle",
          "description": "Güncellenmiş tanım",
          "evidence": "Kısa alıntı"
        }
      ]
    }
  ]
}

BU GRUPTAKİ BÖLÜM METİNLERİ:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Aşağıdaki kitap ayrıntılarını ve İçindekiler tablosunu analiz edin:

Başlık: %s
Yazar: %s
Konular: %s
Açıklama: %s

İçindekiler:
%s

Bu eserin aşağıdakilerden hangisi olduğunu belirleyin:
1. "anthology" (her biri kendi bağımsız anlatısına veya kadrosuna sahip bağımsız kısa öyküler, denemeler veya uzun öyküler derlemesi, ör. "Sherlock Holmes'un Maceraları", "Dublinliler", "Nefes", "Kadınsız Erkekler").
2. "novel" (bölümlere, kısımlara veya perdelere ayrılmış tek bir birleşik roman, ör. "Gurur ve Önyargı", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (tek bir ciltte bir arada yayımlanan tam uzunluktaki romanlardan oluşan çok ciltli bir derleme, ör. "Yüzüklerin Efendisi: Üç Cilt Bir Arada", "Otostopçunun Galaksi Rehberi: Tam Serisi", "Percy Jackson: Kitaplar 1-3").
4. "non_fiction" (bölümlere ayrılmış tek bir kurgu dışı inceleme, tarih veya akademik kitap).

SADECE şu alanlara sahip bir JSON nesnesi döndürün:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 ile 1.0 arasında,
  "reasoning": "kısa açıklama (tek cümle)"
}]],

    -- System instruction
    system_instruction = "Uzman bir edebiyat araştırmacısısın. Cevabın SADECE geçerli JSON formatında olmalıdır. Verilerin yüksek derecede doğru olduğundan ve kesinlikle sağlanan bağlamla ilgili olduğundan emin ol.",

    -- Fallback strings
    fallback = {
        no_biography = "Biyografi Mevcut Değil",
        no_description = "Açıklama Yok",
        not_specified = "Belirtilmemiş",
        unknown_author = "Bilinmeyen Yazar",
        unknown_book = "Bilinmeyen Kitap",
        unnamed_character = "İsimsiz Karakter",
        unnamed_person = "İsimsiz Kişi"
    }
}
