# Doña Galleta

Product and order management for Doña Galleta: a storefront for customers and an
admin panel for products and orders. The same Flutter app runs on the web and on Android.

| Part | Tech | Folder |
| --- | --- | --- |
| App (web + Android) | Flutter, Riverpod, go_router | [`app/`](app/) |
| API (all business logic) | TypeScript on Vercel, `postgres`, zod | [`server/`](server/), [`api/index.ts`](api/index.ts) |
| Database, auth, storage | Supabase (Postgres) | [`supabase/`](supabase/) |

## Architecture

```
Flutter app ──(public catalog, read only)──────────────► Supabase REST (RLS)
     │
     ├──(sign in / sign up)────────────────────────────► Supabase Auth
     │
     └──(Bearer <access token>)──► Vercel API ──(SQL, transactions)──► Postgres
                                       │
                                       └──(verify token, signed uploads)──► Supabase Auth / Storage
```

- **The database only stores data.** It has no functions or triggers.
- **The API owns every rule:** profiles, carts, checkout, stock, order statuses and
  history, `updated_at`, product and image management, permissions.
  It connects to Postgres directly, so checkout runs in a single transaction with row locks.
- **The app reads the public catalog directly from Supabase** (categories, products,
  variants, images, shop settings). RLS exposes only active items there.
  Everything else goes through the API.

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
| Profile created on first sign in (from `user_metadata.full_name`); customers can't change their role | `profiles.ts` |
| Cart: one per user, lines merged per variant + customization, max 99, stock checked, customization required only for customizable products | `cart.ts` |
| Checkout: prices re-read from the catalog, variants locked (`FOR UPDATE`), stock checked per variant across lines, shipping from settings, stock decremented, cart emptied, all in one transaction | `orders.ts` |
| Status changes: logged with who/when, `paid_at` / `shipped_at` stamped, cancelling restores stock, cancelled orders are final | `orders.ts` |
| Customers cancel only their own *pending* orders; admins any order | `orders.ts` |
| Products saved together with their variants in one transaction | `products.ts` |
| Images uploaded straight to Storage with a signed URL from the API (JPG/PNG/WEBP/GIF only) | `products.ts` |
| Shipping: flat rate, free above a threshold | `settings.ts` |

## Setup

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Run the SQL files in `supabase/migrations/`, in order, in the SQL editor
   (or with `supabase db push`):
   - `…01_initial_schema.sql`: tables and indexes.
   - `…02_access_and_storage.sql`: RLS (public read of the catalog only), the
     default settings row and the `product-images` bucket. Safe to run more than once.
3. Optional: load sample data with `supabase/seed.sql`.
4. Sign up in the app, then make yourself admin in the SQL editor:
   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'you@example.com');
   ```

### 2. API environment

Copy [`.env.example`](.env.example) to `.env` and fill in the values:

| Variable | Where to find it |
| --- | --- |
| `SUPABASE_URL` | Project Settings → API |
| `SUPABASE_SECRET_KEY` | Project Settings → API Keys → Secret keys (`sb_secret_…`) |
| `DATABASE_URL` | Connect → **Transaction pooler** connection string (port 6543) |
| `ALLOWED_ORIGINS` | Only for local development across origins |

```bash
npm install
npm run dev:api        # http://localhost:3000/api
```

### 3. Run the app

```bash
cd app
cp env.example.json env.json   # SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, API_BASE_URL
flutter run -d chrome --web-port 5000 --dart-define-from-file=env.json
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
| GET / PATCH | `/api/me` | Current profile (created on first call) / update name and phone. |
| GET | `/api/cart` | Cart with nested products and totals. |
| POST | `/api/cart/items` | Add `{variant_id, quantity, customization}`. |
| PATCH / DELETE | `/api/cart/items/:id` | Set `{quantity}` (0 removes) / remove. |
| POST | `/api/checkout` | Place an order from the cart. |
| GET | `/api/orders`, `/api/orders/:id` | Own orders (admins can open any order). |
| POST | `/api/orders/:id/cancel` | Cancel a pending order. |
| GET | `/api/admin/orders?status=` | All orders. |
| PATCH | `/api/admin/orders/:id` | `{status?, admin_notes?}`. |
| GET | `/api/admin/categories` | All categories, including inactive. |
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
