# Blastfront – Third-Party Credits

All third-party assets bundled with Blastfront are licensed for commercial redistribution.

## Fonts (SIL Open Font License 1.1)

| Font | Author | Location |
| --- | --- | --- |
| Russo One | Jovanny Lemonad | `assets/fonts/russo_one/` (license: `OFL.txt`) |
| Chakra Petch | Cadson Demak | `assets/fonts/chakra_petch/` (license: `OFL.txt`) |

## Sound effects (Creative Commons Zero, CC0 1.0)

Created by Kenney (www.kenney.nl):

- Impact Sounds – footsteps, punches, impacts, casings, glass, metal
- Sci-Fi Sounds – shield/force field, explosions, low-frequency booms, slime
- Interface Sounds – all menu/UI sounds
- Digital Audio – zaps, power-ups, phase jumps, countdown tones
- RPG Audio – reload mechanics, coins
- Music Jingles – round and match stingers

Files live in `assets/audio/sfx/`, `assets/audio/ui/` and `assets/audio/stingers/`.

## Procedurally generated audio

Music and ambience in `assets/audio/music/` were synthesized specifically for Blastfront.
The same goes for the rain, thunder, tide and weapon sounds rendered by `tools/music/render_sfx.py`.

## Engine and middleware (MIT License)

| Component | Copyright | License text |
| --- | --- | --- |
| Godot Engine | Juan Linietsky, Ariel Manzur and the Godot Engine contributors | https://godotengine.org/license |
| GodotSteam | GP Garcia, Chris Ridenour and contributors | `addons/godotsteam/license.md` |

Godot's license asks for its copyright notice and license text to ship with the game: put this file (and
the texts it points to) in the Steam depot next to the executable. The engine's own third-party notices
are listed at https://docs.godotengine.org/en/stable/about/complying_with_licenses.html.

Steamworks SDK binaries (`steam_api64.dll`, `libsteam_api.so`) are redistributed under the Steamworks SDK
Access Agreement.
