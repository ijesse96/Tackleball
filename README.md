# Tackle Ball

Roblox game synced with [Rojo](https://rojo.space/docs/v7/) 7.

## Places

| Place | Place ID | Rojo port | Rojo project | Build output |
|-------|----------|-----------|--------------|--------------|
| Main Menu | [73490771045679](https://www.roblox.com/games/73490771045679) | `34872` | `default.project.json` | `Main Menu.rbxlx` |
| TackleBall Arena Solo | [95975589855069](https://www.roblox.com/games/95975589855069) | `34873` | `tackleball-arena-solo.project.json` | `TackleBall Arena Solo.rbxlx` |
| TackleBall Arena Teams | [79166542960911](https://www.roblox.com/games/79166542960911) | `34874` | `tackleball-arena-teams.project.json` | `TackleBall Arena Teams.rbxlx` |

All places share the same `src/` scripts. Game mode is determined by which arena place is running (solo vs teams).

Both arena Rojo projects set `StarterPlayer.AvatarJointUpgrade` to `Disabled` so characters spawn with classic `Motor6D` joints (needed for tackle ragdoll). If tackles feel stiff in Teams, sync Rojo, confirm that property on `StarterPlayer`, stop play, and test again so characters respawn with the correct rig.

## Arena player count

In Creator Hub, set both arena places **MaxPlayers** to **12** (matches `RECOMMENDED_MAX_PLAYERS` in `Config.luau`). Solo and Teams arenas start immediately with NPC backfill from 1 player.

## Project layout

| Folder | Roblox location |
|--------|-----------------|
| `src/server` | ServerScriptService → Server |
| `src/client` | StarterPlayer → StarterPlayerScripts → Client |
| `src/shared` | ReplicatedStorage → Shared |

## One-time setup

### 1. Rojo CLI

You already have Rojo installed (`rojo --version`).

### 2. Rojo plugin in Roblox Studio

Install the official plugin once:

```bash
rojo plugin install
```

Or get **Rojo** from the [Creator Store](https://create.roblox.com/marketplace/asset/13916111003/Rojo) in Studio.

### 3. Open the project in your editor

Open this folder (`Tackleball`) in Cursor or VS Code so you can edit `.luau` files.

## Connect Studio (live sync)

1. In a terminal, from this folder, start the server for the place you are editing:

   ```bash
   cd ~/Desktop/TackleBall

   # Main Menu (port 34872)
   rojo serve

   # TackleBall Arena Solo (port 34873)
   rojo serve tackleball-arena-solo.project.json

   # TackleBall Arena Teams (port 34874)
   rojo serve tackleball-arena-teams.project.json
   ```

   You can run all three at the same time in separate terminals — each place uses its own port.

2. In Roblox Studio, open the matching place from Creator Hub.
3. Open the **Rojo** plugin → **Connect** (use the port shown in the terminal for that place).
4. Edit files under `src/` — changes sync into Studio while `rojo serve` is running.

## Build a place file (optional)

To generate a `.rbxlx` you can open without the server:

```bash
rojo build -o "Main Menu.rbxlx"
rojo build tackleball-arena-solo.project.json -o "TackleBall Arena Solo.rbxlx"
rojo build tackleball-arena-teams.project.json -o "TackleBall Arena Teams.rbxlx"
```

Then double-click the `.rbxlx` to open it in Studio.

## Docs

- [Rojo — syncing with Studio](https://rojo.space/docs/v7/sync-details/)
- [Luau](https://luau-lang.org/)
