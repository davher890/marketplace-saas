import { badRequest } from '../http';
import { check, unwrap } from '../supabase';
import type { SupabaseClient } from '@supabase/supabase-js';

// A product can be listed in several categories (`product_categories`).
// `products.category_id` is its main one and is always among them. The API
// keeps both in sync (see migration 20261106000004).

/** Embed to add to a products select to get its categories. */
export const productCategoriesEmbed = 'product_categories(category_id, created_at)';

type WithLinks = Record<string, unknown> & {
  category_id?: string | null;
  product_categories?: { category_id: string; created_at: string }[];
};

/**
 * Replaces the embedded links with `category_ids`: the main category first,
 * then the others in the order they were added.
 */
export function withCategoryIds<T extends WithLinks>(product: T): T & { category_ids: string[] } {
  const { product_categories: links = [], ...rest } = product;
  const others = [...links]
    .sort((a, b) => a.created_at.localeCompare(b.created_at) || a.category_id.localeCompare(b.category_id))
    .map((link) => link.category_id);
  const main = product.category_id ?? null;
  const category_ids = main ? [main, ...others.filter((id) => id !== main)] : others;
  return { ...(rest as T), category_ids };
}

/**
 * The categories to save: `category_ids` when given, else the old single
 * `category_id`. Duplicates removed, order kept (the first is the main one).
 */
export function normalizeCategoryIds(input: { category_id: string | null; category_ids?: string[] }): string[] {
  const ids = input.category_ids ?? (input.category_id ? [input.category_id] : []);
  return [...new Set(ids)];
}

/** Fails with 400 before writing anything if a category doesn't exist. */
export async function assertCategoriesExist(db: SupabaseClient, categoryIds: string[]): Promise<void> {
  if (categoryIds.length === 0) return;
  const found = unwrap(await db.from('categories').select('id').in('id', categoryIds)) as { id: string }[];
  if (found.length !== categoryIds.length) throw badRequest('Some categories do not exist');
}

/** Makes the product's links exactly `categoryIds`. */
export async function syncProductCategories(
  db: SupabaseClient,
  productId: string,
  categoryIds: string[],
): Promise<void> {
  let removed = db.from('product_categories').delete().eq('product_id', productId);
  if (categoryIds.length > 0) removed = removed.not('category_id', 'in', `(${categoryIds.join(',')})`);
  check((await removed).error);

  if (categoryIds.length === 0) return;
  const { error } = await db.from('product_categories').upsert(
    categoryIds.map((category_id) => ({ product_id: productId, category_id })),
    { onConflict: 'product_id,category_id', ignoreDuplicates: true },
  );
  check(error);
}
