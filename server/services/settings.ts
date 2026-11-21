import { z } from 'zod';

import { check, now, supabase, supabaseAdmin } from '../supabase';

export interface ShopSettings {
  /** Shipping anywhere outside Madrid (and to Madrid when there's no Madrid rate). */
  shipping_flat_cents: number;
  /** Shipping to Madrid postal codes (28xxx); `null` = the normal rate. */
  shipping_madrid_cents: number | null;
  free_shipping_threshold_cents: number | null;
  contact_email: string | null;
  contact_phone: string | null;
  /** Customers see "Pagar ahora" (Stripe); while false only admins do. */
  online_payment_public: boolean;
}

const columns =
  'shipping_flat_cents, shipping_madrid_cents, free_shipping_threshold_cents, contact_email, contact_phone, online_payment_public';

const defaults: ShopSettings = {
  shipping_flat_cents: 0,
  shipping_madrid_cents: null,
  free_shipping_threshold_cents: null,
  contact_email: null,
  contact_phone: null,
  online_payment_public: false,
};

/** Public settings (readable by anyone through RLS). */
export async function getSettings(): Promise<ShopSettings> {
  const { data, error } = await supabase().from('shop_settings').select(columns).limit(1).maybeSingle();
  check(error);
  return (data as ShopSettings | null) ?? defaults;
}

export const DELIVERY_METHODS = ['shipping', 'pickup'] as const;
export type DeliveryMethod = (typeof DELIVERY_METHODS)[number];

/**
 * Spanish postal code: five digits, the first two the province (01-52),
 * e.g. 28010. Spaces are ignored.
 */
export function isSpanishPostalCode(postalCode: string | null | undefined): boolean {
  return /^(0[1-9]|[1-4]\d|5[0-2])\d{3}$/.test((postalCode ?? '').replace(/\s/g, ''));
}

/** Spanish postal codes of the Madrid province start with 28 (28001-28999). */
export function isMadridPostalCode(postalCode: string | null | undefined): boolean {
  return /^28\d{3}$/.test((postalCode ?? '').replace(/\s/g, ''));
}

/**
 * Shipping cost of an order: free when picked up in the shop or above the
 * free-shipping threshold; otherwise the Madrid rate for 28xxx postal codes
 * (when set) or the normal rate. Without a postal code (the cart, before
 * checkout) it's the normal rate.
 */
export function shippingFor(
  settings: ShopSettings,
  subtotalCents: number,
  delivery: { method: DeliveryMethod; postalCode?: string | null } = { method: 'shipping' },
): number {
  if (delivery.method === 'pickup') return 0;
  const threshold = settings.free_shipping_threshold_cents;
  if (threshold !== null && subtotalCents >= threshold) return 0;
  if (settings.shipping_madrid_cents !== null && isMadridPostalCode(delivery.postalCode)) {
    return settings.shipping_madrid_cents;
  }
  return settings.shipping_flat_cents;
}

const cents = z.number().int().min(0).max(10_000_000);

export const settingsSchema = z.object({
  shipping_flat_cents: cents,
  /** Optional so older admin apps that don't send it keep the stored value. */
  shipping_madrid_cents: cents.nullable().optional(),
  free_shipping_threshold_cents: cents.nullable(),
  contact_email: z.string().trim().max(200).nullable(),
  contact_phone: z.string().trim().max(40).nullable(),
  /** Optional so older admin apps that don't send it keep the stored value. */
  online_payment_public: z.boolean().optional(),
});

/** Admin only (checked by the route); written with the service-role client. */
export async function updateSettings(input: z.infer<typeof settingsSchema>): Promise<ShopSettings> {
  const { error } = await supabaseAdmin()
    .from('shop_settings')
    .upsert(
      {
        id: true,
        shipping_flat_cents: input.shipping_flat_cents,
        ...(input.shipping_madrid_cents !== undefined && { shipping_madrid_cents: input.shipping_madrid_cents }),
        free_shipping_threshold_cents: input.free_shipping_threshold_cents,
        contact_email: input.contact_email || null,
        contact_phone: input.contact_phone || null,
        ...(input.online_payment_public !== undefined && { online_payment_public: input.online_payment_public }),
        updated_at: now(),
      },
      { onConflict: 'id' },
    );
  check(error);
  return getSettings();
}
