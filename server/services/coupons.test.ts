import assert from 'node:assert/strict';
import { test } from 'node:test';

import { couponDiscount, couponSchema, couponStatus, madridToday } from './coupons';

test('amount off the final price, never below 0', () => {
  const coupon = { discount_type: 'amount', amount_cents: 500, percent: null } as const;
  assert.equal(couponDiscount(coupon, 2000, 600), 500);
  assert.equal(couponDiscount(coupon, 300, 100), 400);
});

test('percent off the final price (products and shipping), rounded to the cent', () => {
  const coupon = { discount_type: 'percent', amount_cents: null, percent: 10 } as const;
  assert.equal(couponDiscount(coupon, 2000, 600), 260);
  assert.equal(couponDiscount(coupon, 1995, 0), 200); // 199.5 -> 200
  assert.equal(couponDiscount({ ...coupon, percent: 100 }, 2000, 600), 2600);
});

test('free shipping takes off the shipping, nothing on pickup', () => {
  const coupon = { discount_type: 'free_shipping', amount_cents: null, percent: null } as const;
  assert.equal(couponDiscount(coupon, 2000, 600), 600);
  assert.equal(couponDiscount(coupon, 2000, 0), 0);
});

test('status: dates included, switched off wins', () => {
  const coupon = { is_active: true, starts_on: '2026-12-01', ends_on: '2026-12-31' };
  assert.equal(couponStatus(coupon, '2026-11-30'), 'scheduled');
  assert.equal(couponStatus(coupon, '2026-12-01'), 'active');
  assert.equal(couponStatus(coupon, '2026-12-31'), 'active');
  assert.equal(couponStatus(coupon, '2027-01-01'), 'expired');
  assert.equal(couponStatus({ ...coupon, is_active: false }, '2026-12-15'), 'disabled');
});

test("today is Spain's day, not UTC's", () => {
  // 23:30 UTC on 31 December is already 1 January in Madrid.
  assert.equal(madridToday(new Date('2026-12-31T23:30:00Z')), '2027-01-01');
});

const valid = {
  code: ' navidad-10 ',
  description: 'Navidad',
  starts_on: '2026-12-01',
  ends_on: '2026-12-31',
  usage: 'once_per_user',
  discount_type: 'percent',
  percent: 10,
  amount_cents: 999,
};

test('schema: code in capitals, only the value that goes with the type', () => {
  const parsed = couponSchema.parse(valid);
  assert.equal(parsed.code, 'NAVIDAD-10');
  assert.equal(parsed.percent, 10);
  assert.equal(parsed.amount_cents, null);
  assert.equal(parsed.is_active, true);
  const free = couponSchema.parse({ ...valid, discount_type: 'free_shipping' });
  assert.equal(free.percent, null);
  assert.equal(free.amount_cents, null);
});

test('schema refuses bad codes, reversed dates and missing values', () => {
  assert.equal(couponSchema.safeParse({ ...valid, code: 'NA' }).success, false);
  assert.equal(couponSchema.safeParse({ ...valid, code: 'CON ESPACIO' }).success, false);
  assert.equal(couponSchema.safeParse({ ...valid, ends_on: '2026-11-30' }).success, false);
  assert.equal(couponSchema.safeParse({ ...valid, percent: null }).success, false);
  assert.equal(couponSchema.safeParse({ ...valid, percent: 101 }).success, false);
  assert.equal(couponSchema.safeParse({ ...valid, discount_type: 'amount', amount_cents: null }).success, false);
});
