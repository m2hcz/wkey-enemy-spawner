# Submission Notes

## Approach

I built the enemy system around an authoritative server simulation with client-side visual rendering. The server stores each enemy as data: ID, position, yaw, random visual attributes, speed, and simple behavior state. It updates that state at a fixed simulation rate and sends compact snapshots to clients at 10 Hz.

Clients do not receive moving server-owned enemy Parts. Instead, each client creates anchored local enemy visuals from the server's spawn payload and interpolates between snapshot positions. This keeps replication cost focused on small RemoteEvent payloads instead of default physics/property replication.

Client-to-server RemoteEvent actions are rate-limited per player/action and payloads are validated before they mutate shared state. This prevents repeated sync requests, config spam, kill-all spam, and invalid enemy click reports from doing unnecessary server work.

## Why This Approach

The assignment specifically calls out network `Recv` and encourages custom replication. Because of that, I avoided using server-replicated moving models for enemies. The server remains authoritative for gameplay decisions, while the client handles presentation.

Random enemy attributes are generated once on the server and sent to every client, so the same enemy ID always has the same color, material, size, and speed for everyone.

## Requirement Coverage

- 50x50 stud platform is created by the server.
- Default spawn rate is 1 enemy per second.
- Default enemy cap is 20.
- Spawn rate and cap are adjustable through UI.
- `Kill All` UI button clears enemies.
- Enemies chase the closest player who is standing on the platform.
- Players outside the platform are ignored.
- Enemies wander when no target is available.
- Enemies print/action-flash when close to a player.
- Every enemy has a stable ID.
- Clicking an enemy prints the ID on the client and server.
- Movement is replicated through compact snapshots instead of default moving Part replication.
- Client remote actions are rate-limited and server-validated.

## Ideas Considered

I considered using regular Roblox NPC models with Humanoids, but that would introduce unnecessary physics, character replication, and pathfinding overhead for this assignment.

I also considered creating server-owned Parts and tweening them, but that would still replicate frequent property changes. The final approach keeps server gameplay simple and moves visual smoothing to the client.
