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
- The release APK is signed with the debug key (`android/app/build.gradle`). That is
  fine for your own devices; publishing on Google Play needs your own signing key.

**Checks**:

```bash
npm run typecheck                            # API
cd app && flutter analyze && flutter test    # app
```

## Architecture

```
Flutter app ──(sign in / sign up / password)────────────────► Supabase Auth
     │
     └──(all data; Bearer <access token> when signed in)──► Vercel API ──(supabase-js)──► Supabase REST / Auth / Storage
                                     ├─ publishable key (public catalog, RLS applies)
                                     ├─ as the user (their token, RLS applies)
                                     └─ service role (admin, orders, stock), after its own checks
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
- **The app gets all its data from the API**, the public catalog included
  (`/api/categories`, `/api/products`, `/api/settings`). It only talks to Supabase
  for authentication, to upload admin images to a signed URL issued by the API,
  and to load the product image files (public bucket URLs).
- **RLS** ([`…03_rls_policies.sql`](supabase/migrations/20261104000003_rls_policies.sql)):
  anyone reads the active catalog; each user reads and writes only their own
  profile (never the `role` column) and cart, and reads only their own orders.
  Nobody but the service role writes orders or the catalog.

## Data model

```
auth.users ─1:1─ profiles (role: customer | admin)
     │
     ├─1:1─ carts ─1:N─ cart_items ──N:1─┐
     │                                   │
     └─1:N─ orders ─1:N─ order_items     │
              └─1:N─ order_status_history│
                                         ▼
categories ─1:N─ products ─1:N─ product_variants
  (tree)            └─1:N─ product_images
shop_settings (single row: shipping cost, free-shipping threshold, contact)
```

- **Money** is stored as integer cents (EUR).
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
| Images uploaded straight to Storage with a signed URL from the API (JPG/PNG/WEBP/GIF only) | `products.ts` |
| Shipping: flat rate, free above a threshold | `settings.ts` |
| Profile: name and phone editable (phone validated); email fixed. Password change and recovery use Supabase Auth from the app, and a change asks for the current password | `profiles.ts`, app `profile_repository.dart` |

## Setup

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Run the SQL files in `supabase/migrations/`, in order, in the SQL editor
   (or with `supabase db push`):
   - `…01_initial_schema.sql`: tables and indexes.
   - `…02_defaults_and_storage.sql`: the default settings row and the
     `product-images` bucket.
   - `…03_rls_policies.sql`: Row Level Security for every table.

   The last two are safe to run more than once.
3. Authentication → URL Configuration: set **Site URL** to the deployed web app and
   add these **Redirect URLs**, so password recovery emails open the app's
   `/reset-password` page:
   - `http://localhost:8000/**`
   - `https://<your-vercel-domain>/**`
4. Optional: load sample data with `supabase/seed.sql`.
5. Sign up in the app, then make yourself admin in the SQL editor:
   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'you@example.com');
   ```

### 2. API environment

Copy [`.env.example`](.env.example) to `.env` and fill in the values:

| Variable | Where to find it |
| --- | --- |
| `SUPABASE_URL` | Project Settings → API |
| `SUPABASE_PUBLISHABLE_KEY` | Project Settings → API Keys → Publishable key (`sb_publishable_…`) |
| `SUPABASE_SECRET_KEY` | Project Settings → API Keys → Secret keys (`sb_secret_…`). Server only |
| `ALLOWED_ORIGINS` | Only for local development across origins |

```bash
npm install
npm run dev:api        # http://localhost:3000/api
```

### 3. Run the app

```bash
cd app
cp env.example.json env.json   # SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, API_BASE_URL
flutter run -d chrome --web-port 8000 --dart-define-from-file=env.json
```

`API_BASE_URL` is `http://localhost:3000` locally, or your Vercel URL. On Android it
must always be set; on the deployed web app leave it empty to use the same origin.

### 4. Deploy to Vercel

1. Import the repository in Vercel (root directory = repository root).
2. Add the environment variables from `.env.example`, including
   `SUPABASE_PUBLISHABLE_KEY` for the web build.
3. Deploy. `scripts/vercel-build.sh` installs the pinned Flutter version and builds the
   web app into `app/build/web`. `vercel.json` sends every `/api/*` request to the
   single function in `api/index.ts`, and everything else to the Flutter app.

## API

All bodies are JSON in snake_case. Authenticated routes need
`Authorization: Bearer <supabase access token>`; `/api/admin/*` also needs the admin role.

| Method | Path | Description |
| --- | --- | --- |
| GET | `/api/health` | Health check. |
| GET | `/api/categories` | Active categories, in menu order. No session needed. |
| GET | `/api/products?featured=true`, `?category=<slug>` | Active products with variants and images; a category includes its sub-categories (404 if it doesn't exist). |
| GET | `/api/products/:slug` | One active product (404 if not found or inactive). |
| GET | `/api/settings` | Shipping and contact settings. |
| GET / PATCH | `/api/me` | Current profile (created on first call) / update `{full_name, phone}`. The email can't be changed. |
| GET | `/api/cart` | Cart with nested products and totals. |
| POST | `/api/cart/items` | Add `{variant_id, quantity, customization}`. |
| PATCH / DELETE | `/api/cart/items/:id` | Set `{quantity}` (0 removes) / remove. |
| POST | `/api/checkout` | Place an order from the cart. |
| GET | `/api/orders`, `/api/orders/:id` | Own orders (admins can open any order). |
| POST | `/api/orders/:id/cancel` | Cancel a pending order. |
| GET | `/api/admin/orders?status=` | All orders. |
| PATCH | `/api/admin/orders/:id` | `{status?, admin_notes?}`. |
| GET / POST | `/api/admin/categories` | All categories (including inactive, with `product_count`) / create `{name, slug, parent_id, description, is_active}`. |
| PUT / PATCH / DELETE | `/api/admin/categories/:id` | Replace / toggle `{is_active}` / delete (only if it has no products or sub-categories). |
| POST | `/api/admin/categories/:id/move` | `{direction: "up" \| "down"}` among its siblings. |
| GET / POST | `/api/admin/products` | List all / create with `variants`. |
| GET / PUT / PATCH / DELETE | `/api/admin/products/:id` | Read / replace with variants / toggle `is_active`, `is_featured` / delete. |
| POST | `/api/admin/products/:id/images/upload-url` | Signed upload URL for `{file_name}`. |
| POST | `/api/admin/products/:id/images` | Register `{storage_path}` or `{url}`. |
| DELETE | `/api/admin/images/:id` | Delete an image (and its file). |
| PUT | `/api/admin/settings` | Update shipping and contact settings. |

Errors come back as `{"error": "..."}` with 400 (invalid input), 401, 403, 404 or
409 (business rule, e.g. out of stock).

## Development

```bash
npm run typecheck                              # API
cd app && flutter analyze && flutter test      # Flutter
```
