#!/opt/homebrew/bin/bash
set -euo pipefail

# =============================================================
# 04-notify.sh — Envoie le rapport par email via msmtp
# Usage : ./04-notify.sh <nom_projet>
# =============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNS_DIR="$BASE_DIR/runs"
REPORTS_DIR="$BASE_DIR/reports"
TEMPLATE_FILE="$BASE_DIR/templates/email.html"
LOG_DIR="$HOME/Library/Logs/lhci"

MSMTP_BIN="$(command -v msmtp || true)"
PYTHON_BIN="$(command -v python3 || true)"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Variables d'environnement ---
ENV_FILE="$BASE_DIR/config/env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Fichier config/env introuvable — copier config/env.example et renseigner les variables"
    exit 1
fi
source "$ENV_FILE"
: "${MAIL_TO:?Erreur : MAIL_TO non défini dans config/env}"

# --- Validation argument ---
PROJECT_NAME="${1:?Erreur : nom de projet requis. Usage : $0 <nom_projet>}"
WORK_DIR="$RUNS_DIR/$PROJECT_NAME"
REPORT_DIR="$REPORTS_DIR/$PROJECT_NAME"
PROJECT_LOG="$LOG_DIR/${PROJECT_NAME}.log"
TODAY="$(date '+%Y-%m-%d')"

mkdir -p "$LOG_DIR"

log() {
    local level="$1"; shift
    printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$PROJECT_NAME" "$*" \
        | tee -a "$PROJECT_LOG"
}

# --- Validations ---
if [[ -z "$MSMTP_BIN" ]]; then
    log "ERROR" "msmtp est introuvable"
    exit 1
fi

if [[ -z "$PYTHON_BIN" ]]; then
    log "ERROR" "python3 est introuvable"
    exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    log "ERROR" "Template introuvable : $TEMPLATE_FILE"
    exit 1
fi

HTML_ROWS_FILE="$WORK_DIR/email_rows.html"
if [[ ! -f "$HTML_ROWS_FILE" ]]; then
    log "ERROR" "email_rows.html introuvable — 03-report.sh lancé ?"
    exit 1
fi

CSV_FILE="$(find "$REPORT_DIR" -name "rapport_*.csv" 2>/dev/null | sort -r | head -1 || true)"
if [[ -z "$CSV_FILE" || ! -f "$CSV_FILE" ]]; then
    log "ERROR" "Aucun rapport CSV trouvé dans $REPORT_DIR"
    exit 1
fi

log "INFO" "Notify start"
log "INFO" "CSV : $(basename "$CSV_FILE")"

# =============================================================
# 1. Injection des données dans le template HTML via Python
# =============================================================
HTML_BODY="$("$PYTHON_BIN" - <<PYEOF
import sys

with open("$TEMPLATE_FILE", "r", encoding="utf-8") as f:
    template = f.read()

with open("$HTML_ROWS_FILE", "r", encoding="utf-8") as f:
    rows = f.read().strip()

result = (template
    .replace("{{TODAY}}", "$TODAY")
    .replace("{{PROJECT_NAME}}", "$PROJECT_NAME")
    .replace("{{HTML_ROWS}}", rows)
)

sys.stdout.write(result)
PYEOF
)"

# =============================================================
# 2. Construction et envoi de l'email MIME multipart
# =============================================================
BOUNDARY="LHCI_BOUNDARY_$(date +%s)"
MAIL_SUBJECT="Rapport LHCI Accessibilité - ${PROJECT_NAME} - ${TODAY}"
ENCODED_SUBJECT=$("$PYTHON_BIN" -c "from email.header import Header; print(Header('${MAIL_SUBJECT}', 'utf-8').encode())")
CSV_FILENAME="rapport_${PROJECT_NAME}_${TODAY}.csv"

{
    echo "Subject: ${ENCODED_SUBJECT}"
    echo "To: ${MAIL_TO}"
    echo "Content-Type: multipart/mixed; boundary=\"${BOUNDARY}\""
    echo "MIME-Version: 1.0"
    echo ""

    # --- Partie HTML (base64 pour éviter la coupure de lignes longues par les relais SMTP) ---
    echo "--${BOUNDARY}"
    echo "Content-Type: text/html; charset=UTF-8"
    echo "Content-Transfer-Encoding: base64"
    echo ""
    printf '%s' "${HTML_BODY}" | base64
    echo ""

    # --- Pièce jointe CSV ---
    echo "--${BOUNDARY}"
    echo "Content-Type: text/csv; charset=UTF-8"
    echo "Content-Disposition: attachment; filename=\"${CSV_FILENAME}\""
    echo ""
    cat "$CSV_FILE"
    echo ""

    echo "--${BOUNDARY}--"

} | "$MSMTP_BIN" "$MAIL_TO"

log "INFO" "Email envoyé à ${MAIL_TO}"
log "INFO" "Notify OK"
exit 0
