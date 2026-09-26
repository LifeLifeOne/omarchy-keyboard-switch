#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$root/omarchy-keyboard.sh
sandbox=$(mktemp -d)
trap 'rm -rf -- "$sandbox"' EXIT
export HOME=$sandbox/home XDG_CONFIG_HOME=$sandbox/config
export MOCK_ROOT=$sandbox HYPRLAND_INSTANCE_SIGNATURE=test-only
mkdir -p "$HOME" "$XDG_CONFIG_HOME/hypr" "$sandbox/bin"
export PATH=$sandbox/bin:$PATH
command -v jq >/dev/null || { echo 'jq is required for tests' >&2; exit 1; }
cat > "$sandbox/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  '-j devices') cat "$MOCK_ROOT/devices.json" ;;
  configerrors)
    if [[ -f $MOCK_ROOT/config-error && -f $MOCK_ROOT/reloaded ]]; then
      echo 'mock syntax error'
    fi
    ;;
  reload)
    touch "$MOCK_ROOT/reloaded"
    if [[ -f $MOCK_ROOT/reload-error ]]; then exit 1; fi
    echo ok
    ;;
  'switchxkblayout all 0'|'switchxkblayout all 1')
    printf '%s\n' "$*" >> "$MOCK_ROOT/calls"
    if [[ -f $MOCK_ROOT/switch-error ]]; then echo 'invalid keyboard'; exit 0; fi
    if [[ ! -f $MOCK_ROOT/no-change ]]; then
      jq --argjson idx "$3" '.keyboards |= map(.active_keymap=(if $idx==0 then "English (US, intl., with dead keys)" else "French" end) | .active_layout_index=(if (env.VIRTUAL_FROZEN=="1" and (.name | startswith("hl-virtual-keyboard-"))) then .active_layout_index else $idx end))' \
        "$MOCK_ROOT/devices.json" > "$MOCK_ROOT/next.json"
      mv "$MOCK_ROOT/next.json" "$MOCK_ROOT/devices.json"
    fi
    echo ok
    ;;
  *) echo "Unexpected mock call: $*" >&2; exit 9 ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$sandbox/bin/notify-send"
chmod +x "$sandbox/bin/"*
reset_devices() {
  cat > "$sandbox/devices.json" <<'EOF'
{"keyboards":[
  {"name":"laptop","main":false,"layout":"us,fr","variant":"intl,","active_layout_index":1,"active_keymap":"French"},
  {"name":"usb","main":true,"layout":"us,fr","variant":"intl,","active_layout_index":0,"active_keymap":"English (US, intl., with dead keys)"}
]}
EOF
}
expect_failure() {
  if "$@" > "$sandbox/error-output" 2>&1; then
    echo "Expected failure: $*" >&2; exit 1
  fi
}
assert_indices() {
  jq -e --argjson idx "$1" 'all(.keyboards[]; .active_layout_index==$idx)' "$sandbox/devices.json" >/dev/null
}
reset_devices_virtual() {
  cat > "$sandbox/devices.json" <<'EOF'
{"keyboards":[
  {"name":"laptop","main":false,"layout":"us,fr","variant":"intl,","active_layout_index":0,"active_keymap":"English (US, intl., with dead keys)"},
  {"name":"usb","main":true,"layout":"us,fr","variant":"intl,","active_layout_index":0,"active_keymap":"English (US, intl., with dead keys)"},
  {"name":"hl-virtual-keyboard-fcitx5","main":true,"layout":"fr","variant":"","active_layout_index":0,"active_keymap":"French"}
]}
EOF
}
assert_real_indices() {
  jq -e --argjson idx "$1" 'all(.keyboards[] | select(.name | startswith("hl-virtual-keyboard-") | not); .active_layout_index==$idx)' "$sandbox/devices.json" >/dev/null
}

bash -n "$script"
bash "$script" --help >/dev/null
reset_devices
bash "$script" toggle >/dev/null
assert_indices 1
bash "$script" toggle >/dev/null
assert_indices 0
bash "$script" azerty >/dev/null
assert_indices 1
bash "$script" qwerty >/dev/null
assert_indices 0
bash "$script" status | grep -q '\[principal\]'
echo 'PASS: toggle uses the main keyboard, synchronizes both devices, and explicit choices work'

reset_devices_virtual
bash "$script" status | grep -q '\[virtuel\]'
bash "$script" toggle >/dev/null
assert_real_indices 1
bash "$script" toggle >/dev/null
assert_real_indices 0
echo 'PASS: an input method virtual keyboard (fcitx5) is ignored by the layout check and by status'

reset_devices_virtual
export VIRTUAL_FROZEN=1
bash "$script" azerty >/dev/null
assert_real_indices 1
bash "$script" toggle >/dev/null
assert_real_indices 0
bash "$script" toggle >/dev/null
assert_real_indices 1
unset VIRTUAL_FROZEN
echo 'PASS: toggle direction follows a physical keyboard even when a virtual one is flagged main and frozen'

reset_devices

touch "$sandbox/switch-error"
expect_failure bash "$script" azerty
rm "$sandbox/switch-error"
touch "$sandbox/no-change"
expect_failure bash "$script" azerty
rm "$sandbox/no-change"
expect_failure env HYPRLAND_INSTANCE_SIGNATURE= bash "$script" toggle
expect_failure bash "$script" invalid
jq '.keyboards[0].layout="de"' "$sandbox/devices.json" > "$sandbox/next.json"
mv "$sandbox/next.json" "$sandbox/devices.json"
expect_failure bash "$script" toggle
reset_devices
echo 'PASS: incompatible layouts, missing session, invalid command and compositor errors are rejected'

for format in lua conf; do
  config=$XDG_CONFIG_HOME/hypr/input.$format
  touch "$XDG_CONFIG_HOME/hypr/hyprland.$format"
  printf '%s\n' '# personal settings preserved by the mock' > "$config"
  cp "$config" "$sandbox/original"
  bash "$script" install >/dev/null
  test -x "$HOME/.local/bin/omarchy-keyboard"
  cp "$config" "$sandbox/first-install"
  bash "$HOME/.local/bin/omarchy-keyboard" install >/dev/null
  cmp "$sandbox/first-install" "$config"
  test "$(grep -c 'BEGIN omarchy-keyboard-switch' "$config")" -eq 1
  test "$(find "$XDG_CONFIG_HOME/hypr" -name "input.$format.backup.*" | wc -l)" -ge 2
  bash "$script" uninstall >/dev/null
  cmp "$sandbox/original" "$config"
  test ! -e "$HOME/.local/bin/omarchy-keyboard"
  rm "$XDG_CONFIG_HOME/hypr/hyprland.$format"
done
echo 'PASS: Lua and legacy install/reinstall/uninstall preserve personal settings and backups'

reset_devices_virtual
touch "$XDG_CONFIG_HOME/hypr/hyprland.lua"
printf '%s\n' '# personal settings preserved by the mock' > "$XDG_CONFIG_HOME/hypr/input.lua"
bash "$script" install >/dev/null
grep -q 'kb_layout = "us,fr"' "$XDG_CONFIG_HOME/hypr/input.lua"
bash "$script" uninstall >/dev/null
rm "$XDG_CONFIG_HOME/hypr/hyprland.lua"
echo 'PASS: install succeeds with an input method virtual keyboard present'

touch "$XDG_CONFIG_HOME/hypr/hyprland.lua" "$XDG_CONFIG_HOME/hypr/hyprland.conf"
expect_failure bash "$script" install
rm "$XDG_CONFIG_HOME/hypr/hyprland.conf"
config=$XDG_CONFIG_HOME/hypr/input.lua
cp "$config" "$sandbox/original"
rm -f "$sandbox/reloaded"
touch "$sandbox/config-error"
expect_failure bash "$script" install
cmp "$sandbox/original" "$config"
rm "$sandbox/config-error"
touch "$sandbox/reload-error"
expect_failure bash "$script" install
cmp "$sandbox/original" "$config"
rm "$sandbox/reload-error"
printf '%s\n' '-- BEGIN omarchy-keyboard-switch' >> "$config"
cp "$config" "$sandbox/broken"
expect_failure bash "$script" install
cmp "$sandbox/broken" "$config"
echo 'PASS: ambiguous formats and damaged markers are rejected; failed reload/configuration restores backup'
echo 'All tests passed (mock Hyprland; no real keyboard changes).'
