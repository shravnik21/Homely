# Map Location Picker (Host Listing Wizard)

This documents the "Pin the exact location" map step in the host listing
wizard (`lib/screens/host/listing_wizard_screen.dart`, Step 2: Location) -
the search box added on top of the map, the full-screen expand view, and a
summary of the current-location/tap-to-drop-pin behavior they sit alongside.

## What's on the map, and is it real?

The map itself is a **real, live map** - `flutter_map` rendering actual
OpenStreetMap tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`), not a
static image or placeholder. It's used in two places:

- **Host listing wizard** (this feature) - fully interactive.
- **Guest place detail screen** - a small, intentionally *non-interactive*
  preview that just displays the host's saved pin. Guests have no reason to
  move a listing's pin, so no search/tap behavior was added there.

## The three ways to set the pin

All three live in `_buildMapPinSection()` and can be used interchangeably -
whichever one a host uses last wins. All three also work identically in the
full-screen view (see below).

| Method | How | Backed by |
|---|---|---|
| **Search box** | Type any place name into the box overlaid on the map, tap a result | OpenStreetMap Nominatim API |
| **Use my location** | Tap the "Use my location" button | Device GPS (`geolocator`) |
| **Tap the map** | Tap anywhere on the map directly | `flutter_map`'s `onTap` |
| **Find on map** | Tap "Find on map" to geocode the typed street/city fields | Device's native geocoder (`geocoding`) |

### 1. Search box (new)

A text field floats on top of the map itself. As the host types, results
appear in a dropdown right below it; tapping a result recenters the map and
drops the pin there.

- **Debounced** - a search only fires ~450ms after the host stops typing, not
  on every keystroke. This is both kinder to Nominatim's free tier and avoids
  a flickering results list.
- **Biased to India** (`countrycodes: 'in'`) to match the rest of the app
  ("Listings can now be added in any city in India").
- **No API key, no billing account** - same free Nominatim service, consistent
  with the existing `flutter_map` + OpenStreetMap setup. A descriptive
  `User-Agent` header is sent, per Nominatim's usage policy.
- Fails quietly: no matches, no connection, or any other error just means an
  empty results list - never a crash or an alarming error message. This is a
  routine, expected outcome while someone's still typing.
- An "x" button appears once there's text, to clear the search and its
  results in one tap.

### 2. Use my location

Already existed before this change - included here for completeness. Calls
`Geolocator.getCurrentPosition()` (real device GPS, not mocked), requesting
permission first if needed. Silently no-ops (with an inline error message) if
location services are off or permission is denied - the host can always fall
back to search or a manual tap.

### 3. Tap the map

Also pre-existing. A direct tap always takes priority - it clears any open
search dropdown and drops the pin exactly where tapped, which is what lets a
host fine-tune the exact doorstep after search or GPS gets them *close*.

## Full-screen map

The small 220px preview box is too cramped to search comfortably or place a
pin precisely, so a circular expand button (bottom-right corner of the map)
opens the exact same picker full-screen, as its own route
(`FullScreenMapPickerScreen`, `lib/screens/host/fullscreen_map_picker_screen.dart`).

- Has its own search box, "Use my location" button, and tap-to-drop-pin -
  functionally identical to the small map, just with room to actually use
  them.
- A close (X) button top-left, and a "Confirm location" button at the
  bottom, both return the current pin back to the wizard - either one works,
  there's no meaningful difference between them.
- The **system back gesture/button** does the same thing (via `PopScope`),
  so a host can't accidentally lose their pin by backing out of the
  full-screen view a different way than intended.
- Whatever pin was set (or left unchanged) is applied back to the small map
  in the wizard the moment the full-screen view closes - both stay in sync,
  there's no separate "unsaved" state.

## Files touched

- **`lib/services/location_service.dart`**
  - Added `PlaceSearchResult` (a `displayName` + `LatLng` pair).
  - Added `LocationService.searchPlaces(String query)` - calls Nominatim's
    `/search` endpoint, returns up to 6 matches, empty list on any failure.
- **`lib/screens/host/listing_wizard_screen.dart`**
  - Added the search box + results dropdown, overlaid on the existing map via
    a `Stack`.
  - Added an expand button (bottom-right of the map) that opens
    `FullScreenMapPickerScreen` and applies whatever pin comes back.
  - Added `_mapSearchController`, `_mapSearchFocus`, `_mapSearchDebounce`,
    `_mapSearchResults`, `_mapSearching` state, and disposed the controller
    and timer in `dispose()`.
  - Added `_onMapSearchChanged`, `_selectMapSearchResult`, `_clearMapSearch`,
    `_openFullScreenMap`.
  - The map's own `onTap` now also clears the search dropdown when a host
    taps directly, so the two interactions don't fight each other visually.
- **`lib/screens/host/fullscreen_map_picker_screen.dart`** (new)
  - Self-contained full-screen route: its own map controller, search state,
    "use my location," and tap-to-drop-pin - a mirror of the small map's
    behavior with room to actually use it.
  - Returns the final pin location via `Navigator.pop` on close (X button,
    "Confirm location" button, or the system back gesture) alike.
- **`pubspec.yaml`**
  - Added `http: ^1.2.2` (plain HTTP GET to Nominatim - no other client
    library was already in the project for this).

## Not changed

- The guest-facing map preview (`place_detail_screen.dart`) - stays
  non-interactive by design.
- The database schema - search results feed the exact same `_pinLocation`
  (`LatLng`) that "Use my location" and manual tapping already produced, so
  nothing downstream (saving to `places.latitude`/`places.longitude`,
  guest-side directions via `MapsLauncher`) needed to change.

## Trying it out

1. Run `flutter pub get` to fetch the new `http` dependency.
2. Open the host listing wizard, go to Step 2 (Location), and scroll to
   "Pin the exact location."
3. Type into the search box (e.g. "Baga Beach" or "Connaught Place, Delhi")
   and tap a result - the map should recenter and drop a pin there.
4. Try "Use my location" and a direct tap on the map too, to confirm all
   three still work together without conflicting.
5. Tap the expand icon (bottom-right of the map) to open it full-screen, try
   the same three ways to set a pin there, then close it via the X button,
   "Confirm location," and the system back gesture - confirm the small map
   reflects whatever pin you left it on each time.

## Known limitations / possible follow-ups

- Nominatim's free public API has a fair-use rate limit (roughly 1
  request/second) - fine for a single host typing in the app, but this
  should **not** be used for bulk/automated geocoding.
- No offline fallback - if the device has no connection, search silently
  returns no results (manual tap and "Use my location" both still work
  offline* for the pin-dropping part, though GPS itself still needs a
  location fix, not necessarily network).
- Results are India-biased; a host trying to search for a place outside
  India (unlikely given the app's current scope) won't find it via search,
  but can still drop a pin manually.
