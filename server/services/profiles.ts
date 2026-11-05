import { z } from 'zod';

import type { AuthUser } from '../auth';
import { check, now, unwrap } from '../supabase';

export interface Profile {
  id: string;
  email: string | null;
  full_name: string | null;
  phone: string | null;
  role: 'customer' | 'admin';
  is_admin: boolean;
}

/**
 * Returns the user's profile, creating it on first sign in. Runs as the user,
 * so RLS only lets them create and read their own row.
 */
export async function getOrCreateProfile(user: AuthUser): Promise<Profile> {
  const { error } = await user.db
    .from('profiles')
    .upsert({ id: user.id, full_name: user.fullName }, { onConflict: 'id', ignoreDuplicates: true });
  check(error);

  const row = unwrap(
    await user.db.from('profiles').select('id, full_name, phone, role').eq('id', user.id).single(),
  ) as Omit<Profile, 'email' | 'is_admin'>;
  return { ...row, email: user.email, is_admin: row.role === 'admin' };
}

/** Digits, spaces, `+`, `-`, `(`, `)`, with 6 to 15 digits (same rule as the app). */
const phoneSchema = z
  .string()
  .trim()
  .max(40)
  .refine((phone) => {
    if (phone === '') return true; // Empty clears it.
    const digits = phone.replace(/\D/g, '').length;
    return /^\+?[0-9 ()-]+$/.test(phone) && digits >= 6 && digits <= 15;
  }, 'Invalid phone number');

/** The email is the account identity (Supabase Auth) and is not editable here. */
export const updateProfileSchema = z.object({
  full_name: z.string().trim().max(120).nullable().optional(),
  phone: phoneSchema.nullable().optional(),
});

/** Customers can edit their contact fields; the role column isn't writable for them. */
export async function updateProfile(
  user: AuthUser,
  input: z.infer<typeof updateProfileSchema>,
): Promise<Profile> {
  await getOrCreateProfile(user);

  const changes: Record<string, string | null> = {};
  if (input.full_name !== undefined) changes.full_name = input.full_name || null;
  if (input.phone !== undefined) changes.phone = input.phone || null;

  if (Object.keys(changes).length > 0) {
    const { error } = await user.db
      .from('profiles')
      .update({ ...changes, updated_at: now() })
      .eq('id', user.id);
    check(error);
  }
  return getOrCreateProfile(user);
}
