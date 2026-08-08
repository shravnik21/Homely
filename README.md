# Homely 🏡

Homely is an Airbnb-style booking app for farmhouses, villas, apartments, and holiday homes, built with **Flutter** and **Supabase**.

## Features

### User Mode

- **Browse listings** — search and filter places by city and property type (villa, apartment, cottage, cabin, bungalow, holiday home, beach house, farmhouse, penthouse, homestay)
- **Place details** — photos, pricing, capacity, bedrooms/bathrooms, address, description, and amenities
- **Authentication** — email/password sign up, sign in, sign out, and password reset via Supabase Auth
- **User profiles** — auto-created on sign up, with name, email, phone, and avatar
- **Bookings** — pick check-in/check-out dates, guest count, and confirm a reservation
- **Booking confirmation** — dedicated confirmation screen after a successful booking

### Host Mode


## Tech Stack

| Layer          | Technology                                   |
|----------------|-----------------------------------------------|
| Frontend       | Flutter (Dart SDK ^3.3.0)                     |
| Backend        | Supabase (Postgres, Auth, Row Level Security) |
| State mgmt     | Provider                                      |
| Fonts/UI       | Google Fonts, cached_network_image            |
| Calendar       | table_calendar                                |
| Env config     | flutter_dotenv                                |

## Project Structure

```
lib/
├── config/
│   ├── app_theme.dart          # App-wide theme
│   └── supabase_config.dart    # Supabase client initialization
├── models/
│   └── place.dart              # Place data model
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── signup_screen.dart
│   ├── splash_screen.dart
│   ├── home_screen.dart
│   ├── place_detail_screen.dart
│   ├── booking_screen.dart
│   ├── booking_confirmation_screen.dart
│   └── profile_screen.dart
├── services/
│   ├── auth_service.dart       # Sign up / sign in / sign out / reset password
│   ├── places_service.dart     # Fetch places & cities
│   └── booking_service.dart    # Create bookings
├── widgets/
│   ├── custom_textfield.dart
│   ├── place_card.dart
│   └── primary_button.dart
└── main.dart

supabase/
├── setup.sql            # Phase 1: profiles table, RLS, auto-create-profile trigger
├── schema_places.sql    # Phase 2: cities, places, place_images tables + RLS
├── seed_places.sql      # Phase 2: sample listings across Mumbai, Pune, Goa, Lonavala, Alibaug
└── schema_bookings.sql  # Phase 3: bookings table + RLS
```

## Database Schema

- **profiles** — extends `auth.users` with full name, email, phone, and avatar; a trigger auto-creates a row on sign up
- **cities** — list of supported cities
- **places** — listings with type, price per night, capacity, bedrooms/bathrooms, address, description, and amenities
- **place_images** — up to 5 images per place, ordered
- **bookings** — check-in/check-out dates, guest count, total price, and status, linked to a user and a place

All tables use **Row Level Security**: listings (`places`, `cities`) are publicly readable, while `profiles` and `bookings` are restricted so users can only access their own records.

## Getting Started

### Setup

1. **Clone the repo and install dependencies**
   ```bash
   git clone <repo-url>
   cd homely_app
   flutter pub get
   ```

2. **Configure environment variables**

   Create a `.env` file in the project root:
   ```
   SUPABASE_URL=your_supabase_project_url
   SUPABASE_ANON_KEY=your_supabase_anon_key
   ```

3. **Set up the database**

   In the Supabase SQL Editor, run the scripts in `supabase/` in order:
   ```
   setup.sql
   schema_places.sql
   seed_places.sql
   schema_bookings.sql
   ```

