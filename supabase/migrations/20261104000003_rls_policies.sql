-- =============================================================================
-- Row Level Security. Safe to run more than once: every policy is dropped and
-- created again.
--
-- Who queries Supabase:
--   * The Flutter app, with the publishable key: sign in and READ the public
--     catalog (anon / authenticated).
--   * The API as the calling user (publishable key + their access token): the
--     user's profile, cart and orders, so auth.uid() is the real caller.
--   * The API with the secret key (service role, not subject to RLS): creating
--     orders, status changes, stock and the admin panel, always after checking
--     who is calling.
--
-- Customers never get write access to orders or the catalog: otherwise they
-- could create orders with any price through the REST API.
-- The product-images bucket is public and uploads use signed URLs issued by
-- the API, so no storage.objects policies are needed.
-- =============================================================================

-- Enable RLS on every table ---------------------------------------------------
alter table public.profiles             enable row level security;
alter table public.categories           enable row level security;
alter table public.products             enable row level security;
alter table public.product_variants     enable row level security;
alter table public.product_images       enable row level security;
alter table public.carts                enable row level security;
alter table public.cart_items           enable row level security;
alter table public.orders               enable row level security;
alter table public.order_items          enable row level security;
alter table public.order_status_history enable row level security;
alter table public.shop_settings        enable row level security;

-- -----------------------------------------------------------------------------
-- Public catalog: read only, active items
-- -----------------------------------------------------------------------------
drop policy if exists "Public reads active categories" on public.categories;
create policy "Public reads active categories"
  on public.categories for select to anon, authenticated
  using (is_active);

drop policy if exists "Public reads active products" on public.products;
create policy "Public reads active products"
  on public.products for select to anon, authenticated
  using (is_active);

drop policy if exists "Public reads active variants" on public.product_variants;
create policy "Public reads active variants"
  on public.product_variants for select to anon, authenticated
  using (
    is_active
    and exists (select 1 from public.products p where p.id = product_id and p.is_active)
  );

drop policy if exists "Public reads images of active products" on public.product_images;
create policy "Public reads images of active products"
  on public.product_images for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.is_active));

drop policy if exists "Public reads shop settings" on public.shop_settings;
create policy "Public reads shop settings"
  on public.shop_settings for select to anon, authenticated
  using (true);

-- -----------------------------------------------------------------------------
-- Profiles: each user reads, creates and edits their own
-- -----------------------------------------------------------------------------
drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists "Users create own profile" on public.profiles;
create policy "Users create own profile"
  on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));

drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Customers may only write their contact fields, never `role`.
revoke insert, update on public.profiles from anon, authenticated;
grant insert (id, full_name, phone) on public.profiles to authenticated;
grant update (full_name, phone, updated_at) on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- Carts: each user fully manages their own cart and its lines
-- -----------------------------------------------------------------------------
drop policy if exists "Users manage own cart" on public.carts;
create policy "Users manage own cart"
  on public.carts for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "Users manage own cart items" on public.cart_items;
create policy "Users manage own cart items"
  on public.cart_items for all to authenticated
  using (exists (
    select 1 from public.carts c
    where c.id = cart_id and c.user_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.carts c
    where c.id = cart_id and c.user_id = (select auth.uid())
  ));

-- -----------------------------------------------------------------------------
-- Orders: customers only read their own (the API writes them with the secret key)
-- -----------------------------------------------------------------------------
drop policy if exists "Users read own orders" on public.orders;
create policy "Users read own orders"
  on public.orders for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users read own order items" on public.order_items;
create policy "Users read own order items"
  on public.order_items for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and o.user_id = (select auth.uid())
  ));

drop policy if exists "Users read own order history" on public.order_status_history;
create policy "Users read own order history"
  on public.order_status_history for select to authenticated
  using (exists (
    select 1 from public.orders o
    where o.id = order_id and o.user_id = (select auth.uid())
  ));
