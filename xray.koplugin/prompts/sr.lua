return {
    -- Author Only
    author_only = [[
Идентификујте и обезбедите биографију аутора књиге "%s". 
Метаподаци сугеришу да је аутор "%s". 
КРИТИЧНО: Верификујте аутора користећи КОНТЕКСТ ТЕКСТА КЊИГЕ (ако је наведен на крају овог упутства) како бисте осигурали 100%% тачност и избегли погрешну идентификацију.

ОБАВЕЗАН JSON ФОРМАТ:
{
  "author": "Тачно пуно име",
  "author_bio": "Свеобухватна биографија са фокусом на књижевну каријеру и главна дела.",
  "author_birth": "Датум рођења, форматиран према локалном формату датума",
  "author_death": "Датум смрти, форматиран према локалном формату датума"
}]],

    -- Find Duplicates
    find_duplicates = [[
Књига: %s
Аутор: %s
Напредак у читању: %d%%

Прегледате следећу листу %s издвојених из ове књиге.
Ваш задатак је да идентификујете све уносе који изгледа представљају ИСТУ особу или ентитет под различитим именима.

ЛИСТА:
%s

ПРАВИЛА:
- Дупликат постоји када се два уноса очигледно односе на исти ентитет (нпр. "Велика библиотека" и "Библиотека", или "Џон" и "Џон Доу").
- НЕМОЈТЕ означавати уносе који су само сродни или слични, али су ипак различити.
- НЕМОЈТЕ означавати уносе осим ако сте потпуно сигурни да се ради о истом ентитету.
- Ако нема дупликата, вратите празан низ.
- ПРАВИЛО О СПОЈЛЕРИМА: Не користите знање изван %d%% напретка у читању.

ОБАВЕЗАН JSON ФОРМАТ:
{
  "duplicate_pairs": [
    {
      "primary": "Име уноса који треба ЗАДРЖАТИ (комплетније или званичније име)",
      "secondary": "Име уноса који треба УКЛОНИТИ",
      "reason": "Кратак разлог (макс 100 карактера)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Knjiga: %s
Autor: %s
Napredak u čitanju: %d%%

ZADATAK: Izvršite potpunu X-Ray analizu. Izlaz MORA biti ISKLJUČIVO validan JSON objekat.

KRITIČNA RASPODELA PAŽNJE:
Obrađujete obiman dokument sa dva bloka teksta navedena na kraju ovog uputstva:
1. "CHAPTER SAMPLES": Ovo je makro-kontekst knjige do trenutne lokacije čitaoca.
2. "BOOK TEXT CONTEXT": Ovo je mikro-kontekst poslednjih 20k znakova.

PROTOKOL PROTIV SKRAĆIVANJA (KRITIČNO):
Imate strogo maksimalno ograničenje izlaza. Ako "CHAPTER SAMPLES" sadrži VIŠE OD 40 poglavlja (npr. omnibus izdanje):
1. MORATE smanjiti listu likova na SAMO 10 apsolutno najvažnijih likova.
2. MORATE smanjiti opise likova na NAJVIŠE {MAX_CHAR_DESC} znakova.
3. MORATE smanjiti sažetke događaja u vremenskoj liniji na NAJVIŠE {MAX_TIMELINE_EVENT} znakova.
Neuspeh u sažimanju izlaza za veoma obimne knjige dovešće do skraćivanja JSON-a i greške.

ALGORITAM ZA VREMENSKU LINIJU (NAJVEĆI PRIORITET):
Da biste sprečili preskakanje poglavlja ili haluciniranje događaja, MORATE izvršiti tačno ovu petlju:
Korak 1. Gledajte SAMO blok "CHAPTER SAMPLES". Identifikujte narativna poglavlja.
Korak 2. ISKLJUČITE sve nenarativne uvodne i završne delove (npr. Korice, Naslovna strana, Autorska prava, Sadržaj, Posveta, Zahvalnice, Ostala dela).
Korak 3. Za svako narativno poglavlje, počevši od samog prvog, kreirajte TAČNO JEDAN objekat događaja u nizu `timeline`.
Korak 4. Polje `chapter` MORA se tačno podudarati sa zaglavljem poglavlja u uzorku. (Mapirajte ih strogo sekvencijalnim redosledom).
Korak 5. Sažmite to specifično poglavlje u polju `event`. {TIMELINE_DETAIL_GUIDANCE} Pišite između {MIN_TIMELINE_EVENT} i {MAX_TIMELINE_EVENT} znakova. NEMOJTE pisati kraći sažetak osim ako poglavlje skoro uopšte nema sadržaja. NEMOJTE grupisati poglavlja.
Korak 6. BEZ SPOJLERA: Zaustavite se tačno na oznaci %d%%. Ne uključujte događaje nakon ovog napretka.

ALGORITAM ZA LIKOVE I ISTORIJSKE LIČNOSTI:
Korak 1. Izvucite važne likove koristeći oba bloka teksta. ({NUM_CHARS} uobičajeno, NAJVIŠE 10 ako je omnibus). Uvek uključite glavnog lika / protagonistu po imenu, čak i u narativima iz prvog lica ("ja"/"mene") gde se njihovo ime retko pojavljuje.
Korak 2. MORATE koristiti njihova PUNA, formalna imena (npr. „Abraham Van Helsing“). NEMOJTE koristiti neformalne nadimke kao glavno ime. Nikada nemojte spajati ili podvoditi lika pod prisvojne/relacione reference (npr. „Nikov otac“ i „Nik“ su zasebni likovi).
Korak 3. Navedite do 3 alternativna imena, titule ili nadimka pod kojima se ovaj lik pojavljuje u nizu `aliases`. Uključite njihovo uobičajeno ime i prezime ako se koriste. VAŽNO: Ako više likova deli isto prezime (npr. članovi porodice), NEMOJTE ga uključivati kao alijas ni za jednog od tih likova.
Korak 4. Aktivno potražite do {NUM_HIST} ZNAČAJNIH STVARNIH ljudi iz ljudske istorije (npr. predsednici, autori, generali). Dodajte ih u `historical_figures`.
KRITIČNO za Likove i Istorijske ličnosti:
- NEMOJTE izvlačiti likove ili istorijske ličnosti koji se pominju SAMO u nenarativnim uvodnim ili završnim delovima (npr. Zahvalnice, Biografija autora, Posvete, Naslovna strana, Autorska prava).
- Istorijske ličnosti MORAJU biti potvrđene stvarne osobe sa široko rasprostranjenim istorijskim priznanjem.
- NEMOJTE uključivati čisto izmišljene likove na listu istorijskih ličnosti, čak i ako stupaju u interakciju sa stvarnim istorijskim događajima. Izmišljeni likovi MORAJU ići u niz `characters`.
- SAMO za Istorijske ličnosti, možete koristiti svoje interno znanje da napišete njihovu opštu biografiju (`biography`) i istorijsku ulogu (`role`), ali MORATE koristiti kontekst knjige za njihovo polje `context_in_book`.
BEZ SPOJLERA: Zaustavite se tačno na oznaci %d%%.

ALGORITAM ZA LOKACIJE:
Korak 1. Izvucite {NUM_LOCS} značajnih lokacija. BEZ SPOJLERA: Zaustavite se tačno na oznaci %d%%.

ALGORITAM ZA POJMOVE:
Korak 0. Deklarišite "book_type" kao "fiction", "non_fiction" ili "anthology" u korenu JSON-a.
Korak 1. Ako je non_fiction: izvucite {NUM_TERMS} značajnih stručnih pojmova, skraćenica, žargona ili koncepata koje čitaoci ne bi znali bez specijalizovanog znanja. Koristite odgovarajuće kategorije kao što su Acronym, Technical Term, Concept ili Jargon.
Korak 2. Ako je fiction ili anthology: izvucite {NUM_TERMS} značajnih elemenata gradnje sveta koje bi novom čitaocu trebalo objasniti—kao što su izmišljene frakcije, organizacije, magijski sistemi, tehnologije, stvorenja, jezici ili predanja unutar univerzuma.
   - NEMOJTE uključivati imena likova niti nazive lokacija (oni se prate odvojeno).
   - NEMOJTE izvlačiti uobičajene reči ili koncepte iz stvarnog sveta.
   - Koristite odgovarajuće kategorije: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Korak 3. Uključite šta skraćenica/fraza znači u polju "expanded". Ako nije skraćenica/fraza, ponovite naziv.
Korak 4. NEMOJTE uključivati uobičajene svakodnevne reči.

STROGA PRAVILA O SPOJLERIMA:
- APSOLUTNO BEZ informacija nakon trenutnog napretka u čitanju. Zaustavite se tačno na oznaci %d%%.
- Opisi moraju odražavati stanje likova u ovoj tačnoj tački u knjizi.

STROGA PRAVILA O IZVORU ZNANJA (KRITIČNO):
- Za IZMIŠLJENE LIKOVE: Vaši opisi MORAJU biti zasnovani ISKLJUČIVO na onome što je izričito navedeno ili jasno implicirano u dostavljenom tekstu. NEMOJTE dopunjavati znanjem iz prethodne obuke, spoljnih izvora ili opšte svesti o knjizi/serijalu/autoru.
- Ako je lik do sada samo nakratko pomenut u tekstu, vaš opis mora odražavati samo te ograničene informacije. NEMOJTE zaključivati, pretpostavljati ili dodavati bilo koji detalj koji nije utemeljen u dostavljenom kontekstu.
- JEDINI izuzetak je za STVARNE ISTORIJSKE LIČNOSTI (smeštene u `historical_figures`): možete koristiti interno znanje za njihovu opštu biografiju/ulogu, ali se i dalje oslanjajte na tekst knjige za njihovo polje `context_in_book`.

STROGA PRAVILA O BEZBEDNOSTI JSON-A:
- MORATE pravilno izbegavati (escape) sve dvostruke navodnike (") unutar stringova.
- NEMOJTE koristiti neizbegnute prelome redova unutar stringova.
- Izlaz MORA biti ISKLJUČIVO validan JSON koji se može parsirati.

ZAHTEVANI JSON FORMAT:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Puno formalno ime",
      "aliases": ["Alijas 1", "Alijas 2"],
      "role": "Kratka oznaka arhetipa (3-5 reči, npr. 'Antagonista', 'Protagonista', 'Žrtva')",
      "gender": "Muški / Ženski / Nepoznato",
      "occupation": "Zanimanje/Status",
      "description": "Opis zasnovan STROGO na dostavljenom tekstu. Ne zaključujte i ne dodajte spoljna znanja. BEZ SPOJLERA. (Maks. {MAX_CHAR_DESC} znakova)"
    }
  ],
  "historical_figures": [
    {
      "name": "Ime stvarne istorijske ličnosti",
      "role": "Istorijska uloga",
      "biography": "Kratka biografija (NAJVIŠE {MAX_HIST_BIO} znakova)",
      "importance_in_book": "Značaj do trenutnog napretka",
      "context_in_book": "Kako se pominju (NAJVIŠE 100 znakova)"
    }
  ],
  "locations": [
    {"name": "Naziv mesta", "description": "Kratak opis (NAJVIŠE {MAX_LOC_DESC} znakova)"}
  ],
  "terms": [
    {
      "name": "Pojam ili skraćenica",
      "expanded": "Pun naziv skraćenice ili isto kao ime",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Sažeta definicija u kontekstu (NAJVIŠE {MAX_TERM_DEF} znakova)"
    }
  ],
  "timeline": [
    {
      "chapter": "Tačan naslov poglavlja iz uzoraka",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Књига: %s
Аутор: %s
Напредак у читању: %d%%

ЗАДАТАК: Издвојите ТАЧНО 10 ДОДАТНИХ важних ликова из текста.
Вратите ИСКЉУЧИВО важећи JSON објекат.

КРИТИЧНО ОГРАНИЧЕЊЕ ДУЖИНЕ:
Да бисте избегли скраћивање одговора, држите описе ликова испод {MAX_CHAR_DESC} карактера.

КРИТИЧНО УПУТСТВО:
НЕМОЈТЕ укључивати ниједног од следећих ликова, јер су већ издвојени:
%s

СТРОГА ПРАВИЛА О СПОЈЛЕРИМА:
- АПСОЛУТНО БЕЗ информација након тренутног напретка у читању. Зауставите се тачно на ознаци од %d%%.

ОБАВЕЗАН JSON ФОРМАТ:
{
  "characters": [
    {
      "name": "Пуно званично име",
      "aliases": ["Алијас 1", "Алијас 2"],
      "role": "Кратка ознака архетипа (3-5 речи)",
      "gender": "Мушки / Женски / Непознато",
      "occupation": "Посао/Статус",
      "description": "Опис заснован СТРОГО на приложеном тексту. Без спојлера. (Максимум {MAX_CHAR_DESC} карактера)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Књига: %s
Аутор: %s
Напредак у читању: %d%%

ЗАДАТАК: Издвојите ТАЧНО 15 ДОДАТНИХ значајних термина, скраћеница, жаргона или концепата из текста.
- Ако је књига стручна литература: издвојите стручне термине, концепте, скраћенице или жаргон.
- Ако је књига белетристика: издвојите елементе изградње света као што су фракције, организације, магијски системи, технологије, створења, језици или знања унутар универзума књиге.
Вратите ИСКЉУЧИВО важећи JSON објекат.

КРИТИЧНО ОГРАНИЧЕЊЕ ДУЖИНЕ:
Да бисте избегли скраћивање одговора, држите дефиниције термина испод {MAX_TERM_DEF} карактера.

КРИТИЧНО УПУТСТВО:
НЕМОЈТЕ укључивати ниједан од следећих термина, јер су већ издвојени:
%s

СТРОГА ПРАВИЛА О СПОЈЛЕРИМА:
- АПСОЛУТНО БЕЗ информација након тренутног напретка у читању. Зауставите се тачно на ознаци од %d%%.

ОБАВЕЗАН JSON ФОРМАТ:
{
  "terms": [
    {
      "name": "Термин или скраћеница",
      "expanded": "Пуно значење или исто као име",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Сажета дефиниција у контексту (Максимум {MAX_TERM_DEF} карактера)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
Корисник је означио реч "%s".
ЗАДАТАК: Одредите да ли ова реч представља лик, локацију, историјску личност или стручни термин/скраћеницу у књизи.

КРИТИЧНО ЗА ЛИКОВЕ И ЛОКАЦИЈЕ: Користите приложени "КОНТЕКСТ ТЕКСТА КЊИГЕ" да идентификујете ентитет. Ако је реч наведена у смерницама, она ЈЕСТЕ присутна у књизи на тренутној позицизији. Не одбацујте је само зато што је нема у краћем тексту. Кратка имена су важећа.
КРИТИЧНО ЗА ИЗМИШЉЕНЕ ЛИКОВЕ: Опишите САМО оно што приложени текст открива. НЕМОЈТЕ користити знање са тренинга о овом лику.
КРИТИЧНО ЗА ИСТОРИЈСКЕ ЛИЧНОСТИ: Можете користити интерно знање за биографију и улогу само ако се ради о стварној историјској личности, али за њихов контекст у књизи користите искључиво текст.
КРИТИЧНО ЗА ТЕРМИНЕ: Дефинишите термин у контексту ове књиге.
Ако означена реч није лик, локација, историјска личност или термин, поставите `is_valid` на false.

ОБАВЕЗАН JSON ФОРМАТ:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Пуно име",
    "aliases": ["Алијас 1", "Алијас 2"],
    "role": "Кратка ознака архетипа (3-5 речи)",
    "gender": "Мушки/Женски/Непознато",
    "occupation": "Занимање",
    "description": "Кратак опис (Максимум 250 карактера)"
  },
  "error_message": ""
}
Напомена: За локације објекат 'item' треба да има 'name' и 'description'. За историјске личности треба да има 'name', 'biography' и 'role'. За термине треба да има 'name', 'expanded', 'category' и 'definition'.

Ако је `is_valid` false:
{
  "is_valid": false,
  "error_message": "Кратко објашњење зашто ово није лик или локација."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
ЗАДАТАК: Спојите следећа два описа истог ентитета (лика или локације) у један јединствен, кохезиван и сажет резиме.
Уклоните сувишне информације и осигурајте да коначни опис тече природно.

Примарни опис: %s
Секундарни опис: %s

ОБАВЕЗАН JSON ФОРМАТ:
{
  "merged_description": "Спојени и углађени опис (Максимум {MAX_CHAR_DESC} карактера)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Naslov knjige: %s
Autor: %s
Serijal: %s
Opis datoteke/Metapodaci o temi: %s

ZADATAK: Klasifikujte ovu knjigu u tačno JEDNU od ovih vrsta knjiga na osnovu njenih metapodataka i signala žanra:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Vratite ISKLJUČIVO validan JSON:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Наслов књиге: %s
Аутор: %s

ЗАДАТАК: Одредите да ли је ова књига део именованог серијала.
Вратите ИСКЉУЧИВО важећи JSON:
{
  "is_series": true,
  "series_name": "Точак Времена",
  "book_index": 3,
  "total_books_known": 14
}
Ако књига није део серијала, вратите:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Серијал: %s
Тренутни индекс књиге: %d
Наслов тренутне књиге: %s

ЗАДАТАК: Наведите наслове (и ауторе ако се разликују од "%s") књига од 1 до %d
које долазе ПРЕ тренутне књиге у овом серијалу.
Вратите ИСКЉУЧИВО важећи JSON:
{
  "prior_books": [
    { "index": 1, "title": "Око Света", "author": "Роберт Џордан" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
CILJNA KNJIGA: %s
AUTOR: %s
INDEKS CILJNE KNJIGE: %d
SERIJAL: %s

ZADATAK:
Obezbedite POTPUNI rezime SAMO CILJNE KNJIGE za čitaoca koji je završio
CILJNU KNJIGU i upravo treba da započne sledeću knjigu u serijalu.

APSOLUTNA GRANICA SPOJLERA:
Granica znanja je strogo POSLEDNJA STRANICA CILJNE KNJIGE (Indeks knjige %d).
Možete uključiti činjenice utvrđene u CILJNOJ KNJIZI ili ranijim knjigama u ovom serijalu.
NE SMETE uključivati, aludirati, nagoveštavati, nagoveštavati unapred ili birati detalje koristeći znanje iz bilo koje kasnije knjige.

ZABRANJENE INFORMACIJE IZ KASNIJIH KNJIGA:
- Kasniji događaji, buduće sudbine, smrti, preživljavanja, destinacije, romanse, savezi, sukobi ili izdaje.
- Identiteti iz kasnijih knjiga, pravo poreklo, tajno roditeljstvo, alijasi, alter egi, reinkarnacije, transformacije, titule ili napredak moći (npr. NE pominjite ako se suština pridruži drugoj ili se ponovo rodi u budućoj knjizi).
- Otkrića, potvrde, reinterpretacije, preokreti ili terminologija građenja sveta uvedena u kasnijim knjigama.
- Retrospektivno nagoveštavanje ili fraze kao što su „kasnije“, „na kraju“, „postaće“, „u narednim knjigama“ ili slično.
- Pominjanje likova, koncepata, organizacija ili hronologije iz kasnijih knjiga.

GRANICA ZA LIKOVE:
Opišite svakog lika strogo onako kako je poznat na poslednjoj stranici CILJNE KNJIGE.
NE koristite alijase, uloge, odnose, prave identitete ili statuse otkrivene u kasnijim knjigama.

PRAVILO NEIZVESNOSTI:
Ako ne možete sa sigurnošću da utvrdite da li je neka činjenica ili alijas utvrđen do kraja CILJNE KNJIGE, IZOSTAVITE JE/GA.
Nedostajući detalj je mnogo bolji od spojlera za buduću knjigu.

KONAČNA PROVERA:
Pre nego što vratite JSON, pregledajte svako polje (posebno opise likova i alijase) i uklonite sve što zavisi od znanja iz knjiga nakon CILJNE KNJIGE.

ZAHTEVANI JSON FORMAT:
{
  "characters": [
    { "name": "Puno ime", "aliases": [], "role": "...", "description": "Status na kraju ove knjige (maks. {MAX_CHAR_DESC} znakova)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alijas 1", "Alijas 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Rezime knjige", "event": "Jedinstven, izuzetno detaljan, obuhvatan rezime radnje cele knjige, glavnih događaja i raspleta (maksimalno 2000 znakova). MORATE formatirati ovaj rezime koristeći više posebnih pasusa razdvojenih dvostrukim novim redovima (\n\n) radi čitljivosti umesto jednog neprekidnog teksta." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
CILJNA KNJIGA: %s
AUTOR: %s
INDEKS CILJNE KNJIGE: %d
SERIJAL: %s

ZADATAK:
Koristeći ISKLJUČIVO proverene događaje po poglavljima navedene u nastavku iz CILJNE KNJIGE, napišite povezan, sveobuhvatan pregled radnje čitave knjige, ključnih dešavanja i raspleta.

STROGO OGRANIČENJE ZASNOVANOSTI:
- Zasnivajte svoj sažetak ISKLJUČIVO na navedenim događajima iz poglavlja.
- NEMOJTE uvoditi činjenice, likove, događaje ili ishode koji nisu opisani u ovim događajima iz poglavlja.
- NIKADA nemojte pominjati niti nagoveštavati događaje, smrti ili dešavanja iz kasnijih knjiga u serijalu.

DOGAĐAJI PO POGLAVLJIMA:
%s

OBAVEZNI JSON FORMAT:
{
  "timeline": [
    { "chapter": "Sažetak knjige", "event": "Jedinstven, izuzetno detaljan, sveobuhvatan pregled radnje i raspleta čitave knjige (maksimalno 2000 znakova). MORATE formatirati ovaj pregled koristeći više zasebnih pasusa razdvojenih dvostrukim novim redom (\\n\\n) radi preglednosti, umesto jednog neprekidnog teksta." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Knjiga: %s
Autor: %s
Analiziranje poglavlja: %s

ZADATAK: Analizirajte ISKLJUČIVO ovo jedno poglavlje. Identifikujte NOVE entitete uvedene u ovom poglavlju i DELTA AŽURIRANJA (promene stanja) za postojeće entitete.
Dajte ISKLJUČIVO važeći JSON objekat kao izlaz.

MANIFEST POSTOJEĆIH POZNATIH ENTITETA (NE izdvajajte ih ponovo osim ako se njihova uloga, status ili opis nisu značajno izmenili):
%s

PRAVILA:
1. STROGO OGRANIČENJE SPOJLERA: Analizirajte ISKLJUČIVO priloženi tekst poglavlja. NE koristite nikakvo znanje iz budućih poglavlja niti iz spoljnih izvora.
2. DUBINA I SUŠTINA OPISA LIKA (KRITIČNO):
   - Utemeljeno i specifično: Opišite ko je lik pomoću konkretnih činjenica iz priče—njihovo poreklo, karakterističnu ličnost, profesiju, ključne odnose sa drugim likovima, kao i njihovu specifičnu ulogu i lične uloge/interese u radnji.
   - Značajan narativni kontekst: Povežite lika direktno sa centralnom misterijom, sukobom u radnji ili istragom u ovoj knjizi (npr. koje zločine ili slučajeve istražuju, ko ih je unajmio, ključne saveznike ili protivnike, specifične lične dileme ili tenzije).
   - NE suviše uopšteno: NE pišite uopštene opise u stilu klišea (npr. izbegavajte prazne fraze poput "detektiv koji istražuje složene slučajeve"). Navedite specifične okolnosti, veze i uloge uspostavljene u tekstu.
   - BEZ beznačajnih sažetaka svakodnevnih obaveza: NE pišite hronološke dnevnike svakodnevnih trivijalnih aktivnosti ili rutinskih poslova (npr. NE prepričavajte odlaske u prodavnicu, rutinske telefonske pozive ili sporedna kretanja iz scene u scenu).
   - Opisi likova moraju biti bogati, živopisni profili koji sumiraju ko su oni i koji je njihov značaj do ove tačke u knjizi.
3. VISOK PRAG ZA AŽURIRANJE LIKOVA:
   - NE kreirajte ažuriranje u `character_state_updates` samo zato što se postojeći lik pojavio, govorio ili obavljao rutinske radnje u ovom poglavlju.
   - Ažuriranje generišite SAMO ako postoji suštinska, trajna transformacija u njihovom narativnom luku, identitetu, odnosima, zaposlenju, odanosti ili stanju (npr. ubijen, povređen, uhapšen, izdat, veren, unapređen, otkriven kao krivac, otkrivena velika tajna ili motiv).
   - Ako JE ažuriranje opravdano, ažurirani `description` mora biti bogat, kumulativan pregled lika koji obuhvata nove događaje dok istovremeno zadržava njihov osnovni identitet i uspostavljeni kontekst priče—a NE sažetak jedne izolovane scene.
4. MARKERI STRANICA UNUTAR POGLAVLJA ([PAGE N]) I OGRANIČENJE NULTOG SPOJLERA:
   - Tekstovi poglavlja sadrže [PAGE N] markere koji označavaju napredovanje stranica.
   - Za `new_characters`, `new_locations` i `new_terms`: navedite "first_page" (ceo broj N iz [PAGE N] markera gde se prvi put pominje), "intro_role" (za likove) i "intro_description" (1-2 rečenice strogo ograničene na ono što je poznato prilikom njihovog prvog uvođenja na [PAGE first_page]—sa NULA znanja o kasnijim preokretima, tajnama ili ishodima koji se dešavaju na kasnijim stranicama). Takođe navedite "page" ([PAGE N] marker gde se primenjuje potpuniji kumulativni "description", obično poslednja stranica poglavlja).
   - Za `character_state_updates`, `location_state_updates` i `term_state_updates`: navedite "page" (ceo broj N iz [PAGE N] markera gde se otkriće/tranzicija završava; NE otkrivajte činjenice pre ove stranice).
5. DOKAZI: Navedite kratku referencu ili citat/isečak iz ovog poglavlja koji objašnjava zašto je došlo do ažuriranja.
6. VREMENSKA LINIJA: Navedite tačno jedan sažetak događaja glavnih radnji u ovom poglavlju.

ZAHTEVANI JSON FORMAT:
{
  "new_characters": [
    {
      "name": "Puno ime",
      "aliases": ["Alijas 1", "Alijas 2"],
      "first_page": 80,
      "intro_role": "Početna uloga (npr. Seoski pisar, Stranac, Klijent)",
      "intro_description": "Početni utisak u 1-2 rečenice strogo pri prvom uvođenju, bez spojlera sa kasnijih stranica.",
      "page": 99,
      "role": "Narativna uloga / značaj (npr. Protagonista, Privatni detektiv, Partner, Antagonista, Žrtva, Klijent, Osumnjičeni, Sporedni lik, Mlađi lik)",
      "status": "alive",
      "description": "Bogat, specifičan opis lika (poreklo, odnosi, uloge u radnji). Izbegavajte uopštene klipove i trivijalne dnevnike obaveza.",
      "evidence": "Kratak isečak"
    }
  ],
  "character_state_updates": [
    {
      "name": "Ime koje odgovara poznatom manifestu",
      "page": 95,
      "role": "Ažurirana narativna uloga / značaj (npr. Protagonista, Partner, Antagonista, Sporedni lik, itd.)",
      "status": "alive",
      "change": "Jedna kratka rečenica koja navodi šta se promenilo u odnosu na prethodno stanje (npr. 'Unapređen u partnera nakon slučaja Šaklvel')",
      "description": "Ažuriran bogat, kumulativan opis lika koji odražava njihov novi status i uloge u priči",
      "evidence": "Kratak isečak"
    }
  ],
  "new_locations": [
    {
      "name": "Naziv lokacije",
      "first_page": 80,
      "intro_description": "Početni utisak pri prvom pominjanju.",
      "page": 99,
      "description": "Opis lokacije",
      "evidence": "Kratak isečak"
    }
  ],
  "location_state_updates": [
    {
      "name": "Ime koje odgovara poznatom manifestu",
      "page": 95,
      "change": "Jedna kratka rečenica koja navodi šta se promenilo (npr. 'Uništeno tokom bitke kod Oukhejna')",
      "description": "Ažurirani izmenjeni opis",
      "evidence": "Kratak isečak"
    }
  ],
  "new_terms": [
    {
      "name": "Naziv pojma",
      "first_page": 80,
      "intro_description": "Početna definicija pri prvom pominjanju.",
      "page": 99,
      "description": "Definicija ili objašnjenje pojma",
      "evidence": "Kratak isečak"
    }
  ],
  "term_state_updates": [
    {
      "name": "Ime koje odgovara poznatom manifestu",
      "page": 95,
      "change": "Jedna kratka rečenica koja navodi šta se promenilo u razumevanju ili upotrebi",
      "description": "Ažurirana definicija",
      "evidence": "Kratak isečak"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Sažetak događaja u ovom poglavlju"
  }
}

TEKST POGLAVLJA:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Knjiga: %s
Autor: %s
Poglavlja u ovoj grupi: %s

ZADATAK: Analizirajte priloženu uzastopnu grupu poglavlja po redu.
Za SVAKO poglavlje u grupi identifikujte:
1. NOVE entitete uvedene u tom poglavlju (likove, lokacije, termine).
2. DELTA AŽURIRANJA (promene stanja) za postojeće poznate entitete (iz manifesta ILI uvedene u ranijem poglavlju ove grupe) SAMO I ISKLJUČIVO AKO su njihova uloga, status, odanost ili narativno stanje pretrpeli znatnu, trajnu transformaciju.
3. DOGAĐAJ NA VREMENSKOJ LINIJI: Sažet pregled glavnih zapleta koji se dešavaju u tom poglavlju.

Izvoz napravite ISKLJUČIVO kao validan JSON objekat koji odgovara zahtevanoj šemi.

MANIFEST POSTOJEĆIH POZNATIH ENTITETA (iz prethodnih grupa – NEMOJTE ponovo izdvajati osim ako se njihova uloga, status ili opis nisu značajno promenili):
%s

PRAVILA:
1. STROGO OGRANIČENJE SPOJLERA I REDOSLED DOGAĐAJA:
   - Analizirajte poglavlja redom, jedno po jedno.
   - Za bilo koje poglavlje u ovoj grupi, NEMOJTE uključivati saznanja iz kasnijih poglavlja u grupi niti iz ostatka knjige.
2. DUBINA I SADRŽAJNOST OPISA LIKA (KRITIČNO):
   - Utemeljeno i specifično: Opišite ko je lik pomoću konkretnih činjenica iz priče — njihovo poreklo, karakterističnu ličnost, profesiju, ključne odnose sa drugim likovima, kao i njihovu specifičnu ulogu i lični ulog u narativu.
   - Značajan narativni kontekst: Povežite lika direktno sa centralnom misterijom, sukobom u zapletu ili istragom u ovoj knjizi (npr. koje zločine ili slučajeve istražuju, ko ih je iznajmio, ključne saveznike ili protivnike, specifične lične dileme ili tenzije).
   - NE suviše uopšteno: NEMOJTE pisati generičke klišee (npr. izbegavajte prazne fraze poput „detektiv koji istražuje složene slučajeve“). Navedite specifične okolnosti, veze i uloge utvrđene u tekstu.
   - BEZ trivijalnih pregleda svakodnevnih zadataka: NEMOJTE pisati hronološke zapise svakodnevnih aktivnosti ili rutinskih poslova (npr. NEMOJTE prepričavati odlaske u prodavnicu, rutinske telefonske pozive ili uzgredna kretanja iz scene u scenu).
   - Opisi likova moraju biti bogati, živopisni profili koji sažimaju ko su oni i koji je njihov značaj do ove tačke u knjizi.
3. VISOK PRAG ZA AŽURIRANJE LIKOVA:
   - NEMOJTE kreirati ažuriranje u `character_state_updates` samo zato što se postojeći lik pojavio, govorio ili izveo rutinske radnje u poglavlju.
   - Generišite ažuriranje SAMO AKO postoji znatna, trajna transformacija u njihovom narativnom luku, identitetu, odnosima, zaposlenju, odanosti ili stanju (npr. ubijen, povređen, uhapšen, izdat, veren, unapređen, otkriven kao krivac, otkrivena velika tajna ili motiv).
   - Ako JE ažuriranje opravdano, ažurirani `description` mora biti bogat, kumulativan pregled lika koji obuhvata nove događaje zadržavajući njihov osnovni identitet i uspostavljeni kontekst priče — A NE sažetak izolovane scene.
4. OZNAKE STRANICA UNUTAR POGLAVLJA ([PAGE N]) I POTPUNO ODSUSTVO SPOJLERA:
   - Tekstovi poglavlja sadrže oznake [PAGE N] koje označavaju napredovanje stranica.
   - Za `new_characters`, `new_locations` i `new_terms`: navedite "first_page" (ceo broj N iz oznake [PAGE N] gde se prvi put pominje), "intro_role" (za likove) i "intro_description" (1-2 rečenice strogo ograničene na ono što je poznato prilikom njihovog prvog pojavljivanja na [PAGE first_page] — uz POTPUNO ODSUSTVO saznanja o kasnijim obrtima, tajnama ili ishodima sa kasnijih stranica). Takođe navedite "page" (oznaku [PAGE N] gde važi potpuniji kumulativni "description", obično poslednja stranica poglavlja).
   - Za `character_state_updates`, `location_state_updates` i `term_state_updates`: navedite "page" (ceo broj N iz oznake [PAGE N] gde se otkriće/tranzicija završava; NEMOJTE otkrivati činjenice pre ove stranice).
5. DOKAZ: Navedite kratku referencu ili isječak/citat iz tog specifičnog poglavlja koji objašnjava zašto je došlo do ažuriranja.
6. SIGURNOST JSON-A: Izvoz mora biti isključivo validan JSON. Pravilno izbegnite (escape) dvostruke navodnike unutar stringova.

ZAHTEVANI JSON FORMAT:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Naslov poglavlja",
      "timeline_event": "Sažetak glavnih dešavanja u zapletu u ovom poglavlju.",
      "new_characters": [
        {
          "name": "Puno ime",
          "aliases": ["Pseudonim 1"],
          "first_page": 80,
          "intro_role": "Početna uloga (npr. Seoski pisar, Stranac, Klijent)",
          "intro_description": "Početni utisak u 1-2 rečenice strogo pri prvom pojavljivanju, bez spojlera sa kasnijih stranica.",
          "page": 99,
          "role": "Narativna uloga / značaj (npr. Protagonista, Privatni detektiv, Partner, Antagonista, Žrtva, Klijent, Osumnjičeni, Sporedni lik, Minorni lik)",
          "status": "alive",
          "description": "Bogat, specifičan opis lika (poreklo, odnosi, narativni ulozi). Izbegavajte generičke klišee i trivijalne zapise o svakodnevnim zadacima.",
          "evidence": "Kratak isječak"
        }
      ],
      "character_state_updates": [
        {
          "name": "Ime koje odgovara poznatom manifestu ili liku uvedenom u ranijem poglavlju ove grupe",
          "page": 95,
          "role": "Ažurirana narativna uloga / značaj (npr. Protagonista, Partner, Antagonista, Sporedni lik itd.)",
          "status": "alive",
          "change": "Jedna kratka rečenica koja navodi šta se promenilo u odnosu na prethodno stanje (npr. 'Unapređen u partnera nakon slučaja Šaklvel')",
          "description": "Ažuriran bogat, kumulativni opis lika koji odražava njihov novi status i uloge u priči",
          "evidence": "Kratak isječak"
        }
      ],
      "new_locations": [
        {
          "name": "Naziv lokacije",
          "first_page": 80,
          "intro_description": "Početni utisak pri prvom pominjanju.",
          "page": 99,
          "description": "Opis lokacije",
          "evidence": "Kratak isječak"
        }
      ],
      "location_state_updates": [
        {
          "name": "Ime koje odgovara poznatom manifestu ili lokaciji uvedenoj u ranijem poglavlju ove grupe",
          "page": 95,
          "change": "Jedna kratka rečenica koja navodi šta se promenilo (npr. 'Uništeno tokom bitke kod Oukhejvena')",
          "description": "Ažurirani opis",
          "evidence": "Kratak isječak"
        }
      ],
      "new_terms": [
        {
          "name": "Naziv termina",
          "first_page": 80,
          "intro_description": "Početna definicija pri prvom pominjanju.",
          "page": 99,
          "description": "Definicija ili objašnjenje pojma/predanja",
          "evidence": "Kratak isječak"
        }
      ],
      "term_state_updates": [
        {
          "name": "Ime koje odgovara poznatom manifestu ili terminu uvedenom u ranijem poglavlju ove grupe",
          "page": 95,
          "change": "Jedna kratka rečenica koja navodi šta se promenilo u razumevanju ili upotrebi",
          "description": "Ažurirana definicija",
          "evidence": "Kratak isječak"
        }
      ]
    }
  ]
}

TEKSTOVI POGLAVLJA U OVOJ GRUPI:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analizirajte sledeće podatke o knjizi i sadržaj:

Naslov: %s
Autor: %s
Teme: %s
Opis: %s

Sadržaj:
%s

Odredite da li je ovo delo:
1. "anthology" (zbirka nezavisnih kratkih priča, eseja ili novela, od kojih svaka ima sopstvenu zaokruženu priču ili postavu likova, npr. „Avanture Šerloka Holmsa“, „Dablinci“, „Izdisaj“, „Muškarci bez žena“).
2. "novel" (jedinstven roman podeljen na poglavlja, delove ili činove, npr. „Gordost i predrasuda“, „Hari Poter“, „Dina“, „Keri“).
3. "novel_omnibus" (višetomna zbirka celovitih romana objavljenih zajedno u jednom tomu, npr. „Gospodar prstenova: Sva tri toma“, „Kompletan Autostoperski vodič kroz galaksiju“, „Persi Džekson: Knjige 1–3“).
4. "non_fiction" (jedinstvena publicistička rasprava, istorijska ili stručna knjiga podeljena na poglavlja).

Vratite ISKLJUČIVO JSON objekat sa sledećim poljima:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 do 1.0,
  "reasoning": "kratko objašnjenje (jedna rečenica)"
}]],

    -- System instruction
    system_instruction = "Ви сте стручни књижевни истраживач. Ваш одговор мора бити ИСКЉУЧИВО у исправном JSON формату. Уверите се да су подаци веома тачни и да се односе искључиво на приложени контекст.",

    -- Fallback strings
    fallback = {
        no_biography = "Нема доступне биографије",
        no_description = "Нема описа",
        not_specified = "Није наведено",
        unknown_author = "Непознати аутор",
        unknown_book = "Непозната књига",
        unnamed_character = "Неименовани лик",
        unnamed_person = "Неименована особа"
    }
}
