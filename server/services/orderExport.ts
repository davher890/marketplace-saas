import { badRequest } from '../http';
import { supabaseAdmin, unwrap, type DbClient } from '../supabase';
import { monthKey } from './orderSummary';
import type { OrderStatus } from './orders';

/**
 * A month's orders as a CSV file for the admin "Resumen" page, one row per
 * order. Made for Excel in Spanish: `;` between columns, decimal commas,
 * dates in Spain's time zone and a UTF-8 BOM so accents show right.
 */

const STATUS_LABELS: Record<OrderStatus, string> = {
  received: 'Recibido',
  processing: 'En preparación',
  shipped: 'Enviado',
  delivered: 'Entregado',
  cancelled: 'Cancelado',
};

type ExportItem = {
  product_name: string;
  variant_name: string;
  quantity: number;
  customization: string;
  created_at: string;
};

export type ExportOrder = {
  order_number: number;
  status: OrderStatus;
  created_at: string;
  paid_at: string | null;
  delivery_method: string;
  shipping_name: string;
  contact_email: string | null;
  shipping_phone: string | null;
  shipping_address: Record<string, string> | null;
  subtotal_cents: number;
  shipping_cents: number;
  total_cents: number;
  customer_notes: string | null;
  admin_notes: string | null;
  order_items?: ExportItem[];
};

/** "2026-11", validated (any month from 2000 on). */
export function parseMonth(value: string | null): string {
  if (!value || !/^20\d{2}-(0[1-9]|1[0-2])$/.test(value)) throw badRequest('month must look like 2026-11');
  return value;
}

const dateFormat = new Intl.DateTimeFormat('es-ES', {
  timeZone: 'Europe/Madrid',
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

/** "21/11/2026 10:30", in Spain. */
export function formatDate(iso: string | null): string {
  return iso ? dateFormat.format(new Date(iso)).replace(',', '') : '';
}

/** 1250 -> "12,50": a number Excel in Spanish adds up. */
export function formatEuros(cents: number): string {
  return (cents / 100).toFixed(2).replace('.', ',');
}

/**
 * One CSV cell. Quoted when needed; text starting with = + - @ gets a
 * leading apostrophe so Excel doesn't run what a customer typed as a formula.
 */
export function csvCell(value: string | number): string {
  let text = String(value);
  if (typeof value === 'string' && /^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  return /[";\n\r]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

const HEADER = [
  'Pedido',
  'Fecha',
  'Estado',
  'Pagado',
  'Fecha de pago',
  'Entrega',
  'Cliente',
  'Email',
  'Teléfono',
  'Dirección',
  'Código postal',
  'Ciudad',
  'Provincia',
  'Artículos',
  'Unidades',
  'Subtotal (€)',
  'Envío (€)',
  'Total (€)',
  'Notas del cliente',
  'Notas internas',
];

function itemsText(items: ExportItem[]): string {
  return [...items]
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
    .map((item) => {
      const variant = item.variant_name && item.variant_name !== 'Default' ? ` · ${item.variant_name}` : '';
      const custom = item.customization.trim() ? ` (${item.customization.trim()})` : '';
      return `${item.quantity} × ${item.product_name}${variant}${custom}`;
    })
    .join(' | ');
}

/** The CSV text (without BOM) for [orders], oldest first. */
export function ordersCsv(orders: ExportOrder[]): string {
  const rows = [...orders]
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
    .map((order) => {
      const pickup = order.delivery_method === 'pickup';
      const address = pickup ? {} : (order.shipping_address ?? {});
      const items = order.order_items ?? [];
      return [
        order.order_number,
        formatDate(order.created_at),
        STATUS_LABELS[order.status] ?? order.status,
        order.paid_at ? 'Sí' : 'No',
        formatDate(order.paid_at),
        pickup ? 'Recogida en tienda' : 'Envío',
        order.shipping_name,
        order.contact_email ?? '',
        order.shipping_phone ?? '',
        [address.line1, address.line2].filter(Boolean).join(', '),
        address.postal_code ?? '',
        address.city ?? '',
        address.province ?? '',
        itemsText(items),
        items.reduce((sum, item) => sum + item.quantity, 0),
        formatEuros(order.subtotal_cents),
        formatEuros(order.shipping_cents),
        formatEuros(order.total_cents),
        order.customer_notes ?? '',
        order.admin_notes ?? '',
      ]
        .map(csvCell)
        .join(';');
    });
  return [HEADER.map(csvCell).join(';'), ...rows].join('\r\n') + '\r\n';
}

/** Orders placed in [month] (Spain's calendar), every status. */
export async function monthOrders(month: string, db: DbClient = supabaseAdmin()): Promise<ExportOrder[]> {
  const [year, number] = month.split('-').map(Number);
  // A day of margin each side covers the time zone; the exact month is
  // decided below in Spain's time.
  const from = new Date(Date.UTC(year, number - 1, 1) - 86_400_000).toISOString();
  const to = new Date(Date.UTC(year, number, 1) + 86_400_000).toISOString();
  const rows = unwrap(
    await db
      .from('orders')
      .select(
        'order_number, status, created_at, paid_at, delivery_method, shipping_name, contact_email, shipping_phone, shipping_address, subtotal_cents, shipping_cents, total_cents, customer_notes, admin_notes, order_items(product_name, variant_name, quantity, customization, created_at)',
      )
      .gte('created_at', from)
      .lt('created_at', to)
      .order('created_at')
      .limit(5000),
  ) as ExportOrder[];
  return rows.filter((order) => monthKey(new Date(order.created_at)) === month);
}

/** The CSV file as a download. */
export async function monthOrdersCsvResponse(month: string, headers: Record<string, string>): Promise<Response> {
  const csv = ordersCsv(await monthOrders(month));
  return new Response(`﻿${csv}`, {
    headers: {
      ...headers,
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="pedidos-${month}.csv"`,
      'Cache-Control': 'no-store',
    },
  });
}
