-- =============================================================================
-- Payment is no longer an order status. Orders go
--   received → processing → shipped → delivered   (or cancelled)
-- and whether they are paid is `orders.paid_at` (null = not paid), set by hand
-- from the admin panel for now and by the payment gateway later.
--
-- Existing data:
--   - 'pending' and 'paid' orders become 'received'; 'paid' ones keep paid_at.
--   - Delivered orders without paid_at are marked paid (at their last update).
--   - In the history, the "→ paid" steps are removed and "paid →" steps start
--     from 'received' instead.
--
-- Safe to run more than once: it does nothing once the new type is in place.
-- =============================================================================

do $$
begin
  if exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'dona_galleta' and t.typname = 'order_status' and e.enumlabel = 'received'
  ) then
    raise notice 'order_status already migrated, nothing to do';
    return;
  end if;

  -- Payment dates first, while the old statuses are still there.
  update dona_galleta.orders
  set paid_at = coalesce(paid_at, updated_at)
  where status in ('paid', 'delivered') and paid_at is null;

  delete from dona_galleta.order_status_history where to_status = 'paid';

  alter type dona_galleta.order_status rename to order_status_old;
  create type dona_galleta.order_status as enum (
    'received',    -- placed, not started yet
    'processing',  -- being made
    'shipped',     -- sent (or ready to pick up)
    'delivered',
    'cancelled'
  );

  alter table dona_galleta.orders alter column status drop default;
  alter table dona_galleta.orders
    alter column status type dona_galleta.order_status
    using (case when status::text in ('pending', 'paid') then 'received' else status::text end)::dona_galleta.order_status;
  alter table dona_galleta.orders alter column status set default 'received';

  alter table dona_galleta.order_status_history
    alter column from_status type dona_galleta.order_status
    using (case when from_status::text in ('pending', 'paid') then 'received' else from_status::text end)::dona_galleta.order_status,
    alter column to_status type dona_galleta.order_status
    using (case when to_status::text = 'pending' then 'received' else to_status::text end)::dona_galleta.order_status;

  drop type dona_galleta.order_status_old;
end
$$;

-- Lists of unpaid orders in the admin panel.
create index if not exists orders_paid_at_idx on dona_galleta.orders (paid_at);

notify pgrst, 'reload schema';
