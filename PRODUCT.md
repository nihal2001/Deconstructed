# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

People who eat out often and want a record they can trust. Two jobs matter equally:

- **Finding where to eat**: searching, browsing the map, checking a place's score and its breakdown, saving places to try.
- **Logging and ranking**: scoring a visit, usually on the phone shortly after the meal, and seeing every place they've been in order.

Friends and the feed are secondary: reading how people you follow scored a place.

## Product Purpose

A native iPhone app for finding, logging and ranking restaurants, where every score out of 10 can be explained. You pick a ranking system, choose a described score for each of its criteria, and the app adds them up. There is nowhere to type an overall number. Success is a score the user (or a friend reading it) can trace back to its parts.

## Positioning

Ratings show their working. A score is always a sum of described criterion scores from a named, versioned ranking system, so an 8 means something specific and can be compared like for like.

## Operating Context

- Used one-handed on an iPhone, in restaurants, on the street and at home planning a meal.
- Logging is a one-question-per-slide flow; each criterion is scored by choosing a described level.
- Rankings tie honestly (1, 2, 2, 4) and are listed A–Z within a tie.
- Map and search use Google Maps and Places in live mode, Apple MapKit in demo mode.

## Capabilities and Constraints

- Swift and SwiftUI, iOS 17+, iPhone only. Liquid Glass on iOS 26+, system materials before that.
- Five tabs: Discover, Map, Rankings, Friends, Profile.
- Ranking systems (General, Fine Dining, Fast Casual, custom) have criteria whose maximums total 10, stored as immutable versions.
- Demo mode with invented restaurants and people, labelled on every screen and listing.
- Google attribution in live mode follows Google's styling.
- The app has one appearance: light only (confirmed 2026-11-04). It does not follow the system dark setting.

## Brand Commitments

- Name: Deconstructed. Subtitle: "Restaurant scores you can explain."
- Voice: plain, specific, unhyped.
- The previous five-colour palette (`Color-scheme.png`) is no longer binding (confirmed 2026-11-04); the visual world is open.

## Evidence on Hand

- Demo seed: 20 invented restaurants and seven invented people (`Deconstructed/Services/Demo/`).
- Screenshots of the previous dark look in `docs/screenshots/`.
- No real user data, testimonials or press.

## Product Principles

1. The tool comes first: legibility and speed of reading a score beat atmosphere.
2. Every number shows where it came from; the breakdown is never hidden more than one tap away.
3. Ties, drafts and demo data are shown honestly, never smoothed over.
4. Finding and logging are equal citizens of the app.

## Accessibility & Inclusion

Text meets 4.5:1 contrast. Colour is never the only cue for a criterion; names and numbers sit beside it. Views use Dynamic Type text styles.
