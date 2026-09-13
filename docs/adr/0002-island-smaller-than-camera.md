# The island is deliberately smaller than the camera, not equal to it

ADR-0001 concluded the tiled play space should always exactly match the camera, since that kept wander bounds-checking and rendering simple. We're reversing that specific consequence: the island is now sized to 80% of the safe area's width and height (top-justified, horizontally centered), with a flat-colored backdrop filling the rest of the camera around it, so the play space visually reads as its own distinct object — a diorama — rather than an edge-to-edge world.

This became possible because our grass tileset already has real neighbor-based border/corner autotiling (built for a different reason, to blend terrain types at their edges). Once the island's outer ring of tiles is actually visible instead of hidden behind a perimeter fence, that border art *is* the boundary, so the fence that previously marked "camera edge = play boundary" is now redundant and has been removed. The chicken's movement bounds now come from the island's own tile rectangle (inset by one tile) instead.

The camera itself is unaffected by this — it still always matches the device screen exactly, per ADR-0001.
