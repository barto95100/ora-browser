# Ombre — consignes pour Claude

Navigateur macOS façon Arc, sur WebKit. Dépôt : `barto95100/ora-browser` (sera renommé `ombre-browser`),
local `~/Developer/ora-browser`. Dérivé d'Ora Browser (`the-ora/browser`, GPL-3.0, plus maintenu).
Historique détaillé : document de suivi du projet claude.ai « ORA BRowser » (`claude/suivi-fork-ora.md`).

## Règles de Ludo (à respecter toujours)

- **Répondre en français**, même si le code, les commits et les PR sont en anglais.
- **Résumés et questions pour Ludo toujours en français** : fin de lot, compte rendu d'étape, question de
  décision, étapes de test (y compris après une reprise de contexte ou un long travail en anglais).
- **Une étape à la fois** : proposer, attendre son retour. Il trouve vite qu'on va « trop vite ».
  (Sauf en **mode autonome**, voir plus bas.)
- Après chaque changement : **étapes de test précises et numérotées**, courtes (pas de longues explications).
- **Jamais d'attribution IA dans git** : pas de `Co-Authored-By`, aucune mention de Claude/IA dans les
  commits ni les PR. Le hook `commit-msg` de lefthook refuse ces lignes ; l'attribution automatique est
  désactivée dans `.claude/settings.json`. (Seule exception : les PR vers le projet d'origine, ligne « Code
  written with Claude (AI) under my direction; I reviewed and tested every change on macOS. » — sans objet
  désormais.)
- **git** : Claude peut créer des branches, commiter, pousser, ouvrir et fusionner des PR sur
  `barto95100/ora-browser` (en mode autonome, ou quand Ludo le demande). Jamais de travail direct sur
  `main`, jamais de force push, jamais de réécriture d'historique publié.
- Pour chaque PR : titre + description (`## Summary` / `## Testing`). PR **dans le fork**
  (`gh pr create --repo barto95100/ora-browser --base main`), jamais vers `the-ora/browser`.
- **CI verte avant toute fusion** (« Create a merge commit »), ne jamais contourner la règle de `main`.
  La CI tourne sur le Mac de Ludo (runner auto-hébergé) : « Queued » = runner occupé ou arrêté, Mac
  éteint ou en veille (runner dans `~/actions-runner`, service `./svc.sh start|stop` ; après un
  `./svc.sh install`, retirer `SessionCreate` du plist du service, sinon la signature n'accède pas au
  trousseau : `plutil -remove SessionCreate ~/Library/LaunchAgents/actions.runner.*.plist`).
  Les PR venant d'autres comptes passent par GitHub ; le réglage « Require approval
  for all external contributors » (Settings › Actions › General) doit rester actif. Avant chaque version
  distribuée : la lancer aussi sur GitHub (Actions › Build and Test › Run workflow, runner `github`).
- Après fusion : `git switch main && git pull --ff-only && git fetch --prune && xcodegen`, puis
  `scripts/clean-worktrees.sh` (retire les worktrees des branches fusionnées et désenregistre leurs copies).

## Mode autonome (quand Ludo le demande : enchaîner une liste de PR sans l'attendre)

Ludo n'intervient que pour les décisions produit, les tests manuels par lots et les blocages. Pour chaque PR :

1. `git switch main && git pull --ff-only && git switch -c <branche> && xcodegen` ; plan écrit dans
   `docs/audit/journal/<n°>-<branche>.md` (local, hors git), sans attendre de validation.
2. Code + tests Swift Testing ; un bug à prouver : faire d'abord échouer le test sur le code actuel.
3. `xcodegen`, compilation, suite complète avec `scripts/test.sh` (stable) ; SwiftFormat / SwiftLint propres.
4. Relecture indépendante : un sous-agent neuf, en lecture seule, qui reçoit seulement le diff, les
   identifiants de l'audit et `CLAUDE.md` (pas le raisonnement). Il vérifie : périmètre, pas de
   changement de comportement non voulu, tests pertinents, règles du projet, aucune mention d'IA.
   Corriger ce qu'il trouve ; relancer la relecture si le changement est important.
5. Commit (Conventional Commits, en anglais, sans mention d'IA), push,
   `gh pr create --repo barto95100/ora-browser --base main`, description `## Summary` / `## Testing`.
6. `gh pr checks <n°> --repo barto95100/ora-browser --watch`. CI en échec : corriger et repousser.
   CI en file d'attente : runner du Mac de Ludo occupé, arrêté ou Mac en veille ; le lui signaler.
   Jamais `--admin`, jamais de contournement de la règle de `main`, jamais de force push.
7. `gh pr merge <n°> --repo barto95100/ora-browser --merge --delete-branch`, puis
   `git switch main && git pull --ff-only && git fetch --prune && xcodegen && scripts/clean-worktrees.sh`
   (depuis le dépôt principal).
   Vérifier `scripts/unregister-copies.sh --check` : une seule copie d'Ombre enregistrée (celle de Xcode, plus
   une version installée dans `/Applications` s'il y en a une).
8. Ajouter les étapes de test manuelles numérotées de la PR, avec son lien, dans
   `docs/audit/TESTS-MANUELS.md` (local). Les logs `[DEBUG-…]` de mesure restent hors des commits.

S'arrêter et demander seulement pour : une décision produit (section 5 de `docs/audit/SYNTHESE.md`,
local, ou nouvelle), un changement nécessaire hors périmètre, un échec inexpliqué après 2 essais, une action irréversible
(suppression de données, réécriture d'historique). Sinon, prendre la décision la plus raisonnable et la
noter dans la PR. Pas d'équipe d'agents pour coder : un seul agent qui enchaîne, plus un sous-agent
relecteur par PR. À la fin du lot (ou en cas d'arrêt) : résumé avec les PR fusionnées et leurs liens, les
décisions prises, les points ouverts et la liste des tests manuels à faire.

## Projet et outils

- Projet généré par **XcodeGen** (`project.yml`) : lancer `xcodegen` après tout ajout/suppression de
  fichier et après chaque changement de branche. Les réglages se changent dans `project.yml`, jamais dans
  Xcode (« Update to recommended settings » → ignorer).
- Swift 5.9 avec la vérification de concurrence **complète** (`SWIFT_STRICT_CONCURRENCY: complete`, 0 avertissement :
  en garder 0, la CI et `scripts/test.sh` échouent sur tout avertissement de l'app ou des tests,
  `OMBRE_WARNINGS_AS_ERRORS=YES` ; ce qui touche l'interface, WebKit ou AppKit est `@MainActor`), macOS 15.0 minimum,
  SwiftUI + AppKit, SwiftData, Swift Testing.
- **lefthook** : pre-commit SwiftFormat + SwiftLint (erreurs bloquantes : `type_body_length` > 500,
  `file_length` > 800, `identifier_name` < 3 caractères, `large_tuple` > 2 ; avertissement ligne > 120).
  Le pre-push compile l'app (pas les tests) dans `build/DerivedData.noindex`.
- **Tests isolés des données de Ludo** : `xcodebuild test` construit la configuration « Test »
  (identifiant `com.barto95100.ora.tests`, son propre conteneur) et l'app détecte qu'elle tourne sous les
  tests (`TestHost`) : base en mémoire, aucune fenêtre ni assistant, service à part dans le trousseau.
  Un test ne doit jamais agir sur un singleton qui verrait de vraies fenêtres ou de vraies données.
- **Copies enregistrées dans Launch Services** : toute copie d'Ombre construite hors du DerivedData de Xcode
  (worktrees, hook, `build.sh`, app de tests, CI) et son `Updater.app` (Sparkle) doivent être désenregistrées,
  sinon un clic sur une notification lance une autre copie. **Toujours construire dans un dossier `.noindex`**
  (`build/DerivedData.noindex`, `build/TestData.noindex`, `build/Release.noindex`, `build/<Nom>Data.noindex`
  pour une mesure) : Spotlight l'ignore, sinon il réenregistre l'app même désenregistrée.
  `scripts/unregister-copies.sh <dossier>…` désenregistre (filet de sécurité, appelé par le hook, `build.sh`,
  `scripts/test.sh` et la CI) ; `--check` liste les copies enregistrées et les apps du dépôt hors `.noindex`.
- **Avant chaque push : lancer les tests** : `scripts/test.sh` (`xcodebuild test` dans `build/TestData.noindex`, puis
  désenregistre l'app de test ; options de `xcodebuild` en plus, ex. `-only-testing:OmbreTests/<Suite>`)
  (`ls` de Ludo est un alias : utiliser `/bin/ls` dans les scripts).
- Signature Debug et Release : Personal Team `Q76T6LDBBZ` (Apple Development) ; `./scripts/build.sh` ne laisse que
  le DMG (`build/Release.noindex/Ombre-<version>.dmg`). Pas de Developer ID ni de notarisation (programme payant), Sparkle désactivé. Le droit
  `com.apple.developer.web-browser` (et `.public-key-credential`, clés d'accès sur les sites) exige une demande à
  Apple : pas encore demandé, donc absent (pas de clés d'accès d'ici là).
  Bundle ID actuel `com.barto95100.ora` (Debug `.dev`).
- **Distribution** : DMG seulement. Mac App Store exclu (ses conditions sont incompatibles avec la GPL-3.0).
  Un DMG signé Apple Development ne tourne que sur les Macs de Ludo ; pour le partager, il faut un certificat
  Developer ID et la notarisation (programme payant). Version : `MARKETING_VERSION` dans `project.yml`,
  `CURRENT_PROJECT_VERSION` toujours en hausse ; toute version distribuée reçoit l'étiquette git `v<version>`
  (`build.sh` le rappelle, Ludo la crée).
- Branches : `feat/…`, `fix/…`, `perf/…`, `refactor/…`, `ci/…`, `build/…`, `docs/…`. Depuis `main`, sauf
  si elle dépend d'une PR non fusionnée (alors depuis celle-ci, et fusionner dans l'ordre).
- Commits atomiques, Conventional Commits, en anglais ; chaque commit compile et passe ses tests.
- Logs de diagnostic temporaires préfixés `[DEBUG-…]`, jamais commités. Outils Debug en `#if DEBUG`.

## Principes produit

- **Expérience façon Arc**, **moteur, énergie et vie privée façon Safari**.
- Énergie : pas de minuteur ni de polling superflu (préférer KVO / notifications WebKit), pages en
  arrière-plan ralenties, mesurer avant d'optimiser (`~/Developer/bench/browser-bench.sh`).
- Vie privée « se fondre dans la foule de Safari » : ne falsifier que ce qui diffère de Safari, aucune
  incohérence, navigation privée sans rien de durable sur le disque.
- Méthodes privées WebKit : seulement des méthodes de **délégué** stables, documentées ; jamais d'appel
  direct de méthode privée hors `#if DEBUG`.
  **Unique exception tolérée** (décision de Ludo, 05/11/2026) : la préférence `allowsPictureInPictureMediaPlayback`
  (`PictureInPicturePreference`), sans laquelle aucune page n'a de PiP sur macOS (aucun réglage public) ;
  acceptable car Ombre n'est pas sur le Mac App Store. Posée seulement si WebKit la connaît encore ; un test
  échoue sinon.
  **Deuxième exception tolérée** (décision de Ludo, 05/11/2026) : le partage d'écran (`ScreenSharing`), réglage
  `screenCaptureEnabled` (seulement lu : actif par défaut) et méthode de délégué
  `_webView:requestDisplayCapturePermissionForOrigin:…` (aucune API publique sur macOS) ; un test échoue si WebKit
  perd l'un ou l'autre. Le sélecteur de macOS donne l'accès : pas de permission « Enregistrement de l'écran ».
  Géolocalisation (décision de Ludo) : méthode publique de macOS 27, et avant elle la méthode **de délégué** privée
  `_webView:requestGeolocationPermissionForOrigin:…` (test qui échoue si WebKit ne la déclare plus).
  **Troisième exception tolérée** (décision de Ludo, 08/11/2026) : le fournisseur de position (`GeolocationProvider`).
  Sur macOS, WebKit ne donne aucune position aux pages sans un fournisseur posé par l'app ; Ombre fait comme Safari,
  avec les fonctions C de WebKit (`WKGeolocationManagerSetProvider`, `WKContextGetGeolocationManager`, etc.).
  Elles sont **résolues à l'exécution (`dlsym`), jamais liées** : si l'une manque, les sites sont refusés et Ombre le
  dit une fois, sans plantage ; `GeolocationProviderTests` échoue alors (et vérifie la disposition de la structure C).

## Traduction (français / anglais, selon la langue du Mac)

- Toute l'app est traduite (zone `rest` = tout `Ombre/`) : un nouveau texte visible doit avoir son français, sinon la CI
  échoue. Textes d'Info.plist : `Ombre/Resources/InfoPlist.xcstrings`. Même mot anglais, sens différent : clé propre
  (`String(localized: "cle.contexte", defaultValue: "English")`).
- Catalogue `Ombre/Resources/Localizable.xcstrings` ; textes en `String` → `String(localized:)`, valeur enregistrée
  affichée → propriété `title` traduite. `scripts/check-localization.sh` (aussi en CI) liste ce qui manque dans les
  zones traduites (`ZONES` de `scripts/check-localization.py`) ; `scripts/add-translations.py` ajoute une table JSON.
- Textes de l'app : vouvoiement ; typographie française : espace insécable U+00A0 avant `? : ; !` et dans « », apostrophe ’,
  points de suspension `…`.
- Glossaire (termes de Safari et macOS, sauf les choix de Ludo marqués *) :

  | Anglais | Français |
  |---|---|
  | Space | Espace |
  | Tab / Pinned tab | Onglet / Onglet épinglé |
  | Favorite | Favori |
  | Bookmark | Signet |
  | Split View | Vue partagée * (macOS garde « Split View ») |
  | Peek | Aperçu * |
  | Private window / Private Browsing | Fenêtre privée / Navigation privée |
  | Settings | Réglages |
  | Trackers / Ads | Traqueurs / Publicités |
  | Fingerprint | Empreinte numérique |
  | Essentials (Zen) | Essentials (terme gardé par Zen en français) |
  | Address bar / URL | Barre d’adresse / adresse |
  | Sidebar | Barre latérale |
  | Downloads / History | Téléchargements / Historique |
  | Extension | Extension |
  | Passwords | Mots de passe |
  | Shade levels: Sunny / Ombre / Deep shade | Plein soleil / Ombre / Ombre profonde |

## Leçons apprises (éviter de les refaire)

- Les vues AppKit (ScrollView, images) ne suivent pas les transitions `.move` : utiliser l'opacité.
- Une vue qui mesure sa propre largeur alors que son contenu l'élargit déborde : `ViewThatFits`.
- Une vue utilisée dans la fenêtre des réglages ne doit pas dépendre d'un `@EnvironmentObject` de la
  fenêtre de navigation (crash) : passer par `\.modelContext` ou un singleton.
- Ne pas reconstruire une vue (`.id(changing)`) qui porte un popover ouvert : il se ferme.
- `NSTextView` d'édition : son propre `UndoManager`.
- WebKit content rules : pas de `|` dans les regex.
- Extensions (`WKWebExtension*`, macOS 15.4+, façade `WebExtensionsHub`) : les pages des extensions doivent
  s'annoncer comme Safari (user-agent), toutes les pages chargées doivent appartenir à un onglet annoncé,
  Bitwarden Safari envoie `sleep` en boucle (répondre après 10 s) et rappelle `connectNative` toutes les 10 s quelle
  que soit la réponse (port accepté puis fermé sans erreur, `NativeAppPort` : un refus est une erreur à chaque essai).
- Sur un `@Model` SwiftData, une propriété `@Transient` n'est suivie par l'interface (Observation) que si elle est
  aussi `@Published`. L'état de page d'un onglet vit dans `TabRuntime` (`@Observable`, un par onglet et par fenêtre),
  lu à travers les propriétés de transition de `Tab+Runtime.swift` ; ne jamais créer un runtime dans le `body` d'une vue.
- `TabManager` est isolé `@MainActor` (déclaré explicitement) : marquer les suites de tests `@MainActor` ou les
  fonctions pures `nonisolated`.

## État au 31/10/2026

- Fusionné : notes, tâches, temps et focus, outils de barre latérale, réglages dans la fenêtre, import Zen,
  dossiers imbriqués, extensions étapes 1 à 3 (Safari des apps, accès par site, Chrome Web Store / fichier).
- PR en attente de CI, à fusionner **dans cet ordre** : `feat/extensions-private`, puis
  `feat/extension-updates` (mise à jour auto des extensions du Chrome Web Store).

## Plan (une étape à la fois, dans cet ordre)

1. **Audit complet du code** avant les refontes : onglets/état (`TabManager` > 700 lignes, `Tab` mélange
   SwiftData et état WebKit), moteur de pages, espaces et barre latérale, sécurité (entitlements, mots de
   passe, scripts injectés), concurrence (`assumeIsolated`, passage au mode strict Swift 6), performances
   (SwiftData, démarrage, mémoire). Livrer un rapport classé par priorité (problème, risque, solution,
   effort), puis refontes ciblées, une PR à la fois, avec tests. Pas de réécriture d'un bloc.
2. **Renommage en « Ombre »** (« Ombre Browser » seulement pour le dépôt, le site, les sous-titres) :
   - l'ancien nom retiré de tout ce qui est visible et du code (types, dossiers `Ombre/` et `OmbreTests/`,
     projet `Ombre.xcodeproj`, schéma `Ombre`, CI) ; sous-système des logs et identifiants internes dérivés
     de l'identifiant de bundle (`AppIdentity`) : l'étape 4 ne changera que `project.yml` ;
   - icône prête : `~/Developer/ombre-icon/Ombre.icon` (Icon Composer, apparences claire/sombre/mono) et
     calques `1-globe.svg`, `2-voile.svg`, `3-vague.svg` ;
   - **pas de migration de données** : nouvel identifiant, Ombre démarre à neuf (Ludo est d'accord, ça
     permet de tester l'assistant de premier lancement) ;
   - **GPL-3.0** : garder `LICENSE`, ajouter « Ombre est dérivé d'Ora Browser (the-ora/browser), sous
     licence GPL-3.0 » dans le README, `THIRD_PARTY_NOTICES.md` et une fenêtre « Licences » discrète dans
     l'app (rien de visible ailleurs) ;
   - ne jamais mentionner « worldgeekwide ».
3. **Assistant de premier lancement** (avec import Zen), plus un moyen de le relancer en Debug.
4. **Nom de domaine** (en dernier) : Ludo l'achètera ; l'identifiant de l'app en découlera
   (ex. `ombrebrowser.com` → `com.ombrebrowser.ombre`, Debug `.dev`).

Autres sujets notés : imports Arc/Chrome/Firefox/Safari (quand Ludo aura des données de test), aperçu vidéo
au survol bloqué par une liste de protection sur certains sites (laissé de côté).
