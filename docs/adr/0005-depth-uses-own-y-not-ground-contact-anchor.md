---
status: superseded by ADR-0006
---

# Depth uses a world object's own y, not a per-type ground-contact anchor

World objects (currently the chicken and droppings, with more types expected later) are depth-sorted for rendering by taking each object's own y position directly — the chicken's view y, a dropping's stored ground position — rather than a separate per-type "ground contact point" (e.g. the chicken's shadow, which sits below its view's y at the sprite's visual feet).

We considered using the ground-contact point for more visually precise occlusion, but rejected it: the offset is small enough not to visibly matter, "own y" is the value already used everywhere else in the chicken's code (movement, bounds clamping, tooltip anchoring), and it generalizes to any future world object type with zero per-type configuration — a ground-contact approach would require every new entity type to define its own anchor offset before it could join the sort.
