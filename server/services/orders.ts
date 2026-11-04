import { z } from 'zod';

import type { AuthUser } from '../auth';
import { db, type Db } from '../db';
import { badRequest, conflict, notFound } from '../http';
import { getSettings, shippingFor } from './settings';

export const ORDER_STATUSES = ['pending', 'paid', 'processing', 'shipped', 'delivered', 'cancelled'] as const;
export type OrderStatus = (typeof ORDER_STATUSES)[number];

export type Order = Record<string, unknown> & {
  id: string;
  user_id: string | null;
  status: OrderStatus;
};

// -----------------------------------------------------------------------------
// Reading
// -----------------------------------------------------------------------------

export async function listOrders(filter: { userId?: string; status?: OrderStatus }): Promise<Order[]> {
  const sql = db();
  const rows = await sql<Order[]>`
    select o.*,
      coalesce(
        (select json_agg(oi order by oi.created_at) from order_items oi where oi.order_id = o.id),
        '[]'
      ) as order_items
    from orders o
    where true
      ${filter.userId ? sql`and o.user_id = ${filter.userId}` : sql``}
      ${filter.status ? sql`and o.status = ${filter.status}` : sql``}
    order by o.created_at desc
    limit 500
  `;
  return [...rows];
}

export async function getOrder(sql: Db, orderId: string): Promise<Order | null> {
  const [order] = await sql<Order[]>`
    select o.*,
      coalesce(
        (select json_agg(oi order by oi.created_at) from order_items oi where oi.order_id = o.id),
        '[]'
      ) as order_items,
      coalesce(
        (select json_agg(h order by h.created_at, h.id) from order_status_history h where h.order_id = o.id),
        '[]'
      ) as order_status_history
    from orders o
    where o.id = ${orderId}
  `;
  return order ?? null;
}

/** Customers only see their own orders; admins see all of them. */
export async function getOrderFor(user: AuthUser, orderId: string, admin: boolean): Promise<Order> {
  const order = await getOrder(db(), orderId);
  if (!order || (!admin && order.user_id !== user.id)) throw notFound('Order not found');
  return order;
}

// -----------------------------------------------------------------------------
// Checkout
// -----------------------------------------------------------------------------

const text = (max: number) => z.string().trim().max(max);

export const checkoutSchema = z.object({
  shipping_name: text(120).min(1, 'Shipping name is required'),
  shipping_phone: text(40).nullish(),
  contact_email: z.email().max(200).nullish(),
  customer_notes: text(1000).nullish(),
  shipping_address: z.object({
    line1: text(200).min(1, 'Address is required'),
    line2: text(200).default(''),
    city: text(100).min(1, 'City is required'),
    postal_code: text(20).min(1, 'Postal code is required'),
    province: text(100).default(''),
    country: text(2).default('ES'),
  }),
});

interface LockedLine {
  quantity: number;
  customization: string;
  variant_id: string;
  variant_name: string;
  sku: string | null;
  stock: number | null;
  variant_active: boolean;
  product_id: string;
  product_name: string;
  product_active: boolean;
  unit_price_cents: number;
}

/**
 * Turns the user's cart into an order in a single transaction:
 *   - re-reads prices from the catalog (never trusts the client),
 *   - locks the variants and checks stock, so concurrent checkouts can't oversell,
 *   - computes shipping from the shop settings,
 *   - creates the order, its lines and the first history entry,
 *   - decrements tracked stock and empties the cart.
 */
export async function placeOrder(user: AuthUser, input: z.infer<typeof checkoutSchema>): Promise<Order> {
  const orderId = await db().begin(async (sql) => {
    const [cart] = await sql<{ id: string }[]>`select id from carts where user_id = ${user.id}`;
    if (!cart) throw conflict('Cart is empty');

    const lines = await sql<LockedLine[]>`
      select ci.quantity, ci.customization,
             v.id as variant_id, v.name as variant_name, v.sku, v.stock, v.is_active as variant_active,
             p.id as product_id, p.name as product_name, p.is_active as product_active,
             coalesce(v.price_cents, p.base_price_cents) as unit_price_cents
      from cart_items ci
      join product_variants v on v.id = ci.variant_id
      join products p on p.id = v.product_id
      where ci.cart_id = ${cart.id}
      order by v.id
      for update of v
    `;
    if (lines.length === 0) throw conflict('Cart is empty');

    // The same variant can appear on several lines (different customizations),
    // so stock is checked against the total quantity per variant.
    const quantityByVariant = new Map<string, number>();
    for (const line of lines) {
      if (!line.variant_active || !line.product_active) {
        throw conflict(`"${line.product_name}" is no longer available`);
      }
      quantityByVariant.set(line.variant_id, (quantityByVariant.get(line.variant_id) ?? 0) + line.quantity);
    }
    for (const line of lines) {
      const wanted = quantityByVariant.get(line.variant_id)!;
      if (line.stock !== null && wanted > line.stock) {
        throw conflict(`Not enough stock for "${line.product_name}" (${line.stock} left)`);
      }
    }

    const subtotal = lines.reduce((sum, line) => sum + line.unit_price_cents * line.quantity, 0);
    const shipping = shippingFor(await getSettings(sql), subtotal);

    const [order] = await sql<{ id: string }[]>`
      insert into orders ${sql({
        user_id: user.id,
        status: 'pending',
        subtotal_cents: subtotal,
        shipping_cents: shipping,
        total_cents: subtotal + shipping,
        contact_email: input.contact_email || user.email,
        shipping_name: input.shipping_name,
        shipping_phone: input.shipping_phone || null,
        shipping_address: sql.json(input.shipping_address),
        customer_notes: input.customer_notes || null,
      })}
      returning id
    `;

    await sql`
      insert into order_items ${sql(
        lines.map((line) => ({
          order_id: order.id,
          product_id: line.product_id,
          variant_id: line.variant_id,
          product_name: line.product_name,
          variant_name: line.variant_name,
          sku: line.sku,
          unit_price_cents: line.unit_price_cents,
          quantity: line.quantity,
          customization: line.customization,
        })),
      )}
    `;

    await recordStatusChange(sql, order.id, null, 'pending', user.id);

    for (const [variantId, quantity] of quantityByVariant) {
      await sql`
        update product_variants
        set stock = stock - ${quantity}, updated_at = now()
        where id = ${variantId} and stock is not null
      `;
    }

    await sql`delete from cart_items where cart_id = ${cart.id}`;
    await sql`update carts set updated_at = now() where id = ${cart.id}`;
    return order.id;
  });

  return (await getOrder(db(), orderId))!;
}

// -----------------------------------------------------------------------------
// Status changes
// -----------------------------------------------------------------------------

async function recordStatusChange(
  sql: Db,
  orderId: string,
  from: OrderStatus | null,
  to: OrderStatus,
  changedBy: string,
): Promise<void> {
  await sql`
    insert into order_status_history (order_id, from_status, to_status, changed_by)
    values (${orderId}, ${from}, ${to}, ${changedBy})
  `;
}

async function lockOrder(sql: Db, orderId: string): Promise<Order> {
  const [order] = await sql<Order[]>`select * from orders where id = ${orderId} for update`;
  if (!order) throw notFound('Order not found');
  return order;
}

/** Returns tracked stock of a cancelled order back to its variants. */
async function restoreStock(sql: Db, orderId: string): Promise<void> {
  await sql`
    update product_variants v
    set stock = v.stock + agg.quantity, updated_at = now()
    from (
      select variant_id, sum(quantity)::int as quantity
      from order_items
      where order_id = ${orderId} and variant_id is not null
      group by variant_id
    ) agg
    where v.id = agg.variant_id and v.stock is not null
  `;
}

/**
 * Moves a locked order to a new status: logs the change, stamps
 * `paid_at` / `shipped_at` and restores stock on cancellation.
 */
async function transition(sql: Db, order: Order, to: OrderStatus, actorId: string): Promise<void> {
  if (order.status === to) return;
  if (order.status === 'cancelled') throw conflict('Cancelled orders cannot change status');

  if (to === 'cancelled') await restoreStock(sql, order.id);

  await sql`
    update orders set
      status = ${to},
      paid_at = ${to === 'paid' ? sql`coalesce(paid_at, now())` : sql`paid_at`},
      shipped_at = ${to === 'shipped' ? sql`coalesce(shipped_at, now())` : sql`shipped_at`},
      updated_at = now()
    where id = ${order.id}
  `;
  await recordStatusChange(sql, order.id, order.status, to, actorId);
}

/** Customers may cancel their own pending orders; admins can cancel any order. */
export async function cancelOrder(user: AuthUser, orderId: string, admin: boolean): Promise<Order> {
  await db().begin(async (sql) => {
    const order = await lockOrder(sql, orderId);
    if (!admin && order.user_id !== user.id) throw notFound('Order not found');
    if (!admin && order.status !== 'pending') throw conflict('Only pending orders can be cancelled');
    await transition(sql, order, 'cancelled', user.id);
  });
  return (await getOrder(db(), orderId))!;
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
  await db().begin(async (sql) => {
    const order = await lockOrder(sql, orderId);
    if (input.status) await transition(sql, order, input.status, admin.id);
    if (input.admin_notes !== undefined) {
      await sql`
        update orders set admin_notes = ${input.admin_notes || null}, updated_at = now()
        where id = ${orderId}
      `;
    }
  });
  return (await getOrder(db(), orderId))!;
}

export function parseStatus(value: string | null): OrderStatus | undefined {
  if (value === null || value === '') return undefined;
  if (!(ORDER_STATUSES as readonly string[]).includes(value)) throw badRequest(`Unknown status "${value}"`);
  return value as OrderStatus;
}
