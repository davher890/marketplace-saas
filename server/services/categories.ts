import { z } from 'zod';

import { badRequest, conflict, notFound } from '../http';
import { check, now, supabaseAdmin, unwrap } from '../supabase';

// Admin panel only: called after the route checked the admin role. Uses the
// service-role client because it must see and change inactive categories.
//
// Categories form a two-level tree (the storefront menu and its dropdowns):
// a category is either a root or the child of a root.

export interface Category {
  id: string;
  parent_id: string | null;
  name: string;
  slug: string;
  description: string | null;
  image_url: string | null;
  position: number;
  is_active: boolean;
  /** Products listed in this category, active or not. */
  product_count: number;
}

// Counted through `product_categories`: a product listed in several
// categories counts in each. (Embedding `products` here would be ambiguous,
// since categories reach products both directly and through that table.)
type CategoryRow = Omit<Category, 'product_count'> & { product_categories?: { count: number }[] };

const toCategory = ({ product_categories, ...row }: CategoryRow): Category => ({
  ...row,
  product_count: product_categories?.[0]?.count ?? 0,
});

/** Every category, active or not, ordered as in the menu, with product counts. */
export async function listCategories(): Promise<Category[]> {
  const rows = unwrap(
    await supabaseAdmin()
      .from('categories')
      .select('*, product_categories(count)')
      .order('position', { ascending: true })
      .order('name', { ascending: true }),
  ) as CategoryRow[];
  return rows.map(toCategory);
}

async function getCategory(id: string): Promise<Category> {
  const row = unwrap(
    await supabaseAdmin().from('categories').select('*, product_categories(count)').eq('id', id).maybeSingle(),
  ) as CategoryRow | null;
  if (!row) throw notFound('Category not found');
  return toCategory(row);
}

export const categorySchema = z.object({
  parent_id: z.uuid().nullable().default(null),
  name: z.string().trim().min(1, 'Name is required').max(80),
  /** Stored lower-case, like product slugs. Used in /c/<slug>. */
  slug: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9]+(-[a-z0-9]+)*$/, 'Slug may only contain lowercase letters, numbers and dashes'),
  description: z
    .string()
    .trim()
    .max(1000)
    .nullish()
    .transform((value) => value || null),
  is_active: z.boolean().default(true),
});

export type CategoryInput = z.infer<typeof categorySchema>;

/** Checks the slug is free and the parent keeps the tree two levels deep. */
async function validate(categoryId: string | null, input: CategoryInput): Promise<void> {
  const db = supabaseAdmin();

  let slugQuery = db.from('categories').select('id').eq('slug', input.slug);
  if (categoryId) slugQuery = slugQuery.neq('id', categoryId);
  if ((unwrap(await slugQuery) as unknown[]).length > 0) {
    throw conflict('Another category already uses this slug');
  }

  if (input.parent_id === null) return;
  if (input.parent_id === categoryId) throw badRequest('A category cannot be its own parent');

  const parent = unwrap(
    await db.from('categories').select('id, parent_id').eq('id', input.parent_id).maybeSingle(),
  ) as { parent_id: string | null } | null;
  if (!parent) throw badRequest('The parent category does not exist');
  if (parent.parent_id !== null) throw badRequest('Sub-categories cannot have sub-categories');

  if (categoryId) {
    const children = unwrap(
      await db.from('categories').select('id').eq('parent_id', categoryId).limit(1),
    ) as unknown[];
    if (children.length > 0) {
      throw badRequest('A category with sub-categories cannot become a sub-category');
    }
  }
}

/** Position after the last sibling under `parentId` (null = root level). */
async function nextPosition(parentId: string | null): Promise<number> {
  let query = supabaseAdmin().from('categories').select('position').order('position', { ascending: false }).limit(1);
  query = parentId === null ? query.is('parent_id', null) : query.eq('parent_id', parentId);
  const last = unwrap(await query) as { position: number }[];
  return last.length === 0 ? 0 : last[0].position + 1;
}

function explainUniqueViolation(error: unknown): never {
  if ((error as { code?: string }).code === '23505') throw conflict('Another category already uses this slug');
  throw error;
}

export async function createCategory(input: CategoryInput): Promise<Category> {
  await validate(null, input);
  const position = await nextPosition(input.parent_id);
  try {
    const created = unwrap(
      await supabaseAdmin().from('categories').insert({ ...input, position }).select('id').single(),
    ) as { id: string };
    return getCategory(created.id);
  } catch (error) {
    explainUniqueViolation(error);
  }
}

export async function updateCategory(categoryId: string, input: CategoryInput): Promise<Category> {
  const current = await getCategory(categoryId);
  await validate(categoryId, input);
  // Moving to another parent puts it at the end of its new siblings.
  const position = current.parent_id === input.parent_id ? current.position : await nextPosition(input.parent_id);
  try {
    check(
      (
        await supabaseAdmin()
          .from('categories')
          .update({ ...input, position, updated_at: now() })
          .eq('id', categoryId)
      ).error,
    );
  } catch (error) {
    explainUniqueViolation(error);
  }
  return getCategory(categoryId);
}

export const patchCategorySchema = z.object({ is_active: z.boolean() });

export async function setCategoryActive(categoryId: string, isActive: boolean): Promise<Category> {
  await getCategory(categoryId);
  check(
    (
      await supabaseAdmin()
        .from('categories')
        .update({ is_active: isActive, updated_at: now() })
        .eq('id', categoryId)
    ).error,
  );
  return getCategory(categoryId);
}

export const moveCategorySchema = z.object({ direction: z.enum(['up', 'down']) });

/**
 * Swaps a category with the sibling before / after it, then numbers the
 * siblings 0, 1, 2... so positions stay unique and gap-free.
 */
export async function moveCategory(categoryId: string, direction: 'up' | 'down'): Promise<Category[]> {
  const db = supabaseAdmin();
  const category = await getCategory(categoryId);

  let query = db.from('categories').select('id, position').order('position').order('name');
  query = category.parent_id === null ? query.is('parent_id', null) : query.eq('parent_id', category.parent_id);
  const siblings = unwrap(await query) as { id: string; position: number }[];

  const index = siblings.findIndex((s) => s.id === categoryId);
  const target = direction === 'up' ? index - 1 : index + 1;
  if (target >= 0 && target < siblings.length) {
    [siblings[index], siblings[target]] = [siblings[target], siblings[index]];
    for (const [position, sibling] of siblings.entries()) {
      if (sibling.position === position) continue;
      check(
        (await db.from('categories').update({ position, updated_at: now() }).eq('id', sibling.id)).error,
      );
    }
  }
  return listCategories();
}

/**
 * Deletes an empty category. Categories with products or sub-categories are
 * refused instead of silently leaving those without a category: move them
 * first, or deactivate the category to hide it.
 */
export async function deleteCategory(categoryId: string): Promise<void> {
  const db = supabaseAdmin();
  const category = await getCategory(categoryId);
  if (category.product_count > 0) {
    throw conflict(
      `This category has ${category.product_count} product(s). Remove it from those products or deactivate it instead`,
    );
  }
  const children = unwrap(await db.from('categories').select('id').eq('parent_id', categoryId).limit(1)) as unknown[];
  if (children.length > 0) throw conflict('This category has sub-categories. Move or delete them first');
  check((await db.from('categories').delete().eq('id', categoryId)).error);
}
