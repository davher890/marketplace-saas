import { randomUUID } from 'node:crypto';

import { badRequest } from '../http';
import { supabaseAdmin } from '../supabase';

// Where product images are stored (Supabase Storage today). This is the only
// API file that knows the provider: switching to S3, Cloudinary, R2... means
// rewriting the functions below (and the app's upload file, see below).
//
// - The database keeps each stored image's `storage_path` (provider-neutral);
//   public URLs are always built here when reading ([withImageUrls]).
// - Uploads never go through the API: it hands the admin app a signed upload
//   ([UploadTarget]) and the app sends the file there with the Supabase SDK
//   (app/lib/repositories/product_image_repository.dart, the app's only
//   Supabase file). A new provider changes this file and that one.

const BUCKET = 'product-images';

const IMAGE_TYPES: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  gif: 'image/gif',
};

/**
 * A one-time upload to Supabase Storage, as the SDK's
 * `uploadBinaryToSignedUrl(path, token, bytes)` takes it. `path` is the
 * image's `storage_path` once uploaded.
 */
export interface UploadTarget {
  bucket: string;
  path: string;
  token: string;
  content_type: string;
}

/**
 * Picks where a new image of the product will live and how to upload it.
 * Only JPG, PNG, WEBP and GIF files are accepted.
 */
export async function createImageUpload(productId: string, fileName: string): Promise<UploadTarget> {
  const extension = fileName.includes('.') ? fileName.split('.').pop()!.toLowerCase() : '';
  const contentType = IMAGE_TYPES[extension];
  if (!contentType) throw badRequest('Only JPG, PNG, WEBP or GIF images are allowed');

  const path = `${productId}/${Date.now()}-${randomUUID().slice(0, 8)}.${extension}`;
  const { data, error } = await supabaseAdmin().storage.from(BUCKET).createSignedUploadUrl(path);
  if (error || !data) throw new Error(`Could not create upload URL: ${error?.message}`);

  return { bucket: BUCKET, path: data.path, token: data.token, content_type: contentType };
}

/** Whether a stored image path belongs to the product (uploads are per product). */
export function isProductImagePath(productId: string, storagePath: string): boolean {
  return storagePath.startsWith(`${productId}/`) && !storagePath.includes('..');
}

/** Public URL of a stored image. */
export function publicImageUrl(storagePath: string): string {
  return supabaseAdmin().storage.from(BUCKET).getPublicUrl(storagePath).data.publicUrl;
}

/**
 * Fills `url` of stored images from their `storage_path`, so URLs always point
 * at the current provider. External images (no `storage_path`) keep theirs.
 */
export function withImageUrls<T extends { url?: unknown; storage_path?: string | null }>(images: T[]): T[] {
  for (const image of images) {
    if (image.storage_path) image.url = publicImageUrl(image.storage_path);
  }
  return images;
}

/**
 * Copies a stored image into another product's folder (e.g. when a product
 * is duplicated), so each product owns its files and deleting one never
 * removes the other's. Returns the new `storage_path`.
 */
export async function copyImageFile(storagePath: string, toProductId: string): Promise<string> {
  const extension = storagePath.includes('.') ? storagePath.split('.').pop()!.toLowerCase() : 'jpg';
  const target = `${toProductId}/${Date.now()}-${randomUUID().slice(0, 8)}.${extension}`;
  const { error } = await supabaseAdmin().storage.from(BUCKET).copy(storagePath, target);
  if (error) throw new Error(`Could not copy image ${storagePath}: ${error.message}`);
  return target;
}

/** Deletes stored files. Best effort: a leftover file must not fail the request. */
export async function removeImageFiles(paths: (string | null | undefined)[]): Promise<void> {
  const files = paths.filter((path): path is string => Boolean(path));
  if (files.length === 0) return;
  const { error } = await supabaseAdmin().storage.from(BUCKET).remove(files);
  if (error) console.error('Could not delete image files', files, error.message);
}
