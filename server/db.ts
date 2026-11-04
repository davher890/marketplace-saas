import postgres from 'postgres';

import { HttpError } from './http';

type Types = { bigint: number };

/** Common interface of the pool and of a transaction, accepted by services. */
export type Db = postgres.ISql<Types>;

let pool: postgres.Sql<Types> | undefined;

/**
 * Shared Postgres connection pool.
 *
 * DATABASE_URL should be Supabase's *transaction pooler* connection string
 * (port 6543), which suits serverless functions. That pooler doesn't support
 * prepared statements, hence `prepare: false`.
 *
 * The API connects as the database owner, so Row Level Security does not apply:
 * every permission check happens in the services.
 */
export function db(): postgres.Sql<Types> {
  if (pool) return pool;

  const url = process.env.DATABASE_URL;
  if (!url) throw new HttpError(500, 'Server is missing DATABASE_URL');

  const created = postgres(url, {
    prepare: false,
    max: Number(process.env.DATABASE_POOL_SIZE ?? 5),
    idle_timeout: 20,
    connect_timeout: 10,
    ssl: process.env.DATABASE_SSL === 'disable' ? false : 'require',
    types: {
      // Return bigint columns (order_number, counts) as plain numbers.
      bigint: {
        to: 20,
        from: [20],
        serialize: (value: number) => String(value),
        parse: (raw: string) => Number(raw),
      },
    },
  });
  pool = created;
  return created;
}

/** Closes the pool (used by scripts and tests). */
export async function closeDb(): Promise<void> {
  await pool?.end({ timeout: 5 });
  pool = undefined;
}
