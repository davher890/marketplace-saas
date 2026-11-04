import { createClient, type SupabaseClient, type User } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_PUBLISHABLE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY;

export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function requireConfig(): { url: string; key: string } {
  if (!SUPABASE_URL || !SUPABASE_PUBLISHABLE_KEY) {
    throw new HttpError(500, 'Server is missing Supabase configuration');
  }
  return { url: SUPABASE_URL, key: SUPABASE_PUBLISHABLE_KEY };
}

/**
 * Builds a Supabase client that acts as the caller: every query runs with the
 * user's JWT, so Row Level Security and `auth.uid()` apply exactly as in the app.
 * Returns the verified user together with the client.
 */
export async function clientForRequest(
  request: Request,
): Promise<{ supabase: SupabaseClient; user: User }> {
  const { url, key } = requireConfig();
  const header = request.headers.get('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';
  if (!token) throw new HttpError(401, 'Missing access token');

  const supabase = createClient(url, key, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, 'Invalid or expired session');

  return { supabase, user: data.user };
}

/** Maps Postgres error codes raised by our SQL functions to HTTP statuses. */
export function statusForPostgresError(code: string | undefined): number {
  switch (code) {
    case '28000': // not authenticated
      return 401;
    case '22023': // invalid parameter
      return 400;
    case 'P0002': // not found
      return 404;
    case 'P0001': // business rule (empty cart, out of stock...)
      return 409;
    default:
      return 500;
  }
}
