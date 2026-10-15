#!/bin/zsh
# Jauge — installation ou mise à jour, sans compte GitHub et sans outil à installer :
#   curl -fsSL https://raw.githubusercontent.com/LucasHRCHatReply/jauge-releases/main/installer.sh | zsh
# Options (après `zsh -s --`) : --oui (quitter AlDente sans demander), --rapport (écrire le rapport de test sur
# le Bureau), --sans-rapport. Sans terminal, le script ne pose jamais de question.
# Réglages, historique et appareils ne sont jamais touchés. Aucun mot de passe administrateur.
set -uo pipefail
ZIP_URL="${JAUGE_ZIP_URL:-https://github.com/LucasHRCHatReply/jauge-releases/releases/latest/download/Jauge.zip}"
TEAM="JT9FY7PP7K"
OUI=0; RAPPORT=ask
for a in "$@"; do
  case "$a" in
    --oui) OUI=1 ;;
    --rapport) RAPPORT=oui ;;
    --sans-rapport) RAPPORT=non ;;
    *) echo "Option inconnue : $a" >&2; exit 2 ;;
  esac
done
fail() { echo "\nÉCHEC : $*" >&2; exit 1; }
step() { echo "\n[$1/5] $2"; }
if [[ -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then HAS_TTY=1; else HAS_TTY=0; fi
ask() { (( HAS_TTY )) || return 1; local r; read -q "r?$1 [o/N] " </dev/tty || { echo; return 1; }; echo; return 0 }

step 1 "Ce Mac convient-il ?"
macos=$(sw_vers -productVersion)
(( ${macos%%.*} >= 26 )) || fail "Jauge demande macOS 26 ou plus (ce Mac : $macos). Mettre macOS à jour, puis relancer."
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]] || fail "Jauge ne tourne que sur les Mac à puce Apple (M1 ou plus récent)."
echo "  macOS $macos, $(sysctl -n machdep.cpu.brand_string 2>/dev/null) : ok"

step 2 "AlDente"
if pgrep -f "AlDente.*/Contents/MacOS" >/dev/null; then
  echo "  AlDente tourne : deux apps qui pilotent la charge se contredisent, il faut le quitter."
  if (( OUI )) || ask "  Quitter AlDente maintenant ?"; then
    osascript -e 'tell application "AlDente" to quit' >/dev/null 2>&1 || true
    for i in {1..10}; do pgrep -f "AlDente.*/Contents/MacOS" >/dev/null || break; sleep 0.5; done
    pkill -f "AlDente.*/Contents/MacOS" 2>/dev/null || true
    echo "  AlDente quitté (à retirer aussi de « Ouvrir à la connexion », sinon il se relance seul)."
  else
    fail "AlDente est ouvert. Le quitter, ou relancer avec l'option --oui (zsh -s -- --oui)."
  fi
else
  echo "  AlDente ne tourne pas : ok"
fi

step 3 "Téléchargement et contrôle"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jauge-install.XXXXXX") || fail "dossier temporaire impossible"
trap 'rm -rf "$WORK"' EXIT
curl -fL --silent --show-error -o "$WORK/Jauge.zip" "$ZIP_URL" || fail "téléchargement impossible (réseau coupé, ou aucune version publiée) : $ZIP_URL"
# Empreinte publiée avec la Release (depuis la 1.0.3) : si elle existe, elle doit correspondre.
if curl -fL --silent -o "$WORK/Jauge.zip.sha256" "$ZIP_URL.sha256" 2>/dev/null && [[ -s "$WORK/Jauge.zip.sha256" ]]; then
  want=$(awk '{print $1; exit}' "$WORK/Jauge.zip.sha256"); have=$(shasum -a 256 "$WORK/Jauge.zip" | awk '{print $1}')
  [[ "$want" == "$have" ]] || fail "l'empreinte SHA-256 du zip ne correspond pas à celle publiée : installation refusée."
  echo "  empreinte SHA-256 : conforme"
fi
ditto -x -k "$WORK/Jauge.zip" "$WORK/contenu" || fail "le zip est illisible"
DIR=$(ls -d "$WORK"/contenu/Jauge-* 2>/dev/null | head -1)
[[ -n "$DIR" && -d "$DIR/Jauge.app" && -f "$DIR/install.sh" ]] || fail "le zip n'a pas le contenu attendu (Jauge-X.Y.Z/Jauge.app et install.sh)."
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DIR/Jauge.app/Contents/Info.plist" 2>/dev/null)" == "fr.jauge.app" ]] || fail "identifiant de l'app inattendu : installation refusée."
got=$(codesign -dv "$DIR/Jauge.app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[[ "$got" == "$TEAM" ]] || fail "l'app n'est pas signée par l'équipe attendue ($TEAM) mais par « ${got:-aucune} » : installation refusée."
codesign --verify --deep --strict "$DIR/Jauge.app" 2>/dev/null || fail "la signature de Jauge.app est invalide : installation refusée."
NEW=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIR/Jauge.app/Contents/Info.plist")
echo "  Jauge $NEW, signature valide, équipe $TEAM : ok  ($(du -h "$WORK/Jauge.zip" | cut -f1))"

APP="$HOME/Applications/Jauge.app"
CTL="$APP/Contents/MacOS/Jauge"
reglages() { [[ -x "$CTL" ]] && "$CTL" --ctl status 2>/dev/null | grep -E '"(limit|sailing|version|versionsEgales)"' | tr -d ' \n'; echo; }
AVANT=$(reglages)
[[ -n "$AVANT" ]] && echo "  avant : $AVANT"

step 4 "Installation"
zsh "$DIR/install.sh" "$DIR/Jauge.app" || fail "l'installation a échoué (voir le message ci-dessus)."
state=$("$CTL" --ctl install-state 2>/dev/null || echo "?")
if [[ "$state" != "ready" ]]; then
  cat <<MSG

  ÉTAPE MANUELLE (une seule fois) : Réglages Système › Général › Ouverture et arrière-plan,
  section « Autoriser en arrière-plan » : activer « Jauge ». Le panneau s'est ouvert.
  Attente jusqu'à 3 minutes…
MSG
  open "x-apple.systempreferences:com.apple.LoginItems-Settings.extension" 2>/dev/null || true
  deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    state=$("$CTL" --ctl install-state 2>/dev/null || echo "?")
    [[ "$state" == "ready" ]] && break
    sleep 3
  done
fi
[[ "$state" == "ready" ]] || fail "l'autorisation n'a pas été donnée en 3 minutes (état : $state). L'activer dans Réglages Système › Général › Ouverture et arrière-plan › Jauge, puis relancer la même commande (réinstaller est sans risque)."
sleep 2
APRES=$(reglages)
echo "  Jauge est installée et active."
[[ -n "$APRES" ]] && echo "  après : $APRES"

step 5 "Rapport de test"
INSTALLEE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)
# Le rapport sur fichier existe depuis la 1.0.2.
if [[ "$(printf '%s\n%s\n' 1.0.2 "${INSTALLEE:-0}" | sort -V | head -1)" != "1.0.2" ]]; then
  echo "  Cette version ne sait pas encore écrire de rapport : rien à envoyer."
elif [[ "$RAPPORT" == "oui" ]] || { [[ "$RAPPORT" == "ask" ]] && ask "  Écrire un rapport de test (modèle, clés de charge, batterie) sur le Bureau, à envoyer à Lucas ?"; }; then
  "$CTL" --ctl rapport --fichier | tail -2
else
  echo "  Plus tard :  ~/Applications/Jauge.app/Contents/MacOS/Jauge --ctl rapport --fichier"
fi
echo "\nTerminé."
