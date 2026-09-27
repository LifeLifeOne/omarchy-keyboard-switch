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
cat > "$sandbox/bin/omarchy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
clone_id="${USER:-$(id -un)}.keyboard-layout"
dir="$XDG_CONFIG_HOME/omarchy/plugins/$clone_id"
case "$*" in
  'plugin clone omarchy.keyboard-layout')
    printf 'clone\n' >> "$MOCK_ROOT/omarchy-calls"
    [[ -f $MOCK_ROOT/clone-error ]] && exit 1
    mkdir -p "$dir"
    cp "$MOCK_ROOT/fixture.qml" "$dir/KeyboardLayout.qml"
    printf 'stub\n' > "$dir/KeyboardLayoutModel.js"
    printf '{"schemaVersion":1,"id":"%s","kinds":["bar-widget"],"entryPoints":{"barWidget":"KeyboardLayout.qml"},"omarchy":{"clonedFrom":"omarchy.keyboard-layout"}}\n' "$clone_id" > "$dir/manifest.json"
    ;;
  'restart shell') printf 'restart\n' >> "$MOCK_ROOT/omarchy-calls" ;;
  "plugin remove $clone_id --yes")
    printf 'remove\n' >> "$MOCK_ROOT/omarchy-calls"
    rm -rf "$dir"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$sandbox/bin/"*
cp "$root/tests/fixtures/KeyboardLayout.qml" "$sandbox/fixture.qml"
# The suite drives the real omarchy binary unless the mock shadows it, and the
# real one talks to the running shell. Refuse to start rather than risk it.
if [[ $(command -v omarchy || true) != "$sandbox/bin/omarchy" ]]; then
  echo "Refusing to run: omarchy resolves to '$(command -v omarchy || true)', not the mock" >&2
  exit 1
fi
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

# --- bar widget -------------------------------------------------------------
# The built-in widget cycles a single named keyboard, which never settles when
# several are attached. install clones it, patches the click to cycle the seat,
# and marks the clone so uninstall can give the packaged widget back.
clone_id="${USER:-$(id -un)}.keyboard-layout"
clone_dir="$XDG_CONFIG_HOME/omarchy/plugins/$clone_id"
qml="$clone_dir/KeyboardLayout.qml"
marker="$clone_dir/.omarchy-keyboard-switch"

reset_devices
touch "$XDG_CONFIG_HOME/hypr/hyprland.lua"
# The damaged-marker test above leaves input.lua with a duplicated block, which
# install rightly refuses. Start the widget tests from a clean personal file.
printf '%s\n' '# personal settings preserved by the mock' > "$XDG_CONFIG_HOME/hypr/input.lua"
rm -rf "$clone_dir"
rm -f "$sandbox/omarchy-calls"

bash "$script" install > "$sandbox/install-output" 2>&1
grep -q 'switchxkblayout all next' "$qml"
! grep -q 'root\.keyboardName) + " next"' "$qml"
grep -q 'if (!root.bar) return' "$qml"
test -f "$marker"
test "$(grep -c '^clone$' "$sandbox/omarchy-calls")" -eq 1
grep -q '^restart$' "$sandbox/omarchy-calls"
echo 'PASS: install clones the widget and makes its click cycle every keyboard'

# A second install must not clone again, otherwise a user re-running install
# would keep overwriting a widget they had started to edit.
bash "$script" install >/dev/null 2>&1
test "$(grep -c '^clone$' "$sandbox/omarchy-calls")" -eq 1
grep -q 'switchxkblayout all next' "$qml"
echo 'PASS: reinstalling does not re-clone an existing widget'

bash "$script" uninstall >/dev/null 2>&1
test ! -e "$clone_dir"
test "$(grep -c '^remove$' "$sandbox/omarchy-calls")" -eq 1
echo 'PASS: uninstall removes the marked clone and hands the packaged widget back'

# A clone the user made for their own reasons is not ours to delete.
bash "$script" install >/dev/null 2>&1
rm -f "$marker"
bash "$script" uninstall >/dev/null 2>&1
test -f "$qml"
! grep -q '^remove$' "$sandbox/omarchy-calls"
rm -rf "$clone_dir"
echo 'PASS: uninstall leaves an unmarked hand-made clone alone'

touch "$sandbox/clone-error"
bash "$script" install > "$sandbox/install-output" 2>&1
grep -q 'le clone a echoue' "$sandbox/install-output"
grep -q 'omarchy restart shell' "$sandbox/install-output"
test -x "$HOME/.local/bin/omarchy-keyboard"
rm -f "$sandbox/clone-error"
rm -rf "$clone_dir"
echo 'PASS: a failed clone warns with a recovery hint and leaves the shortcut installed'

# If Omarchy renames or rewrites the click, the patch cannot apply. The
# keyboard still works through the shortcut, so warn and carry on.
bash "$script" install >/dev/null 2>&1
rm -f "$marker" "$sandbox/omarchy-calls"
printf '// upstream rewrote the widget\nItem { function cycleLayout() {} }\n' > "$qml"
bash "$script" install > "$sandbox/install-output" 2>&1
grep -q 'a change' "$sandbox/install-output"
test ! -f "$sandbox/omarchy-calls"
rm -rf "$clone_dir"
echo 'PASS: an upstream rewrite is reported and left to the user instead of failing install'

# On a desktop without omarchy the widget step has nothing to talk to. Removing
# the mock from PATH is not enough: the real binary would still be found and
# would drive the running shell. Build a PATH with no omarchy at all instead.
shim=$sandbox/shim
mkdir -p "$shim"
IFS=: read -r -a path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
  [[ -d $dir ]] || continue
  for entry in "$dir"/*; do
    [[ -f $entry && -x $entry ]] || continue
    name=${entry##*/}
    [[ $name == omarchy || -e $shim/$name ]] && continue
    ln -s "$entry" "$shim/$name" 2>/dev/null || true
  done
done
PATH=$shim bash "$script" install > "$sandbox/install-output" 2>&1
grep -q 'omarchy est absent' "$sandbox/install-output"
test ! -e "$clone_dir"
echo 'PASS: install completes without the widget step when omarchy is unavailable'

# The patterns are pinned to the real packaged widget whenever it is present.
upstream=/usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayout.qml
if [[ -f $upstream ]]; then
  mkdir -p "$clone_dir"
  cp "$upstream" "$qml"
  rm -f "$marker"
  bash "$script" install > "$sandbox/install-output" 2>&1
  grep -q 'switchxkblayout all next' "$qml"
  ! grep -q 'root\.keyboardName) + " next"' "$qml"
  echo 'PASS: the patch applies to the widget Omarchy actually ships'
else
  echo 'SKIP: packaged widget not available on this machine'
fi
rm -rf "$clone_dir"
bash "$script" uninstall >/dev/null 2>&1

echo 'All tests passed (mock Hyprland and Omarchy; no real keyboard changes).'
