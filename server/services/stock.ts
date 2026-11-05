import { conflict } from '../http';
import { check, now, supabaseAdmin, unwrap } from '../supabase';

const MAX_ATTEMPTS = 5;

/**
 * Adds `delta` (negative to take stock) to a variant's tracked stock.
 *
 * supabase-js can't run `stock = stock - n` or open a transaction, so this is a
 * compare-and-swap: the update only applies if the stock still has the value
 * just read; if someone else changed it in between, it reads again and retries.
 * That makes concurrent checkouts safe without locks or SQL functions.
 *
 * Variants with `stock = null` (made to order) are left untouched.
 * Returns false when there isn't enough stock to take.
 */
export async function adjustStock(variantId: string, delta: number): Promise<boolean> {
  const db = supabaseAdmin();
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const { stock } = unwrap(
      await db.from('product_variants').select('stock').eq('id', variantId).single(),
    ) as { stock: number | null };
    if (stock === null) return true;

    const next = stock + delta;
    if (next < 0) return false;

    const { data, error } = await db
      .from('product_variants')
      .update({ stock: next, updated_at: now() })
      .eq('id', variantId)
      .eq('stock', stock)
      .select('id');
    check(error);
    if (data && data.length > 0) return true;
  }
  throw conflict('Stock changed while processing the request, please try again');
}

/**
 * Takes stock for several variants at once. If any of them runs short, the
 * ones already taken are given back and `false` is returned.
 */
export async function reserveStock(quantities: Map<string, number>): Promise<boolean> {
  const taken: [string, number][] = [];
  for (const [variantId, quantity] of quantities) {
    let ok = false;
    try {
      ok = await adjustStock(variantId, -quantity);
    } catch (error) {
      await releaseStock(taken);
      throw error;
    }
    if (!ok) {
      await releaseStock(taken);
      return false;
    }
    taken.push([variantId, quantity]);
  }
  return true;
}

/** Gives stock back (cancelled order or failed checkout). Best effort per variant. */
export async function releaseStock(quantities: Iterable<[string, number]>): Promise<void> {
  for (const [variantId, quantity] of quantities) {
    try {
      await adjustStock(variantId, quantity);
    } catch (error) {
      console.error(`Could not give back ${quantity} units of variant ${variantId}`, error);
    }
  }
}
