import { HttpError } from '../http';
import { getProductBySlug, listCategories, listProducts } from './catalog';

/**
 * HTML for search engines and link previews. The shop is a Flutter app that
 * draws on a canvas, so the plain app page has no text to index and the same
 * title on every URL. For the shop's public pages (home, categories,
 * products) the API serves the app page with, added:
 *
 * - the page's own title, description and canonical URL;
 * - Open Graph / Twitter tags (photo and price in WhatsApp, Instagram...);
 * - schema.org data for Google (product, price, breadcrumbs);
 * - the page's content as plain HTML, shown while Flutter loads and removed
 *   on its first frame;
 * - a 404 status for products and categories that don't exist.
 *
 * `vercel.json` sends `/`, `/c/:slug`, `/product/:slug`, `/robots.txt` and
 * `/sitemap.xml` here; every other path still gets the plain app page.
 */

export const SHOP_NAME = 'Doña Galleta';
const TAGLINE = 'Regalos personalizados hechos a mano';
const HOME_DESCRIPTION =
  'Regalos personalizados hechos a mano: detalles con nombre para cumpleaños, comuniones, Navidad y el cole. Envíos a toda España.';

type Category = {
  id: string;
  parent_id: string | null;
  name: string;
  slug: string;
  description: string | null;
  image_url: string | null;
};

/** `stock` null: made to order, never sold out. */
type Variant = { name: string; price_cents: number | null; is_active: boolean; position: number; stock?: number | null };

export type SeoProduct = {
  name: string;
  slug: string;
  description: string | null;
  base_price_cents: number;
  updated_at?: string;
  category_ids?: string[];
  product_variants: Variant[];
  product_images: { position: number; url: string; storage_path: string | null }[];
};

/** What goes into the app page for one URL. */
export type Page = {
  status: number;
  title: string;
  description: string;
  /** Path of the canonical URL, e.g. `/product/lapices-con-nombre`. */
  path: string;
  image?: string;
  ogType?: 'website' | 'product';
  /** schema.org objects, one JSON-LD script each. */
  jsonLd?: object[];
  /** Visible content, already escaped. */
  body: string;
  /** Extra Open Graph `<meta property>` tags (e.g. product price). */
  meta?: Record<string, string>;
};

// --- Text helpers -------------------------------------------------------------

export function escapeHtml(text: string): string {
  return text.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

/** JSON inside `<script>`: `<` escaped so "</script>" in a text can't close it. */
function jsonScript(data: object): string {
  return `<script type="application/ld+json">${JSON.stringify(data).replace(/</g, '\\u003c')}</script>`;
}

/** At most [max] characters, cut at a word, with "…" when cut. One line. */
export function summary(text: string | null | undefined, max = 160): string {
  const clean = (text ?? '').replace(/\s+/g, ' ').trim();
  if (clean.length <= max) return clean;
  const cut = clean.slice(0, max - 1);
  const space = cut.lastIndexOf(' ');
  return `${(space > max * 0.6 ? cut.slice(0, space) : cut).replace(/[\s,.;:]+$/, '')}…`;
}

const euros = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR' });

/** 1250 -> "12,50 €". */
export function formatPrice(cents: number): string {
  return euros.format(cents / 100);
}

/** 1250 -> "12.50", for schema.org and Open Graph. */
const plainPrice = (cents: number) => (cents / 100).toFixed(2);

function paragraphs(text: string | null): string {
  return (text ?? '')
    .split(/\n\s*\n/)
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => `<p>${escapeHtml(p).replace(/\n/g, '<br>')}</p>`)
    .join('');
}

/** Lowest and highest price of the active variants (the base price without variants). */
export function priceRange(product: SeoProduct): { low: number; high: number; count: number } {
  const variants = product.product_variants.filter((v) => v.is_active);
  const prices = variants.length ? variants.map((v) => v.price_cents ?? product.base_price_cents) : [product.base_price_cents];
  return { low: Math.min(...prices), high: Math.max(...prices), count: prices.length };
}

/** Sold out: it has active variants and none can be bought (all with stock 0). */
export function soldOut(product: SeoProduct): boolean {
  const variants = product.product_variants.filter((v) => v.is_active);
  return variants.length > 0 && variants.every((v) => v.stock === 0);
}

const productPath = (slug: string) => `/product/${encodeURIComponent(slug)}`;
const categoryPath = (slug: string) => `/c/${encodeURIComponent(slug)}`;

/** Categories a customer can browse: active (the API only returns those) under an active parent. */
export function visibleCategories(categories: Category[]): Category[] {
  const ids = new Set(categories.map((c) => c.id));
  return categories.filter((c) => !c.parent_id || ids.has(c.parent_id));
}

function productLinks(products: SeoProduct[]): string {
  if (products.length === 0) return '<p>Todavía no hay productos aquí.</p>';
  const items = products.map(
    (p) =>
      `<li><a href="${productPath(p.slug)}">${escapeHtml(p.name)}</a> · desde ${formatPrice(priceRange(p).low)}</li>`,
  );
  return `<ul>${items.join('')}</ul>`;
}

function categoryLinks(categories: Category[]): string {
  if (categories.length === 0) return '';
  return `<ul>${categories.map((c) => `<li><a href="${categoryPath(c.slug)}">${escapeHtml(c.name)}</a></li>`).join('')}</ul>`;
}

function breadcrumbs(site: string, steps: { name: string; path: string }[]): object {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: steps.map((step, index) => ({
      '@type': 'ListItem',
      position: index + 1,
      name: step.name,
      item: `${site}${step.path}`,
    })),
  };
}

// --- Pages ----------------------------------------------------------------------

export function homePage(site: string, categories: Category[], products: SeoProduct[]): Page {
  const visible = visibleCategories(categories);
  const top = visible.filter((c) => !c.parent_id);
  return {
    status: 200,
    title: `${SHOP_NAME} · ${TAGLINE}`,
    description: HOME_DESCRIPTION,
    path: '/',
    image: products.find((p) => p.product_images.length > 0)?.product_images[0].url,
    jsonLd: [
      {
        '@context': 'https://schema.org',
        '@type': 'Store',
        name: SHOP_NAME,
        description: TAGLINE,
        url: `${site}/`,
        logo: `${site}/icons/Icon-512.png`,
        image: `${site}/icons/Icon-512.png`,
      },
      { '@context': 'https://schema.org', '@type': 'WebSite', name: SHOP_NAME, url: `${site}/` },
    ],
    body:
      `<h1>${SHOP_NAME}</h1><p>${escapeHtml(TAGLINE)}.</p>` +
      (top.length ? `<h2>Categorías</h2>${categoryLinks(top)}` : '') +
      `<h2>Productos</h2>${productLinks(products)}`,
  };
}

export function categoryPage(site: string, category: Category, categories: Category[], products: SeoProduct[]): Page {
  const visible = visibleCategories(categories);
  const parent = visible.find((c) => c.id === category.parent_id);
  const children = visible.filter((c) => c.parent_id === category.id);
  const names = products.slice(0, 4).map((p) => p.name.toLowerCase());
  const description = category.description?.trim()
    ? summary(category.description)
    : summary(`${category.name} en ${SHOP_NAME}, regalos personalizados hechos a mano${names.length ? `: ${names.join(', ')}` : ''}.`);
  const trail = [
    { name: SHOP_NAME, path: '/' },
    ...(parent ? [{ name: parent.name, path: categoryPath(parent.slug) }] : []),
    { name: category.name, path: categoryPath(category.slug) },
  ];
  return {
    status: 200,
    title: `${category.name} · ${SHOP_NAME}`,
    description,
    path: categoryPath(category.slug),
    image: category.image_url ?? products.find((p) => p.product_images.length > 0)?.product_images[0].url,
    jsonLd: [
      breadcrumbs(site, trail),
      {
        '@context': 'https://schema.org',
        '@type': 'ItemList',
        name: category.name,
        itemListElement: products.map((p, index) => ({
          '@type': 'ListItem',
          position: index + 1,
          url: `${site}${productPath(p.slug)}`,
          name: p.name,
        })),
      },
    ],
    body:
      (parent ? `<p><a href="${categoryPath(parent.slug)}">${escapeHtml(parent.name)}</a></p>` : '') +
      `<h1>${escapeHtml(category.name)}</h1>${paragraphs(category.description)}` +
      categoryLinks(children) +
      productLinks(products),
  };
}

export function productPage(site: string, product: SeoProduct, categories: Category[]): Page {
  const variants = product.product_variants.filter((v) => v.is_active);
  const { low, high, count } = priceRange(product);
  const images = product.product_images.map((i) => i.url);
  const url = `${site}${productPath(product.slug)}`;
  const visible = visibleCategories(categories);
  const category = (product.category_ids ?? []).map((id) => visible.find((c) => c.id === id)).find(Boolean);
  const named = variants.filter((v) => v.name && v.name !== 'Default');

  const offer = {
    priceCurrency: 'EUR',
    availability: soldOut(product) ? 'https://schema.org/OutOfStock' : 'https://schema.org/InStock',
    itemCondition: 'https://schema.org/NewCondition',
    url,
  };
  const productLd = {
    '@context': 'https://schema.org',
    '@type': 'Product',
    name: product.name,
    description: summary(product.description, 5000) || undefined,
    image: images.length ? images : undefined,
    url,
    brand: { '@type': 'Brand', name: SHOP_NAME },
    offers:
      low === high
        ? { '@type': 'Offer', price: plainPrice(low), ...offer }
        : { '@type': 'AggregateOffer', lowPrice: plainPrice(low), highPrice: plainPrice(high), offerCount: count, ...offer },
  };

  return {
    status: 200,
    title: `${product.name} · ${SHOP_NAME}`,
    description: summary(product.description) || `${product.name}, hecho a mano en ${SHOP_NAME}.`,
    path: productPath(product.slug),
    image: images[0],
    ogType: 'product',
    meta: { 'product:price:amount': plainPrice(low), 'product:price:currency': 'EUR' },
    jsonLd: [
      productLd,
      breadcrumbs(site, [
        { name: SHOP_NAME, path: '/' },
        ...(category ? [{ name: category.name, path: categoryPath(category.slug) }] : []),
        { name: product.name, path: productPath(product.slug) },
      ]),
    ],
    body:
      (category ? `<p><a href="${categoryPath(category.slug)}">${escapeHtml(category.name)}</a></p>` : '') +
      `<h1>${escapeHtml(product.name)}</h1>` +
      `<p><strong>${low === high ? '' : 'Desde '}${formatPrice(low)}</strong></p>` +
      (images[0] ? `<img src="${escapeHtml(images[0])}" alt="${escapeHtml(product.name)}" width="320">` : '') +
      paragraphs(product.description) +
      (named.length
        ? `<h2>Opciones</h2><ul>${named
            .map((v) => `<li>${escapeHtml(v.name)} · ${formatPrice(v.price_cents ?? product.base_price_cents)}</li>`)
            .join('')}</ul>`
        : ''),
  };
}

export function notFoundPage(path: string): Page {
  return {
    status: 404,
    title: `Página no encontrada · ${SHOP_NAME}`,
    description: HOME_DESCRIPTION,
    path,
    body: `<h1>Página no encontrada</h1><p><a href="/">Volver a la tienda</a></p>`,
  };
}

// --- Into the app page ------------------------------------------------------

const BOX_STYLE =
  'max-width:720px;margin:0 auto;padding:24px 16px;font-family:Raleway,system-ui,sans-serif;color:#37453B;line-height:1.5';

/**
 * The app page ([shell], the built `index.html`) with [page]'s title, tags
 * and content. The content sits before Flutter's script and is removed when
 * Flutter shows its first frame.
 */
export function renderPage(shell: string, page: Page, site: string): string {
  const url = `${site}${page.path}`;
  const image = page.image ? (/^https?:/.test(page.image) ? page.image : `${site}${page.image}`) : `${site}/icons/Icon-512.png`;
  const og: Record<string, string> = {
    'og:site_name': SHOP_NAME,
    'og:locale': 'es_ES',
    'og:type': page.ogType ?? 'website',
    'og:title': page.title,
    'og:description': page.description,
    'og:url': url,
    'og:image': image,
    ...page.meta,
  };
  const head = [
    `<link rel="canonical" href="${escapeHtml(url)}">`,
    ...Object.entries(og).map(([key, value]) => `<meta property="${key}" content="${escapeHtml(value)}">`),
    `<meta name="twitter:card" content="${page.image ? 'summary_large_image' : 'summary'}">`,
    ...(page.status === 404 ? ['<meta name="robots" content="noindex">'] : []),
    ...(page.jsonLd ?? []).map(jsonScript),
  ].join('\n  ');

  const title = `<title>${escapeHtml(page.title)}</title>`;
  const description = `<meta name="description" content="${escapeHtml(page.description)}">`;
  let html = /<title>[\s\S]*?<\/title>/.test(shell)
    ? shell.replace(/<title>[\s\S]*?<\/title>/, () => title)
    : shell.replace('</head>', () => `  ${title}\n</head>`);
  html = /<meta name="description"[^>]*>/.test(html)
    ? html.replace(/<meta name="description"[^>]*>/, () => description)
    : html.replace('</head>', () => `  ${description}\n</head>`);
  html = html.replace('</head>', () => `  ${head}\n</head>`);

  const content =
    `<div id="dg-seo" style="${BOX_STYLE}">${page.body}</div>\n` +
    `  <script>window.addEventListener('flutter-first-frame',function(){var e=document.getElementById('dg-seo');if(e)e.remove();});</script>`;
  return html.replace(/<body([^>]*)>/, (match) => `${match}\n  ${content}`);
}

// --- robots.txt and sitemap -------------------------------------------------

/** Only production is indexed; previews ask crawlers to stay away. */
export function robotsTxt(site: string, production: boolean): string {
  if (!production) return 'User-agent: *\nDisallow: /\n';
  return [
    'User-agent: *',
    'Allow: /',
    // Signed-in, admin and one-off pages: nothing to index.
    ...['/admin', '/api/', '/cart', '/checkout', '/login', '/reset-password', '/profile', '/orders', '/buscar'].map(
      (path) => `Disallow: ${path}`,
    ),
    '',
    `Sitemap: ${site}/sitemap.xml`,
    '',
  ].join('\n');
}

export function sitemapXml(site: string, categories: Category[], products: SeoProduct[]): string {
  const entry = (path: string, lastmod?: string) =>
    `  <url><loc>${escapeHtml(`${site}${path}`)}</loc>${lastmod ? `<lastmod>${lastmod.slice(0, 10)}</lastmod>` : ''}</url>`;
  const newest = products.map((p) => p.updated_at ?? '').sort().at(-1) || undefined;
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    entry('/', newest),
    ...visibleCategories(categories).map((c) => entry(categoryPath(c.slug))),
    ...products.map((p) => entry(productPath(p.slug), p.updated_at)),
    entry('/privacidad.html'),
    '</urlset>',
    '',
  ].join('\n');
}

// --- Serving ----------------------------------------------------------------

/** The site's public address: SITE_URL, or the address the request came to. */
export function siteUrl(request: Request): string {
  const configured = process.env.SITE_URL?.trim().replace(/\/+$/, '');
  return configured || new URL(request.url).origin;
}

let cachedShell: string | undefined;

/**
 * The built app page. `scripts/vercel-build.sh` publishes it as `app.html`
 * (not `index.html`, which Vercel would serve for `/` before any rewrite).
 * Read once per function instance: an instance belongs to one deployment.
 */
async function appShell(request: Request): Promise<string> {
  if (cachedShell) return cachedShell;
  const response = await fetch(new URL('/app.html', new URL(request.url).origin), {
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error(`app.html: ${response.status}`);
  cachedShell = await response.text();
  return cachedShell;
}

const PUBLIC_CACHE = 'public, max-age=0, s-maxage=300, stale-while-revalidate=86400';

function html(body: string, status: number, cache: string): Response {
  return new Response(body, {
    status,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': cache },
  });
}

/**
 * The app page for a shop URL, with [load]'s page in it. A missing product or
 * category gives a 404 page; if the catalog can't be read, the plain app page
 * (customers still get the shop).
 */
export async function pageResponse(request: Request, path: string, load: (site: string) => Promise<Page>): Promise<Response> {
  let shell: string;
  try {
    shell = await appShell(request);
  } catch (error) {
    console.error('SEO: could not read the app page', error);
    return new Response('Service unavailable', { status: 503, headers: { 'Retry-After': '5', 'Cache-Control': 'no-store' } });
  }
  const site = siteUrl(request);
  try {
    const page = await load(site);
    return html(renderPage(shell, page, site), page.status, PUBLIC_CACHE);
  } catch (error) {
    if (error instanceof HttpError && error.status === 404) {
      return html(renderPage(shell, notFoundPage(path), site), 404, 'public, max-age=0, s-maxage=60');
    }
    console.error('SEO: could not build', path, error);
    return html(shell, 200, 'no-store');
  }
}

export const loadHome = async (site: string) => {
  const [categories, products] = await Promise.all([listCategories(), listProducts({ sort: 'name' })]);
  return homePage(site, categories as Category[], products as unknown as SeoProduct[]);
};

export const loadCategory = (slug: string) => async (site: string) => {
  const [categories, products] = await Promise.all([listCategories(), listProducts({ category: slug, sort: 'price' })]);
  const category = (categories as Category[]).find((c) => c.slug === slug.toLowerCase());
  if (!category || !visibleCategories(categories as Category[]).includes(category)) {
    throw new HttpError(404, 'Category not found');
  }
  return categoryPage(site, category, categories as Category[], products as unknown as SeoProduct[]);
};

export const loadProduct = (slug: string) => async (site: string) => {
  const [product, categories] = await Promise.all([getProductBySlug(slug), listCategories()]);
  return productPage(site, product as unknown as SeoProduct, categories as Category[]);
};

export async function robotsResponse(request: Request): Promise<Response> {
  return new Response(robotsTxt(siteUrl(request), process.env.VERCEL_ENV === 'production'), {
    headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': PUBLIC_CACHE },
  });
}

export async function sitemapResponse(request: Request): Promise<Response> {
  const [categories, products] = await Promise.all([listCategories(), listProducts({ sort: 'name' })]);
  return new Response(sitemapXml(siteUrl(request), categories as Category[], products as unknown as SeoProduct[]), {
    headers: { 'Content-Type': 'application/xml; charset=utf-8', 'Cache-Control': PUBLIC_CACHE },
  });
}
