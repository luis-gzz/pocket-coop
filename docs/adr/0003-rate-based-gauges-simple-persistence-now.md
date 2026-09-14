---
status: accepted
---

# Gauges are built for future offline reconstruction, but this milestone only does simple persistence

Every gauge update goes through one path shaped as rate × delta-time, with a last-update timestamp stored alongside — even though nothing reads that timestamp yet. This is deliberate groundwork: a future pass that reconstructs gauge decay for time elapsed while the app was closed only needs to call the same update path with a large delta, instead of a rewrite. Droppings are likewise stored as timestamped instances (not a bare count) and the pet buff as an expiry timestamp (not a countdown), for the same reason — both collapse cleanly given an arbitrary elapsed time.

Despite building for that future, this milestone deliberately does *not* implement offline reconstruction. Persistence here is simple: satiety, cleanliness, the dropping list, pet-buff expiry, and chicken position are saved to a plain JSON file (Solar2D's built-in `json` + `io`, in `system.DocumentsDirectory`) both periodically and on app suspend/exit. On load, values resume exactly as saved — no decay is computed for elapsed time, time simply continues forward from that point. We chose a hand-rolled JSON file over a plugin (e.g. `plugin.GBCDataCabinet`, used in the reference project `JumpyLlamaRedux`) specifically to avoid an external dependency for what is currently a small, simple blob.

The save format will need to grow once offline reconstruction is built (at minimum, the load path will start using the stored timestamps instead of ignoring them). That's an anticipated, contained follow-up, not a surprise.
