return {
    -- Author Only
    author_only = [[
Zidentyfikuj i przedstaw biografię autora książki "%s". 
Metadane sugerują, że autorem jest "%s". 
1
BARDZO WAŻNE: Zweryfikuj autora za pomocą KONTEKSTU TEKSTU KSIĄŻKI (jeśli został podany na końcu tego monitu), aby zapewnić 100%% dokładności i uniknąć błędnej identyfikacji.

WYMAGANY FORMAT JSON:
{
  "author": "Poprawne pełne imię i nazwisko",
  "author_bio": "Kompleksowa biografia skupiająca się na karierze literackiej i najważniejszych dziełach.",
  "author_birth": "Data urodzenia, sformatowana zgodnie z lokalnym formatem daty",
  "author_death": "Data śmierci, sformatowana zgodnie z lokalnym formatem daty"
}]],

    -- Find Duplicates
    find_duplicates = [[
Książka: %s
Autor: %s
Postęp czytania: %d%%

Przeglądasz następującą listę %s wyodrębnionych z tej książki.
Twoim zadaniem jest zidentyfikowanie wpisów, które wydają się być tą samą encją zapisaną pod różnymi nazwami.

LISTA:
%s

ZASADY:
- Duplikat istnieje, gdy dwa wpisy wyraźnie odnoszą się do tej samej encji (np. "Wielka Biblioteka" i "Wielka Biblioteka" lub "Jan" i "Jan Kowalski").
- NIE oznaczaj wpisów, które są jedynie powiązane lub podobne, ale odrębne.
- NIE oznaczaj wpisów, chyba że masz absolutną pewność, że to ta sama encja.
- Jeśli nie ma duplikatów, zwróć pustą tablicę.
- ZASADA SPOILERA: Nie używaj wiedzy spoza %d%% postępu czytania.

WYMAGANY FORMAT JSON:
{
  "duplicate_pairs": [
    {
      "primary": "Nazwa wpisu do ZACHOWANIA (bardziej kompletna lub oficjalna nazwa)",
      "secondary": "Nazwa wpisu do USUNIĘCIA",
      "reason": "Krótki powód (maks. 100 znaków)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Książka: %s
Autor: %s
Postęp czytania: %d%%

ZADANIE: Przeprowadź pełną analizę X-Ray. Wygeneruj WYŁĄCZNIE poprawny obiekt JSON.

KRYTYCZNY PODZIAŁ UWAGI:
Przetwarzasz ogromny dokument z dwoma blokami tekstu podanymi na końcu tego monitu:
1. "CHAPTER SAMPLES": To jest makrokontekst książki do obecnego miejsca czytelnika.
2. "BOOK TEXT CONTEXT": To jest mikrokontekst ostatnich 20 tysięcy znaków.

PROTOKÓŁ PRZECIWDZIAŁANIA OCIĘCIU (BARDZO WAŻNE):
Masz ścisły maksymalny limit wyjściowy. Jeśli "CHAPTER SAMPLES" zawiera WIĘCEJ NIŻ 40 rozdziałów (np. wydanie zbiorcze/omnibus):
1. MUSISZ ograniczyć listę postaci TYLKO do 10 absolutnie najważniejszych postaci.
2. MUSISZ skrócić opisy postaci do MAKSYMALNIE {MAX_CHAR_DESC} znaków.
3. MUSISZ skrócić podsumowania zdarzeń na osi czasu do MAKSYMALNIE {MAX_TIMELINE_EVENT} znaków.
Niezastosowanie kompresji danych wyjściowych dla obszernych książek spowoduje obcięcie kodu JSON i błąd przetwarzania.

ALGORYTM DLA OSI CZASU (NAJWYŻSZY PRIORYTET):
Aby uniknąć pomijania rozdziałów lub halucynowania wydarzeń, MUSISZ wykonać dokładnie tę pętlę:
Krok 1. Spójrz WYŁĄCZNIE na blok "CHAPTER SAMPLES". Zidentyfikuj rozdziały narracyjne.
Krok 2. WYKLUCZ wszystkie nienarracyjne elementy początkowe i końcowe (np. okładkę, stronę tytułową, prawa autorskie, spis treści, dedykację, podziękowania, inne dzieła autora).
Krok 3. Dla każdego rozdziału narracyjnego, zaczynając od samego pierwszego, utwórz DOKŁADNIE JEDEN obiekt zdarzenia w tablicy `timeline`.
Krok 4. Pole `chapter` MUSI dokładnie odpowiadać nagłówkowi rozdziału w próbce. (Przyporządkuj je ściśle w kolejności sekwencyjnej).
Krok 5. Podsumuj ten konkretny rozdział w polu `event`. {TIMELINE_DETAIL_GUIDANCE} Napisz od {MIN_TIMELINE_EVENT} do {MAX_TIMELINE_EVENT} znaków. NIE pisz krótszego podsumowania, chyba że rozdział prawie nie zawiera treści. NIE grupuj rozdziałów.
Krok 6. BEZ SPOILERÓW: Zatrzymaj się dokładnie na punkcie %d%%. Nie uwzględniaj wydarzeń wykraczających poza ten postęp.

ALGORYTM DLA POSTACI I POSTACI HISTORYCZNYCH:
Krok 1. Wyodrębnij ważne postaci, korzystając z obu bloków tekstu ({NUM_CHARS} standardowo, MAKSYMALNIE 10 w przypadku wydań zbiorczych).
Krok 2. MUSISZ używać ich PEŁNYCH, oficjalnych imion i nazwisk (np. „Abraham Van Helsing”). NIE używaj potocznych pseudonimów jako głównej nazwy.
Krok 3. Podaj do 3 alternatywnych imion, tytułów lub pseudonimów, pod którymi ta postać występuje, w tablicy `aliases`. Uwzględnij ich powszechne imię i nazwisko, jeśli są używane. WAŻNE: Jeśli nazwisko jest dzielone przez wiele postaci (np. członków rodziny), NIE dołączaj go jako aliasu dla żadnej z nich.
Krok 4. Aktywnie wyszukaj do {NUM_HIST} ZNANYCH, RZECZYWISTYCH postaci z historii ludzkości (np. prezydentów, pisarzy, generałów). Dodaj je do `historical_figures`.
BARDZO WAŻNE w przypadku Postaci i Postaci Historycznych:
- NIE wyodrębniaj postaci ani osobistości historycznych wymienionych WYŁĄCZNIE w nienarracyjnych częściach początkowych lub końcowych (np. podziękowaniach, biografii autora, dedykacjach, stronie tytułowej, prawach autorskich).
- Postaci historyczne MUSZĄ być rzeczywistymi ludźmi o powszechnym uznaniu historycznym.
- NIE umieszczaj postaci czysto fikcyjnych na liście postaci historycznych, nawet jeśli wchodzą w interakcje z prawdziwymi wydarzeniami historycznymi. Fikcyjne postaci MUSZĄ trafić do tablicy `characters`.
- WYŁĄCZNIE w przypadku postaci historycznych możesz użyć własnej wiedzy wewnętrznej do opisania ich ogólnej biografii (`biography`) i roli historycznej (`role`), ale MUSISZ użyć kontekstu książki do opisu ich powiązania z książką (`context_in_book`).
BEZ SPOILERÓW: Zatrzymaj się dokładnie na punkcie %d%%.

ALGORYTM DLA LOKACJI:
Krok 1. Wyodrębnij {NUM_LOCS} znaczących lokacji. BEZ SPOILERÓW: Zatrzymaj się dokładnie na punkcie %d%%.

ALGORYTM DLA POJĘĆ:
Krok 0. Zadeklaruj „book_type” jako „fiction” lub „non_fiction” w głównym węźle JSON.
Krok 1. Jeśli non_fiction: wyodrębnij {NUM_TERMS} znaczących terminów technicznych, akronimów, żargonu lub pojęć, których czytelnicy nie znaliby bez specjalistycznej wiedzy. Użyj odpowiednich kategorii, takich jak Acronym, Technical Term, Concept lub Jargon.
Krok 2. Jeśli fiction: wyodrębnij {NUM_TERMS} znaczących elementów wykreowanego świata, które nowy czytelnik musiałby mieć wyjaśnione — takich jak wymyślone frakcje, organizacje, systemy magii, technologie, stworzenia, języki lub wiedza o uniwersum (lore).
   - NIE uwzględniaj imion postaci ani nazw lokacji (są one śledzone osobno).
   - NIE wyodrębniaj powszechnych słów ani pojęć z prawdziwego świata.
   - Użyj odpowiednich kategorii: Faction, Magic System, Technology, Creature, Organization, Lore, Language.
Krok 3. W polu "expanded" wpisz pełne rozwinięcie skrótu/frazy. Jeśli to nie jest skrót/fraza, powtórz nazwę.
Krok 4. NIE uwzględniaj powszechnych słów codziennego użytku.

ŚCISŁE REGUŁY DOTYCZĄCE SPOILERÓW:
- ABSOLUTNIE BRAK informacji z części książki następującej po bieżącym postępie czytania. Zatrzymaj się dokładnie na punkcie %d%%.
- Opisy muszą odzwierciedlać stan postaci dokładnie w tym punkcie książki.

ŚCISŁE REGUŁY DOTYCZĄCE ŹRÓDŁA WIEDZY (BARDZO WAŻNE):
- Dla POSTACI FIKCYJNYCH: Twoje opisy MUSZĄ opierać się WYŁĄCZNIE na tym, co zostało wyraźnie stwierdzone lub jednoznacznie zasugerowane w dostarczonym tekście. NIE uzupełniaj ich wiedzą z wcześniejszego treningu, zewnętrznych źródeł ani ogólnej znajomości książki/serii/autora.
- Jeśli postać została do tej pory wspomniana w tekście jedynie pobieżnie, Twój opis musi odzwierciedlać wyłącznie te ograniczone informacje. NIE wnioskuj, nie zakładaj ani nie dodawaj żadnych szczegółów niepopartych dostarczonym kontekstem.
- JEDYNYM wyjątkiem są RZECZYWISTE POSTACI HISTORYCZNE (umieszczane w `historical_figures`): możesz użyć wiedzy wewnętrznej do opisania ich ogólnej biografii/roli, ale nadal musisz polegać na tekście książki w kwestii ich `context_in_book`.

ŚCISŁE ZASADY BEZPIECZEŃSTWA JSON:
- MUSISZ prawidłowo stosować znaki ucieczki dla wszystkich cudzysłowów (\") wewnątrz łańcuchów znaków.
- NIE używaj znaków nowej linii bez ucieczki wewnątrz łańcuchów znaków.
- Generuj WYŁĄCZNIE poprawny, dający się przetworzyć kod JSON.

WYMAGANY FORMAT JSON:
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Pełne oficjalne imię i nazwisko",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krótkie określenie archetypu (3-5 słów, np. 'Antagonist', 'Protagonist', 'The Victim')",
      "gender": "Male / Female / Unknown",
      "occupation": "Zawód/Status",
      "description": "Opis oparty ŚCIŚLE na dostarczonym tekście. Nie wyciągaj wniosków ani nie dodawaj zewnętrznej wiedzy. BEZ SPOILERÓW. (Maksymalnie {MAX_CHAR_DESC} znaków)"
    }
  ],
  "historical_figures": [
    {
      "name": "Imię i nazwisko rzeczywistej postaci historycznej",
      "role": "Rola historyczna",
      "biography": "Krótka biografia (MAKSYMALNIE {MAX_HIST_BIO} znaków)",
      "importance_in_book": "Znaczenie do bieżącego postępu",
      "context_in_book": "Jak są wspomniani (MAKSYMALNIE 100 znaków)"
    }
  ],
  "locations": [
    {"name": "Nazwa miejsca", "description": "Krótki opis (MAKSYMALNIE {MAX_LOC_DESC} znaków)"}
  ],
  "terms": [
    {
      "name": "Termin lub akronim",
      "expanded": "Pełne rozwinięcie lub to samo co nazwa",
      "category": "Acronym / Technical Term / Concept / Jargon",
      "definition": "Zwięzła definicja w kontekście (MAKSYMALNIE {MAX_TERM_DEF} znaków)"
    }
  ],
  "timeline": [
    {
      "chapter": "Dokładny tytuł rozdziału z próbek",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Książka: %s
Autor: %s
Postęp czytania: %d%%

ZADANIE: Wyodrębnij z tekstu DOKŁADNIE 10 DODATKOWYCH ważnych postaci.
Zwróć WYŁĄCZNIE poprawny obiekt JSON.

WYMÓG ZWIĘZŁOŚCI (BARDZO WAŻNE):
Aby uniknąć obcięcia odpowiedzi przez AI, ogranicz opisy postaci do {MAX_CHAR_DESC} znaków.

KRYTYCZNA INSTRUKCJA:
NIE uwzględniaj żadnej z poniższych postaci, ponieważ zostały one już wyodrębnione:
%s

ŚCISŁE REGUŁY DOTYCZĄCE SPOILERÓW:
- ABSOLUTNIE BRAK informacji z części książki następującej po bieżącym postępie czytania. Zatrzymaj się dokładnie na punkcie %d%%.
- Opisy muszą odzwierciedlać stan postaci dokładnie w tym punkcie książki.

WYMAGANY FORMAT JSON:
{
  "characters": [
    {
      "name": "Pełne oficjalne imię i nazwisko",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Krótkie określenie archetypu (3-5 słów, np. 'Antagonist', 'Protagonist', 'The Victim')",
      "gender": "Male / Female / Unknown",
      "occupation": "Zawód/Status",
      "description": "Opis oparty ŚCIŚLE na dostarczonym tekście. Nie wyciągaj wniosków ani nie dodawaj zewnętrznej wiedzy. BEZ SPOILERÓW. (Maksymalnie {MAX_CHAR_DESC} znaków)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Książka: %s
Autor: %s
Postęp czytania: %d%%

ZADANIE: Wyodrębnij z tekstu DOKŁADNIE 15 DODATKOWYCH znaczących terminów, akronimów, żargonu lub pojęć.
- Jeśli ta książka to literatura faktu (non-fiction): wyodrębnij terminy techniczne, pojęcia, akronimy lub żargon.
- Jeśli ta książka to fikcja (fiction): wyodrębnij elementy wykreowanego świata, takie jak frakcje, organizacje, systemy magii, technologie, stworzenia, języki lub wiedzę o uniwersum (lore).
Zwróć WYŁĄCZNIE poprawny obiekt JSON.

WYMÓG ZWIĘZŁOŚCI (BARDZO WAŻNE):
Aby uniknąć obcięcia odpowiedzi przez AI, ogranicz definicje terminów do {MAX_TERM_DEF} znaków.

KRYTYCZNA INSTRUKCJA:
NIE uwzględniaj żadnego z poniższych terminów, ponieważ zostały one już wyodrębnione:
%s

ŚCISŁE REGUŁY DOTYCZĄCE SPOILERÓW:
- ABSOLUTNIE BRAK informacji z części książki następującej po bieżącym postępie czytania. Zatrzymaj się dokładnie na punkcie %d%%.

WYMAGANY FORMAT JSON:
{
  "terms": [
    {
      "name": "Termin lub akronim",
      "expanded": "Pełne rozwinięcie lub to samo co nazwa",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Technical Term / Concept / Jargon",
      "definition": "Zwięzła definicja w kontekście (MAKSYMALNIE {MAX_TERM_DEF} znaków)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
Użytkownik zaznaczył słowo "%s".
ZADANIE: Określ, czy to słowo reprezentuje postać (Character), lokację (Location), postać historyczną (Historical Figure) czy też termin techniczny/akronim (Technical Term/Acronym) w książce.

BARDZO WAŻNE DLA POSTACI I LOKACJI: Użyj dostarczonego "BOOK TEXT CONTEXT", aby zidentyfikować obiekt. Jeśli słowo zostało podane we wskazówce "SEARCH TARGET" lub "DIRECT REFERENCE", OZNACZA TO, że znajduje się ono w książce na obecnej pozycji. Nie odrzucaj go tylko dlatego, że nie zostało znalezione dokładnie w pobranym fragmencie tekstu narracyjnego. Krótkie imiona/nazwy (nawet dwuliterowe, np. "Oz", "Al", "Jo") są poprawne i powinny zostać przeanalizowane.
BARDZO WAŻNE DLA POSTACI FIKCYJNYCH: Opisz WYŁĄCZNIE to, co ujawnia dostarczony tekst książki. NIE używaj wcześniejszej wiedzy z treningu na temat tej postaci, nawet jeśli rozpoznajesz ją z dobrze znanej serii. Jeśli tekst wspomina o tej postaci tylko krótko, Twój opis musi odzwierciedlać wyłącznie te ograniczone informacje.
BARDZO WAŻNE DLA POSTACI HISTORYCZNYCH: MOŻESZ użyć własnej wiedzy wewnętrznej, aby zweryfikować ich tożsamość i przedstawić ich biografię/rolę, TYLKO jeśli jest to rzeczywista, znana postać historyczna. Nadal MUSISZ użyć kontekstu tekstu w celu określenia ich powiązania z książką.
BARDZO WAŻNE DLA TERMINÓW: Jeśli książka to literatura faktu, sprawdź, czy słowo jest terminem technicznym, akronimem lub kluczowym pojęciem. Podaj jego definicję w kontekście.
Jeśli słowo NIE jest postacią, lokacją, postacią historyczną ani terminem technicznym, ustaw wartość `is_valid` na false.

WYMAGANY FORMAT JSON:
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Pełne imię i nazwisko",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Krótkie określenie archetypu (3-5 słów, np. 'Antagonist', 'Protagonist', 'The Victim')",
    "gender": "Male/Female/Unknown",
    "occupation": "Occupation",
    "description": "Krótki opis (MAKSYMALNIE 250 znaków)"
  },
  "error_message": ""
}

Uwaga: Jeśli typ to "location", obiekt powinien zawierać pola "name" i "description". Jeśli typ to "historical_figure", obiekt powinien zawierać pola "name", "biography" i "role". Jeśli typ to "term", obiekt powinien zawierać pola "name", "expanded", "category" i "definition".

Jeśli `is_valid` jest false:
{
  "is_valid": false,
  "error_message": "Krótkie wyjaśnienie, dlaczego to słowo nie reprezentuje postaci ani lokacji."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
ZADANIE: Połącz poniższe dwa opisy tego samego obiektu (postaci lub lokacji) w jedno spójne i zwięzłe podsumowanie.
Usuń powtarzające się informacje i upewnij się, że końcowy opis brzmi naturalnie.

Opis główny: %s
Opis pomocniczy: %s

WYMAGANY FORMAT JSON:
{
  "merged_description": "Połączony i dopracowany opis (Maksymalnie {MAX_CHAR_DESC} znaków)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Tytuł książki: %s
Autor: %s
Seria: %s
Opis pliku / Metadane tematu: %s

ZADANIE: Sklasyfikuj tę książkę do dokładnie JEDNEGO z poniższych typów książek na podstawie jej metadanych i sygnałów gatunkowych:
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Zwróć WYŁĄCZNIE poprawny kod JSON:
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Tytuł książki: %s
Autor: %s

ZADANIE: Określ, czy ta książka jest częścią nazwanej serii.
Zwróć WYŁĄCZNIE poprawny kod JSON:
{
  "is_series": true,
  "series_name": "The Wheel of Time",
  "book_index": 3,
  "total_books_known": 14
}
Jeśli to NIE jest książka z serii, zwróć:
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Seria: %s
Bieżący indeks książki: %d
Tytuł bieżącej książki: %s

ZADANIE: Wypisz tytuły (oraz autorów, jeśli różnią się od "%s") książek od 1 do %d,
które ukazały się PRZED bieżącą książką w tej serii.
Zwróć WYŁĄCZNIE poprawny kod JSON:
{
  "prior_books": [
    { "index": 1, "title": "The Eye of the World", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
KSIĄŻKA DOCELOWA: %s
AUTOR: %s
INDEKS KSIĄŻKI DOCELOWEJ: %d
SERIA: %s

ZADANIE:
Przedstaw PEŁNE podsumowanie wyłącznie KSIĄŻKI DOCELOWEJ dla czytelnika, który ukończył
KSIĄŻKĘ DOCELOWĄ i ma zamiar rozpocząć kolejną książkę z serii.

ABSOLUTNA GRANICA SPOILERÓW:
Granica wiedzy to ściśle OSTATNIA STRONA KSIĄŻKI DOCELOWEJ (indeks książki %d).
Możesz uwzględniać fakty ustalone w KSIĄŻCE DOCELOWEJ lub we wcześniejszych książkach z tej serii.
NIE WOLNO Ci uwzględniać, sugerować, insynuować, zapowiadać ani dobierać szczegółów w oparciu o wiedzę z jakiejkolwiek późniejszej książki.

ZAKAZANE INFORMACJE Z PÓŹNIEJSZYCH KSIĄŻEK:
- Późniejsze wydarzenia, przyszłe losy, śmierci, przetrwania, miejsca docelowe, romanse, sojusze, konflikty lub zdrady.
- Tożsamości z późniejszych książek, prawdziwe pochodzenie, sekretne pokrewieństwo, aliasy, alter ego, reinkarnacje, transformacje, tytuły lub awanse mocy (np. NIE wspominaj, jeśli jakaś esencja łączy się z inną lub odradza się w przyszłej książce).
- Ujawnienia, potwierdzenia, reinterpretacje, zwroty akcji lub terminologia wykreowanego świata wprowadzone w późniejszych książkach.
- Retrospektywne zapowiedzi (foreshadowing) lub zwroty takie jak „później”, „ostatecznie”, „stanie się”, „w kolejnych książkach” lub ich odpowiedniki.
- Wspominanie postaci, pojęć, organizacji lub chronologii z późniejszych książek.

GRANICA DLA POSTACI:
Opisz każdą postać ściśle tak, jak jest znana na ostatniej stronie KSIĄŻKI DOCELOWEJ.
NIE używaj aliasów, ról, relacji, prawdziwych tożsamości ani statusów ujawnionych w późniejszych książkach.

ZASADA NIEPEWNOŚCI:
Jeśli nie potrafisz z pełnym przekonaniem stwierdzić, czy dany fakt lub alias został ustalony przed końcem KSIĄŻKI DOCELOWEJ, POMIŃ GO.
Brak szczegółu jest o wiele lepszy niż spoiler z przyszłej książki.

AUDYT KOŃCOWY:
Przed zwróceniem JSON sprawdź każde pole (szczególnie opisy postaci i aliasy) i usuń wszystko, co zależy od wiedzy z książek następujących po KSIĄŻCE DOCELOWEJ.

WYMAGANY FORMAT JSON:
{
  "characters": [
    { "name": "Pełne imię i nazwisko", "aliases": [], "role": "...", "description": "Status na końcu tej książki (maksymalnie {MAX_CHAR_DESC} znaków)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Podsumowanie książki", "event": "Jedno, wysoce szczegółowe, kompleksowe streszczenie fabuły całej książki, głównych wydarzeń i rozwiązania (maksymalnie 2000 znaków). MUSISZ sformatować to streszczenie przy użyciu wielu wyraźnych akapitów oddzielonych podwójnymi znakami nowej linii (\\n\\n) dla czytelności, zamiast jednego bloku tekstu." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
KSIĄŻKA DOCELOWA: %s
AUTOR: %s
INDEKS KSIĄŻKI DOCELOWEJ: %d
SERIA: %s

ZADANIE:
Używając WYŁĄCZNIE zweryfikowanych wydarzeń z poszczególnych rozdziałów podanych poniżej dla KSIĄŻKI DOCELOWEJ, napisz spójne, kompleksowe streszczenie fabuły całej książki, kluczowych wydarzeń i rozwiązania.

ŚCISŁE OGRANICZENIE DO PODANEGO TEKSTU:
- Oprzyj swoje podsumowanie WYŁĄCZNIE na podanych wydarzeniach z rozdziałów.
- NIE wprowadzaj faktów, postaci, wydarzeń ani wyników nieopisanych w tych wydarzeniach z rozdziałów.
- NIGDY nie wspominaj ani nie zapowiadaj wydarzeń, śmierci ani wątków z późniejszych książek w serii.

WYDARZENIA Z ROZDZIAŁÓW:
%s

WYMAGANY FORMAT JSON:
{
  "timeline": [
    { "chapter": "Podsumowanie książki", "event": "Jedno, wysoce szczegółowe, kompleksowe streszczenie fabuły całej książki i rozwiązania (maksymalnie 2000 znaków). MUSISZ sformatować to streszczenie przy użyciu wielu wyraźnych akapitów oddzielonych podwójnymi znakami nowej linii (\\n\\n) dla czytelności, zamiast jednego bloku tekstu." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Książka: %s
Autor: %s
Analizowany rozdział: %s

ZADANIE: Przeanalizuj WYŁĄCZNIE ten jeden rozdział. Zidentyfikuj NOWE encje wprowadzone w tym rozdziale oraz AKTUALIZACJE DELTA (zmiany stanu) dla istniejących encji.
Wygeneruj WYŁĄCZNIE poprawny obiekt JSON.

MANIFEST ISTNIEJĄCYCH ZNANYCH ENCJI (NIE wyodrębniaj ponownie, chyba że ich rola, status lub opis uległy znaczącej ewolucji):
%s

ZASADY:
1. ŚCISŁE OGRANICZENIE SPOILERÓW: Analizuj WYŁĄCZNIE dostarczony tekst rozdziału. NIE używaj żadnej wiedzy z przyszłych rozdziałów ani źródeł zewnętrznych.
2. GŁĘBIA I TREŚĆ OPISÓW POSTACI (KRYTYCZNE):
   - Oparte na faktach i konkretne: Opisz, kim jest postać, podając konkretne fakty z fabuły — jej przeszłość, wyraźną osobowość, zawód, kluczowe relacje z innymi postaciami oraz jej szczególną rolę i osobiste stawki w narracji.
   - Istotny kontekst narracyjny: Powiąż postać bezpośrednio z główną tajemnicą, konfliktem fabularnym lub śledztwem w tej książce (np. jakie przestępstwa lub sprawy bada, kto ją zatrudnił, kim są jej kluczowi sojusznicy lub przeciwnicy, jakie ma konkretne osobiste dylematy lub napięcia).
   - NIE zbyt ogólne: NIE pisz ogólnikowych frazesów (np. unikaj pustych sformułowań takich jak „detektyw badający złożone sprawy”). Nazwij konkretne okoliczności, powiązania i stawki ustalone w tekście.
   - BEZ streszczeń błahych sprawunków: NIE twórz chronologicznych rejestrów zwykłych codziennych czynności ani rutynowych obowiązków (np. NIE streszczaj wyjść do sklepu spożywczego, rutynowych rozmów telefonicznych ani nieistotnych przemieszczeń ze sceny na scenę).
   - Opisy postaci muszą być bogatymi, wyrazistymi profilami podsumowującymi to, kim są i jakie mają znaczenie aż do tego punktu książki.
3. WYSOKI PRÓG DLA AKTUALIZACJI POSTACI:
   - NIE twórz aktualizacji w `character_state_updates` tylko dlatego, że istniejąca postać pojawiła się, odezwała lub wykonała rutynowe czynności w tym rozdziale.
   - Generuj aktualizację WYŁĄCZNIE wtedy, gdy nastąpiła istotna, trwała przemiana w jej wątku fabularnym, tożsamości, relacjach, zatrudnieniu, lojalności lub stanie (np. śmierć, odniesienie ran, aresztowanie, zdrada, zaręczyny, awans, ujawnienie jako sprawcy, odkrycie wielkiego sekretu lub motywu).
   - Jeśli aktualizacja JEST uzasadniona, zaktualizowane pole `description` musi być bogatym, kumulatywnym przeglądem postaci, który uwzględnia nowe wydarzenia przy zachowaniu jej podstawowej tożsamości i ustalonego kontekstu fabularnego — a NIE streszczeniem odosobnionej sceny.
4. ZNACZNIKI STRON WEWNĄTRZ ROZDZIAŁU ([PAGE N]) I BRAMKOWANIE ZERO-SPOILER:
   - Teksty rozdziałów zawierają znaczniki [PAGE N] wskazujące postęp stron.
   - Dla `new_characters`, `new_locations` i `new_terms`: podaj "first_page" (liczba całkowita N ze znacznika [PAGE N], na której wzmianka pojawia się po raz pierwszy), "intro_role" (dla postaci) oraz "intro_description" (1-2 zdania ściśle ograniczone do tego, co wiadomo przy pierwszym wprowadzeniu na [PAGE first_page] — z ZEROWĄ wiedzą o późniejszych zwrotach akcji, sekretach lub wynikach występujących na dalszych stronach). Podaj także "page" (znacznik [PAGE N], od którego obowiązuje pełniejszy, kumulatywny opis "description", zazwyczaj ostatnia strona rozdziału).
   - Dla `character_state_updates`, `location_state_updates` i `term_state_updates`: podaj "page" (liczba całkowita N ze znacznika [PAGE N], na której ujawnienie/przemiana się dopełnia; NIE ujawniaj faktów przed tą stroną).
5. DOWÓD (EVIDENCE): Podaj krótkie odniesienie lub wycinek cytatu z tego rozdziału wyjaśniający, dlaczego nastąpiła aktualizacja.
6. OŚ CZASU: Podaj dokładnie jedno podsumowanie głównych wydarzeń fabularnych w tym rozdziale.

WYMAGANY FORMAT JSON:
{
  "new_characters": [
    {
      "name": "Pełne imię i nazwisko",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Początkowa rola (np. Urzędnik wiejski, Nieznajomy, Klient)",
      "intro_description": "Początkowe wrażenie w 1-2 zdaniach ściśle z chwili pierwszego wprowadzenia, zero spoilerów z późniejszych stron.",
      "page": 99,
      "role": "Rola narracyjna / znaczenie (np. Protagonista, Prywatny detektyw, Partner, Antagonista, Ofiara, Klient, Podejrzany, Postać drugoplanowa, Postać epizodyczna)",
      "status": "alive",
      "description": "Bogaty, konkretny opis postaci (przeszłość, relacje, stawki narracyjne). Unikaj ogólników i rejestrów błahych sprawunków.",
      "evidence": "Krótki fragment"
    }
  ],
  "character_state_updates": [
    {
      "name": "Nazwa pasująca do znanego manifestu",
      "page": 95,
      "role": "Zaktualizowana rola narracyjna / znaczenie (np. Protagonista, Partner, Antagonista, Postać drugoplanowa itd.)",
      "status": "alive",
      "change": "Jedno krótkie zdanie nazywające, co się zmieniło od poprzedniego stanu (np. 'Awansowany na partnera po sprawie Shacklewell')",
      "description": "Zaktualizowany, bogaty, kumulatywny opis postaci odzwierciedlający jej nowy status i stawki w historii",
      "evidence": "Krótki fragment"
    }
  ],
  "new_locations": [
    {
      "name": "Nazwa lokacji",
      "first_page": 80,
      "intro_description": "Początkowe wrażenie przy pierwszej wzmiance.",
      "page": 99,
      "description": "Opis lokacji",
      "evidence": "Krótki fragment"
    }
  ],
  "location_state_updates": [
    {
      "name": "Nazwa pasująca do znanego manifestu",
      "page": 95,
      "change": "Jedno krótkie zdanie nazywające, co się zmieniło (np. 'Zniszczone podczas bitwy o Oakhaven')",
      "description": "Zaktualizowany, rozwinięty opis",
      "evidence": "Krótki fragment"
    }
  ],
  "new_terms": [
    {
      "name": "Nazwa pojęcia",
      "first_page": 80,
      "intro_description": "Początkowa definicja przy pierwszej wzmiance.",
      "page": 99,
      "description": "Definicja lub wyjaśnienie lore",
      "evidence": "Krótki fragment"
    }
  ],
  "term_state_updates": [
    {
      "name": "Nazwa pasująca do znanego manifestu",
      "page": 95,
      "change": "Jedno krótkie zdanie nazywające, co zmieniło się w rozumieniu lub użyciu",
      "description": "Zaktualizowana definicja",
      "evidence": "Krótki fragment"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Podsumowanie wydarzeń w tym rozdziale"
  }
}

TEKST ROZDZIAŁU:
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Książka: %s
Autor: %s
Rozdziały w tej partii: %s

ZADANIE: Przeanalizuj dostarczoną sekwencyjną partię rozdziałów po kolei.
Dla KAŻDEGO rozdziału w partii zidentyfikuj:
1. NOWE encje wprowadzone w tym rozdziale (postaci, lokacje, pojęcia).
2. AKTUALIZACJE DELTA (zmiany stanu) dla istniejących znanych encji (z manifestu LUB wprowadzonych we wcześniejszym rozdziale tej partii) WTEDY I TYLKO WTEDY, gdy ich rola, status, lojalność lub sytuacja narracyjna przeszły istotną, trwałą przemianę.
3. WYDARZENIE NA OSI CZASU: Zwięzłe podsumowanie głównych wydarzeń fabularnych zachodzących w tym rozdziale.

Wygeneruj WYŁĄCZNIE poprawny obiekt JSON zgodny z wymaganym schematem.

MANIFEST ISTNIEJĄCYCH ZNANYCH ENCJI (z poprzednich partii - NIE wyodrębniaj ponownie, chyba że ich rola, status lub opis uległy znaczącej ewolucji):
%s

ZASADY:
1. ŚCISŁE OGRANICZENIE SPOILERÓW I SEKWENCYJNY POSTĘP:
   - Analizuj rozdziały w kolejności sekwencyjnej.
   - W odniesieniu do dowolnego rozdziału w tej partii NIE uwzględniaj wiedzy z późniejszych rozdziałów w tej partii ani z reszty książki.
2. GŁĘBIA I TREŚĆ OPISÓW POSTACI (KRYTYCZNE):
   - Oparte na faktach i konkretne: Opisz, kim jest postać, podając konkretne fakty z fabuły — jej przeszłość, wyraźną osobowość, zawód, kluczowe relacje z innymi postaciami oraz jej szczególną rolę i osobiste stawki w narracji.
   - Istotny kontekst narracyjny: Powiąż postać bezpośrednio z główną tajemnicą, konfliktem fabularnym lub śledztwem w tej książce (np. jakie przestępstwa lub sprawy bada, kto ją zatrudnił, kim są jej kluczowi sojusznicy lub przeciwnicy, jakie ma konkretne osobiste dylematy lub napięcia).
   - NIE zbyt ogólne: NIE pisz ogólnikowych frazesów (np. unikaj pustych sformułowań takich jak „detektyw badający złożone sprawy”). Nazwij konkretne okoliczności, powiązania i stawki ustalone w tekście.
   - BEZ streszczeń błahych sprawunków: NIE twórz chronologicznych rejestrów zwykłych codziennych czynności ani rutynowych obowiązków (np. NIE streszczaj wyjść do sklepu spożywczego, rutynowych rozmów telefonicznych ani nieistotnych przemieszczeń ze sceny na scenę).
   - Opisy postaci muszą być bogatymi, wyrazistymi profilami podsumowującymi to, kim są i jakie mają znaczenie aż do tego punktu książki.
3. WYSOKI PRÓG DLA AKTUALIZACJI POSTACI:
   - NIE twórz aktualizacji w `character_state_updates` tylko dlatego, że istniejąca postać pojawiła się, odezwała lub wykonała rutynowe czynności w rozdziale.
   - Generuj aktualizację WYŁĄCZNIE wtedy, gdy nastąpiła istotna, trwała przemiana w jej wątku fabularnym, tożsamości, relacjach, zatrudnieniu, lojalności lub stanie (np. śmierć, odniesienie ran, aresztowanie, zdrada, zaręczyny, awans, ujawnienie jako sprawcy, odkrycie wielkiego sekretu lub motywu).
   - Jeśli aktualizacja JEST uzasadniona, zaktualizowane pole `description` musi być bogatym, kumulatywnym przeglądem postaci, który uwzględnia nowe wydarzenia przy zachowaniu jej podstawowej tożsamości i ustalonego kontekstu fabularnego — a NIE streszczeniem odosobnionej sceny.
4. ZNACZNIKI STRON WEWNĄTRZ ROZDZIAŁU ([PAGE N]) I BRAMKOWANIE ZERO-SPOILER:
   - Teksty rozdziałów zawierają znaczniki [PAGE N] wskazujące postęp stron.
   - Dla `new_characters`, `new_locations` i `new_terms`: podaj "first_page" (liczba całkowita N ze znacznika [PAGE N], na której wzmianka pojawia się po raz pierwszy), "intro_role" (dla postaci) oraz "intro_description" (1-2 zdania ściśle ograniczone do tego, co wiadomo przy pierwszym wprowadzeniu na [PAGE first_page] — z ZEROWĄ wiedzą o późniejszych zwrotach akcji, sekretach lub wynikach występujących na dalszych stronach). Podaj także "page" (znacznik [PAGE N], od którego obowiązuje pełniejszy, kumulatywny opis "description", zazwyczaj ostatnia strona rozdziału).
   - Dla `character_state_updates`, `location_state_updates` i `term_state_updates`: podaj "page" (liczba całkowita N ze znacznika [PAGE N], na której ujawnienie/przemiana się dopełnia; NIE ujawniaj faktów przed tą stroną).
5. DOWÓD (EVIDENCE): Podaj krótkie odniesienie lub wycinek cytatu z tego konkretnego rozdziału wyjaśniający, dlaczego nastąpiła aktualizacja.
6. BEZPIECZEŃSTWO JSON: Wygeneruj ściśle poprawny kod JSON. Prawidłowo stosuj znaki ucieczki dla podwójnych cudzysłowów wewnątrz ciągów znaków.

WYMAGANY FORMAT JSON:
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Tytuł rozdziału",
      "timeline_event": "Podsumowanie głównych wydarzeń fabularnych w tym rozdziale.",
      "new_characters": [
        {
          "name": "Pełne imię i nazwisko",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Początkowa rola (np. Urzędnik wiejski, Nieznajomy, Klient)",
          "intro_description": "Początkowe wrażenie w 1-2 zdaniach ściśle z chwili pierwszego wprowadzenia, zero spoilerów z późniejszych stron.",
          "page": 99,
          "role": "Rola narracyjna / znaczenie (np. Protagonista, Prywatny detektyw, Partner, Antagonista, Ofiara, Klient, Podejrzany, Postać drugoplanowa, Postać epizodyczna)",
          "status": "alive",
          "description": "Bogaty, konkretny opis postaci (przeszłość, relacje, stawki narracyjne). Unikaj ogólników i rejestrów błahych sprawunków.",
          "evidence": "Krótki fragment"
        }
      ],
      "character_state_updates": [
        {
          "name": "Nazwa pasująca do znanego manifestu lub postaci wprowadzonej we wcześniejszym rozdziale tej partii",
          "page": 95,
          "role": "Zaktualizowana rola narracyjna / znaczenie (np. Protagonista, Partner, Antagonista, Postać drugoplanowa itd.)",
          "status": "alive",
          "change": "Jedno krótkie zdanie nazywające, co się zmieniło od poprzedniego stanu (np. 'Awansowany na partnera po sprawie Shacklewell')",
          "description": "Zaktualizowany, bogaty, kumulatywny opis postaci odzwierciedlający jej nowy status i stawki w historii",
          "evidence": "Krótki fragment"
        }
      ],
      "new_locations": [
        {
          "name": "Nazwa lokacji",
          "first_page": 80,
          "intro_description": "Początkowe wrażenie przy pierwszej wzmiance.",
          "page": 99,
          "description": "Opis lokacji",
          "evidence": "Krótki fragment"
        }
      ],
      "location_state_updates": [
        {
          "name": "Nazwa pasująca do znanego manifestu lub lokacji wprowadzonej we wcześniejszym rozdziale tej partii",
          "page": 95,
          "change": "Jedno krótkie zdanie nazywające, co się zmieniło (np. 'Zniszczone podczas bitwy o Oakhaven')",
          "description": "Zaktualizowany opis",
          "evidence": "Krótki fragment"
        }
      ],
      "new_terms": [
        {
          "name": "Nazwa pojęcia",
          "first_page": 80,
          "intro_description": "Początkowa definicja przy pierwszej wzmiance.",
          "page": 99,
          "description": "Definicja lub wyjaśnienie lore",
          "evidence": "Krótki fragment"
        }
      ],
      "term_state_updates": [
        {
          "name": "Nazwa pasująca do znanego manifestu lub pojęcia wprowadzonego we wcześniejszym rozdziale tej partii",
          "page": 95,
          "change": "Jedno krótkie zdanie nazywające, co zmieniło się w rozumieniu lub użyciu",
          "description": "Zaktualizowana definicja",
          "evidence": "Krótki fragment"
        }
      ]
    }
  ]
}

TEKSTY ROZDZIAŁÓW W TEJ PARTII:
%s]],

    -- Anthology Detect
    anthology_detect = [[
Przeanalizuj poniższe szczegóły książki i Spis treści:

Tytuł: %s
Autor: %s
Tematyka: %s
Opis: %s

Spis treści:
%s

Określ, czy to dzieło jest:
1. "anthology" (zbiór niezależnych opowiadań, esejów lub nowel, z których każdy ma własną zamkniętą fabułę lub obsadę, np. "The Adventures of Sherlock Holmes", "Dubliners", "Exhalation", "Men Without Women").
2. "novel" (pojedyncza spójna powieść podzielona na rozdziały, części lub akty, np. "Pride and Prejudice", "Harry Potter", "Dune", "Carrie").
3. "novel_omnibus" (wielotomowy zbiór pełnowymiarowych powieści opublikowanych razem w jednym tomie, np. "The Lord of the Rings: All Three Volumes", "The Complete Hitchhiker's Guide to the Galaxy", "Percy Jackson: Books 1-3").
4. "non_fiction" (pojedyncza rozprawa literatury faktu, książka historyczna lub akademicka podzielona na rozdziały).

Zwróć WYŁĄCZNIE obiekt JSON zawierający:
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 to 1.0,
  "reasoning": "krótkie wyjaśnienie (jedno zdanie)"
}]],

    -- System instruction
    system_instruction = "Jesteś ekspertem w dziedzinie badań literackich. Twoja odpowiedź musi być wyłącznie w poprawnym formacie JSON. Upewnij się, że dane są wysoce dokładne i dotyczą ściśle podanego kontekstu.",

    -- Fallback strings
    fallback = {
        no_biography = "Brak dostępnej biografii",
        no_description = "Brak opisu",
        not_specified = "Nie określono",
        unknown_author = "Nieznany autor",
        unknown_book = "Nieznana książka",
        unnamed_character = "Postać bez nazwy",
        unnamed_person = "Osoba bez nazwy"
    }
}
