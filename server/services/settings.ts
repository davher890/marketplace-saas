import { z } from 'zod';

import { db, type Db } from '../db';

export interface ShopSettings {
  shipping_flat_cents: number;
  free_shipping_threshold_cents: number | null;
  contact_email: string | null;
  contact_phone: string | null;
}

const defaults: ShopSettings = {
  shipping_flat_cents: 0,
  free_shipping_threshold_cents: null,
  contact_email: null,
  contact_phone: null,
};

export async function getSettings(sql: Db = db()): Promise<ShopSettings> {
  const [row] = await sql<ShopSettings[]>`
    select shipping_flat_cents, free_shipping_threshold_cents, contact_email, contact_phone
    from shop_settings
    limit 1
  `;
  return row ?? defaults;
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

export async function updateSettings(input: z.infer<typeof settingsSchema>): Promise<ShopSettings> {
  const sql = db();
  const values = {
    id: true,
    shipping_flat_cents: input.shipping_flat_cents,
    free_shipping_threshold_cents: input.free_shipping_threshold_cents,
    contact_email: input.contact_email || null,
    contact_phone: input.contact_phone || null,
  };
  await sql`
    insert into shop_settings ${sql(values)}
    on conflict (id) do update set
      shipping_flat_cents = excluded.shipping_flat_cents,
      free_shipping_threshold_cents = excluded.free_shipping_threshold_cents,
      contact_email = excluded.contact_email,
      contact_phone = excluded.contact_phone,
      updated_at = now()
  `;
  return getSettings();
}
