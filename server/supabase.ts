import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import { HttpError } from './http';

export const PRODUCT_IMAGES_BUCKET = 'product-images';

const noSession = { auth: { persistSession: false, autoRefreshToken: false } } as const;

function env(name: string): string {
  const value = process.env[name];
  if (!value) throw new HttpError(500, `Server is missing ${name}`);
  return value;
}

let publicClient: SupabaseClient | undefined;
let adminClient: SupabaseClient | undefined;

/**
 * Client with the publishable key. Used to verify access tokens and to read
 * the public catalog; RLS applies as the `anon` role.
 */
export function supabase(): SupabaseClient {
  publicClient ??= createClient(env('SUPABASE_URL'), env('SUPABASE_PUBLISHABLE_KEY'), noSession);
  return publicClient;
}

/**
 * Client that runs queries as the calling user (their access token is sent
 * with every request), so RLS policies based on `auth.uid()` see the real
 * caller. Used for everything a customer does with their own data.
 */
export function supabaseForUser(token: string): SupabaseClient {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_PUBLISHABLE_KEY'), {
    ...noSession,
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
}

/**
 * Client with the secret (service-role) key: it is NOT subject to RLS.
 * Server-side only, and only for operations a customer must not be able to
 * do with their own token (creating orders, changing stock, admin panel),
 * always after the API has checked who is calling.
 */
export function supabaseAdmin(): SupabaseClient {
  adminClient ??= createClient(env('SUPABASE_URL'), env('SUPABASE_SECRET_KEY'), noSession);
  return adminClient;
}

/** Throws the supabase-js error (mapped to an HTTP status by the handler). */
export function check(error: unknown): void {
  if (error) throw error;
}

/** Returns `data` or throws the supabase-js error. */
export function unwrap<T>(result: { data: T | null; error: unknown }): T {
  check(result.error);
  return result.data as T;
}

export const now = () => new Date().toISOString();
