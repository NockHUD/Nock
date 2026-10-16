## 2.1.3

### Both clients

- **Settings: Step aside**: a new footer button hides the settings window without closing it, so you can drag the HUD into place and come straight back to the page, tab and search you were on. A pill at the top of the screen brings the window back and carries a Lock / Unlock frames toggle of its own; the lock is otherwise left as you had it. The same cycle (open, step aside, back) is on a keybinding, Settings: open / step aside / back, under Key Bindings → Nock.

### WoW Forever (beta)

- **Auto Shot wind-up**: the client now has a wind-up before each Auto Shot, and the game reports nothing about it, so Nock measures it from your own shots: a move that begins inside the wind-up interrupts it, and from those interrupts Nock learns where the wind-up starts (the game's 0.5 s plus your latency, so about 0.6 s). The wind-up mark on the Auto Shot bar and the inverse auto bar's second phase move to the measured spot (the spell-queue window stands in until the first measurement), and the React cast bar shows the wind-up the way it does on TBC: standing still it runs up to the shot; after a late stop it runs from the stop. Moving before the mark is free; moving past it holds the shot until about a second after you stand still again. The measurement is kept per character. Auto Shot wind-up on cast bar (Nock HUD → Size & Elements) switches the cast-bar part off, which you will want with the inverse auto bar, since the two would show the same window twice; the switch now sits in Simple mode. /nock probe windup shows what Nock measured, for bug reports.
- **Learned spells only**: a new Grid option (off by default) leaves a cooldown tile out of the grid while you have not trained its spell, instead of showing it greyed; the row closes up, and the tile returns the moment you learn the spell. The cooldown board still lists the spell, greyed, so it can be placed ahead of time. By request.
