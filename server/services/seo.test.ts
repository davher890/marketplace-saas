import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  categoryPage,
  escapeHtml,
  formatPrice,
  homePage,
  notFoundPage,
  productPage,
  renderPage,
  robotsTxt,
  sitemapXml,
  summary,
  type SeoProduct,
} from './seo';

const SITE = 'https://www.example.es';

const SHELL = `<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta name="description" content="Regalos personalizados hechos a mano">
  <title>Doña Galleta</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>`;

const categories = [
  { id: 'nav', parent_id: null, name: 'Navidad', slug: 'navidad', description: null, image_url: null },
  { id: 'bolas', parent_id: 'nav', name: 'Packs bolas', slug: 'packs-bolas', description: null, image_url: null },
  // Its parent is hidden (not in the list), so it isn't browsable.
  { id: 'orphan', parent_id: 'hidden', name: 'Huérfana', slug: 'huerfana', description: null, image_url: null },
];

const product = (over: Partial<SeoProduct> = {}): SeoProduct => ({
  name: 'Lápices con nombre',
  slug: 'lapices-con-nombre',
  description: 'Lapiceros de madera con el nombre de cada invitado.\n\nPerfectos para cumpleaños.',
  base_price_cents: 250,
  updated_at: '2026-11-20T10:00:00Z',
  category_ids: ['bolas'],
  product_variants: [],
  product_images: [{ position: 0, url: 'https://cdn.example/lapices.jpg', storage_path: 'a.jpg' }],
  ...over,
});

test('summary cuts long text at a word and keeps short text', () => {
  assert.equal(summary('  Hola\n mundo  '), 'Hola mundo');
  const long = summary('palabra '.repeat(40), 50);
  assert.ok(long.length <= 50);
  assert.ok(long.endsWith('palabra…'));
});

test('formatPrice uses Spanish format', () => {
  assert.equal(formatPrice(1250).replace(/\s/g, ' '), '12,50 €');
});

test('escapeHtml escapes markup', () => {
  assert.equal(escapeHtml(`<a href="x">'&'</a>`), '&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;');
});

test('product page: title, price, schema.org offer, breadcrumbs', () => {
  const page = productPage(SITE, product(), categories);
  assert.equal(page.title, 'Lápices con nombre · Doña Galleta');
  assert.equal(page.path, '/product/lapices-con-nombre');
  assert.equal(page.image, 'https://cdn.example/lapices.jpg');
  const [ld, crumbs] = page.jsonLd as any[];
  assert.equal(ld['@type'], 'Product');
  assert.deepEqual(ld.offers.price, '2.50');
  assert.equal(ld.offers.priceCurrency, 'EUR');
  assert.deepEqual(
    crumbs.itemListElement.map((i: any) => i.name),
    ['Doña Galleta', 'Packs bolas', 'Lápices con nombre'],
  );
  assert.match(page.body, /<h1>Lápices con nombre<\/h1>/);
  assert.match(page.body, /<p>Perfectos para cumpleaños\.<\/p>/);
});

test('product with variants at different prices: "Desde" and an AggregateOffer', () => {
  const page = productPage(
    SITE,
    product({
      product_variants: [
        { name: 'Pack 6', price_cents: 1200, is_active: true, position: 0 },
        { name: 'Pack 12', price_cents: 2000, is_active: true, position: 1 },
        { name: 'Agotado', price_cents: 100, is_active: false, position: 2 },
      ],
    }),
    categories,
  );
  const offers = (page.jsonLd as any[])[0].offers;
  assert.equal(offers['@type'], 'AggregateOffer');
  assert.equal(offers.lowPrice, '12.00');
  assert.equal(offers.highPrice, '20.00');
  assert.match(page.body, /Desde 12,00/);
  assert.match(page.body, /Pack 12/);
  assert.doesNotMatch(page.body, /Agotado/);
  assert.equal(page.meta?.['product:price:amount'], '12.00');
});

test('availability: out of stock only when every active variant has stock 0', () => {
  const variant = (stock: number | null, is_active = true) => ({ name: 'V', price_cents: 100, is_active, position: 0, stock });
  const availability = (variants: ReturnType<typeof variant>[]) =>
    ((productPage(SITE, product({ product_variants: variants }), categories).jsonLd as any[])[0].offers.availability as string);
  assert.equal(availability([variant(0), variant(0, false)]), 'https://schema.org/OutOfStock');
  assert.equal(availability([variant(0), variant(null)]), 'https://schema.org/InStock');
  assert.equal(availability([variant(0), variant(2)]), 'https://schema.org/InStock');
  assert.equal(availability([]), 'https://schema.org/InStock');
});

test('category page lists its products and sub-categories', () => {
  const page = categoryPage(SITE, categories[0], categories, [product()]);
  assert.equal(page.title, 'Navidad · Doña Galleta');
  assert.match(page.body, /href="\/c\/packs-bolas"/);
  assert.match(page.body, /href="\/product\/lapices-con-nombre"/);
  assert.match(page.description, /^Navidad en Doña Galleta, regalos personalizados hechos a mano: lápices con nombre\.$/);
});

test('home page links visible top categories only', () => {
  const page = homePage(SITE, categories, [product()]);
  assert.match(page.body, /href="\/c\/navidad"/);
  assert.doesNotMatch(page.body, /huerfana/);
});

test('renderPage replaces title and description and adds tags and content', () => {
  const html = renderPage(SHELL, productPage(SITE, product({ name: 'Taza </script><b>' }), categories), SITE);
  assert.equal(html.match(/<title>/g)?.length, 1);
  assert.match(html, /<title>Taza &lt;\/script&gt;&lt;b&gt; · Doña Galleta<\/title>/);
  assert.equal(html.match(/<meta name="description"/g)?.length, 1);
  assert.match(html, /<link rel="canonical" href="https:\/\/www\.example\.es\/product\/lapices-con-nombre">/);
  assert.match(html, /<meta property="og:image" content="https:\/\/cdn\.example\/lapices\.jpg">/);
  assert.match(html, /<meta property="og:type" content="product">/);
  // JSON-LD can't be closed by text inside it.
  assert.doesNotMatch(html, /"name":"Taza <\/script>/);
  assert.match(html, /\\u003c\/script>/);
  // Content before Flutter's script, removed on its first frame.
  assert.ok(html.indexOf('id="dg-seo"') < html.indexOf('flutter_bootstrap.js'));
  assert.match(html, /flutter-first-frame/);
  assert.doesNotMatch(html, /noindex/);
});

test('404 page is noindex', () => {
  const html = renderPage(SHELL, notFoundPage('/product/nope'), SITE);
  assert.match(html, /<meta name="robots" content="noindex">/);
  assert.match(html, /Página no encontrada/);
});

test('robots.txt: production lists the sitemap, previews block everything', () => {
  const production = robotsTxt(SITE, true);
  assert.match(production, /Disallow: \/admin/);
  assert.match(production, /Disallow: \/checkout/);
  assert.match(production, /Sitemap: https:\/\/www\.example\.es\/sitemap\.xml/);
  assert.equal(robotsTxt(SITE, false), 'User-agent: *\nDisallow: /\n');
});

test('sitemap lists home, visible categories and products', () => {
  const xml = sitemapXml(SITE, categories, [product()]);
  assert.match(xml, /<loc>https:\/\/www\.example\.es\/<\/loc><lastmod>2026-11-20<\/lastmod>/);
  assert.match(xml, /\/c\/navidad<\/loc>/);
  assert.match(xml, /\/c\/packs-bolas<\/loc>/);
  assert.doesNotMatch(xml, /huerfana/);
  assert.match(xml, /\/product\/lapices-con-nombre<\/loc><lastmod>2026-11-20<\/lastmod>/);
});
