import { supabaseAdmin, unwrap } from '../supabase';
import { sendEmail } from './email';
import type { Order, OrderStatus } from './orders';
import { getSettings } from './settings';

// Emails about orders, in Spanish:
// - to the shop's mailbox (the contact email in the admin settings) and to
//   every admin, when an order is placed, besides the push notification;
// - to the email the customer gave in the order (`contact_email`), when they
//   place it and whenever its status changes.
// None of them throws: a failed email never fails the order or the change.
//
// SITE_URL (e.g. https://www.xn--doagalleta-u9a.es) adds links to the order.

interface OrderItem {
  product_name: string;
  variant_name: string;
  quantity: number;
  unit_price_cents: number;
  customization: string | null;
}

interface OrderDetails {
  id: string;
  order_number: number;
  contact_email: string | null;
  shipping_name: string;
  shipping_phone: string | null;
  shipping_address: {
    line1: string;
    line2?: string;
    city: string;
    postal_code: string;
    province?: string;
    country?: string;
  };
  customer_notes: string | null;
  subtotal_cents: number;
  shipping_cents: number;
  total_cents: number;
  order_items?: OrderItem[];
}

const euros = new Intl.NumberFormat('es-ES', { style: 'currency', currency: 'EUR' });
const money = (cents: number) => euros.format(cents / 100);

/** Customer-typed text goes into HTML: escape it. */
export function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function siteLink(path: string): string | null {
  const site = process.env.SITE_URL?.replace(/\/+$/, '');
  return site ? `${site}${path}` : null;
}

// -----------------------------------------------------------------------------
// Building blocks
// -----------------------------------------------------------------------------

function addressLines(order: OrderDetails): string[] {
  const a = order.shipping_address;
  return [
    order.shipping_name,
    a.line1,
    a.line2,
    [a.postal_code, a.city].filter(Boolean).join(' '),
    a.province,
    order.shipping_phone ? `Tel. ${order.shipping_phone}` : null,
  ].filter((line): line is string => Boolean(line && line.trim()));
}

function itemsHtml(order: OrderDetails): string {
  const rows = (order.order_items ?? [])
    .map((item) => {
      const variant = item.variant_name && item.variant_name !== 'Default' ? ` · ${escapeHtml(item.variant_name)}` : '';
      const custom = item.customization
        ? `<br><span style="color:#7a6a63">Personalización: ${escapeHtml(item.customization)}</span>`
        : '';
      return `<tr>
        <td style="padding:8px 0;border-bottom:1px solid #e6dcd8">${item.quantity} × ${escapeHtml(item.product_name)}${variant}${custom}</td>
        <td style="padding:8px 0;border-bottom:1px solid #e6dcd8;text-align:right;white-space:nowrap">${money(item.unit_price_cents * item.quantity)}</td>
      </tr>`;
    })
    .join('');
  const total = (label: string, cents: number, bold = false) =>
    `<tr><td style="padding:4px 0;${bold ? 'font-weight:bold' : ''}">${label}</td>
      <td style="padding:4px 0;text-align:right;${bold ? 'font-weight:bold' : ''}">${money(cents)}</td></tr>`;
  return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:16px 0">
    ${rows}
    ${total('Subtotal', order.subtotal_cents)}
    ${total(order.shipping_cents === 0 ? 'Envío (gratis)' : 'Envío', order.shipping_cents)}
    ${total('Total', order.total_cents, true)}
  </table>`;
}

function itemsText(order: OrderDetails): string {
  const lines = (order.order_items ?? []).map((item) => {
    const variant = item.variant_name && item.variant_name !== 'Default' ? ` (${item.variant_name})` : '';
    const custom = item.customization ? `\n    Personalización: ${item.customization}` : '';
    return `- ${item.quantity} × ${item.product_name}${variant}: ${money(item.unit_price_cents * item.quantity)}${custom}`;
  });
  return [
    ...lines,
    `Subtotal: ${money(order.subtotal_cents)}`,
    `Envío: ${order.shipping_cents === 0 ? 'gratis' : money(order.shipping_cents)}`,
    `Total: ${money(order.total_cents)}`,
  ].join('\n');
}

/** The shop's look: cream card on sage, forest headings. */
function layout(heading: string, bodyHtml: string, button?: { label: string; url: string | null }): string {
  const cta = button?.url
    ? `<p style="margin:24px 0 8px"><a href="${escapeHtml(button.url)}" style="background:#37453B;color:#EEE4E0;padding:12px 20px;border-radius:8px;text-decoration:none;display:inline-block">${escapeHtml(button.label)}</a></p>`
    : '';
  return `<!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body style="margin:0;background:#DCE5DF;font-family:Helvetica,Arial,sans-serif;color:#251E1B">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px">
      <tr><td style="background:#37453B;color:#EEE4E0;padding:18px 24px;border-radius:12px 12px 0 0;font-family:Georgia,serif;font-style:italic;font-size:26px">Doña Galleta</td></tr>
      <tr><td style="padding:24px;font-size:15px;line-height:1.5">
        <h1 style="font-size:20px;color:#37453B;margin:0 0 12px">${escapeHtml(heading)}</h1>
        ${bodyHtml}
        ${cta}
      </td></tr>
    </table>
    <p style="font-size:12px;color:#7a6a63;margin:16px 0 0">Doña Galleta · Regalos personalizados hechos a mano</p>
  </td></tr></table>
</body></html>`;
}

function paragraph(text: string): string {
  return `<p style="margin:0 0 12px">${text}</p>`;
}

// -----------------------------------------------------------------------------
// New order
// -----------------------------------------------------------------------------

/** Emails of the users with the admin role (from Supabase Auth). */
async function adminEmails(): Promise<string[]> {
  const db = supabaseAdmin();
  const admins = unwrap(await db.from('profiles').select('id').eq('role', 'admin')) as { id: string }[];
  const users = await Promise.all(admins.map((admin) => db.auth.admin.getUserById(admin.id)));
  return users.map((result) => result.data.user?.email).filter((email): email is string => Boolean(email));
}

/**
 * Who hears about a new order: the shop's mailbox (the contact email in the
 * admin settings, donagalletashop@gmail.com, or else the account that sends
 * the emails) and every admin. Each address once.
 */
export function newOrderRecipients(shopEmail: string | null | undefined, admins: string[]): string[] {
  const seen = new Set<string>();
  return [shopEmail, ...admins].filter((email): email is string => {
    const key = email?.trim().toLowerCase();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export function newOrderAdminEmail(order: OrderDetails) {
  const subject = `Nuevo pedido #${order.order_number} · ${order.shipping_name} · ${money(order.total_cents)}`;
  const contact = [order.contact_email, order.shipping_phone].filter(Boolean).map(escapeHtml).join(' · ');
  const html = layout(
    `Nuevo pedido #${order.order_number}`,
    paragraph(`<strong>${escapeHtml(order.shipping_name)}</strong>${contact ? `<br>${contact}` : ''}`) +
      itemsHtml(order) +
      paragraph(`<strong>Envío a</strong><br>${addressLines(order).map(escapeHtml).join('<br>')}`) +
      (order.customer_notes ? paragraph(`<strong>Notas del cliente</strong><br>${escapeHtml(order.customer_notes)}`) : ''),
    { label: 'Abrir en la administración', url: siteLink(`/admin/orders/${order.id}`) },
  );
  const text = [
    `Nuevo pedido #${order.order_number}`,
    `${order.shipping_name}${order.contact_email ? ` · ${order.contact_email}` : ''}${order.shipping_phone ? ` · ${order.shipping_phone}` : ''}`,
    '',
    itemsText(order),
    '',
    `Envío a:\n${addressLines(order).join('\n')}`,
    order.customer_notes ? `\nNotas del cliente:\n${order.customer_notes}` : '',
    siteLink(`/admin/orders/${order.id}`) ?? '',
  ].join('\n');
  return { subject, html, text };
}

export function orderReceivedEmail(order: OrderDetails) {
  const subject = `Hemos recibido tu pedido #${order.order_number}`;
  const html = layout(
    '¡Gracias por tu pedido!',
    paragraph(`Hola ${escapeHtml(order.shipping_name)},`) +
      paragraph(
        `Hemos recibido tu pedido <strong>#${order.order_number}</strong>. Te contactaremos para confirmar el pago y los detalles de la personalización.`,
      ) +
      itemsHtml(order) +
      paragraph(`<strong>Dirección de envío</strong><br>${addressLines(order).map(escapeHtml).join('<br>')}`) +
      paragraph('Si tienes cualquier duda, responde a este email.'),
    { label: 'Ver mi pedido', url: siteLink(`/orders/${order.id}`) },
  );
  const text = [
    `Hola ${order.shipping_name},`,
    '',
    `Hemos recibido tu pedido #${order.order_number}. Te contactaremos para confirmar el pago y los detalles de la personalización.`,
    '',
    itemsText(order),
    '',
    `Dirección de envío:\n${addressLines(order).join('\n')}`,
    '',
    'Si tienes cualquier duda, responde a este email.',
    siteLink(`/orders/${order.id}`) ?? '',
  ].join('\n');
  return { subject, html, text };
}

/**
 * Tells the shop and the admins (see [newOrderRecipients]) and the customer
 * about a new order. Awaited by the checkout route, so it finishes before
 * Vercel freezes the function.
 */
export async function sendNewOrderEmails(order: Order): Promise<void> {
  try {
    const details = order as unknown as OrderDetails;
    const settings = await getSettings();
    const shop = newOrderRecipients(settings.contact_email || process.env.SMTP_USER, await adminEmails());
    await Promise.all([
      shop.length > 0
        ? sendEmail({ to: shop, replyTo: details.contact_email ?? undefined, ...newOrderAdminEmail(details) })
        : Promise.resolve(false),
      details.contact_email
        ? sendEmail({
            to: details.contact_email,
            replyTo: settings.contact_email ?? undefined,
            ...orderReceivedEmail(details),
          })
        : Promise.resolve(false),
    ]);
  } catch (error) {
    console.error('Could not send the new order emails', error);
  }
}

// -----------------------------------------------------------------------------
// Status changes
// -----------------------------------------------------------------------------

const STATUS_COPY: Partial<Record<OrderStatus, { subject: string; heading: string; message: string }>> = {
  paid: {
    subject: 'Pago confirmado · pedido #{n}',
    heading: 'Hemos recibido tu pago',
    message: 'El pago de tu pedido <strong>#{n}</strong> está confirmado. En breve empezamos a prepararlo.',
  },
  processing: {
    subject: 'Estamos preparando tu pedido #{n}',
    heading: 'Tu pedido está en preparación',
    message: 'Estamos preparando tu pedido <strong>#{n}</strong> a mano, con mucho cariño.',
  },
  shipped: {
    subject: 'Tu pedido #{n} está en camino',
    heading: '¡Tu pedido está en camino!',
    message: 'Hemos enviado tu pedido <strong>#{n}</strong>. Pronto lo tendrás en casa.',
  },
  delivered: {
    subject: 'Tu pedido #{n} ha sido entregado',
    heading: 'Pedido entregado',
    message: 'Tu pedido <strong>#{n}</strong> figura como entregado. ¡Esperamos que te encante!',
  },
  cancelled: {
    subject: 'Pedido #{n} cancelado',
    heading: 'Tu pedido se ha cancelado',
    message: 'Tu pedido <strong>#{n}</strong> se ha cancelado. Si no esperabas este cambio o tienes cualquier duda, responde a este email.',
  },
};

/** Null for statuses customers aren't emailed about (e.g. back to pending). */
export function statusChangeEmail(order: OrderDetails, status: OrderStatus) {
  const copy = STATUS_COPY[status];
  if (!copy) return null;
  const fill = (template: string) => template.replace(/\{n\}/g, String(order.order_number));
  const html = layout(
    copy.heading,
    paragraph(`Hola ${escapeHtml(order.shipping_name)},`) + paragraph(fill(copy.message)) + itemsHtml(order),
    { label: 'Ver mi pedido', url: siteLink(`/orders/${order.id}`) },
  );
  const text = [
    `Hola ${order.shipping_name},`,
    '',
    fill(copy.message).replace(/<[^>]+>/g, ''),
    '',
    itemsText(order),
    siteLink(`/orders/${order.id}`) ?? '',
  ].join('\n');
  return { subject: fill(copy.subject), html, text };
}

/** Emails the customer the order's new status. */
export async function sendStatusChangeEmail(order: Order): Promise<void> {
  try {
    const details = order as unknown as OrderDetails;
    const email = statusChangeEmail(details, order.status);
    if (!email || !details.contact_email) return;
    const settings = await getSettings();
    await sendEmail({ to: details.contact_email, replyTo: settings.contact_email ?? undefined, ...email });
  } catch (error) {
    console.error('Could not send the status change email', error);
  }
}
