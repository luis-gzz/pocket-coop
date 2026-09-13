# Pocket Chicken

A Solar2D (Corona) tamagotchi-style game where the player cares for one or more chickens.

## Language

**Camera**:
The visible play area, sized to exactly match the device's screen. It never scrolls or follows anything — what's on screen is the entire game world.
_Avoid_: Viewport, screen (screen is ambiguous between device pixels and camera content points)

**Island**:
The tiled rectangular play space, with its own visible bordered edge (cliff/dirt tiles). Deliberately smaller than the camera and positioned within it — the two are no longer the same thing.
_Avoid_: World, map, level

**Backdrop**:
The flat-colored area of the camera outside the island. Purely atmospheric — nothing is placed or interacts there.
_Avoid_: Background, void

**Tile**:
A fixed-size square unit of the island's ground, repeated edge-to-edge with no gaps to cover the island exactly.

**Play area**:
The region within the island where the chicken is allowed to move — the island's tile rectangle inset by one tile from its outer edge, so the chicken never overlaps the border tiles.

**Chicken**:
The player's pet, driven by a finite state machine. Stays within the play area's bounds at all times.

**State** (chicken):
One mode of chicken behavior — currently idle, eat, or wander — each with its own animation. The chicken is always in exactly one state.

**Dwell time**:
How long a chicken remains in a timer-based state (idle, eat) before transitioning to the next state. Randomized per state to avoid a robotic cadence.
_Avoid_: Duration, timer

**Wander destination**:
A random point near the chicken, within the play area's bounds, chosen when a chicken enters the wander state. Wander ends when the chicken arrives there — not on a timer, unlike other states.

**Wiggle**:
The feedback animation a chicken plays immediately after being dropped by the player. Pauses the chicken's state cycling until it completes.
