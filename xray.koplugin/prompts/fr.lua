return {
    -- Author Only
    author_only = [[
Identifiez et fournissez une biographie pour l'auteur du livre "%s". 
Les métadonnées suggèrent que l'auteur est "%s". 

CRITIQUE : Vérifiez l'auteur en utilisant le CONTEXTE DU TEXTE DU LIVRE (si fourni à la fin de cette invite) pour garantir une précision à 100%% et éviter les identifications incorrectes.

FORMAT JSON REQUIS :
{
  "author": "Nom complet correct",
  "author_bio": "Biographie complète axée sur sa carrière littéraire et ses œuvres majeures.",
  "author_birth": "Date de naissance, formatée selon le format de date local",
  "author_death": "Date de décès, formatée selon le format de date local"
}]],

    -- Find Duplicates
    find_duplicates = [[
Livre : %s
Auteur : %s
Progression de la lecture : %d%%

Vous passez en revue la liste suivante de %s extraits de ce livre.
Votre tâche consiste à identifier les entrées qui semblent être la MÊME entité répertoriée sous différents noms.

LISTE :
%s

RÈGLES :
- Un doublon existe lorsque deux entrées font clairement référence à la même entité (par exemple, "La Grande Bibliothèque" et "Grande Chronique", ou "Jean" et "Jean Dupont").
- Ne signalez PAS les entrées qui sont simplement liées ou similaires mais distinctes.
- Ne signalez les entrées que si vous êtes convaincu qu'il s'agit de la même entité.
- Si aucun doublon n'existe, renvoyez un tableau vide.
- RÈGLE CONTRE LES SPOILERS : N'utilisez pas d'informations au-delà de %d%% de progression de la lecture.

FORMAT JSON REQUIS :
{
  "duplicate_pairs": [
    {
      "primary": "Nom de l'entrée à CONSERVER (le nom le plus complet ou formel)",
      "secondary": "Nom de l'entrée à SUPPRIMER",
      "reason": "Raison brève (max 100 caractères)"
    }
  ]
}]],

    -- Comprehensive Xray
    comprehensive_xray = [[
Livre : %s
Auteur : %s
Progression de lecture : %d%%

TÂCHE : Effectuer une analyse X-Ray complète. Produisez UNIQUEMENT un objet JSON valide.

RÉPARTITION CRITIQUE DE L'ATTENTION :
Vous traitez un document massif avec deux blocs de texte fournis à la fin de cette invite :
1. « ÉCHANTILLONS DE CHAPITRES » : Il s'agit du macro-contexte du livre jusqu'à l'emplacement actuel du lecteur.
2. « CONTEXTE TEXTUEL DU LIVRE » : Il s'agit du micro-contexte des 20 000 derniers caractères.

PROTOCOLE ANTI-TRONCATURE (CRITIQUE) :
Vous avez une limite de sortie maximale stricte. Si les « ÉCHANTILLONS DE CHAPITRES » contiennent PLUS DE 40 chapitres (ex. : une édition intégrale) :
1. Vous DEVEZ réduire la liste des personnages aux 10 personnages les plus importants au sens absolu.
2. Vous DEVEZ réduire les descriptions de personnages à un MAXIMUM de {MAX_CHAR_DESC} caractères.
3. Vous DEVEZ réduire les résumés d'événements de la chronologie à un MAXIMUM de {MAX_TIMELINE_EVENT} caractères.
L'échec de la compression de votre sortie pour les livres volumineux entraînera la troncature et l'échec du JSON.

ALGORITHME POUR LA CHRONOLOGIE (PRIORITÉ ABSOLUE) :
Pour éviter de sauter des chapitres ou d'halluciner des événements, vous DEVEZ exécuter exactement cette boucle :
Étape 1. Consultez UNIQUEMENT le bloc « ÉCHANTILLONS DE CHAPITRES ». Identifiez les chapitres narratifs.
Étape 2. EXCLUEZ tous les éléments non narratifs du début et de la fin de l'ouvrage (ex. : couverture, page de titre, copyright, table des matières, dédicace, remerciements, du même auteur).
Étape 3. Pour chaque chapitre narratif, en commençant par le tout premier, créez EXACTEMENT UN objet événement dans le tableau `timeline`.
Étape 4. Le champ `chapter` DOIT correspondre exactement à l'en-tête du chapitre dans l'échantillon. (Mappez-les strictement par ordre séquentiel).
Étape 5. Résumez ce chapitre spécifique dans le champ `event`. {TIMELINE_DETAIL_GUIDANCE} Écrivez entre {MIN_TIMELINE_EVENT} et {MAX_TIMELINE_EVENT} caractères. Ne rédigez PAS un résumé plus court, sauf si le chapitre n'a presque aucun contenu. Ne regroupez PAS les chapitres.
Étape 6. PAS DE SPOILERS : Arrêtez-vous exactement à la marque de %d%%. N'incluez pas d'événements au-delà de cette progression.

ALGORITHME POUR LES PERSONNAGES ET LES FIGURES HISTORIQUES :
Étape 1. Extrayez les personnages importants en utilisant les deux blocs de texte. ({NUM_CHARS} normaux, MAX 10 s'il s'agit d'une intégrale). Incluez toujours le personnage principal / protagoniste par son nom, même dans les récits à la première personne (« je »/« moi ») où son nom apparaît peu fréquemment.
Étape 2. Vous DEVEZ utiliser leurs noms complets et officiels (ex. : « Abraham Van Helsing »). N'utilisez PAS de surnoms informels comme nom principal. Ne fusionnez jamais et ne subordonnez jamais un personnage sous une référence possessive ou relationnelle (ex. : « Le père de Nick » et « Nick » sont des personnages distincts).
Étape 3. Fournissez jusqu'à 3 noms alternatifs, titres ou surnoms par lesquels ce personnage est désigné dans un tableau `aliases`. Incluez leur prénom et nom de famille courants s'ils sont utilisés. IMPORTANT : Si un nom de famille est partagé par plusieurs personnages (ex. : membres d'une famille), ne l'incluez PAS comme alias pour l'un ou l'autre des personnages.
Étape 4. Recherchez activement jusqu'à {NUM_HIST} PERSONNES RÉELLES NOTABLES de l'histoire humaine (ex. : présidents, auteurs, généraux). Ajoutez-les à `historical_figures`.
CRITIQUE pour les personnages et les figures historiques :
- N'extrayez PAS de personnages ou de figures historiques mentionnés UNIQUEMENT dans les éléments non narratifs du début ou de la fin de l'ouvrage (ex. : remerciements, biographie de l'auteur, dédicaces, page de titre, copyright).
- Les figures historiques DOIVENT être des personnes réelles vérifiées ayant une reconnaissance historique étendue.
- N'incluez PAS de personnages purement fictifs dans la liste des figures historiques, même s'ils interagissent avec des événements historiques réels. Les personnages fictifs DOIVENT aller dans le tableau `characters`.
- Pour les FIGURES HISTORIQUES UNIQUEMENT, vous pouvez utiliser vos connaissances internes pour rédiger leur `biography` générale et leur `role` historique, mais vous DEVEZ utiliser le contexte du livre pour leur `context_in_book`.
PAS DE SPOILERS : Arrêtez-vous exactement à la marque de %d%%.

ALGORITHME POUR LES LIEUX :
Étape 1. Extrayez {NUM_LOCS} lieux significatifs. PAS DE SPOILERS : Arrêtez-vous exactement à la marque de %d%%.

ALGORITHME POUR LES TERMES :
Étape 0. Déclarez "book_type" comme "fiction", "non_fiction" ou "anthology" à la racine du JSON.
Étape 1. Si non_fiction : extrayez {NUM_TERMS} termes techniques, acronymes, jargon ou concepts significatifs que les lecteurs ne connaîtraient pas sans connaissances spécialisées. Utilisez des catégories appropriées telles que Acronyme, Terme technique, Concept ou Jargon.
Étape 2. Si fiction ou anthologie : extrayez {NUM_TERMS} éléments significatifs de construction d'univers qu'un nouveau lecteur aurait besoin de se voir expliquer — tels que des factions inventées, des organisations, des systèmes de magie, des technologies, des créatures, des langues ou des légendes propres à l'univers.
   - N'incluez PAS de noms de personnages ou de noms de lieux (ceux-ci sont suivis séparément).
   - N'extrayez PAS de mots ou de concepts courants du monde réel.
   - Utilisez des catégories appropriées : Faction, Système de magie, Technologie, Créature, Organisation, Légende, Langue.
Étape 3. Incluez ce que l'acronyme/l'expression signifie dans « expanded ». S'il ne s'agit pas d'un acronyme/d'une expression, répétez le nom.
Étape 4. N'incluez PAS de mots courants de la vie quotidienne.

RÈGLES STRICTES CONCERNANT LES SPOILERS :
- ABSOLUMENT AUCUNE information postérieure à la progression de lecture actuelle. Arrêtez-vous exactement à la marque de %d%%.
- Les descriptions doivent refléter l'état des personnages à ce moment précis du livre.

RÈGLES STRICTES SUR LES SOURCES DE CONNAISSANCES (CRITIQUE) :
- Pour les PERSONNAGES DE FICTION : Vos descriptions DOIVENT être basées EXCLUSIVEMENT sur ce qui est explicitement énoncé ou clairement suggéré dans le texte fourni. Ne complétez PAS avec des connaissances issues d'un entraînement préalable, de sources externes ou d'une connaissance générale du livre/de la série/de l'auteur.
- Si un personnage n'a été que brièvement mentionné dans le texte jusqu'à présent, votre description doit refléter uniquement cette information limitée. Ne faites pas de déductions, ne supposez pas et n'ajoutez aucun détail qui ne soit pas ancré dans le contexte fourni.
- La SEULE exception concerne les FIGURES HISTORIQUES RÉELLES (placées dans `historical_figures`) : vous pouvez utiliser vos connaissances internes pour leur biographie/rôle général, mais vous devez toujours vous appuyer sur le texte du livre pour leur `context_in_book`.

RÈGLES STRICTES DE SÉCURITÉ JSON :
- Vous DEVEZ échapper correctement tous les guillemets doubles (\") à l'intérieur des chaînes de caractères.
- N'utilisez PAS de sauts de ligne non échappés à l'intérieur des chaînes de caractères.
- Produisez UNIQUEMENT un JSON valide et analysable.

FORMAT JSON REQUIS :
{
  "book_type": "fiction",
  "characters": [
    {
      "name": "Nom formel complet",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Étiquette d'archétype courte (3-5 mots, ex. : 'Antagoniste', 'Protagoniste', 'La Victime')",
      "gender": "Masculin / Féminin / Inconnu",
      "occupation": "Métier/Statut",
      "description": "Description basée STRICTEMENT sur le texte fourni. Ne pas déduire ou ajouter de connaissances externes. PAS DE SPOILERS. (Max {MAX_CHAR_DESC} car.)"
    }
  ],
  "historical_figures": [
    {
      "name": "Nom de la personne historique réelle",
      "role": "Rôle historique",
      "biography": "Courte biographie (MAX {MAX_HIST_BIO} car.)",
      "importance_in_book": "Importance jusqu'à la progression actuelle",
      "context_in_book": "Comment ils sont mentionnés (MAX 100 car.)"
    }
  ],
  "locations": [
    {"name": "Nom du lieu", "description": "Courte desc (MAX {MAX_LOC_DESC} car.)"}
  ],
  "terms": [
    {
      "name": "Terme ou acronyme",
      "expanded": "Expansion complète ou identique au nom",
      "category": "Acronyme / Terme technique / Concept / Jargon",
      "definition": "Définition concise en contexte (MAX {MAX_TERM_DEF} car.)"
    }
  ],
  "timeline": [
    {
      "chapter": "Titre exact du chapitre d'après les échantillons",
      "event": "{TIMELINE_EXAMPLE}"
    }
  ]
}]],

    -- More Characters
    more_characters = [[
Livre : %s
Auteur : %s
Progression de la lecture : %d%%

TÂCHE : Extrayez EXACTEMENT 10 personnages importants SUPPLÉMENTAIRES du texte.
Retournez UNIQUEMENT un objet JSON valide.

MANDAT DE CONCISION (CRITIQUE) :
Pour éviter la troncature de la réponse de l'IA, gardez les descriptions des personnages sous {MAX_CHAR_DESC} caractères.

INSTRUCTION CRITIQUE :
N'incluez AUCUN des personnages suivants, car ils ont déjà été extraits :
%s

RÈGLES STRICTES CONTRE LES SPOILERS :
- ABSOLUTEMENT AUCUNE information provenant d'après la progression actuelle de la lecture. Arrêtez-vous exactement à la marque de %d%%.
- Les descriptions doivent refléter l'état des personnages à ce point exact du livre.

FORMAT JSON REQUIS :
{
  "characters": [
    {
      "name": "Nom formel complet",
      "aliases": ["Alias 1", "Alias 2"],
      "role": "Rôle jusqu'à la progression actuelle",
      "gender": "Masculin / Féminin / Inconnu",
      "occupation": "Métier/Statut",
      "description": "Description basée STRICTEMENT sur le texte fourni. N'inférez pas et n'ajoutez pas de connaissances externes. PAS DE SPOILERS. (Max {MAX_CHAR_DESC} caractères)"
    }
  ]
}]],

    -- More Terms
    more_terms = [[
Livre : %s
Auteur : %s
Progression de la lecture : %d%%

TÂCHE : Extrayez EXACTEMENT 15 termes, acronymes, jargon ou concepts significatifs SUPPLÉMENTAIRES du texte.
- Si ce livre est une œuvre de non-fiction : extrayez des termes techniques, des concepts, des acronymes ou du jargon.
- Si ce livre est une œuvre de fiction : extrayez des éléments de construction de l'univers (world-building) comme des factions, des organisations, des systèmes de magie, des technologies, des créatures, des langues ou du lore de l'univers.
Retournez UNIQUEMENT un objet JSON valide.

MANDAT DE CONCISION (CRITIQUE) :
Pour éviter la troncature de la réponse de l'IA, gardez les définitions des termes sous {MAX_TERM_DEF} caractères.

INSTRUCTION CRITIQUE :
N'incluez AUCUN des termes suivants, car ils ont déjà été extraits :
%s

RÈGLES STRICTES CONTRE LES SPOILERS :
- ABSOLUTEMENT AUCUNE information provenant d'après la progression actuelle de la lecture. Arrêtez-vous exactement à la marque de %d%%.

FORMAT JSON REQUIS :
{
  "terms": [
    {
      "name": "Terme ou Acronyme",
      "expanded": "Expansion complète ou identique au nom",
      "category": "Faction / Magic System / Technology / Creature / Organization / Lore / Language / Acronym / Terme Technique / Concept / Jargon",
      "definition": "Définition concise en contexte (MAX {MAX_TERM_DEF} caractères)"
    }
  ]
}]],

    -- Single Word Lookup
    single_word_lookup = [[
L'utilisateur a surligné le mot "%s".
TÂCHE : Déterminez si ce mot est un Personnage, un Lieu, une Figure Historique ou un Terme Technique/Acronyme dans le livre.
 
CRITIQUE POUR LES PERSONNAGES ET LES LIEUX : Utilisez UNIQUEMENT le "BOOK TEXT CONTEXT" fourni. Les connaissances externes sont strictement interdites. Ne pas halluciner.
CRITIQUE POUR LES PERSONNAGES DE FICTION : Décrivez UNIQUEMENT ce que révèle le texte du livre fourni. N'utilisez PAS de connaissances préalables issues de votre entraînement sur ce personnage, même si vous le reconnaissez dans une série connue. Si le texte ne mentionne que brièvement ce personnage, votre description doit refléter ces informations limitées.
CRITIQUE POUR LES FIGURES HISTORIQUES : Vous POUVEZ utiliser vos connaissances internes pour vérifier leur identité et fournir leur biographie/rôle, UNIQUEMENT s'il s'agit d'une figure historique réelle et notable. Vous DEVEZ toujours utiliser le contexte du texte pour leur pertinence dans le livre.
CRITICAL FOR TERMS : Si le livre est une œuvre de non-fiction, vérifiez si le mot est un terme technique, un acronyme ou un concept clé. Fournissez sa définition dans son contexte.
Si le mot n'est PAS un personnage, un lieu, une figure historique ou un terme technique dans le texte, définissez `is_valid` sur false.
 
FORMAT JSON REQUIS :
{
  "is_valid": true,
  "type": "character",
  "item": {
    "name": "Nom complet",
    "aliases": ["Alias 1", "Alias 2"],
    "role": "Rôle",
    "gender": "Masculin/Féminin/Inconnu",
    "occupation": "Profession",
    "description": "Brève description (max. 250 caractères)"
  },
  "error_message": ""
}
 
Remarque : si le type est "location", l'élément doit avoir "name" and "description". Si le type est "historical_figure", l'élément doit avoir "name", "biography" et "role". Si le type est "term", l'élément doit avoir "name", "expanded", "category" et "definition".
 
If `is_valid` is false:
{
  "is_valid": false,
  "error_message": "Explication courte expliquant pourquoi ce n'est ni un personnage ni un lieu."
}]],

    -- Merge Descriptions
    merge_descriptions = [[
TÂCHE : Combinez les deux descriptions suivantes de la même entité (personnage ou lieu) en un résumé unique, cohérent et concis.
Supprimez les informations redondantes et assurez-vous que la description finale s'enchaîne naturellement.

Description principale : %s
Description secondaire : %s

FORMAT JSON REQUIS :
{
  "merged_description": "Description combinée et polie (Max {MAX_CHAR_DESC} caractères)"
}]],

    -- Book Type Detect
    book_type_detect = [[
Titre du livre : %s
Auteur : %s
Série : %s
Description du fichier/Métadonnées du sujet : %s

TÂCHE : Classer ce livre dans exactement UN de ces types de livres sur la base de ses métadonnées et des indicateurs de genre :
prose_fiction, prose_nonfiction, manga, graphic_novel, children, poetry, cookbook, textbook, travel, unknown

Retourner UNIQUEMENT un JSON valide :
{
  "book_type_label": "prose_fiction",
  "confidence": "high"
}]],

    -- Series Detect
    series_detect = [[
Titre du livre : %s
Auteur : %s

TÂCHE : Déterminez si ce livre fait partie d'une série nommée.
Retournez UNIQUEMENT un JSON valide :
{
  "is_series": true,
  "series_name": "La Roue du Temps",
  "book_index": 3,
  "total_books_known": 14
}
Si ce n'est PAS un livre de série, retournez :
{ "is_series": false }]],

    -- Prior Book List
    prior_book_list = [[
Série : %s
Index du livre actuel : %d
Titre du livre actuel : %s

TÂCHE : Listez les titres (et auteurs si différents de "%s") des livres 1 à %d
qui précèdent le livre actuel dans cette série.
Retournez UNIQUEMENT un JSON valide :
{
  "prior_books": [
    { "index": 1, "title": "L'Œil du monde", "author": "Robert Jordan" }
  ]
}]],

    -- Series Book Summary
    series_book_summary = [[
LIVRE CIBLE : %s
AUTEUR : %s
INDEX DU LIVRE CIBLE : %d
SÉRIE : %s

MISSION :
Fournissez un résumé COMPLET du LIVRE CIBLE uniquement, destiné à un lecteur ayant terminé le LIVRE CIBLE et s'apprêtant à commencer le tome suivant de la série.

LIMITE ABSOLUE DE SPOIL :
La limite des connaissances est strictement fixée à la DERNIÈRE PAGE du LIVRE CIBLE (Index du livre %d).
Vous pouvez inclure des faits établis dans le LIVRE CIBLE ou dans les tomes précédents de cette série.
Vous NE DEVEZ PAS inclure, sous-entendre, suggérer, préfigurer ou sélectionner des détails en utilisant des connaissances issues d'un livre ultérieur.

INFORMATIONS INTERDITES SUR LES LIVRES ULTÉRIEURS :
- Événements futurs, destins à venir, décès, survies, destinations, romances, alliances, conflits ou trahisons.
- Identités révélées plus tard, origines réelles, parentés secrètes, alias, alter egos, réincarnations, transformations, titres ou progressions de pouvoir (par ex., ne mentionnez PAS si une essence en rejoint une autre ou renaît dans un futur livre).
- Révélations, confirmations, réinterprétations, rebondissements ou terminologie de l'univers introduits dans les livres ultérieurs.
- Préfiguration rétrospective ou expressions telles que « plus tard », « finalement », « deviendra », « dans les tomes suivants » ou équivalent.
- Mention de personnages, concepts, organisations ou chronologie issus de livres ultérieurs.

LIMITE POUR LES PERSONNAGES :
Décrivez chaque personnage strictement tel qu'il est connu à la dernière page du LIVRE CIBLE.
N'utilisez PAS d'alias, de rôles, de relations, d'identités réelles ou de statuts révélés dans les livres ultérieurs.

RÈGLE D'INCERTITUDE :
Si vous ne pouvez pas déterminer avec certitude si un fait ou un alias a été établi avant la fin du LIVRE CIBLE, OMETTEZ-LE.
L'absence de détails est bien préférable à un spoil sur un livre futur.

AUDIT FINAL :
Avant de renvoyer le JSON, inspectez chaque champ (en particulier les descriptions de personnages et les alias) et purgez tout ce qui dépend de connaissances acquises après le LIVRE CIBLE.

FORMAT JSON REQUIS :
{
  "characters": [
    { "name": "Nom complet", "aliases": [], "role": "...", "description": "Statut à la fin de ce livre (max {MAX_CHAR_DESC} chars)" }
  ],
  "locations": [
    { "name": "...", "description": "..." }
  ],
  "terms": [
    { "name": "...", "aliases": ["Alias 1", "Alias 2"], "expanded": "...", "category": "...", "definition": "..." }
  ],
  "timeline": [
    { "chapter": "Résumé du livre", "event": "Un résumé unique, hautement détaillé et complet de l'intrigue de l'ensemble du livre, des événements principaux et de la résolution (max 2000 caractères). Vous DEVEZ formater ce résumé en utilisant plusieurs paragraphes distincts séparés par des doubles sauts de ligne (\\n\\n) pour la lisibilité au lieu d'un seul bloc de texte." }
  ]
}]],

    -- Local Timeline Summary
    local_timeline_summary = [[
LIVRE CIBLE : %s
AUTEUR : %s
INDEX DU LIVRE CIBLE : %d
SÉRIE : %s

TACHE :
En utilisant UNIQUEMENT les événements chapitre par chapitre vérifiés fournis ci-dessous pour le LIVRE CIBLE, rédigez un résumé cohérent et complet de l'intrigue, des développements clés et de la résolution de tout le livre.

CONTRAINTE STRICTE DE FONDEMENT :
- Basez votre résumé EXCLUSIVEMENT sur les événements des chapitres fournis.
- NE PAS introduire de faits, de personnages, d'événements ou de résultats non décrits dans ces événements de chapitres.
- NE JAMAIS mentionner ou laisser présager des événements, des décès ou des développements issus de livres ultérieurs de la série.

ÉVÉNEMENTS DES CHAPITRES :
%s

FORMAT JSON REQUIS :
{
  "timeline": [
    { "chapter": "Résumé du livre", "event": "Un résumé unique, très détaillé et complet de l'intrigue et de la résolution de tout le livre (max 2000 caractères). Vous DEVEZ formater ce résumé en utilisant plusieurs paragraphes distincts séparés par des doubles sauts de ligne (\n\n) pour une meilleure lisibilité, plutôt qu'un bloc de texte unique." }
  ]
}]],

    -- Chapter Delta
    chapter_delta = [[
Livre : %s
Auteur : %s
Analyse du chapitre : %s

TÂCHE : Analysez UNIQUEMENT ce chapitre. Identifiez les NOUVELLES entités introduites dans ce chapitre et les MISES À JOUR DIFFÉRENTIELLES (changements d'état) pour les entités existantes.
Retournez UNIQUEMENT un objet JSON valide.

MANIFESTE DES ENTITÉS DÉJÀ CONNUES (NE PAS réextraire sauf si leur rôle, statut ou description a évolué de manière significative) :
%s

RÈGLES :
1. CONFINEMENT STRICT CONTRE LES SPOILERS : Analysez UNIQUEMENT le texte du chapitre fourni. N'utilisez AUCUNE connaissance provenant de chapitres ultérieurs ou de sources externes.
2. PROFONDEUR ET SUBSTANCE DES DESCRIPTIONS DE PERSONNAGES (CRITIQUE) :
   - Ancré et précis : Décrivez qui est le personnage à l'aide de faits concrets de l'histoire : ses antécédents, sa personnalité distinctive, sa profession, ses relations clés avec d'autres personnages, ainsi que son rôle précis et ses enjeux personnels dans le récit.
   - Contexte narratif significatif : Reliez directement le personnage au mystère central, au conflit de l'intrigue ou à l'enquête de ce livre (par ex. quels crimes ou affaires il étudie, qui l'a engagé, ses alliés ou adversaires clés, ses dilemmes ou tensions personnelles spécifiques).
   - PAS trop général : N'écrivez PAS de formules génériques ou clichés (par ex. évitez les phrases vides comme « un détective enquêtant sur des affaires complexes »). Nommez les circonstances précises, les liens et les enjeux établis dans le texte.
   - PAS de résumés de tâches banales : N'écrivez PAS de journaux chronologiques d'activités quotidiennes banales ou de corvées routinières (par ex. NE résumez PAS les courses au supermarché, les appels téléphoniques de routine ou les déplacements accessoires scène par scène).
   - Les descriptions des personnages doivent être des profils riches et vivants résumant qui ils sont et leur importance jusqu'à ce point du livre.
3. SEUIL ÉLEVÉ POUR LES MISES À JOUR DE PERSONNAGES :
   - NE créez PAS de mise à jour dans `character_state_updates` simplement parce qu'un personnage existant est apparu, a parlé ou a effectué des actions routinières dans ce chapitre.
   - NE générez une mise à jour QUE s'il y a une transformation substantielle et durable de son arc narratif, son identité, ses relations, son emploi, son allégeance ou sa condition (par ex. tué, blessé, arrêté, trahi, fiancé, promu, révélé comme étant le coupable, secret majeur ou mobile découvert).
   - Si une mise à jour EST justifiée, la `description` mise à jour doit être un aperçu riche et cumulatif du personnage intégrant les nouveaux développements tout en conservant son identité fondamentale et le contexte narratif établi — et NON le résumé d'une scène isolée.
4. MARQUEURS DE PAGE INTRA-CHAPITRE ([PAGE N]) ET FILTRAGE ZÉRO SPOILER :
   - Les textes des chapitres contiennent des marqueurs [PAGE N] indiquant la progression des pages.
   - Pour `new_characters`, `new_locations` et `new_terms` : fournissez "first_page" (entier N du marqueur [PAGE N] où il est mentionné pour la première fois), "intro_role" (pour les personnages) et "intro_description" (1 à 2 phrases strictement limitées à ce qui est connu lors de sa première introduction à [PAGE first_page] — avec ZÉRO connaissance des rebondissements, secrets ou dénouements survenant aux pages suivantes). Fournissez également "page" (le marqueur [PAGE N] où s'applique la "description" cumulative plus complète, généralement la dernière page du chapitre).
   - Pour `character_state_updates`, `location_state_updates` et `term_state_updates` : fournissez "page" (entier N du marqueur [PAGE N] où la révélation ou transition s'achève ; NE révélez PAS de faits avant cette page).
5. PREUVE : Fournissez une brève référence ou un extrait de citation de ce chapitre expliquant pourquoi la mise à jour a eu lieu.
6. CHRONOLOGIE : Fournissez exactement un résumé d'événement des principales actions de l'intrigue dans ce chapitre.

FORMAT JSON REQUIS :
{
  "new_characters": [
    {
      "name": "Nom complet",
      "aliases": ["Alias 1", "Alias 2"],
      "first_page": 80,
      "intro_role": "Rôle initial (par ex. Greffier du village, Inconnu, Client)",
      "intro_description": "Première impression en 1 à 2 phrases strictement lors de la première introduction, zéro spoiler des pages suivantes.",
      "page": 99,
      "role": "Rôle narratif / importance (par ex. Protagoniste, Détective privé, Partenaire, Antagoniste, Victime, Client, Suspect, Personnage secondaire, Personnage mineur)",
      "status": "alive",
      "description": "Description riche et précise du personnage (antécédents, relations, enjeux narratifs). Évitez les formules génériques et les relevés de tâches banales.",
      "evidence": "Court extrait"
    }
  ],
  "character_state_updates": [
    {
      "name": "Nom correspondant au manifeste connu",
      "page": 95,
      "role": "Rôle narratif / importance mis à jour (par ex. Protagoniste, Partenaire, Antagoniste, Personnage secondaire, etc.)",
      "status": "alive",
      "change": "Une courte phrase précisant ce qui a changé depuis l'état précédent (par ex. 'Promu associé après l'affaire Shacklewell')",
      "description": "Description mise à jour, riche et cumulative du personnage reflétant son nouveau statut et ses enjeux dans l'histoire",
      "evidence": "Court extrait"
    }
  ],
  "new_locations": [
    {
      "name": "Nom du lieu",
      "first_page": 80,
      "intro_description": "Impression initiale lors de la première mention.",
      "page": 99,
      "description": "Description du lieu",
      "evidence": "Court extrait"
    }
  ],
  "location_state_updates": [
    {
      "name": "Nom correspondant au manifeste connu",
      "page": 95,
      "change": "Une courte phrase précisant ce qui a changé (par ex. 'Détruit lors de la bataille d'Oakhaven')",
      "description": "Description évolutive mise à jour",
      "evidence": "Court extrait"
    }
  ],
  "new_terms": [
    {
      "name": "Nom du terme",
      "first_page": 80,
      "intro_description": "Définition initiale lors de la première mention.",
      "page": 99,
      "description": "Définition ou explication de l'univers",
      "evidence": "Court extrait"
    }
  ],
  "term_state_updates": [
    {
      "name": "Nom correspondant au manifeste connu",
      "page": 95,
      "change": "Une courte phrase précisant ce qui a changé dans la compréhension ou l'usage",
      "description": "Définition mise à jour",
      "evidence": "Court extrait"
    }
  ],
  "timeline_event": {
    "chapter": "%s",
    "event": "Résumé des événements de ce chapitre"
  }
}

TEXTE DU CHAPITRE :
%s]],

    -- Batch Chapter Delta
    batch_chapter_delta = [[
Livre : %s
Auteur : %s
Chapitres de ce lot : %s

TÂCHE : Analysez dans l'ordre le lot séquentiel de chapitres fourni.
Pour CHAQUE chapitre du lot, identifiez :
1. Les NOUVELLES entités introduites dans ce chapitre (personnages, lieux, termes).
2. Les MISES À JOUR DIFFÉRENTIELLES (changements d'état) pour les entités déjà connues (issues du manifeste OU introduites dans un chapitre précédent de ce lot) SI ET SEULEMENT SI leur rôle, statut, allégeance ou condition narrative a connu une transformation substantielle et durable.
3. ÉVÉNEMENT DE CHRONOLOGIE : Un résumé concis des principaux événements de l'intrigue survenant dans ce chapitre.

Retournez UNIQUEMENT un objet JSON valide respectant le schéma requis.

MANIFESTE DES ENTITÉS DÉJÀ CONNUES (des lots précédents - NE PAS réextraire sauf si leur rôle, statut ou description a évolué de manière significative) :
%s

RÈGLES :
1. CONFINEMENT STRICT CONTRE LES SPOILERS ET PROGRESSION SÉQUENTIELLE :
   - Analysez les chapitres dans l'ordre séquentiel.
   - Pour tout chapitre de ce lot, N'intégrez PAS de connaissances issues de chapitres ultérieurs du lot ou du reste du livre.
2. PROFONDEUR ET SUBSTANCE DES DESCRIPTIONS DE PERSONNAGES (CRITIQUE) :
   - Ancré et précis : Décrivez qui est le personnage à l'aide de faits concrets de l'histoire : ses antécédents, sa personnalité distinctive, sa profession, ses relations clés avec d'autres personnages, ainsi que son rôle précis et ses enjeux personnels dans le récit.
   - Contexte narratif significatif : Reliez directement le personnage au mystère central, au conflit de l'intrigue ou à l'enquête de ce livre (par ex. quels crimes ou affaires il étudie, qui l'a engagé, ses alliés ou adversaires clés, ses dilemmes ou tensions personnelles spécifiques).
   - PAS trop général : N'écrivez PAS de formules génériques ou clichés (par ex. évitez les phrases vides comme « un détective enquêtant sur des affaires complexes »). Nommez les circonstances précises, les liens et les enjeux établis dans le texte.
   - PAS de résumés de tâches banales : N'écrivez PAS de journaux chronologiques d'activités quotidiennes banales ou de corvées routinières (par ex. NE résumez PAS les courses au supermarché, les appels téléphoniques de routine ou les déplacements accessoires scène par scène).
   - Les descriptions des personnages doivent être des profils riches et vivants résumant qui ils sont et leur importance jusqu'à ce point du livre.
3. SEUIL ÉLEVÉ POUR LES MISES À JOUR DE PERSONNAGES :
   - NE créez PAS de mise à jour dans `character_state_updates` simplement parce qu'un personnage existant est apparu, a parlé ou a effectué des actions routinières dans un chapitre.
   - NE générez une mise à jour QUE s'il y a une transformation substantielle et durable de son arc narratif, son identité, ses relations, son emploi, son allégeance ou sa condition (par ex. tué, blessé, arrêté, trahi, fiancé, promu, révélé comme étant le coupable, secret majeur ou mobile découvert).
   - Si une mise à jour EST justifiée, la `description` mise à jour doit être un aperçu riche et cumulatif du personnage intégrant les nouveaux développements tout en conservant son identité fondamentale et le contexte narratif établi — et NON le résumé d'une scène isolée.
4. MARQUEURS DE PAGE INTRA-CHAPITRE ([PAGE N]) ET FILTRAGE ZÉRO SPOILER :
   - Les textes des chapitres contiennent des marqueurs [PAGE N] indiquant la progression des pages.
   - Pour `new_characters`, `new_locations` et `new_terms` : fournissez "first_page" (entier N du marqueur [PAGE N] où il est mentionné pour la première fois), "intro_role" (pour les personnages) et "intro_description" (1 à 2 phrases strictement limitées à ce qui est connu lors de sa première introduction à [PAGE first_page] — avec ZÉRO connaissance des rebondissements, secrets ou dénouements survenant aux pages suivantes). Fournissez également "page" (le marqueur [PAGE N] où s'applique la "description" cumulative plus complète, généralement la dernière page du chapitre).
   - Pour `character_state_updates`, `location_state_updates` et `term_state_updates` : fournissez "page" (entier N du marqueur [PAGE N] où la révélation ou transition s'achève ; NE révélez PAS de faits avant cette page).
5. PREUVE : Fournissez une brève référence ou un extrait de citation de ce chapitre spécifique expliquant pourquoi la mise à jour a eu lieu.
6. SÉCURITÉ JSON : Retournez un JSON strictement valide. Échappez correctement les guillemets doubles à l'intérieur des chaînes.

FORMAT JSON REQUIS :
{
  "chapters": [
    {
      "chapter_index": 1,
      "chapter_title": "Titre du chapitre",
      "timeline_event": "Résumé des principaux développements de l'intrigue dans ce chapitre.",
      "new_characters": [
        {
          "name": "Nom complet",
          "aliases": ["Alias 1"],
          "first_page": 80,
          "intro_role": "Rôle initial (par ex. Greffier du village, Inconnu, Client)",
          "intro_description": "Première impression en 1 à 2 phrases strictement lors de la première introduction, zéro spoiler des pages suivantes.",
          "page": 99,
          "role": "Rôle narratif / importance (par ex. Protagoniste, Détective privé, Partenaire, Antagoniste, Victime, Client, Suspect, Personnage secondaire, Personnage mineur)",
          "status": "alive",
          "description": "Description riche et précise du personnage (antécédents, relations, enjeux narratifs). Évitez les formules génériques et les relevés de tâches banales.",
          "evidence": "Bref extrait"
        }
      ],
      "character_state_updates": [
        {
          "name": "Nom correspondant au manifeste connu ou personnage introduit dans un chapitre précédent de ce lot",
          "page": 95,
          "role": "Rôle narratif / importance mis à jour (par ex. Protagoniste, Partenaire, Antagoniste, Personnage secondaire, etc.)",
          "status": "alive",
          "change": "Une courte phrase précisant ce qui a changé depuis l'état précédent (par ex. 'Promu associé après l'affaire Shacklewell')",
          "description": "Description mise à jour, riche et cumulative du personnage reflétant son nouveau statut et ses enjeux dans l'histoire",
          "evidence": "Bref extrait"
        }
      ],
      "new_locations": [
        {
          "name": "Nom du lieu",
          "first_page": 80,
          "intro_description": "Impression initiale lors de la première mention.",
          "page": 99,
          "description": "Description du lieu",
          "evidence": "Bref extrait"
        }
      ],
      "location_state_updates": [
        {
          "name": "Nom correspondant au manifeste connu ou lieu introduit dans un chapitre précédent de ce lot",
          "page": 95,
          "change": "Une courte phrase précisant ce qui a changé (par ex. 'Détruit lors de la bataille d'Oakhaven')",
          "description": "Description mise à jour",
          "evidence": "Bref extrait"
        }
      ],
      "new_terms": [
        {
          "name": "Nom du terme",
          "first_page": 80,
          "intro_description": "Définition initiale lors de la première mention.",
          "page": 99,
          "description": "Définition ou explication de l'univers",
          "evidence": "Bref extrait"
        }
      ],
      "term_state_updates": [
        {
          "name": "Nom correspondant au manifeste connu ou terme introduit dans un chapitre précédent de ce lot",
          "page": 95,
          "change": "Une courte phrase précisant ce qui a changé dans la compréhension ou l'usage",
          "description": "Définition mise à jour",
          "evidence": "Bref extrait"
        }
      ]
    }
  ]
}

TEXTES DES CHAPITRES DE CE LOT :
%s]],

    -- Anthology Detect
    anthology_detect = [[
Analysez les détails du livre et la table des matières suivants :

Titre : %s
Auteur : %s
Sujets : %s
Description : %s

Table des matières :
%s

Déterminez si cette œuvre est :
1. "anthology" (un recueil de nouvelles, d'essais ou de romans courts indépendants, chacun ayant son propre récit ou sa propre distribution autonome, par ex. « Les Aventures de Sherlock Holmes », « Gens de Dublin », « Expiration », « Des hommes sans femmes »).
2. "novel" (un roman unique et unifié divisé en chapitres, parties ou actes, par ex. « Orgueil et Préjugés », « Harry Potter », « Dune », « Carrie »).
3. "novel_omnibus" (une collection en plusieurs tomes de romans complets publiés ensemble dans un seul volume, par ex. « Le Seigneur des anneaux : Les trois volumes », « Le Guide du voyageur galactique : L'Intégrale », « Percy Jackson : Tomes 1 à 3 »).
4. "non_fiction" (un ouvrage unique de non-fiction, d'histoire ou un livre académique divisé en chapitres).

Retournez UNIQUEMENT un objet JSON avec :
{
  "type": "anthology" | "novel" | "novel_omnibus" | "non_fiction",
  "confidence": 0.0 à 1.0,
  "reasoning": "brève explication (une phrase)"
}]],

    -- System instruction
    system_instruction = "Vous êtes un chercheur littéraire expert. Votre réponse doit être UNIQUEMENT au format JSON valide. Assurez-vous que les données sont très précises et se rapportent strictement au contexte fourni.",

    -- Fallback strings
    fallback = {
        no_biography = "Pas de biographie disponible",
        no_description = "Pas de description",
        not_specified = "Non spécifié",
        unknown_author = "Auteur inconnu",
        unknown_book = "Livre inconnu",
        unnamed_character = "Personnage sans nom",
        unnamed_person = "Personne sans nom"
    }
}
