export interface RouteContext {
  request: Request;
  params: Record<string, string>;
  query: URLSearchParams;
}

/** Returns a body (sent as JSON with status 200), a `Reply`, or a `Response`. */
export type RouteHandler = (context: RouteContext) => Promise<unknown>;

interface Route {
  method: string;
  pattern: RegExp;
  paramNames: string[];
  handler: RouteHandler;
}

/** Minimal method + path router, e.g. `router.get('/api/orders/:id', handler)`. */
export class Router {
  private readonly routes: Route[] = [];

  add(method: string, path: string, handler: RouteHandler): this {
    const paramNames: string[] = [];
    const source = path.replace(/:(\w+)/g, (_, name: string) => {
      paramNames.push(name);
      return '([^/]+)';
    });
    this.routes.push({ method, pattern: new RegExp(`^${source}$`), paramNames, handler });
    return this;
  }

  get = (path: string, handler: RouteHandler) => this.add('GET', path, handler);
  post = (path: string, handler: RouteHandler) => this.add('POST', path, handler);
  put = (path: string, handler: RouteHandler) => this.add('PUT', path, handler);
  patch = (path: string, handler: RouteHandler) => this.add('PATCH', path, handler);
  delete = (path: string, handler: RouteHandler) => this.add('DELETE', path, handler);

  /** `null` when nothing matches; `'method-not-allowed'` when only the path does. */
  match(
    method: string,
    path: string,
  ): { handler: RouteHandler; params: Record<string, string> } | 'method-not-allowed' | null {
    let pathMatched = false;
    for (const route of this.routes) {
      const match = route.pattern.exec(path);
      if (!match) continue;
      pathMatched = true;
      if (route.method !== method) continue;
      const params = Object.fromEntries(
        route.paramNames.map((name, index) => [name, decodeURIComponent(match[index + 1])]),
      );
      return { handler: route.handler, params };
    }
    return pathMatched ? 'method-not-allowed' : null;
  }
}
