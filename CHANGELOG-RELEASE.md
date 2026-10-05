## 2.0.12

### Both clients

- **Redtuzk corner icons**: a second look for the React HUD's corner icons (Size & Elements → Corners → Corner icon style). "Nock" keeps the corner squares; "Redtuzk" draws wide rectangles centred above the cluster: your aspect in the middle, joined by Hunter's Mark only while it is on your target, the pair growing out from the centre. Each style keeps its own dragged positions, and the mark previews while the HUD is unlocked. Idea and look by redtuzk.
- **Latency zone on the cast bar**: an optional red zone at the right end of the React cast bar, as wide as your latency, the way Quartz shows it. Once the fill reaches it, a move or your next press arrives at the server after the cast has already landed. Channels and the Auto Shot wind-up get none. Off by default: Size & Elements → Cast bar → Latency zone; colour under Skin.
- **Crisper borders**: bars and tiles that share a border now always draw exactly one pixel of it, at any UI scale. Before, some scales hid the line entirely (and cut a pixel off the tile, so a grid row looked clipped by the one above) or drew it doubled. Fixed across the React grid, the React and Fluffy bar stacks, the Fluffy cooldown row, the buff row and the pet lamps.
