import { z } from 'zod';

import type { AuthUser } from '../auth';
import { badRequest, conflict, notFound } from '../http';
import { check, now, supabaseAdmin, unwrap, type DbClient } from '../supabase';
import { loadCartLines, removeOrderedLines } from './cart';
import { sendStatusChangeEmail } from './orderEmails';
import { DELIVERY_METHODS, getSettings, isSpanishPostalCode, shippingFor } from './settings';

export const ORDER_STATUSES = ['pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled'] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export type Order = Record<string, unknown> & {
  id: string;
  user_id: string | null;
  status: OrderStatus;
  paid_at: string | null;
  shipped_at: string | null;
  created_at: string;
  order_items?: { variant_id: string | null; quantity: number; created_at: string }[];
  order_status_history?: { id: number; created_at: string }[];
};

// -----------------------------------------------------------------------------
// Reading. Customers use their own client (RLS: only their orders); the admin
// panel uses the service-role client after the route checked the admin role.
// -----------------------------------------------------------------------------

function sortNested(order: Order): Order {
  order.order_items?.sort((a, b) => a.created_at.localeCompare(b.created_at));
  order.order_status_history?.sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id - b.id);
  return order;
}

export async function listOrders(
  db: DbClient,
  filter: { userId?: string; status?: OrderStatus } = {},
): Promise<Order[]> {
  let query = db.from('orders').select('*, order_items(*)');
  if (filter.userId) query = query.eq('user_id', filter.userId);
  if (filter.status) query = query.eq('status', filter.status);
  const rows = unwrap(await query.order('created_at', { ascending: false }).limit(500)) as Order[];
  return rows.map(sortNested);
}

export async function getOrder(db: DbClient, orderId: string): Promise<Order | null> {
  const order = unwrap(
    await db
      .from('orders')
      .select('*, order_items(*), order_status_history(*)')
      .eq('id', orderId)
      .maybeSingle(),
  ) as Order | null;
  return order ? sortNested(order) : null;
}

/** RLS hides other people's orders, so a customer simply gets "not found". */
export async function getOrderFor(user: AuthUser, orderId: string, admin: boolean): Promise<Order> {
  const order = await getOrder(admin ? supabaseAdmin() : user.db, orderId);
  if (!order) throw notFound('Order not found');
  return order;
}

// -----------------------------------------------------------------------------
// Checkout
// -----------------------------------------------------------------------------

const text = (max: number) => z.string().trim().max(max);

const addressSchema = z.object({
  line1: text(200).min(1, 'Address is required'),
  line2: text(200).default(''),
  city: text(100).min(1, 'City is required'),
  postal_code: text(20)
    .min(1, 'Postal code is required')
    .transform((value) => value.replace(/\s/g, ''))
    .refine(isSpanishPostalCode, 'Postal code must be a Spanish one, e.g. 28010'),
  province: text(100).default(''),
  country: text(2).default('ES'),
});

export const checkoutSchema = z
  .object({
    /** 'pickup': collected in the shop, free shipping and no address. */
    delivery_method: z.enum(DELIVERY_METHODS).default('shipping'),
    shipping_name: text(120).min(1, 'Shipping name is required'),
    shipping_phone: text(40).nullish(),
    contact_email: z.email().max(200).nullish(),
    customer_notes: text(1000).nullish(),
    shipping_address: addressSchema.nullish(),
  })
  .superRefine((input, ctx) => {
    if (input.delivery_method === 'shipping' && !input.shipping_address) {
      ctx.addIssue({ code: 'custom', path: ['shipping_address'], message: 'Address is required' });
    }
  });

/**
 * Turns the user's cart into an order.
 *
 * Prices come from the catalog (read with the user's client), never from the
 * request. Stock isn't tracked, so nothing is reserved. Without database
 * transactions, if writing the lines fails the order is deleted again.
 */
export async function placeOrder(user: AuthUser, input: z.infer<typeof checkoutSchema>): Promise<Order> {
  const { lines, removed } = await loadCartLines(user);
  if (removed > 0) throw conflict('Some products in your cart are no longer available. Please review it.');
  if (lines.length === 0) throw conflict('Cart is empty');

  const subtotal = lines.reduce((sum, line) => sum + line.unit_price_cents * line.quantity, 0);
  const pickup = input.delivery_method === 'pickup';
  const shipping = shippingFor(await getSettings(), subtotal, {
    method: input.delivery_method,
    postalCode: input.shipping_address?.postal_code,
  });
  const admin = supabaseAdmin();
  let orderId: string | null = null;

  try {
    const order = unwrap(
      await admin
        .from('orders')
        .insert({
          user_id: user.id,
          status: 'pending',
          subtotal_cents: subtotal,
          shipping_cents: shipping,
          total_cents: subtotal + shipping,
          contact_email: input.contact_email || user.email,
          shipping_name: input.shipping_name,
          shipping_phone: input.shipping_phone || null,
          delivery_method: input.delivery_method,
          // Pickup orders have no address (the column can't be null).
          shipping_address: pickup ? {} : input.shipping_address,
          customer_notes: input.customer_notes || null,
        })
        .select('id')
        .single(),
    ) as { id: string };
    orderId = order.id;

    check(
      (
        await admin.from('order_items').insert(
          lines.map((line) => ({
            order_id: order.id,
            product_id: line.product_variants.products.id,
            variant_id: line.product_variants.id,
            product_name: line.product_variants.products.name,
            variant_name: line.product_variants.name,
            sku: line.product_variants.sku,
            unit_price_cents: line.unit_price_cents,
            quantity: line.quantity,
            customization: line.customization,
          })),
        )
      ).error,
    );

    await recordStatusChange(order.id, null, 'pending', user.id);
  } catch (error) {
    // Undo what was done so far: the order (its lines cascade).
    if (orderId) await admin.from('orders').delete().eq('id', orderId);
    throw error;
  }

  await removeOrderedLines(
    user,
    lines.map((line) => line.id),
  );
  return (await getOrder(admin, orderId))!;
}

// -----------------------------------------------------------------------------
// Status changes (always written with the service-role client: customers have
// no write access to orders)
// -----------------------------------------------------------------------------

async function recordStatusChange(
  orderId: string,
  from: OrderStatus | null,
  to: OrderStatus,
  changedBy: string,
): Promise<void> {
  check(
    (
      await supabaseAdmin()
        .from('order_status_history')
        .insert({ order_id: orderId, from_status: from, to_status: to, changed_by: changedBy })
    ).error,
  );
}

/**
 * Moves an order to a new status. The update only applies if the order still
 * has the status we read (compare-and-swap), so two simultaneous changes
 * can't both win.
 */
async function transition(order: Order, to: OrderStatus, actorId: string): Promise<boolean> {
  if (order.status === to) return false;
  if (order.status === 'cancelled') throw conflict('Cancelled orders cannot change status');

  const changes: Record<string, unknown> = { status: to, updated_at: now() };
  if (to === 'paid' && !order.paid_at) changes.paid_at = now();
  if (to === 'shipped' && !order.shipped_at) changes.shipped_at = now();

  const updated = unwrap(
    await supabaseAdmin()
      .from('orders')
      .update(changes)
      .eq('id', order.id)
      .eq('status', order.status)
      .select('id'),
  ) as { id: string }[];
  if (updated.length === 0) throw conflict('The order was changed by someone else. Reload and try again.');

  await recordStatusChange(order.id, order.status, to, actorId);
  return true;
}

/** Customers may cancel their own pending orders; admins can cancel any order. */
export async function cancelOrder(user: AuthUser, orderId: string, admin: boolean): Promise<Order> {
  const order = await getOrderFor(user, orderId, admin);
  if (!admin && order.status !== 'pending') throw conflict('Only pending orders can be cancelled');
  const changed = await transition(order, 'cancelled', user.id);
  const updated = (await getOrder(supabaseAdmin(), orderId))!;
  if (changed) await sendStatusChangeEmail(updated);
  return updated;
}

export const adminUpdateOrderSchema = z
  .object({
    status: z.enum(ORDER_STATUSES).optional(),
    admin_notes: z.string().trim().max(2000).nullable().optional(),
  })
  .refine((body) => body.status !== undefined || body.admin_notes !== undefined, {
    message: 'Nothing to update',
  });

export async function adminUpdateOrder(
  admin: AuthUser,
  orderId: string,
  input: z.infer<typeof adminUpdateOrderSchema>,
): Promise<Order> {
  const db = supabaseAdmin();
  const order = await getOrder(db, orderId);
  if (!order) throw notFound('Order not found');

  const changed = input.status ? await transition(order, input.status, admin.id) : false;
  if (input.admin_notes !== undefined) {
    check(
      (
        await db
          .from('orders')
          .update({ admin_notes: input.admin_notes || null, updated_at: now() })
          .eq('id', orderId)
      ).error,
    );
  }
  const updated = (await getOrder(db, orderId))!;
  // Awaited so it finishes before Vercel freezes the function; never throws.
  if (changed) await sendStatusChangeEmail(updated);
  return updated;
}

export function parseStatus(value: string | null): OrderStatus | undefined {
  if (value === null || value === '') return undefined;
  if (!(ORDER_STATUSES as readonly string[]).includes(value)) throw badRequest(`Unknown status "${value}"`);
  return value as OrderStatus;
}
