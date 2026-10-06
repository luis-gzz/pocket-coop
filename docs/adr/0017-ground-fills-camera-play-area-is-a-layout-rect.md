---
status: accepted
---

# The ground fills the camera; the play area is a layout rect, not an island

Supersedes ADR-0002. The bordered island is gone: plain grass now tiles the whole camera, behind the UI bands too, from the camera's top-left corner (with partial tiles cut off at the right and bottom). There is no backdrop and no autotiled border.

The play area is now a rect that `layout.lua` computes from the safe area and has no tie to the tile grid. Vertically it takes 85% of the safe height, no longer rounded down to whole tiles, with the bands splitting the leftover space as in ADR-0009. Horizontally it is inset 2% of the safe width on each side. Its bottom keeps the half-tile inset. Because the ground covers everything, the play area's size no longer has to come out in whole tiles. Its edge is invisible on purpose; a fence or props can mark it later if playtesting asks for that.

We kept ADR-0002's other result, a play area slightly smaller than the camera. What we gave up is the diorama look, in exchange for a uniform field. Saved positions are not clamped on load, so an item saved right at the old edge can sit slightly inside the new margin.
