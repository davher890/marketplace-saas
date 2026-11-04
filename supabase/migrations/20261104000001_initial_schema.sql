-- =============================================================================
-- Doña Galleta - initial schema
-- Catalog (categories, products, variants, images), carts, orders and profiles.
-- Users live in Supabase's auth.users; `profiles` extends them with app data.
-- All money amounts are stored as integer cents (EUR) to avoid rounding issues.
--
-- The database only stores data: there are no functions or triggers. All the
-- business logic (updated_at, profile creation, carts, checkout, stock, order
-- status history...) lives in the API (`server/`).
-- =============================================================================

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
-- Profiles (1:1 with auth.users). The API creates the row on first sign in.
-- -----------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text,
  phone       text,
  role        public.user_role not null default 'customer',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Categories (two levels on the current site, but any depth is supported)
-- -----------------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  parent_id   uuid references public.categories (id) on delete set null,
  name        text not null,
  slug        text not null unique,
  description text,
  image_url   text,
  position    integer not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index categories_parent_id_idx on public.categories (parent_id);

-- -----------------------------------------------------------------------------
-- Products
-- A product is what the customer browses. What they actually buy is a
-- variant (size, color...). Every product has at least one variant.
-- -----------------------------------------------------------------------------
create table public.products (
  id                uuid primary key default gen_random_uuid(),
  category_id       uuid references public.categories (id) on delete set null,
  name              text not null,
  slug              text not null unique,
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

-- -----------------------------------------------------------------------------
-- Product variants
-- `options` holds the attribute combination, e.g. {"Size": "2 years", "Color": "Blue"}.
-- `stock` NULL means "made to order" (no stock tracking).
-- -----------------------------------------------------------------------------
create table public.product_variants (
  id           uuid primary key default gen_random_uuid(),
  product_id   uuid not null references public.products (id) on delete cascade,
  sku          text unique,
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
-- Carts (one active cart per user)
-- -----------------------------------------------------------------------------
create table public.carts (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null unique references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

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

-- Timeline of every status change (who and when), written by the API.
create table public.order_status_history (
  id          bigint generated always as identity primary key,
  order_id    uuid not null references public.orders (id) on delete cascade,
  from_status public.order_status,
  to_status   public.order_status not null,
  changed_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);

create index order_status_history_order_id_idx on public.order_status_history (order_id);

-- -----------------------------------------------------------------------------
-- Shop settings (single row, edited from the admin panel)
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
