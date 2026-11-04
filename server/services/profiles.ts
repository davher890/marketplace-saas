import { z } from 'zod';

import type { AuthUser } from '../auth';
import { db } from '../db';

export interface Profile {
  id: string;
  email: string | null;
  full_name: string | null;
  phone: string | null;
  role: 'customer' | 'admin';
  is_admin: boolean;
}

/**
 * Returns the user's profile, creating it on first sign in
 * (replaces the old `on_auth_user_created` trigger).
 */
export async function getOrCreateProfile(user: AuthUser): Promise<Profile> {
  const sql = db();
  await sql`
    insert into profiles (id, full_name)
    values (${user.id}, ${user.fullName})
    on conflict (id) do nothing
  `;
  const [row] = await sql<Omit<Profile, 'email' | 'is_admin'>[]>`
    select id, full_name, phone, role from profiles where id = ${user.id}
  `;
  return { ...row, email: user.email, is_admin: row.role === 'admin' };
}

export const updateProfileSchema = z.object({
  full_name: z.string().trim().max(120).nullable().optional(),
  phone: z.string().trim().max(40).nullable().optional(),
});

/** Customers can edit their contact fields, never their role. */
export async function updateProfile(
  user: AuthUser,
  input: z.infer<typeof updateProfileSchema>,
): Promise<Profile> {
  await getOrCreateProfile(user);
  const changes: Record<string, string | null> = {};
  if (input.full_name !== undefined) changes.full_name = input.full_name || null;
  if (input.phone !== undefined) changes.phone = input.phone || null;

  if (Object.keys(changes).length > 0) {
    const sql = db();
    await sql`
      update profiles set ${sql(changes)}, updated_at = now()
      where id = ${user.id}
    `;
  }
  return getOrCreateProfile(user);
}
