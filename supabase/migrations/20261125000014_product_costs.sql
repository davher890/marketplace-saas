-- =============================================================================
-- What each product costs the shop, and what each order cost.
--
-- * suppliers: who the shop buys from (Ajustes → Proveedores), with the cost
--   of picking an order up from them (transport_cents). An order pays each
--   supplier's transport once, however many of its articles come from it.
-- * cost_settings: one row, the price of each box size (S, M, L).
-- * product_costs: per product, its cost, supplier and box size.
-- * variant_costs: a variant's own cost; without one, the product's applies
--   (like the price).
-- * order_item_costs: the costs of each order line, saved when the order is
--   placed, so changing a product's cost later doesn't change past orders.
--     line cost  = unit_cost_cents * quantity + box_cents (one box per line)
--     order cost = sum of line costs + transport_cents of each supplier once
--
-- Costs and suppliers are for the admin only. They live in their own tables
-- (RLS on, no policies: only the API's service role reads them) because the
-- catalog and the customer's orders are readable by customers.
--
-- Run before deploying the API that uses them. Safe to run more than once.
-- (Migration 11 is the online payment one, in its own pull request.)
-- =============================================================================

create table if not exists dona_galleta.suppliers (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (length(btrim(name)) between 1 and 120),
  transport_cents  integer not null default 0 check (transport_cents >= 0),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create unique index if not exists suppliers_name_key on dona_galleta.suppliers (lower(name));

create table if not exists dona_galleta.cost_settings (
  id           boolean primary key default true check (id), -- a single row
  box_s_cents  integer not null default 25 check (box_s_cents >= 0),
  box_m_cents  integer not null default 50 check (box_m_cents >= 0),
  box_l_cents  integer not null default 100 check (box_l_cents >= 0),
  updated_at   timestamptz not null default now()
);

insert into dona_galleta.cost_settings (id) values (true) on conflict (id) do nothing;

create table if not exists dona_galleta.product_costs (
  product_id   uuid primary key references dona_galleta.products (id) on delete cascade,
  cost_cents   integer check (cost_cents is null or cost_cents >= 0),
  supplier_id  uuid references dona_galleta.suppliers (id) on delete set null,
  box_size     text check (box_size is null or box_size in ('S', 'M', 'L')),
  updated_at   timestamptz not null default now()
);

create index if not exists product_costs_supplier_idx on dona_galleta.product_costs (supplier_id);

create table if not exists dona_galleta.variant_costs (
  variant_id  uuid primary key references dona_galleta.product_variants (id) on delete cascade,
  cost_cents  integer not null check (cost_cents >= 0),
  updated_at  timestamptz not null default now()
);

create table if not exists dona_galleta.order_item_costs (
  order_item_id    uuid primary key references dona_galleta.order_items (id) on delete cascade,
  order_id         uuid not null references dona_galleta.orders (id) on delete cascade,
  -- NULL: the product had no cost when the order was placed.
  unit_cost_cents  integer check (unit_cost_cents is null or unit_cost_cents >= 0),
  box_size         text check (box_size is null or box_size in ('S', 'M', 'L')),
  box_cents        integer not null default 0 check (box_cents >= 0),
  supplier_id      uuid references dona_galleta.suppliers (id) on delete set null,
  -- Kept so the order still names the supplier if it's deleted later.
  supplier_name    text,
  transport_cents  integer not null default 0 check (transport_cents >= 0),
  created_at       timestamptz not null default now()
);

create index if not exists order_item_costs_order_idx on dona_galleta.order_item_costs (order_id);

-- No policies: only the API (service role) reads or writes them.
alter table dona_galleta.suppliers        enable row level security;
alter table dona_galleta.cost_settings    enable row level security;
alter table dona_galleta.product_costs    enable row level security;
alter table dona_galleta.variant_costs    enable row level security;
alter table dona_galleta.order_item_costs enable row level security;

revoke all on dona_galleta.suppliers, dona_galleta.cost_settings, dona_galleta.product_costs,
  dona_galleta.variant_costs, dona_galleta.order_item_costs from anon, authenticated;
grant all on dona_galleta.suppliers, dona_galleta.cost_settings, dona_galleta.product_costs,
  dona_galleta.variant_costs, dona_galleta.order_item_costs to service_role;

notify pgrst, 'reload schema';
