// Local development server for the API: `npm run dev:api` (reads `.env`).
// Logs one line per request, the error message of failed requests, and a
// warning when a browser origin is not in ALLOWED_ORIGINS (CORS would block it).
import { createServer } from 'node:http';

import { handle } from './handler';

const port = Number(process.env.PORT ?? 3000);
const useColor = process.stdout.isTTY;

const paint = (code: number, text: string) => (useColor ? `\x1b[${code}m${text}\x1b[0m` : text);
const statusColor = (status: number) => (status >= 500 ? 31 : status >= 400 ? 33 : 32);

createServer(async (req, res) => {
  const startedAt = performance.now();
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;

  const headers = new Headers();
  for (const [key, value] of Object.entries(req.headers)) {
    if (typeof value === 'string') headers.set(key, value);
    else if (Array.isArray(value)) headers.set(key, value.join(', '));
  }

  const request = new Request(`http://localhost:${port}${req.url}`, {
    method: req.method,
    headers,
    body: req.method === 'GET' || req.method === 'HEAD' ? undefined : body,
  });

  const response = await handle(request);
  const payload = Buffer.from(await response.arrayBuffer());
  res.writeHead(response.status, Object.fromEntries(response.headers));
  res.end(payload);

  const ms = Math.round(performance.now() - startedAt);
  const time = new Date().toLocaleTimeString('es-ES');
  let line = `${paint(90, time)} ${req.method} ${req.url} ${paint(statusColor(response.status), String(response.status))} ${ms}ms`;
  if (response.status >= 400 && payload.length > 0) {
    try {
      line += `  ${paint(90, (JSON.parse(payload.toString()) as { error?: string }).error ?? '')}`;
    } catch {
      // Not JSON: nothing to add.
    }
  }
  console.log(line);

  const origin = req.headers.origin;
  if (origin && !response.headers.has('access-control-allow-origin')) {
    console.warn(
      paint(33, `  ↳ origin ${origin} is not in ALLOWED_ORIGINS: the browser will block this response`),
    );
  }
}).listen(port, () => {
  console.log(`API listening on http://localhost:${port}/api`);
  console.log(`Allowed browser origins: ${process.env.ALLOWED_ORIGINS || '(none)'}`);
});
