-- =============================================================================
-- Shop settings, cart helpers and checkout (place_order)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Single-row settings table, editable by admins from the app.
-- -----------------------------------------------------------------------------
create table public.shop_settings (
  id                             boolean primary key default true check (id), -- enforces a single row
  shipping_flat_cents            integer not null default 495 check (shipping_flat_cents >= 0),
  -- NULL disables free shipping.
  free_shipping_threshold_cents  integer check (free_shipping_threshold_cents is null or free_shipping_threshold_cents >= 0),
  contact_email                  text,
  contact_phone                  text,
  updated_at                     timestamptz not null default now()
);

create trigger shop_settings_set_updated_at
  before update on public.shop_settings
  for each row execute function public.set_updated_at();

insert into public.shop_settings (shipping_flat_cents, free_shipping_threshold_cents, contact_email, contact_phone)
values (495, 5000, 'donagalletashop@gmail.com', '676 00 35 63');

-- -----------------------------------------------------------------------------
-- Returns the current user's cart id, creating the cart if needed.
-- Runs with the caller's permissions, so RLS still applies.
-- -----------------------------------------------------------------------------
create or replace function public.get_or_create_cart()
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_cart_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  select id into v_cart_id from public.carts where user_id = auth.uid();

  if v_cart_id is null then
    insert into public.carts (user_id)
    values (auth.uid())
    on conflict (user_id) do update set updated_at = now()
    returning id into v_cart_id;
  end if;

  return v_cart_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Adds a variant to the cart, or increases its quantity if already there.
-- -----------------------------------------------------------------------------
create or replace function public.add_to_cart(
  p_variant_id    uuid,
  p_quantity      integer default 1,
  p_customization text default ''
)
returns public.cart_items
language plpgsql
set search_path = ''
as $$
declare
  v_cart_id uuid := public.get_or_create_cart();
  v_item    public.cart_items;
begin
  if p_quantity is null or p_quantity < 1 then
    raise exception 'Quantity must be at least 1' using errcode = '22023';
  end if;

  insert into public.cart_items (cart_id, variant_id, quantity, customization)
  values (v_cart_id, p_variant_id, p_quantity, coalesce(trim(p_customization), ''))
  on conflict (cart_id, variant_id, customization)
  do update set quantity = least(public.cart_items.quantity + excluded.quantity, 99)
  returning * into v_item;

  return v_item;
end;
$$;

-- -----------------------------------------------------------------------------
-- Turns the current user's cart into an order, atomically:
--   * re-reads prices from the catalog (never trusts the client),
--   * checks and decrements stock (row locks prevent overselling),
--   * computes shipping from shop_settings,
--   * empties the cart.
-- SECURITY DEFINER because customers cannot insert orders directly.
-- -----------------------------------------------------------------------------
create or replace function public.place_order(
  p_shipping_name    text,
  p_shipping_address jsonb,
  p_shipping_phone   text default null,
  p_contact_email    text default null,
  p_customer_notes   text default null
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id   uuid := auth.uid();
  v_cart_id   uuid;
  v_subtotal  integer := 0;
  v_shipping  integer := 0;
  v_settings  public.shop_settings;
  v_order     public.orders;
  v_line      record;
  v_count     integer := 0;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if coalesce(trim(p_shipping_name), '') = '' then
    raise exception 'Shipping name is required' using errcode = '22023';
  end if;

  if p_shipping_address is null
     or coalesce(trim(p_shipping_address ->> 'line1'), '') = ''
     or coalesce(trim(p_shipping_address ->> 'city'), '') = ''
     or coalesce(trim(p_shipping_address ->> 'postal_code'), '') = '' then
    raise exception 'Shipping address is incomplete' using errcode = '22023';
  end if;

  select id into v_cart_id from public.carts where user_id = v_user_id;
  if v_cart_id is null then
    raise exception 'Cart is empty' using errcode = 'P0001';
  end if;

  -- Lock the variants involved so concurrent checkouts can't oversell.
  for v_line in
    select ci.quantity,
           ci.customization,
           v.id          as variant_id,
           v.name        as variant_name,
           v.sku::text   as sku,
           v.stock,
           v.is_active   as variant_active,
           p.id          as product_id,
           p.name        as product_name,
           p.is_active   as product_active,
           coalesce(v.price_cents, p.base_price_cents) as unit_price_cents
    from public.cart_items ci
    join public.product_variants v on v.id = ci.variant_id
    join public.products p on p.id = v.product_id
    where ci.cart_id = v_cart_id
    order by v.id
    for update of v
  loop
    v_count := v_count + 1;

    if not (v_line.variant_active and v_line.product_active) then
      raise exception 'Product "%" is no longer available', v_line.product_name using errcode = 'P0001';
    end if;

    if v_line.stock is not null and v_line.stock < v_line.quantity then
      raise exception 'Not enough stock for "%" (% left)', v_line.product_name, v_line.stock using errcode = 'P0001';
    end if;

    v_subtotal := v_subtotal + v_line.unit_price_cents * v_line.quantity;
  end loop;

  if v_count = 0 then
    raise exception 'Cart is empty' using errcode = 'P0001';
  end if;

  select * into v_settings from public.shop_settings limit 1;
  if v_settings.free_shipping_threshold_cents is not null
     and v_subtotal >= v_settings.free_shipping_threshold_cents then
    v_shipping := 0;
  else
    v_shipping := coalesce(v_settings.shipping_flat_cents, 0);
  end if;

  insert into public.orders (
    user_id, subtotal_cents, shipping_cents, total_cents,
    contact_email, shipping_name, shipping_phone, shipping_address, customer_notes
  )
  values (
    v_user_id, v_subtotal, v_shipping, v_subtotal + v_shipping,
    coalesce(p_contact_email, (select email from auth.users where id = v_user_id)),
    trim(p_shipping_name), p_shipping_phone, p_shipping_address, p_customer_notes
  )
  returning * into v_order;

  insert into public.order_items (
    order_id, product_id, variant_id, product_name, variant_name, sku,
    unit_price_cents, quantity, customization
  )
  select v_order.id, p.id, v.id, p.name, v.name, v.sku::text,
         coalesce(v.price_cents, p.base_price_cents), ci.quantity, ci.customization
  from public.cart_items ci
  join public.product_variants v on v.id = ci.variant_id
  join public.products p on p.id = v.product_id
  where ci.cart_id = v_cart_id;

  -- Decrement tracked stock (NULL stock = made to order, left untouched).
  update public.product_variants v
  set stock = v.stock - agg.quantity
  from (
    select variant_id, sum(quantity)::integer as quantity
    from public.cart_items
    where cart_id = v_cart_id
    group by variant_id
  ) agg
  where v.id = agg.variant_id and v.stock is not null;

  delete from public.cart_items where cart_id = v_cart_id;

  return v_order;
end;
$$;

-- -----------------------------------------------------------------------------
-- Lets a customer cancel their own order while it is still pending.
-- Restores tracked stock.
-- -----------------------------------------------------------------------------
create or replace function public.cancel_order(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders;
begin
  select * into v_order from public.orders where id = p_order_id for update;

  if v_order.id is null
     or (v_order.user_id is distinct from auth.uid() and not public.is_admin()) then
    raise exception 'Order not found' using errcode = 'P0002';
  end if;

  if v_order.status <> 'pending' and not public.is_admin() then
    raise exception 'Only pending orders can be cancelled' using errcode = 'P0001';
  end if;

  if v_order.status = 'cancelled' then
    return v_order;
  end if;

  update public.product_variants v
  set stock = v.stock + agg.quantity
  from (
    select variant_id, sum(quantity)::integer as quantity
    from public.order_items
    where order_id = p_order_id and variant_id is not null
    group by variant_id
  ) agg
  where v.id = agg.variant_id and v.stock is not null;

  update public.orders set status = 'cancelled' where id = p_order_id
  returning * into v_order;

  return v_order;
end;
$$;
