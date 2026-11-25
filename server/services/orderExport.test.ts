import assert from 'node:assert/strict';
import { test } from 'node:test';

import { DEFAULT_EXPORT_COLUMNS, exportColumns, exportColumnsSchema, ordersCsv, type ExportOrder } from './orderExport';

const order: ExportOrder = {
  order_number: 1004,
  status: 'received',
  created_at: '2026-11-21T09:30:00Z',
  paid_at: null,
  delivery_method: 'shipping',
  shipping_name: 'Lucía Pérez',
  contact_email: 'lucia@example.com',
  shipping_phone: '600000000',
  shipping_address: { line1: 'Calle Mayor 1', postal_code: '28013', city: 'Madrid', province: 'Madrid' },
  subtotal_cents: 2000,
  shipping_cents: 495,
  discount_cents: 0,
  coupon_code: null,
  total_cents: 2495,
  customer_notes: null,
  admin_notes: null,
  order_items: [
    { product_name: 'Bolas', variant_name: 'Default', quantity: 2, customization: 'Ana', created_at: '2026-11-21T09:30:00Z' },
  ],
};

const lines = (csv: string) => csv.trimEnd().split('\r\n');

test('every column by default, in the default order', () => {
  const [header, row] = lines(ordersCsv([order]));
  assert.equal(header.split(';').length, DEFAULT_EXPORT_COLUMNS.length);
  assert.ok(header.startsWith('Pedido;Fecha;Estado;'));
  assert.ok(row.startsWith('1004;21/11/2026 10:30;Recibido;'));
});

test('only the chosen columns, in the chosen order', () => {
  const [header, row] = lines(ordersCsv([order], ['total', 'customer', 'items', 'order_number']));
  assert.equal(header, 'Total (€);Cliente;Artículos;Pedido');
  assert.equal(row, '24,95;Lucía Pérez;2 × Bolas (Ana);1004');
});

test('unknown and repeated columns are dropped; nothing left means every column', () => {
  assert.deepEqual(exportColumns(['total', 'gone', 'total', 'email']), ['total', 'email']);
  assert.deepEqual(exportColumns(['gone']), DEFAULT_EXPORT_COLUMNS);
  assert.deepEqual(exportColumns(null), DEFAULT_EXPORT_COLUMNS);
});

test('the saved list needs at least one known column, without repeats', () => {
  assert.equal(exportColumnsSchema.safeParse({ columns: ['total', 'email'] }).success, true);
  assert.equal(exportColumnsSchema.safeParse({ columns: [] }).success, false);
  assert.equal(exportColumnsSchema.safeParse({ columns: ['total', 'total'] }).success, false);
  assert.equal(exportColumnsSchema.safeParse({ columns: ['nope'] }).success, false);
});

test('cost columns: the breakdown in euros, blank when not worked out', () => {
  const columns = ['order_number', 'cost_products', 'cost_variants', 'cost_transport', 'cost_boxes', 'cost_total'];
  const withCosts: ExportOrder = {
    ...order,
    costs: {
      items: [],
      suppliers: [],
      products_cost_cents: 600,
      variants_cost_cents: 4600,
      boxes_cost_cents: 300,
      items_cost_cents: 5500,
      transport_cents: 250,
      total_cost_cents: 5750,
      missing_costs: false,
      estimated: false,
    },
  };
  const [header, row] = lines(ordersCsv([withCosts], columns));
  assert.equal(header, 'Pedido;Coste productos (€);Coste variantes (€);Transporte proveedores (€);Cajas (€);Coste total (€)');
  assert.equal(row, '1004;6,00;46,00;2,50;3,00;57,50');
  assert.equal(lines(ordersCsv([order], columns))[1], '1004;;;;;');
});
