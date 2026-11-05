import { randomUUID } from 'node:crypto';

import { z } from 'zod';

import { badRequest, conflict, notFound } from '../http';
import { check, now, PRODUCT_IMAGES_BUCKET, supabaseAdmin, unwrap } from '../supabase';

// Admin panel only: every function here is called after the route checked the
// admin role, and uses the service-role client (it must see inactive items).

export type Product = Record<string, unknown> & {
  id: string;
  product_variants: { id: string; position: number }[];
  product_images: { id: string; position: number; storage_path: string | null }[];
};

const productSelect = '*, product_variants(*), product_images(*)';

function sortNested(product: Product): Product {
  product.product_variants.sort((a, b) => a.position - b.position);
  product.product_images.sort((a, b) => a.position - b.position);
  return product;
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

export const productSchema = z.object({
  category_id: z.uuid().nullable().default(null),
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
async function validateBeforeSave(productId: string | null, input: ProductInput): Promise<void> {
  const db = supabaseAdmin();

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
 * or inserted in the given order. A new product is deleted again if its
 * variants can't be saved.
 */
export async function saveProduct(productId: string | null, input: ProductInput): Promise<Product> {
  const db = supabaseAdmin();
  const { variants, ...fields } = input;
  const row = {
    ...fields,
    customization_label: fields.is_customizable ? fields.customization_label : null,
  };

  if (productId) await getProduct(productId); // 404 before validating
  await validateBeforeSave(productId, input);

  try {
    if (productId === null) {
      const created = unwrap(await db.from('products').insert(row).select('id').single()) as { id: string };
      const { error } = await db
        .from('product_variants')
        .insert(variants.map(({ id: _id, ...v }, position) => ({ ...v, position, product_id: created.id })));
      if (error) {
        await db.from('products').delete().eq('id', created.id);
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

/** Deletes the product (variants and images cascade) and its stored files. */
export async function deleteProduct(productId: string): Promise<void> {
  const db = supabaseAdmin();
  const images = unwrap(
    await db.from('product_images').select('storage_path').eq('product_id', productId),
  ) as { storage_path: string | null }[];
  const deleted = unwrap(await db.from('products').delete().eq('id', productId).select('id')) as unknown[];
  if (deleted.length === 0) throw notFound('Product not found');
  await removeFiles(images.map((image) => image.storage_path));
}

// -----------------------------------------------------------------------------
// Images
// -----------------------------------------------------------------------------

const IMAGE_TYPES: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  gif: 'image/gif',
};

export const uploadUrlSchema = z.object({
  file_name: z.string().trim().min(1).max(200),
});

/**
 * Issues a signed URL so the admin app uploads the file straight to Storage
 * (no file goes through the API). Register it afterwards with [addImage].
 */
export async function createImageUpload(productId: string, fileName: string) {
  await getProduct(productId);

  const extension = fileName.includes('.') ? fileName.split('.').pop()!.toLowerCase() : '';
  const contentType = IMAGE_TYPES[extension];
  if (!contentType) throw badRequest('Only JPG, PNG, WEBP or GIF images are allowed');

  const path = `${productId}/${Date.now()}-${randomUUID().slice(0, 8)}.${extension}`;
  const { data, error } = await supabaseAdmin().storage.from(PRODUCT_IMAGES_BUCKET).createSignedUploadUrl(path);
  if (error || !data) throw new Error(`Could not create upload URL: ${error?.message}`);

  return { bucket: PRODUCT_IMAGES_BUCKET, path: data.path, token: data.token, content_type: contentType };
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
    if (!input.storage_path.startsWith(`${productId}/`)) {
      throw badRequest('The image does not belong to this product');
    }
    url = db.storage.from(PRODUCT_IMAGES_BUCKET).getPublicUrl(input.storage_path).data.publicUrl;
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
  await removeFiles(deleted.map((image) => image.storage_path));
}

/** Best effort: a leftover file must not fail an otherwise finished request. */
async function removeFiles(paths: (string | null)[]): Promise<void> {
  const files = paths.filter((path): path is string => Boolean(path));
  if (files.length === 0) return;
  const { error } = await supabaseAdmin().storage.from(PRODUCT_IMAGES_BUCKET).remove(files);
  if (error) console.error('Could not delete files from storage', files, error.message);
}
