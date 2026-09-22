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
One mode of chicken behavior — idle, approach, eat, wander, nest, or held — each with its own animation. The chicken is always in exactly one state.

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
An individual mess a chicken leaves on the island, spawned by the poop clock. Persists as its own object until tapped away. Belongs to the garden, not the chicken that made it — every chicken's cleanliness counts every dropping on the island, not just its own (see ADR-0012).
_Avoid_: Poop, mess (dropping is the canonical term; use it consistently even though "poop clock" keeps the informal word for the timer's name)

**Poop clock**:
The recurring, FSM-independent timer that rolls a chance each cycle to spawn a new dropping. Odds increase the longer it's been since the last successful roll, and after the chicken has eaten recently.

**Lay clock**:
The recurring, FSM-independent timer that rolls a chance each cycle for a hen to lay an egg, mirroring the poop clock's shape exactly. Gated by a minimum happiness and a refractory period since the hen's last lay; stores that last lay as a timestamp, not a countdown, the same way the poop clock's own timing state works. Firing sends the hen into the nest state to walk to its target before laying — the refractory timestamp itself is set only once the egg actually lands, not when the clock fires (see ADR-0013).

**Happiness buff**:
A flat, temporary happiness boost with an expiry. Granting one again while it's still active is a no-op — it neither extends the remaining time nor stacks a second bonus. A mealworm treat is the only source so far.
_Avoid_: Pet buff (tapping a chicken no longer grants one)

**Clock**:
The single source of simulated time every chicken's gauges advance against, replacing each chicken computing its own frame delta independently. Also owns the debug time scale below, since scaling time is part of the same "what does a second of sim time mean right now" concern.

**Time scale**:
A debug-only multiplier the Clock applies to every gauge's rate-of-change, used to compress real time for testing (e.g. a minute of decay in one second). Never present in a real play session.

**World object**:
An entity that lives in the game world, as opposed to the island's ground tiles or screen-space UI (the tooltip, the debug button, the egg counter, the toolbar), which always render in their own fixed layers — currently the chicken, its droppings, hen beds, eggs, and food items, with more object types expected later. Most world objects (the chicken, its droppings, eggs) are depth-sorted against each other in the main sort; hen beds and food items instead render in the floor layer, always behind every object in the main sort regardless of position (see Floor layer).
_Avoid_: Entity, game object (too generic — use world object specifically for things that live in the game world)

**Floor layer**:
The fixed render layer beneath the main depth sort, holding hen beds and food items — both always draw behind every world object in the main sort (the chicken, droppings, eggs), no matter their relative position. Hen beds are depth-sorted against each other within this layer, so overlapping beds still order correctly; food items aren't sorted within it at all, since their placement already keeps them from overlapping each other. Distinct from a floor egg's "floor" (meaning: laid outside any bed) — here "floor" names the render layer, not a lack of containment.
_Avoid_: Background layer (Backdrop already owns that sense), ground layer

**Depth**:
A world object's front-to-back render order relative to other world objects: whichever is lower on screen renders in front. Depth is a world object's bottom edge, not its center — every world object type is responsible for supplying its own offset to reach it (see ADR-0006).
_Avoid_: Z-order, layer, Y-sort (Y-sort is the sorting mechanism; depth is the value it sorts by)

## Egg laying

**Hen bed**:
A placeable world object, added via the toolbar, that a laying hen's egg goes into when a slot is open. Holds up to three eggs at once, one per egg slot — full once every slot is occupied. Renders in the floor layer, always behind every object in the main sort. Not removable once placed, but repositionable by holding and dragging it — a drop that would leave any part of it outside the play area snaps back to where it was instead. Two beds may partially overlap, but a placement or drag that would leave one bed's center too close to another's on both axes at once is nudged apart instead of letting them sit directly on top of each other (see ADR-0014).
_Avoid_: Bed (hen bed is the canonical term, to stay unambiguous alongside other future toolbar items). "Nest" is reserved for the chicken state (see Nest) — a hen bed itself is never called a nest.

**Egg slot**:
One of a hen bed's three fixed positions for an egg. A bed is full once every slot is occupied — a laying hen then looks for another bed with an open slot, lays on the floor near a bed if none has one open, or falls back to laying wherever it stands if no bed exists on the island at all.
_Avoid_: Nest slot, spot

**Egg**:
A collectable world object produced by a hen's lay clock. Sits either in a hen bed's egg slot (tidy — doesn't affect cleanliness) or on the ground as a floor egg. Tapping either kind collects it: increments the egg counter, removes the egg, and frees its slot if it had one.

**Floor egg**:
An egg that landed outside any hen bed's slots. Lands near the nearest bed if any bed exists on the island (every one of them full), or wherever the hen happens to be if no bed exists at all. Counted toward the cleanliness target as a dirty item, weighted the same as a dropping — collecting it removes that penalty automatically.
_Avoid_: Loose egg, ground egg

**Nest**:
The state a chicken is in while walking to where it will lay, entered the moment the lay clock fires: a hen bed with an open slot if one exists anywhere on the island, or a floor spot near the nearest bed if every bed is full. Preempts whatever the hen was doing, the same way a treat's placement preempts approach. Re-checks its target on arrival — if the chosen bed filled up in the meantime, it looks again for another bed with an open slot before falling back to the floor. If no bed exists anywhere on the island, the hen lays immediately instead of entering nest at all.
_Avoid_: Lay approach, settle (nest is the canonical term for this state)

**Garden**:
The single shared owner of every chicken, every placed hen bed, every active egg, and every dropping, plus the player's collected-egg count, with Feed held alongside it for the food side. Decides where a newly laid egg goes and whose cleanliness a dropping counts against, and is where saving happens on a lay, a collect, a placement, or a dropping spawning/being cleaned. Distinct from a hen's own gauges and its own state machine: gauges gate *when* a hen lays or poops, Garden decides *where* the result goes and *who* it affects, and the hen's own nest state carries out *how* it gets there, since beds, eggs, and droppings belong to the garden as a whole, not to any one hen (see ADR-0007, ADR-0012, ADR-0013).
_Avoid_: Coop (retired — beds/eggs/droppings are no longer a separate owner from the chickens themselves)

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
Eating from the bare ground, which a chicken falls back to only when no food source exists anywhere on the island — a treat waiting to be noticed doesn't count. Fills satiety no further than halfway, so placed food is the only route to a fully fed chicken. Never gets Eat's minimum-eating floor, so a forage bout can still end within its first second, same as always.
_Avoid_: Graze, peck, scratching

**Approach**:
The state a chicken is in while walking to a food item it has picked. Unlike a wander destination, the target is a specific food item, and arrival either enters eat (a food source) or consumes the treat at once and lingers briefly playing the eat animation (a mealworm has nothing to eat over time, but still gets a couple of seconds of the animation as a flourish) — or re-decides, if the target is gone before it gets there.
_Avoid_: Seek, travel, pathing

**Eat**:
The state a chicken is in while actively eating — from a claimed food source, or foraging in place with no target. From a food source, it's guaranteed to close at least half the gap between its satiety and full before it can quit early, so a hen that was already mostly fed still eats for a little while rather than stopping the instant it started; forage has no such floor (see Forage). Past that floor — or from the first moment, when foraging — it rolls roughly once a second for whether to stop, the chance rising the closer satiety already is to whichever ceiling is in force. Always ends the moment satiety reaches that ceiling regardless of the floor, and can also be cut short at any time by a treat, being picked up, or the food source running out.
_Avoid_: Eating (eat is the state's own name already)

**Feed**:
The single shared owner of every placed food item, and the one place a hungry chicken asks what there is to eat. Answers with a food item or with nothing — and nothing is what sends the chicken to forage. Owned by Garden alongside its chicken/bed/egg/dropping state — Garden owns everything else in the world, Feed owns the food side (see ADR-0011).
