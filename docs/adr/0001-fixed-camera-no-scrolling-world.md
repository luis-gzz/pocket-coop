---
status: accepted (partially superseded by ADR-0002 — see note below)
---

# Camera matches the device screen exactly; the world never scrolls

The game needs to look consistent across wildly different device screen sizes and aspect ratios without maintaining per-device art or complex scroll/follow logic. We fix a logical content width, let Solar2D compute content height from the device's actual pixel aspect ratio, and use `scale = "letterbox"` — which in practice shows no visible bars, since the computed height already matches the device ratio. Texture filtering is forced to `nearest` so pixel art stays crisp at the resulting non-integer scale factors.

A consequence of this is that the **camera never scrolls** — that part still holds. We originally also concluded the tiled play space would never be bigger than the camera either, keeping it always exactly camera-sized; ADR-0002 reverses that specific consequence (the island is now deliberately smaller than the camera) while keeping everything else here — the fixed-width scaling trick, the lack of scrolling — intact.

This mirrors the approach used in the reference project (`JumpyLlamaRedux`), which uses the same fixed-width/computed-height/letterbox trick in its `config.lua`.
