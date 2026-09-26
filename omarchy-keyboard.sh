#!/usr/bin/env bash
# omarchy-keyboard-switch: user-local AZERTY / US International helper
set -euo pipefail

die() { printf 'Erreur : %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'EOF'
Usage : omarchy-keyboard [toggle|qwerty|azerty|status|install [lua|conf]|uninstall [lua|conf]]

  install    Installe la commande et Ctrl+Alt+Espace (sauvegarde incluse).
  toggle     Bascule tous les claviers selon la disposition du clavier principal.
  qwerty     US International, avec touches mortes (us / intl).
  azerty     Francais AZERTY classique (fr).
  status     Affiche les dispositions actives.
  uninstall  Retire le bloc ajoute et la commande installee.

A executer dans une session Omarchy / Hyprland, sans sudo.
EOF
}

need() { command -v "$1" >/dev/null 2>&1 || die "Commande manquante : $1"; }
session() {
  need hyprctl
  need jq
  [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || die 'Ouvre un terminal dans ta session Hyprland.'
}
hypr_ok() {
  local result
  result=$(hyprctl "$@") || die "hyprctl $* a echoue."
  [[ $result == ok ]] || die "hyprctl $* : $result"
}

config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}/hypr
binary=$HOME/.local/bin/omarchy-keyboard
begin='# BEGIN omarchy-keyboard-switch'
end='# END omarchy-keyboard-switch'
config=''
format=''

select_config() {
  format=${1:-}
  if [[ -z $format ]]; then
    if [[ -f $config_root/hyprland.lua && -f $config_root/hyprland.conf ]]; then
      die 'Les deux formats existent. Precise install lua ou install conf (ou uninstall).'
    elif [[ -f $config_root/hyprland.lua ]]; then
      format=lua
    elif [[ -f $config_root/hyprland.conf ]]; then
      format=conf
    else
      die "Configuration Omarchy introuvable dans $config_root."
    fi
  fi
  case $format in
    lua) begin='-- BEGIN omarchy-keyboard-switch'; end='-- END omarchy-keyboard-switch' ;;
    conf) ;;
    *) die 'Format attendu : lua ou conf.' ;;
  esac
  config=$config_root/input.$format
  [[ -f $config ]] || die "Fichier introuvable : $config"
}

# Reject damaged markers rather than removing unrelated lines.
check_markers() {
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { if (inside || count++) exit 1; inside=1 }
    $0 == end { if (!inside) exit 1; inside=0; closed++ }
    END { if (inside || count != closed) exit 1 }
  ' "$config" || die "Bloc gere incomplet ou duplique dans $config."
}
without_block() {
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { inside=1; next }
    $0 == end { inside=0; next }
    !inside { print }
  ' "$config"
}
backup_config() {
  backup=$(mktemp "$config.backup.XXXXXXXX")
  cp -pL -- "$config" "$backup"
  printf 'Sauvegarde : %s\n' "$backup"
}
write_block() {
  printf '%s\n' "$begin"
  if [[ $format == lua ]]; then
    cat <<'EOF'
hl.config({ input = { kb_layout = "us,fr", kb_variant = "intl," } })
hl.bind("CONTROL + ALT + SPACE", hl.dsp.exec_cmd("~/.local/bin/omarchy-keyboard toggle"), { description = "Toggle keyboard layout" })
EOF
  else
    cat <<'EOF'
input {
    kb_layout = us,fr
    kb_variant = intl,
}
bind = CTRL ALT, SPACE, exec, ~/.local/bin/omarchy-keyboard toggle
EOF
  fi
  printf '%s\n' "$end"
}
devices() { hyprctl -j devices; }
# Hyprland exposes the software keyboards created by input methods (fcitx5,
# ibus, ...) among the regular keyboards. They keep their own layout, which is
# not covered by kb_layout, and they are often flagged as main. They must be
# left out of both the layout check and the source of the toggle direction.
real='map(select(.name | startswith("hl-virtual-keyboard-") | not))'
real_layouts='.keyboards | '"$real"' | length > 0 and all(.[]; .layout == "us,fr" and .variant == "intl,")'
real_synced='.keyboards | '"$real"' | length > 0 and all(.[]; .active_layout_index == $index)'
real_current='(.keyboards | '"$real"' | map(select(.main)) | .[0]).active_layout_index // (.keyboards | '"$real"' | .[0].active_layout_index)'
check_layouts() {
  jq -e "$real_layouts" \
    <<< "$1" >/dev/null || die 'Les claviers doivent utiliser us,fr / intl,. Lance install ; verifie les overrides par peripherique.'
}
show_status() {
  jq -r '.keyboards[] | "\(.name) : \(.active_keymap)\(if (.name | startswith("hl-virtual-keyboard-")) then " [virtuel]" elif .main then " [principal]" else "" end)"' <<< "$1"
}

action=${1:-toggle}
case $action in
  -h|--help|help) usage; exit 0 ;;
  toggle|qwerty|azerty|status) [[ $# -le 1 ]] || die 'Trop d’arguments.' ;;
  install|uninstall) [[ $# -le 2 ]] || die 'Trop d’arguments.' ;;
  *) usage >&2; exit 2 ;;
esac

if [[ $action == install || $action == uninstall ]]; then
  [[ $EUID -ne 0 ]] || die 'Lance ce script sans sudo.'
  select_config "${2:-}"
  check_markers
  if [[ $action == install ]]; then
    session
    errors=$(hyprctl configerrors)
    [[ -z $errors ]] || die "Corrige les erreurs Hyprland existantes avant installation : $errors"
    # Do not replace an unrelated command with the same name.
    if [[ -e $binary ]]; then
      grep -q '^# omarchy-keyboard-switch: ' "$binary" || die "Une autre commande existe : $binary"
    fi
    backup_config
    temp=$(mktemp "$config.tmp.XXXXXXXX")
    trap 'rm -f -- "$temp"' EXIT
    without_block > "$temp"
    write_block >> "$temp"
    mkdir -p -- "${binary%/*}"
    # Installing from the already installed command must also work.
    if [[ ! $0 -ef $binary ]]; then
      install -m 755 -- "$0" "$binary"
    fi
    cat -- "$temp" > "$config"
    if ! hyprctl reload >/dev/null; then
      cp -p -- "$backup" "$config"
      die 'Rechargement impossible. Configuration precedente restauree.'
    fi
    errors=$(hyprctl configerrors)
    if [[ -n $errors ]]; then
      cp -p -- "$backup" "$config"
      hyprctl reload >/dev/null || true
      die "Configuration precedente restauree : $errors"
    fi
    check_layouts "$(devices)"
    hypr_ok switchxkblayout all 0
    printf 'Installe : %s\nCtrl+Alt+Espace : QWERTY US International <-> AZERTY francais.\n' "$binary"
    exit 0
  fi
  if grep -Fxq -- "$begin" "$config"; then
    backup_config
    temp=$(mktemp "$config.tmp.XXXXXXXX")
    trap 'rm -f -- "$temp"' EXIT
    without_block > "$temp"
    cat -- "$temp" > "$config"
  fi
  if [[ -f $binary ]] && grep -q '^# omarchy-keyboard-switch: ' "$binary"; then
    rm -- "$binary"
  fi
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v hyprctl >/dev/null 2>&1; then
    hypr_ok reload
  fi
  printf 'Bloc et commande retires. Sauvegardes conservees.\n'
  exit 0
fi

session
snapshot=$(devices)
if [[ $action == status ]]; then
  show_status "$snapshot"
  exit 0
fi
check_layouts "$snapshot"
case $action in
  qwerty) index=0 ;;
  azerty) index=1 ;;
  toggle)
    # Query the real compositor state, not a potentially stale state file.
    current=$(jq -er "$real_current" <<< "$snapshot") \
      || die 'Hyprland ne fournit pas active_layout_index. Utilise qwerty ou azerty, ou mets Hyprland a jour.'
    case $current in
      0) index=1 ;;
      1) index=0 ;;
      *) die "Indice de disposition inattendu : $current" ;;
    esac
    ;;
esac
hypr_ok switchxkblayout all "$index"
snapshot=$(devices)
jq -e --argjson index "$index" "$real_synced" \
  <<< "$snapshot" >/dev/null || die 'La bascule n’a pas ete confirmee pour tous les claviers.'
show_status "$snapshot"
if [[ $index == 0 ]]; then label='QWERTY US International'; else label='AZERTY francais'; fi
if command -v notify-send >/dev/null 2>&1; then
  notify-send -t 1800 'Clavier' "$label" >/dev/null 2>&1 || true
fi
