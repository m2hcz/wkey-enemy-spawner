# WKEY Enemy Spawner

Take-home assignment project for a performant Roblox enemy spawner built with Rojo and Luau.

## What It Does

- Creates a 50x50 stud platform at runtime.
- Spawns 1 enemy per second by default.
- Stops spawning at 20 enemies by default.
- Lets the player change spawn rate and max enemies through UI.
- Lets the player kill all enemies through UI.
- Gives every enemy a stable unique ID.
- Gives every enemy server-generated random visual traits, shared with every client.
- Makes enemies chase the closest player standing on the platform.
- Ignores players outside the platform.
- Prints an enemy action when an enemy reaches a player.
- Prints clicked enemy IDs on both client and server.

## Technical Approach

The server owns the authoritative enemy list and simulates enemy movement as plain Luau data, not as moving replicated Parts. Clients create local visual enemies from server spawn payloads and interpolate low-frequency, quantized position snapshots.

This keeps Roblox's default physics replication out of the hot path. The server only sends compact enemy state snapshots at 10 Hz, while clients render smooth movement locally.

Enemy randomization is generated once on the server and included in the spawn/sync payload, so all clients see the same ID, color, material, size, and movement speed for each enemy.

## Running

Install Rojo, then run:

```powershell
rojo serve
```

Open Roblox Studio, connect the Rojo plugin, and play-test.

To build a place file:

```powershell
New-Item -ItemType Directory -Force build
rojo build default.project.json -o build/WKEYEnemySpawner.rbxlx
```

## Controls

- Use the top-left UI to adjust spawn rate and enemy cap.
- Press `Kill All` to remove all current enemies.
- Click any enemy to print its ID on the client and server.

## Commit History Shape

This repository is intentionally committed in small increments:

1. Rojo project scaffold.
2. Arena platform and spawn controller.
3. Server-authored enemy IDs and random variants.
4. Platform chasing, idle wandering, and proximity action.
5. Compact snapshot replication.
6. Client-side visual enemies and interpolation.
7. UI controls for spawn settings and kill all.
8. Click reporting for enemy IDs.
9. Documentation and submission explanation.

That mirrors the assignment requirements and keeps the implementation reviewable.
