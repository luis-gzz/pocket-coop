# Pocket Chicken

A Solar2D (Corona) tamagotchi-style game where the player cares for one or more chickens.

## Language

**Camera**:
The visible play area, sized to exactly match the device's screen. It never scrolls or follows anything — what's on screen is the entire game world.
_Avoid_: Viewport, screen (screen is ambiguous between device pixels and camera content points)

**Ground**:
The grass tiled edge-to-edge across the entire camera, under the UI bands too. Purely visual — it has no border and no bearing on where anything can go; that's the play area's job.
_Avoid_: Island (retired — there is no longer a bordered play space), backdrop (retired), world, map, level

**Tile**:
A fixed-size square unit of the ground, repeated with no gaps from the camera's top-left corner until the whole camera is covered; tiles at the right and bottom edges may be cut off.

**Play area**:
The region of the camera where the chicken can move and world objects can be placed: between the two UI bands vertically (stopping half a tile short of the bottom band), and inset from the safe area's left and right edges by a small margin. Not marked by anything on screen — the ground looks the same on either side of its edge.
_Avoid_: Island

**Chicken**:
The player's pet, driven by a finite state machine. Stays within the play area's bounds at all times.

**State** (chicken):
One mode of chicken behavior — idle, approach, eat, bathe, wander, nest, or held — each with its own animation. The chicken is always in exactly one state.

**Dwell time**:
How long a chicken remains in idle or wander before the state machine re-decides. Randomized per state to avoid a robotic cadence.
_Avoid_: Duration, timer

**Wander destination**:
A random point near the chicken, within the play area's bounds, chosen when a chicken enters the wander state. Wander ends when the chicken arrives there — not on a timer, unlike idle/wander's dwell time.

**Held**:
The state a chicken is in while the player is dragging it. Entered by touch input rather than by the state machine's own re-decide logic; exits back into a fresh re-decide (not necessarily idle) on release.

**Wiggle**:
The feedback animation a chicken plays continuously for as long as it's held. Stops and settles flat the moment it's released.

**Selected**:
A purely visual highlight (a ring under the chicken) shown while that chicken's tooltip is open. It has no effect on behavior — a selected chicken keeps doing whatever it was doing, and stays selected while picked up and dragged.
_Avoid_: Frozen, focused

**Satiety**:
The gauge tracking how fed a chicken is (0–100, 100 is full). Falls steadily over real hours while the chicken isn't eating (more slowly while satisfied), rises while eating. Displayed to the player as "Fullness."
_Avoid_: Hunger (inverted sense — high hunger would mean *unfed*, which is the opposite convention every gauge in this game uses)

**Satisfied**:
A short spell after a chicken's satiety reaches 100 during which it falls much more slowly. It never stops the chicken eating — it only slows how fast it gets hungry again. Granted by any meal or mealworm that tops satiety off.
_Avoid_: Satisfied buff as a mood effect (it has no effect on happiness), full

**Hunger trigger**:
The satiety level below which a chicken starts a hunger cycle. It has one for each way of eating — a higher one used while any food source exists, a much lower one while only foraging is possible — and both are re-picked at random each time a hunger cycle ends, so a chicken doesn't get hungry at the same number every time. Which one applies follows whether food exists *right now*, so placing food draws a moderately hungry chicken at once.

**Hunger cycle**:
The stretch from a chicken crossing its hunger trigger until it is done eating: until satiety reaches 100 when eating from a food source, or until it reaches the forage stop when foraging. Made up of one or more bouts.

**Bout**:
One sitting of eating from a food source: it closes half the gap between satiety and 100, or all of it once that gap is small. Bouts within a hunger cycle are separated by a short break of wandering or idling.
_Avoid_: Meal (a meal is ambiguous between one bout and the whole cycle)

**Forage stop**:
The satiety level (re-picked each hunger cycle, always under the forage ceiling of 50) at which a foraging chicken stops eating and its hunger cycle ends.

**Cleanliness**:
The gauge tracking how clean a chicken's surroundings are (0–100, 100 is clean). Doesn't drain directly — it eases toward a target set by how many droppings and floor eggs currently exist, so cleaning a dropping or collecting a floor egg raises the target and cleanliness recovers toward it gradually — mostly within a quarter hour, fully within the hour — rather than being restored directly by the act of cleaning. Time away recovers it the same way, so cleaning up and coming straight back doesn't return a spotless chicken. Ash is the one thing that bumps the gauge itself; that bump then eases back toward the target like any other value, so it lasts in a tidy garden and fades in a messy one.

**Hydration**:
The gauge tracking how watered a chicken is (0–100, 100 is fully watered). For now it always sits at 100 with no way to change it and no bearing on happiness; it exists so the tooltip shows it ahead of water being added.
_Avoid_: Thirst (inverted sense, same reason as hunger)

**Happiness**:
A chicken's overall well-being, computed on read from satiety, cleanliness, and any active happiness buff — never stored on its own. Weighted so that whichever of satiety/cleanliness is worse pulls the result down harder.
_Avoid_: Mood, wellbeing

**Dropping**:
An individual mess a chicken leaves in the play area, spawned when its poop progress completes. Persists as its own object until tapped away. Belongs to the garden, not the chicken that made it — every chicken's cleanliness counts every dropping in the garden, not just its own (see ADR-0012).
_Avoid_: Poop, mess (dropping is the canonical term; use it consistently even though "poop progress" keeps the informal word for the gauge's name)

**Poop progress**:
A chicken's steady, FSM-independent progress toward its next dropping, filling at the same average rate (about one every two hours) whether the chicken is fed or not. Each dropping needs a slightly different, randomly picked amount of progress so they don't arrive like clockwork; leftover progress carries over, including across time away.
_Avoid_: Poop clock (retired — there is no longer a recurring roll)

**Lay progress**:
A hen's steady, FSM-independent progress toward her next egg, filling faster the happier she is and not at all below a minimum happiness. Like poop progress, each egg needs a slightly different amount and leftover progress carries over. A hen can't lay again until a minimum gap has passed since her last egg landed. Completing it sends the hen into the nest state; the progress is only spent once the egg actually lands, so an interrupted walk doesn't lose the egg (see ADR-0013).
_Avoid_: Lay clock (retired — there is no longer a recurring roll)

**Happiness buff**:
A flat, temporary happiness boost lasting an hour. A chicken has at most one: granting it again while it's still active restarts the hour rather than stacking a second bonus. Granted by any treat (mealworm or ash).
_Avoid_: Pet buff (tapping a chicken no longer grants one)

**Chicken tooltip**:
The screen-space panel opened by tapping a chicken: its name on top, then one icon-labeled bar per gauge — happiness, fullness (satiety), cleanliness, hydration. It sits in the play area's bottom-right corner, or its top-right corner if the chicken is under that spot when it opens, and stays there until dismissed. Item tooltips are a separate, simpler panel anchored beside their item: a food source's shows how much is left; a treat's shows its name and what it gives.
_Avoid_: Popover, inspector, stats panel

**Clock**:
The single source of simulated time every chicken's gauges advance against, replacing each chicken computing its own frame delta independently. Also owns the debug time scale below, and every timer that affects a gauge (how long a chicken idles, the break between bouts), so the whole simulation speeds up together. Only cosmetic timing — walking and animation — stays in real time.

**Time scale**:
A debug-only multiplier the Clock applies to every gauge's rate-of-change, used to compress real time for testing (e.g. a minute of decay in one second). Never present in a real play session.

**World object**:
An entity that lives in the game world, as opposed to the ground or screen-space UI (the tooltip, the debug button, the egg counter, the toolbar), which always render in their own fixed layers — currently the chicken, its droppings, hen beds, eggs, food sources, and treats, with more object types expected later. Most world objects (the chicken, its droppings, eggs, mealworms) are depth-sorted against each other in the main sort; hen beds, food sources, and ash instead render in the floor layer, always behind every object in the main sort regardless of position (see Floor layer).
_Avoid_: Entity, game object (too generic — use world object specifically for things that live in the game world)

**Floor layer**:
The fixed render layer beneath the main depth sort, holding hen beds, food sources, and ash — all always draw behind every world object in the main sort (the chicken, droppings, eggs, mealworms), no matter their relative position. Hen beds are depth-sorted against each other within this layer, so overlapping beds still order correctly; food sources and ash aren't sorted within it at all, since their placement already keeps them from overlapping each other. Distinct from a floor egg's "floor" (meaning: laid outside any bed) — here "floor" names the render layer, not a lack of containment.
_Avoid_: Background layer, ground layer (Ground already owns that sense)

**Depth**:
A world object's front-to-back render order relative to other world objects: whichever is lower on screen renders in front. Depth is a world object's bottom edge, not its center — every world object type is responsible for supplying its own offset to reach it (see ADR-0006).
_Avoid_: Z-order, layer, Y-sort (Y-sort is the sorting mechanism; depth is the value it sorts by)

## Egg laying

**Hen bed**:
A placeable world object, added via the toolbar, that a laying hen's egg goes into when a slot is open. Holds up to three eggs at once, one per egg slot — full once every slot is occupied. Renders in the floor layer, always behind every object in the main sort. Not removable once placed, but repositionable by holding and dragging it — a drop that would leave any part of it outside the play area snaps back to where it was instead. Two beds may partially overlap, but a placement or drag that would leave one bed's center too close to another's on both axes at once is nudged apart instead of letting them sit directly on top of each other (see ADR-0014).
_Avoid_: Bed (hen bed is the canonical term, to stay unambiguous alongside other future toolbar items). "Nest" is reserved for the chicken state (see Nest) — a hen bed itself is never called a nest.

**Egg slot**:
One of a hen bed's three fixed positions for an egg. A bed is full once every slot is occupied — a laying hen then looks for another bed with an open slot, lays on the floor near a bed if none has one open, or falls back to laying wherever it stands if no bed exists in the garden at all.
_Avoid_: Nest slot, spot

**Egg**:
A collectable world object produced when a hen's lay progress completes. Sits either in a hen bed's egg slot (tidy — doesn't affect cleanliness) or on the ground as a floor egg. Tapping either kind collects it: increments the egg counter, removes the egg, and frees its slot if it had one.

**Floor egg**:
An egg that landed outside any hen bed's slots. Lands near the nearest bed if any bed exists in the garden (every one of them full), or wherever the hen happens to be if no bed exists at all. Counted toward the cleanliness target as a dirty item, but only half as dirty as a dropping — collecting it removes that penalty automatically.
_Avoid_: Loose egg, ground egg

**Nest**:
The state a chicken is in while walking to where it will lay, entered the moment lay progress completes: a hen bed with an open slot if one exists anywhere in the garden, or a floor spot near the nearest bed if every bed is full. Preempts whatever the hen was doing, except a claimed treat, which she finishes first (the lay waits, it isn't lost). Re-checks its target on arrival — if the chosen bed filled up in the meantime, it looks again for another bed with an open slot before falling back to the floor. If no bed exists anywhere in the garden, the hen lays immediately instead of entering nest at all.
_Avoid_: Lay approach, settle (nest is the canonical term for this state)

**Garden**:
The single shared owner of every chicken, every placed hen bed, every active egg, and every dropping, plus the player's collected-egg count, with Feed held alongside it for the food side. Decides where a newly laid egg goes and whose cleanliness a dropping counts against, and is where saving happens on a lay, a collect, a placement, or a dropping spawning/being cleaned. Distinct from a hen's own gauges and its own state machine: gauges gate *when* a hen lays or poops, Garden decides *where* the result goes and *who* it affects, and the hen's own nest state carries out *how* it gets there, since beds, eggs, and droppings belong to the garden as a whole, not to any one hen (see ADR-0007, ADR-0012, ADR-0013).
_Avoid_: Coop (retired — beds/eggs/droppings are no longer a separate owner from the chickens themselves)

**Toolbar**:
The bottom UI band's control for placing world objects: a row of item icons, each defined by its icon and what it places. Hold an item's slot and drag into the play area to place its item there for free; dropping outside the play area cancels. Hen bed, seed patch, lettuce, mealworm, and ash are its entries so far — adding another item is meant to be one more definition, not new UI code.

**Slot**:
The Toolbar's fixed-size, uniform square background behind each item's icon. Tapping and holding anywhere within a slot's bounds — not just on its icon — starts that item's drag. An item's icon renders shrunk to fit inside its slot; the dragged ghost still renders at the item's true world size.
_Avoid_: Tile (already the ground's unit term), button

**Egg counter**:
The top UI band's display of the player's total collected eggs — their stash, not the number of eggs currently sitting uncollected in the world. Updates the moment an egg is collected.

**UI band**:
One of two strips of the camera, above and below the play area, reserved for on-screen controls — the egg counter on top, the toolbar on the bottom — rather than gameplay. Sized from whatever space is left over after the play area claims its target share of the safe area's height, not a fixed height of their own. The ground shows through behind both bands.

## Feeding

**Food source**:
Something the player places in the play area for chickens to repeatedly eat from, holding a pool of food units (its capacity) that eating draws down. Any number of chickens can eat from it at once — they simply deplete it faster together — and it disappears the moment its pool reaches zero, never on a timer. A placement that would land on (or very near) another food source or a treat is nudged a little instead of stacking on top of it; a placement outside the play area entirely is cancelled. Seed patch and lettuce are the two so far.
_Avoid_: Feeder (implies a container), station, plate, food item (retired: one-use items left Feed and became treats)

**Seed patch**:
One food source drawn as a scatter of individual seed sprites around the point it was placed. The scatter is both art and a depletion gauge: sprites disappear one at a time as the patch's capacity is drawn down, so by the time it's empty every sprite is already gone. Still a single capacity and a single tooltip, but a chicken pecks at one individual seed, hopping to another still-showing seed (within the same bout) when its own disappears.
_Avoid_: Seeds, seed pile (the patch is one thing, not ten)

**Capacity**:
How much food a food source holds, in food units, before it's used up. Drawn down only by eating — sitting unused doesn't reduce it.
_Avoid_: TTL, lifetime, spoilage, durability, charges

**Food unit**:
The measure of food a food source holds, defined by what a fed chicken eats: about 100 food units keep one well-fed chicken fed for an hour. Each unit is worth only a small amount of satiety, so keeping a chicken fed is cheap but refilling a hungry one is deliberately expensive — a mealworm is the fast way back.
_Avoid_: Fullness, satiety points (satiety is the chicken's gauge, not the food's)

**Forage**:
Eating from the bare ground, which a chicken falls back to only when no food source exists anywhere in the garden — a treat waiting to be noticed doesn't count. Starts only once satiety drops below the (low) forage hunger trigger and ends at the forage stop, never above halfway, so an unfed chicken hovers around a quarter full and placed food is the only route to a fully fed one.
_Avoid_: Graze, peck, scratching (as names for foraging; a peck point is unrelated)

**Peck point**:
The spot on a food source or mealworm where a chicken's beak lands while it eats: somewhere along the item's bottom edge, or one particular seed for a seed patch. Picked fresh on each approach; any number of chickens may pick overlapping ones.
_Avoid_: Eating spot (that's where the chicken stands, not where it pecks)

**Approach**:
The state a chicken is in while walking to a food source or treat it has picked. Unlike a wander destination, the target is a specific item. For something it will eat, the chicken stands beside it at the same depth, on whichever side is the shorter walk, and turns to face it so its beak lands on a peck point. For ash it walks to the patch's center instead. Arrival enters eat (a food source), eats a mealworm over a couple of seconds of the eat animation (the mealworm staying in place until it's done), or enters bathe (ash) — or re-decides, if the target is gone before it gets there.
_Avoid_: Seek, travel, pathing

**Eat**:
The state a chicken is in while actively eating — one bout from a claimed food source, or foraging in place with no target. Ends once the bout's target (or the forage stop) is reached, and can also be cut short at any time by a treat, being picked up, or the food source running out; a forage bout also ends the moment food is placed, so the chicken can head for it.
_Avoid_: Eating (eat is the state's own name already)

**Feed**:
The single shared owner of every placed food source, and the one place a hungry chicken asks what there is to eat. Answers with a food source or with nothing — and nothing is what sends the chicken to forage. Owned by Garden alongside its chicken/bed/egg/dropping state — Garden owns everything else in the world, Feed owns the food sources, Treats owns the one-use items (see ADR-0011, ADR-0018).

## Time away

**Offline catch-up**:
Bringing the garden up to date for time the app was closed or in the background, once that time reaches the offline threshold. It lands where watching would have landed — same rules, same numbers — but works out the result in a few broad phases (food lasting, then food gone) instead of replaying every moment. Time away counts for at most a day. Treats are never used during it — they stay out for the chicken to find once the player is back — and each chicken reappears somewhere new, as if it had wandered off meanwhile.
_Avoid_: Offline simulation, replay (it deliberately doesn't step through time)

**Offline threshold**:
How long the player must be away (ten minutes) before a return counts as time away. A shorter absence — a quick app switch — simply continues the game as if it had never paused: no catch-up, no welcome-back card, and the chicken stays where it was.

**Welcome-back card**:
The message shown after every offline catch-up, telling the player how long they were really away (not capped at a day). Dismissed with its OK button or a tap anywhere else; the game keeps running behind it.
_Avoid_: Welcome screen, offline report (it reports only the time away, not what happened)

**Fed plateau**:
The satiety a chicken with food available averages over its hunger cycles. Offline catch-up holds a fed chicken there while food lasts. Its counterpart for an unfed chicken is the **unfed floor**, where foraging settles.

## Treats

**Treat**:
Anything the player places in the play area that's used up whole by the single chicken that reaches it first, granting a one-time boost to one gauge (an amount each treat type defines) plus the happiness buff, then disappearing. Placing one immediately preempts whatever the nearest chicken within alert range was doing. Once claimed, the chicken sees it through: a newer or nearer treat doesn't draw it away, and neither does a lay. Only being picked up, or the player dragging the treat away, breaks the claim. A chicken uses one even when the gauge it helps is already full. Never counts as food for hunger or foraging, even a mealworm, and never used during time away. Placement spacing matches food sources. Mealworm (satiety) and ash (cleanliness) so far.
_Avoid_: Snack, one-shot food, pamper item (retired)

**Mealworm**:
A treat that gives satiety (+25). Eaten over a couple of seconds of the eat animation, staying in place until it's done. Depth-sorted in the main sort, just behind the chicken eating it.

**Ash**:
The early-game treat that gives cleanliness, drawn as a patch of wood ash a little larger than a chicken, always rendered in the floor layer. The chicken that claims it walks to its center and bathes in it for a few seconds; only once the bath finishes does it get a cleanliness bump (+75) and the happiness buff, and the patch disappears. Picking the chicken up mid-bath cancels with no payoff, and the patch stays out to be claimed again. Displayed to the player as "Ash bath."
_Avoid_: Ash patch, ash pile (the patch is just how it looks), dust bath (reserved for a separate, later treat)

**Bathe**:
The state a chicken is in while bathing in ash: sitting on the patch and shimmying in place.

**Shimmy**:
The gentle side-to-side motion a bathing chicken makes for the whole bath. Smaller and quicker than the held wiggle.
_Avoid_: Wiggle (reserved for being held)

**Treats** (module):
The single shared owner of every placed treat, Feed's counterpart for one-use items. Owned by Garden alongside Feed (see ADR-0018).

**Alert priority**:
When several treats are within a chicken's alert range, it prefers one that helps its lower gauge (a mealworm if satiety is lower than cleanliness, ash if cleanliness is lower), then the nearest. A lone treat in range is always taken, whichever gauge it helps.
