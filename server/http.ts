import { z } from 'zod';

/** Error with an HTTP status, turned into a JSON response by the handler. */
export class HttpError extends Error {
  constructor(
    public readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export const badRequest = (message: string) => new HttpError(400, message);
export const notFound = (message = 'Not found') => new HttpError(404, message);
export const conflict = (message: string) => new HttpError(409, message);

/** Lets a route choose a status code other than 200. */
export class Reply {
  constructor(
    public readonly body: unknown,
    public readonly status = 200,
  ) {}
}

/**
 * Comma separated list of origins allowed to call the API from a browser on a
 * different origin (e.g. `http://localhost:5000` while running `flutter run -d chrome`).
 * The deployed web app is same-origin and the Android app is not subject to CORS.
 */
function allowedOrigins(): string[] {
  return (process.env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}

export function corsHeaders(request: Request): Record<string, string> {
  const origin = request.headers.get('origin');
  if (!origin || !allowedOrigins().includes(origin)) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

export function json(request: Request, body: unknown, status = 200): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      ...corsHeaders(request),
    },
  });
}

/** Parses and validates the JSON body with a zod schema. */
export async function readBody<T>(request: Request, schema: z.ZodType<T>): Promise<T> {
  let raw: unknown;
  try {
    raw = await request.json();
  } catch {
    throw badRequest('Body must be valid JSON');
  }
  const result = schema.safeParse(raw);
  if (!result.success) {
    const message = result.error.issues
      .map((issue) => (issue.path.length ? `${issue.path.join('.')}: ${issue.message}` : issue.message))
      .join('; ');
    throw badRequest(message);
  }
  return result.data;
}

/** Postgres error codes that are caused by bad input rather than a server bug. */
const postgresErrorStatus: Record<string, [number, string]> = {
  '22P02': [400, 'Invalid identifier or value'],
  '23502': [400, 'A required field is missing'],
  '23503': [400, 'A referenced record does not exist'],
  '23505': [409, 'A record with the same unique value already exists'],
  '23514': [400, 'A value is out of the allowed range'],
};

/** Converts any thrown error into a JSON error response. */
export function errorResponse(request: Request, error: unknown): Response {
  if (error instanceof HttpError) {
    return json(request, { error: error.message }, error.status);
  }
  const code = (error as { code?: string } | null)?.code;
  if (code && postgresErrorStatus[code]) {
    const [status, message] = postgresErrorStatus[code];
    const detail = (error as { detail?: string }).detail;
    return json(request, { error: detail ? `${message}: ${detail}` : message }, status);
  }
  console.error(error);
  return json(request, { error: 'Internal server error' }, 500);
}
