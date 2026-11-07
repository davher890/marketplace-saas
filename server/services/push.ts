import { createSign } from 'node:crypto';
import { z } from 'zod';

import type { AuthUser } from '../auth';
import { check, now, supabaseAdmin, unwrap } from '../supabase';

// Push notifications to Android devices through Firebase Cloud Messaging
// (HTTP v1 API). Every app install registers, signed in or not; new-order
// notices only go to admins' devices. Needs FIREBASE_SERVICE_ACCOUNT (the service account
// key JSON from Firebase → Project settings → Service accounts). Without it,
// nothing is sent and orders work as usual.

// -----------------------------------------------------------------------------
// Device registration
// -----------------------------------------------------------------------------

export const registerDeviceSchema = z.object({
  /** Firebase Installation ID, from the app's `onRegistered`. */
  fid: z.string().trim().min(10).max(256),
  platform: z.literal('android').default('android'),
});

/**
 * Saves the device, linked to whoever is signed in on it, or to nobody. An
 * FID identifies one app install, so registering it again moves it: to the
 * new user on a shared phone, or back to nobody after signing out (so it
 * stops getting a former admin's notices).
 */
export async function registerDevice(
  user: AuthUser | null,
  input: z.infer<typeof registerDeviceSchema>,
): Promise<{ registered: true }> {
  const { error } = await supabaseAdmin()
    .from('push_devices')
    .upsert(
      { fid: input.fid, user_id: user?.id ?? null, platform: input.platform, updated_at: now() },
      { onConflict: 'fid' },
    );
  check(error);
  return { registered: true };
}

// -----------------------------------------------------------------------------
// Firebase access token (OAuth 2 with a service account JWT, RFC 7523)
// -----------------------------------------------------------------------------

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function serviceAccount(): ServiceAccount | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) return null;
  const parsed = JSON.parse(raw) as Partial<ServiceAccount>;
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key');
  }
  return parsed as ServiceAccount;
}

const base64url = (value: string | Buffer) => Buffer.from(value).toString('base64url');

// Reused while the function instance stays warm (tokens last one hour).
let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(account: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;

  const issuedAt = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64url(
    JSON.stringify({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: issuedAt,
      exp: issuedAt + 3600,
    }),
  );
  const signature = createSign('RSA-SHA256').update(`${header}.${claims}`).sign(account.private_key);
  const assertion = `${header}.${claims}.${base64url(signature)}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!response.ok) throw new Error(`Firebase auth failed: ${response.status} ${await response.text()}`);
  const body = (await response.json()) as { access_token: string; expires_in: number };
  cachedToken = { value: body.access_token, expiresAt: Date.now() + body.expires_in * 1000 };
  return body.access_token;
}

// -----------------------------------------------------------------------------
// Sending
// -----------------------------------------------------------------------------

export interface PushMessage {
  title: string;
  body: string;
  /** Delivered to the app; string values only (FCM rule). */
  data: Record<string, string>;
}

/** FCM answers 404 UNREGISTERED (or 400 for a malformed target) for installs to forget. */
function isInvalidTarget(status: number, body: string): boolean {
  if (status === 404) return true;
  return status === 400 && /UNREGISTERED|installation|registration token/i.test(body);
}

/**
 * Sends the message to each app install, by Firebase Installation ID (FCM's
 * direct-send target, which replaces registration tokens). Returns the FIDs
 * FCM no longer accepts; other failures are logged and otherwise ignored.
 */
export async function sendToDevices(fids: string[], message: PushMessage): Promise<string[]> {
  const account = serviceAccount();
  if (!account || fids.length === 0) return [];

  const bearer = await accessToken(account);
  const url = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`;
  const invalid: string[] = [];

  await Promise.all(
    fids.map(async (fid) => {
      const response = await fetch(url, {
        method: 'POST',
        headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            fid,
            notification: { title: message.title, body: message.body },
            data: message.data,
            // "orders" is created by the app (MainActivity.kt).
            android: { priority: 'high', notification: { channel_id: 'orders' } },
          },
        }),
      });
      if (response.ok) return;
      const body = await response.text();
      if (isInvalidTarget(response.status, body)) invalid.push(fid);
      else console.error(`FCM send failed (${response.status}): ${body}`);
    }),
  );
  return invalid;
}

const euros = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR' });

interface NewOrder {
  id: string;
  shipping_name?: unknown;
  total_cents?: unknown;
  order_items?: { quantity: number }[];
}

/** "Ana López · 34,50 € · 3 artículos" */
export function newOrderMessage(order: NewOrder): PushMessage {
  const items = (order.order_items ?? []).reduce((sum, item) => sum + item.quantity, 0);
  const parts = [
    typeof order.shipping_name === 'string' ? order.shipping_name : null,
    typeof order.total_cents === 'number' ? euros.format(order.total_cents / 100) : null,
    items > 0 ? `${items} ${items === 1 ? 'artículo' : 'artículos'}` : null,
  ].filter(Boolean);
  return {
    title: 'Nuevo pedido',
    body: parts.join(' · '),
    data: { type: 'new_order', order_id: order.id },
  };
}

/**
 * Tells every admin device about a new order. Never throws: a failed
 * notification must not fail the checkout.
 */
export async function notifyAdminsOfOrder(order: NewOrder): Promise<void> {
  try {
    if (!process.env.FIREBASE_SERVICE_ACCOUNT) return;
    const db = supabaseAdmin();
    const admins = unwrap(await db.from('profiles').select('id').eq('role', 'admin')) as { id: string }[];
    if (admins.length === 0) return;

    const rows = unwrap(
      await db.from('push_devices').select('fid').in('user_id', admins.map((admin) => admin.id)),
    ) as { fid: string }[];
    const invalid = await sendToDevices(
      rows.map((row) => row.fid),
      newOrderMessage(order),
    );
    if (invalid.length > 0) check((await db.from('push_devices').delete().in('fid', invalid)).error);
  } catch (error) {
    console.error('Could not notify admins of the new order', error);
  }
}
