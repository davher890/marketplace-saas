import { notFound } from '../http';
import { supabase, unwrap } from '../supabase';
import { productCategoriesEmbed, withCategoryIds } from './productCategories';

// Public storefront catalog. Runs with the publishable key, so the RLS
// policies decide what anyone may see (active categories, products, variants
// and their images). The explicit `is_active` filters say the same thing
// and keep the results right even if a policy is loosened.

type Row = Record<string, unknown>;

type ProductRow = Row & {
  category_id: string | null;
  product_variants: { position: number; is_active: boolean }[];
  product_images: { position: number }[];
  product_categories?: { category_id: string; created_at: string }[];
};

const productSelect = `*, product_variants(*), product_images(*), ${productCategoriesEmbed}`;

/** Nested lists in display order, only active variants, and `category_ids`. */
function shapeProduct(product: ProductRow): ProductRow & { category_ids: string[] } {
  product.product_variants = product.product_variants
    .filter((v) => v.is_active)
    .sort((a, b) => a.position - b.position);
  product.product_images.sort((a, b) => a.position - b.position);
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

export interface ProductFilter {
  /** Category slug; includes its sub-categories. */
  category?: string | null;
  featured?: boolean;
}

/** Ids of the products listed in any of these categories. */
async function productIdsIn(categories: string[]): Promise<string[]> {
  const links = unwrap(
    await supabase().from('product_categories').select('product_id').in('category_id', categories),
  ) as { product_id: string }[];
  return [...new Set(links.map((link) => link.product_id))];
}

/** Active products, newest first. */
export async function listProducts(filter: ProductFilter): Promise<ProductRow[]> {
  let query = supabase().from('products').select(productSelect).eq('is_active', true);
  if (filter.category) {
    const ids = await productIdsIn(await categoryIds(filter.category));
    if (ids.length === 0) return [];
    query = query.in('id', ids);
  }
  if (filter.featured) query = query.eq('is_featured', true);
  const rows = unwrap(await query.order('created_at', { ascending: false })) as ProductRow[];
  return rows.map(shapeProduct);
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
