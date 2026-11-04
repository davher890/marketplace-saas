-- =============================================================================
-- Row Level Security
--   * Catalog: anyone can read active items; admins manage everything.
--   * Carts: each user sees and edits only their own.
--   * Orders: customers read their own; only place_order() creates them;
--     admins read and update all.
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
-- Profiles
-- -----------------------------------------------------------------------------
create policy "Users read own profile, admins read all"
  on public.profiles for select
  to authenticated
  using (id = auth.uid() or public.is_admin());

create policy "Users update own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "Admins update any profile"
  on public.profiles for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Customers may only edit their contact fields, never their role.
revoke update on public.profiles from authenticated;
grant update (full_name, phone) on public.profiles to authenticated;

-- -----------------------------------------------------------------------------
-- Catalog
-- -----------------------------------------------------------------------------
create policy "Public reads active categories"
  on public.categories for select
  to anon, authenticated
  using (is_active or public.is_admin());

create policy "Admins manage categories"
  on public.categories for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "Public reads active products"
  on public.products for select
  to anon, authenticated
  using (is_active or public.is_admin());

create policy "Admins manage products"
  on public.products for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "Public reads active variants"
  on public.product_variants for select
  to anon, authenticated
  using (
    public.is_admin()
    or (
      is_active
      and exists (select 1 from public.products p where p.id = product_id and p.is_active)
    )
  );

create policy "Admins manage variants"
  on public.product_variants for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "Public reads images of active products"
  on public.product_images for select
  to anon, authenticated
  using (
    public.is_admin()
    or exists (select 1 from public.products p where p.id = product_id and p.is_active)
  );

create policy "Admins manage images"
  on public.product_images for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -----------------------------------------------------------------------------
-- Shop settings
-- -----------------------------------------------------------------------------
create policy "Public reads shop settings"
  on public.shop_settings for select
  to anon, authenticated
  using (true);

create policy "Admins update shop settings"
  on public.shop_settings for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- -----------------------------------------------------------------------------
-- Carts
-- -----------------------------------------------------------------------------
create policy "Users manage own cart"
  on public.carts for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "Users manage own cart items"
  on public.cart_items for all
  to authenticated
  using (exists (select 1 from public.carts c where c.id = cart_id and c.user_id = auth.uid()))
  with check (exists (select 1 from public.carts c where c.id = cart_id and c.user_id = auth.uid()));

-- -----------------------------------------------------------------------------
-- Orders (no insert policy: orders are only created through place_order())
-- -----------------------------------------------------------------------------
create policy "Users read own orders, admins read all"
  on public.orders for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy "Admins update orders"
  on public.orders for update
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "Admins delete orders"
  on public.orders for delete
  to authenticated
  using (public.is_admin());

create policy "Users read own order items, admins read all"
  on public.order_items for select
  to authenticated
  using (
    public.is_admin()
    or exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid())
  );

create policy "Users read own order history, admins read all"
  on public.order_status_history for select
  to authenticated
  using (
    public.is_admin()
    or exists (select 1 from public.orders o where o.id = order_id and o.user_id = auth.uid())
  );

-- -----------------------------------------------------------------------------
-- Function privileges
-- -----------------------------------------------------------------------------
revoke execute on function public.place_order(text, jsonb, text, text, text) from public, anon;
grant execute on function public.place_order(text, jsonb, text, text, text) to authenticated;

revoke execute on function public.cancel_order(uuid) from public, anon;
grant execute on function public.cancel_order(uuid) to authenticated;

revoke execute on function public.add_to_cart(uuid, integer, text) from public, anon;
grant execute on function public.add_to_cart(uuid, integer, text) to authenticated;

revoke execute on function public.get_or_create_cart() from public, anon;
grant execute on function public.get_or_create_cart() to authenticated;

-- -----------------------------------------------------------------------------
-- Storage: public bucket for product images, writable by admins only.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do nothing;

create policy "Public reads product images"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'product-images');

create policy "Admins upload product images"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'product-images' and public.is_admin());

create policy "Admins update product images"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'product-images' and public.is_admin());

create policy "Admins delete product images"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'product-images' and public.is_admin());
