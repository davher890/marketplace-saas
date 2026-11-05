-- =============================================================================
-- Seed data: category tree from the current Wix shop and a few sample products.
-- Safe to run on an empty database (`supabase db reset` runs it automatically).
-- =============================================================================

-- Top-level categories --------------------------------------------------------
insert into public.categories (name, slug, position) values
  ('Joyería',            'joyeria',          1),
  ('Complementos',       'complementos',     2),
  ('Ropa',               'ropa',             3),
  ('Decoración & Hogar', 'decoracion-hogar', 4),
  ('Eventos',            'eventos',          5),
  ('Regalos',            'regalos',          6);

-- Sub-categories --------------------------------------------------------------
insert into public.categories (parent_id, name, slug, position)
select parent.id, sub.name, sub.slug, sub.position
from (values
  ('joyeria',          'Anillos',              'anillos',              1),
  ('joyeria',          'Pulseras',             'pulseras',             2),
  ('joyeria',          'Joyas',                'joyas',                3),
  ('complementos',     'Llaveros',             'llaveros',             1),
  ('complementos',     'Bolsos',               'bolsos',               2),
  ('complementos',     'Marcapáginas',         'marcapaginas',         3),
  ('ropa',             'Ropa mayores',         'ropa-mayores',         1),
  ('ropa',             'Ropa peques',          'ropa-peques',          2),
  ('decoracion-hogar', 'Cuadros decorativos',  'cuadros-decorativos',  1),
  ('decoracion-hogar', 'Juguetes & Deco',      'juguetes-deco',        2),
  ('decoracion-hogar', 'Cojines & Textiles',   'cojines-textiles',     3),
  ('decoracion-hogar', 'Tazas con mensajes',   'tazas-mensajes',       4),
  ('eventos',          'Navidad',              'navidad',              1),
  ('eventos',          'Boda',                 'bodas',                2),
  ('eventos',          'Cumpleaños',           'cumpleanos',           3),
  ('eventos',          'Colegio & Guarde',     'colegio-guarde',       4),
  ('eventos',          'Recién nacido',        'recien-nacido',        5),
  ('regalos',          'Profes & Otros',       'profes-otros',         1),
  ('regalos',          'Cestas de bebés',      'cestas-bebes',         2),
  ('regalos',          'Mascotas',             'mascotas',             3)
) as sub(parent_slug, name, slug, position)
join public.categories parent on parent.slug = sub.parent_slug;

-- Sample products ---------------------------------------------------------------
with new_products as (
  insert into public.products (category_id, name, slug, description, base_price_cents, is_customizable, customization_label, is_featured)
  select c.id, p.name, p.slug, p.description, p.price, p.customizable, p.label, p.featured
  from (values
    ('ropa-peques', 'Conjunto frase/dibujo Superman', 'conjunto-superman',
     'Conjunto de camiseta para peque y adulto con frase o dibujo a juego.', 3000, false, null, true),
    ('ropa-peques', 'Conjunto camiseta culotte', 'conjunto-camiseta-culotte',
     'Conjunto de camiseta y culotte hecho a mano.', 3000, false, null, false),
    ('cojines-textiles', 'Cojín nube', 'cojin-nube',
     'Cojín de 30×50 cm aprox., diseñado y hecho a mano en España por Doña Galleta.', 1695, false, null, true),
    ('cojines-textiles', 'Cojín estrella', 'cojin-estrella',
     'Cojín de 40×40 cm, diseñado y hecho a mano en España por Doña Galleta.', 1695, false, null, false),
    ('recien-nacido', 'Chupetero personalizado', 'chupetero-personalizado',
     'Chupetero de tela con el nombre del bebé.', 1200, true, 'Nombre del bebé', true)
  ) as p(category_slug, name, slug, description, price, customizable, label, featured)
  join public.categories c on c.slug = p.category_slug
  returning id, slug
)
insert into public.product_variants (product_id, sku, name, options, stock, position)
select np.id, v.sku, v.name, v.options::jsonb, v.stock, v.position
from new_products np
join (values
  ('conjunto-superman',          'SUP-2Y',  '2 años', '{"Talla":"2 años"}', 3,    1),
  ('conjunto-superman',          'SUP-4Y',  '4 años', '{"Talla":"4 años"}', 2,    2),
  ('conjunto-superman',          'SUP-6Y',  '6 años', '{"Talla":"6 años"}', null, 3),
  ('conjunto-camiseta-culotte',  'CUL-1Y',  '12 meses', '{"Talla":"12 meses"}', null, 1),
  ('cojin-nube',                 'COJ-NUB', 'Default', '{}', 5, 1),
  ('cojin-estrella',             'COJ-EST', 'Default', '{}', 5, 1),
  ('chupetero-personalizado',    'CHU-ROS', 'Rosa',  '{"Color":"Rosa"}',  null, 1),
  ('chupetero-personalizado',    'CHU-AZU', 'Azul',  '{"Color":"Azul"}',  null, 2)
) as v(product_slug, sku, name, options, stock, position) on v.product_slug = np.slug;
