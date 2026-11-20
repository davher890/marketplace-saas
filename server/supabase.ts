import { createClient, type SupabaseClient } from '@supabase/supabase-js';

import { HttpError } from './http';

/**
 * Postgres schema with the shop's tables (see the migration
 * …09_move_to_dona_galleta_schema.sql). It must be listed in Supabase's
 * Data API → Exposed schemas.
 */
export const DB_SCHEMA = 'dona_galleta';

const noSession = {
  auth: { persistSession: false, autoRefreshToken: false },
  db: { schema: DB_SCHEMA },
} as const;

function env(name: string): string {
  const value = process.env[name];
  if (!value) throw new HttpError(500, `Server is missing ${name}`);
  return value;
}

/** A supabase-js client bound to `DB_SCHEMA` (tables are untyped). */
export type DbClient = SupabaseClient<any, typeof DB_SCHEMA>;

let publicClient: DbClient | undefined;
let adminClient: DbClient | undefined;

/**
 * Client with the publishable key. Used to verify access tokens and to read
 * the public catalog; RLS applies as the `anon` role.
 */
export function supabase(): DbClient {
  publicClient ??= createClient(env('SUPABASE_URL'), env('SUPABASE_PUBLISHABLE_KEY'), noSession);
  return publicClient;
}

/**
 * New client with the publishable key for one Supabase Auth call (sign in,
 * sign up, refresh...). A fresh one each time, so a session obtained for one
 * request can never leak into another.
 */
export function supabaseAuth(): SupabaseClient {
  return createClient(env('SUPABASE_URL'), env('SUPABASE_PUBLISHABLE_KEY'), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

/**
 * Client that runs queries as the calling user (their access token is sent
 * with every request), so RLS policies based on `auth.uid()` see the real
 * caller. Used for everything a customer does with their own data.
 */
export function supabaseForUser(token: string): DbClient {
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
export function supabaseAdmin(): DbClient {
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
