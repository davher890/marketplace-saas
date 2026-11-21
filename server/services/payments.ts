import Stripe from 'stripe';

import { isAdmin, type AuthUser } from '../auth';
import { allowedOrigins, badRequest, conflict, HttpError } from '../http';
import { check, now, supabaseAdmin, unwrap } from '../supabase';
import { sendPaymentConfirmedEmail } from './orderEmails';
import { getOrder, getOrderFor, type Order } from './orders';
import { getSettings } from './settings';

// -----------------------------------------------------------------------------
// Online payment with Stripe Checkout (Stripe's hosted payment page).
//
// 1. POST /api/orders/:id/pay creates a Checkout session for an unpaid order
//    and returns its URL; the app sends the customer there.
// 2. Stripe calls POST /api/stripe/webhook when the payment succeeds; the
//    order is marked paid (paid_via 'stripe') and the customer emailed.
// The payment methods offered (cards, Apple Pay, Google Pay, Bizum...) are
// chosen in the Stripe Dashboard. An abandoned session just expires: the
// order stays unpaid and can be paid again or by other means.
//
// Env: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, and SITE_URL for the pages
// Stripe returns to (the browser's origin is used when it is an allowed one).
// -----------------------------------------------------------------------------

let client: Stripe | null = null;

function stripe(): Stripe {
  const key = process.env.STRIPE_SECRET_KEY;
  if (!key) throw new HttpError(503, 'Online payment is not configured', 'payments_not_configured');
  client ??= new Stripe(key);
  return client;
}

/** Customers see online payment once the shop opens it; admins always (to try it). */
export async function canPayOnline(user: AuthUser): Promise<boolean> {
  return (await getSettings()).online_payment_public || (await isAdmin(user));
}

type OrderItem = {
  product_name: string;
  variant_name: string;
  unit_price_cents: number;
  quantity: number;
  customization: string;
};

/** Site the customer comes back to after paying: their own origin when allowed, else SITE_URL. */
export function returnSite(request: Request): string {
  const origin = request.headers.get('origin');
  if (origin && allowedOrigins().includes(origin)) return origin;
  const site = process.env.SITE_URL?.replace(/\/+$/, '');
  if (!site) throw new HttpError(503, 'SITE_URL is not configured', 'payments_not_configured');
  return site;
}

/** The order's lines and shipping as Stripe Checkout parameters. */
export function checkoutParams(order: Order, site: string): Stripe.Checkout.SessionCreateParams {
  const items = (order.order_items ?? []) as unknown as OrderItem[];
  const shipping = order.shipping_cents as number;
  const total = items.reduce((sum, item) => sum + item.unit_price_cents * item.quantity, 0) + shipping;
  // Stripe adds up the lines itself: they must give the order's total.
  if (total !== order.total_cents) throw conflict('The order total does not match its lines');
  const metadata = { order_id: order.id, order_number: String(order.order_number) };

  return {
    mode: 'payment',
    locale: 'es',
    client_reference_id: order.id,
    customer_email: (order.contact_email as string | null) ?? undefined,
    metadata,
    payment_intent_data: { metadata, description: `Pedido #${order.order_number}` },
    line_items: items.map((item) => ({
      quantity: item.quantity,
      price_data: {
        currency: 'eur',
        unit_amount: item.unit_price_cents,
        product_data: {
          name:
            item.variant_name && item.variant_name !== 'Default'
              ? `${item.product_name} · ${item.variant_name}`
              : item.product_name,
          ...(item.customization.trim() && { description: item.customization.trim().slice(0, 500) }),
        },
      },
    })),
    ...(shipping > 0 && {
      shipping_options: [
        {
          shipping_rate_data: {
            type: 'fixed_amount' as const,
            display_name: 'Envío',
            fixed_amount: { amount: shipping, currency: 'eur' },
          },
        },
      ],
    }),
    success_url: `${site}/orders/${order.id}?pago=ok`,
    cancel_url: `${site}/orders/${order.id}?pago=cancelado`,
  };
}

/** Opens a Stripe Checkout session for one of the user's own unpaid orders. */
export async function createCheckout(user: AuthUser, orderId: string, request: Request): Promise<{ url: string }> {
  if (!(await canPayOnline(user))) throw new HttpError(403, 'Online payment is not available yet');
  const order = await getOrderFor(user, orderId, false);
  if (order.status === 'cancelled') throw conflict('Cancelled orders cannot be paid');
  if (order.paid_at) throw conflict('The order is already paid');

  const session = await stripe().checkout.sessions.create(checkoutParams(order, returnSite(request)));
  check(
    (
      await supabaseAdmin()
        .from('orders')
        .update({ stripe_checkout_session_id: session.id, updated_at: now() })
        .eq('id', order.id)
    ).error,
  );
  if (!session.url) throw new HttpError(502, 'Stripe did not return a payment page');
  return { url: session.url };
}

/**
 * Marks the order paid by Stripe. Only the first confirmation counts (Stripe
 * may send an event more than once); an order already marked paid by hand
 * keeps its date but gets the payment's id.
 */
export async function markPaidByStripe(orderId: string, paymentIntentId: string | null): Promise<boolean> {
  const db = supabaseAdmin();
  const updated = unwrap(
    await db
      .from('orders')
      .update({ paid_at: now(), paid_via: 'stripe', stripe_payment_intent_id: paymentIntentId, updated_at: now() })
      .eq('id', orderId)
      .is('paid_at', null)
      .select('id'),
  ) as { id: string }[];
  if (updated.length === 0) {
    check(
      (
        await db
          .from('orders')
          .update({ stripe_payment_intent_id: paymentIntentId })
          .eq('id', orderId)
          .is('stripe_payment_intent_id', null)
      ).error,
    );
    return false;
  }
  const order = await getOrder(db, orderId);
  if (order) {
    if (order.status === 'cancelled') console.warn(`Order ${orderId} was paid through Stripe after being cancelled`);
    await sendPaymentConfirmedEmail(order);
  }
  return true;
}

/** Stripe's webhook. The signature proves the event comes from Stripe. */
export async function handleStripeWebhook(request: Request): Promise<{ received: true }> {
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!secret) throw new HttpError(503, 'Online payment is not configured', 'payments_not_configured');
  const signature = request.headers.get('stripe-signature');
  if (!signature) throw badRequest('Missing Stripe signature');

  let event: Stripe.Event;
  try {
    event = await stripe().webhooks.constructEventAsync(await request.text(), signature, secret);
  } catch {
    throw badRequest('Invalid Stripe signature');
  }

  switch (event.type) {
    // Cards are paid at once; Bizum and other delayed methods confirm later.
    case 'checkout.session.completed':
    case 'checkout.session.async_payment_succeeded': {
      const session = event.data.object;
      const orderId = session.metadata?.order_id ?? session.client_reference_id;
      if (session.payment_status !== 'paid' || !orderId) break;
      const paymentIntent =
        typeof session.payment_intent === 'string' ? session.payment_intent : (session.payment_intent?.id ?? null);
      await markPaidByStripe(orderId, paymentIntent);
      break;
    }
    case 'checkout.session.async_payment_failed':
      console.warn(`Stripe payment failed for order ${event.data.object.metadata?.order_id}`);
      break;
  }
  return { received: true };
}
