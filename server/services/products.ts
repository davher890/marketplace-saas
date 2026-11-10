import { z } from 'zod';

import { badRequest, conflict, notFound } from '../http';
import { check, now, supabaseAdmin, unwrap } from '../supabase';
import * as images from './images';
import {
  assertCategoriesExist,
  normalizeCategoryIds,
  productCategoriesEmbed,
  syncProductCategories,
  withCategoryIds,
} from './productCategories';

// Admin panel only: every function here is called after the route checked the
// admin role, and uses the service-role client (it must see inactive items).

export type Product = Record<string, unknown> & {
  id: string;
  category_id: string | null;
  product_variants: { id: string; position: number }[];
  product_images: { id: string; position: number; url: string; storage_path: string | null }[];
  product_categories?: { category_id: string; created_at: string }[];
};

const productSelect = `*, product_variants(*), product_images(*), ${productCategoriesEmbed}`;

/** Nested lists in display order, and `category_ids` (main category first). */
function sortNested(product: Product): Product & { category_ids: string[] } {
  product.product_variants.sort((a, b) => a.position - b.position);
  images.withImageUrls(product.product_images).sort((a, b) => a.position - b.position);
  return withCategoryIds(product);
}

/** Every product, active or not. */
export async function listProducts(): Promise<Product[]> {
  const rows = unwrap(
    await supabaseAdmin().from('products').select(productSelect).order('updated_at', { ascending: false }),
  ) as Product[];
  return rows.map(sortNested);
}

export async function getProduct(productId: string): Promise<Product> {
  const product = unwrap(
    await supabaseAdmin().from('products').select(productSelect).eq('id', productId).maybeSingle(),
  ) as Product | null;
  if (!product) throw notFound('Product not found');
  return sortNested(product);
}

// -----------------------------------------------------------------------------
// Create / update
// -----------------------------------------------------------------------------

const cents = z.number().int().min(0).max(10_000_000);
const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullish()
    .transform((value) => value || null);

const variantSchema = z.object({
  /** Omitted for new variants. */
  id: z.uuid().optional(),
  name: z
    .string()
    .trim()
    .max(80)
    .transform((value) => value || 'Default'),
  /** SKUs are stored upper-case so lookups don't depend on how they were typed. */
  sku: optionalText(40).transform((value) => value?.toUpperCase() ?? null),
  options: z.record(z.string().trim().min(1).max(40), z.string().trim().max(80)).default({}),
  price_cents: cents.nullable().default(null),
  /** `null` = made to order. */
  stock: z.number().int().min(0).max(100_000).nullable().default(null),
  is_active: z.boolean().default(true),
});

/** A list the customer picks one value from, e.g. "Color del lazo": Rojo, Azul. */
const choiceFieldSchema = z
  .object({
    label: z.string().trim().min(1, 'Each list needs a name').max(60),
    options: z.array(z.string().trim().min(1).max(60)).min(1, 'Each list needs at least one value').max(30),
  })
  .transform((field) => ({ label: field.label, options: [...new Set(field.options)] }));

export const productSchema = z.object({
  /** Main category. Ignored when `category_ids` is sent (its first item wins). */
  category_id: z.uuid().nullable().default(null),
  /** Every category the product is listed in; the first one is the main one. */
  category_ids: z.array(z.uuid()).max(20).optional(),
  name: z.string().trim().min(1, 'Name is required').max(200),
  slug: z
    .string()
    .trim()
    .toLowerCase()
    .regex(/^[a-z0-9]+(-[a-z0-9]+)*$/, 'Slug may only contain lowercase letters, numbers and dashes'),
  description: optionalText(5000),
  base_price_cents: cents,
  is_customizable: z.boolean().default(false),
  customization_label: optionalText(80),
  /** Lists the customer picks one value from (no price or stock of their own). */
  choice_fields: z
    .array(choiceFieldSchema)
    .max(10)
    .default([])
    .refine((fields) => new Set(fields.map((f) => f.label.toLowerCase())).size === fields.length, {
      message: 'Two choice lists have the same name',
    }),
  is_active: z.boolean().default(true),
  is_featured: z.boolean().default(false),
  variants: z.array(variantSchema).min(1, 'A product needs at least one variant').max(100),
});

export type ProductInput = z.infer<typeof productSchema>;

/**
 * Checks everything that could make a write fail halfway (unique slug and
 * SKUs, variants that belong to another product) before writing anything,
 * since supabase-js can't wrap the writes in a transaction.
 */
async function validateBeforeSave(
  productId: string | null,
  input: ProductInput,
  categoryIds: string[],
): Promise<void> {
  const db = supabaseAdmin();
  await assertCategoriesExist(db, categoryIds);

  let slugQuery = db.from('products').select('id').eq('slug', input.slug);
  if (productId) slugQuery = slugQuery.neq('id', productId);
  if ((unwrap(await slugQuery) as unknown[]).length > 0) {
    throw conflict('Another product already uses this slug');
  }

  const skus = input.variants.map((v) => v.sku).filter((sku): sku is string => Boolean(sku));
  if (new Set(skus).size !== skus.length) throw badRequest('Two variants have the same SKU');
  if (skus.length > 0) {
    let skuQuery = db.from('product_variants').select('sku').in('sku', skus);
    if (productId) skuQuery = skuQuery.neq('product_id', productId);
    const taken = unwrap(await skuQuery) as { sku: string }[];
    if (taken.length > 0) throw conflict(`Another product already uses SKU ${taken[0].sku}`);
  }

  const ids = input.variants.map((v) => v.id).filter((id): id is string => Boolean(id));
  if (ids.length > 0) {
    if (!productId) throw badRequest('New products cannot reference existing variants');
    const own = unwrap(
      await db.from('product_variants').select('id').eq('product_id', productId).in('id', ids),
    ) as { id: string }[];
    if (own.length !== new Set(ids).size) throw badRequest('Some variants do not belong to this product');
  }
}

/** Rewrites unique-constraint errors (e.g. a race with another save) into clear messages. */
function explainUniqueViolation(error: unknown): never {
  const e = error as { code?: string; message?: string };
  if (e.code === '23505') {
    if (e.message?.includes('slug')) throw conflict('Another product already uses this slug');
    if (e.message?.includes('sku')) throw conflict('Another variant already uses this SKU');
  }
  throw error;
}

/**
 * Creates a product (when `productId` is null) or updates it, and syncs its
 * variants: variants missing from the input are deleted, the rest are updated
 * or inserted in the given order. Its categories are synced the same way.
 * A new product is deleted again if its variants or categories can't be saved.
 */
export async function saveProduct(productId: string | null, input: ProductInput): Promise<Product> {
  const db = supabaseAdmin();
  const { variants, category_ids: _categoryIds, ...fields } = input;
  const categoryIds = normalizeCategoryIds(input);
  const row = {
    ...fields,
    category_id: categoryIds[0] ?? null,
    customization_label: fields.is_customizable ? fields.customization_label : null,
  };

  if (productId) await getProduct(productId); // 404 before validating
  await validateBeforeSave(productId, input, categoryIds);

  try {
    if (productId === null) {
      const created = unwrap(await db.from('products').insert(row).select('id').single()) as { id: string };
      try {
        check(
          (
            await db
              .from('product_variants')
              .insert(variants.map(({ id: _id, ...v }, position) => ({ ...v, position, product_id: created.id })))
          ).error,
        );
        await syncProductCategories(db, created.id, categoryIds);
      } catch (error) {
        await db.from('products').delete().eq('id', created.id); // variants and links cascade
        throw error;
      }
      return getProduct(created.id);
    }

    check((await db.from('products').update({ ...row, updated_at: now() }).eq('id', productId)).error);

    const keptIds = variants.map((v) => v.id).filter((id): id is string => Boolean(id));
    let removed = db.from('product_variants').delete().eq('product_id', productId);
    if (keptIds.length > 0) removed = removed.not('id', 'in', `(${keptIds.join(',')})`);
    check((await removed).error);

    for (const [position, { id, ...variant }] of variants.entries()) {
      const { error } = id
        ? await db
            .from('product_variants')
            .update({ ...variant, position, updated_at: now() })
            .eq('id', id)
            .eq('product_id', productId)
        : await db.from('product_variants').insert({ ...variant, position, product_id: productId });
      check(error);
    }
    await syncProductCategories(db, productId, categoryIds);
    return getProduct(productId);
  } catch (error) {
    explainUniqueViolation(error);
  }
}

export const patchProductSchema = z
  .object({
    is_active: z.boolean().optional(),
    is_featured: z.boolean().optional(),
  })
  .refine((body) => Object.keys(body).length > 0, { message: 'Nothing to update' });

/** Quick toggles from the product list. */
export async function patchProduct(
  productId: string,
  input: z.infer<typeof patchProductSchema>,
): Promise<Product> {
  const updated = unwrap(
    await supabaseAdmin()
      .from('products')
      .update({ ...input, updated_at: now() })
      .eq('id', productId)
      .select('id'),
  ) as unknown[];
  if (updated.length === 0) throw notFound('Product not found');
  return getProduct(productId);
}

// -----------------------------------------------------------------------------
// Duplicate
// -----------------------------------------------------------------------------

/** A free slug for a copy: "<slug>-copia", then "<slug>-copia-2", "-3"... */
async function copySlug(slug: string): Promise<string> {
  const base = `${slug}-copia`;
  const rows = unwrap(
    await supabaseAdmin().from('products').select('slug').like('slug', `${base}%`),
  ) as { slug: string }[];
  const taken = new Set(rows.map((row) => row.slug));
  if (!taken.has(base)) return base;
  let n = 2;
  while (taken.has(`${base}-${n}`)) n++;
  return `${base}-${n}`;
}

type FullProduct = Product & {
  name: string;
  slug: string;
  category_ids: string[];
  product_variants: (Record<string, unknown> & { id: string; position: number })[];
  product_images: {
    id: string;
    position: number;
    url: string;
    storage_path: string | null;
    alt_text: string | null;
    variant_id: string | null;
  }[];
};

/**
 * Copies a product with its variants, categories and images. The copy is
 * hidden and not featured, named "<name> (copia)" with a free slug, so it
 * can be reviewed before it shows in the shop. Variants lose their SKU
 * (SKUs are unique) and stored images get their own copy of the file, so
 * deleting either product never removes the other's photos. If any step
 * fails, the half-made copy is deleted.
 */
export async function duplicateProduct(productId: string): Promise<Product> {
  const source = (await getProduct(productId)) as FullProduct;
  const db = supabaseAdmin();
  const {
    id: _id,
    created_at: _created,
    updated_at: _updated,
    product_variants: variants,
    product_images: sourceImages,
    product_categories: _links,
    category_ids: categoryIds,
    ...fields
  } = source;

  const created = unwrap(
    await db
      .from('products')
      .insert({
        ...fields,
        name: `${source.name} (copia)`.slice(0, 200),
        slug: await copySlug(source.slug),
        is_active: false,
        is_featured: false,
      })
      .select('id')
      .single(),
  ) as { id: string };

  const copiedFiles: string[] = [];
  try {
    const variantIds = new Map<string, string>();
    for (const variant of variants) {
      const { id, product_id: _p, created_at: _c, updated_at: _u, sku: _sku, ...rest } = variant;
      const copy = unwrap(
        await db
          .from('product_variants')
          .insert({ ...rest, product_id: created.id, sku: null })
          .select('id')
          .single(),
      ) as { id: string };
      variantIds.set(id, copy.id);
    }

    await syncProductCategories(db, created.id, categoryIds);

    for (const image of sourceImages) {
      let storagePath: string | null = null;
      let url = image.url;
      if (image.storage_path) {
        storagePath = await images.copyImageFile(image.storage_path, created.id);
        copiedFiles.push(storagePath);
        url = images.publicImageUrl(storagePath);
      }
      check(
        (
          await db.from('product_images').insert({
            product_id: created.id,
            variant_id: image.variant_id ? (variantIds.get(image.variant_id) ?? null) : null,
            url,
            storage_path: storagePath,
            alt_text: image.alt_text,
            position: image.position,
          })
        ).error,
      );
    }
  } catch (error) {
    await db.from('products').delete().eq('id', created.id);
    await images.removeImageFiles(copiedFiles);
    throw error;
  }
  return getProduct(created.id);
}

/** Deletes the product (variants and images cascade) and its stored files. */
export async function deleteProduct(productId: string): Promise<void> {
  const db = supabaseAdmin();
  const stored = unwrap(
    await db.from('product_images').select('storage_path').eq('product_id', productId),
  ) as { storage_path: string | null }[];
  const deleted = unwrap(await db.from('products').delete().eq('id', productId).select('id')) as unknown[];
  if (deleted.length === 0) throw notFound('Product not found');
  await images.removeImageFiles(stored.map((image) => image.storage_path));
}

// -----------------------------------------------------------------------------
// Images
// -----------------------------------------------------------------------------

// Storing files is up to images.ts; here only which product they belong to.

export const uploadUrlSchema = z.object({
  file_name: z.string().trim().min(1).max(200),
});

/**
 * Where and how the admin app uploads a new image of the product (straight
 * to the storage provider: no file goes through the API). Register it
 * afterwards with [addImage].
 */
export async function createImageUpload(productId: string, fileName: string) {
  await getProduct(productId);
  return images.createImageUpload(productId, fileName);
}

export const addImageSchema = z
  .object({
    /** Path returned by the upload-url endpoint, once the file is uploaded. */
    storage_path: z.string().trim().min(1).max(300).optional(),
    /** Or an external image URL (e.g. migrated from Wix). */
    url: z.url({ protocol: /^https?$/ }).max(2000).optional(),
    alt_text: optionalText(200),
  })
  .refine((body) => Boolean(body.storage_path) !== Boolean(body.url), {
    message: 'Send either storage_path or url',
  });

export async function addImage(productId: string, input: z.infer<typeof addImageSchema>): Promise<Product> {
  const product = await getProduct(productId);
  const db = supabaseAdmin();

  let url = input.url ?? '';
  if (input.storage_path) {
    if (!images.isProductImagePath(productId, input.storage_path)) {
      throw badRequest('The image does not belong to this product');
    }
    // Stored for reference; reads rebuild it from storage_path (images.ts).
    url = images.publicImageUrl(input.storage_path);
  }

  const position = product.product_images.reduce((max, image) => Math.max(max, image.position + 1), 0);
  check(
    (
      await db.from('product_images').insert({
        product_id: productId,
        url,
        storage_path: input.storage_path ?? null,
        alt_text: input.alt_text,
        position,
      })
    ).error,
  );
  return getProduct(productId);
}

export async function deleteImage(imageId: string): Promise<void> {
  const deleted = unwrap(
    await supabaseAdmin().from('product_images').delete().eq('id', imageId).select('storage_path'),
  ) as { storage_path: string | null }[];
  if (deleted.length === 0) throw notFound('Image not found');
  await images.removeImageFiles(deleted.map((image) => image.storage_path));
}
