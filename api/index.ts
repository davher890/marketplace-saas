// Single Vercel function serving the whole API. `vercel.json` rewrites every
// `/api/*` request here; routing happens in `server/routes.ts`.
import { handle } from '../server/handler';

export const GET = handle;
export const POST = handle;
export const PUT = handle;
export const PATCH = handle;
export const DELETE = handle;
export const OPTIONS = handle;
