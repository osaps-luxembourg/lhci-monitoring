#!/opt/homebrew/bin/bash
set -euo pipefail

# =============================================================
# run-all.sh — Orchestrateur LHCI : lance les 4 étapes
#              pour chaque projet actif
# Usage : ./run-all.sh
# =============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
LOG_DIR="$HOME/Library/Logs/lhci"
RUNNER_LOG="$LOG_DIR/runner.log"
LOCK_DIR="$BASE_DIR/.lock"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# =============================================================
# Chargement de la configuration
# =============================================================
ENV_FILE="$BASE_DIR/config/env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Fichier config/env introuvable — copier config/env.example et renseigner les variables"
    exit 1
fi
source "$ENV_FILE"
: "${LHCI_PROJECTS:?Erreur : LHCI_PROJECTS non défini dans config/env}"

# Conversion de la chaîne en tableau
read -ra PROJECTS <<< "$LHCI_PROJECTS"

# =============================================================
# Utilitaires
# =============================================================
mkdir -p "$LOG_DIR"

log_runner() {
    local level="$1"; shift
    printf '%s [%s] [runner] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" \
        | tee -a "$RUNNER_LOG"
}

# =============================================================
# Protection contre les exécutions concurrentes
# =============================================================
cleanup() {
    [[ -d "$LOCK_DIR" ]] && rmdir "$LOCK_DIR" 2>/dev/null || true
}

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log_runner "WARN" "Une exécution est déjà en cours — abandon"
    exit 0
fi

trap cleanup EXIT

# =============================================================
# Lancement des projets
# =============================================================
log_runner "INFO" "========================================="
log_runner "INFO" "LHCI run start (${#PROJECTS[@]} projet(s))"

FAILED_PROJECTS=()
START_TOTAL=$(date +%s)

for PROJECT in "${PROJECTS[@]}"; do
    log_runner "INFO" "-----------------------------------------"
    log_runner "INFO" "Début : $PROJECT"
    START_PROJECT=$(date +%s)
    PROJECT_OK=true

    # --- Étape 1 : Collect ---
    if ! "$SCRIPTS_DIR/01-collect.sh" "$PROJECT"; then
        log_runner "ERROR" "[$PROJECT] collect FAILED — projet abandonné"
        FAILED_PROJECTS+=("$PROJECT")
        continue
    fi

    # --- Étape 2 : Upload ---
    if ! "$SCRIPTS_DIR/02-upload.sh" "$PROJECT"; then
        log_runner "WARN" "[$PROJECT] upload FAILED — poursuite vers report/notify"
        PROJECT_OK=false
    fi

    # --- Étape 3 : Report ---
    if ! "$SCRIPTS_DIR/03-report.sh" "$PROJECT"; then
        log_runner "ERROR" "[$PROJECT] report FAILED — notify ignoré"
        FAILED_PROJECTS+=("$PROJECT")
        continue
    fi

    # --- Étape 4 : Notify ---
    if ! "$SCRIPTS_DIR/04-notify.sh" "$PROJECT"; then
        log_runner "ERROR" "[$PROJECT] notify FAILED"
        PROJECT_OK=false
    fi

    END_PROJECT=$(date +%s)
    DUR=$(( END_PROJECT - START_PROJECT ))

    if $PROJECT_OK; then
        log_runner "INFO" "[$PROJECT] OK (${DUR}s)"
    else
        log_runner "WARN" "[$PROJECT] terminé avec avertissements (${DUR}s)"
        FAILED_PROJECTS+=("$PROJECT")
    fi
done

# =============================================================
# Bilan
# =============================================================
END_TOTAL=$(date +%s)
DUR_TOTAL=$(( END_TOTAL - START_TOTAL ))

log_runner "INFO" "========================================="

if [[ ${#FAILED_PROJECTS[@]} -eq 0 ]]; then
    log_runner "INFO" "Tous les projets OK — durée totale : ${DUR_TOTAL}s"
    exit 0
else
    log_runner "ERROR" "Projets en échec : ${FAILED_PROJECTS[*]} — durée totale : ${DUR_TOTAL}s"
    exit 1
fi
