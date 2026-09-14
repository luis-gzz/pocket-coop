# Cleanliness eases toward a target instead of draining directly

The obvious reading of "cleanliness drops faster the more droppings exist" is a pure drain rate — but a pure drain only ever slows the bleeding when you clean a dropping; it never actually recovers cleanliness on its own. That contradicts the plain expectation that cleaning up should visibly make things better.

Instead, cleanliness eases toward a target that's a pure function of the current dropping count (`target = clamp(100 - droppings × penalty, 0, 100)`), moving toward that target over time rather than being pushed directly by drops or cleaning events. Cleaning a dropping raises the target, and cleanliness recovers toward it on its own — recovery falls out of the model shape for free, with no separate "cleaning bonus" needed. As a side effect, this also makes a future offline pass nearly trivial for this gauge: over any large time gap, cleanliness simply arrives at `target(dropping_count_at_wake)`.
