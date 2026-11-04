import { corsHeaders, errorResponse, json, Reply } from './http';
import { router } from './routes';

/**
 * Resolves the API path. On Vercel every `/api/*` request is rewritten to the
 * single `api/index.ts` function with the original path in `__path`
 * (see `vercel.json`); locally the path arrives untouched.
 */
function resolvePath(url: URL): string {
  const rewritten = url.searchParams.get('__path');
  url.searchParams.delete('__path');
  const path = rewritten !== null ? `/api/${rewritten}` : url.pathname;
  return path.length > 1 ? path.replace(/\/+$/, '') : path;
}

/** Entry point shared by the Vercel function and the local dev server. */
export async function handle(request: Request): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(request) });
  }

  try {
    const url = new URL(request.url);
    const match = router.match(request.method, resolvePath(url));
    if (match === null) return json(request, { error: 'Not found' }, 404);
    if (match === 'method-not-allowed') return json(request, { error: 'Method not allowed' }, 405);

    const result = await match.handler({ request, params: match.params, query: url.searchParams });
    if (result instanceof Response) return result;
    if (result instanceof Reply) return json(request, result.body, result.status);
    return json(request, result);
  } catch (error) {
    return errorResponse(request, error);
  }
}
