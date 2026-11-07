# Doña Galleta

Product and order management for Doña Galleta: a storefront for customers and an
admin panel for products and orders. The same Flutter app runs on the web and on Android.

| Part | Tech | Folder |
| --- | --- | --- |
| App (web + Android) | Flutter, Riverpod, go_router | [`app/`](app/) |
| API (all business logic) | TypeScript on Vercel, supabase-js, zod | [`server/`](server/), [`api/index.ts`](api/index.ts) |
| Database, auth, storage | Supabase (Postgres) | [`supabase/`](supabase/) |

## Run locally

First time only: create `.env` (repository root) and `app/env.json` as described in
[Setup](#setup), then install the dependencies:

```bash
npm install
cd app && flutter pub get
```

Then use two terminals.

**Terminal 1: API** (repository root), on `http://localhost:3000/api`:

```bash
npm run dev:api
```

It logs one line per request, the error message of failed requests, and a warning
when a browser origin isn't in `ALLOWED_ORIGINS`. Restart it after changing `.env`.

**Terminal 2: web app**, on `http://localhost:8000`:

```bash
cd app
flutter run -d chrome --web-port 8000 --dart-define-from-file=env.json
```

In the Flutter terminal, `r` hot-reloads, `R` restarts the app and `q` quits.
The port must match `ALLOWED_ORIGINS` in `.env` (`http://localhost:8000`).

**Android** (emulator or device) instead of the web:

```bash
cd app
flutter run -d android --dart-define-from-file=env.json
```

On Android, `localhost` is the phone itself. Point `API_BASE_URL` in `app/env.json`
to your deployed Vercel URL, or to `http://10.0.2.2:3000` when using the emulator.

**Install a release build on a phone** (no hot reload, faster app). `flutter install`
only installs an APK that is already built, and it uninstalls the old version
first, so build it before installing:

```bash
cd app
flutter devices                                                # find the device id
flutter build apk --release --dart-define-from-file=env.json   # → build/app/outputs/flutter-apk/app-release.apk
flutter install -d <device-id>
```

- Rebuild after every code change or `env.json` change: the values are baked into the APK.
- Release builds only allow HTTPS, so `API_BASE_URL` must be the Vercel URL
  (plain `http://`, such as `10.0.2.2`, only works in debug builds).
- The APK is signed with the Google Play upload key when `app/android/key.properties`
  exists, and with the debug key otherwise (see [Publish on Google Play](#5-publish-on-google-play)).
  The installed app keeps its data only while the key stays the same: switching keys
  needs an uninstall first.

**Checks**:

```bash
npm run typecheck                            # API
cd app && flutter analyze && flutter test    # app
```

## Architecture

```
Flutter app ──(everything: data, sign in, sessions; Bearer <access token>)──► Vercel API ──(supabase-js)──► Supabase REST / Auth / Storage
     │                                     ├─ publishable key (public catalog, sign in, RLS applies)
     │                                     ├─ as the user (their token, RLS applies)
     │                                     └─ service role (admin, orders, stock), after its own checks
     ├──(admin image upload: Supabase SDK, signed upload from the API)──► Supabase Storage
     └──(image files: the public URLs the API returns)──────────────────► Supabase Storage
```

- **The database only stores data.** It has no functions or triggers.
- **The API owns every rule:** profiles, carts, checkout, stock, order statuses and
  history, `updated_at`, product and image management, permissions.
- **The API only talks to Supabase through supabase-js**, with the same three clients
  as `the-horse-tracker-api` ([`server/supabase.ts`](server/supabase.ts)):
  - `supabase()`: publishable key, to verify tokens and read public data;
  - `supabaseForUser(token)`: runs as the caller, so **RLS applies** to their profile,
    cart and orders;
  - `supabaseAdmin()`: secret key, for what a customer must never do with their own
    token (create orders, change stock, admin panel), always after `requireAdmin` or
    an ownership check.
- **The app only talks to the API**: data (the public catalog included), sign in and
  sessions (`/api/auth/*`). Changing the database or the auth provider means
  changing the API, not publishing a new app. The exception is uploading product
  images, which uses the Supabase SDK in a single file (see Images below); images
  load from the URLs the API returns.
- **Sessions** ([`lib/core/auth.dart`](app/lib/core/auth.dart)): the app stores the
  access and refresh tokens with `flutter_secure_storage` (Android Keystore,
  encrypted on the web), renews the access token a minute before it expires (or
  after a 401) through `/api/auth/refresh`, and sends it as `Bearer` to the API.
  Email links (confirm account, recover password) go through Supabase and land on
  the web app with the session in the URL fragment, which the app reads on start-up
  and then removes from the address bar.
- **Images**: two files know the storage provider (Supabase Storage), one per side.
  Moving to S3, R2, Cloudinary... means rewriting those two (and copying the files
  over).
  - API: [`server/services/images.ts`](server/services/images.ts) signs uploads,
    builds public URLs and deletes files. The database keeps each image's
    `storage_path`, and URLs are built from it when reading.
  - App: [`product_image_repository.dart`](app/lib/repositories/product_image_repository.dart)
    uploads, links and deletes images. It's the only file in the app that uses the
    Supabase SDK (`uploadBinaryToSignedUrl`), including its configuration.
- **RLS** ([`…03_rls_policies.sql`](supabase/migrations/20261104000003_rls_policies.sql)):
  anyone reads the active catalog; each user reads and writes only their own
  profile (never the `role` column) and cart, and reads only their own orders.
  Nobody but the service role writes orders or the catalog.

## Data model

```
auth.users ─1:1─ profiles (role: customer | admin)
     ├─1:N─ push_devices (admins' phones, for notifications)
     │
     ├─1:1─ carts ─1:N─ cart_items ──N:1─┐
     │                                   │
     └─1:N─ orders ─1:N─ order_items     │
              └─1:N─ order_status_history│
                                         ▼
categories ─N:M─ products ─1:N─ product_variants
  (tree)  (product_categories) └─1:N─ product_images
shop_settings (single row: shipping cost, free-shipping threshold, contact)
```

- **Money** is stored as integer cents (EUR).
- **Categories**: a product can be listed in several categories (`product_categories`).
  `products.category_id` is its main one (shown in the admin list) and is always
  among them. A category page lists the products of the category and its
  sub-categories.
- **Variants**: every product has at least one variant; customers buy variants.
  `options` is a JSON object such as `{"Talla": "2 años"}`. A variant can override the
  product price. `stock = NULL` means *made to order* (stock not tracked).
- **Customizable products** accept a custom text (e.g. a baby's name), stored on the
  cart line and copied to the order line.
- **Orders** copy product name, variant, SKU and price, so later catalog edits don't
  change past orders. Every status change is logged in `order_status_history`.
- **Slugs** are stored lower-case and **SKUs** upper-case by the API, so uniqueness
  doesn't depend on how they were typed.

## Business rules (in `server/services/`)

| Rule | Where |
| --- | --- |
| Profile created on first sign in (from `user_metadata.full_name`), as the user | `profiles.ts` |
| Cart: one per user, lines merged per variant + customization, max 99, stock checked, customization required only for customizable products | `cart.ts` |
| Checkout: prices re-read from the catalog, stock reserved per variant across lines, shipping from settings, order written, ordered lines removed from the cart. If a step fails, the order is deleted and the stock given back | `orders.ts` |
| Status changes: only applied if the order still has the status that was read (so two changes can't both win), logged with who/when, `paid_at` / `shipped_at` stamped, cancelling restores stock, cancelled orders are final | `orders.ts` |
| Customers cancel only their own *pending* orders; admins any order | `orders.ts` |
| Stock: compare-and-swap updates (`… where stock = <value read>`, retried), so concurrent checkouts can't oversell | `stock.ts` |
| Products saved with their variants; slug, SKUs and variant ownership validated before writing anything | `products.ts` |
| Categories: two levels (menu + dropdowns), unique slug, a parent must be a main category, new ones go last, reordered by swapping with a sibling. Deleting is refused while a category has products or sub-categories (deactivate it to hide it) | `categories.ts` |
| Images: uploaded straight to Storage with a signed upload from the API (JPG/PNG/WEBP/GIF only, into the product's folder), public URLs built from `storage_path` when reading, files deleted with the image or product | `images.ts` |
| Sign in, sign up, sessions: Supabase Auth called only from the API, with a new client per call. Errors keep Supabase's code (`invalid_credentials`...) for the app to show in Spanish. Password recovery answers the same for any email | `sessions.ts` |
| Storefront product lists: cheapest first by default (lowest active variant price), or by price descending or name (Spanish alphabetical order, accents ignored). The category page keeps the choice in the URL (`?orden=nombre`) | `catalog.ts` |
| Shipping: flat rate, free above a threshold | `settings.ts` |
| New order: a push notification to every admin's Android device. A failed notification never fails the checkout; devices FCM no longer knows are removed | `push.ts` |
| Profile: name and phone editable (phone validated); email fixed | `profiles.ts` |
| Password change: needs the current password, except within an hour of opening a recovery link. Supabase then ends every session of the user, so the API returns a new one for this device. Deleting the account also asks for the password | `sessions.ts`, `profiles.ts` |

## Setup

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Run the SQL files in `supabase/migrations/`, in order, in the SQL editor
   (or with `supabase db push`):
   - `…01_initial_schema.sql`: tables and indexes.
   - `…02_defaults_and_storage.sql`: the default settings row and the
     `product-images` bucket.
   - `…03_rls_policies.sql`: Row Level Security for every table.
   - `…04_product_categories.sql`: lets a product be in several categories, and
     links existing products to their current category.
   - `…05_push_devices.sql`: the admins' devices for push notifications.

   All but the first are safe to run more than once.
3. Authentication → URL Configuration, so the links in Supabase's emails (sign-up
   confirmation, password recovery) open the app:
   - **Site URL**: the deployed web app, e.g. `https://<your-vercel-domain>`. It is
     `http://localhost:3000` by default, and links that don't name an allowed
     address (e.g. accounts created from Android) go there.
   - **Redirect URLs**: `http://localhost:8000/**` and `https://<your-vercel-domain>/**`.
     The web app asks for its own address (`/` after confirming an account,
     `/reset-password` for a new password); Supabase only honors it if it's listed.

   The link signs you in on the web app wherever you open it (the session comes in
   the link itself).
4. Authentication → Rate Limits: Supabase counts sign-in and sign-up attempts per
   IP address, and every attempt now comes from the API on Vercel, so all users
   share the same limit. If people get "Demasiados intentos", raise the limits for
   sign-ins and token refreshes there.
5. Optional: load sample data with `supabase/seed.sql`.
6. Sign up in the app, then make yourself admin (see [Administrators](#administrators)).

### 2. API environment

Create `.env` in the repository root (gitignored: it holds secrets, never commit it):

```properties
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_SECRET_KEY=sb_secret_...
ALLOWED_ORIGINS=http://localhost:8000
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
API_BASE_URL=
FIREBASE_SERVICE_ACCOUNT=
```

| Variable | Where to find it | Used by |
| --- | --- | --- |
| `SUPABASE_URL` | Project Settings → API | API and web build |
| `SUPABASE_SECRET_KEY` | Project Settings → API Keys → Secret keys (`sb_secret_…`). Secret | API (Auth checks, admin writes, Storage) |
| `ALLOWED_ORIGINS` | Comma-separated origins allowed to call `/api` from another origin. Only for local development | API |
| `SUPABASE_PUBLISHABLE_KEY` | Project Settings → API Keys → Publishable key (`sb_publishable_…`) | API and web build |
| `API_BASE_URL` | Leave empty: the deployed web app calls the API on its own origin | Web build |
| `FIREBASE_SERVICE_ACCOUNT` | Optional. Service account key JSON on one line, see [Push notifications](#6-push-notifications-to-admins). Secret | API |

```bash
npm install
npm run dev:api        # http://localhost:3000/api
```

### 3. Run the app

Create `app/env.json` (gitignored):

```json
{
  "API_BASE_URL": "http://localhost:3000",
  "SUPABASE_URL": "https://<project>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_..."
}
```

`API_BASE_URL` is all the app needs to run. `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` (Project Settings → API) are only used to upload product
images from the admin panel.

```bash
cd app
flutter run -d chrome --web-port 8000 --dart-define-from-file=env.json
```

`env.local.json` is also gitignored, handy to keep a second set of values (e.g. local
API vs. production) and switch with `--dart-define-from-file=env.local.json`.

`API_BASE_URL` is `http://localhost:3000` locally, or your Vercel URL. On Android it
must always be set; on the deployed web app leave it empty to use the same origin.

### 4. Deploy to Vercel

1. Import the repository in Vercel (root directory = repository root).
2. Add the environment variables from [API environment](#2-api-environment) (all but
   `ALLOWED_ORIGINS`), including `SUPABASE_PUBLISHABLE_KEY` for the web build.
3. Deploy. `scripts/vercel-build.sh` installs the pinned Flutter version and builds the
   web app into `app/build/web`. `vercel.json` sends every `/api/*` request to the
   single function in `api/index.ts`, and everything else to the Flutter app.

### 5. Publish on Google Play

The app ID is `es.donagalleta.app`. It can never change once the app is published.

**Upload key.** Google Play only accepts bundles signed with your upload key. It lives
outside git, in `app/android/upload-keystore.jks`, with its passwords in
`app/android/key.properties`:

```properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Keep a copy of both files somewhere safe, such as a password manager. Losing the key
doesn't lose the app (with Play App Signing, Google holds the real signing key), but
resetting it means asking Google support and waiting a few days. To create a new one:

```bash
cd app/android
keytool -genkeypair -v -keystore upload-keystore.jks -storetype PKCS12 \
  -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

**Build the bundle.** Raise the number after `+` in `app/pubspec.yaml` (`version:
1.0.0+1`) for every upload: Google Play rejects a version code it has seen before.

```bash
cd app
flutter build appbundle --release --dart-define-from-file=env.json   # → build/app/outputs/bundle/release/app-release.aab
```

`API_BASE_URL` in `env.json` must be the production URL: the bundle keeps that
value until the next upload.

**Store listing.** In Play Console:

- Icon `app/store/play/icon-512.png` and feature graphic `app/store/play/feature-graphic.png`.
  Screenshots: at least 2 phone screenshots.
- Privacy policy URL: `https://www.xn--doagalleta-u9a.es/privacidad.html`
  (`app/web/privacidad.html`).
- Account deletion URL: `https://www.xn--doagalleta-u9a.es/privacidad.html#eliminar-cuenta`.
  Users can also delete their account from *Mi perfil*.
- Data safety form:
  - Collected: email, name, phone, address, purchase history and "other user content"
    (order notes and personalisation texts). They are needed for the app to work and
    for account management, and are not shared with third parties.
  - Data is encrypted in transit and users can request deletion.
  - No ads, analytics or location.
- Target audience: adults (18+). The shop sells gifts for children but isn't aimed at them.

New personal developer accounts must run a closed test with at least 12 testers for 14
days before publishing to production. Organisation accounts don't need to.

### 6. Push notifications to admins

When an order is placed, every admin gets a notification on Android. Tapping it
opens the order. The API sends them with Firebase Cloud Messaging; until Firebase
is set up, everything else works without them.

1. In the [Firebase console](https://console.firebase.google.com), create a project.
   Analytics isn't needed.
2. **Add an Android app** with package name `es.donagalleta.app`. Download
   `google-services.json` into `app/android/app/`. It isn't secret: it only says
   which Firebase project the app belongs to.
3. **Server key**: Project settings → Service accounts → *Generate new private key*.
   Paste the whole JSON file, on one line, as `FIREBASE_SERVICE_ACCOUNT` in Vercel
   (Production) and in your local `.env`. It is secret: never commit it.
4. Run migration `…05_push_devices.sql` in Supabase.
5. Rebuild the app. An admin who signs in is asked for permission to show
   notifications, and the device is registered in `push_devices`.

How it works:

- The app registers its Firebase Installation ID (FID), FCM's replacement for
  registration tokens. It does this only for admins, with
  `POST /api/admin/devices`.
- Signing out unregisters the device from FCM, so the next person using the phone
  gets nothing. The API deletes devices that FCM rejects.
- Android shows the notifications in the *Pedidos* channel (`MainActivity.kt`). If
  the app is open, a message appears at the bottom instead, with a *Ver* button.

### 7. Google Analytics and Tag Manager (web)

The web app loads Google Tag Manager, and Google Analytics 4 is set up inside it.
Tag Manager only loads after the visitor accepts analytics cookies in the app's
banner (Spanish law requires asking first), and Google Consent Mode v2 starts with
everything denied. Without `GTM_ID`, nothing is loaded and no banner is shown. The
Android app has no analytics.

1. **Google Analytics**: create a GA4 property with a *Web* data stream for
   `https://www.xn--doagalleta-u9a.es`. Copy its measurement ID (`G-…`). In the
   stream's *Enhanced measurement*, keep **Page changes based on browser history
   events** on: the shop is a single-page app, and that's how page views are counted
   when moving between pages.
2. **Tag Manager**: create a *Web* container and copy its ID (`GTM-…`).
   - Add a **Google tag** with the `G-…` ID, triggered on *Initialization – All
     Pages*.
   - Don't add another page-view tag: the Google tag and enhanced measurement already
     count page views.
   - Click **Submit** to publish the container.
3. **Vercel**: add `GTM_ID=GTM-…` (Production) and redeploy. `scripts/vercel-build.sh`
   writes it into `index.html` and refuses IDs that don't look like `GTM-…`.
4. **Check it**: open the shop, accept cookies, and look at GA4 → Reports → Realtime,
   or use Tag Manager's *Preview* mode.

How it works:

- The loader and consent handling live in a script in
  [`app/web/index.html`](app/web/index.html), exposed as `window.dgAnalytics`.
- The banner and the footer's *Cookies* link are in
  [`lib/core/analytics/cookie_consent.dart`](app/lib/core/analytics/cookie_consent.dart).
- The visitor's choice is stored in `localStorage` (`analytics_consent`). Rejecting
  after accepting deletes the `_ga` cookies.

## Administrators

The role lives in `public.profiles.role` (`customer` or `admin`) and nobody can change
it from the app: run these in Supabase's SQL editor. The person must have signed in
at least once, since that's when their profile row is created; otherwise the update
changes 0 rows.

**Make someone admin:**

```sql
update public.profiles
set role = 'admin', updated_at = now()
where id = (select id from auth.users where lower(email) = lower('someone@example.com'));
```

**Remove the role:**

```sql
update public.profiles
set role = 'customer', updated_at = now()
where id = (select id from auth.users where lower(email) = lower('someone@example.com'));
```

**List admins:**

```sql
select u.email, p.full_name, p.updated_at
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'admin'
order by u.email;
```

The API checks the role on every `/api/admin/*` request, so a change applies right
away. The app shows or hides "Administración" in the account menu after reloading
the page or signing in again.

## API

All bodies are JSON in snake_case. Authenticated routes need
`Authorization: Bearer <access token>` (from `/api/auth/login`); `/api/admin/*` also
needs the admin role.

| Method | Path | Description |
| --- | --- | --- |
| GET | `/api/health` | Health check. |
| POST | `/api/auth/signup` | `{email, password, full_name?, redirect_to?}` → `{session, confirmation_required}` (`session` is null until the email is confirmed). |
| POST | `/api/auth/login` | `{email, password}` → session `{access_token, refresh_token, expires_at, user}`. |
| POST | `/api/auth/refresh` | `{refresh_token}` → new session (each refresh token works once). |
| POST | `/api/auth/logout` | Ends the caller's session (its refresh token stops working). |
| POST | `/api/auth/recover` | `{email, redirect_to?}`: emails a link to choose a new password. Same answer for unknown emails. |
| PUT | `/api/auth/password` | `{password, current_password?}` → new session. `current_password` is required unless the session comes from a recovery link. |
| GET | `/api/categories` | Active categories, in menu order. No session needed. |
| GET | `/api/products?featured=true`, `?category=<slug>`, `&sort=price\|price_desc\|name` | Active products with variants and images; a category includes its sub-categories (404 if it doesn't exist). Cheapest first by default (lowest active variant price, as shown on the cards); `name` is alphabetical in Spanish. |
| GET | `/api/products/:slug` | One active product (404 if not found or inactive). |
| GET | `/api/settings` | Shipping and contact settings. |
| GET / PATCH / DELETE | `/api/me` | Current profile (created on first call) / update `{full_name, phone}` / delete the account with `{password}`. The email can't be changed. Deleting keeps the orders (without `user_id`) and is refused for admins. |
| GET | `/api/cart` | Cart with nested products and totals. |
| POST | `/api/cart/items` | Add `{variant_id, quantity, customization}`. |
| PATCH / DELETE | `/api/cart/items/:id` | Set `{quantity}` (0 removes) / remove. |
| POST | `/api/checkout` | Place an order from the cart. |
| GET | `/api/orders`, `/api/orders/:id` | Own orders (admins can open any order). |
| POST | `/api/orders/:id/cancel` | Cancel a pending order. |
| GET | `/api/admin/orders?status=` | All orders. |
| PATCH | `/api/admin/orders/:id` | `{status?, admin_notes?}`. |
| POST | `/api/admin/devices` | Register this device for new-order notifications: `{fid, platform: "android"}`. |
| GET / POST | `/api/admin/categories` | All categories (including inactive, with `product_count`) / create `{name, slug, parent_id, description, is_active}`. |
| PUT / PATCH / DELETE | `/api/admin/categories/:id` | Replace / toggle `{is_active}` / delete (only if it has no products or sub-categories). |
| POST | `/api/admin/categories/:id/move` | `{direction: "up" \| "down"}` among its siblings. |
| GET / POST | `/api/admin/products` | List all / create with `variants` and `category_ids` (the first is the main category). |
| GET / PUT / PATCH / DELETE | `/api/admin/products/:id` | Read / replace with variants / toggle `is_active`, `is_featured` / delete. |
| POST | `/api/admin/products/:id/images/upload-url` | `{file_name}` → `{bucket, path, token, content_type}`: a one-time signed upload for the Supabase SDK. |
| POST | `/api/admin/products/:id/images` | Register `{storage_path}` or `{url}`. |
| DELETE | `/api/admin/images/:id` | Delete an image (and its file). |
| PUT | `/api/admin/settings` | Update shipping and contact settings. |

Errors come back as `{"error": "..."}` with 400 (invalid input), 401, 403, 404,
409 (business rule, e.g. out of stock) or 429 (too many attempts). Authentication
errors also carry a `code` (`invalid_credentials`, `email_not_confirmed`,
`wrong_password`, `over_request_rate_limit`...) that the app turns into a message
in Spanish.

## Development

```bash
npm run typecheck                              # API
cd app && flutter analyze && flutter test      # Flutter
```
