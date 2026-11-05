import { z } from 'zod';

import { check, now, supabase, supabaseAdmin } from '../supabase';

export interface ShopSettings {
  shipping_flat_cents: number;
  free_shipping_threshold_cents: number | null;
  contact_email: string | null;
  contact_phone: string | null;
}

const columns = 'shipping_flat_cents, free_shipping_threshold_cents, contact_email, contact_phone';

const defaults: ShopSettings = {
  shipping_flat_cents: 0,
  free_shipping_threshold_cents: null,
  contact_email: null,
  contact_phone: null,
};

/** Public settings (readable by anyone through RLS). */
export async function getSettings(): Promise<ShopSettings> {
  const { data, error } = await supabase().from('shop_settings').select(columns).limit(1).maybeSingle();
  check(error);
  return (data as ShopSettings | null) ?? defaults;
}

/** Shipping cost for a subtotal: free above the threshold, flat rate otherwise. */
export function shippingFor(settings: ShopSettings, subtotalCents: number): number {
  const threshold = settings.free_shipping_threshold_cents;
  if (threshold !== null && subtotalCents >= threshold) return 0;
  return settings.shipping_flat_cents;
}

const cents = z.number().int().min(0).max(10_000_000);

export const settingsSchema = z.object({
  shipping_flat_cents: cents,
  free_shipping_threshold_cents: cents.nullable(),
  contact_email: z.string().trim().max(200).nullable(),
  contact_phone: z.string().trim().max(40).nullable(),
});

/** Admin only (checked by the route); written with the service-role client. */
export async function updateSettings(input: z.infer<typeof settingsSchema>): Promise<ShopSettings> {
  const { error } = await supabaseAdmin()
    .from('shop_settings')
    .upsert(
      {
        id: true,
        shipping_flat_cents: input.shipping_flat_cents,
        free_shipping_threshold_cents: input.free_shipping_threshold_cents,
        contact_email: input.contact_email || null,
        contact_phone: input.contact_phone || null,
        updated_at: now(),
      },
      { onConflict: 'id' },
    );
  check(error);
  return getSettings();
}
