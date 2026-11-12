---
status: accepted
---

# Foraging is removed, and laying has hard gates on satiety and hydration

Eggs should come only from a hen whose needs are met, so prices and food values can later be tuned against one clear rule. Foraging worked against that: it existed to stop a hen going hungry, so a hen neglected for a day hovered around a quarter full and still laid about three eggs. Foraging is gone entirely, including the peck at bare ground, so pecking always means she is eating something the player placed. With no food source out a hen isn't hunger-seeking; she idles and wanders while satiety falls to 0. Hunger is now one flag, the mirror of thirst.

Laying gets two hard gates, checked before happiness: satiety below 10 (`LAY_SATIETY_GATE`) or hydration below 10 (`DEHYDRATED_BELOW`) means a lay rate of 0. Happiness alone wasn't enough, because buffs are added after the gauges are weighed: a starving but clean, watered hen with a treat buff read about 43 and laid. While a gate fails, lay progress holds and banked progress can't fire; only a lay already walking to the bed lands. There is no cleanliness gate: happiness already stops laying at about 16 cleanliness, and mess should cost eggs gradually, not as a switch.

Starving also gets dehydration's multiplier (ADR-0019): below 10 satiety, happiness before the buff is scaled by `satiety / 10`. When a hen is both starving and dehydrated only the worse of the two scales apply, not their product. This keeps the tooltip face tied to the happiness number, as before, while making a starving hen read sad in nearly every case. The face and the gate can still disagree in a narrow band (about 3 to 10 satiety or hydration with a treat buff reads meh while she isn't laying). That band is accepted: it is narrow, and the nearly empty bar sits right beside the face. A status line under the bars ("Laying", "Not laying: hungry") was built and dropped, since the bars and the face already carry it. The other alternative was to make the face follow the lay rate instead, which would have left a sad face beside a half-full happiness bar.

This amends ADR-0010 and ADR-0015 (no forage trigger, forage stop or unfed floor) and ADR-0019 (the multiplier now has a satiety twin).
