## 2.1.5

### WoW Forever

- **Profiles no longer reset on launch**: if another addon shipped a newer copy of the AceDB library (RXPGuides does), a profile you selected or imported was saved where Nock did not look for it, so every launch dropped you back on Default. Your selection and per-character data now follow your character itself, whichever addons you run. The first launch finds a profile that was stranded this way, restores it and tells you in chat; your Default profile stays in the Profiles list. On Anniversary the per-character data moves over the same way, with no visible change.
- **Held Auto Shot on the swing bars**: when a shot cannot start its wind-up (you are moving, jumping or casting, or the target is out of range), the bar now holds at the wind-up line and dims instead of running on to a shot that will not fire, then runs one wind-up from the moment you can shoot. Works on the React, Fluffy and Classic bars, the inverse bar included.
- **More of what moves the swing bars**: getting up from Feign Death and swapping your ranged weapon restart the reload, Quick Shots shortens the reload it lands on, and a parry cuts your main hand swing.
- **Hide idle swing bars**: a new switch under General → Visibility (off by default) hides the Auto Shot and melee bars between fights. A bar stays while its swing is running or that attack is switched on, so a shot started before the pull still shows. Their space stays reserved so the HUD does not move at a pull, and they always show while frames are unlocked or practice mode is on. By request.
- **AUTO SWAP warning**: an optional square (off by default, under Alerts → Warnings) for when the game's Auto Attack/Auto Shot option is on, which swaps between Auto Shot and melee by range on its own and works against weaving. To turn that option off: Options, Combat, scroll to the bottom and untick it.
- **/nock probe windup** also logs melee on and off, range changes and that game option, for bug reports.
