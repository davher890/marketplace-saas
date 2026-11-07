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

export interface ProductFilter {
  /** Category slug; includes its sub-categories. */
  category?: string | null;
  featured?: boolean;
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
  // Sorted here: the price depends on the variants, which PostgREST can't order by.
  const rows = unwrap(await query) as ProductRow[];
  return sortProducts(rows.map(shapeProduct), filter.sort ?? 'price');
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
