# Homely 🏡

Homely is an Airbnb-style booking app for farmhouses, villas, apartments, and holiday homes, built with **Flutter** and **Supabase**. It supports two roles from a single codebase — **Guest** (browse, book, manage trips) and **Host** (list properties, manage bookings, get paid) — chosen at sign-up.

## Features

### Guest Mode

- **Browse listings** — search and filter places by city and property type (villa, apartment, cottage, cabin, bungalow, holiday home, beach house, farmhouse, penthouse, homestay)
- **Place details** — photos, pricing, capacity, bedrooms/bathrooms, address, description, and amenities
- **Wishlist** — save places for later
- **Availability calendar** — already-booked dates are greyed out and unselectable when picking a date range, so a guest can never pick a conflicting range
- **Bookings** — pick check-in/check-out dates, guest count, and confirm a reservation; a booking-confirmation screen follows a successful booking
- **Manage bookings** — a dedicated "My Bookings" list; tapping a booking opens full details with a **Manage booking** action to:
  - **Reschedule** — pick new dates via the same availability calendar
  - **Cancel** — with a tiered refund policy shown up front (15+ days out: full refund · 2–14 days out: 50% fee · 0–1 days out: no refund); the fee/refund is locked in at the moment of cancellation and stored on the booking
- **Authentication** — email/password sign up, sign in, sign out, and password reset via Supabase Auth
- **Profile & settings** — edit profile (name, phone, avatar), plus About, Help & Support, Privacy Policy, and Terms of Service screens

### Host Mode

- **Host onboarding** — a short intro flow, host agreement acceptance, identity verification (government ID photo upload), and payout details (bank/UPI) before a host can list
- **Listings (My Listings)** — a multi-step listing wizard (property details, photos, amenities, pricing) to create and publish listings; manage/edit/delete existing ones
- **Host dashboard (Host Home)** — an at-a-glance view with a "Recent Bookings" preview (capped, with a "View all" link) and dashboard stats
- **Your Bookings** — the full booking list, split into **Upcoming / Completed / Cancelled** tabs so cancelled bookings always have a clear home instead of getting lost in a flat list
- **Booking details** — tapping any booking (from the dashboard or Your Bookings) opens a read-only detail screen with guest info (name, avatar), stay dates, guest count, and the price/payout breakdown — including payout amount on cancelled bookings
- **Private notes** — a host can attach a private note to a booking

## Reliability & Error Handling

- **No internet connection screen** — the whole app is wrapped in a connectivity watcher (`ConnectivityGate`). If the device loses network entirely (airplane mode, wifi/data off), a plain "No Internet Connection" screen takes over automatically — with a 2-second debounce so brief wifi↔cellular handovers don't flash it — and disappears the moment connectivity returns, with the underlying screen's state fully preserved.
- **No raw backend errors shown to users** — every network/database failure across the app (login, signup, bookings, listings, wishlist, profile, etc.) is mapped through a shared `friendlyError()` helper and `ErrorStateView` widget, so users only ever see clean, consistent messages ("No internet connection...", "Could not save...") instead of raw `PostgrestException`/`SocketException` text.
- **Auto-reload on reconnect** — some screens (e.g. the home feed) automatically retry their failed request as soon as the device comes back online.

## Tech Stack

| Layer          | Technology                                   |
|----------------|-----------------------------------------------|
| Frontend       | Flutter (Dart SDK ^3.3.0)                     |
| Backend        | Supabase (Postgres, Auth, Row Level Security) |
| State mgmt     | Provider                                      |
| Fonts/UI       | Google Fonts, cached_network_image            |
| Calendar       | table_calendar                                |
| Connectivity   | connectivity_plus                             |
| Image picking  | image_picker                                  |
| Env config     | flutter_dotenv                                |

## Project Structure

```
lib/
├── config/
│   ├── app_theme.dart              # App-wide theme
│   └── supabase_config.dart        # Supabase client initialization
├── models/
│   ├── booking.dart                # Booking data model (+ reschedule/cancel fields)
│   ├── host_booking.dart           # Booking + guest name/avatar, for the host side
│   └── place.dart                  # Place data model
├── screens/
│   ├── splash_screen.dart
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── signup_screen.dart
│   ├── guest/
│   │   ├── home_screen.dart
│   │   ├── place_detail_screen.dart
│   │   ├── booking_screen.dart
│   │   ├── booking_confirmation_screen.dart
│   │   ├── booking_detail_screen.dart      # Manage booking: reschedule / cancel
│   │   ├── my_bookings_screen.dart
│   │   ├── wishlist_screen.dart
│   │   ├── profile_screen.dart
│   │   └── settings/
│   │       ├── settings_screen.dart
│   │       ├── edit_profile_screen.dart
│   │       ├── about_screen.dart
│   │       ├── help_support_screen.dart
│   │       ├── privacy_policy_screen.dart
│   │       ├── terms_of_service_screen.dart
│   │       └── legal_document_screen.dart
│   └── host/
│       ├── host_onboarding_screen.dart
│       ├── host_agreement_screen.dart
│       ├── host_verify_identity_screen.dart
│       ├── host_payout_details_screen.dart
│       ├── host_profile_screen.dart
│       ├── host_home_screen.dart           # Host dashboard
│       ├── host_bookings_screen.dart       # Upcoming / Completed / Cancelled tabs
│       ├── host_booking_detail_screen.dart # Guest info, dates, payout, notes
│       ├── my_listings_screen.dart
│       ├── listing_wizard_screen.dart      # Multi-step create/edit flow
│       ├── listing_manage_screen.dart
│       └── listing_constants.dart
├── services/
│   ├── auth_service.dart           # Sign up / sign in / sign out / reset password
│   ├── places_service.dart         # Fetch places & cities
│   ├── booking_service.dart        # Create / reschedule / cancel bookings
│   ├── cancellation_policy.dart    # Sliding-scale refund policy
│   ├── availability_service.dart   # Booked-date lookups for the calendar
│   ├── wishlist_service.dart
│   ├── host_service.dart           # Host agreement / verification / payout details
│   ├── host_listings_service.dart
│   └── host_bookings_service.dart  # Bookings across a host's listings + guest info
├── utils/
│   ├── connectivity_gate.dart      # App-wide "no internet" takeover
│   ├── network_error_helper.dart   # isNetworkError() / friendlyError()
│   ├── auto_reload_on_reconnect.dart
│   └── network_retry.dart
├── widgets/
│   ├── custom_textfield.dart
│   ├── primary_button.dart
│   ├── place_card.dart
│   ├── role_toggle.dart
│   ├── availability_date_range_sheet.dart  # Shared date-range picker (booking + reschedule)
│   ├── no_internet_screen.dart
│   └── error_state_view.dart
└── main.dart

supabase/
├── setup.sql                              # profiles table, RLS, auto-create-profile trigger
├── add_role_column.sql                    # guest/host role on profiles
├── schema_places.sql                      # cities, places, place_images + RLS
├── seed_places.sql                        # sample listings across Mumbai, Pune, Goa, Lonavala, Alibaug
├── schema_bookings.sql                    # bookings table + RLS
├── schema_no_overlapping_bookings.sql     # prevents double-booking the same dates
├── schema_reschedule_tracking.sql         # previous dates / rescheduled_at columns
├── schema_cancellation_fee.sql            # cancellation_fee / refund_amount columns
├── schema_place_availability.sql          # booked-date lookups for the calendar
├── schema_wishlists.sql
├── schema_host_onboarding.sql
├── schema_host_verification.sql
├── schema_host_listings.sql
├── schema_host_bookings.sql               # host_notes on bookings
├── schema_host_booking_notes.sql
├── schema_host_public_info.sql            # public host info visible to guests
├── host_public_info_error_fix.sql
├── schema_split_host_profiles.sql
├── schema_host_profiles_fk.sql
├── schema_host_profiles_duplicate_name_email.sql
└── schema_fix_places_order.sql
```

## Database Schema

- **profiles** — extends `auth.users` with full name, email, phone, avatar, and role (`guest`/`host`); a trigger auto-creates a row on sign up
- **cities** — list of supported cities
- **places** — listings with type, price per night, capacity, bedrooms/bathrooms, address, description, and amenities
- **place_images** — up to 5 images per place, ordered
- **bookings** — check-in/check-out dates, guest count, total price, status (`confirmed`/`cancelled`), plus reschedule history (previous dates, `rescheduled_at`) and cancellation figures (`cancellation_fee`, `refund_amount`), a host-only private note, and a database constraint preventing overlapping bookings on the same place
- **wishlists** — a user's saved places

All tables use **Row Level Security**: listings (`places`, `cities`) are publicly readable, while `profiles`, `bookings`, and `wishlists` are restricted so users can only access their own records (with a scoped exception letting hosts read booking/guest info for their own listings).

## Getting Started

1. **Install Flutter** (SDK ^3.3.0) — see [flutter.dev](https://flutter.dev/docs/get-started/install).
2. **Clone the repo** and run:
   ```bash
   flutter pub get
   ```
3. **Set up Supabase**
   - Create a project at [supabase.com](https://supabase.com).
   - Run the SQL files in `supabase/` against your project, in roughly the order listed above (`setup.sql` first, then the feature-specific schema files).
4. **Configure environment variables** — create a `.env` file in the project root:
   ```
   SUPABASE_URL=your-supabase-project-url
   SUPABASE_ANON_KEY=your-supabase-anon-key
   ```
5. **Run the app**
   ```bash
   flutter run
   ```

## Known Gaps / Not Yet Production-Complete

- No offline data caching — the app blocks on lost connectivity rather than showing previously-loaded data.
- Guests self-serve reschedule/cancel; hosts can view bookings but don't yet have their own reschedule/cancel actions.
- Cancellation policy is a single app-wide sliding scale (no per-listing policy tiers yet).
