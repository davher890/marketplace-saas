import { z } from 'zod';

import type { AuthUser } from '../auth';
import { badRequest, conflict, notFound } from '../http';
import { check, now, unwrap } from '../supabase';
import { withImageUrls } from './images';
import { getSettings, shippingFor } from './settings';

// Everything here runs with the user's client (`user.db`): RLS guarantees a
// customer only ever reads or changes their own cart.

export const MAX_LINE_QUANTITY = 99;

interface VariantRow extends Record<string, unknown> {
  id: string;
  is_active: boolean;
  stock: number | null;
  price_cents: number | null;
  name: string;
  sku: string | null;
  products: Record<string, unknown> & {
    id: string;
    name: string;
    base_price_cents: number;
    is_customizable: boolean;
    is_active: boolean;
  };
}

/** Cart line with its variant and product nested, as the app expects. */
export interface CartLine {
  id: string;
  quantity: number;
  customization: string;
  unit_price_cents: number;
  product_variants: VariantRow;
}

export interface Cart {
  items: CartLine[];
  item_count: number;
  subtotal_cents: number;
  shipping_cents: number;
  total_cents: number;
  /** Lines dropped because their product is no longer for sale. */
  removed_unavailable: number;
}

const lineSelect =
  'id, quantity, customization, created_at, product_variants(*, products(*, product_images(*)))';

/** A variant can be bought only if it and its product are active. */
function isAvailable(variant: VariantRow | null): variant is VariantRow {
  return Boolean(variant?.is_active && variant.products?.is_active);
}

/**
 * Loads the user's cart lines. Lines whose variant or product is no longer
 * active (or no longer visible through the catalog policies) are removed.
 */
export async function loadCartLines(user: AuthUser): Promise<{ lines: CartLine[]; removed: number }> {
  const rows = unwrap(
    await user.db.from('cart_items').select(lineSelect).order('created_at', { ascending: true }),
  ) as unknown as (Omit<CartLine, 'unit_price_cents' | 'product_variants'> & {
    product_variants: VariantRow | null;
  })[];

  const unavailable = rows.filter((row) => !isAvailable(row.product_variants)).map((row) => row.id);
  if (unavailable.length > 0) {
    check((await user.db.from('cart_items').delete().in('id', unavailable)).error);
  }

  const lines = rows
    .filter((row) => isAvailable(row.product_variants))
    .map((row) => {
      const variant = row.product_variants!;
      const images =
        (variant.products.product_images as
          | { position: number; url: string; storage_path: string | null }[]
          | undefined) ?? [];
      withImageUrls(images).sort((a, b) => a.position - b.position);
      return {
        id: row.id,
        quantity: row.quantity,
        customization: row.customization,
        unit_price_cents: variant.price_cents ?? variant.products.base_price_cents,
        product_variants: variant,
      };
    });
  return { lines, removed: unavailable.length };
}

export async function getCart(user: AuthUser): Promise<Cart> {
  const { lines, removed } = await loadCartLines(user);
  const subtotal = lines.reduce((sum, line) => sum + line.unit_price_cents * line.quantity, 0);
  const shipping = lines.length === 0 ? 0 : shippingFor(await getSettings(), subtotal);
  return {
    items: lines,
    item_count: lines.reduce((sum, line) => sum + line.quantity, 0),
    subtotal_cents: subtotal,
    shipping_cents: shipping,
    total_cents: subtotal + shipping,
    removed_unavailable: removed,
  };
}

/** Returns the user's cart id, creating the cart on first use. */
async function getOrCreateCartId(user: AuthUser): Promise<string> {
  const existing = unwrap(
    await user.db.from('carts').select('id').eq('user_id', user.id).maybeSingle(),
  ) as { id: string } | null;
  if (existing) return existing.id;

  const { data, error } = await user.db.from('carts').insert({ user_id: user.id }).select('id').single();
  if (!error) return (data as { id: string }).id;

  // Two requests created it at the same time: use the one that won.
  if ((error as { code?: string }).code === '23505') {
    const winner = unwrap(
      await user.db.from('carts').select('id').eq('user_id', user.id).single(),
    ) as { id: string };
    return winner.id;
  }
  throw error;
}

export interface ChoiceField {
  label: string;
  options: string[];
}

interface PurchasableVariant {
  id: string;
  is_active: boolean;
  stock: number | null;
  products: {
    name: string;
    is_customizable: boolean;
    is_active: boolean;
    choice_fields: ChoiceField[] | null;
  } | null;
}

type AvailableVariant = PurchasableVariant & { products: NonNullable<PurchasableVariant['products']> };

/** Only active variants of active products can be added. */
async function findVariant(user: AuthUser, variantId: string): Promise<AvailableVariant> {
  const variant = unwrap(
    await user.db
      .from('product_variants')
      .select('id, is_active, stock, products(name, is_customizable, is_active, choice_fields)')
      .eq('id', variantId)
      .maybeSingle(),
  ) as PurchasableVariant | null;
  if (!variant?.is_active || !variant.products?.is_active) throw notFound('Product not available');
  return variant as AvailableVariant;
}

function assertStock(variant: AvailableVariant, quantity: number): void {
  if (variant.stock !== null && quantity > variant.stock) {
    throw conflict(
      variant.stock === 0
        ? `"${variant.products.name}" is sold out`
        : `Only ${variant.stock} left of "${variant.products.name}"`,
    );
  }
}

export const addItemSchema = z.object({
  variant_id: z.uuid(),
  quantity: z.number().int().min(1).max(MAX_LINE_QUANTITY).default(1),
  customization: z.string().trim().max(60).default(''),
  /** The value picked in each of the product's choice lists, by list name. */
  choices: z.record(z.string().max(60), z.string().trim().max(60)).default({}),
});

/**
 * What is stored on the cart line (and copied to the order): the picked
 * value of each choice list, then the free text, e.g.
 * "Color del lazo: Azul · Lucía". Every list needs a value from its options,
 * and the text is required only for customizable products.
 */
export function lineCustomization(
  product: { is_customizable: boolean; choice_fields: ChoiceField[] | null },
  input: { customization: string; choices: Record<string, string> },
): string {
  const picks = (product.choice_fields ?? []).map((field) => {
    const value = input.choices[field.label];
    if (!value) throw badRequest(`Choose a value for "${field.label}"`);
    if (!field.options.includes(value)) throw badRequest(`"${value}" is not an option of "${field.label}"`);
    return `${field.label}: ${value}`;
  });

  const text = product.is_customizable ? input.customization : '';
  if (product.is_customizable && !text) throw badRequest('This product needs a customization text');
  return [...picks, text].filter(Boolean).join(' · ');
}

/** Adds a variant to the cart, or increases its quantity if already there. */
export async function addItem(user: AuthUser, input: z.infer<typeof addItemSchema>): Promise<Cart> {
  const variant = await findVariant(user, input.variant_id);

  // Only customizable products keep the custom text; choice lists go first.
  const customization = lineCustomization(variant.products, input);

  const cartId = await getOrCreateCartId(user);
  const existing = unwrap(
    await user.db
      .from('cart_items')
      .select('quantity')
      .eq('cart_id', cartId)
      .eq('variant_id', variant.id)
      .eq('customization', customization)
      .maybeSingle(),
  ) as { quantity: number } | null;

  const quantity = Math.min((existing?.quantity ?? 0) + input.quantity, MAX_LINE_QUANTITY);
  assertStock(variant, quantity);

  const { error } = await user.db.from('cart_items').upsert(
    { cart_id: cartId, variant_id: variant.id, customization, quantity, updated_at: now() },
    { onConflict: 'cart_id,variant_id,customization' },
  );
  check(error);
  return getCart(user);
}

export const updateItemSchema = z.object({
  quantity: z.number().int().min(0).max(MAX_LINE_QUANTITY),
});

/** Sets the quantity of a cart line; 0 removes it. */
export async function updateItem(user: AuthUser, itemId: string, quantity: number): Promise<Cart> {
  if (quantity === 0) return removeItem(user, itemId);

  const item = unwrap(
    await user.db.from('cart_items').select('variant_id').eq('id', itemId).maybeSingle(),
  ) as { variant_id: string } | null;
  if (!item) throw notFound('Cart item not found');

  assertStock(await findVariant(user, item.variant_id), quantity);
  check((await user.db.from('cart_items').update({ quantity, updated_at: now() }).eq('id', itemId)).error);
  return getCart(user);
}

export async function removeItem(user: AuthUser, itemId: string): Promise<Cart> {
  const deleted = unwrap(await user.db.from('cart_items').delete().eq('id', itemId).select('id'));
  if (!deleted || deleted.length === 0) throw notFound('Cart item not found');
  return getCart(user);
}

/**
 * Removes the lines that were just ordered. Only those ids, so an item added
 * while the checkout was running stays in the cart.
 */
export async function removeOrderedLines(user: AuthUser, lineIds: string[]): Promise<void> {
  if (lineIds.length === 0) return;
  const { error } = await user.db.from('cart_items').delete().in('id', lineIds);
  if (error) console.error('Could not empty the cart after checkout', error);
}
