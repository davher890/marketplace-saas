-- =============================================================================
-- A product can be listed in several categories (e.g. a Christmas pack under
-- both "Ideas regalo" and "Profes › Packs profes").
--
-- `product_categories` holds every category a product appears in.
-- `products.category_id` stays as its main category (the first one chosen in
-- the admin) and is always one of those rows; the API keeps both in sync
-- (there are no triggers, see 20261104000001).
--
-- Safe to run more than once.
-- =============================================================================

create table if not exists public.product_categories (
  product_id  uuid not null references public.products (id) on delete cascade,
  category_id uuid not null references public.categories (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (product_id, category_id)
);

-- "Products of these categories" lookups start from the category.
create index if not exists product_categories_category_id_idx
  on public.product_categories (category_id);

-- Existing products keep their current category.
insert into public.product_categories (product_id, category_id)
select id, category_id from public.products where category_id is not null
on conflict do nothing;

-- Row Level Security: anyone can see which categories an active product is
-- in; only the service role (the API's admin client) writes.
alter table public.product_categories enable row level security;

drop policy if exists "Public reads categories of active products" on public.product_categories;
create policy "Public reads categories of active products"
  on public.product_categories for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and p.is_active));
