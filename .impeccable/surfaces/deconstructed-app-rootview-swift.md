---
version: 1
slug: "deconstructed-app-rootview-swift"
primary_target: "Deconstructed/App/RootView.swift"
related_targets: ["Deconstructed/DesignSystem/Theme.swift"]
---

# App shell (all tabs)

Scope: the whole iOS app, every tab and sheet. Mode: Operate. Platform: ios.

Audience and job: diners finding where to eat and logging/ranking visits with explainable scores. Glance-first, one-handed, in daylight.

Constraints: native navigation (tab bar with SF Symbol icons, stacks, sheets), Dynamic Type, light only, Reduce Motion honoured. Demo labelling stays on every screen. User steer (2026-11-05): softer, rounder, easier to look at, more animated; contrasting colour to highlight what matters; soft diffuse shadows; pep and steel; glossy and glass-like; calm background; score bars show only earned points, closed up.

## Direction contract

THESIS: Glass gelato. Glossy frosted panels, very round, on calm steel; colour is spent on emphasis: the key panel, the podium, the primary action. Refuses the previous hard-ruled press proof and the flat grey category list.

OWN-WORLD: Steel gradient #EEF2F6→#DFE5EC. Panels white 72% over ultra-thin material, a top gloss band, a bright 1pt white edge, soft diffuse shadows, 24pt corners (28 on the key panel, 16 on controls, 14 on badges). Key panel and primary actions: cobalt→ocean gradient #2452E0→#0B6FB8 with gloss. Criteria scoops: coral #FF4D3A, cobalt #2F6BFF, amber #FFB000, aqua #00C2A8, violet, pink. Podium badges: coral, cyan (navy text), cobalt gradients. SF Pro Rounded throughout. Tint #1F55E0. Tab bar pre-26: frosted with a cobalt capsule behind the selected icon.

STORY: The diner sees their ranking with glossy podium scoops, reads the earned-points bar, taps through to a restaurant whose score ring and bar fill in, logs a visit by tapping springy score tiles.

FIRST VIEWPORT: Rankings: large rounded title; cobalt glass key panel (Ranked with, system, criterion allocation, legend); glass filter chips; glass rows with rank scoop, name, earned-points bar, round score scoop. Restaurant: cobalt key panel with name and visited tag; cobalt Log a visit; glass secondary actions; score panel with ring.

FORM: Gelato Counter (my own grounded pick), raised by the user over four steer rounds to Glass Gelato, Ocean Neon scheme (user's choice, 2026-11-05). seed:c5af56b99e9922c2. Signature move: scores fill in point by point, each glossy pill springing out in turn, and the ring sweeps round; every tap squishes with a light haptic.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
