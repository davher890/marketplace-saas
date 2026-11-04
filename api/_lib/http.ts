import { HttpError } from './supabase';

/**
 * Comma separated list of origins allowed to call the API from a browser on a
 * different origin (e.g. `http://localhost:5000` while running `flutter run -d chrome`).
 * The deployed web app is same-origin and the Android app is not subject to CORS.
 */
const allowedOrigins = (process.env.ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get('origin');
  if (!origin || !allowedOrigins.includes(origin)) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

export function json(request: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders(request) },
  });
}

export function preflight(request: Request): Response {
  return new Response(null, { status: 204, headers: corsHeaders(request) });
}

/** Converts thrown errors into JSON error responses. */
export function errorResponse(request: Request, error: unknown): Response {
  if (error instanceof HttpError) {
    return json(request, { error: error.message }, error.status);
  }
  console.error(error);
  return json(request, { error: 'Internal server error' }, 500);
}
