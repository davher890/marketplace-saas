-- =============================================================================
-- Online payment with Stripe Checkout.
--
-- * shop_settings.online_payment_public: whether customers see the "Pagar
--   ahora" option. While false, only admins do (to try it out).
-- * orders.paid_via: how a paid order was paid: 'manual' (marked from the
--   admin panel) or 'stripe' (confirmed by Stripe's webhook). NULL while not
--   paid. Orders paid before this migration are 'manual'.
-- * orders.stripe_checkout_session_id / stripe_payment_intent_id: the last
--   Stripe Checkout session opened for the order, and the payment it ended in
--   (to find it in the Stripe Dashboard, e.g. for a refund).
--
-- Run before deploying the API that uses them. Safe to run more than once.
-- =============================================================================

alter table dona_galleta.shop_settings
  add column if not exists online_payment_public boolean not null default false;

alter table dona_galleta.orders
  add column if not exists paid_via text,
  add column if not exists stripe_checkout_session_id text,
  add column if not exists stripe_payment_intent_id text;

alter table dona_galleta.orders drop constraint if exists orders_paid_via_check;
alter table dona_galleta.orders
  add constraint orders_paid_via_check check (paid_via is null or paid_via in ('manual', 'stripe'));

update dona_galleta.orders set paid_via = 'manual' where paid_at is not null and paid_via is null;

-- The webhook finds the order by its session.
create index if not exists orders_stripe_checkout_session_id_idx
  on dona_galleta.orders (stripe_checkout_session_id);

notify pgrst, 'reload schema';
