# Ombre (ex-fork d'Ora Browser) — consignes pour Claude

Navigateur macOS façon Arc, sur WebKit. Dépôt : `barto95100/ora-browser` (sera renommé `ombre-browser`),
local `~/Developer/ora-browser`. Dérivé d'Ora Browser (`the-ora/browser`, GPL-3.0, plus maintenu).
Historique détaillé : document de suivi du projet claude.ai « ORA BRowser » (`claude/suivi-fork-ora.md`).

## Règles de Ludo (à respecter toujours)

- **Répondre en français**, même si le code, les commits et les PR sont en anglais.
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
- **CI verte avant toute fusion** (« Create a merge commit »). CI « Queued » longtemps = panne GitHub
  (runners macOS) : attendre / « Re-run all jobs », ne jamais contourner la règle de `main`.
- Après fusion : `git switch main && git pull --ff-only && git fetch --prune && xcodegen`.

## Mode autonome (quand Ludo le demande : enchaîner une liste de PR sans l'attendre)

Ludo n'intervient que pour les décisions produit, les tests manuels par lots et les blocages. Pour chaque PR :

1. `git checkout main && git pull && git checkout -b <branche> && xcodegen` ; plan écrit dans
   `docs/audit/journal/<n°>-<branche>.md` (local, hors git), sans attendre de validation.
2. Code + tests Swift Testing ; un bug à prouver : faire d'abord échouer le test sur le code actuel.
3. `xcodegen`, compilation, suite complète avec `xcodebuild` (stable) ; SwiftFormat / SwiftLint propres.
4. Relecture indépendante : un sous-agent neuf, en lecture seule, qui reçoit seulement le diff, les
   identifiants de l'audit et `CLAUDE.md` (pas le raisonnement). Il vérifie : périmètre, pas de
   changement de comportement non voulu, tests pertinents, règles du projet, aucune mention d'IA.
   Corriger ce qu'il trouve ; relancer la relecture si le changement est important.
5. Commit (Conventional Commits, en anglais, sans mention d'IA), push,
   `gh pr create --repo barto95100/ora-browser --base main`, description `## Summary` / `## Testing`.
6. `gh pr checks --watch`. CI en échec : corriger et repousser. CI en file d'attente chez GitHub :
   attendre. Jamais `--admin`, jamais de contournement de la règle de `main`, jamais de force push.
7. `gh pr merge --merge --delete-branch`, puis `git checkout main && git pull && xcodegen`.
8. Ajouter les étapes de test manuelles numérotées de la PR, avec son lien, dans
   `docs/audit/TESTS-MANUELS.md` (local). Les logs `[DEBUG-…]` de mesure restent hors des commits.

S'arrêter et demander seulement pour : une décision produit (section 5 de la synthèse ou nouvelle), un
changement nécessaire hors périmètre, un échec inexpliqué après 2 essais, une action irréversible
(suppression de données, réécriture d'historique). Sinon, prendre la décision la plus raisonnable et la
noter dans la PR. Pas d'équipe d'agents pour coder : un seul agent qui enchaîne, plus un sous-agent
relecteur par PR. À la fin du lot (ou en cas d'arrêt) : résumé avec les PR fusionnées et leurs liens, les
décisions prises, les points ouverts et la liste des tests manuels à faire.

## Projet et outils

- Projet généré par **XcodeGen** (`project.yml`) : lancer `xcodegen` après tout ajout/suppression de
  fichier et après chaque changement de branche. Les réglages se changent dans `project.yml`, jamais dans
  Xcode (« Update to recommended settings » → ignorer).
- Swift 5.9 (concurrence permissive), macOS 15.0 minimum, SwiftUI + AppKit, SwiftData, Swift Testing.
- **lefthook** : pre-commit SwiftFormat + SwiftLint (erreurs bloquantes : `type_body_length` > 500,
  `file_length` > 800, `identifier_name` < 3 caractères, `large_tuple` > 2 ; avertissement ligne > 120).
  Le pre-push compile l'app (pas les tests) dans `build/DerivedData`.
- **Avant chaque push : lancer les tests** :
  `xcodebuild test -scheme ora -destination 'platform=macOS,arch=arm64' 2>&1 | xcbeautify`
  (`ls` de Ludo est un alias : utiliser `/bin/ls` dans les scripts).
- Signature Debug : Personal Team `Q76T6LDBBZ`. Bundle ID actuel `com.barto95100.ora` (Debug `.dev`).
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
  Bitwarden Safari envoie `sleep` en boucle (répondre après 10 s).
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
   - retirer « Ora » de tout ce qui est visible et du code (types `Ora…`, dossier `ora/`, projet, schéma,
     tests, CI, Sparkle, logger `com.orabrowser…`) ;
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
