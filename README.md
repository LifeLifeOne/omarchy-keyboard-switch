# Omarchy Keyboard Switch

Basculer entre **QWERTY US International** et **AZERTY français** dans Omarchy avec **Ctrl + Alt + Espace** ou une commande.

Pensé pour un portable AZERTY utilisé avec un clavier USB QWERTY. Le script sélectionne la même disposition sur tous les claviers : on choisit celle du clavier sur lequel on écrit.

| Commande | Résultat |
| --- | --- |
| `omarchy-keyboard toggle` | Bascule vers l’autre disposition |
| `omarchy-keyboard qwerty` | US International avec touches mortes (`us`, variante `intl`) |
| `omarchy-keyboard azerty` | Français AZERTY classique (`fr`, variante vide) |
| `omarchy-keyboard status` | Affiche l’état de chaque clavier |

La disposition US International correspond à l’usage « FRA INTL » de Windows : QWERTY avec composition des accents. Les combinaisons exactes de certains caractères peuvent différer entre Windows et Linux. Ce n’est pas la variante `altgr-intl`.

## Installation sur Omarchy

Dans un terminal de ta **session graphique Omarchy**, sans `sudo` :

```sh
git clone https://github.com/LifeLifeOne/omarchy-keyboard-switch.git
cd omarchy-keyboard-switch
bash omarchy-keyboard.sh install
```

Ensuite, utilise **Ctrl + Alt + Espace**. Si `~/.local/bin` n’est pas dans ton `PATH`, les commandes restent accessibles par leur chemin complet :

```sh
~/.local/bin/omarchy-keyboard qwerty
~/.local/bin/omarchy-keyboard azerty
```

Prérequis : Bash, `hyprctl`, `jq` et les outils GNU usuels (`awk`, `grep`, `install`, `mktemp`). La notification utilise `notify-send` si disponible. Si `jq` manque, installe-le avec `sudo pacman -S jq`.

## Ce qui est modifié

- Copie du script dans `~/.local/bin/omarchy-keyboard`.
- Sauvegarde de `~/.config/hypr/input.lua` ou `input.conf` avant chaque modification ; son chemin est affiché.
- Ajout d’un bloc clairement délimité en fin de fichier : dispositions `us,fr`, variantes `intl,`, raccourci Ctrl+Alt+Espace.
- Rechargement de Hyprland et sélection initiale de QWERTY US International.

En Lua, le raccourci est enregistré avec la description `Toggle keyboard layout`, visible dans `hyprctl binds`.

Les autres réglages du fichier sont conservés, notamment la souris, le pavé tactile et les options Compose. Relancer `install` remplace le bloc géré au lieu de le dupliquer. `XDG_CONFIG_HOME` est respecté. Aucune modification du clavier Windows, du clavier de console Linux ni de l’écran de connexion SDDM.

La configuration Lua est détectée via `hyprland.lua`, l’ancienne syntaxe via `hyprland.conf`. Si les deux existent, indique le format réellement utilisé :

```sh
bash omarchy-keyboard.sh install lua
# ou, pour une ancienne installation :
bash omarchy-keyboard.sh install conf
```

L’installateur suppose la structure standard d’Omarchy, qui charge le fichier `input` personnel après les réglages par défaut. Un fichier non chargé ou un override clavier défini ailleurs peut empêcher l’application ; le script signale les dispositions inattendues.

## Comportement et limites

- La bascule s’appuie sur l’état réel du clavier principal retourné par Hyprland, puis synchronise tous les claviers. Aucun fichier d’état susceptible de se désynchroniser.
- Les claviers virtuels créés par un moteur de saisie (fcitx5, ibus,…) sont ignorés pour la vérification des dispositions et pour le sens de la bascule. Hyprland les liste parmi les claviers, mais ils déclarent leur propre disposition et sont souvent marqués « principal » : sans cette exclusion, l’installation échoue et la bascule peut rester bloquée sur le même sens. `status` les signale avec `[virtuel]`.
- Au redémarrage de la session ou au rechargement de la configuration, la disposition par défaut est QWERTY US International. La dernière sélection n’est pas mémorisée.
- Un clavier branché après une bascule peut démarrer avec la disposition par défaut : relance `qwerty` ou `azerty` pour synchroniser les claviers.
- Les raccourcis Hyprland sont résolus par défaut selon la première disposition (`us`). Certains raccourcis avec des lettres peuvent donc suivre la position QWERTY même en AZERTY. Le raccourci fourni utilise Espace pour éviter cette ambiguïté.
- Les réglages distincts par périphérique (AZERTY permanent sur le portable, QWERTY permanent sur l’USB) constituent une autre approche. Ce script est destiné à une **bascule globale manuelle** et refuse les configurations par périphérique incompatibles.
- Réservé à Hyprland : pas à GNOME, KDE, X11 ni à Windows. L’API JSON doit exposer `active_layout_index` (vérifiée dans le code Hyprland 0.55).
- Dans Try Omarchy pour Windows, le lanceur peut resynchroniser la disposition depuis Windows. Le projet vise d’abord une installation native d’Omarchy.

## Désinstallation

```sh
omarchy-keyboard uninstall
```

Cela retire seulement le bloc géré et la copie installée du script. Les autres réglages, le dépôt cloné et les sauvegardes restent en place. Si les deux formats de configuration existent, ajoute `lua` ou `conf`.

Pour revenir exactement au fichier d’avant installation, copie la sauvegarde affichée sur le fichier `input` correspondant, puis exécute `hyprctl reload`. Attention : une restauration complète remplace aussi tes modifications ultérieures.

## Validation

```sh
bash -n omarchy-keyboard.sh
bash tests/test.sh
```

Les tests utilisent un faux `hyprctl` et un dossier temporaire : installation/réinstallation, préservation des réglages, désinstallation, synchronisation des deux claviers, erreurs et restauration. Ils ne changent pas le clavier de la machine de test. Le comportement sur un vrai bureau Hyprland doit être vérifié sur Omarchy ; il n’a pas été testé matériellement depuis Windows.

## Références

- [Claviers et variantes Hyprland](https://wiki.hypr.land/configuring/core/binds/keyboard-layouts/)
- [Commandes hyprctl](https://wiki.hypr.land/0.55.0/Configuring/Advanced-and-Cool/Using-hyprctl/)
- [Fichier input.lua officiel d’Omarchy](https://github.com/omacom/omarchy/blob/master/config/hypr/input.lua)
- [Configuration personnelle Omarchy](https://omarchy.org/manual/dotfiles/)

Projet indépendant, sans affiliation officielle à Omarchy ou Hyprland.
