# Shrink the island for UI bands instead of overlaying them

The egg counter and toolbar need dedicated screen space above and below the play area. The island currently fills nearly the entire safe area (100% width, 92% height, top-justified, with no top margin at all), so that space doesn't exist yet.

We're shrinking the island's width/height fractions (and adding a top margin where there was none) to create real, empty bands the island never draws into, rather than overlaying the counter and toolbar directly on top of the grass at fixed screen positions. Overlaying would be cheaper, but nothing would stop a chicken, bed, or egg from wandering underneath the overlaid UI and getting visually obscured by it — shrinking keeps the play area and the UI bands strictly non-overlapping.
