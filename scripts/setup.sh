#!/opt/homebrew/bin/bash
set -euo pipefail

# =============================================================
# setup.sh — Installation des launchd agents + réveil pmset
# Usage : ./setup.sh
# À lancer une seule fois (ou après modification des plists)
# =============================================================

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHD_DIR="$BASE_DIR/launchd"
AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs/lhci"

echo ""
echo "=== Installation LHCI Monitoring ==="
echo ""

# --- Création des répertoires nécessaires ---
echo "→ Création des répertoires..."
mkdir -p "$AGENTS_DIR" "$LOG_DIR" \
    "$BASE_DIR/runs" \
    "$BASE_DIR/reports"
echo "  OK"

# --- Symlink du plugin RAWeb dans node_modules ---
echo "→ Installation du plugin lighthouse-plugin-raweb..."
mkdir -p "$BASE_DIR/node_modules"
ln -sf "../plugins/lighthouse-plugin-raweb" "$BASE_DIR/node_modules/lighthouse-plugin-raweb"
echo "  OK"

# --- Génération des plists depuis les templates ---
echo "→ Génération des launchd agents..."

for TEMPLATE in "$LAUNCHD_DIR"/*.plist.example; do
    LABEL="$(basename "${TEMPLATE%.example}")"
    PLIST="$LAUNCHD_DIR/${LABEL}"
    DEST="$AGENTS_DIR/$LABEL"

    # Substitution des placeholders
    sed -e "s|{{BASE_DIR}}|$BASE_DIR|g" \
        -e "s|{{HOME}}|$HOME|g" \
        "$TEMPLATE" > "$PLIST"
    echo "  Généré : $PLIST"

    # Déchargement si déjà chargé
    if launchctl list | grep -q "${LABEL%.plist}" 2>/dev/null; then
        echo "  Déchargement de ${LABEL%.plist}..."
        launchctl unload "$DEST" 2>/dev/null || true
    fi

    cp "$PLIST" "$DEST"
    echo "  Copié : $DEST"
done

# --- Chargement des agents ---
echo "→ Chargement des launchd agents..."

for PLIST in "$AGENTS_DIR"/com.lhci.*.plist; do
    launchctl load "$PLIST"
    echo "  Chargé : $(basename "$PLIST")"
done

# --- Vérification ---
echo "→ Vérification..."
launchctl list | grep "com.lhci" || echo "  WARN : aucun agent com.lhci trouvé dans launchctl list"

# --- Réveil pmset (lundi à 05:55) ---
echo ""
echo "→ Configuration du réveil automatique (sudo requis)..."
echo "  Jour : lundi (M) à 05:55"
echo ""

sudo pmset repeat wake M 05:55:00

echo ""
echo "  Réveil configuré. Vérification :"
pmset -g sched | grep -i wake || echo "  (aucune entrée wake visible)"

# --- Résumé ---
echo ""
echo "=== Installation terminée ==="
echo ""
echo "  Planification :"
echo "    Lundi   06:00 — com.lhci.monday"
echo "    Réveil  05:55 — lundi (pmset)"
echo ""
echo "  Logs : $LOG_DIR/runner.log"
echo ""
echo "  Pour tester manuellement :"
echo "    $BASE_DIR/scripts/run-all.sh"
echo ""
