# lhci-monitoring

Système d'audit automatique de l'accessibilité web basé sur [Lighthouse CI](https://github.com/GoogleChrome/lighthouse-ci), conçu pour macOS. Il audite plusieurs sites web chaque semaine, génère des rapports CSV avec suivi de tendance, et envoie les résultats par email HTML.

## Fonctionnement

Le pipeline se déroule en 4 étapes séquentielles, projet par projet :

```
01-collect.sh  →  02-upload.sh  →  03-report.sh  →  04-notify.sh
```

| Étape | Description |
|---|---|
| **collect** | Lance `lhci collect` URL par URL (isolation des crashs), accumule les résultats JSON, écrit `failed_urls.txt` si des URLs sont en échec |
| **upload** | Upload les résultats vers un serveur LHCI local |
| **report** | Calcule les scores moyens (accessibilité + RAWeb), les tendances vs rapport précédent et vs 30 jours, génère un CSV et des lignes HTML — inclut une ligne d'erreur pour les URLs en échec |
| **notify** | Injecte les données dans le template email et envoie via `msmtp` avec le CSV en pièce jointe |

L'orchestrateur `run-all.sh` exécute le pipeline pour chaque projet listé, avec protection contre les exécutions concurrentes (verrou par répertoire).

## Déclenchement automatique

Le système utilise un **launchd agent** macOS déclenché le **lundi à 06:00** :

| Agent | Jour | Heure |
|---|---|---|
| `com.lhci.monday` | Lundi | 06:00 |

Le plist utilise `caffeinate -i -s` pour empêcher le Mac de passer en veille pendant l'exécution.

Un réveil automatique `pmset` est configuré à **05:55** (lundi) pour que le Mac soit allumé avant l'exécution.

## Structure du projet

```
lhci-monitoring/
├── config/
│   ├── env.example            # Template des variables d'environnement
│   └── projects/              # Configuration LHCI par projet (.js) — gitignorés
│       └── mon-projet.js.example
├── launchd/
│   └── com.lhci.monday.plist.example  # Template plist (chemin généré par setup.sh)
├── node_modules/
│   └── lighthouse-plugin-raweb  →  ../plugins/lighthouse-plugin-raweb  (symlink)
├── plugins/
│   └── lighthouse-plugin-raweb/   # Plugin RAWeb Luxembourg
│       ├── package.json
│       ├── plugin.mjs             # Point d'entrée du plugin
│       └── audits/
│           ├── raweb-accessibility-statement.mjs  # RAWeb 14.1
│           ├── raweb-skip-links.mjs               # RAWeb 12.6/12.7
│           ├── raweb-no-meta-refresh.mjs          # RAWeb 13.3
│           ├── raweb-contact-link.mjs             # RAWeb 12.5
│           └── raweb-multiple-navigation.mjs      # RAWeb 12.1 (informatif)
├── reports/                   # Rapports CSV — gitignorés (générés automatiquement)
├── runs/                      # Données temporaires de collect — gitignorés
├── scripts/
│   ├── 01-collect.sh
│   ├── 02-upload.sh
│   ├── 03-report.sh
│   ├── 04-notify.sh
│   ├── run-all.sh             # Orchestrateur principal
│   └── setup.sh               # Installation initiale
└── templates/
    └── email.html             # Template email HTML
```

## Prérequis

- macOS (launchd + pmset)
- [Homebrew](https://brew.sh)
- `lhci` — `npm install -g @lhci/cli`
- `node` — requis pour lire les configs JS depuis les scripts bash
- `jq` — `brew install jq`
- `msmtp` — `brew install msmtp` (configuré dans `~/.msmtprc`)
- `python3` — inclus dans macOS ou via Homebrew
- **Docker** avec le serveur LHCI (`patrickhulce/lhci-server`) :

```bash
docker run -d \
  --name lhci-server \
  --restart unless-stopped \
  -p 9001:9001 \
  -v lhci-data:/data \
  patrickhulce/lhci-server
```

Le serveur sera accessible sur `http://localhost:9001`. L'interface web permet de consulter l'historique des audits et de créer les tokens de projet.

## Installation

```bash
# Cloner le dépôt
git clone <repo-url> ~/projets/lhci-monitoring
cd ~/projets/lhci-monitoring

# Configurer les variables d'environnement
cp config/env.example config/env
# Éditer config/env avec les vraies valeurs (adresse email destinataire)

# Créer les configs projets
# cp config/projects/mon-projet.js.example config/projects/mon-projet.js
# Éditer avec les URLs et le token LHCI du projet

# Lancer l'installation (launchd + pmset + symlink plugin)
./scripts/setup.sh
```

`setup.sh` effectue :
1. Création des répertoires nécessaires (`runs/`, `reports/`, logs)
2. Création du symlink `node_modules/lighthouse-plugin-raweb`
3. Génération du plist depuis `launchd/*.plist.example` (substitution du chemin absolu)
4. Copie et chargement du plist dans `~/Library/LaunchAgents/`
5. Configuration du réveil automatique via `sudo pmset`

## Variables d'environnement

Les variables sensibles sont dans `config/env` (non commité, basé sur `config/env.example`) :

```bash
MAIL_TO="destinataire@example.com"
```

## Configuration d'un projet

Chaque projet est défini par un fichier `.js` dans `config/projects/` (non commité) :

```js
// config/projects/mon-projet.js
module.exports = {
  ci: {
    collect: {
      url: [
        "https://example.com/page1",
        "https://example.com/page2",
      ],
      numberOfRuns: 3,
      settings: {
        plugins: ["lighthouse-plugin-raweb"],
        onlyCategories: [
          "accessibility",
          "lighthouse-plugin-raweb",
        ],
        chromeFlags: "--headless=new --no-sandbox --disable-gpu --ignore-certificate-errors",
      },
    },
    upload: {
      target: "lhci",
      serverBaseUrl: "http://localhost:9001",
      token: "votre-token-projet",
    },
  },
};
```

Le token se récupère en créant un projet via l'interface web du serveur LHCI (`http://localhost:9001`).

Pour activer un nouveau projet, ajouter son nom dans le tableau `PROJECTS` de `run-all.sh`.

## Collect URL par URL

`01-collect.sh` lance `lhci collect` une fois par URL (et non une seule fois pour toutes les URLs). Cela permet d'**isoler les crashs** : si une URL provoque un crash Node.js (bot detection, page vide…), les autres URLs ne sont pas affectées.

Les URLs en échec sont listées dans `runs/<projet>/failed_urls.txt`, lu par `03-report.sh` pour générer des lignes d'erreur dans le rapport.

> **Comportement attendu :** lhci supprime et recrée son répertoire `.lighthouseci/` à chaque appel. Le script utilise un dossier de staging (`.lhci_staging/`) pour accumuler les JSON de toutes les URLs avant de les fusionner.

## Plugin RAWeb Luxembourg

Le plugin `lighthouse-plugin-raweb` ajoute des audits Lighthouse couvrant des critères du [Référentiel d'Accessibilité Web (RAWeb)](https://accessibilite.public.lu/fr/raweb1/) du Luxembourg non détectés par axe-core.

### Critères implémentés

| ID audit | Critère RAWeb | Description | Poids |
|---|---|---|---|
| `raweb-accessibility-statement` | 14.1 | Lien vers une déclaration d'accessibilité | 1 |
| `raweb-skip-links` | 12.6 / 12.7 | Lien d'évitement vers le contenu principal | 1 |
| `raweb-no-meta-refresh` | 13.3 | Absence de `<meta http-equiv="refresh">` | 1 |
| `raweb-contact-link` | 12.5 | Présence d'un moyen de contact accessible | 1 |
| `raweb-multiple-navigation` | 12.1 | Au moins deux moyens de navigation (informatif) | 0 |

### Résultats dans le serveur LHCI

- **"Open Report"** : tous les audits RAWeb apparaissent dans le rapport Lighthouse complet avec leurs détails.
- **Dashboard LHCI** : une catégorie **"RAWeb Luxembourg"** s'ajoute au score `accessibility` existant.

### Limites et vérification manuelle

Les audits sont basés sur la détection automatique de patterns HTML. Certains critères nécessitent une vérification manuelle :

- **12.1** (navigation multiple) : l'audit est marqué `informatif` (poids 0) — la détection de menus, fil d'Ariane, plan du site et moteur de recherche peut être incomplète.
- **12.5** (contact) et **14.1** (déclaration) : la détection repose sur les textes et URLs des liens — un lien avec un texte inhabituel peut passer inaperçu.

### Installation du plugin

Le plugin est exposé via un symlink dans `node_modules/` créé automatiquement par `setup.sh` :

```
node_modules/lighthouse-plugin-raweb  →  ../plugins/lighthouse-plugin-raweb
```

Lighthouse exige que les plugins soient référencés par un nom commençant par `lighthouse-plugin-`. Le symlink permet d'utiliser `"lighthouse-plugin-raweb"` dans les configs sans installer de package npm.

> Si le symlink est supprimé accidentellement, relancer `./scripts/setup.sh` pour le recréer.

### Ajouter un nouveau critère RAWeb

1. Créer un fichier `plugins/lighthouse-plugin-raweb/audits/raweb-<id>.mjs` avec une classe exportée par défaut (méthodes statiques `meta` et `audit`).
2. Ajouter l'entrée `{ path: join(__dirname, 'audits/raweb-<id>.mjs') }` dans `plugin.mjs`.
3. Ajouter la référence `{ id: 'raweb-<id>', weight: 1 }` dans `category.auditRefs` de `plugin.mjs`.

## Lancement manuel

```bash
# Lancer tous les projets
./scripts/run-all.sh

# Lancer une étape pour un projet spécifique
./scripts/01-collect.sh mon-projet
./scripts/02-upload.sh mon-projet
./scripts/03-report.sh mon-projet
./scripts/04-notify.sh mon-projet
```

## Logs

Les logs sont écrits dans `~/Library/Logs/lhci/` :

```
~/Library/Logs/lhci/
├── runner.log       # Log de l'orchestrateur run-all.sh
├── projet1.log      # Log par projet (collect + report + notify)
├── projet2.log
└── ...
```

## Rapports CSV

Chaque exécution génère un CSV dans `reports/<projet>/YYYY/MM/rapport_YYYY-MM-DD.csv` :

```
date,url,score_a11y,tendance_a11y,score_raweb,tendance_raweb,tendance_a11y_30j,tendance_raweb_30j,statut
2026-04-14,https://example.com/page1,87,+3,92,+1,+5,+8,OK
2026-04-14,https://example.com/page2,92,=,78,=,n/a,n/a,OK
2026-04-14,https://example.com/page3,ERREUR,n/a,-1,n/a,n/a,n/a,ERREUR
```

- `score_a11y` : score d'accessibilité Lighthouse (0–100)
- `score_raweb` : score RAWeb Luxembourg (0–100, ou `-1` si non disponible)
- `tendance_a11y` / `tendance_raweb` : évolution vs le rapport précédent disponible (`+N`, `-N`, `=`, `n/a`)
- `tendance_a11y_30j` / `tendance_raweb_30j` : évolution vs le rapport le plus récent vieux d'au moins 30 jours (`n/a` si l'historique est insuffisant)
- `statut` : `OK` ou `ERREUR` (URL en échec de collecte)

La tendance 30j se remplit automatiquement après 30 jours d'historique.

## Email

Le rapport est envoyé à l'adresse définie dans `config/env` (`MAIL_TO`). L'email contient :
- Un tableau HTML avec 7 colonnes : URL, Score A11y, Tendance Dernier, Tendance 30j, Score RAWeb, Tendance Dernier, Tendance 30j
- Scores colorés selon le niveau (vert / orange / rouge)
- Les URLs en échec de collecte signalées en rouge avec `⚠ Échec de collecte`
- Une légende des niveaux de score
- Une légende des critères RAWeb testés automatiquement
- Le fichier CSV en pièce jointe

Le body HTML est encodé en base64 (`Content-Transfer-Encoding: base64`) pour éviter la corruption des balises par les relais SMTP (compatibilité Outlook).

`msmtp` doit être configuré dans `~/.msmtprc` avec les paramètres SMTP appropriés.

## Fichiers ignorés

```
config/env           # Variables sensibles (email destinataire)
config/projects/*.js # Configs projets (URLs, tokens LHCI)
launchd/*.plist      # Plists avec chemins absolus (générés par setup.sh)
reports/             # Rapports CSV générés
runs/                # Données temporaires de collect
.lock/               # Verrou d'exécution concurrente
.claude/             # Paramètres locaux Claude Code
.DS_Store
```
