# Doña Galleta

Product and order management for Doña Galleta: a storefront for customers and an
admin panel for products and orders. The same Flutter app runs on the web and on Android.

| Part | Tech | Folder |
| --- | --- | --- |
| App (web + Android) | Flutter, Riverpod, go_router | [`app/`](app/) |
| Database, auth, storage | Supabase (Postgres + RLS) | [`supabase/`](supabase/) |
| API + web hosting | Vercel serverless functions | [`api/`](api/), [`vercel.json`](vercel.json) |

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

### Server-side logic (SQL functions)

| Function | What it does |
| --- | --- |
| `add_to_cart(variant, qty, customization)` | Creates the cart if needed and adds/merges the line. |
| `place_order(...)` | Atomic checkout: re-reads prices, locks and decrements stock, computes shipping, creates the order and empties the cart. |
| `cancel_order(order)` | Customers cancel their own *pending* orders; admins any order. Restores stock. |
| `is_admin()` | Used by RLS policies. |

### Security (RLS)

- Catalog: anyone reads active items; admins manage everything.
- Carts: each user only sees their own.
- Orders: customers read their own; they are only created via `place_order`. Admins read and update all.
- Customers can edit `full_name` / `phone` on their profile but never their `role`.
- Storage bucket `product-images`: public read, admin write.

## Setup

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Apply the migrations, either with the CLI:
   ```bash
   supabase link --project-ref YOUR-PROJECT-REF
   supabase db push
   ```
   or by pasting the files in `supabase/migrations/` (in order) into the SQL editor.
3. Optionally load sample data: run `supabase/seed.sql` in the SQL editor.
4. Sign up in the app, then make yourself admin in the SQL editor:
   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'you@example.com');
   ```

### 2. Run the app locally

```bash
cd app
cp env.example.json env.json   # fill in SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY
flutter run -d chrome --dart-define-from-file=env.json
```

Android (emulator or device): set `API_BASE_URL` in `env.json` to your Vercel URL
(the Android app can't use relative URLs), then:

```bash
flutter run -d android --dart-define-from-file=env.json
```

To test checkout locally on the web, run the API with `npm run dev` (Vercel CLI, port 3000),
set `API_BASE_URL=http://localhost:3000` in `env.json`, and add the Flutter dev origin to
`ALLOWED_ORIGINS` in `.env`.

### 3. Deploy to Vercel

1. Import the repository in Vercel (root directory = repository root).
2. Add the environment variables from [`.env.example`](.env.example).
3. Deploy. `scripts/vercel-build.sh` installs the pinned Flutter version, builds the web
   app into `app/build/web`, and Vercel serves it together with the functions in `api/`.

## API

| Method | Path | Description |
| --- | --- | --- |
| GET | `/api/health` | Health check. |
| POST | `/api/checkout` | Places an order from the caller's cart. Requires `Authorization: Bearer <supabase access token>`. |

The API acts on behalf of the user (it forwards their JWT), so RLS applies. It's the
place to add payments (PayPal / Stripe), confirmation emails and webhooks.

## Development

```bash
cd app && flutter analyze && flutter test   # Flutter
npm install && npm run typecheck            # API
```
