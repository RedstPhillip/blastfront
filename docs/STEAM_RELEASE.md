# Blastfront – Steam release checklist

What the repository already does for a Steam release, and what still has to happen outside of it
(Steamworks partner site, store page, legal). Nothing in the second half is done by the code; do not
tick it off because the build runs.

## In the build

| Area | State |
| --- | --- |
| Steam start-up | `autoload/steam_service.gd` initialises GodotSteam 4.18 with app id `GameSettings.STEAM_APP_ID` (4714540); the game runs offline when Steam is missing. |
| Online play | Steam lobbies, invites (`+connect_lobby`) and P2P networking in `autoload/network_session.gd`. |
| Achievements and stats | Reported from `SteamService.report_match_result()` when a match ends (bot or online). The API names have to be created in Steamworks, see below. |
| Rich presence | `SteamService.set_presence(text)` sets the `status` key: "Menu", "Sandbox · <world>", "Versus bot · <world>", "Online duel · <world>". |
| Settings | Audio, video (windowed / borderless / exclusive, resolution, vsync, FPS cap, post-processing, flashes), gameplay (shake, particle detail, hit-stop, damage numbers) and rebindable keyboard and pad controls, stored in `user://settings.cfg`. |
| Display | 16:9, 16:10 and Steam Deck fill the screen (`keep_width` stretch); ultrawide gets side bars. |
| Controller | Full pad navigation in menus and play; prompts follow the device in use. |
| Icon and splash | `icon.svg` and `assets/ui/boot_splash.png` (the Godot defaults are gone). |
| Export presets | `Windows Desktop` and `Linux` (x86_64), tools excluded, version 1.0.0.0. |
| Licences | `CREDITS.md` lists fonts (OFL), Kenney sounds (CC0), Godot and GodotSteam (MIT). |

### Weather and particle detail

Rain (Tidewater) and snowfall (Rimefall) follow the existing *Particle detail* setting: Off removes them,
the steps in between thin them out. The sea's refraction needs one screen copy per frame while water is
on screen; there is no separate switch for it.

## To do in Steamworks (cannot be done from the repository)

### Achievements

Create these under *Stats & Achievements* with exactly these API names, then publish the change.

| API name | Unlocks when | Suggested name |
| --- | --- | --- |
| `ACH_FIRST_WIN` | first match won (bot or online) | First Blood |
| `ACH_BEAT_HARD` | match won against the Hard bot | Hard Target |
| `ACH_FLAWLESS` | match won without conceding a point (bot) or a set (online) | Untouched |
| `ACH_ONLINE_WIN` | online match won | Duelist |
| `ACH_WIN_VERDANT` | match won on Verdant | Ridge Runner |
| `ACH_WIN_MARS` | match won on Mars | Dust Devil |
| `ACH_WIN_TIDEWATER` | match won on Tidewater | High Water |
| `ACH_WIN_RIMEFALL` | match won on Rimefall | Glare Ice |
| `ACH_ALL_WORLDS` | all four world achievements | World Tour |

Each needs a 256x256 unlocked and locked icon (JPG). None exist yet.

### Stats

Integer stats, *Client* may set them: `STAT_MATCHES_PLAYED`, `STAT_MATCHES_WON`, `STAT_ONLINE_WINS`.

### Steam Cloud

Auto-Cloud is enough, no code needed. Root *WinAppDataRoaming*, subdirectory
`Godot/app_userdata/Blastfront`, pattern `settings.cfg`; on Linux root *LinuxHome*, subdirectory
`.local/share/godot/app_userdata/Blastfront`. If you would rather not have "Godot" in the save path, set
`application/config/use_custom_user_dir` before launch (after launch it would orphan players' settings).
Research, loadouts and coins are per match by design, so there is no progress file to sync.

### Depots and builds

- Install the Godot 4.6.1 export templates, export both presets (`builds/` is git-ignored).
- Windows depot: `blastfront.exe`, `blastfront.pck`, `steam_api64.dll`, the GodotSteam library next to the
  exe, `CREDITS.md`. Linux depot: `blastfront.x86_64`, `blastfront.pck`, `libsteam_api.so`,
  `libgodotsteam*.so`, `CREDITS.md`.
- Do not ship `steam_appid.txt` (already git-ignored); the Steam client supplies the id.
- Launch options: one per OS; tick *Steam Deck* compatibility after a test on a Deck.
- macOS: no export preset yet. GodotSteam ships a macOS library (`addons/godotsteam/osx`), but a Mac build
  needs a bundle identifier, signing and notarisation with an Apple developer account.
- Upload with SteamPipe (`steamcmd` + `app_build` script) and set the build live on a beta branch first.

### Store page and release

- Capsules (header 920x430, small 462x174, main 1232x706, vertical 748x896), library assets (600x900,
  3840x1240 hero, logo), at least five 1920x1080 screenshots, a trailer.
- Short and long description, tags, supported languages (the game is English only), system requirements
  (measured target: Radeon iGPU laptop, 1920x1200 at 60 fps).
- Controller support declaration ("Full"), Steam Input configuration (the game reads standard gamepads;
  no Steam Input action set is defined).
- Age rating questionnaire, pricing (planned EUR 19.99), release date, review by Valve (allow 3-5 working
  days for store page and build review each).
- Company and legal lines: `application/company_name` and `application/copyright` in `export_presets.cfg`
  are empty on purpose until the publishing entity is decided; fill them before the release export. EULA
  and privacy policy if you want anything beyond Steam's defaults.

## Before pressing the button

```bash
bash tools/testing/regress.sh
```

```bash
bash tools/testing/release_boot.sh
```

The first must print `OK` for every scenario, the second exports a Windows release build and times its
start. Then play one online match between two Steam accounts on the exported build: lobby, invite, a full
set on each world (the tide and its weather must match on both sides), a disconnect.
