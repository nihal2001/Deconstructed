---
name: Deconstructed
description: Restaurant scores you can explain.
colors:
  stock: "#FBE2D4"
  plate: "#FFF8F3"
  fill: "#F6D3C2"
  hairline: "#E7C3B2"
  ink: "#2A0E08"
  ink-soft: "#6A4A40"
  teal: "#0E6E6A"
  tomato: "#D93A1C"
  ochre: "#D9961B"
  ultramarine: "#2E3FA8"
  plum: "#8A2D63"
  moss: "#44701A"
  warning: "#B52E12"
  on-tint: "#FFFFFF"
typography:
  large-title:
    fontFamily: "SF Pro (system), Dynamic Type largeTitle"
    fontSize: "34pt"
    fontWeight: 800
    letterSpacing: "-0.6pt"
  title:
    fontFamily: "SF Pro (system), Dynamic Type title"
    fontSize: "28pt"
    fontWeight: 800
  title3:
    fontFamily: "SF Pro (system), Dynamic Type title3"
    fontSize: "20pt"
    fontWeight: 600
  headline:
    fontFamily: "SF Pro (system), Dynamic Type headline"
    fontSize: "17pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro (system), Dynamic Type subheadline"
    fontSize: "15pt"
    fontWeight: 400
  footnote:
    fontFamily: "SF Pro (system), Dynamic Type footnote"
    fontSize: "13pt"
    fontWeight: 400
  label:
    fontFamily: "SF Pro (system), Dynamic Type caption"
    fontSize: "12pt"
    fontWeight: 600
  data-key:
    fontFamily: "SF Mono (system monospaced), Dynamic Type caption2"
    fontSize: "11pt"
    fontWeight: 500
    letterSpacing: "0.8pt"
rounded:
  stamp: "2px"
  plate: "4px"
  capsule: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  row: "14px"
  lg: "16px"
  xl: "28px"
components:
  plate:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.plate}"
    padding: "16px"
  plate-row:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.plate}"
    padding: "14px"
  button-primary:
    backgroundColor: "{colors.teal}"
    textColor: "{colors.on-tint}"
    typography: "{typography.headline}"
    rounded: "{rounded.capsule}"
    padding: "12px 18px"
    height: "52px"
  button-primary-disabled:
    backgroundColor: "{colors.fill}"
    textColor: "{colors.ink-soft}"
    rounded: "{rounded.capsule}"
  button-secondary:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
    padding: "11px 14px"
  button-secondary-pressed:
    backgroundColor: "{colors.fill}"
    textColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
  chip:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
    padding: "0 14px"
    height: "36px"
  chip-selected:
    backgroundColor: "{colors.teal}"
    textColor: "{colors.on-tint}"
    rounded: "{rounded.capsule}"
    padding: "0 14px"
    height: "36px"
  tag:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.stamp}"
    padding: "3px 7px"
  tag-warning:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.warning}"
    typography: "{typography.label}"
    rounded: "{rounded.stamp}"
    padding: "3px 7px"
  input:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.plate}"
    padding: "10px 12px"
  rank-tile:
    backgroundColor: "{colors.plate}"
    textColor: "{colors.ink}"
    rounded: "{rounded.plate}"
    size: "40px"
---

# Design System: Deconstructed

## Overview

**Creative North Star: "The Press Proof"**

Every restaurant, score and visit is a ruled cream plate laid on warm peach stock, and every plate casts a crisp offset shadow in a second ink, as if a colour had been printed slightly out of register. The look is a proof sheet, not a glass dashboard: flat colour, hard rules, no blur. The density follows a list you scan: plates stack at a steady rhythm, the score sits heavy at the right edge, and the criteria that made it read left to right as outlined cells.

Colour carries meaning. Six criterion inks belong to the score data, teal is the one colour you can tap, and a few state colours mark visited, saved and warnings. Everything else is oxblood ink on cream and peach. San Francisco carries the whole app, set heavy and tracked in for titles and scores, so Dynamic Type and native navigation keep working while the proof does the talking.

The system refuses soft blurred card shadows, the dark glass canvas the app used to have, and the grey-list-with-one-tint look common in this category. The system tab bar and floating map controls stay on Liquid Glass on iOS 26. That is the platform's own layer above the proof, not part of the proof.

**Key Characteristics:**
- Peach stock ground, cream plates, 2pt oxblood rule, 4pt corners.
- Solid, unblurred offset shadows down and to the right, in a second ink.
- Six criterion inks, one interactive teal, everything else ink.
- SF Pro throughout: heavy titles and scores, small mono uppercase keys over data values.
- Capsule buttons that press down onto their own shadow.
- Light only.

## Colors

A warm two-paper palette (peach stock, cream plate) in oxblood ink, with saturated printer's inks kept for data and action.

### Primary
- **Proof Teal** (teal): the one interactive colour. Primary buttons, selected chips, links, the tab bar tint, the empty-state symbol. It is also the default offset shadow under plates and the second podium ink.

### Secondary (the criterion inks)
- **Tomato** (tomato): criterion 1 and the first podium place. Search-result pins on the map.
- **Proof Teal** (teal): criterion 2.
- **Ochre** (ochre): criterion 3, and the shadow under the key plate of each screen. No podium place uses it.
- **Ultramarine** (ultramarine): criterion 4, the third podium place, and the "saved / want to try" state.
- **Plum** (plum): criterion 5.
- **Moss** (moss): criterion 6, and the "done, visited, balanced" state.

Criteria 7 to 12 reuse the six inks at 55% opacity. A criterion keeps its ink everywhere its score appears: bar, ring, breakdown square, allocation strip, level grid.

### Tertiary
- **Proof Red** (warning): problems, things that need attention, and the Demo stamp. Deeper than tomato so it stays text-safe.

### Neutral
- **Peach Stock** (stock): the ground behind every screen, the pre-iOS 26 bars, and the map background before tiles load.
- **Cream Plate** (plate): every content panel, secondary buttons, unselected chips, inputs, search fields.
- **Sunk Peach** (fill): sunk wells. Pressed secondary buttons, disabled primary buttons, tracks.
- **Hairline Blush** (hairline): quiet dividers inside a plate and disabled rules.
- **Oxblood Ink** (ink): all primary text and the rule round every plate and control. Also the shadow under buttons and map pins.
- **Soft Ink** (ink-soft): secondary text, metadata, denominators, data keys, unselected tab items.

### Named Rules
**The One Tap Colour Rule.** Teal is the only colour that means "tappable". Criterion inks never style a control unless that control is choosing a score for that criterion.

**The Ink Follows the Criterion Rule.** A criterion is coloured by its position everywhere, and colour is never the only cue: its name and number sit beside it.

**The Text-Safe Rule.** Text on the cream plate is ink, soft ink, teal, ultramarine, plum, moss or warning, all 4.5:1 or better there. On the peach stock, moss drops below 4.5:1, so moss text sits on a plate. Tomato and ochre are for fills and rules, never running text. On a solid ink fill, pick ink or white by luminance.

## Typography

**Display Font:** SF Pro (system), scaled by Dynamic Type
**Body Font:** SF Pro (system)
**Label/Mono Font:** SF Mono (system monospaced), for data keys only

**Character:** One grotesque for everything. Weight does the work: heavy for titles and scores, semibold for names, regular for reading. The only contrast in voice is a small monospaced key over a data value.

### Hierarchy
- **Large Title** (heavy, 34pt, −0.6pt kerning): navigation large titles on every tab, ink on peach.
- **Title** (heavy, 28pt, −1pt tracking on scores): the score on a ranked row; the large score badge at 34pt.
- **Title 3** (semibold, 20pt): section titles, the system name on a key plate, empty-state titles.
- **Headline** (semibold, 17pt): restaurant names in rows, primary button labels, level numbers.
- **Body** (regular or semibold, 15pt subheadline): row text, breakdown rows, chip and secondary button labels.
- **Footnote** (regular, 13pt): metadata, criterion descriptions, section details.
- **Label** (semibold, 12pt caption): tags and stamps, legend entries.
- **Data Key** (medium, 11pt mono, 0.8pt tracking, uppercase): a key directly over or beside the value it names ("RANKED WITH" over the system, "SEARCHING NEAR" over the area, "SYSTEM" beside the system name).

### Named Rules
**The Heavy Number Rule.** Scores are heavy with monospaced digits; the "/10" denominator is a size smaller, regular weight, in soft ink. The system name always travels with the number.

**The Key Over Value Rule.** Mono uppercase is only ever a data key naming the value next to it. It is never a section heading, a kicker or a decorative label above a title.

## Layout

Single-column scrolling stacks on peach, in native navigation stacks, tabs and sheets. Screen and plate padding is 16pt; dense list rows use 14pt; small inline plates use 12pt. Elements inside a plate step 4, 8, 12 or 14pt apart, and plates stack with room for their 5pt shadow. Chips and tags wrap with a flow layout so they survive large Dynamic Type sizes. Floating footers pin the main action under scrolling content; on iOS 26 the content fades out beneath them, earlier versions get a peach bar under a 1.5pt ink rule.

## Elevation & Depth

Depth is printed, not lit. There are no blurred shadows anywhere. A plate lifts off the stock with a solid copy of its own shape shifted down and right, in a second ink. The offset is reserved space: plates pad their trailing and bottom edges by the offset so the shadow never collides with neighbours. Liquid Glass on iOS 26 is the one exception, kept for the system tab bar, floating map controls and toasts.

### Shadow Vocabulary
- **Plate offset** (solid teal, 5pt down-right, no blur): the default under any plate.
- **Key plate offset** (solid ochre, 6pt down-right, no blur): the one most important plate on a screen (Rankings scope, restaurant header, Discover's lead plate, profile header, sign-in).
- **Podium offset** (solid rank ink, 5pt): ranked rows 1 to 3 cast in tomato, teal and ultramarine. Rows below the podium cast nothing.
- **Button offset** (solid ink, 3pt primary / 2pt secondary): sits under capsule buttons; pressing moves the button onto it.
- **Pin offset** (solid ink, 2pt, no blur): under map pin badges.
- **Glass fallback offset** (solid ink, 3pt): under floating controls before iOS 26.

### Named Rules
**The No Blur Rule.** Every shadow is a solid, unblurred offset. A blurred or ambient shadow does not belong in this world.

**The One Key Plate Rule.** Each screen has at most one ochre-offset plate. Long lists drop the shadow on ordinary rows so the plates that do cast one mean something.

## Shapes

Small, firm corners and hard rules. Plates, rank tiles and inputs use 4pt continuous corners. Tags and stamps use 2pt corners. Score cells, level choices and allocation strips are square. Buttons and chips are full capsules; avatars and map pins are circles. Rules are oxblood ink: 2pt round plates, rank tiles and primary buttons, 1.5pt round secondary buttons, chips, tags and inputs, 1pt round score cells. Unscored criterion cells are dashed (2 on, 2 off). The community score, which is not yours, is a dashed 1.2pt soft-ink outline with no fill and no shadow.

## Components

### Buttons
Tactile and printed: they press into their own shadow.
- **Shape:** full capsule (999px).
- **Primary:** teal fill, white headline label, 2pt ink rule, 52pt tall, full width, 3pt solid ink offset. One per screen, for the main action ("Log a visit").
- **Pressed:** the button moves 3pt down-right onto its shadow (snappy, 0.12s).
- **Disabled:** sunk peach fill, soft ink label, hairline offset.
- **Secondary:** cream plate fill, ink semibold label, 1.5pt ink rule, 2pt ink offset; pressed fills sunk peach and moves 2pt. Takes an optional label tint.
- **Inline text buttons** ("Change", "Try again"): plain teal semibold text.

### Chips
- **Style:** capsule, 36pt tall, 14pt side padding, 1.5pt ink rule, semibold 15pt label.
- **State:** unselected is cream plate with ink text; selected is teal with white text. Used as a segmented control and wraps at large type sizes. Filter menus use the same capsule with a chevron.

### Tags (stamps)
- **Style:** a ruled stamp, 2pt corners, 1.5pt rule in the tone's ink, cream fill, semibold 12pt label, optional small SF Symbol.
- **Tones:** neutral (ink), accent (teal), saved (ultramarine), positive (moss), warning (proof red). `solid` fills with the tone and sets white text. The Demo stamp is a warning tag and appears on every demo listing.

### Cards / Containers (plates)
- **Corner Style:** 4pt continuous.
- **Background:** cream plate on peach stock.
- **Shadow Strategy:** see Elevation. Teal by default, ochre on the key plate, rank ink on the podium, none on ordinary list rows.
- **Border:** 2pt oxblood ink.
- **Internal Padding:** 16pt, 14pt for ranked rows, 12pt for compact inline plates.

### Inputs / Fields
- **Style:** cream plate well, 4pt corners, 1.5pt ink rule, 10pt by 12pt padding. System search fields are recoloured to cream plate.
- **Focus:** the system caret and selection in teal.

### Navigation
- **Style:** native tab bar and navigation stacks. Large titles heavy 34pt ink, inline titles bold 17pt ink, tint teal. On iOS 26 the bars are Liquid Glass; before that the navigation bar is peach stock and the tab bar cream plate, each edged with an ink rule, unselected items in soft ink.

### Score Bar (signature)
Ten square cells in one row, grouped by criterion with a 3pt gap between criteria. Earned points are solid in the criterion's ink; the rest are outlined in it; an unscored criterion is dashed. 12pt tall by default, 8pt inside ranked rows.

### Score Ring and Badge
The same ten points bent into a ring of butt-capped arcs (earned at full ink, the rest at 20%), with the heavy total in the middle; arcs sweep in on appear unless Reduce Motion is on. The badge reads "8/10 · General": heavy number, smaller regular denominator, system name in soft ink.

### Ranked Row
A plate with a 40pt square rank tile (tomato, teal or ultramarine on the podium with ink or white by luminance, cream below it, 2pt ink rule), "tied" under shared ranks, name and meta, the score bar, and the heavy score on the right.

### Level Choice
A grid of square, ruled choices for scoring one criterion: a square numeral cell outlined in the criterion's ink, the level name, and its description. Selected fills the cell with the ink, washes the choice at 12% of the ink and thickens its rule to 2.5pt.

### Allocation Strip
A 10pt strip divided by criterion maximums, in the criterion inks, inside a 1.5pt ink rule, with a wrapping legend of 8pt squares, names and points.

### Map Pins
Circular badges: the pin's ink ringed in white (ultramarine saved, teal visited, tomato result), with a 2pt solid ink offset. Selected is larger (44pt) and inverted. The basemap is the palette laid over cream and flattened: peach land, pale teal water, pale moss parks, white local roads, ochre-tinted major roads, ink labels.

## Do's and Don'ts

### Do:
- **Do** set every content panel as a cream plate with a 2pt ink rule and 4pt corners on peach stock.
- **Do** lift plates with a solid, unblurred offset: teal 5pt by default, ochre 6pt for the one key plate on a screen, the rank ink for podium rows.
- **Do** reserve teal for things you can tap, and keep it to one primary button per screen.
- **Do** colour a criterion by its position everywhere it appears, with its name and number beside the colour.
- **Do** set scores heavy with monospaced digits and keep the system name with the number.
- **Do** use Dynamic Type text styles and SF Symbols, and let chips and tags wrap.

### Don't:
- **Don't** use blurred, ambient or soft shadows.
- **Don't** use mono uppercase as a section heading or a kicker above a title; it only names a data value.
- **Don't** set running text in tomato or ochre; they are below 4.5:1 on the plate.
- **Don't** put a shadow on every plate in a long list; ordinary rows drop it.
- **Don't** add a dark appearance; the app is light only.
- **Don't** use criterion inks for chrome, navigation or general actions.
