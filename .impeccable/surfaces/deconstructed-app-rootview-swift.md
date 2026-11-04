---
version: 1
slug: "deconstructed-app-rootview-swift"
primary_target: "Deconstructed/App/RootView.swift"
related_targets: ["Deconstructed/DesignSystem/Theme.swift"]
---

# App shell (all tabs)

Scope: the whole iOS app, every tab and sheet. Mode: Operate. Platform: ios.

Audience and job: diners finding where to eat and logging/ranking visits with explainable scores. Glance-first: a score and where it came from must read in under a second, one-handed, in daylight.

Constraints: native navigation (tab bar, stacks, sheets), Dynamic Type, SF Symbols, light only. Demo labelling stays on every screen. User steer: distinct and non-corporate, sharp in places, not too round, no blurry soft shadows, coloured ground welcome.

## Direction contract

THESIS: A press proof on peach stock. Every restaurant, score and visit is a ruled cream plate with a crisp offset shadow in a second ink. Refuses the incumbent dark glass canvas, soft blurred card shadows, and the grey-list-with-one-tint category default.

OWN-WORLD: Stock #FBE2D4 peach; plates #FFF8F3 ruled 2pt in oxblood ink #2A0E08, 4pt corners; secondary text #6A4A40. Offset shadows are solid, unblurred, 5pt down-right: teal #0E6E6A by default, ochre #D9961B on the screen's key plate, podium rows in their rank ink. Criterion inks tomato #D93A1C, teal, ochre, ultramarine #2E3FA8, plum, moss. Teal is the one interactive tint. SF Pro throughout, heavy for titles and scores; small mono uppercase keys for data labels. Buttons are capsules with a 3pt ink offset that they press into.

STORY: The diner sees rank and score first, reads which criteria made it from the outlined 10-cell bar, taps through to the breakdown, logs a visit with the one teal button.

FIRST VIEWPORT: Large heavy title on peach. Rankings: key plate (RANKED WITH, system, ruled allocation strip, legend) with ochre offset; filter capsules; ranked plates with square rank tile, name + meta, outlined criterion cells, heavy score right. Restaurant: key plate with name, meta, visited tag; teal Log a visit; secondary capsules; score plate with ring and breakdown.

FORM: Design Annual Plates (catalog challenger design-annual-s-plate-section), steered over two rounds to Peach & teal (scheme F, chosen 2026-11-04). seed:336eb3858e01ccc0. Signature move: the crisp offset proof shadow, with the podium casting in its own ink so the top three lift off the list.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
