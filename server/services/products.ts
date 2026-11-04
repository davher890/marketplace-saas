import { randomUUID } from 'node:crypto';

import { z } from 'zod';

import { db, type Db } from '../db';
import { badRequest, conflict, notFound } from '../http';
import { PRODUCT_IMAGES_BUCKET, supabaseAdmin } from '../supabase';

export type Product = Record<string, unknown> & {
  id: string;
  product_variants: Record<string, unknown>[];
  product_images: { id: string; storage_path: string | null }[];
};

const productSelect = (sql: Db) => sql`
  select p.*,
    coalesce(
      (select json_agg(v order by v.position, v.created_at) from product_variants v where v.product_id = p.id),
      '[]'
    ) as product_variants,
    coalesce(
      (select json_agg(i order by i.position, i.created_at) from product_images i where i.product_id = p.id),
      '[]'
    ) as product_images
  from products p
`;

/** Every product, active or not, for the admin panel. */
export async function listProducts(): Promise<Product[]> {
  const sql = db();
  const rows = await sql<Product[]>`${productSelect(sql)} order by p.updated_at desc`;
  return [...rows];
}

export async function getProduct(sql: Db, productId: string): Promise<Product> {
  const [product] = await sql<Product[]>`${productSelect(sql)} where p.id = ${productId}`;
  if (!product) throw notFound('Product not found');
  return product;
}

/** Every category, active or not, for the product form. */
export async function listCategories(): Promise<Record<string, unknown>[]> {
  const rows = await db()`select * from categories order by position, name`;
  return [...rows];
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

/** Rewrites unique-constraint errors into messages the admin can act on. */
function explainUniqueViolation(error: unknown): never {
  const e = error as { code?: string; constraint_name?: string };
  if (e.code === '23505') {
    if (e.constraint_name?.includes('slug')) throw conflict('Another product already uses this slug');
    if (e.constraint_name?.includes('sku')) throw conflict('Another variant already uses this SKU');
  }
  throw error;
}

/**
 * Creates a product (when `productId` is null) or updates it, and syncs its
 * variants in the same transaction: variants missing from the input are
 * deleted, the rest are updated or inserted in the given order.
 */
export async function saveProduct(productId: string | null, input: ProductInput): Promise<Product> {
  const { variants, ...fields } = input;
  const row = {
    ...fields,
    customization_label: fields.is_customizable ? fields.customization_label : null,
  };

  try {
    const id = await db().begin(async (sql) => {
      let id: string;
      if (productId === null) {
        const [created] = await sql<{ id: string }[]>`insert into products ${sql(row)} returning id`;
        id = created.id;
      } else {
        const updated = await sql`
          update products set ${sql(row)}, updated_at = now()
          where id = ${productId}
          returning id
        `;
        if (updated.length === 0) throw notFound('Product not found');
        id = productId;
      }

      const keptIds = variants.map((v) => v.id).filter((v): v is string => Boolean(v));
      await sql`
        delete from product_variants
        where product_id = ${id}
          ${keptIds.length ? sql`and id not in ${sql(keptIds)}` : sql``}
      `;

      for (const [position, variant] of variants.entries()) {
        const { id: variantId, options, ...variantFields } = variant;
        const values = { ...variantFields, options: sql.json(options), position };
        if (variantId) {
          const updated = await sql`
            update product_variants set ${sql(values)}, updated_at = now()
            where id = ${variantId} and product_id = ${id}
            returning id
          `;
          if (updated.length === 0) throw badRequest(`Variant ${variantId} does not belong to this product`);
        } else {
          await sql`insert into product_variants ${sql({ ...values, product_id: id })}`;
        }
      }
      return id;
    });
    return getProduct(db(), id);
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
  const sql = db();
  const updated = await sql`
    update products set ${sql(input)}, updated_at = now()
    where id = ${productId}
    returning id
  `;
  if (updated.length === 0) throw notFound('Product not found');
  return getProduct(sql, productId);
}

/** Deletes the product (variants and images cascade) and its stored files. */
export async function deleteProduct(productId: string): Promise<void> {
  const paths = await db().begin(async (sql) => {
    const images = await sql<{ storage_path: string | null }[]>`
      select storage_path from product_images where product_id = ${productId}
    `;
    const deleted = await sql`delete from products where id = ${productId} returning id`;
    if (deleted.length === 0) throw notFound('Product not found');
    return images.map((image) => image.storage_path);
  });
  await removeFiles(paths);
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
  await getProduct(db(), productId);

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
  const sql = db();
  await getProduct(sql, productId);

  let url = input.url ?? '';
  if (input.storage_path) {
    if (!input.storage_path.startsWith(`${productId}/`)) {
      throw badRequest('The image does not belong to this product');
    }
    url = supabaseAdmin().storage.from(PRODUCT_IMAGES_BUCKET).getPublicUrl(input.storage_path).data.publicUrl;
  }

  await sql`
    insert into product_images (product_id, url, storage_path, alt_text, position)
    select ${productId}, ${url}, ${input.storage_path ?? null}, ${input.alt_text},
           coalesce(max(position) + 1, 0)
    from product_images
    where product_id = ${productId}
  `;
  return getProduct(sql, productId);
}

export async function deleteImage(imageId: string): Promise<void> {
  const [deleted] = await db()<{ storage_path: string | null }[]>`
    delete from product_images where id = ${imageId} returning storage_path
  `;
  if (!deleted) throw notFound('Image not found');
  await removeFiles([deleted.storage_path]);
}

/** Best effort: a leftover file must not fail an otherwise finished request. */
async function removeFiles(paths: (string | null)[]): Promise<void> {
  const files = paths.filter((path): path is string => Boolean(path));
  if (files.length === 0) return;
  const { error } = await supabaseAdmin().storage.from(PRODUCT_IMAGES_BUCKET).remove(files);
  if (error) console.error('Could not delete files from storage', files, error.message);
}
