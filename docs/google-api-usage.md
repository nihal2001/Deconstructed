# Google Maps Platform: usage, cost and policy notes

How Deconstructed uses Google, what each action costs, and which rules shaped the design.

Prices and policies were checked on **7 October 2026** against the pages linked at the bottom. Google changes both; re-check before launch and whenever you change a field mask.

## What each user action sends

| User action | Request | Billing SKU | Fields requested |
|---|---|---|---|
| Typing in search (3+ characters, after a 350 ms pause) | Autocomplete (New) with a session token | Autocomplete Requests, or free when the session ends in a details request | – |
| Tapping a suggestion | Place Details with the same session token, which closes the session | Place Details Pro | ID, name, coordinate, address, types, address components |
| Pressing Search on the keyboard | Text Search (New) | Text Search Pro | same six fields |
| Tapping **Search this area** | Nearby Search (New), max 20 results | Nearby Search Pro | same six fields |
| Opening a result from a search | none: the search already returned what the profile header needs | – | – |
| Tapping **Show hours and contact details** | Place Details | Place Details Enterprise | adds price level, website, phone, current opening hours |
| Map tab drawing a saved or visited pin with no fresh coordinate | Place Details | Place Details Essentials | ID, coordinate |
| Tapping a saved pin, or a row in Rankings, Saved or the feed whose name isn't in memory | Place Details | Place Details Pro | the six core fields |
| Panning or zooming the map | **nothing** | – | – |

Never requested: photos, ratings, review text, editorial summaries. Photos in the app are the user's own.

The code that enforces this:

- `DiscoveryModel` owns debounce, minimum length, session lifetime and the rule that `mapMoved` sends nothing.
- `GooglePlacesProvider` holds the three field masks (`location`, `core`, `extended`), one per SKU tier.
- `AppModel.ensurePlace` keeps loaded places in memory for the launch, shares one request between concurrent callers, and never re-requests a level it already has.
- `MeteredPlacesProvider` and `RequestMonitor` count and cap every request.

## Prices at the time of writing

| SKU | Free per month | Then, per 1,000 |
|---|---|---|
| Maps SDK for iOS (map loads) | unlimited | – |
| Autocomplete Requests | 10,000 | $2.83 |
| Autocomplete session ending in Place Details | unlimited | – (the details request is billed) |
| Place Details Essentials | 10,000 | $5.00 |
| Place Details Pro | 5,000 | $17.00 |
| Place Details Enterprise | 1,000 | $20.00 |
| Text Search Pro | 5,000 | $32.00 |
| Nearby Search Pro | 5,000 | $32.00 |

Free allowances are per SKU, per billing account, per month. The first paid tier is shown; volume tiers are cheaper.

## Storage and caching rules, and what they forced

Google's terms allow this app to keep very little:

> The 30-day coordinate rule below is from the Places section of the Service Specific Terms. I could read it in the 2023–2025 versions; the current page was only partly retrievable when I checked, so confirm the wording there before relying on it.

- **Place IDs may be stored indefinitely.** They are the only Google value in the database (`restaurants.provider_place_id`).
- **Latitude and longitude may be cached for up to 30 consecutive days.** `restaurants.lat/lng/location_cached_at` hold them; `app_private.purge_stale_restaurant_locations()` clears anything older, and the client independently ignores a stored coordinate past 30 days (`RestaurantRef.freshCoordinate`).
- **Everything else (name, address, types, hours) may not be stored.** It lives in memory for the current launch only and is never written to Supabase or to disk.

Consequences worth knowing:

1. **Names are fetched, not stored.** Every list that shows a restaurant the user saved or rated needs a Place Details Pro request per place, once per launch. A user with 40 ranked restaurants who opens Rankings costs 40 Pro requests that launch, about $0.68 beyond the free allowance. This is the app's main recurring cost. Options if it becomes a problem are listed below.
2. **Saved-place maps are cheap.** Pins need only a coordinate. With the 30-day cache that is at most one Essentials request per saved place per month, and none in the first 30 days for places saved from a search (the search's coordinate is stored at save time). The name is fetched only when a pin is tapped.
3. **Visit history survives listing changes.** Visits reference the app's own restaurant ID. If Google retires a place ID, the visit, scores and photos remain; the row shows "Name unavailable" and the profile explains that the listing is gone.
4. **User content is separate.** Notes, dishes, scores, photos and ranking systems are in their own tables and never mixed into provider records.

## Rough monthly estimate

For one fairly active user: 20 search sessions, 8 "Search this area", 30 app launches, 25 saved or rated places, 5 "show hours".

| Flow | Requests | SKU |
|---|---|---|
| Autocomplete sessions that end in a pick (14 of 20) | 14 details | Details Pro |
| Autocomplete sessions abandoned (6, about 4 keystroke requests each) | 24 | Autocomplete |
| Keyboard searches | 6 | Text Search Pro |
| Search this area | 8 | Nearby Search Pro |
| Names for lists (25 places, on perhaps 10 of 30 launches) | 250 | Details Pro |
| Pin coordinates past 30 days | up to 25 | Details Essentials |
| Hours and contact | 5 | Details Enterprise |

Roughly 264 Details Pro, 14 Search Pro, 24 Autocomplete, 25 Essentials and 5 Enterprise requests. About 19 such users fit inside the monthly free allowance for Details Pro; past that, each costs about $4.50 a month in Details Pro and under $0.50 for everything else. **Name lookups dominate.**

## If name lookups get expensive

In order of effort:

1. Load names only for rows that scroll into view (they already load per row; lists are not paginated yet, so long lists load every name).
2. Let users give a place their own label when saving it. A user-typed label is user content and can be stored.
3. Use Google's Place Details UI Kit components for rows, which have their own pricing.
4. Add a second provider behind `PlacesProvider` whose terms allow storing names.

## Attribution and display

- Places content is shown on a Google map. The live Map tab uses the Maps SDK for iOS; `GoogleMapView` pads the map so the Google logo is never covered by the preview card.
- Where listing content appears off the map (search results, suggestions, the restaurant profile), `ProviderAttribution` shows the text "Google Maps" in a neutral style, plus any third-party attribution the place returns.
- The demo has no key and no Google content, so it uses Apple's map and labels every listing as demo.
- Profile → About and attributions links Google's terms and privacy policy and shows the SDK's open-source licences.
- **Still required before release:** your own Terms of Use and Privacy Policy that incorporate Google's terms and disclose use of Google Maps Platform. See the README's unfinished list.

## Quotas, limits and monitoring

Set these in Google Cloud Console; the app cannot.

1. **APIs & Services → Enabled APIs**: enable *Maps SDK for iOS* and *Places API (New)* only.
2. **Credentials → your key**: Application restriction *iOS apps* with your bundle ID; API restriction limited to those two APIs.
3. **Places API (New) → Quotas**: set a per-day cap on each of Text Search, Nearby Search, Place Details and Autocomplete. Start low (for example 500 a day each) and raise it deliberately.
4. **Billing → Budgets & alerts**: a monthly budget with alerts at 50%, 90% and 100%.
5. Consider App Check for the Places SDK so the key can't be used outside your app.

On the device, `RequestMonitor` enforces `PLACES_MAX_REQUESTS_PER_MINUTE` (30) and `PLACES_MAX_REQUESTS_PER_DAY` (400) from `Config/App.xcconfig`, counts requests by SKU, and shows them under Profile → Search usage. It is a guard against bugs and loops, not a security control.

When Google reports quota exhaustion, or the local cap is hit, the app shows a plain message with a Try again button. Saved places, rankings, visit logging and the feed keep working because none of them needs a search.

## Sources

- [Google Maps Platform pricing](https://developers.google.com/maps/billing-and-pricing/pricing)
- [Places SDK for iOS policies](https://developers.google.com/maps/documentation/places/ios-sdk/policies)
- [Place data fields and SKUs](https://developers.google.com/maps/documentation/places/ios-sdk/data-fields)
- [Session tokens](https://developers.google.com/maps/documentation/places/ios-sdk/place-session-tokens)
- [Google Maps Platform Service Specific Terms](https://cloud.google.com/maps-platform/terms/maps-service-terms)
