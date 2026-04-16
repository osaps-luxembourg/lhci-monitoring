#!/opt/homebrew/bin/bash
set -euo pipefail

# =============================================================
# 03-report.sh — Génère le rapport CSV + les lignes HTML email
# Usage : ./03-report.sh <nom_projet>
# Format CSV : date,url,score_a11y,tendance_a11y,tendance_a11y_30j,score_raweb,tendance_raweb,tendance_raweb_30j,statut
# =============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNS_DIR="$BASE_DIR/runs"
REPORTS_DIR="$BASE_DIR/reports"
LOG_DIR="$HOME/Library/Logs/lhci"

JQ_BIN="$(command -v jq || true)"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# --- Validation argument ---
PROJECT_NAME="${1:?Erreur : nom de projet requis. Usage : $0 <nom_projet>}"
WORK_DIR="$RUNS_DIR/$PROJECT_NAME"
REPORT_DIR="$REPORTS_DIR/$PROJECT_NAME"
PROJECT_LOG="$LOG_DIR/${PROJECT_NAME}.log"
TODAY="$(date '+%Y-%m-%d')"
YEAR="$(date '+%Y')"
MONTH="$(date '+%m')"
MONTH_DIR="$REPORT_DIR/$YEAR/$MONTH"

mkdir -p "$MONTH_DIR" "$LOG_DIR"

log() {
    local level="$1"; shift
    printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$PROJECT_NAME" "$*" \
        | tee -a "$PROJECT_LOG"
}

# --- Validation jq ---
if [[ -z "$JQ_BIN" ]]; then
    log "ERROR" "jq est introuvable"
    exit 1
fi

# --- Validation résultats collect ---
shopt -s nullglob
JSON_FILES=("$WORK_DIR/.lighthouseci"/lhr-*.json)
shopt -u nullglob

if [[ ${#JSON_FILES[@]} -eq 0 ]]; then
    log "ERROR" "Aucun fichier lhr-*.json trouvé dans $WORK_DIR/.lighthouseci"
    exit 1
fi

log "INFO" "Report start (${#JSON_FILES[@]} fichier(s) JSON)"

# =============================================================
# Helpers
# =============================================================
score_style() {
    local s=$1
    if   [[ $s -gt 95 ]]; then printf 'color:#1a7a4a; font-weight:bold;'
    elif [[ $s -ge 90 ]]; then printf 'color:#2eaa6a; font-weight:bold;'
    elif [[ $s -ge 70 ]]; then printf 'color:#b45309; font-weight:bold;'
    elif [[ $s -ge 50 ]]; then printf 'color:#c2500a; font-weight:bold;'
    else                        printf 'color:#cc1f1f; font-weight:bold;'
    fi
}

trend_label() {
    local avg=$1 prev=$2
    [[ -z "$prev" || "$prev" == "-1" || "$prev" == "n/a" ]] && { printf 'n/a'; return; }
    local diff=$(( avg - prev ))
    if   [[ $diff -gt 0 ]]; then printf '&#8593; +%d' "$diff"
    elif [[ $diff -lt 0 ]]; then printf '&#8595; %d'  "$diff"
    else                          printf '='
    fi
}

trend_csv() {
    local avg=$1 prev=$2
    [[ -z "$prev" || "$prev" == "-1" || "$prev" == "n/a" ]] && { printf 'n/a'; return; }
    local diff=$(( avg - prev ))
    if   [[ $diff -gt 0 ]]; then printf '+%d' "$diff"
    elif [[ $diff -lt 0 ]]; then printf '%d'  "$diff"
    else                          printf '='
    fi
}

trend_style() {
    local avg=$1 prev=$2
    [[ -z "$prev" || "$prev" == "-1" || "$prev" == "n/a" ]] && { printf 'color:#666666;'; return; }
    local diff=$(( avg - prev ))
    if   [[ $diff -gt 0 ]]; then printf 'color:#2eaa6a; font-weight:bold;'
    elif [[ $diff -lt 0 ]]; then printf 'color:#cc1f1f; font-weight:bold;'
    else                          printf 'color:#666666;'
    fi
}

score_label() {
    local s=$1
    if   [[ $s -gt 95 ]]; then printf 'Excellent'
    elif [[ $s -ge 90 ]]; then printf 'Bon'
    elif [[ $s -ge 70 ]]; then printf 'Moyen'
    elif [[ $s -ge 50 ]]; then printf 'Insuffisant'
    else                        printf 'Critique'
    fi
}

trend_aria() {
    local avg=$1 prev=$2
    [[ -z "$prev" || "$prev" == "-1" || "$prev" == "n/a" ]] && { printf 'Non disponible'; return; }
    local diff=$(( avg - prev ))
    if   [[ $diff -gt 0 ]]; then printf 'En hausse de %d point(s)' "$diff"
    elif [[ $diff -lt 0 ]]; then printf 'En baisse de %d point(s)' "$(( -diff ))"
    else                          printf 'Stable'
    fi
}

# =============================================================
# 1. Calcul des moyennes de score par URL (a11y + raweb)
# =============================================================
declare -A scores_a11y_by_url
declare -A scores_raweb_by_url
declare -A count_by_url
declare -A count_raweb_by_url

for f in "${JSON_FILES[@]}"; do
    url="$("$JQ_BIN" -r '(.finalDisplayedUrl // .finalUrl // .requestedUrl)' "$f")"
    if [[ -z "${url:-}" ]]; then
        log "WARN" "URL introuvable dans $f, fichier ignoré"
        continue
    fi

    raw_a11y="$("$JQ_BIN" -r '(.categories.accessibility.score // 0) * 100' "$f")"
    score_a11y=$(printf "%.0f" "$raw_a11y")

    raw_raweb="$("$JQ_BIN" -r 'if .categories["lighthouse-plugin-raweb"] then (.categories["lighthouse-plugin-raweb"].score * 100) else -1 end' "$f")"
    score_raweb=$(printf "%.0f" "$raw_raweb")

    scores_a11y_by_url["$url"]=$(( ${scores_a11y_by_url["$url"]:-0} + score_a11y ))
    count_by_url["$url"]=$(( ${count_by_url["$url"]:-0} + 1 ))

    if [[ $score_raweb -ge 0 ]]; then
        scores_raweb_by_url["$url"]=$(( ${scores_raweb_by_url["$url"]:-0} + score_raweb ))
        count_raweb_by_url["$url"]=$(( ${count_raweb_by_url["$url"]:-0} + 1 ))
    fi
done

if [[ ${#scores_a11y_by_url[@]} -eq 0 ]]; then
    log "ERROR" "Aucun score extrait des fichiers JSON"
    exit 1
fi

# =============================================================
# 2. Lecture du rapport précédent pour la tendance
#    Rétrocompatibilité : ancien format 5 col / nouveau 7 col
# =============================================================
declare -A prev_a11y
declare -A prev_raweb

PREV_FILE="$(find "$REPORT_DIR" -name "rapport_*.csv" ! -name "rapport_${TODAY}.csv" 2>/dev/null | sort -r | head -1 || true)"

if [[ -n "$PREV_FILE" && -f "$PREV_FILE" ]]; then
    log "INFO" "Rapport précédent trouvé : $(basename "$PREV_FILE")"
    HEADER="$(head -1 "$PREV_FILE")"
    COL_COUNT=$(echo "$HEADER" | awk -F',' '{print NF}')

    while IFS=',' read -ra fields; do
        [[ "${fields[0]}" == "date" ]] && continue
        local_url="${fields[1]}"
        if [[ $COL_COUNT -ge 7 ]]; then
            # Détection format : nouveau (tendance_a11y_30j en col 4) ou ancien (score_raweb en col 4)
            if [[ "$HEADER" == *"tendance_a11y_30j,score_raweb"* ]]; then
                prev_a11y["$local_url"]="${fields[2]}"
                prev_raweb["$local_url"]="${fields[5]}"
            else
                prev_a11y["$local_url"]="${fields[2]}"
                prev_raweb["$local_url"]="${fields[4]}"
            fi
        else
            # Ancien format : date,url,score,tendance,statut
            prev_a11y["$local_url"]="${fields[2]}"
        fi
    done < "$PREV_FILE"
else
    log "INFO" "Aucun rapport précédent, tendance non disponible"
fi

# =============================================================
# 2b. Lecture du rapport ~30j pour la tendance longue
# =============================================================
declare -A prev_a11y_30j
declare -A prev_raweb_30j

DATE_30J="$(date -v-30d '+%Y-%m-%d')"
PREV_30J_FILE="$(find "$REPORT_DIR" -name "rapport_*.csv" 2>/dev/null \
    | while IFS= read -r f; do
        fname="$(basename "$f")"
        fdate="${fname#rapport_}"; fdate="${fdate%.csv}"
        [[ "$fdate" == "$TODAY" ]] && continue
        [[ "$fdate" < "$DATE_30J" || "$fdate" == "$DATE_30J" ]] && echo "$f"
      done \
    | sort -r | head -1 || true)"

if [[ -n "$PREV_30J_FILE" && -f "$PREV_30J_FILE" ]]; then
    log "INFO" "Rapport 30j trouvé : $(basename "$PREV_30J_FILE")"
    HEADER_30J="$(head -1 "$PREV_30J_FILE")"
    COL_COUNT_30J=$(echo "$HEADER_30J" | awk -F',' '{print NF}')
    while IFS=',' read -ra fields; do
        [[ "${fields[0]}" == "date" ]] && continue
        [[ "${fields[2]}" == "ERREUR" ]] && continue
        local_url="${fields[1]}"
        if [[ $COL_COUNT_30J -ge 7 ]]; then
            # Détection format : nouveau (tendance_a11y_30j en col 4) ou ancien (score_raweb en col 4)
            if [[ "$HEADER_30J" == *"tendance_a11y_30j,score_raweb"* ]]; then
                prev_a11y_30j["$local_url"]="${fields[2]}"
                prev_raweb_30j["$local_url"]="${fields[5]}"
            else
                prev_a11y_30j["$local_url"]="${fields[2]}"
                prev_raweb_30j["$local_url"]="${fields[4]}"
            fi
        else
            prev_a11y_30j["$local_url"]="${fields[2]}"
        fi
    done < "$PREV_30J_FILE"
else
    log "INFO" "Aucun rapport 30j disponible (moins de 30j d'historique)"
fi

# =============================================================
# 3. Génération du CSV
# =============================================================
CSV_FILE="$MONTH_DIR/rapport_${TODAY}.csv"
echo "date,url,score_a11y,tendance_a11y,tendance_a11y_30j,score_raweb,tendance_raweb,tendance_raweb_30j,statut" > "$CSV_FILE"

# =============================================================
# 4. Génération des lignes HTML
# =============================================================
HTML_ROWS=""
CELL="padding:10px 14px; border-bottom:1px solid #e8ecf0;"
CELL_C="padding:10px 14px; border-bottom:1px solid #e8ecf0; text-align:center; white-space:nowrap;"

mapfile -t SORTED_URLS < <(printf '%s\n' "${!scores_a11y_by_url[@]}" | sort)
for url in "${SORTED_URLS[@]}"; do
    count="${count_by_url["$url"]}"
    avg_a11y=$(( scores_a11y_by_url["$url"] / count ))

    # Score RAWeb (peut être absent)
    if [[ -n "${count_raweb_by_url["$url"]:-}" && ${count_raweb_by_url["$url"]} -gt 0 ]]; then
        avg_raweb=$(( scores_raweb_by_url["$url"] / count_raweb_by_url["$url"] ))
    else
        avg_raweb=-1
    fi

    # --- Tendances 7j ---
    t_label_a11y="$(trend_label "$avg_a11y" "${prev_a11y["$url"]:-}")"
    t_style_a11y="$(trend_style "$avg_a11y" "${prev_a11y["$url"]:-}")"
    t_csv_a11y="$(trend_csv   "$avg_a11y" "${prev_a11y["$url"]:-}")"

    # --- Tendances 30j ---
    t_label_a11y_30j="$(trend_label "$avg_a11y" "${prev_a11y_30j["$url"]:-}")"
    t_style_a11y_30j="$(trend_style "$avg_a11y" "${prev_a11y_30j["$url"]:-}")"
    t_csv_a11y_30j="$(trend_csv   "$avg_a11y" "${prev_a11y_30j["$url"]:-}")"

    if [[ $avg_raweb -ge 0 ]]; then
        t_label_raweb="$(trend_label "$avg_raweb" "${prev_raweb["$url"]:-}")"
        t_style_raweb="$(trend_style "$avg_raweb" "${prev_raweb["$url"]:-}")"
        t_csv_raweb="$(trend_csv   "$avg_raweb" "${prev_raweb["$url"]:-}")"
        t_label_raweb_30j="$(trend_label "$avg_raweb" "${prev_raweb_30j["$url"]:-}")"
        t_style_raweb_30j="$(trend_style "$avg_raweb" "${prev_raweb_30j["$url"]:-}")"
        t_csv_raweb_30j="$(trend_csv   "$avg_raweb" "${prev_raweb_30j["$url"]:-}")"
        raweb_display="$avg_raweb"
        raweb_style="$(score_style "$avg_raweb")"
        raweb_csv="$avg_raweb"
    else
        t_label_raweb="n/a"
        t_style_raweb="color:#888888;"
        t_csv_raweb="n/a"
        t_label_raweb_30j="n/a"
        t_style_raweb_30j="color:#888888;"
        t_csv_raweb_30j="n/a"
        raweb_display="N/A"
        raweb_style="color:#888888;"
        raweb_csv="-1"
    fi

    # --- Style et labels accessibles ---
    a11y_style="$(score_style "$avg_a11y")"
    a11y_label="$(score_label "$avg_a11y")"
    t_aria_a11y="$(trend_aria "$avg_a11y" "${prev_a11y["$url"]:-}")"
    t_aria_a11y_30j="$(trend_aria "$avg_a11y" "${prev_a11y_30j["$url"]:-}")"

    if [[ $avg_raweb -ge 0 ]]; then
        raweb_label="$(score_label "$avg_raweb")"
        t_aria_raweb="$(trend_aria "$avg_raweb" "${prev_raweb["$url"]:-}")"
        t_aria_raweb_30j="$(trend_aria "$avg_raweb" "${prev_raweb_30j["$url"]:-}")"
    else
        raweb_label="Non disponible"
        t_aria_raweb="Non disponible"
        t_aria_raweb_30j="Non disponible"
    fi

    # --- Couleur de fond ligne (rouge si a11y critique) ---
    # bgcolor sur chaque <td> pour compatibilité Outlook (ignore background sur <tr>)
    row_bg=""
    row_bg_attr=""
    if [[ $avg_a11y -lt 50 ]]; then
        row_bg=" background-color:#fff0f0;"
        row_bg_attr=' bgcolor="#fff0f0"'
    fi

    # --- Ligne HTML ---
    HTML_ROWS="${HTML_ROWS}<tr>"
    HTML_ROWS="${HTML_ROWS}<td${row_bg_attr} style=\"${CELL}${row_bg} word-break:break-word;\"><a href=\"${url}\" style=\"color:#1a3a5c;\">${url}</a></td>"
    HTML_ROWS="${HTML_ROWS}<td${row_bg_attr} style=\"${CELL_C}${row_bg} ${a11y_style}\" aria-label=\"Score accessibilité : ${avg_a11y} sur 100, niveau ${a11y_label}\">${avg_a11y}</td>"
    HTML_ROWS="${HTML_ROWS}<td${row_bg_attr} style=\"${CELL_C}${row_bg} ${t_style_a11y}\" aria-label=\"Tendance accessibilité depuis dernier rapport : ${t_aria_a11y}\">${t_label_a11y}</td>"
    HTML_ROWS="${HTML_ROWS}<td${row_bg_attr} style=\"${CELL_C}${row_bg} ${t_style_a11y_30j}\" aria-label=\"Tendance accessibilité sur 30 jours : ${t_aria_a11y_30j}\">${t_label_a11y_30j}</td>"
    HTML_ROWS="${HTML_ROWS}<td${row_bg_attr} style=\"${CELL_C}${row_bg} ${raweb_style}\" aria-label=\"Score RAWeb : ${raweb_display}, niveau ${raweb_label}\">${raweb_display}</td>"
    HTML_ROWS="${HTML_ROWS}<td${row_bg_attr} style=\"${CELL_C}${row_bg} ${t_style_raweb}\" aria-label=\"Tendance RAWeb depuis dernier rapport : ${t_aria_raweb}\">${t_label_raweb}</td>"
    HTML_ROWS="${HTML_ROWS}<td${row_bg_attr} style=\"${CELL_C}${row_bg} ${t_style_raweb_30j}\" aria-label=\"Tendance RAWeb sur 30 jours : ${t_aria_raweb_30j}\">${t_label_raweb_30j}</td>"
    HTML_ROWS="${HTML_ROWS}</tr>"

    # --- Ligne CSV ---
    echo "${TODAY},${url},${avg_a11y},${t_csv_a11y},${t_csv_a11y_30j},${raweb_csv},${t_csv_raweb},${t_csv_raweb_30j},OK" >> "$CSV_FILE"
done

# =============================================================
# 5. Lignes pour les URLs en échec de collecte
# =============================================================
FAILED_URLS_FILE="$WORK_DIR/failed_urls.txt"
if [[ -f "$FAILED_URLS_FILE" ]]; then
    FAIL_BG=" background-color:#fff0f0;"
    FAIL_BG_ATTR=' bgcolor="#fff0f0"'
    FAIL_STYLE="color:#cc1f1f; font-weight:bold;"

    while IFS= read -r failed_url; do
        [[ -z "$failed_url" ]] && continue

        HTML_ROWS="${HTML_ROWS}<tr>"
        HTML_ROWS="${HTML_ROWS}<td${FAIL_BG_ATTR} style=\"${CELL}${FAIL_BG} word-break:break-word;\">${failed_url}</td>"
        HTML_ROWS="${HTML_ROWS}<td${FAIL_BG_ATTR} colspan=\"6\" style=\"${CELL_C}${FAIL_BG} ${FAIL_STYLE}\">&#9888;&nbsp;Échec de collecte</td>"
        HTML_ROWS="${HTML_ROWS}</tr>"

        echo "${TODAY},${failed_url},ERREUR,n/a,n/a,-1,n/a,n/a,ERREUR" >> "$CSV_FILE"

        log "INFO" "Ligne erreur ajoutée : $failed_url"
    done < <(sort "$FAILED_URLS_FILE")
fi

# --- Sauvegarde des lignes HTML pour 04-notify.sh ---
echo "$HTML_ROWS" > "$WORK_DIR/email_rows.html"

log "INFO" "CSV généré : $CSV_FILE"
log "INFO" "HTML rows générés : $WORK_DIR/email_rows.html"
log "INFO" "Report OK"
exit 0
