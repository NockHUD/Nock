# Attribution

Nock's own code is released under the WTFPL (see `LICENSE`). This file credits
the people and projects whose ideas, techniques and components it builds on.

## Inspiration

- **Fluffy Hunter Bars** by **fluffymoo4kra**
  (https://www.curseforge.com/wow/addons/fluffy-hunter-bars) — the idea of a
  scrolling shot-timing view with bars moving toward the shot, its
  DPS-equilibrium way of choosing a clip cutoff, and its second row for the
  melee weave window. Nock's Shot Bars (`Modules/ShotPredictor.lua`,
  `UI/Frame_ShotBars.lua`) are Nock's own implementation of those ideas — the
  timing model, the data sources and the rendering were written for Nock — not
  a copy of Fluffy's code.
- **"Weave Time Tracker"** WeakAura by **Ishri** — the A-W / W-A / T columns and
  colour steps of the weave log.
- **Grounded** by **Gello** — the press/release weave-bind idea; Nock
  reimplements it and can import a Grounded bind (no Grounded code is used).
- **rotationtools** (https://diziet559.github.io/rotationtools/) — the rotation
  notation and the reference for rotation correctness.

## Credits

- **Big Chungus** (Classic Hunter Discord) — for working out that the Steam Tonk
  transform is exited by dismissing the charmed creature (`PetDismiss`) rather
  than by cancelling the aura, which is what makes Nock's Steam Tonk guard work
  in combat. No code was taken; the mechanism is the contribution.
- Everyone named in `CHANGELOG.md` for bug reports, testing and suggestions.

## Third-party components (their own licences apply)

- **Libraries** under `Libs/` (Ace3, LibStub, CallbackHandler-1.0,
  LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0, LibCustomGlow-1.0) —
  each under the licence stated in its own file header.
- **Fonts** under `Media/` (Saira Extra Condensed, IBM Plex Sans, IBM Plex Mono)
  — SIL Open Font License 1.1, see `Media/FONTS-LICENSE.txt`.
- **Pixel icons** rasterised into `Media/PixelIcons.tga` and `Media/Icons/` —
  from the Nucleo icon set, used under its licence.
