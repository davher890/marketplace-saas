-- =============================================================================
-- Access rules, storage bucket and default settings.
-- Safe to run more than once.
--
-- Access model:
--   * The Flutter app reads the PUBLIC catalog directly from Supabase
--     (categories, products, variants, images, shop settings), so those tables
--     get read-only policies for anon/authenticated.
--   * Everything else (profiles, carts, orders and every write) goes through
--     the API, which connects to Postgres directly and enforces the rules in
--     code. Tables without policies are invisible to the anon/authenticated
--     roles, so the Supabase public key alone can't read or change them.
-- =============================================================================

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
-- Public, read-only catalog
-- -----------------------------------------------------------------------------
drop policy if exists "Public reads active categories" on public.categories;
create policy "Public reads active categories"
  on public.categories for select
  to anon, authenticated
  using (is_active);

drop policy if exists "Public reads active products" on public.products;
create policy "Public reads active products"
  on public.products for select
  to anon, authenticated
  using (is_active);

drop policy if exists "Public reads active variants" on public.product_variants;
create policy "Public reads active variants"
  on public.product_variants for select
  to anon, authenticated
  using (
    is_active
    and exists (select 1 from public.products p where p.id = product_id and p.is_active)
  );

drop policy if exists "Public reads images of active products" on public.product_images;
create policy "Public reads images of active products"
  on public.product_images for select
  to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.is_active));

drop policy if exists "Public reads shop settings" on public.shop_settings;
create policy "Public reads shop settings"
  on public.shop_settings for select
  to anon, authenticated
  using (true);

-- -----------------------------------------------------------------------------
-- Default settings row
-- -----------------------------------------------------------------------------
insert into public.shop_settings (id, shipping_flat_cents, free_shipping_threshold_cents, contact_email, contact_phone)
values (true, 495, 5000, 'donagalletashop@gmail.com', '676 00 35 63')
on conflict (id) do nothing;

-- -----------------------------------------------------------------------------
-- Storage: public bucket for product images. Files are publicly readable
-- through their public URL; uploads use signed URLs issued by the API.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;
