-- =============================================================================
-- Moves every shop table and type from `public` to the `dona_galleta` schema.
--
-- ALTER ... SET SCHEMA keeps the data, indexes, constraints, identity
-- sequences, RLS policies and grants (including the column grants on
-- profiles), so nothing is copied. Storage (the product-images bucket) and
-- Supabase Auth are not affected.
--
-- After running it, add `dona_galleta` to Project Settings → Data API →
-- Exposed schemas, and deploy the API that uses it (server/supabase.ts).
-- From now on, new migrations create objects in `dona_galleta`; don't re-run
-- the older ones, they would create empty tables in `public` again.
--
-- Safe to run more than once: whatever was already moved is skipped.
-- =============================================================================

create schema if not exists dona_galleta;

-- The API reaches the schema through PostgREST with these roles.
grant usage on schema dona_galleta to anon, authenticated, service_role;

do $$
declare
  name text;
begin
  -- Enum types first: columns keep pointing at them.
  foreach name in array array['user_role', 'order_status'] loop
    if exists (
      select 1 from pg_type t join pg_namespace n on n.oid = t.typnamespace
      where n.nspname = 'public' and t.typname = name
    ) then
      execute format('alter type public.%I set schema dona_galleta', name);
    end if;
  end loop;

  -- Tables (their indexes, sequences, policies and grants move with them).
  foreach name in array array[
    'profiles',
    'categories',
    'products',
    'product_categories',
    'product_variants',
    'product_images',
    'carts',
    'cart_items',
    'orders',
    'order_items',
    'order_status_history',
    'shop_settings',
    'push_devices'
  ] loop
    execute format('alter table if exists public.%I set schema dona_galleta', name);
  end loop;
end
$$;

-- The service role (the API's secret key) bypasses RLS but still needs grants.
grant all on all tables in schema dona_galleta to service_role;
grant all on all sequences in schema dona_galleta to service_role;

-- Tables created later get the same defaults Supabase gives `public`; RLS
-- still decides what anon and authenticated can see.
alter default privileges in schema dona_galleta
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema dona_galleta
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema dona_galleta
  grant all on functions to anon, authenticated, service_role;

-- PostgREST picks up the moved tables.
notify pgrst, 'reload schema';
