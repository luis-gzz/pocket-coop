---
status: accepted
---

# A held egg delays an egg from time away so it's laid live; it never adds one

At one egg every few hours, players almost never see a hen hop onto the bed and lay, which is the most charming thing she does. After a full offline catch-up, with a 1 in 3 chance, one hen keeps her last egg from the absence instead of having it placed. Shortly after the welcome-back card closes (15 to 30 real seconds) she lays it live through the normal nest walk, with the egg bubble showing.

It delays an egg and never adds one, so egg counts and the offline numbers (ADR-0027) are unchanged; the egg's lay progress was already spent while away. For that reason it ignores the one-hour minimum gap and the lay gates once it's due. It's only held back if, at return, the hen passes both lay gates (ADR-0026) and a bed still has an open slot after catch-up has placed every other egg: the point is watching her hop onto a bed, and a hen too hungry to lay shouldn't be shown laying. At most one hen per return, picked at random from those that laid.

It is never lost. The flag is saved on the hen; if the app suspends or closes before she lays it, it lands then, and a flag still set when the next catch-up starts lands first. If she's picked up or drawn to a treat on the way, she tries again afterwards. A normal lay that happens to fire before the held one is due uses the held egg instead of her progress, which keeps the total the same.

Alternatives were to add a bonus egg on return (changes the economy and rewards absence) or to replay the last egg's timing exactly (needs positions offline doesn't have).
