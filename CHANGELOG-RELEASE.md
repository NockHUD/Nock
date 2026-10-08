## 2.1.0

### Both clients

- **Cooldown grid tile size**: the Icons card on the Grid tab (Advanced) now sets the size of the tiles. Top row height, whether the top row fills the HUD width or keeps a tile width of your choice (centred), and the height and tile width of the rows under it; FluffyHUD's row gets its own height. Unset, the grid looks as before. A width the HUD cannot fit fills it instead, icon zoom crops the art to any shape, and the HUD below moves to make room. By request.
- **Cast bar, pixel-exact**: the React cast bar is laid out in whole screen pixels, like the rest of the HUD, so its fill now meets the right border at any UI scale and its seams stay one pixel.

### WoW Forever (beta)

- **Eyes of the Beast pulse timer**: while you control your pet with Eyes of the Beast, it pulls nearby mobs on a fixed beat counted from the pull. A new row stacked on the React cast bar counts that beat down in combat while Eyes of the Beast is channelled, so you can time your moves between pulses. Right-click it, or type /nock pulse, to resync when the pet's pulse drifts. The interval is 5.6 s by default and adjustable. Off by default: Alerts → Eyes of the Beast pulse. After the "EotB Pet Combat Pulse" WeakAura by Rubot; by request.
- **Trueshot Aura warning**: an amber TSA square when Trueshot Aura is talented but not on you, or has under a minute left on its 30 minutes (the square then counts it down; the lead is a slider, 0 turns it off). In and out of combat, so it shows before the pull; a Where setting limits it to dungeons and raids, or raids only. The game hides your auras in combat, so there Nock goes by your own casts and the buff's 30 minutes: casting it clears the square, /cancelaura Trueshot Aura brings it back, and a right-click on the buff is seen when combat ends. Alerts → Warnings → Combat. By request.
- **Active timers on Rapid Fire, Bestial Wrath and Deterrence**: like the racials, these cooldown tiles now light up with their buff's countdown before the cooldown takes over. Bestial Wrath's is read from your pet.
- **Aspect after /cancelaura**: cancelling your aspect with /cancelaura in combat now clears it from the HUD at once, instead of when combat ends.
