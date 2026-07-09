# Homely — Phase 1 (Splash + Login + Signup + Supabase Auth)

## What's included
- `lib/main.dart` — app entry, initializes Supabase
- `lib/config/supabase_config.dart` — loads `.env` and sets up the Supabase client
- `lib/config/app_theme.dart` — colors + theme (basic now, will be refined later)
- `lib/services/auth_service.dart` — signUp / signIn / signOut wrapper
- `lib/screens/splash_screen.dart` — checks session, routes to Login or Home
- `lib/screens/auth/login_screen.dart`
- `lib/screens/auth/signup_screen.dart`
- `lib/screens/home_screen.dart` — placeholder to confirm login works
- `lib/widgets/` — reusable text field + button
- `supabase/setup.sql` — run this in your Supabase project

## Setup steps

### 1. Create a Supabase project
Go to https://supabase.com → New Project.

### 2. Run the SQL
Open **SQL Editor** in your Supabase dashboard, paste the contents of
`supabase/setup.sql`, and run it. This creates the `profiles` table,
enables Row Level Security, and adds a trigger so a profile row is
auto-created every time someone signs up.

### 3. Get your API keys
Project Settings → API → copy:
- **Project URL**
- **anon public key**

### 4. Configure the app
Rename `.env.example` to `.env` and fill in:
```
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_ANON_KEY=xxxxxxxxxxxxxxxxx
```

### 5. Email confirmation (recommended OFF while testing)
Authentication → Providers → Email → toggle **Confirm email** OFF.
This way signup logs you straight in without needing to click a link
in your inbox. Turn it back ON before you ship.

### 6. Install & run
```bash
flutter pub get
flutter run
```

## Flow you'll see
Splash (2s) → checks if a session exists →
- No session → Login screen → "Sign up" link → Signup screen → back to Home on success
- Existing session → straight to Home screen (placeholder) with a working Logout button

## Next steps (Phase 2)
- Home screen: city selector + place cards grid (10 places × 5 cities)
- Place Detail screen (image carousel, amenities, price)
- Then Booking screen, Profile, My Bookings
- Tier 2: Wishlist, Search + Filters, Bottom Nav Bar

Let me know once you've run this and logged in successfully, and we'll
move on to the Home screen + seeding city/place data in Supabase.
