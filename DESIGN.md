---
name: Deconstructed
description: Restaurant scores you can explain.
colors:
  steel-top: "#EEF2F6"
  steel-bottom: "#DFE5EC"
  glass-plate: "rgba(255, 255, 255, 0.72)"
  glass-edge: "rgba(255, 255, 255, 0.9)"
  sunk-well: "#E3E8EF"
  hairline: "#D5DCE4"
  shadow-ink: "#1E2836"
  ink: "#18202B"
  ink-soft: "#56606C"
  tint: "#1F55E0"
  key-cobalt: "#2452E0"
  key-ocean: "#0B6FB8"
  coral: "#FF4D3A"
  cobalt: "#2F6BFF"
  amber: "#FFB000"
  aqua: "#00C2A8"
  violet: "#8B3DFF"
  pink: "#FF4FA3"
  podium-coral: "#F0402C"
  podium-cyan: "#00B4F0"
  on-podium-cyan: "#06283A"
  positive: "#0A8061"
  saved: "#2A5FE8"
  warning: "#D11F3F"
typography:
  display:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: 1.2
  score:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "34px"
    fontWeight: 800
    lineHeight: 1
    fontFeature: "tnum"
  headline:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.25
  title:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.35
  detail:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  label:
    fontFamily: "SF Pro Rounded, ui-rounded, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.3
rounded:
  badge: "14px"
  control: "16px"
  card: "24px"
  key: "28px"
  capsule: "9999px"
spacing:
  hair: "4px"
  tight: "8px"
  row: "12px"
  base: "16px"
  key: "18px"
  section: "20px"
components:
  button-primary:
    backgroundColor: "{colors.key-cobalt}"
    textColor: "#FFFFFF"
    typography: "{typography.title}"
    rounded: "{rounded.capsule}"
    padding: "13px 18px"
    height: "54px"
  button-primary-on-key:
    backgroundColor: "#FFFFFF"
    textColor: "{colors.tint}"
    rounded: "{rounded.capsule}"
    padding: "13px 18px"
  button-primary-disabled:
    backgroundColor: "{colors.sunk-well}"
    textColor: "{colors.ink-soft}"
    rounded: "{rounded.capsule}"
  button-secondary:
    backgroundColor: "{colors.glass-plate}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.capsule}"
    padding: "12px 14px"
  chip:
    backgroundColor: "{colors.glass-plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
    padding: "0 16px"
    height: "38px"
  chip-selected:
    backgroundColor: "{colors.key-cobalt}"
    textColor: "#FFFFFF"
    rounded: "{rounded.capsule}"
    padding: "0 16px"
    height: "38px"
  card:
    backgroundColor: "{colors.glass-plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.card}"
    padding: "{spacing.base}"
  key-panel:
    backgroundColor: "{colors.key-cobalt}"
    textColor: "#FFFFFF"
    rounded: "{rounded.key}"
    padding: "{spacing.key}"
  input:
    backgroundColor: "{colors.glass-plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "11px 14px"
  tag:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "4px 9px"
  demo-badge:
    backgroundColor: "{colors.sunk-well}"
    textColor: "{colors.ink-soft}"
    rounded: "{rounded.capsule}"
    padding: "2px 7px"
  podium-rank-1:
    backgroundColor: "{colors.podium-coral}"
    textColor: "#FFFFFF"
    rounded: "{rounded.badge}"
    size: "42px"
  podium-rank-2:
    backgroundColor: "{colors.podium-cyan}"
    textColor: "{colors.on-podium-cyan}"
    rounded: "{rounded.badge}"
    size: "42px"
  podium-rank-3:
    backgroundColor: "{colors.cobalt}"
    textColor: "#FFFFFF"
    rounded: "{rounded.badge}"
    size: "42px"
  score-scoop:
    backgroundColor: "{colors.podium-coral}"
    textColor: "#FFFFFF"
    rounded: "{rounded.capsule}"
    size: "54px"
  score-tile:
    backgroundColor: "{colors.glass-plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "10px"
---

# Design System: Deconstructed

## Overview

**Creative North Star: "Glass Gelato, Ocean Neon"**

Deconstructed is a counter of glossy scoops on calm steel. Every surface is frosted glass: a translucent white body over ultra-thin material, a bright band of gloss across its top half, a one-point white edge, and a soft diffuse shadow underneath. Shapes are very round and use continuous corners, and every glyph is SF Pro Rounded so the type matches the forms. The steel ground is deliberately quiet, so colour can be spent only where it means something.

Colour carries emphasis, not decoration. Each screen has exactly one key panel, a cobalt-to-ocean glass slab holding the thing the screen is about (the ranking system on Rankings, the restaurant on its profile). The same key gradient fills the one primary action and the selected chip. The podium (ranks 1 to 3) is coral, cyan and cobalt scoops. Criteria keep their own scoop colour, by position, everywhere their points appear. Everything else is ink on glass.

The world moves on springs. Scores fill in point by point, ring arcs sweep round, and anything tappable squishes and springs back with a light haptic. Reduce Motion removes the fills and sweeps. The app is light only, and the previous hard-ruled press-proof look and flat grey category lists are rejected.

**Key Characteristics:**
- Frosted glass panels on a steel gradient, glossy top band, bright white edge
- One cobalt-to-ocean key panel per screen; the same gradient marks the primary action
- Coral, cyan, cobalt podium scoops; six criterion scoop colours by position
- SF Pro Rounded everywhere, heavy numerals for scores
- Soft diffuse shadows only, tinted by the fill they sit under
- Spring motion: squish on press, pop on select, point-by-point fills

## Colors

A calm steel neutral field with one cobalt key voice and a small family of saturated gelato scoops reserved for scores and ranks.

### Primary
- **Key Cobalt to Ocean** (key-cobalt to key-ocean, top-leading to bottom-trailing): the key panel, the primary button and the selected chip. Both ends hold white text at 4.5:1 or better. Content inside the key panel renders in the dark colour scheme, so ink, glass and wells turn white automatically.
- **Interactive Cobalt** (tint): the one interactive colour for links, navigation items, the selected tab label, the primary button's text when it sits on the key panel, and empty-state symbols. Text-safe on glass and steel.

### Secondary
- **Podium Scoops**: rank 1 is coral (#FF7A66 to podium-coral), rank 2 is cyan (#5FDCFF to podium-cyan, with on-podium-cyan text), rank 3 is cobalt (#5B8CFF to cobalt). Ranks below 3 get a steel scoop (#EEF1F5 to #D6DCE4) with ink-soft text. Each podium scoop casts a glow in its own hue.

### Tertiary
- **Criterion Scoops** (coral, cobalt, amber, aqua, violet, pink, then the same six at 60% opacity): one colour per criterion by position, applied to score-bar pills, ring arcs, allocation strips, legend dots and selected score tiles. Avatars draw from the same six.

### Neutral
- **Steel Top / Steel Bottom** (steel-top, steel-bottom): the screen gradient behind everything; steel-top also backs the map before tiles load.
- **Glass Plate** (glass-plate): the body of every panel, card, secondary button, unselected chip and input.
- **Glass Edge** (glass-edge): the bright one-point stroke round every glass panel and control.
- **Sunk Well** (sunk-well): unselected tracks, the disabled primary button, the demo badge, and the community-score well.
- **Hairline** (hairline): quiet input and score-tile borders.
- **Ink / Ink Soft** (ink, ink-soft): primary and secondary text. Ink also fills the map cluster badge.
- **Status**: positive for done and visited, saved for want-to-try, warning for problems.

### Named Rules
**The One Key Panel Rule.** A screen gets one key panel and one primary action. The key gradient appears nowhere else except the selected chip; if two things on a screen are cobalt slabs, one of them is wrong.

**The Scoop Follows the Criterion Rule.** A criterion's colour is fixed by its position and travels with it to every bar, ring, strip and tile. Colour is never the only cue: the criterion's name and number always sit beside it.

**The Scoops Are Fills Rule.** Criterion and podium colours are fills under white or navy text, not text colours on glass. Text on glass is ink, ink-soft or tint.

## Typography

**Display Font:** SF Pro Rounded (system `.rounded` design, applied app-wide)
**Body Font:** SF Pro Rounded
**Label Font:** SF Pro Rounded, semibold caption

**Character:** One rounded family throughout, so every glyph shares the soft geometry of the glass. Hierarchy comes from weight and Dynamic Type style, not from a second face. All sizes are iOS points at the default content size and scale with Dynamic Type.

### Hierarchy
- **Display** (bold, 34pt large title): navigation large titles and the restaurant name in its key panel.
- **Score** (heavy, monospaced digits): the total in score badges (headline, title2 or large title by size) and inside the score ring (40% of the ring diameter). The denominator follows in regular weight and ink-soft.
- **Headline** (semibold, 20pt title3): section titles, the ranking-system picker, score-grid numerals.
- **Title** (semibold, 17pt headline): row names, the primary button label, inline navigation titles.
- **Body** (regular to semibold, 15pt subheadline): row text, chip and secondary-button labels, breakdown rows.
- **Detail** (regular, 13pt footnote): subtitles, level descriptions, section detail lines.
- **Label** (semibold, 12pt caption): tags and data keys such as "Ranked with"; demo badge at 11pt caption2. Sentence case, no tracking.

### Named Rules
**The Heavy Number Rule.** A score's number is the heaviest thing in its group; its "/10" is regular and soft, and the system name always travels with it.

## Layout

Single-column, glance-first stacks on an iPhone width with native navigation: a five-tab bar, push stacks and sheets. Content sits in glass cards 16pt in from the screen edge with a 16pt base gutter and internal padding (18pt in the key panel). Spacing runs on a small set of steps: 4 inside tags and badges, 8 between chips and inline items, 10 to 12 between stacked lines and rows, 14 between a ring and its badge, 20 between larger groups. Chips and legends wrap onto further lines at large Dynamic Type sizes rather than truncating. Score tiles sit in a two-column grid; numeric score choices use an adaptive grid with a 48pt minimum cell.

## Elevation & Depth

Depth is layered glass lifted by soft, diffuse shadows. Nothing casts a hard or offset shadow. Neutral glass casts a cool shadow-ink shadow; coloured fills cast a glow in their own hue at higher opacity. On iOS 26 and later the floating controls (tab bar, toasts, bars) use Liquid Glass; earlier versions fall back to ultra-thin material with the same gloss, bright edge and soft shadow.

### Shadow Vocabulary
- **Panel** (shadow-ink at 10%, blur 22, y 10): every glass card and secondary button.
- **Floating glass** (shadow-ink at 12%, blur 22, y 10): pre-iOS 26 Liquid Glass fallback, toasts.
- **Key panel glow** (cobalt at 32%, blur 24, y 14): under the key panel only.
- **Primary glow** (cobalt at 35%, blur 14, y 8; black at 15% when on the key panel): the primary button.
- **Scoop glow** (the scoop's own hue at 35%, blur 8 to 10, y 4 to 5; 8% below the podium): podium rank and score scoops, avatars, selected chips and selected score tiles.
- **Tab edge** (shadow-ink fading from 0 to 8% over 10pt): replaces the hairline above the pre-iOS 26 tab bar.

### Named Rules
**The Diffuse Shadow Rule.** Shadows are wide, soft and fall straight down. A shadow takes the colour of what casts it: steel ink under glass, the scoop's hue under a scoop.

**The Gloss Band Rule.** Every glass or glossy surface carries a white band from its top edge fading out by 55% of its height (60% strength on panels, about 45% on scoops and buttons, 16% on the key panel).

## Shapes

Very round, always continuous-cornered. Panels and cards are 24pt, the key panel 28pt, controls, inputs and score tiles 16pt, rank badges 14pt. Buttons, chips, tags, the demo badge, score-bar pills and toasts are capsules; score scoops and avatars are circles. Score bars are closed-up glossy pills with 3pt gaps, one per earned point, so a bar's length is its total; ring arcs use round caps with a gap between criteria. Every glass shape carries a one-point bright white edge.

## Components

### Buttons
Glossy, springy, never flat.
- **Shape:** capsule (rounded.capsule), full width.
- **Primary:** the key gradient with white headline text, 13pt vertical and 18pt horizontal padding, white edge at 45%, primary glow. One per screen.
- **On the key panel:** the primary turns to white glass with tint text and a soft black shadow, so it still stands out against cobalt.
- **Disabled:** sunk-well fill, ink-soft text, no glow.
- **Secondary:** a glass capsule with ink semibold subheadline text and the panel shadow, for actions beside the primary.
- **Press:** every button and tappable tile squishes to 94% on the press spring and springs back; the primary adds a light impact haptic.

### Chips
- **Style:** 38pt-tall glass capsules with 16pt horizontal padding, ink semibold subheadline text, gloss band and bright edge.
- **State:** the selected chip fills with the key gradient and white text and pops on the pop spring with a selection haptic. Chips stand in for segmented controls and wrap at large type sizes.

### Tags
- **Style:** capsules in caption semibold; the tone colour at 13% behind tone-coloured text (10% for neutral). Solid tags fill with the tone colour, add a gloss band and use white text.
- **Demo badge:** quiet by design, sunk-well fill and ink-soft caption2 text, opaque in both schemes so it reads on the key panel too. It appears beside every demo name.

### Cards / Containers
- **Corner Style:** 24pt continuous.
- **Background:** glass plate over ultra-thin material with the gloss band.
- **Shadow Strategy:** panel shadow; a card may tint its glow, or drop it.
- **Border:** one-point glass edge.
- **Internal Padding:** 16pt base (12pt for dense scoring cards).
- **Community score:** a sunk well at 70% instead of glass, so it never reads as your own score.

### Key Panel
The cobalt-to-ocean slab that opens each primary screen (Rankings, Discover, Restaurant, Profile, Sign in). 28pt corners, 18pt padding (24 on sign-in), gloss at 16%, white edge at 40%, key panel glow. Its contents render in the dark colour scheme, so text and glass inside it turn white without per-view overrides.

### Inputs / Fields
- **Style:** glass plate in a 16pt continuous rectangle, hairline border, 11pt vertical and 14pt horizontal padding. System search fields are white at 70%.
- **Focus:** the system cursor and tint; no extra ring.

### Navigation
- **Style:** native navigation bars and a five-tab bar. Titles are SF Pro Rounded, bold 34pt large and semibold 17pt inline, in ink.
- **Selected tab:** on iOS 26 and later the system Liquid Glass tab bar with the tint. Before that, frosted ultra-thin bars with no hairline, a soft shadow fade above the tab bar, and the selected icon sitting white on a glossy cobalt capsule (48 by 30pt, #3A6BF0 to key-ocean) with its label in tint below.

### Score Bar, Ring and Allocation Strip (signature)
The rubric made visible. The score bar is one glossy capsule per earned point in its criterion's colour, closed up with empty slots holding the remaining width so lengths compare across rows; points spring in one after another (fill spring, 35ms stagger capped at 0.4s). The score ring bends the same points into round-capped arcs with a gloss line, sweeping round 0.12s apart, with the heavy total in the middle over a faint sunk-well track. The allocation strip shows each criterion's maximum as a glossy capsule with a dot-and-name legend below.

### Podium Rows
Rankings rows are glass cards holding a 42pt rank badge (14pt corners) and a 54pt round score scoop, both glossy and coloured coral, cyan or cobalt for ranks 1 to 3, steel below, with their own glow. Tied ranks share a scoop and say "tied" beneath it. Badges pop in on appear.

### Score Tiles
Choosing a level is tapping a 16pt-cornered glass tile with a hairline border. Selected tiles tint to their criterion colour at 14%, take a two-point border in that colour, glow, and pop to 103% (numeric grid cells fill solid and pop to 108%). Each selection fires a selection haptic.

### Map Pins
Round badges, 32pt (44pt when selected) with a white ring and a bold white SF Symbol: cobalt for want-to-try, coral for search results, green for visited. A selected pin inverts to white with the pin's colour as ring and glyph, and every pin glows in its own colour. The Google basemap is a pale steel world with cobalt-tinted water, aqua parks, and coral- and violet-tinted major roads, with points of interest and transit hidden.

### Motion
- **press** (spring 0.28s, bounce 0.45): squish on every tap.
- **pop** (spring 0.4s, bounce 0.35): selection and state changes.
- **fill** (spring 0.5s, bounce 0.3, 35ms stagger, max 0.4s delay): score points filling in.
Reduce Motion shows finished bars and rings with no fill or sweep.

## Do's and Don'ts

### Do:
- **Do** put every surface on the steel gradient and build panels as glass: glass plate, gloss band, one-point glass edge, panel shadow.
- **Do** give each screen exactly one key panel and one key-gradient primary action.
- **Do** colour a criterion by its position everywhere it appears, and always print its name and points beside the colour.
- **Do** use SF Pro Rounded for everything, through Dynamic Type text styles, with heavy monospaced digits for scores.
- **Do** use the Motion springs (press, pop, fill) for anything that moves, and honour Reduce Motion.
- **Do** keep the demo badge beside every demo name, quiet and opaque.

### Don't:
- **Don't** cast hard or offset shadows; every shadow is soft, diffuse and falls straight down.
- **Don't** add a second key panel, or use the key gradient for anything but the key panel, primary action and selected chip.
- **Don't** set text in criterion or podium scoop colours on glass; scoops are fills under white or navy text.
- **Don't** use square corners or circular-arc corners on panels; use the radius scale with continuous corners.
- **Don't** fall back to flat grey system lists or segmented controls; use glass cards and chips.
- **Don't** add a dark appearance; the app is light only.
