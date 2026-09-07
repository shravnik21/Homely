# Homely 🏡

Homely is an Airbnb-style booking app for farmhouses, villas, apartments, and holiday homes, built with **Flutter** and **Supabase**. It supports two roles from a single codebase — **Guest** (browse, book, manage trips) and **Host** (list properties, manage bookings, get paid) — chosen at sign-up.

## Features

### Guest Mode

- **Browse listings** — search and filter places by city (any city in India, not just a fixed list — see below) and property type (villa, apartment, cottage, cabin, bungalow, holiday home, beach house, farmhouse, penthouse, homestay)
- **Place details** — photos, pricing, capacity, bedrooms/bathrooms, address, description, amenities, a highlights row (self check-in method + up to 2 host-chosen highlights), and guest reviews
- **Wishlist** — save places for later
- **Availability calendar** — already-booked dates *and* dates a host has manually blocked are greyed out and unselectable, so a guest can never pick a conflicting range
- **Bookings & payments** — pick check-in/check-out dates and guest count, then pay via **Razorpay Checkout**; the booking itself is only created after the payment is verified server-side (see [Payments & Security](#payments--security) below), followed by a booking-confirmation screen
- **Manage bookings** — a dedicated "My Bookings" list; tapping a booking opens full details with a **Manage booking** action to:
  - **Reschedule** — pick new dates via the same availability calendar; the new price is recomputed server-side from the listing's real nightly rate
  - **Cancel** — with the listing's own cancellation policy (flexible / moderate / strict, each with its own fee tiers) shown up front; the fee/refund is computed and locked in server-side at the moment of cancellation
- **Reviews** — leave one review per completed stay
- **Messaging** — a real-time, booking-scoped chat with the host of that stay (one conversation per booking, powered by Supabase Realtime)
- **Notifications** — booking confirmed/cancelled/rescheduled alerts, plus check-in reminders and review prompts
- **Authentication** — email/password sign up, sign in, sign out, and password reset via Supabase Auth
- **Profile & settings** — edit profile (name, phone, avatar), plus About, Help & Support, Privacy Policy, and Terms of Service screens

### Host Mode

- **Host onboarding** — a short intro flow, host agreement acceptance, identity verification (government ID photo upload), and payout details (bank/UPI) before a host can list
- **Listings (My Listings)** — a multi-step listing wizard (property details, photos, amenities, pricing, cancellation policy, check-in method, highlights) to create and publish listings; manage/edit/delete existing ones
- **List in any city** — hosts aren't limited to a fixed set of seeded cities; typing a new city adds it on the fly (with map geocoding to help place the pin), and it immediately shows up as a filter option for guests too
- **Blocked dates** — a host can manually mark individual dates unavailable on their own calendar (personal use, maintenance, an off-platform booking), independent of guest bookings
- **Host dashboard (Host Home)** — an at-a-glance view with a "Recent Bookings" preview (capped, with a "View all" link) and dashboard stats
- **Your Bookings** — the full booking list, split into **Upcoming / Completed / Cancelled** tabs so cancelled bookings always have a clear home instead of getting lost in a flat list
- **Booking details** — tapping any booking opens a read-only detail screen with guest info (name, avatar), stay dates, guest count, and the price/payout breakdown — including payout amount on cancelled bookings
- **Private notes** — a host can attach a private note to a booking
- **Reviews & notifications** — see reviews left on their listings, and get notified of new bookings, cancellations, and messages

## Payments & Security

- **Razorpay Checkout** for payment collection, with the order created server-side by a `create-razorpay-order` Edge Function — the amount charged is always computed from the listing's real price, never trusted from the client.
- **Server-verified booking creation** — a booking is never inserted directly by the app. Once Checkout reports success, a second Edge Function (`verify-and-create-booking`) independently recomputes Razorpay's payment signature using the server-side key secret and only creates the booking if it matches — a modified client can't fabricate a "successful payment."
- **Server-computed cancellation & reschedule** — the fee, refund, and rescheduled price a guest sees are calculated by Postgres functions (`cancel_booking`, `reschedule_booking`) from the listing's actual policy and rate, not from whatever the client sends.
- **Row Level Security everywhere**, with column-level write protection on top for the fields that matter most: a user can't edit their own `role`, a host can't self-approve their own ID verification status, and neither a guest nor a host can directly rewrite a booking's price, dates, or status outside the functions above.

## Reliability & Error Handling

- **No internet connection screen** — the whole app is wrapped in a connectivity watcher (`ConnectivityGate`). If the device loses network entirely (airplane mode, wifi/data off), a plain "No Internet Connection" screen takes over automatically — with a 2-second debounce so brief wifi↔cellular handovers don't flash it — and disappears the moment connectivity returns, with the underlying screen's state fully preserved.
- **No raw backend errors shown to users** — every network/database failure across the app (login, signup, bookings, listings, wishlist, profile, etc.) is mapped through a shared `friendlyError()` helper and `ErrorStateView` widget, so users only ever see clean, consistent messages ("No internet connection...", "Could not save...") instead of raw `PostgrestException`/`SocketException` text.
- **Auto-reload on reconnect** — some screens (e.g. the home feed) automatically retry their failed request as soon as the device comes back online.

## Tech Stack

| Layer            | Technology                                                  |
|-------------------|--------------------------------------------------------------|
| Frontend          | Flutter (Dart SDK ^3.3.0)                                    |
| Backend           | Supabase (Postgres, Auth, Realtime, Storage, Row Level Security) |
| Serverless        | Supabase Edge Functions (Deno) — payment order creation & verification |
| Payments          | Razorpay Checkout                                             |
| State mgmt        | Provider                                                      |
| Fonts/UI          | Google Fonts, cached_network_image                            |
| Calendar          | table_calendar                                                |
| Maps & location   | flutter_map (OpenStreetMap), geolocator, geocoding             |
| Connectivity      | connectivity_plus                                              |
| Image picking     | image_picker                                                   |
| Env config        | flutter_dotenv                                                 |

## Project Structure

```
lib/
├── config/
│   ├── app_theme.dart              # App-wide theme
│   └── supabase_config.dart        # Supabase client initialization
├── models/
│   ├── booking.dart                # Booking data model (+ reschedule/cancel fields)
│   ├── host_booking.dart           # Booking + guest name/avatar, for the host side
│   ├── place.dart                  # Place data model
│   ├── review.dart
│   ├── chat_message.dart
│   └── app_notification.dart
├── screens/
│   ├── splash_screen.dart
│   ├── chat_screen.dart            # Booking-scoped guest<->host chat
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── signup_screen.dart
│   ├── guest/
│   │   ├── home_screen.dart
│   │   ├── place_detail_screen.dart
│   │   ├── booking_screen.dart
│   │   ├── booking_confirmation_screen.dart
│   │   ├── booking_detail_screen.dart      # Manage booking: reschedule / cancel
│   │   ├── cancellation_policy_detail_screen.dart
│   │   ├── my_bookings_screen.dart
│   │   ├── my_reviews_screen.dart
│   │   ├── write_review_screen.dart
│   │   ├── review_prompt_screen.dart
│   │   ├── notifications_screen.dart
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
│       ├── host_reviews_screen.dart
│       ├── listing_reviews_screen.dart
│       ├── host_notifications_screen.dart
│       ├── my_listings_screen.dart
│       ├── listing_wizard_screen.dart      # Multi-step create/edit flow
│       ├── listing_manage_screen.dart
│       └── listing_constants.dart
├── services/
│   ├── auth_service.dart           # Sign up / sign in / sign out / reset password
│   ├── places_service.dart         # Fetch places & cities
│   ├── booking_service.dart        # Reschedule / cancel bookings (server-computed)
│   ├── payment_service.dart        # Razorpay order creation + payment verification
│   ├── cancellation_policy.dart    # Client-side preview of the server's fee calc
│   ├── availability_service.dart   # Booked/blocked-date lookups for the calendar
│   ├── review_service.dart
│   ├── messages_service.dart
│   ├── notifications_service.dart
│   ├── host_notifications_service.dart
│   ├── wishlist_service.dart
│   ├── host_service.dart           # Host agreement / verification / payout details
│   ├── host_listings_service.dart
│   ├── host_bookings_service.dart  # Bookings across a host's listings + guest info
│   └── location_service.dart       # Geocoding + place search for the wizard's map step
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
│   ├── review_tile.dart
│   ├── availability_date_range_sheet.dart  # Shared date-range picker (booking + reschedule)
│   ├── no_internet_screen.dart
│   └── error_state_view.dart
└── main.dart

supabase/
├── setup.sql                              # profiles table, RLS, auto-create-profile trigger
├── add_role_column.sql                    # guest/host role on profiles
├── schema_places.sql                      # cities, places, place_images + RLS
├── schema_cities_host_insert.sql          # lets a host add a new city on the fly
├── schema_address_components.sql
├── schema_fix_places_order.sql
├── seed_places.sql                        # sample listings across Mumbai, Pune, Goa, Lonavala, Alibaug
├── schema_place_highlights.sql            # listing highlights row
├── schema_place_checkin_method.sql        # smart lock / lockbox / in-person, etc.
├── schema_bookings.sql                    # bookings table + RLS
├── schema_no_overlapping_bookings.sql     # prevents double-booking the same dates
├── schema_blocked_dates.sql               # host-blocked calendar dates
├── schema_place_availability.sql          # booked/blocked-date lookups for the calendar
├── schema_reschedule_tracking.sql         # previous dates / rescheduled_at columns
├── schema_cancellation_fee.sql            # cancellation_fee / refund_amount columns
├── schema_cancellation_policy_type.sql    # per-listing flexible/moderate/strict policy
├── schema_checked_in.sql
├── schema_hide_bookings.sql
├── schema_payment_orders.sql              # Razorpay order tracking (server-authoritative)
├── schema_secure_bookings.sql             # locks booking writes to the Edge Function + RPCs
├── schema_secure_profiles.sql             # protects role / id_verification_status from self-escalation
├── schema_reviews.sql
├── fix_review_submit_bug.sql
├── schema_messages.sql                    # booking-scoped chat
├── schema_message_notifications.sql
├── schema_notifications.sql
├── schema_host_notifications.sql
├── cleanup_duplicate_notifications.sql
├── schema_wishlists.sql
├── schema_host_onboarding.sql
├── schema_host_verification.sql
├── schema_host_listings.sql
├── schema_host_bookings.sql               # host_notes on bookings
├── schema_host_booking_notes.sql
├── schema_host_public_info.sql            # public host info visible to guests
├── schema_host_public_info_change_fix.sql
├── host_public_info_error_fix.sql
├── schema_split_host_profiles.sql
├── schema_host_profiles_fk.sql
├── schema_host_profiles_duplicate_name_email.sql
├── migrate_split_existing_addresses.sql
└── functions/
    ├── create-razorpay-order/          # Server-computed Razorpay order creation
    └── verify-and-create-booking/      # Verifies payment signature, then creates the booking
```

## Database Schema

- **profiles** — extends `auth.users` with full name, email, phone, avatar, and role (`guest`/`host`); a trigger auto-creates a row on sign up. `role` is immutable to the client after signup.
- **cities** — supported cities; hosts can add new ones directly from the listing wizard.
- **places** — listings with type, price per night, capacity, bedrooms/bathrooms, address, description, amenities, highlights, check-in method, and cancellation policy type.
- **place_images** — up to 5 images per place, ordered.
- **blocked_dates** — dates a host has manually marked unavailable, independent of bookings.
- **bookings** — check-in/check-out dates, guest count, total price, status (`confirmed`/`cancelled`), reschedule history, and cancellation figures (`cancellation_fee`, `refund_amount`); a database exclusion constraint prevents overlapping bookings on the same place. Only ever created by the `verify-and-create-booking` Edge Function, and price/date/status fields can only change via `cancel_booking`/`reschedule_booking`.
- **payment_orders** — one row per Razorpay order, tracking status (`created`/`paid`/`failed`/`refund_needed`) server-side.
- **reviews** — one review per completed booking.
- **messages** — real-time chat messages, scoped to a single booking.
- **notifications** — booking and message alerts, per user.
- **host_profiles** / **host_public_info** — a host's private verification/payout data, split from the public-facing info shown to guests on a listing.
- **wishlists** — a user's saved places.

All tables use **Row Level Security**. Listings (`places`, `cities`) are publicly readable; everything else is scoped so users can only access their own records (with narrow, purpose-built exceptions — e.g. a host can read booking/guest info for their own listings, and a guest/host can read messages on a booking they're actually part of).

## Getting Started

1. **Install Flutter** (SDK ^3.3.0) — see [flutter.dev](https://flutter.dev/docs/get-started/install).
2. **Clone the repo** and run:
   ```bash
   flutter pub get
   ```
3. **Set up Supabase**
   - Create a project at [supabase.com](https://supabase.com).
   - Run the SQL files in `supabase/` against your project, in roughly the order listed above (`setup.sql` first, then the feature-specific schema files).
4. **Configure environment variables** — create a `.env` file in the project root (see `.env.example`):
   ```
   SUPABASE_URL=your-supabase-project-url
   SUPABASE_ANON_KEY=your-supabase-anon-key
   ```
5. **Set up Razorpay + Edge Functions**
   - Create a [Razorpay](https://razorpay.com) account and get your Key ID / Key Secret.
   - Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then link it to your project: `supabase link --project-ref your-project-ref`.
   - Set the secret both Edge Functions need: `supabase secrets set RAZORPAY_KEY_SECRET=your_key_secret`.
   - Deploy both functions:
     ```bash
     supabase functions deploy create-razorpay-order
     supabase functions deploy verify-and-create-booking
     ```
6. **Run the app**
   ```bash
   flutter run
   ```


