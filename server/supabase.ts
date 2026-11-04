import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import { HttpError } from './http';

export const PRODUCT_IMAGES_BUCKET = 'product-images';

let client: SupabaseClient | undefined;

/**
 * Supabase client with the secret key. Used only for Auth (verifying access
 * tokens) and Storage (signed uploads, deleting files); data goes through `db()`.
 */
export function supabaseAdmin(): SupabaseClient {
  if (client) return client;

  const url = process.env.SUPABASE_URL;
  const secretKey = process.env.SUPABASE_SECRET_KEY;
  if (!url || !secretKey) {
    throw new HttpError(500, 'Server is missing SUPABASE_URL or SUPABASE_SECRET_KEY');
  }

  client = createClient(url, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return client;
}
