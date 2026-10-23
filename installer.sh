#!/bin/zsh
# Jauge — installation ou mise à jour, sans compte GitHub et sans outil à installer :
#   curl -fsSL https://raw.githubusercontent.com/LucasHRCHatReply/jauge-releases/main/installer.sh | zsh
# Options (après `zsh -s --`) : --oui (quitter AlDente sans demander), --rapport (écrire le rapport de test sur
# le Bureau), --sans-rapport, --propre (installation qui fait le ménage : voir plus bas). Sans terminal, le script
# ne pose jamais de question.
# Réglages, historique et appareils ne sont jamais touchés. Jauge se place dans /Applications : macOS demande alors le mot de passe du Mac dans sa propre boîte (le démon de charge tourne en root, personne d'autre ne doit pouvoir le remplacer).
# --propre : avant d'installer, quitte Jauge, désinscrit le démon, liste les AUTRES copies de Jauge.app (identifiant
# fr.jauge.app, trouvées par Spotlight, hors ~/Applications) et les met à la Corbeille (jamais rm -rf ; avec --oui
# sans demander, sinon une confirmation par copie), retire les anciens plist de lancement et binaires du démon laissés
# hors de l'app, puis installe et vérifie que l'app et le démon ont la même version. Ne touche jamais aux réglages ni
# à l'historique, ni à rien sous ~/Jauge ou ~/Library/Developer (Mac de développement).
set -uo pipefail
ZIP_URL="${JAUGE_ZIP_URL:-https://github.com/LucasHRCHatReply/jauge-releases/releases/latest/download/Jauge.zip}"
TEAM="JT9FY7PP7K"
OUI=0; RAPPORT=ask; PROPRE=0
for a in "$@"; do
  case "$a" in
    --oui) OUI=1 ;;
    --rapport) RAPPORT=oui ;;
    --sans-rapport) RAPPORT=non ;;
    --propre) PROPRE=1 ;;
    *) echo "Option inconnue : $a" >&2; exit 2 ;;
  esac
done
fail() { echo "\nÉCHEC : $*" >&2; exit 1; }
step() { echo "\n[$1/5] $2"; }
if [[ -z "${JAUGE_SANS_TTY:-}" && -r /dev/tty ]] && { : </dev/tty; } 2>/dev/null; then HAS_TTY=1; else HAS_TTY=0; fi
ask() { (( HAS_TTY )) || return 1; local r; read -q "r?$1 [o/N] " </dev/tty || { echo; return 1; }; echo; return 0 }

# JAUGE_APP : app à traiter à la place de /Applications/Jauge.app (essais : un faux dossier, jamais le vrai démon).
# En mode essai (JAUGE_PROPRE_SEUL), JAUGE_APP est obligatoire : sans lui le script viserait la vraie app et désinscrirait le vrai démon.
if [[ -n "${JAUGE_PROPRE_SEUL:-}" && -z "${JAUGE_APP:-}" ]]; then echo "ÉCHEC : JAUGE_PROPRE_SEUL demande JAUGE_APP (un faux dossier d'essai)." >&2; exit 3; fi
APP="${JAUGE_APP:-/Applications/Jauge.app}"
[[ -n "${JAUGE_APP:-}" || -d "$APP" ]] || { [[ -d "$HOME/Applications/Jauge.app" ]] && APP="$HOME/Applications/Jauge.app"; }   # ancienne installation
CTL="$APP/Contents/MacOS/Jauge"

# Met un fichier ou une app à la Corbeille (jamais rm -rf). JAUGE_CORBEILLE : dossier de remplacement (essais).
corbeille() {
  local src="$1" dir="${JAUGE_CORBEILLE:-}"
  if [[ -z "$dir" ]]; then
    osascript -e "tell application \"Finder\" to delete POSIX file \"$src\"" >/dev/null 2>&1 && [[ ! -e "$src" ]] && return 0
    dir="$HOME/.Trash"
  fi
  mkdir -p "$dir" 2>/dev/null || return 1
  local dest="$dir/${src:t}"; [[ -e "$dest" ]] && dest="$dir/${src:t:r} $(date +%H.%M.%S).$RANDOM.${src:e}"
  mv "$src" "$dest" 2>/dev/null
}

# Une copie à ignorer : la copie installée, tout ce qui est sous ~/Jauge, ~/Library/Developer, DerivedData ou la Corbeille.
a_ignorer() {
  local p="${1:A}"
  [[ "$p" == "${APP:A}" ]] && return 0
  [[ "$p" == "${HOME:A}/Jauge/"* || "$p" == "${HOME:A}/Library/Developer/"* || "$p" == */DerivedData/* || "$p" == "${HOME:A}/.Trash/"* ]] && return 0
  return 1
}

# Le ménage de --propre, avant l'installation : (a) quitter, (b) désinscrire le démon, (c) autres copies, (d) restes hors de l'app.
menage() {
  echo "\n[ménage] --propre"
  # (a) quitter Jauge
  if pgrep -x Jauge >/dev/null; then
    osascript -e 'tell application "Jauge" to quit' >/dev/null 2>&1 || true
    for i in {1..10}; do pgrep -x Jauge >/dev/null || break; sleep 0.5; done
    pkill -x Jauge 2>/dev/null || true
    echo "  Jauge quittée"
  else echo "  Jauge ne tourne pas"; fi
  # (b) désinscrire le démon (il remet les clés de charge à l'état normal en s'arrêtant)
  if [[ -x "$CTL" ]]; then
    "$CTL" --ctl unregister >/dev/null 2>&1 || true
    [[ -z "${JAUGE_PROPRE_SEUL:-}" ]] && sleep 1
    echo "  démon désinscrit"
  else echo "  aucune Jauge installée : rien à désinscrire"; fi
  # (c) les autres copies
  local found=() p
  while IFS= read -r p; do
    [[ -n "$p" && -d "$p" && "${p:e}" == "app" ]] || continue
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$p/Contents/Info.plist" 2>/dev/null)" == "fr.jauge.app" ]] || continue
    a_ignorer "$p" && continue
    found+=("$p")
  done < <(eval "${JAUGE_MDFIND_CMD:-mdfind \"kMDItemCFBundleIdentifier == 'fr.jauge.app'\"}" 2>/dev/null)
  if (( ${#found} == 0 )); then echo "  aucune autre copie de Jauge.app"
  else
    echo "  Autres copies de Jauge.app (identifiant fr.jauge.app) :"
    for p in $found; do echo "    - $p  ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$p/Contents/Info.plist" 2>/dev/null))"; done
    for p in $found; do
      if (( OUI )) || ask "  Mettre à la Corbeille « $p » ?"; then
        corbeille "$p" && echo "  à la Corbeille : $p" || echo "  impossible de déplacer : $p (à retirer à la main)" >&2
      else echo "  conservée : $p"; fi
    done
  fi
  # (d) anciens plist de lancement et binaires du démon hors de l'app (Jauge n'en pose plus : le démon vit dans l'app, SMAppService)
  local root="${JAUGE_RACINE:-}" r
  for r in "$root/Library/LaunchDaemons/fr.jauge.daemon.plist" "$root/Library/PrivilegedHelperTools/fr.jauge.daemon" \
           "$root/Library/LaunchDaemons/fr.jauge.plist" "$HOME/Library/LaunchAgents/fr.jauge.app.plist" "$HOME/Library/LaunchAgents/fr.jauge.daemon.plist"; do
    [[ -e "$r" ]] || continue
    if corbeille "$r"; then echo "  ancien reste retiré (Corbeille) : $r"
    else echo "  ancien reste à retirer avec sudo : $r"; fi
  done
}

(( PROPRE )) && [[ -n "${JAUGE_PROPRE_SEUL:-}" ]] && { menage; exit 0; }

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

reglages() { [[ -x "$CTL" ]] && "$CTL" --ctl status 2>/dev/null | grep -E '"(limit|sailing|version|versionsEgales)"' | tr -d ' \n'; echo; }
AVANT=$(reglages)
[[ -n "$AVANT" ]] && echo "  avant : $AVANT"

(( PROPRE )) && menage
step 4 "Installation"
zsh "$DIR/install.sh" "$DIR/Jauge.app" || fail "l'installation a échoué (voir le message ci-dessus)."
if [[ -d /Applications/Jauge.app ]]; then APP="/Applications/Jauge.app"; else APP="$HOME/Applications/Jauge.app"; fi
CTL="$APP/Contents/MacOS/Jauge"
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
# L'app et le démon doivent avoir la même version (sinon l'ancien démon tourne encore : --propre ou « Réparer »).
VERS=$("$CTL" --ctl version 2>/dev/null)
va=$(print -r -- "$VERS" | sed -n 's/^app //p'); vd=$(print -r -- "$VERS" | sed -n 's/^démon //p')
if [[ -n "$va" && "$va" == "$vd" ]]; then echo "  app et démon : même version ($va)"
elif (( PROPRE )); then fail "l'app ($va) et le démon (${vd:-injoignable}) n'ont pas la même version. Ouvrir Jauge › Réglages › Démon › Réparer, puis relancer."
else echo "  attention : app ($va) et démon (${vd:-injoignable}) n'ont pas la même version (relancer avec --propre)."; fi
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
  echo "  Plus tard :  $APP/Contents/MacOS/Jauge --ctl rapport --fichier"
fi
echo "\nTerminé."
