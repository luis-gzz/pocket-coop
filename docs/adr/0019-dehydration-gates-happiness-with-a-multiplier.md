# Dehydration gates happiness with a multiplier, applied before the buff

Hydration joins satiety and cleanliness in happiness's worst-pulls-hardest weighted average, with its own knee (80 or more counts as fully watered, like satiety's 85). On its own, though, that average lets two good gauges carry a chicken that has no water at all, and going without water should be serious. So below 10 hydration (dehydrated), the weighted result is also multiplied by `hydration / 10`, and it reaches zero when the gauge is empty. The alternatives were a plain three-way average (too forgiving) or a multiplier across the whole range (it would punish ordinary drinking dips).

The happiness buff is added *after* the multiplier. A dehydrated chicken that just had a treat therefore still reads about 25 (below the lay gate, but not zero), rather than the buff being scaled away as well. This is deliberate: a treat should always visibly help. It's easy to "fix" back by moving the buff inside the multiplier.
