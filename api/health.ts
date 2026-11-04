import { json } from './_lib/http';

/** GET /api/health - quick check that the API is deployed. */
export function GET(request: Request): Response {
  return json(request, {
    status: 'ok',
    supabaseConfigured: Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_PUBLISHABLE_KEY),
  });
}
