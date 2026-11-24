-- =============================================================================
-- Discount coupons.
--
-- * coupons: created from the admin panel ("Cupones"). The code is unique
--   regardless of case and stored in capitals. Valid from starts_on to
--   ends_on, both days included (Spain's calendar).
--     usage:         'once_per_user'  each customer can use it on one order
--                                     (cancelled orders don't count);
--                    'once_per_order' usable on any number of orders.
--                    An order always takes one coupon at most.
--     discount_type: 'amount'        amount_cents off the final price;
--                    'percent'       percent % off the final price;
--                    'free_shipping' the shipping is free.
--   "Final price" is products + shipping, and the discount never goes
--   below 0. Only the API (service role) reads or writes coupons.
-- * orders.coupon_id / coupon_code / discount_cents: the coupon used and what
--   it took off. total_cents = subtotal_cents + shipping_cents - discount_cents.
--
-- Run before deploying the API that uses them. Safe to run more than once.
-- (Migration 11 is the online payment one, in its own pull request.)
-- =============================================================================

create table if not exists dona_galleta.coupons (
  id             uuid primary key default gen_random_uuid(),
  code           text not null check (code = upper(code) and length(code) between 3 and 30),
  description    text not null default '',
  starts_on      date not null,
  ends_on        date not null,
  usage          text not null check (usage in ('once_per_user', 'once_per_order')),
  discount_type  text not null check (discount_type in ('amount', 'percent', 'free_shipping')),
  amount_cents   integer,
  percent        integer,
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint coupons_dates check (ends_on >= starts_on),
  constraint coupons_value check (
    (discount_type = 'amount' and amount_cents > 0 and percent is null)
    or (discount_type = 'percent' and percent between 1 and 100 and amount_cents is null)
    or (discount_type = 'free_shipping' and amount_cents is null and percent is null)
  )
);

create unique index if not exists coupons_code_key on dona_galleta.coupons (code);

-- No policies: customers can't list coupons, only the API can.
alter table dona_galleta.coupons enable row level security;
grant all on dona_galleta.coupons to service_role;

alter table dona_galleta.orders
  add column if not exists coupon_id uuid references dona_galleta.coupons (id) on delete set null,
  add column if not exists coupon_code text,
  add column if not exists discount_cents integer not null default 0;

alter table dona_galleta.orders drop constraint if exists orders_discount_cents_check;
alter table dona_galleta.orders
  add constraint orders_discount_cents_check check (discount_cents >= 0);

-- "Has this customer used this coupon already?"
create index if not exists orders_coupon_user_idx on dona_galleta.orders (coupon_id, user_id);

notify pgrst, 'reload schema';
