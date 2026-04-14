#!/opt/homebrew/bin/bash
set -euo pipefail

# =============================================================
# 02-upload.sh — Upload les résultats lhci vers le serveur
# Usage : ./02-upload.sh <nom_projet>
# =============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_DIR="$BASE_DIR/config/projects"
RUNS_DIR="$BASE_DIR/runs"
LOG_DIR="$HOME/Library/Logs/lhci"

LHCI_BIN="/opt/homebrew/bin/lhci"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Validation argument ---
PROJECT_NAME="${1:?Erreur : nom de projet requis. Usage : $0 <nom_projet>}"
CONFIG_FILE="$CONFIG_DIR/${PROJECT_NAME}.js"
WORK_DIR="$RUNS_DIR/$PROJECT_NAME"
PROJECT_LOG="$LOG_DIR/${PROJECT_NAME}.log"

mkdir -p "$LOG_DIR"

log() {
    local level="$1"; shift
    printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$PROJECT_NAME" "$*" \
        | tee -a "$PROJECT_LOG"
}

# --- Validation config ---
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "ERROR" "Config introuvable : $CONFIG_FILE"
    exit 1
fi

# --- Validation résultats collect ---
if [[ ! -d "$WORK_DIR/.lighthouseci" ]] || \
   [[ -z "$(ls "$WORK_DIR/.lighthouseci"/lhr-*.json 2>/dev/null)" ]]; then
    log "ERROR" "Aucun résultat collect trouvé dans $WORK_DIR/.lighthouseci — collect lancé ?"
    exit 1
fi

log "INFO" "Upload start"

cd "$WORK_DIR"

# --- Upload ---
if "$LHCI_BIN" upload --config="$CONFIG_FILE" >> "$PROJECT_LOG" 2>&1; then
    log "INFO" "Upload OK"
    exit 0
else
    log "ERROR" "Upload FAILED"
    exit 1
fi
