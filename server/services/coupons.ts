import { z } from 'zod';

import type { AuthUser } from '../auth';
import { HttpError, notFound } from '../http';
import { check, now, supabaseAdmin, unwrap, type DbClient } from '../supabase';

/**
 * Discount coupons (see migration …12_coupons.sql). Admins create them in
 * "Cupones"; customers type the code at checkout. The discount comes off the
 * final price (products + shipping) and is worked out here, never trusted
 * from the app.
 */

export const COUPON_USAGES = ['once_per_user', 'once_per_order'] as const;
export const DISCOUNT_TYPES = ['amount', 'percent', 'free_shipping'] as const;

export type Coupon = {
  id: string;
  code: string;
  description: string;
  starts_on: string;
  ends_on: string;
  usage: (typeof COUPON_USAGES)[number];
  discount_type: (typeof DISCOUNT_TYPES)[number];
  amount_cents: number | null;
  percent: number | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

/** 'active' can be used today; the others can't, for the reason they name. */
export type CouponStatus = 'active' | 'scheduled' | 'expired' | 'disabled';

const madridDay = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Madrid',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/** Today in Spain as "2026-11-24" (coupons run on Spain's calendar). */
export function madridToday(at: Date = new Date()): string {
  return madridDay.format(at);
}

export function couponStatus(coupon: Pick<Coupon, 'is_active' | 'starts_on' | 'ends_on'>, today: string): CouponStatus {
  if (!coupon.is_active) return 'disabled';
  if (today < coupon.starts_on) return 'scheduled';
  if (today > coupon.ends_on) return 'expired';
  return 'active';
}

/**
 * What [coupon] takes off an order of [subtotal] products and [shipping]:
 * never more than the final price, so the total never goes below 0.
 */
export function couponDiscount(
  coupon: Pick<Coupon, 'discount_type' | 'amount_cents' | 'percent'>,
  subtotal: number,
  shipping: number,
): number {
  const total = subtotal + shipping;
  switch (coupon.discount_type) {
    case 'amount':
      return Math.min(coupon.amount_cents ?? 0, total);
    case 'percent':
      return Math.min(Math.round((total * (coupon.percent ?? 0)) / 100), total);
    case 'free_shipping':
      return shipping;
  }
}

/** Codes are typed by customers: capitals, digits, "-" and "_", no spaces. */
export function normalizeCode(code: string): string {
  return code.trim().toUpperCase();
}

const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must look like 2026-11-24');

export const couponSchema = z
  .object({
    code: z
      .string()
      .transform(normalizeCode)
      .pipe(z.string().regex(/^[A-Z0-9_-]{3,30}$/, 'Code must be 3 to 30 letters, digits, "-" or "_"')),
    description: z.string().trim().max(300).default(''),
    starts_on: day,
    ends_on: day,
    usage: z.enum(COUPON_USAGES),
    discount_type: z.enum(DISCOUNT_TYPES),
    amount_cents: z.number().int().min(1).max(10_000_000).nullish(),
    percent: z.number().int().min(1).max(100).nullish(),
    is_active: z.boolean().default(true),
  })
  .superRefine((input, ctx) => {
    if (input.ends_on < input.starts_on) {
      ctx.addIssue({ code: 'custom', path: ['ends_on'], message: 'The end date is before the start date' });
    }
    if (input.discount_type === 'amount' && !input.amount_cents) {
      ctx.addIssue({ code: 'custom', path: ['amount_cents'], message: 'Amount is required' });
    }
    if (input.discount_type === 'percent' && !input.percent) {
      ctx.addIssue({ code: 'custom', path: ['percent'], message: 'Percent is required' });
    }
  })
  // Only the value that goes with the type is kept.
  .transform((input) => ({
    ...input,
    amount_cents: input.discount_type === 'amount' ? input.amount_cents! : null,
    percent: input.discount_type === 'percent' ? input.percent! : null,
  }));

export const patchCouponSchema = z.object({ is_active: z.boolean() });

// -----------------------------------------------------------------------------
// Admin (the routes check the admin role; written with the service-role client)
// -----------------------------------------------------------------------------

/** A coupon for the admin list: its status today and how many orders used it. */
export type AdminCoupon = Coupon & { status: CouponStatus; uses: number };

export async function listCoupons(db: DbClient = supabaseAdmin()): Promise<AdminCoupon[]> {
  const [coupons, used] = await Promise.all([
    db.from('coupons').select('*').order('created_at', { ascending: false }),
    db.from('orders').select('coupon_id').not('coupon_id', 'is', null).neq('status', 'cancelled'),
  ]);
  const uses = new Map<string, number>();
  for (const { coupon_id } of unwrap(used) as { coupon_id: string }[]) {
    uses.set(coupon_id, (uses.get(coupon_id) ?? 0) + 1);
  }
  const today = madridToday();
  return (unwrap(coupons) as Coupon[]).map((coupon) => ({
    ...coupon,
    status: couponStatus(coupon, today),
    uses: uses.get(coupon.id) ?? 0,
  }));
}

/** Postgres' unique violation on the code, in words the admin understands. */
function codeTaken(error: unknown): never {
  if ((error as { code?: string } | null)?.code === '23505') {
    throw new HttpError(409, 'There is already a coupon with that code', 'coupon_code_taken');
  }
  throw error;
}

async function withStatus(coupon: Coupon): Promise<AdminCoupon> {
  const { count, error } = await supabaseAdmin()
    .from('orders')
    .select('id', { count: 'exact', head: true })
    .eq('coupon_id', coupon.id)
    .neq('status', 'cancelled');
  check(error);
  return { ...coupon, status: couponStatus(coupon, madridToday()), uses: count ?? 0 };
}

export async function createCoupon(input: z.infer<typeof couponSchema>): Promise<AdminCoupon> {
  const { data, error } = await supabaseAdmin().from('coupons').insert(input).select('*').single();
  if (error) codeTaken(error);
  return withStatus(data as Coupon);
}

export async function updateCoupon(id: string, input: z.infer<typeof couponSchema>): Promise<AdminCoupon> {
  const { data, error } = await supabaseAdmin()
    .from('coupons')
    .update({ ...input, updated_at: now() })
    .eq('id', id)
    .select('*')
    .maybeSingle();
  if (error) codeTaken(error);
  if (!data) throw notFound('Coupon not found');
  return withStatus(data as Coupon);
}

export async function setCouponActive(id: string, isActive: boolean): Promise<AdminCoupon> {
  const updated = unwrap(
    await supabaseAdmin()
      .from('coupons')
      .update({ is_active: isActive, updated_at: now() })
      .eq('id', id)
      .select('*')
      .maybeSingle(),
  ) as Coupon | null;
  if (!updated) throw notFound('Coupon not found');
  return withStatus(updated);
}

// -----------------------------------------------------------------------------
// Checkout
// -----------------------------------------------------------------------------

/** What the app gets when the customer applies a code: enough to show the discount. */
export type PublicCoupon = Pick<Coupon, 'code' | 'description' | 'discount_type' | 'amount_cents' | 'percent'>;

export function publicCoupon(coupon: Coupon): PublicCoupon {
  const { code, description, discount_type, amount_cents, percent } = coupon;
  return { code, description, discount_type, amount_cents, percent };
}

const refused = (code: string, message: string) => new HttpError(409, message, code);

/**
 * The coupon behind [code] if [user] can use it today, or a 409 whose `code`
 * says why not (the app shows it in Spanish).
 */
export async function usableCoupon(user: AuthUser, code: string, today = madridToday()): Promise<Coupon> {
  const db = supabaseAdmin();
  const coupon = unwrap(
    await db.from('coupons').select('*').eq('code', normalizeCode(code)).maybeSingle(),
  ) as Coupon | null;
  if (!coupon) throw refused('coupon_not_found', 'Coupon not found');

  switch (couponStatus(coupon, today)) {
    case 'disabled':
      throw refused('coupon_inactive', 'This coupon is no longer available');
    case 'scheduled':
      throw refused('coupon_not_started', 'This coupon cannot be used yet');
    case 'expired':
      throw refused('coupon_expired', 'This coupon has expired');
  }

  if (coupon.usage === 'once_per_user') {
    const { count, error } = await db
      .from('orders')
      .select('id', { count: 'exact', head: true })
      .eq('coupon_id', coupon.id)
      .eq('user_id', user.id)
      .neq('status', 'cancelled');
    check(error);
    if ((count ?? 0) > 0) throw refused('coupon_already_used', 'You have already used this coupon');
  }
  return coupon;
}

/** The discount [coupon] gives this order, refusing coupons that give nothing (free shipping on pickup). */
export function orderDiscount(coupon: Coupon, subtotal: number, shipping: number): number {
  const discount = couponDiscount(coupon, subtotal, shipping);
  if (discount <= 0) throw refused('coupon_not_applicable', 'This coupon does not apply to this order');
  return discount;
}

export const applyCouponSchema = z.object({ code: z.string().trim().min(1).max(60) });
