import { z } from 'zod';

import { badRequest } from '../http';
import { check, now, supabaseAdmin, unwrap, type DbClient } from '../supabase';
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
  discount_cents?: number;
  coupon_code?: string | null;
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

/** What a column needs to fill its cell for one order. */
type Row = { order: ExportOrder; pickup: boolean; address: Record<string, string>; items: ExportItem[] };

/**
 * Every column the file can have, in the default order. The admin picks
 * which ones go in the file and in what order ("Columnas del Excel"); the
 * keys are what is saved, so they must not change.
 */
export const EXPORT_COLUMNS = [
  { key: 'order_number', label: 'Pedido', cell: ({ order }: Row) => order.order_number },
  { key: 'created_at', label: 'Fecha', cell: ({ order }: Row) => formatDate(order.created_at) },
  { key: 'status', label: 'Estado', cell: ({ order }: Row) => STATUS_LABELS[order.status] ?? order.status },
  { key: 'paid', label: 'Pagado', cell: ({ order }: Row) => (order.paid_at ? 'Sí' : 'No') },
  { key: 'paid_at', label: 'Fecha de pago', cell: ({ order }: Row) => formatDate(order.paid_at) },
  { key: 'delivery', label: 'Entrega', cell: ({ pickup }: Row) => (pickup ? 'Recogida en tienda' : 'Envío') },
  { key: 'customer', label: 'Cliente', cell: ({ order }: Row) => order.shipping_name },
  { key: 'email', label: 'Email', cell: ({ order }: Row) => order.contact_email ?? '' },
  { key: 'phone', label: 'Teléfono', cell: ({ order }: Row) => order.shipping_phone ?? '' },
  {
    key: 'address',
    label: 'Dirección',
    cell: ({ address }: Row) => [address.line1, address.line2].filter(Boolean).join(', '),
  },
  { key: 'postal_code', label: 'Código postal', cell: ({ address }: Row) => address.postal_code ?? '' },
  { key: 'city', label: 'Ciudad', cell: ({ address }: Row) => address.city ?? '' },
  { key: 'province', label: 'Provincia', cell: ({ address }: Row) => address.province ?? '' },
  { key: 'items', label: 'Artículos', cell: ({ items }: Row) => itemsText(items) },
  {
    key: 'units',
    label: 'Unidades',
    cell: ({ items }: Row) => items.reduce((sum, item) => sum + item.quantity, 0),
  },
  { key: 'subtotal', label: 'Subtotal (€)', cell: ({ order }: Row) => formatEuros(order.subtotal_cents) },
  { key: 'shipping', label: 'Envío (€)', cell: ({ order }: Row) => formatEuros(order.shipping_cents) },
  { key: 'coupon', label: 'Cupón', cell: ({ order }: Row) => order.coupon_code ?? '' },
  { key: 'discount', label: 'Descuento (€)', cell: ({ order }: Row) => formatEuros(order.discount_cents ?? 0) },
  { key: 'total', label: 'Total (€)', cell: ({ order }: Row) => formatEuros(order.total_cents) },
  { key: 'customer_notes', label: 'Notas del cliente', cell: ({ order }: Row) => order.customer_notes ?? '' },
  { key: 'admin_notes', label: 'Notas internas', cell: ({ order }: Row) => order.admin_notes ?? '' },
] as const satisfies readonly { key: string; label: string; cell: (row: Row) => string | number }[];

export type ExportColumnKey = (typeof EXPORT_COLUMNS)[number]['key'];

export const DEFAULT_EXPORT_COLUMNS: ExportColumnKey[] = EXPORT_COLUMNS.map((column) => column.key);

const COLUMN_KEYS = DEFAULT_EXPORT_COLUMNS as [ExportColumnKey, ...ExportColumnKey[]];

/**
 * [keys] as a usable column list: unknown keys (e.g. a column removed from
 * the code) and repeats are dropped, and nothing left means every column.
 */
export function exportColumns(keys: readonly string[] | null | undefined): ExportColumnKey[] {
  const known = new Set<string>(DEFAULT_EXPORT_COLUMNS);
  const picked = [...new Set(keys ?? [])].filter((key): key is ExportColumnKey => known.has(key));
  return picked.length ? picked : DEFAULT_EXPORT_COLUMNS;
}

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

/** The CSV text (without BOM) for [orders], oldest first, with [columns] in that order. */
export function ordersCsv(orders: ExportOrder[], columns: readonly string[] = DEFAULT_EXPORT_COLUMNS): string {
  const byKey = new Map(EXPORT_COLUMNS.map((column) => [column.key as string, column]));
  const picked = exportColumns(columns).map((key) => byKey.get(key)!);
  const rows = [...orders]
    .sort((a, b) => a.created_at.localeCompare(b.created_at))
    .map((order) => {
      const pickup = order.delivery_method === 'pickup';
      const row: Row = {
        order,
        pickup,
        address: pickup ? {} : (order.shipping_address ?? {}),
        items: order.order_items ?? [],
      };
      return picked.map((column) => csvCell(column.cell(row))).join(';');
    });
  return [picked.map((column) => csvCell(column.label)).join(';'), ...rows].join('\r\n') + '\r\n';
}

// -----------------------------------------------------------------------------
// The admin's choice of columns (shop_settings.order_export_columns)
// -----------------------------------------------------------------------------

/** For the "Columnas del Excel" dialog: every column, and the ones in the file now. */
export type ExportColumnsSetting = {
  available: { key: ExportColumnKey; label: string }[];
  selected: ExportColumnKey[];
};

/** The saved columns; every column if none are saved (or the migration hasn't run yet). */
export async function getExportColumns(db: DbClient = supabaseAdmin()): Promise<ExportColumnKey[]> {
  const { data, error } = await db.from('shop_settings').select('order_export_columns').limit(1).maybeSingle();
  if (error) {
    console.warn('Could not read the export columns, using every column:', error.message);
    return DEFAULT_EXPORT_COLUMNS;
  }
  return exportColumns((data as { order_export_columns: string[] | null } | null)?.order_export_columns);
}

export async function exportColumnsSetting(): Promise<ExportColumnsSetting> {
  return {
    available: EXPORT_COLUMNS.map(({ key, label }) => ({ key, label })),
    selected: await getExportColumns(),
  };
}

export const exportColumnsSchema = z.object({
  columns: z
    .array(z.enum(COLUMN_KEYS))
    .min(1, 'Choose at least one column')
    .refine((keys) => new Set(keys).size === keys.length, 'A column is repeated'),
});

/** Saves the admin's columns. The default list is saved as NULL so columns added later show up. */
export async function saveExportColumns(columns: ExportColumnKey[]): Promise<ExportColumnsSetting> {
  const isDefault =
    columns.length === DEFAULT_EXPORT_COLUMNS.length && columns.every((key, i) => key === DEFAULT_EXPORT_COLUMNS[i]);
  const { error } = await supabaseAdmin()
    .from('shop_settings')
    .upsert({ id: true, order_export_columns: isDefault ? null : columns, updated_at: now() }, { onConflict: 'id' });
  check(error);
  return exportColumnsSetting();
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
        'order_number, status, created_at, paid_at, delivery_method, shipping_name, contact_email, shipping_phone, shipping_address, subtotal_cents, shipping_cents, coupon_code, discount_cents, total_cents, customer_notes, admin_notes, order_items(product_name, variant_name, quantity, customization, created_at)',
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
  const [orders, columns] = await Promise.all([monthOrders(month), getExportColumns()]);
  const csv = ordersCsv(orders, columns);
  return new Response(`﻿${csv}`, {
    headers: {
      ...headers,
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="pedidos-${month}.csv"`,
      'Cache-Control': 'no-store',
    },
  });
}
