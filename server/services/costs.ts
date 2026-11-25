import { z } from 'zod';

import { badRequest, HttpError, notFound } from '../http';
import { check, now, supabaseAdmin, unwrap, type DbClient } from '../supabase';

/**
 * What products cost the shop, and what each order cost (see migration
 * …14_product_costs.sql). Admin only: every function here is called after the
 * route checked the admin role, and uses the service-role client.
 *
 *   line cost  = unit cost × quantity + one box
 *   order cost = line costs + each supplier's transport once
 *
 * A variant's own cost wins over the product's, like the price.
 */

export const BOX_SIZES = ['S', 'M', 'L'] as const;
export type BoxSize = (typeof BOX_SIZES)[number];

const cents = z.number().int().min(0).max(10_000_000);

// -----------------------------------------------------------------------------
// Box prices (Ajustes)
// -----------------------------------------------------------------------------

export type CostSettings = { box_s_cents: number; box_m_cents: number; box_l_cents: number };

/** Used until the row exists (the migration creates it with these values). */
const DEFAULT_COST_SETTINGS: CostSettings = { box_s_cents: 25, box_m_cents: 50, box_l_cents: 100 };

export function boxPrice(settings: CostSettings, size: BoxSize | null | undefined): number {
  switch (size) {
    case 'S':
      return settings.box_s_cents;
    case 'M':
      return settings.box_m_cents;
    case 'L':
      return settings.box_l_cents;
    default:
      return 0;
  }
}

export async function getCostSettings(db: DbClient = supabaseAdmin()): Promise<CostSettings> {
  const row = unwrap(
    await db.from('cost_settings').select('box_s_cents, box_m_cents, box_l_cents').limit(1).maybeSingle(),
  ) as CostSettings | null;
  return row ?? DEFAULT_COST_SETTINGS;
}

export const costSettingsSchema = z.object({ box_s_cents: cents, box_m_cents: cents, box_l_cents: cents });

export async function saveCostSettings(input: CostSettings): Promise<CostSettings> {
  check(
    (await supabaseAdmin().from('cost_settings').upsert({ id: true, ...input, updated_at: now() }, { onConflict: 'id' }))
      .error,
  );
  return getCostSettings();
}

// -----------------------------------------------------------------------------
// Suppliers (Ajustes)
// -----------------------------------------------------------------------------

export type Supplier = { id: string; name: string; transport_cents: number };

/** A supplier for the Ajustes list, with how many products it's set on. */
export type AdminSupplier = Supplier & { products: number };

export const supplierSchema = z.object({
  name: z.string().trim().min(1, 'Name is required').max(120),
  transport_cents: cents,
});

export async function listSuppliers(): Promise<AdminSupplier[]> {
  const db = supabaseAdmin();
  const [suppliers, used] = await Promise.all([
    db.from('suppliers').select('id, name, transport_cents').order('name'),
    db.from('product_costs').select('supplier_id').not('supplier_id', 'is', null),
  ]);
  const counts = new Map<string, number>();
  for (const { supplier_id } of unwrap(used) as { supplier_id: string }[]) {
    counts.set(supplier_id, (counts.get(supplier_id) ?? 0) + 1);
  }
  return (unwrap(suppliers) as Supplier[]).map((s) => ({ ...s, products: counts.get(s.id) ?? 0 }));
}

/** Postgres' unique violation on the name, in words the admin understands. */
function nameTaken(error: unknown): never {
  if ((error as { code?: string } | null)?.code === '23505') {
    throw new HttpError(409, 'There is already a supplier with that name', 'supplier_name_taken');
  }
  throw error;
}

export async function createSupplier(input: z.infer<typeof supplierSchema>): Promise<Supplier> {
  const { data, error } = await supabaseAdmin()
    .from('suppliers')
    .insert(input)
    .select('id, name, transport_cents')
    .single();
  if (error) nameTaken(error);
  return data as Supplier;
}

export async function updateSupplier(id: string, input: z.infer<typeof supplierSchema>): Promise<Supplier> {
  const { data, error } = await supabaseAdmin()
    .from('suppliers')
    .update({ ...input, updated_at: now() })
    .eq('id', id)
    .select('id, name, transport_cents')
    .maybeSingle();
  if (error) nameTaken(error);
  if (!data) throw notFound('Supplier not found');
  return data as Supplier;
}

/** Products that had it are left without a supplier; past orders keep its name. */
export async function deleteSupplier(id: string): Promise<void> {
  const deleted = unwrap(await supabaseAdmin().from('suppliers').delete().eq('id', id).select('id')) as unknown[];
  if (deleted.length === 0) throw notFound('Supplier not found');
}

// -----------------------------------------------------------------------------
// Product costs (product form)
// -----------------------------------------------------------------------------

/** The cost fields of the product form (sent along with the product). */
export const productCostFields = {
  cost_cents: cents.nullable().default(null),
  supplier_id: z.uuid().nullable().default(null),
  box_size: z.enum(BOX_SIZES).nullable().default(null),
};

export type ProductCosts = { cost_cents: number | null; supplier_id: string | null; box_size: BoxSize | null };

/** The embeds that bring a product's costs along with it (admin reads only). */
export const productCostsEmbed = 'product_costs(cost_cents, supplier_id, box_size)';
export const variantCostsEmbed = 'variant_costs(cost_cents)';

/** A one-to-one embed comes as an object, or as a list in older PostgREST. */
function single<T>(value: T | T[] | null | undefined): T | null {
  return (Array.isArray(value) ? value[0] : value) ?? null;
}

/**
 * Moves the embedded costs onto the product and its variants as plain fields
 * (`cost_cents`, `supplier_id`, `box_size`; `cost_cents` on each variant).
 */
export function flattenCosts<P extends Record<string, unknown>>(product: P): P & ProductCosts {
  const costs = single(product.product_costs as ProductCosts | ProductCosts[] | null);
  delete product.product_costs;
  Object.assign(product, {
    cost_cents: costs?.cost_cents ?? null,
    supplier_id: costs?.supplier_id ?? null,
    box_size: costs?.box_size ?? null,
  });
  for (const variant of (product.product_variants as Record<string, unknown>[] | undefined) ?? []) {
    const own = single(variant.variant_costs as { cost_cents: number } | { cost_cents: number }[] | null);
    delete variant.variant_costs;
    variant.cost_cents = own?.cost_cents ?? null;
  }
  return product as P & ProductCosts;
}

/** Saves the product's costs, and each variant's own cost (none = the product's). */
export async function saveProductCosts(
  productId: string,
  costs: ProductCosts,
  variantCosts: { variant_id: string; cost_cents: number | null }[],
): Promise<void> {
  const db = supabaseAdmin();
  const { error } = await db
    .from('product_costs')
    .upsert({ product_id: productId, ...costs, updated_at: now() }, { onConflict: 'product_id' });
  if ((error as { code?: string } | null)?.code === '23503') throw badRequest('Supplier not found');
  check(error);

  const withCost = variantCosts.filter((v) => v.cost_cents !== null);
  const withoutCost = variantCosts.filter((v) => v.cost_cents === null).map((v) => v.variant_id);
  if (withCost.length > 0) {
    check(
      (
        await db
          .from('variant_costs')
          .upsert(
            withCost.map((v) => ({ variant_id: v.variant_id, cost_cents: v.cost_cents, updated_at: now() })),
            { onConflict: 'variant_id' },
          )
      ).error,
    );
  }
  if (withoutCost.length > 0) {
    check((await db.from('variant_costs').delete().in('variant_id', withoutCost)).error);
  }
}

// -----------------------------------------------------------------------------
// Order costs
// -----------------------------------------------------------------------------

/** What one order line cost: per unit, its box, and its supplier's transport. */
export type ItemCost = {
  /** `null`: the product has no cost. */
  unit_cost_cents: number | null;
  box_size: BoxSize | null;
  box_cents: number;
  supplier_id: string | null;
  supplier_name: string | null;
  transport_cents: number;
};

type OrderLine = { id: string; product_id: string | null; variant_id: string | null; quantity: number };

/** What [lines] would cost with today's product costs, box prices and suppliers. */
export async function currentItemCosts(lines: Omit<OrderLine, 'quantity'>[]): Promise<Map<string, ItemCost>> {
  const db = supabaseAdmin();
  const productIds = [...new Set(lines.map((l) => l.product_id).filter((id): id is string => Boolean(id)))];
  const variantIds = [...new Set(lines.map((l) => l.variant_id).filter((id): id is string => Boolean(id)))];
  const [products, variants, settings] = await Promise.all([
    productIds.length
      ? db.from('product_costs').select('product_id, cost_cents, supplier_id, box_size').in('product_id', productIds)
      : Promise.resolve({ data: [], error: null }),
    variantIds.length
      ? db.from('variant_costs').select('variant_id, cost_cents').in('variant_id', variantIds)
      : Promise.resolve({ data: [], error: null }),
    getCostSettings(db),
  ]);
  const byProduct = new Map(
    (unwrap(products) as (ProductCosts & { product_id: string })[]).map((p) => [p.product_id, p]),
  );
  const byVariant = new Map(
    (unwrap(variants) as { variant_id: string; cost_cents: number }[]).map((v) => [v.variant_id, v.cost_cents]),
  );
  const supplierIds = [...new Set([...byProduct.values()].map((p) => p.supplier_id).filter(Boolean))] as string[];
  const suppliers = new Map(
    supplierIds.length
      ? (
          unwrap(await db.from('suppliers').select('id, name, transport_cents').in('id', supplierIds)) as Supplier[]
        ).map((s) => [s.id, s])
      : [],
  );

  const costs = new Map<string, ItemCost>();
  for (const line of lines) {
    const product = line.product_id ? byProduct.get(line.product_id) : undefined;
    const supplier = product?.supplier_id ? suppliers.get(product.supplier_id) : undefined;
    const variantCost = line.variant_id ? byVariant.get(line.variant_id) : undefined;
    costs.set(line.id, {
      unit_cost_cents: variantCost ?? product?.cost_cents ?? null,
      box_size: product?.box_size ?? null,
      box_cents: boxPrice(settings, product?.box_size),
      supplier_id: supplier?.id ?? null,
      supplier_name: supplier?.name ?? null,
      transport_cents: supplier?.transport_cents ?? 0,
    });
  }
  return costs;
}

/**
 * Saves what each line of a just-placed order costs, so later changes to the
 * product costs don't change it.
 */
export async function saveOrderCosts(orderId: string, lines: Omit<OrderLine, 'quantity'>[]): Promise<void> {
  if (lines.length === 0) return;
  const costs = await currentItemCosts(lines);
  check(
    (
      await supabaseAdmin()
        .from('order_item_costs')
        .upsert(
          lines.map((line) => ({ order_item_id: line.id, order_id: orderId, ...costs.get(line.id)! })),
          { onConflict: 'order_item_id' },
        )
    ).error,
  );
}

/**
 * A line's cost as used for an order: also whether it was worked out with
 * today's costs and whether its unit cost is the variant's own.
 */
type LineCost = ItemCost & { estimated?: boolean; from_variant?: boolean };

export type OrderItemCost = ItemCost & {
  order_item_id: string;
  quantity: number;
  /** Unit cost × quantity + box (the box alone when the product has no cost). */
  line_cost_cents: number;
  /** Worked out with today's costs: the order is older than the costs. */
  estimated: boolean;
  /** The unit cost is the variant's own, not the product's. */
  from_variant: boolean;
};

export type OrderCosts = {
  items: OrderItemCost[];
  /** Each supplier once, with its transport. */
  suppliers: { name: string; transport_cents: number }[];
  /** Units at the product's cost. */
  products_cost_cents: number;
  /** Units at a variant's own cost. */
  variants_cost_cents: number;
  /** One box per article. */
  boxes_cost_cents: number;
  /** Products, variants and boxes. */
  items_cost_cents: number;
  transport_cents: number;
  total_cost_cents: number;
  /** Some article has no cost, so the total falls short. */
  missing_costs: boolean;
  /** Some article was worked out with today's costs. */
  estimated: boolean;
};

/**
 * The cost of an order from its lines' costs: each line's units and box,
 * plus the transport of each supplier once, however many lines it has.
 */
export function computeOrderCosts(lines: Pick<OrderLine, 'id' | 'quantity'>[], costs: Map<string, LineCost>): OrderCosts {
  const items: OrderItemCost[] = [];
  const suppliers = new Map<string, { name: string; transport_cents: number }>();
  for (const line of lines) {
    const { estimated, from_variant, ...cost } = costs.get(line.id) ?? {
      unit_cost_cents: null,
      box_size: null,
      box_cents: 0,
      supplier_id: null,
      supplier_name: null,
      transport_cents: 0,
    };
    items.push({
      ...cost,
      order_item_id: line.id,
      quantity: line.quantity,
      line_cost_cents: (cost.unit_cost_cents ?? 0) * line.quantity + cost.box_cents,
      estimated: estimated ?? false,
      from_variant: from_variant ?? false,
    });
    const key = cost.supplier_id ?? (cost.supplier_name ? `name:${cost.supplier_name}` : null);
    if (key && !suppliers.has(key)) {
      suppliers.set(key, { name: cost.supplier_name ?? '', transport_cents: cost.transport_cents });
    }
  }
  const units = (fromVariant: boolean) =>
    items
      .filter((item) => item.from_variant === fromVariant)
      .reduce((sum, item) => sum + (item.unit_cost_cents ?? 0) * item.quantity, 0);
  const itemsCost = items.reduce((sum, item) => sum + item.line_cost_cents, 0);
  const transport = [...suppliers.values()].reduce((sum, s) => sum + s.transport_cents, 0);
  return {
    items,
    suppliers: [...suppliers.values()],
    products_cost_cents: units(false),
    variants_cost_cents: units(true),
    boxes_cost_cents: items.reduce((sum, item) => sum + item.box_cents, 0),
    items_cost_cents: itemsCost,
    transport_cents: transport,
    total_cost_cents: itemsCost + transport,
    missing_costs: items.some((item) => item.unit_cost_cents === null),
    estimated: items.some((item) => item.estimated),
  };
}

/** Splits [values] into groups of [size], to keep `in (...)` filters short. */
function chunks<T>(values: T[], size = 200): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

export type OrderWithLines = { id: string; order_items: (OrderLine & { created_at?: string })[] };

/**
 * The costs of several orders: what was saved when each was placed, today's
 * costs for older lines. A line's unit cost counts as the variant's when its
 * variant has a cost of its own.
 */
export async function costsForOrders(orders: OrderWithLines[]): Promise<Map<string, OrderCosts>> {
  const db = supabaseAdmin();
  const lines = orders.flatMap((order) => order.order_items);
  const costs = new Map<string, LineCost>();
  for (const ids of chunks(orders.map((order) => order.id))) {
    const saved = unwrap(
      await db
        .from('order_item_costs')
        .select('order_item_id, unit_cost_cents, box_size, box_cents, supplier_id, supplier_name, transport_cents')
        .in('order_id', ids),
    ) as (ItemCost & { order_item_id: string })[];
    for (const { order_item_id, ...cost } of saved) costs.set(order_item_id, cost);
  }
  const unsaved = lines.filter((line) => !costs.has(line.id));
  if (unsaved.length > 0) {
    for (const group of chunks(unsaved)) {
      for (const [id, cost] of await currentItemCosts(group)) costs.set(id, { ...cost, estimated: true });
    }
  }
  const variantIds = [...new Set(lines.map((l) => l.variant_id).filter((id): id is string => Boolean(id)))];
  const withOwnCost = new Set<string>();
  for (const ids of chunks(variantIds)) {
    const rows = unwrap(await db.from('variant_costs').select('variant_id').in('variant_id', ids)) as {
      variant_id: string;
    }[];
    for (const row of rows) withOwnCost.add(row.variant_id);
  }
  for (const line of lines) {
    const cost = costs.get(line.id);
    if (cost) cost.from_variant = line.variant_id !== null && withOwnCost.has(line.variant_id);
  }

  const result = new Map<string, OrderCosts>();
  for (const order of orders) {
    const sorted = [...order.order_items].sort((a, b) => (a.created_at ?? '').localeCompare(b.created_at ?? ''));
    result.set(order.id, computeOrderCosts(sorted, costs));
  }
  return result;
}

/** The costs of an order: those saved when it was placed, today's for older lines. */
export async function getOrderCosts(orderId: string): Promise<OrderCosts> {
  const order = unwrap(
    await supabaseAdmin()
      .from('orders')
      .select('id, order_items(id, product_id, variant_id, quantity, created_at)')
      .eq('id', orderId)
      .maybeSingle(),
  ) as OrderWithLines | null;
  if (!order) throw notFound('Order not found');
  return (await costsForOrders([order])).get(order.id)!;
}
