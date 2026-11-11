---
status: accepted
---

# Petting is a stroke gesture that pauses the hen, not a state

A chicken's touch already meant two things by duration: a short tap opens her tooltip, a still hold of 350 ms picks her up (ADR-0022 covers taps with an item selected). Petting adds a third by movement: a touch that travels more than about a quarter of her width before the long press fires becomes a pet. The long-press timer is cancelled, so she isn't picked up and no tooltip opens on release. A tap still grants nothing.

A pet is a pause laid over whatever state she is in, not a state of its own. Movement, an eating bout and a drink freeze, nothing new starts, and on release she carries on with exactly what she was doing: the same wander route, the same walk to food, a bowl, a treat or a bed. The first design made `pet` a state that ended in a fresh re-decide, like being picked up; that would have thrown away a nest walk or a half-eaten bout for a two-second gesture. Gauges keep running as if she were held, so a lay that comes due waits for release. She can't be petted while on or hopping to a hen bed, while eating a treat or bathing (short timed animations that pay out at the end), or while held.

Progress is seconds of stroking: each move event over a padded hit zone adds the time since the last one, capped, so a resting finger earns nothing and slipping off pauses rather than resets. About two seconds completes the pet: one burst of hearts per touch and the pet buff (+10 happiness for 30 minutes). The buff never stacks: each pet sets its expiry to 30 minutes from that moment, and with a treat buff active only the larger bonus applies. There is no cooldown, so an attentive player can keep +10 up while playing; that is accepted because the lay gates (ADR-0026) stop it turning a neglected hen into eggs, and it lapses 30 minutes into any absence. Petting clears a selected item, matching pickup.
