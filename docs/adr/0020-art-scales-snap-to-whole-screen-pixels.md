# Art scales snap to whole screen pixels; UI has its own scale

Pixel art drawn with nearest-neighbour filtering only looks even when each art pixel covers a whole number of real screen pixels. The aspect-ratio-interpolated `PIXEL_SCALE` and the fixed 384-point content width didn't guarantee that. On an iPhone, a world pixel came out at about 9.2 screen pixels, so pixels alternated between 9 and 10 wide. The tooltip's 16×16 icons, squeezed into an 8-unit box, came out at about 4.6 and alternated between 4 and 5, which was visibly wrong.

We now treat `computePixelScale()` as a target and snap it to whole screen pixels at launch. `WORLD_PPA` is the screen pixels per world art pixel, and `PIXEL_SCALE` follows from it. This trades exact aspect-ratio scaling for crisp pixels: the world's size can shift by up to about 5% on some devices.

UI art gets its own scale, `UI_PIXEL_SCALE`: about half the world's pixel size, also whole. Tooltip icons can therefore stay small and fine without going uneven. Toolbar icons shrink into their slots only by whole steps (`snapPpa`), capped at world size, rather than by an arbitrary contain-fit.

Anything new that draws art should size it from `PIXEL_SCALE` (world) or `UI_PIXEL_SCALE` (UI), never from a free-form fraction of either.

With every scale whole, image sheet frames line up exactly, so `isImageSheetSampledInsideFrame` is turned off. That half-texel inset was a workaround for edge bleed at the old fractional scales, and at whole scales it only squished each frame's edge pixels (most visibly the tooltip's happiness face).
