import { z } from 'zod';

import { db, type Db } from '../db';
import { badRequest, conflict, notFound } from '../http';
import { getSettings, shippingFor } from './settings';

export const MAX_LINE_QUANTITY = 99;

/** Cart line with its variant and product nested, as the app expects. */
export interface CartItem {
  id: string;
  quantity: number;
  customization: string;
  unit_price_cents: number;
  product_variants: Record<string, unknown> & { products: Record<string, unknown> };
}

export interface Cart {
  items: CartItem[];
  item_count: number;
  subtotal_cents: number;
  shipping_cents: number;
  total_cents: number;
}

export async function getCart(userId: string): Promise<Cart> {
  const sql = db();
  const items = await sql<CartItem[]>`
    select
      ci.id,
      ci.quantity,
      ci.customization,
      coalesce(v.price_cents, p.base_price_cents) as unit_price_cents,
      to_jsonb(v) || jsonb_build_object(
        'products', to_jsonb(p) || jsonb_build_object(
          'product_images', coalesce(
            (select jsonb_agg(i order by i.position) from product_images i where i.product_id = p.id),
            '[]'::jsonb
          )
        )
      ) as product_variants
    from cart_items ci
    join carts c on c.id = ci.cart_id
    join product_variants v on v.id = ci.variant_id
    join products p on p.id = v.product_id
    where c.user_id = ${userId}
    order by ci.created_at
  `;

  const subtotal = items.reduce((sum, item) => sum + item.unit_price_cents * item.quantity, 0);
  const shipping = items.length === 0 ? 0 : shippingFor(await getSettings(sql), subtotal);
  return {
    items: [...items],
    item_count: items.reduce((sum, item) => sum + item.quantity, 0),
    subtotal_cents: subtotal,
    shipping_cents: shipping,
    total_cents: subtotal + shipping,
  };
}

/** Returns the user's cart id, creating the cart on first use. */
async function getOrCreateCartId(sql: Db, userId: string): Promise<string> {
  const [cart] = await sql<{ id: string }[]>`
    insert into carts (user_id) values (${userId})
    on conflict (user_id) do update set updated_at = now()
    returning id
  `;
  return cart.id;
}

interface PurchasableVariant {
  id: string;
  stock: number | null;
  product_name: string;
  is_customizable: boolean;
  available: boolean;
}

async function findVariant(sql: Db, variantId: string): Promise<PurchasableVariant> {
  const [variant] = await sql<PurchasableVariant[]>`
    select v.id, v.stock, p.name as product_name, p.is_customizable,
           (v.is_active and p.is_active) as available
    from product_variants v
    join products p on p.id = v.product_id
    where v.id = ${variantId}
  `;
  if (!variant || !variant.available) throw notFound('Product not available');
  return variant;
}

function assertStock(variant: PurchasableVariant, quantity: number): void {
  if (variant.stock !== null && quantity > variant.stock) {
    throw conflict(
      variant.stock === 0
        ? `"${variant.product_name}" is sold out`
        : `Only ${variant.stock} left of "${variant.product_name}"`,
    );
  }
}

export const addItemSchema = z.object({
  variant_id: z.uuid(),
  quantity: z.number().int().min(1).max(MAX_LINE_QUANTITY).default(1),
  customization: z.string().trim().max(60).default(''),
});

/** Adds a variant to the cart, or increases its quantity if already there. */
export async function addItem(userId: string, input: z.infer<typeof addItemSchema>): Promise<Cart> {
  await db().begin(async (sql) => {
    const variant = await findVariant(sql, input.variant_id);

    // Only customizable products keep the custom text.
    const customization = variant.is_customizable ? input.customization : '';
    if (variant.is_customizable && !customization) {
      throw badRequest('This product needs a customization text');
    }

    const cartId = await getOrCreateCartId(sql, userId);
    const [existing] = await sql<{ quantity: number }[]>`
      select quantity from cart_items
      where cart_id = ${cartId} and variant_id = ${variant.id} and customization = ${customization}
      for update
    `;
    const quantity = Math.min((existing?.quantity ?? 0) + input.quantity, MAX_LINE_QUANTITY);
    assertStock(variant, quantity);

    await sql`
      insert into cart_items (cart_id, variant_id, quantity, customization)
      values (${cartId}, ${variant.id}, ${quantity}, ${customization})
      on conflict (cart_id, variant_id, customization)
      do update set quantity = excluded.quantity, updated_at = now()
    `;
  });
  return getCart(userId);
}

export const updateItemSchema = z.object({
  quantity: z.number().int().min(0).max(MAX_LINE_QUANTITY),
});

/** Sets the quantity of a cart line; 0 removes it. */
export async function updateItem(userId: string, itemId: string, quantity: number): Promise<Cart> {
  if (quantity === 0) return removeItem(userId, itemId);

  await db().begin(async (sql) => {
    const [item] = await sql<{ variant_id: string }[]>`
      select ci.variant_id
      from cart_items ci
      join carts c on c.id = ci.cart_id
      where ci.id = ${itemId} and c.user_id = ${userId}
      for update of ci
    `;
    if (!item) throw notFound('Cart item not found');

    assertStock(await findVariant(sql, item.variant_id), quantity);
    await sql`update cart_items set quantity = ${quantity}, updated_at = now() where id = ${itemId}`;
  });
  return getCart(userId);
}

export async function removeItem(userId: string, itemId: string): Promise<Cart> {
  const sql = db();
  const deleted = await sql`
    delete from cart_items ci
    using carts c
    where ci.id = ${itemId} and ci.cart_id = c.id and c.user_id = ${userId}
    returning ci.id
  `;
  if (deleted.length === 0) throw notFound('Cart item not found');
  return getCart(userId);
}
