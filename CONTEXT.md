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
One mode of chicken behavior — idle, approach, eat, wander, or held — each with its own animation. The chicken is always in exactly one state.

**Dwell time**:
How long a chicken remains in idle or wander before the state machine re-decides. Randomized per state to avoid a robotic cadence.
_Avoid_: Duration, timer

**Wander destination**:
A random point near the chicken, within the play area's bounds, chosen when a chicken enters the wander state. Wander ends when the chicken arrives there — not on a timer, unlike idle/wander's dwell time.

**Held**:
The state a chicken is in while the player is dragging it. Entered by touch input rather than by the state machine's own re-decide logic; exits back into a fresh re-decide (not necessarily idle) on release.

**Wiggle**:
The feedback animation a chicken plays continuously for as long as it's held. Stops and settles flat the moment it's released.

**Satiety**:
The gauge tracking how fed a chicken is (0–100, 100 is full). Falls while idle or wandering, rises while eating. Displayed to the player as "Fullness."
_Avoid_: Hunger (inverted sense — high hunger would mean *unfed*, which is the opposite convention every gauge in this game uses)

**Cleanliness**:
The gauge tracking how clean a chicken's surroundings are (0–100, 100 is clean). Doesn't drain directly — it eases toward a target set by how many droppings and floor eggs currently exist, so cleaning a dropping or collecting a floor egg raises the target and cleanliness recovers toward it over time, rather than being restored directly by the act of cleaning.

**Happiness**:
A chicken's overall well-being, computed on read from satiety, cleanliness, and any active happiness buff — never stored on its own. Weighted so that whichever of satiety/cleanliness is worse pulls the result down harder.
_Avoid_: Mood, wellbeing

**Dropping**:
An individual mess a chicken leaves on the island, spawned by the poop clock. Persists as its own object until tapped away.
_Avoid_: Poop, mess (dropping is the canonical term; use it consistently even though "poop clock" keeps the informal word for the timer's name)

**Poop clock**:
The recurring, FSM-independent timer that rolls a chance each cycle to spawn a new dropping. Odds increase the longer it's been since the last successful roll, and after the chicken has eaten recently.

**Lay clock**:
The recurring, FSM-independent timer that rolls a chance each cycle for a hen to lay an egg, mirroring the poop clock's shape exactly. Gated by a minimum happiness and a refractory period since the hen's last lay; stores that last lay as a timestamp, not a countdown, the same way the poop clock's own timing state works.

**Happiness buff**:
A flat, temporary happiness boost with an expiry. Granting one again while it's still active is a no-op — it neither extends the remaining time nor stacks a second bonus. A mealworm treat is the only source so far.
_Avoid_: Pet buff (tapping a chicken no longer grants one)

**Time scale**:
A debug-only multiplier on every gauge's rate-of-change, used to compress real time for testing (e.g. a minute of decay in one second). Never present in a real play session.

**World object**:
An entity that lives in the game world and is depth-sorted against other world objects — currently the chicken, its droppings, hen beds, eggs, and food items, with more object types expected later. The island's ground tiles and screen-space UI (the tooltip, the debug button, the egg counter, the toolbar) are not world objects — they always render in their own fixed layers, never depth-sorted.
_Avoid_: Entity, game object (too generic — use world object specifically for things that participate in depth sorting)

**Depth**:
A world object's front-to-back render order relative to other world objects: whichever is lower on screen renders in front. Depth is a world object's bottom edge, not its center — every world object type is responsible for supplying its own offset to reach it (see ADR-0006).
_Avoid_: Z-order, layer, Y-sort (Y-sort is the sorting mechanism; depth is the value it sorts by)

## Egg laying

**Hen bed**:
A placeable world object, added via the toolbar, that a laying hen's egg goes into when one is available. Holds at most one egg at a time — occupied while it does, open otherwise. Not removable once placed, but repositionable by holding and dragging it — a drop that would leave any part of it outside the play area snaps back to where it was instead.
_Avoid_: Bed, nest (hen bed is the canonical term, to stay unambiguous alongside other future toolbar items)

**Egg**:
A collectable world object produced by a hen's lay clock. Sits either in a hen bed (tidy — doesn't affect cleanliness) or on the ground as a floor egg. Tapping either kind collects it: increments the egg counter, removes the egg, and frees its bed if it had one.

**Floor egg**:
An egg that landed outside a hen bed, because every bed was occupied or none existed yet. Counted toward the cleanliness target as a dirty item, weighted the same as a dropping — collecting it removes that penalty automatically.
_Avoid_: Loose egg, ground egg

**Coop**:
The single shared owner of every placed hen bed and every active egg, plus the player's collected-egg count. Decides where a newly laid egg goes, and is where saving happens on a lay, a collect, or a placement. Distinct from a hen's own gauges: gauges gate *when* a hen lays, Coop decides *where* the egg ends up, since beds and eggs belong to the coop as a whole, not to any one hen (see ADR-0007).

**Toolbar**:
The bottom UI band's control for placing world objects: a row of item icons, each defined by its icon and what it places. Hold an item's slot and drag into the play area to place its item there for free; dropping outside the play area cancels. Hen bed, seed patch, lettuce, and mealworm are its entries so far — adding another item is meant to be one more definition, not new UI code.

**Slot**:
The Toolbar's fixed-size, uniform square background behind each item's icon. Tapping and holding anywhere within a slot's bounds — not just on its icon — starts that item's drag. An item's icon renders shrunk to fit inside its slot; the dragged ghost still renders at the item's true world size.
_Avoid_: Tile (already the island's ground-unit term), button

**Egg counter**:
The top UI band's display of the player's total collected eggs — their stash, not the number of eggs currently sitting uncollected in the world. Updates the moment an egg is collected.

**UI band**:
One of two strips of the camera, above and below the island, reserved for on-screen controls — the egg counter on top, the toolbar on the bottom — rather than gameplay. Sized from whatever space is left over after the island claims its target share of the safe area's height, not a fixed height of their own. Distinct from the Backdrop: a band holds interactive UI, while the backdrop is purely atmospheric.

## Feeding

**Food item**:
Anything the player places on the island for a chicken to eat. Exists in exactly two kinds — a food source or a treat — which differ in how a chicken consumes them, not in how they are placed. A placement that would land on (or very near) an existing food item is nudged a little instead of stacking exactly on top of it; a placement off the island entirely is cancelled.
_Avoid_: Feed (already the verb, and the name of the module that owns these), food, ploppable

**Food source**:
A food item chickens repeatedly eat from, holding a pool of fullness (its capacity) that eating draws down. Any number of chickens can eat from it at once — they simply deplete it faster together — and it disappears the moment its pool reaches zero, never on a timer. Seed patch and lettuce are the two so far.
_Avoid_: Feeder (implies a container), station, plate

**Treat**:
A food item consumed whole by the single chicken that reaches it first, granting a one-off satiety bump and a temporary happiness buff, then disappearing. Placing one immediately preempts whatever the nearest chicken was doing. Mealworm is the only one so far.
_Avoid_: Snack, one-shot food

**Seed patch**:
One food source drawn as a scatter of individual seed sprites around the point it was placed. The scatter is both art and a depletion gauge: sprites disappear one at a time as the patch's capacity is drawn down, so by the time it's empty every sprite is already gone. Still a single capacity, a single tooltip, and a single point chickens walk to.
_Avoid_: Seeds, seed pile (the patch is one thing, not ten)

**Capacity**:
How much fullness a food source can deliver in total before it's used up, measured in the same units as the Satiety gauge (so a 100-capacity source is exactly enough to fill one empty chicken). Drawn down only by eating — sitting unused doesn't reduce it.
_Avoid_: TTL, lifetime, spoilage, durability, charges

**Forage**:
Eating from the bare ground, which a chicken falls back to only when no food source exists anywhere on the island — a treat waiting to be noticed doesn't count. Fills satiety no further than halfway, so placed food is the only route to a fully fed chicken.
_Avoid_: Graze, peck, scratching

**Approach**:
The state a chicken is in while walking to a food item it has picked. Unlike a wander destination, the target is a specific food item, and arrival either enters eat (a food source) or consumes the treat at once and lingers briefly playing the eat animation (a mealworm has nothing to eat over time, but still gets a couple of seconds of the animation as a flourish) — or re-decides, if the target is gone before it gets there.
_Avoid_: Seek, travel, pathing

**Feed**:
The single shared owner of every placed food item, and the one place a hungry chicken asks what there is to eat. Answers with a food item or with nothing — and nothing is what sends the chicken to forage. Sibling to Coop: Coop owns the egg side of the world, Feed owns the food side (see ADR-0011).
