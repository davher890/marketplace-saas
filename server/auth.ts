import type { SupabaseClient } from '@supabase/supabase-js';

import { HttpError } from './http';
import { supabase, supabaseAdmin, supabaseForUser } from './supabase';

export interface AuthUser {
  id: string;
  email: string | null;
  /** Name given at sign up (`user_metadata.full_name`). */
  fullName: string | null;
  /** Supabase client acting as this user: RLS applies to every query. */
  db: SupabaseClient;
  /** The verified access token the request came with. */
  accessToken: string;
}

function bearerToken(request: Request): string {
  const header = request.headers.get('authorization') ?? '';
  return header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';
}

/**
 * Single place where a request's `Authorization: Bearer <token>` is verified.
 * Returns the user and a client that queries Supabase on their behalf.
 */
export async function requireUser(request: Request): Promise<AuthUser> {
  const token = bearerToken(request);
  if (!token) throw new HttpError(401, 'Missing access token');

  const { data, error } = await supabase().auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, 'Invalid or expired session');

  const fullName = data.user.user_metadata?.full_name;
  return {
    id: data.user.id,
    email: data.user.email ?? null,
    fullName: typeof fullName === 'string' && fullName.trim() ? fullName.trim() : null,
    db: supabaseForUser(token),
    accessToken: token,
  };
}

/**
 * The caller if the request carries an access token, null if it carries none.
 * A token that is present but invalid is still rejected (401), so the app
 * renews its session instead of silently acting anonymously.
 */
export async function optionalUser(request: Request): Promise<AuthUser | null> {
  return bearerToken(request) ? requireUser(request) : null;
}

/**
 * Reads the role from `profiles`. Uses the service-role client so the check
 * doesn't depend on how the profiles policies are written.
 */
export async function isAdmin(user: AuthUser): Promise<boolean> {
  const { data, error } = await supabaseAdmin().from('profiles').select('role').eq('id', user.id).maybeSingle();
  if (error) throw error;
  return data?.role === 'admin';
}

/** Like [requireUser], but also requires the `admin` role. */
export async function requireAdmin(request: Request): Promise<AuthUser> {
  const user = await requireUser(request);
  if (!(await isAdmin(user))) throw new HttpError(403, 'Admin access required');
  return user;
}

