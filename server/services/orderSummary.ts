import { badRequest } from '../http';
import { supabaseAdmin, unwrap, type DbClient } from '../supabase';
import { ORDER_STATUSES, type OrderStatus } from './orders';

/**
 * Figures for the admin "Resumen" page. A small shop has a few thousand
 * orders at most, so the rows are read (only the columns needed) and added up
 * here; PostgREST can't group by.
 */

export const SUMMARY_PERIODS = ['month', 'quarter', 'year', 'all'] as const;
export type SummaryPeriod = (typeof SUMMARY_PERIODS)[number];

const PAGE = 1000;
const TIME_ZONE = 'Europe/Madrid';

type OrderRow = {
  id: string;
  status: OrderStatus;
  total_cents: number;
  delivery_method: string;
  paid_at: string | null;
  created_at: string;
};

/** Orders that count as sold: marked paid and not cancelled. */
const isSold = (order: OrderRow) => order.paid_at !== null && order.status !== 'cancelled';
type ItemRow = { order_id: string; product_name: string; quantity: number; line_total_cents: number };

export type MonthSummary = { month: string; orders: number; sold: number; cancelled: number; revenue_cents: number };

export type OrderSummary = {
  period: SummaryPeriod;
  /** Current number of orders in each status, whatever the period. */
  by_status: Record<OrderStatus, number>;
  /** Orders not cancelled and not paid yet, whatever the period. */
  unpaid: { orders: number; total_cents: number };
  /** Figures for the orders placed in the period. */
  totals: {
    orders: number;
    sold: number;
    delivered: number;
    cancelled: number;
    revenue_cents: number;
    average_cents: number;
    pickup: number;
    shipping: number;
  };
  /** Newest month first; months without orders are left out. */
  months: MonthSummary[];
  top_products: { name: string; quantity: number; revenue_cents: number }[];
};

export function parsePeriod(value: string | null): SummaryPeriod {
  if (value === null || value === '') return 'all';
  if (!(SUMMARY_PERIODS as readonly string[]).includes(value)) throw badRequest(`Unknown period "${value}"`);
  return value as SummaryPeriod;
}

const monthFormat = new Intl.DateTimeFormat('en-CA', { timeZone: TIME_ZONE, year: 'numeric', month: '2-digit' });

/** "2026-11": the month of [date] in Spain. */
export function monthKey(date: Date): string {
  const parts = monthFormat.formatToParts(date);
  const part = (type: string) => parts.find((p) => p.type === type)!.value;
  return `${part('year')}-${part('month')}`;
}

/** Earliest month key included in [period], or null for every month. */
export function firstMonthOf(period: SummaryPeriod, today: Date): string | null {
  const current = monthKey(today);
  const [year, month] = current.split('-').map(Number);
  switch (period) {
    case 'month':
      return current;
    case 'quarter': {
      // This month and the two before it.
      const index = year * 12 + (month - 1) - 2;
      return `${Math.floor(index / 12)}-${String((index % 12) + 1).padStart(2, '0')}`;
    }
    case 'year':
      return `${year}-01`;
    case 'all':
      return null;
  }
}

async function readAll<T>(fetchPage: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: unknown }>) {
  const rows: T[] = [];
  for (let from = 0; ; from += PAGE) {
    const page = unwrap(await fetchPage(from, from + PAGE - 1));
    rows.push(...page);
    if (page.length < PAGE) return rows;
  }
}

/** Adds up [orders] and their [items]. Pure, so it can be tested without a database. */
export function summarize(
  orders: OrderRow[],
  items: ItemRow[],
  period: SummaryPeriod,
  today: Date = new Date(),
): OrderSummary {
  const byStatus = Object.fromEntries(ORDER_STATUSES.map((s) => [s, 0])) as Record<OrderStatus, number>;
  const unpaid = { orders: 0, total_cents: 0 };
  for (const order of orders) {
    byStatus[order.status] += 1;
    if (order.status !== 'cancelled' && order.paid_at === null) {
      unpaid.orders += 1;
      unpaid.total_cents += order.total_cents;
    }
  }

  const first = firstMonthOf(period, today);
  const inPeriod = orders.filter((o) => first === null || monthKey(new Date(o.created_at)) >= first);

  const months = new Map<string, MonthSummary>();
  const totals = { orders: 0, sold: 0, delivered: 0, cancelled: 0, revenue_cents: 0, average_cents: 0, pickup: 0, shipping: 0 };
  const soldIds = new Set<string>();
  for (const order of inPeriod) {
    const key = monthKey(new Date(order.created_at));
    const month = months.get(key) ?? { month: key, orders: 0, sold: 0, cancelled: 0, revenue_cents: 0 };
    months.set(key, month);
    month.orders += 1;
    totals.orders += 1;
    if (order.status === 'cancelled') {
      month.cancelled += 1;
      totals.cancelled += 1;
      continue;
    }
    if (order.delivery_method === 'pickup') totals.pickup += 1;
    else totals.shipping += 1;
    if (order.status === 'delivered') totals.delivered += 1;
    if (isSold(order)) {
      soldIds.add(order.id);
      month.sold += 1;
      month.revenue_cents += order.total_cents;
      totals.sold += 1;
      totals.revenue_cents += order.total_cents;
    }
  }
  totals.average_cents = totals.sold === 0 ? 0 : Math.round(totals.revenue_cents / totals.sold);

  const products = new Map<string, { name: string; quantity: number; revenue_cents: number }>();
  for (const item of items) {
    if (!soldIds.has(item.order_id)) continue;
    const product = products.get(item.product_name) ?? { name: item.product_name, quantity: 0, revenue_cents: 0 };
    products.set(item.product_name, product);
    product.quantity += item.quantity;
    product.revenue_cents += item.line_total_cents;
  }

  return {
    period,
    by_status: byStatus,
    unpaid,
    totals,
    months: [...months.values()].sort((a, b) => b.month.localeCompare(a.month)),
    top_products: [...products.values()]
      .sort((a, b) => b.quantity - a.quantity || b.revenue_cents - a.revenue_cents || a.name.localeCompare(b.name))
      .slice(0, 5),
  };
}

export async function getOrderSummary(period: SummaryPeriod, db: DbClient = supabaseAdmin()): Promise<OrderSummary> {
  const [orders, items] = await Promise.all([
    readAll<OrderRow>((from, to) =>
      db
        .from('orders')
        .select('id, status, total_cents, delivery_method, paid_at, created_at')
        .order('created_at')
        .order('id')
        .range(from, to),
    ),
    readAll<ItemRow>((from, to) =>
      db
        .from('order_items')
        .select('order_id, product_name, quantity, line_total_cents')
        .order('id')
        .range(from, to),
    ),
  ]);
  return summarize(orders, items, period);
}
