-- =============================================================================
-- Store pickup and a Madrid shipping rate.
--
-- * shop_settings.shipping_madrid_cents: shipping to postal codes starting
--   with 28 (Madrid). NULL: Madrid pays the normal rate (shipping_flat_cents).
-- * orders.delivery_method: 'shipping' (to the address) or 'pickup' (in the
--   shop, free shipping and no address).
--
-- Run before deploying the API that uses them. Safe to run more than once.
-- =============================================================================

alter table public.shop_settings
  add column if not exists shipping_madrid_cents integer
  check (shipping_madrid_cents is null or shipping_madrid_cents >= 0);

alter table public.orders
  add column if not exists delivery_method text not null default 'shipping';

alter table public.orders drop constraint if exists orders_delivery_method_check;
alter table public.orders
  add constraint orders_delivery_method_check check (delivery_method in ('shipping', 'pickup'));
