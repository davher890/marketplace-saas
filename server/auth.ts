import { db } from './db';
import { HttpError } from './http';
import { supabaseAdmin } from './supabase';

export interface AuthUser {
  id: string;
  email: string | null;
  /** Name given at sign up (`user_metadata.full_name`). */
  fullName: string | null;
}

function bearerToken(request: Request): string {
  const header = request.headers.get('authorization') ?? '';
  return header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';
}

/** Verifies the Supabase access token sent by the app and returns its user. */
export async function requireUser(request: Request): Promise<AuthUser> {
  const token = bearerToken(request);
  if (!token) throw new HttpError(401, 'Missing access token');

  const { data, error } = await supabaseAdmin().auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, 'Invalid or expired session');

  const fullName = data.user.user_metadata?.full_name;
  return {
    id: data.user.id,
    email: data.user.email ?? null,
    fullName: typeof fullName === 'string' && fullName.trim() ? fullName.trim() : null,
  };
}

export async function isAdmin(userId: string): Promise<boolean> {
  const [row] = await db()<{ role: string }[]>`
    select role from profiles where id = ${userId}
  `;
  return row?.role === 'admin';
}

/** Like [requireUser], but also requires the `admin` role. */
export async function requireAdmin(request: Request): Promise<AuthUser> {
  const user = await requireUser(request);
  if (!(await isAdmin(user.id))) throw new HttpError(403, 'Admin access required');
  return user;
}
