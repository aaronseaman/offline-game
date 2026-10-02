# Molded-plastic artwork

The visual target is the rounded, satin-finished, softly lit toy material of the supplied character reference. This pass applies that material to the puzzle pieces, tray, controls, special blocks, icons and launch screens.

![Phone gameplay with a seeded review board](artwork-play.png)

![Main menu](artwork-menu.png)

The gameplay image uses a seeded board to show the ordinary pieces, line blaster, bomb and prism together. This fixture is not included in normal gameplay.

## Verified

- Existing engine test suite passes; game rules are unchanged.
- Chromium rendering reviewed at 440 × 956, 390 × 844 and 956 × 440 CSS pixels.
- Pause, settings, color symbols, resume and offline reload checked with no page errors.
- Shared artwork and core modules load through the service worker while offline.
- Icons and all six iOS launch-screen sizes regenerated with the shared renderer.
- Single-file artifact build succeeds.

Physical iPhone Safari testing remains outstanding. The reference is a rendered character image; this is an intentionally lightweight Canvas approximation of its materials, not a live 3D renderer.
