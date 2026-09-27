# Omarchy Keyboard Switch

![tests](https://github.com/LifeLifeOne/omarchy-keyboard-switch/actions/workflows/tests.yml/badge.svg)

Bascule entre **QWERTY US International** et **AZERTY français** dans Omarchy, avec **Ctrl + Alt + Espace**.

Fait pour un portable AZERTY utilisé avec un clavier USB QWERTY : la bascule s'applique à **tous** les claviers en même temps. On choisit donc la disposition du clavier sur lequel on écrit, et l'autre suit.

| Commande | Effet |
| --- | --- |
| `omarchy-keyboard toggle` | Bascule vers l'autre disposition |
| `omarchy-keyboard qwerty` | US International avec touches mortes |
| `omarchy-keyboard azerty` | Français AZERTY classique |
| `omarchy-keyboard status` | Affiche la disposition de chaque clavier |

US International correspond au réglage « FRA INTL » de Windows : QWERTY avec composition des accents. Quelques combinaisons peuvent différer de Windows, et ce n'est pas la variante `altgr-intl`.

## Installation

Dans un terminal de ta session Omarchy, **sans `sudo`** :

```sh
git clone https://github.com/LifeLifeOne/omarchy-keyboard-switch.git
cd omarchy-keyboard-switch
bash omarchy-keyboard.sh install
```

C'est tout. **Ctrl + Alt + Espace** fonctionne, et la pastille de la barre est cliquable.

Si `~/.local/bin` n'est pas dans ton `PATH`, les commandes restent accessibles ainsi :

```sh
~/.local/bin/omarchy-keyboard azerty
```

Il faut Bash, `hyprctl`, `jq` et les outils GNU habituels (`awk`, `grep`, `install`, `mktemp`). Sur Arch, `jq` s'installe avec `sudo pacman -S jq`.

## Ce que fait l'installateur

- Copie le script dans `~/.local/bin/omarchy-keyboard`.
- **Sauvegarde** `~/.config/hypr/input.lua` (ou `input.conf`) et affiche le chemin de la sauvegarde.
- Ajoute un bloc délimité en fin de fichier : dispositions `us,fr`, variante `intl,`, raccourci Ctrl+Alt+Espace.
- Recharge Hyprland et sélectionne QWERTY US International.
- Corrige le clic de la pastille dans la barre (voir plus bas).

Le reste de ton fichier de configuration est conservé : souris, pavé tactile, options Compose. Relancer `install` remplace le bloc au lieu de le dupliquer. `XDG_CONFIG_HOME` est respecté.

Le clavier Windows, le clavier de la console Linux et l'écran de connexion SDDM ne sont pas touchés.

Si tu as les deux formats de configuration, précise lequel est réellement utilisé :

```sh
bash omarchy-keyboard.sh install lua   # format actuel
bash omarchy-keyboard.sh install conf  # ancien format
```

## La pastille dans la barre

**Le clic de la pastille ne marche pas d'origine avec plusieurs claviers.** C'est un défaut d'Omarchy, pas de ce script.

Le widget livré d'Omarchy demande à Hyprland de changer la disposition d'**un** clavier précis. Problème : avec plusieurs claviers, il ne sait pas lequel choisir. Il se fie au dernier périphérique qu'il a entendu, ce qui peut être un bouton de power ou un pseudo-périphérique, pas ton clavier. Le clic bouge alors un clavier invisible — et comme tous les claviers affichent la même disposition, rien ne semble se passer.

`install` corrige cela : il copie le widget dans ta config et le modifie pour basculer **tous** les claviers, exactement comme le raccourci. Le libellé reste juste, puisque les claviers sont synchronisés.

À savoir :

- Le fichier d'Omarchy dans `/usr/share/omarchy` n'est **jamais** modifié.
- Relancer `install` n'écrase pas un widget que tu aurais commencé à éditer.
- `uninstall` retire le clone et réactive le widget d'Omarchy. Omarchy le met de côté au lieu de l'effacer. Un clone que tu n'as jamais fait corriger est laissé intact.
- Si une mise à jour d'Omarchy réécrit ce clic, le correctif ne s'applique plus. `install` te le signale sans échouer : le raccourci, lui, continue de fonctionner.

## À savoir

- **Après un redémarrage de session**, la disposition repart sur QWERTY US International. La dernière choice n'est pas mémorisée.
- **Un clavier branché après une bascule** peut démarrer sur la disposition par défaut. Relance `omarchy-keyboard azerty` pour resynchroniser.
- **Les raccourcis avec des lettres** suivent la position QWERTY même en AZERTY, car Hyprland résout les raccourcis selon la première disposition. C'est pour ça que le raccourci utilise Espace, qui n'est pas ambigu.
- **Les méthodes de saisie** (fcitx5, ibus) créent un clavier virtuel que Hyprland liste comme un vrai clavier. Il est ignoré, sinon l'installation échouerait et la bascule resterait bloquée dans le même sens. `status` le marque `[virtuel]`.
- **Des dispositions fixes par périphérique** (AZERTY tout le temps sur le portable, QWERTY sur l'USB) sont une autre approche. Ce script fait une bascule globale manuelle et refuse les configurations par périphérique incompatibles.
- **Hyprland uniquement** : pas GNOME, KDE, X11 ni Windows.
- **Try Omarchy pour Windows** : le lanceur peut resynchroniser la disposition depuis Windows. Le projet vise d'abord une installation native.

## Désinstallation

```sh
omarchy-keyboard uninstall
```

Retire le bloc de configuration, la commande installée et le clone du widget, ce qui réactive celui d'Omarchy. Tes autres réglages, le dépôt cloné et les sauvegardes restent en place.

Pour revenir exactement au fichier d'avant installation, copie la sauvegarde affichée sur le fichier `input` concerné, puis lance `hyprctl reload`. Attention, une restauration complète écrase aussi tes modifications ultérieures.

## Validation

```sh
bash -n omarchy-keyboard.sh
bash tests/test.sh
```

La CI lance ces deux commandes à chaque push sur `main` et à chaque pull request.

Les tests utilisent de faux `hyprctl` et `omarchy` dans un dossier temporaire : installation, réinstallation, désinstallation, synchronisation des claviers, claviers virtuels, correctif de la pastille, erreurs et restauration. Ils ne touchent jamais ton clavier. La suite refuse même de démarrer si elle détecte le vrai binaire `omarchy`, qui pilote ta session en cours.

## Références

- [Claviers et variantes Hyprland](https://wiki.hypr.land/configuring/core/binds/keyboard-layouts/)
- [Commandes hyprctl](https://wiki.hypr.land/0.55.0/Configuring/Advanced-and-Cool/Using-hyprctl/)
- [Fichier input.lua officiel d'Omarchy](https://github.com/omacom/omarchy/blob/master/config/hypr/input.lua)
- [Configuration personnelle Omarchy](https://omarchy.org/manual/dotfiles/)

Projet indépendant, sans affiliation officielle à Omarchy ou Hyprland.
