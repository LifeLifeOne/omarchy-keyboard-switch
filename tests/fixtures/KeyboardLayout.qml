// Extrait fidele de /usr/share/omarchy/shell/plugins/bar/widgets/KeyboardLayout.qml
// au moment ou le correctif du clic a ete ecrit. Sert de fixture aux tests :
// le script ne doit reconnaitre que ces deux lignes et rien d'autre.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Ui
import qs.Commons
import "KeyboardLayoutModel.js" as KeyboardLayoutModel

Item {
  id: root

  // switchxkblayout is a hyprctl command rather than a dispatcher, so it has to
  // be run for the keyboard this widget is tracking.
  function cycleLayout() {
    if (!root.keyboardName || !root.bar) return
    root.bar.run("hyprctl switchxkblayout " + Util.shellQuote(root.keyboardName) + " next")
  }
}
