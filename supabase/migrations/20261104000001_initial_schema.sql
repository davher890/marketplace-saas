-- =============================================================================
-- Doña Galleta - initial schema
-- Catalog (categories, products, variants, images), carts, orders and profiles.
-- Users live in Supabase's auth.users; `profiles` extends them with app data.
-- All money amounts are stored as integer cents (EUR) to avoid rounding issues.
-- =============================================================================

create extension if not exists citext;

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
create type public.user_role as enum ('customer', 'admin');

create type public.order_status as enum (
  'pending',      -- created, waiting for payment
  'paid',         -- payment confirmed
  'processing',   -- being handmade / prepared
  'shipped',      -- handed to the carrier
  'delivered',    -- received by the customer
  'cancelled'
);

-- -----------------------------------------------------------------------------
-- Shared helpers
-- -----------------------------------------------------------------------------

-- Keeps `updated_at` columns current on every update.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- -----------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text,
  phone       text,
  role        public.user_role not null default 'customer',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- Creates a profile automatically whenever a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- True when the current request belongs to an admin user.
-- SECURITY DEFINER so it can read profiles without tripping RLS recursion.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- -----------------------------------------------------------------------------
-- Categories (two levels on the current site, but any depth is supported)
-- -----------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references public.categories (id) on delete set null,
  name        text not null,
  slug        citext not null unique,
  description text,
  image_url   text,
  position    integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index categories_parent_id_idx on public.categories (parent_id);

create trigger categories_set_updated_at
  before update on public.categories
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Products
-- A product is what the customer browses. What they actually buy is a
-- variant (size, color...). Every product has at least one variant.
-- -----------------------------------------------------------------------------
create table public.products (
  id                uuid primary key default gen_random_uuid(),
  category_id       uuid references public.categories (id) on delete set null,
  name              text not null,
  slug              citext not null unique,
  description       text,
  -- Default price. A variant may override it with its own price.
  base_price_cents  integer not null check (base_price_cents >= 0),
  -- Handmade items that accept a custom text (e.g. a name on a pacifier clip).
  is_customizable   boolean not null default false,
  customization_label text,
  is_active         boolean not null default true,
  is_featured       boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index products_category_id_idx on public.products (category_id);
create index products_active_idx on public.products (is_active) where is_active;

create trigger products_set_updated_at
  before update on public.products
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Product variants
-- `options` holds the attribute combination, e.g. {"Size": "2 years", "Color": "Blue"}.
-- `stock` NULL means "made to order" (no stock tracking).
-- -----------------------------------------------------------------------------
create table public.product_variants (
  id           uuid primary key default gen_random_uuid(),
  product_id   uuid not null references public.products (id) on delete cascade,
  sku          citext unique,
  name         text not null default 'Default',
  options      jsonb not null default '{}'::jsonb check (jsonb_typeof(options) = 'object'),
  price_cents  integer check (price_cents is null or price_cents >= 0),
  stock        integer check (stock is null or stock >= 0),
  position     integer not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index product_variants_product_id_idx on public.product_variants (product_id);

create trigger product_variants_set_updated_at
  before update on public.product_variants
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Product images (optionally tied to a specific variant)
-- -----------------------------------------------------------------------------
create table public.product_images (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.products (id) on delete cascade,
  variant_id  uuid references public.product_variants (id) on delete set null,
  url         text not null,
  -- Path inside the `product-images` storage bucket, when uploaded there.
  storage_path text,
  alt_text    text,
  position    integer not null default 0,
  created_at  timestamptz not null default now()
);

create index product_images_product_id_idx on public.product_images (product_id);

-- -----------------------------------------------------------------------------
-- Carts (one active cart per user; anonymous auth users can have one too)
-- -----------------------------------------------------------------------------
create table public.carts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger carts_set_updated_at
  before update on public.carts
  for each row execute function public.set_updated_at();

create table public.cart_items (
  id             uuid primary key default gen_random_uuid(),
  cart_id        uuid not null references public.carts (id) on delete cascade,
  variant_id     uuid not null references public.product_variants (id) on delete cascade,
  quantity       integer not null check (quantity > 0 and quantity <= 99),
  -- Custom text for customizable products. Empty string = no customization,
  -- so the unique constraint below works without NULL edge cases.
  customization  text not null default '',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (cart_id, variant_id, customization)
);

create index cart_items_cart_id_idx on public.cart_items (cart_id);

create trigger cart_items_set_updated_at
  before update on public.cart_items
  for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Orders
-- Order items snapshot product data so later catalog edits don't alter history.
-- -----------------------------------------------------------------------------
create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  -- Human friendly, sequential number shown to customers ("Order #1042").
  order_number      bigint generated always as identity (start with 1000) unique,
  user_id           uuid references auth.users (id) on delete set null,
  status            public.order_status not null default 'pending',
  currency          char(3) not null default 'EUR',
  subtotal_cents    integer not null check (subtotal_cents >= 0),
  shipping_cents    integer not null default 0 check (shipping_cents >= 0),
  total_cents       integer not null check (total_cents >= 0),
  contact_email     text,
  shipping_name     text not null,
  shipping_phone    text,
  -- {"line1", "line2", "city", "postal_code", "province", "country"}
  shipping_address  jsonb not null,
  customer_notes    text,
  admin_notes       text,
  paid_at           timestamptz,
  shipped_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index orders_user_id_idx on public.orders (user_id);
create index orders_status_idx on public.orders (status);
create index orders_created_at_idx on public.orders (created_at desc);

create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();

create table public.order_items (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references public.orders (id) on delete cascade,
  product_id        uuid references public.products (id) on delete set null,
  variant_id        uuid references public.product_variants (id) on delete set null,
  product_name      text not null,
  variant_name      text not null,
  sku               text,
  unit_price_cents  integer not null check (unit_price_cents >= 0),
  quantity          integer not null check (quantity > 0),
  line_total_cents  integer generated always as (unit_price_cents * quantity) stored,
  customization     text not null default '',
  created_at        timestamptz not null default now()
);

create index order_items_order_id_idx on public.order_items (order_id);

-- Keeps a timeline of every status change (who and when).
create table public.order_status_history (
  id          bigint generated always as identity primary key,
  order_id    uuid not null references public.orders (id) on delete cascade,
  from_status public.order_status,
  to_status   public.order_status not null,
  changed_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

create index order_status_history_order_id_idx on public.order_status_history (order_id);

create or replace function public.log_order_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (new.id, null, new.status, auth.uid());
  elsif new.status is distinct from old.status then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (new.id, old.status, new.status, auth.uid());
    if new.status = 'paid' and new.paid_at is null then
      new.paid_at = now();
    elsif new.status = 'shipped' and new.shipped_at is null then
      new.shipped_at = now();
    end if;
  end if;
  return new;
end;
$$;

create trigger orders_log_status_insert
  after insert on public.orders
  for each row execute function public.log_order_status_change();

create trigger orders_log_status_update
  before update of status on public.orders
  for each row execute function public.log_order_status_change();
