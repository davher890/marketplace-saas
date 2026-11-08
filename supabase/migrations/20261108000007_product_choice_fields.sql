-- =============================================================================
-- Choice lists on products: the customer picks one value from each list the
-- admin defines, e.g. [{"label": "Color del lazo", "options": ["Rojo", "Azul"]}].
--
-- Unlike variants they don't change the price or the stock. The API checks
-- the picked values and stores them in the cart / order line's
-- `customization`, before the free text ("Color del lazo: Azul · Lucía").
--
-- Safe to run more than once.
-- =============================================================================

alter table public.products
  add column if not exists choice_fields jsonb not null default '[]'::jsonb;

alter table public.products drop constraint if exists products_choice_fields_is_array;
alter table public.products
  add constraint products_choice_fields_is_array check (jsonb_typeof(choice_fields) = 'array');
