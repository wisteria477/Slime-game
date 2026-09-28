# Slime Life — Bare Minimum Game v1

Native Godot life-sim prototype. This repository is completely separate from Colony Clash.

## v1 loop

- Start one furnished house.
- Build/erase floors, walls, doors and essential furniture.
- Create an adult slime with a name and color.
- Add more slimes.
- Select and move slimes around the home.
- Autonomous Hunger, Energy, Hygiene, Fun, Social and Comfort.
- Two adults can have a baby.
- Baby color/traits inherit from both parents.
- Babies grow into adults.
- No old-age death.
- Autosave + Continue.
- Pause / 1x / 2x / 3x.
- Touch camera on mobile; keyboard/mouse camera on desktop.

## iPhone testing

The repository includes an unsigned iPhone IPA build workflow. It validates and boots the real Godot project on GitHub, exports iOS, compiles the Xcode project, packages an unsigned IPA, and uploads the IPA as an Actions artifact.

For free personal iPhone testing, download the IPA artifact and sign/install it with SideStore or Sideloadly.

## Character

The first playable build uses a native procedural slime fallback so the iPhone build has no binary-asset blocker. The gameplay slot still checks for `assets/models/nim_slime_current.glb`; when the final approved model is added, it will replace the fallback without rewriting the household simulation.

## Scope lock

No jobs, town, quests, multiplayer, or unrelated systems belong in this first playable. The goal is the smallest real household loop that can be installed and tested.
