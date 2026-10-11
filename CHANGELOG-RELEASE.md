## 2.1.2

### Both clients

- **OmniCC GODMODE**: Nock's own timer digits now stand down when OmniCC GODMODE is loaded, as they already did for OmniCC, tullaCC and ncCooldown, so you no longer get two countdowns on the same icon.

### WoW Forever (beta)

- **Eyes of the Beast pulse, out of combat**: a new option, Also out of combat (Alerts → Eyes of the Beast pulse, off by default), shows the pulse bar while you channel Eyes of the Beast outside combat too.
- **Eyes of the Beast pulse follows the pet's beat**: the countdown now starts when you begin the channel and keeps running through the pull and after combat ends, which is what in-game measurements showed. If your bar falls out of step right after a pull, the new Restart at the pull option brings back the old behaviour. A /reload mid-fight no longer leaves the bar empty until a resync, and /nock pulse log shows what the timer saw for bug reports.
- **Fix: Lua error after leaving Eyes of the Beast**: with a sting timer on the cooldown grid, exiting Eyes of the Beast after a kill could throw "calling 'SetFont' on bad self". The sting countdown is now left alone once the game has taken it over.
