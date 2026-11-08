import { badRequest, notFound } from '../http';
import { supabase, unwrap } from '../supabase';
import { withImageUrls } from './images';
import { productCategoriesEmbed, withCategoryIds } from './productCategories';

// Public storefront catalog. Runs with the publishable key, so the RLS
// policies decide what anyone may see (active categories, products, variants
// and their images). The explicit `is_active` filters say the same thing
// and keep the results right even if a policy is loosened.

type Row = Record<string, unknown>;

type ProductRow = Row & {
  category_id: string | null;
  name: string;
  base_price_cents: number;
  product_variants: { position: number; is_active: boolean; price_cents: number | null }[];
  product_images: { position: number; url: string; storage_path: string | null }[];
  product_categories?: { category_id: string; created_at: string }[];
};

const productSelect = `*, product_variants(*), product_images(*), ${productCategoriesEmbed}`;

/** Nested lists in display order, only active variants, and `category_ids`. */
function shapeProduct(product: ProductRow): ProductRow & { category_ids: string[] } {
  product.product_variants = product.product_variants
    .filter((v) => v.is_active)
    .sort((a, b) => a.position - b.position);
  withImageUrls(product.product_images).sort((a, b) => a.position - b.position);
  return withCategoryIds(product);
}

/** Active categories, in menu order. */
export async function listCategories(): Promise<Row[]> {
  return unwrap(
    await supabase()
      .from('categories')
      .select('id, parent_id, name, slug, description, image_url, position, is_active')
      .eq('is_active', true)
      .order('position', { ascending: true })
      .order('name', { ascending: true }),
  ) as Row[];
}

/** Ids of an active category and its active sub-categories. */
async function categoryIds(slug: string): Promise<string[]> {
  const db = supabase();
  const category = unwrap(
    await db.from('categories').select('id').eq('slug', slug.toLowerCase()).eq('is_active', true).maybeSingle(),
  ) as { id: string } | null;
  if (!category) throw notFound('Category not found');

  const children = unwrap(
    await db.from('categories').select('id').eq('parent_id', category.id).eq('is_active', true),
  ) as { id: string }[];
  return [category.id, ...children.map((c) => c.id)];
}

export const PRODUCT_SORTS = ['price', 'price_desc', 'name'] as const;
export type ProductSort = (typeof PRODUCT_SORTS)[number];

/** `?sort=` of the products list; cheapest first when not given. */
export function parseSort(value: string | null): ProductSort {
  if (!value) return 'price';
  if ((PRODUCT_SORTS as readonly string[]).includes(value)) return value as ProductSort;
  throw badRequest(`sort must be one of: ${PRODUCT_SORTS.join(', ')}`);
}

/**
 * The price shown on the product card ("Desde X €"): the lowest of its active
 * variants, or the base price. Same rule as `Product.minPriceCents` in the app.
 */
export function lowestPriceCents(product: ProductRow): number {
  const prices = product.product_variants
    .filter((variant) => variant.is_active)
    .map((variant) => variant.price_cents ?? product.base_price_cents);
  return prices.length > 0 ? Math.min(...prices) : product.base_price_cents;
}

/** Spanish alphabetical order: accents and case don't matter, "ñ" after "n". */
const byName = new Intl.Collator('es', { sensitivity: 'base', numeric: true });

export function sortProducts<T extends ProductRow>(products: T[], sort: ProductSort): T[] {
  const name = (a: T, b: T) => byName.compare(a.name, b.name);
  const price = (a: T, b: T) => lowestPriceCents(a) - lowestPriceCents(b);
  const compare: Record<ProductSort, (a: T, b: T) => number> = {
    price: (a, b) => price(a, b) || name(a, b),
    price_desc: (a, b) => price(b, a) || name(a, b),
    name: (a, b) => name(a, b) || price(a, b),
  };
  return [...products].sort(compare[sort]);
}

/** Lower case without accents, so "balsamo" finds "Bálsamo" (ñ becomes n too). */
export function searchable(text: string): string {
  return text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}

/**
 * How well a product matches the search: 2 when every word of the query is
 * in its name, 1 when every word is in its name or description (between
 * them), 0 when it doesn't match. Words can come in any order.
 */
export function searchScore(product: { name: string; description?: unknown }, query: string): 0 | 1 | 2 {
  const words = searchable(query).split(/\s+/).filter(Boolean);
  if (words.length === 0) return 0;
  const name = searchable(product.name);
  if (words.every((word) => name.includes(word))) return 2;
  const description = typeof product.description === 'string' ? searchable(product.description) : '';
  const text = `${name} ${description}`;
  return words.every((word) => text.includes(word)) ? 1 : 0;
}

export interface ProductFilter {
  /** Category slug; includes its sub-categories. */
  category?: string | null;
  featured?: boolean;
  /**
   * Text to find in the product name or description (accents and case
   * ignored). Products matching by name come first.
   */
  search?: string | null;
  /** Cheapest first by default. */
  sort?: ProductSort;
}

/** Ids of the products listed in any of these categories. */
async function productIdsIn(categories: string[]): Promise<string[]> {
  const links = unwrap(
    await supabase().from('product_categories').select('product_id').in('category_id', categories),
  ) as { product_id: string }[];
  return [...new Set(links.map((link) => link.product_id))];
}

/** Active products, cheapest first unless `filter.sort` says otherwise. */
export async function listProducts(filter: ProductFilter): Promise<ProductRow[]> {
  let query = supabase().from('products').select(productSelect).eq('is_active', true);
  if (filter.category) {
    const ids = await productIdsIn(await categoryIds(filter.category));
    if (ids.length === 0) return [];
    query = query.in('id', ids);
  }
  if (filter.featured) query = query.eq('is_featured', true);
  // Filtered and sorted here: PostgREST can't ignore accents or order by the
  // variants' price. The catalog is small enough to do it in memory.
  const rows = unwrap(await query) as ProductRow[];
  const sorted = sortProducts(rows.map(shapeProduct), filter.sort ?? 'price');
  const search = filter.search?.trim();
  if (!search) return sorted;
  // Name matches first, then description matches, each in the chosen order.
  const scored = sorted.map((product) => ({ product, score: searchScore(product, search) }));
  return [2, 1].flatMap((score) => scored.filter((s) => s.score === score).map((s) => s.product));
}

export async function getProductBySlug(slug: string): Promise<ProductRow> {
  const product = unwrap(
    await supabase()
      .from('products')
      .select(productSelect)
      .eq('slug', slug.toLowerCase())
      .eq('is_active', true)
      .maybeSingle(),
  ) as ProductRow | null;
  if (!product) throw notFound('Product not found');
  return shapeProduct(product);
}
