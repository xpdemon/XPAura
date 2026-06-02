# XpAura

A lightweight World of Warcraft addon (Retail, patch 12.0 *Midnight*) that shows **glowing icons** as a visual rotation aid, driven by **combat-safe conditions**: resources (health / power, including Holy Power, Combo Points, Soul Shards…), spell availability, and rune count.

Designed around Midnight's **Secret Values**: in combat the player's health/power and aura data are "secret" (an addon can't read or compare them). XpAura never reads those values directly — it routes them through Blizzard's sanctioned APIs (`UnitPowerPercent`/`UnitHealthPercent` + `C_CurveUtil` curves, cooldown `Duration` objects) so the icons keep working **during combat**.

> 🇫🇷 Version française plus bas.

---

## Features

- **Condition-based glow** — show an icon (with an optional pulsing halo) when conditions are met:
  - **Resource threshold** — health or any power type (`< / >`, percentage or absolute value). Discrete resources (Holy Power, Combo Points…) snap cleanly between integer steps.
  - **Unit choice for health** — read **your own**, your **target's**, or your **focus'** health (e.g. glow in execute range when the target drops below 35%). Power types always read yourself.
  - **Spell availability** — *ready* (GCD-aware), *not ready*, or *charges full*. Can watch the icon's own spell or any other spell.
  - **Runes available** (Death Knight) — threshold on the number of ready runes.
- **Combine conditions** with **AND / OR** in a single rule.
- **Cooldown tracking** — icon with the cooldown sweep, or glow-when-ready / glow-when-charged.
- **Per-character rules**, scoped to **Global / class / current spec**. The rule list is grouped into collapsible **accordions** (Global + one section per spec).
- **Export / Import** rules as a shareable code (per character).
- **Movable, resizable icons** with an optional placement grid (snap supported).
- **Minimap button** (left click: config, right click: lock/unlock, drag to reposition).
- **Localization**: English (default), Français, Deutsch, Русский, 简体中文, 한국어, Español, Português (BR). Resource names use Blizzard's own localized strings.

## Installation

1. Download / clone into your AddOns folder:
   `World of Warcraft/_retail_/Interface/AddOns/XpAura`
2. Make sure the folder is named **`XpAura`** and contains `XpAura.toc`.
3. Restart the game or `/reload`.

## Usage

| Command | Action |
| --- | --- |
| `/xpaura config` | Open the configuration window |
| `/xpaura unlock` / `lock` | Unlock / lock icon placement |
| `/xpaura grid` | Toggle the placement grid |
| `/xpaura reset` | Reset positions and sizes |
| `/xpaura test` | Diagnostics |

Create a rule in the config window: pick a **rule type**, set the **icon** (spell name or ID), add **conditions** (combined with AND/OR), choose the **scope** (global / class / spec), then **Create rule**. Unlock to drag icons where you want them, then lock.

## Compatibility

- Built for **Retail 12.0.x (Midnight)**.
- No external libraries required.

---

# XpAura (Français)

Addon léger pour World of Warcraft (Retail, patch 12.0 *Midnight*) qui affiche des **icônes qui brillent (glow)** comme aide visuelle de rotation, pilotées par des **conditions compatibles combat** : ressources (vie / puissance, dont Puissance sacrée, Points de combo, Fragments d'âme…), disponibilité de sort, et nombre de runes.

Conçu pour les **valeurs secrètes** de Midnight : en combat, la vie/puissance du joueur et les auras sont « secrètes » (un addon ne peut ni les lire ni les comparer). XpAura ne lit jamais ces valeurs directement — il passe par les API officielles (`UnitPowerPercent`/`UnitHealthPercent` + courbes `C_CurveUtil`, objets `Duration` des recharges) pour que les icônes continuent de fonctionner **en plein combat**.

## Fonctionnalités

- **Glow selon conditions** — affiche une icône (avec un halo pulsant optionnel) quand les conditions sont remplies :
  - **Seuil de ressource** — vie ou n'importe quelle puissance (`< / >`, pourcentage ou valeur absolue). Les ressources discrètes (Puissance sacrée, Points de combo…) basculent nettement entre paliers.
  - **Choix de l'unité pour la vie** — lit **ta** vie, celle de ta **cible** ou de ton **focus** (ex. glow en phase d'exécution quand la cible passe sous 35 %). Les puissances lisent toujours toi-même.
  - **Disponibilité d'un sort** — *prêt* (GCD géré), *pas prêt*, ou *charges pleines*. Surveille le sort de l'icône ou un autre sort au choix.
  - **Runes disponibles** (Chevalier de la mort) — seuil sur le nombre de runes prêtes.
- **Combinaison de conditions** en **ET / OU** dans une même règle.
- **Suivi de recharge** — icône avec le balayage de cooldown, ou glow-quand-prêt / glow-quand-chargé.
- **Règles par personnage**, avec une **portée Global / classe / spé actuelle**. La liste est regroupée en **accordéons** repliables (Global + une section par spé).
- **Export / Import** des règles via un code partageable (par personnage).
- **Icônes déplaçables et redimensionnables** avec une grille de placement optionnelle (aimantation).
- **Bouton minimap** (clic gauche : config, clic droit : verrouiller/déverrouiller, glisser pour déplacer).
- **Localisation** : anglais (défaut), français, allemand, russe, chinois simplifié, coréen, espagnol, portugais (BR). Les noms de ressources utilisent les chaînes déjà localisées par Blizzard.

## Installation

1. Copier / cloner dans le dossier AddOns :
   `World of Warcraft/_retail_/Interface/AddOns/XpAura`
2. Le dossier doit s'appeler **`XpAura`** et contenir `XpAura.toc`.
3. Relancer le jeu ou faire `/reload`.

## Utilisation

| Commande | Action |
| --- | --- |
| `/xpaura config` | Ouvrir la fenêtre de configuration |
| `/xpaura unlock` / `lock` | Déverrouiller / verrouiller le placement |
| `/xpaura grid` | Afficher/masquer la grille |
| `/xpaura reset` | Réinitialiser positions et tailles |
| `/xpaura test` | Diagnostics |

Crée une règle dans la config : choisis un **type de règle**, définis l'**icône** (nom ou ID du sort), ajoute des **conditions** (combinées en ET/OU), choisis la **portée** (global / classe / spé), puis **Créer la règle**. Déverrouille pour placer les icônes, puis verrouille.

## Compatibilité

- Conçu pour **Retail 12.0.x (Midnight)**.
- Aucune bibliothèque externe requise.

## License

MIT
