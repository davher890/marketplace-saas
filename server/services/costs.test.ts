import assert from 'node:assert/strict';
import { test } from 'node:test';

import { boxPrice, computeOrderCosts, flattenCosts, supplierSchema, type ItemCost } from './costs';

const settings = { box_s_cents: 25, box_m_cents: 50, box_l_cents: 100 };

const cost = (over: Partial<ItemCost>): ItemCost => ({
  unit_cost_cents: 200,
  box_size: null,
  box_cents: 0,
  supplier_id: null,
  supplier_name: null,
  transport_cents: 0,
  ...over,
});

test('box prices by size; no box costs nothing', () => {
  assert.equal(boxPrice(settings, 'S'), 25);
  assert.equal(boxPrice(settings, 'M'), 50);
  assert.equal(boxPrice(settings, 'L'), 100);
  assert.equal(boxPrice(settings, null), 0);
});

test('line cost: units times cost plus one box per article', () => {
  const costs = computeOrderCosts(
    [{ id: 'a', quantity: 3 }],
    new Map([['a', cost({ unit_cost_cents: 200, box_size: 'M', box_cents: 50 })]]),
  );
  assert.equal(costs.items[0].line_cost_cents, 650); // 3 × 2,00 + 0,50
  assert.equal(costs.total_cost_cents, 650);
});

test("each supplier's transport counts once per order", () => {
  const costs = computeOrderCosts(
    [
      { id: 'a', quantity: 1 },
      { id: 'b', quantity: 2 },
      { id: 'c', quantity: 1 },
    ],
    new Map([
      ['a', cost({ supplier_id: 's1', supplier_name: 'Telas Ana', transport_cents: 300 })],
      ['b', cost({ supplier_id: 's1', supplier_name: 'Telas Ana', transport_cents: 300 })],
      ['c', cost({ supplier_id: 's2', supplier_name: 'Cajas Sur', transport_cents: 150 })],
    ]),
  );
  assert.equal(costs.items_cost_cents, 800); // 2,00 + 4,00 + 2,00
  assert.deepEqual(costs.suppliers, [
    { name: 'Telas Ana', transport_cents: 300 },
    { name: 'Cajas Sur', transport_cents: 150 },
  ]);
  assert.equal(costs.transport_cents, 450);
  assert.equal(costs.total_cost_cents, 1250);
});

test('a deleted supplier still counts once by its saved name', () => {
  const costs = computeOrderCosts(
    [
      { id: 'a', quantity: 1 },
      { id: 'b', quantity: 1 },
    ],
    new Map([
      ['a', cost({ supplier_name: 'Antiguo', transport_cents: 100 })],
      ['b', cost({ supplier_name: 'Antiguo', transport_cents: 100 })],
    ]),
  );
  assert.equal(costs.transport_cents, 100);
});

test('articles without a cost are flagged; estimated ones too', () => {
  const costs = computeOrderCosts(
    [
      { id: 'a', quantity: 2 },
      { id: 'b', quantity: 1 },
      { id: 'gone', quantity: 1 },
    ],
    new Map<string, ItemCost & { estimated?: boolean }>([
      ['a', cost({ unit_cost_cents: null, box_cents: 25 })],
      ['b', { ...cost({}), estimated: true }],
    ]),
  );
  assert.equal(costs.items[0].line_cost_cents, 25); // only the box
  assert.equal(costs.items[2].line_cost_cents, 0);
  assert.equal(costs.missing_costs, true);
  assert.equal(costs.estimated, true);
  assert.equal(costs.total_cost_cents, 225);
});

test('product costs come out of their embeds as plain fields', () => {
  const product = flattenCosts({
    id: 'p',
    product_costs: { cost_cents: 300, supplier_id: 's1', box_size: 'L' },
    product_variants: [
      { id: 'v1', variant_costs: { cost_cents: 350 } },
      { id: 'v2', variant_costs: null },
    ],
  });
  assert.equal(product.cost_cents, 300);
  assert.equal(product.supplier_id, 's1');
  assert.equal(product.box_size, 'L');
  assert.equal('product_costs' in product, false);
  const variants = product.product_variants as Record<string, unknown>[];
  assert.equal(variants[0].cost_cents, 350);
  assert.equal(variants[1].cost_cents, null);
  assert.equal('variant_costs' in variants[0], false);

  const bare = flattenCosts({ id: 'p', product_costs: [], product_variants: [] });
  assert.equal(bare.cost_cents, null);
  assert.equal(bare.box_size, null);
});

test('a supplier needs a name; transport in whole cents', () => {
  assert.deepEqual(supplierSchema.parse({ name: '  Telas Ana ', transport_cents: 300 }), {
    name: 'Telas Ana',
    transport_cents: 300,
  });
  assert.equal(supplierSchema.safeParse({ name: ' ', transport_cents: 300 }).success, false);
  assert.equal(supplierSchema.safeParse({ name: 'A', transport_cents: -1 }).success, false);
});

test('breakdown: units at product cost, at variant cost, boxes and transport', () => {
  const costs = computeOrderCosts(
    [
      { id: 'bola', quantity: 2 },
      { id: 'bolso', quantity: 1 },
    ],
    new Map<string, ItemCost & { from_variant?: boolean }>([
      ['bola', cost({ unit_cost_cents: 300, box_size: 'M', box_cents: 110, supplier_id: 'j', supplier_name: 'Jessi' })],
      [
        'bolso',
        {
          ...cost({
            unit_cost_cents: 4600,
            box_size: 'L',
            box_cents: 190,
            supplier_id: 'c',
            supplier_name: 'Carmen CL',
            transport_cents: 250,
          }),
          from_variant: true,
        },
      ],
    ]),
  );
  assert.equal(costs.products_cost_cents, 600);
  assert.equal(costs.variants_cost_cents, 4600);
  assert.equal(costs.boxes_cost_cents, 300);
  assert.equal(costs.transport_cents, 250);
  assert.equal(costs.total_cost_cents, 600 + 4600 + 300 + 250);
  assert.equal(costs.items_cost_cents + costs.transport_cents, costs.total_cost_cents);
});
