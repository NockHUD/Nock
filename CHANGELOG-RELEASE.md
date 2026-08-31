## 1.1.6

- **Cast bar after weaves, fixed twice** (thank you to everyone who reported
  the 1.1.5 regression!). First: a Steady Shot cancelled by the weave
  step-in could leave a ghost cast behind that swallowed the bar for the
  rest of the cycle — the bar now double-checks the client one frame later,
  so a real cancel clears instantly while button-spamming still can't hide
  a running cast. Second: after the weave, the Auto Shot wind-up bar could
  be born already full and just fade out — a weave re-arm starts its
  wind-up almost exactly on the predicted shot, and the bar anchored to
  that prediction however close it was. The wind-up always takes its full
  haste-scaled time (about 0.5s divided by your haste), so the bar now
  refuses an implausibly short span and fills over the real wind-up again,
  while normal turret cycles keep ending the bar exactly as the arrow
  leaves.
