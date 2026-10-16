#!/bin/sh
# Installation du pack régional dans le conteneur de l'application sur le
# SIMULATEUR iOS. REQUIERT une autorisation ciblée : écriture hors projet
# (conteneur simulateur) + vérification SHA-256 après copie.
#
# Usage : tool/routing_proof/scripts/install_regional_pack.sh <udid_simulateur>
#
# Étapes :
#   1. Vérifie l'empreinte locale du pack avant copie.
#   2. Copie routing_regional.tar + valhalla.template.json dans
#      <Documents>/routing/ du conteneur via `xcrun simctl get_app_container`
#      puis copie de fichiers (simctl n'offre pas de push direct).
#   3. Supprime le valhalla.json généré précédemment pour forcer sa
#      réécriture au prochain lancement (évite toute réutilisation
#      silencieuse de l'ancienne configuration pointant l'ancien pack).
#   4. Vérifie le SHA-256 du fichier RÉELLEMENT installé.
#
# Conserve ObjectBox, trajets, repères et préférences : aucun fichier
# hors <Documents>/routing/ n'est touché. L'application doit ensuite être
# relancée (le moteur Valhalla natif garde son instance en mémoire).

set -eu

UDID="${1:?Usage: $0 <udid_simulateur>}"
BUNDLE="com.casaloopengine.casaLoopEngine"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GRAPH_DIR="$ROOT/tool/routing_regional/graph"
TAR="$GRAPH_DIR/routing_regional.tar"
TEMPLATE="$GRAPH_DIR/valhalla.template.json"
EXPECTED_SHA="090c7a4f07ff90a3ac2845f378d712599e4ebd428432e660030831dc55c4456a"

echo "==> Empreinte locale du pack"
actual="$(shasum -a 256 "$TAR" | awk '{print $1}')"
[ "$actual" = "$EXPECTED_SHA" ] || { echo "SHA-256 inattendu : $actual"; exit 1; }
echo "    $actual"

echo "==> Conteneur applicatif du simulateur $UDID"
DATA_DIR="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
ROUTING_DIR="$DATA_DIR/Documents/routing"
mkdir -p "$ROUTING_DIR"

echo "==> Copie du pack et du gabarit"
cp "$TAR" "$ROUTING_DIR/routing_regional.tar"
cp "$TEMPLATE" "$ROUTING_DIR/valhalla.template.json"

echo "==> Invalidation de l'ancienne configuration générée"
rm -f "$ROUTING_DIR/valhalla.json"

echo "==> Vérification du pack effectivement installé"
installed="$(shasum -a 256 "$ROUTING_DIR/routing_regional.tar" | awk '{print $1}')"
[ "$installed" = "$EXPECTED_SHA" ] || { echo "Copie corrompue : $installed"; exit 1; }
echo "    installé : $installed"
echo "==> Terminé. Relancer l'application : le service reconfigurera le"
echo "    moteur sur routing_regional.tar au premier calcul."
