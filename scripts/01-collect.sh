#!/opt/homebrew/bin/bash
set -euo pipefail

# =============================================================
# 01-collect.sh — Lance lhci collect URL par URL pour un projet
# Usage : ./01-collect.sh <nom_projet>
# =============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$BASE_DIR/config/projects"
RUNS_DIR="$BASE_DIR/runs"
LOG_DIR="$HOME/Library/Logs/lhci"

LHCI_BIN="/opt/homebrew/bin/lhci"
GIT_BIN="/usr/bin/git"
NODE_BIN="$(command -v node || true)"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Validation argument ---
PROJECT_NAME="${1:?Erreur : nom de projet requis. Usage : $0 <nom_projet>}"
CONFIG_FILE="$CONFIG_DIR/${PROJECT_NAME}.js"
WORK_DIR="$RUNS_DIR/$PROJECT_NAME"
PROJECT_LOG="$LOG_DIR/${PROJECT_NAME}.log"

mkdir -p "$WORK_DIR" "$LOG_DIR"

log() {
    local level="$1"; shift
    printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$PROJECT_NAME" "$*" \
        | tee -a "$PROJECT_LOG"
}

# --- Validations ---
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR" "Config introuvable : $CONFIG_FILE"
    exit 1
fi

if [[ -z "$NODE_BIN" ]]; then
    log "ERROR" "node est introuvable"
    exit 1
fi

log "INFO" "Collect start"

cd "$WORK_DIR"

# --- Git init (requis par LHCI pour générer un hash de build) ---
if [[ ! -d ".git" ]]; then
    "$GIT_BIN" init >> "$PROJECT_LOG" 2>&1
    "$GIT_BIN" -c user.email="lhci@local" -c user.name="LHCI" \
        commit --allow-empty -m "init" >> "$PROJECT_LOG" 2>&1
fi

"$GIT_BIN" -c user.email="lhci@local" -c user.name="LHCI" \
    commit --allow-empty -m "LHCI run $(date '+%Y-%m-%d %H:%M:%S')" >> "$PROJECT_LOG" 2>&1

# --- Nettoyage résultats précédents ---
rm -rf "$WORK_DIR/.lighthouseci"

# --- Lecture des URLs depuis la config ---
mapfile -t URLS < <("$NODE_BIN" -e \
    "const c = require('$CONFIG_FILE'); c.ci.collect.url.forEach(u => console.log(u))")

if [[ ${#URLS[@]} -eq 0 ]]; then
    log "ERROR" "Aucune URL trouvée dans $CONFIG_FILE"
    exit 1
fi

TOTAL=${#URLS[@]}
log "INFO" "${TOTAL} URL(s) à collecter"

# --- Collect URL par URL ---
# lhci collect supprime et recrée .lighthouseci/ à chaque appel.
# Stratégie : laisser lhci écrire dans .lighthouseci/ (CWD), puis déplacer
# immédiatement les JSON vers un dossier de staging avant le prochain appel.
FAILED_URLS=()
SUCCESS_URLS=()
STAGING_DIR="$WORK_DIR/.lhci_staging"
mkdir -p "$STAGING_DIR"

for i in "${!URLS[@]}"; do
    url="${URLS[$i]}"
    idx=$(( i + 1 ))

    log "INFO" "[$idx/$TOTAL] → $url"

    set +e
    "$LHCI_BIN" collect --config="$CONFIG_FILE" --url="$url" >> "$PROJECT_LOG" 2>&1
    exit_code=$?
    set -e

    # Vérification des JSON produits (exit 0 ne garantit pas de résultat)
    shopt -s nullglob
    produced_jsons=("$WORK_DIR/.lighthouseci"/lhr-*.json)
    shopt -u nullglob

    if [[ ${#produced_jsons[@]} -gt 0 ]]; then
        mv "${produced_jsons[@]}" "$STAGING_DIR/"
        SUCCESS_URLS+=("$url")
        log "INFO" "[$idx/$TOTAL] OK (${#produced_jsons[@]} résultat(s))"
    else
        FAILED_URLS+=("$url")
        log "WARN" "[$idx/$TOTAL] FAIL (code $exit_code, aucun JSON) — $url"
    fi
done

# --- Fusion : tous les JSON de staging → .lighthouseci/ ---
shopt -s nullglob
staged_jsons=("$STAGING_DIR"/lhr-*.json)
shopt -u nullglob
if [[ ${#staged_jsons[@]} -gt 0 ]]; then
    mkdir -p "$WORK_DIR/.lighthouseci"
    mv "${staged_jsons[@]}" "$WORK_DIR/.lighthouseci/"
fi
rm -rf "$STAGING_DIR"

# --- Sauvegarde des URLs en échec pour 03-report.sh ---
if [[ ${#FAILED_URLS[@]} -gt 0 ]]; then
    printf '%s\n' "${FAILED_URLS[@]}" > "$WORK_DIR/failed_urls.txt"
else
    rm -f "$WORK_DIR/failed_urls.txt"
fi

# --- Résumé ---
log "INFO" "Collect terminé : ${#SUCCESS_URLS[@]}/$TOTAL OK"

if [[ ${#FAILED_URLS[@]} -gt 0 ]]; then
    log "WARN" "${#FAILED_URLS[@]} URL(s) en échec :"
    for u in "${FAILED_URLS[@]}"; do
        log "WARN" "  ✗ $u"
    done
fi

# --- Vérification : au moins un résultat JSON produit ---
shopt -s nullglob
JSON_FILES=("$WORK_DIR/.lighthouseci"/lhr-*.json)
shopt -u nullglob

if [[ ${#JSON_FILES[@]} -eq 0 ]]; then
    log "ERROR" "Collect FAILED — aucun résultat JSON produit"
    exit 1
fi

log "INFO" "Collect OK (${#JSON_FILES[@]} résultat(s))"
exit 0
