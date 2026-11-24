import assert from 'node:assert/strict';
import { test } from 'node:test';

import { addItemSchema, lineCustomization, MAX_CUSTOMIZATION_LENGTH } from './cart';

const item = { variant_id: '6f1c2b1e-8f0a-4c4e-9b55-2d7f4f1f1a01' };

test('customization text: room for ten names, one per line', () => {
  const names = Array.from({ length: 10 }, (_, i) => `Nombre número ${i + 1}`).join('\n');
  const parsed = addItemSchema.parse({ ...item, customization: `  ${names}\n` });
  assert.equal(parsed.customization, names);
  const product = { is_customizable: true, choice_fields: [{ label: 'Color', options: ['Azul'] }] };
  assert.equal(lineCustomization(product, { customization: names, choices: { Color: 'Azul' } }), `Color: Azul · ${names}`);
});

test('customization text: refused over the limit', () => {
  assert.equal(addItemSchema.safeParse({ ...item, customization: 'a'.repeat(MAX_CUSTOMIZATION_LENGTH) }).success, true);
  assert.equal(addItemSchema.safeParse({ ...item, customization: 'a'.repeat(MAX_CUSTOMIZATION_LENGTH + 1) }).success, false);
});
