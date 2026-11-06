import { isAuthError, type Session, type User } from '@supabase/supabase-js';
import { z } from 'zod';

import type { AuthUser } from '../auth';
import { badRequest, HttpError } from '../http';
import { supabaseAdmin, supabaseAuth } from '../supabase';

// Sign up, sign in, sessions and passwords. The app never talks to Supabase
// Auth directly: it calls these routes, keeps the session they return and
// sends its access token to the rest of the API (verified in auth.ts).
//
// Links in Supabase's emails (confirm account, recover password) go through
// Supabase and then to `redirect_to` with the new session in the URL
// fragment (`#access_token=...&refresh_token=...&type=...`), which the web
// app reads on start-up.

// -----------------------------------------------------------------------------
// Responses
// -----------------------------------------------------------------------------

export interface SessionJson {
  access_token: string;
  refresh_token: string;
  /** Unix time (seconds) when the access token expires. */
  expires_at: number;
  user: { id: string; email: string | null; full_name: string | null };
}

function userJson(user: User): SessionJson['user'] {
  const fullName = user.user_metadata?.full_name;
  return {
    id: user.id,
    email: user.email ?? null,
    full_name: typeof fullName === 'string' && fullName.trim() ? fullName.trim() : null,
  };
}

function sessionJson(session: Session): SessionJson {
  return {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at ?? Math.floor(Date.now() / 1000) + session.expires_in,
    user: userJson(session.user),
  };
}

/**
 * Supabase Auth errors keep their status and code (`invalid_credentials`,
 * `user_already_exists`, `over_request_rate_limit`...), so the app can show a
 * message in Spanish. Anything unexpected is rethrown as a server error.
 */
function authError(error: unknown): never {
  if (isAuthError(error)) {
    const status = error.status && error.status >= 400 && error.status < 500 ? error.status : 502;
    throw new HttpError(status, error.message, error.code ?? undefined);
  }
  throw error;
}

// -----------------------------------------------------------------------------
// Schemas
// -----------------------------------------------------------------------------

const email = z.email().max(254).transform((value) => value.trim().toLowerCase());
/** Supabase's default minimum; bcrypt ignores anything past 72 bytes. */
const newPassword = z.string().min(6, 'Password must have at least 6 characters').max(72);
/** Where Supabase's email links land; Supabase only accepts its allow-listed URLs. */
const redirectTo = z.url().max(500).optional();

export const signInSchema = z.object({ email, password: z.string().min(1).max(72) });

export const signUpSchema = z.object({
  email,
  password: newPassword,
  full_name: z.string().trim().max(120).optional(),
  redirect_to: redirectTo,
});

export const refreshSchema = z.object({ refresh_token: z.string().min(1).max(1000) });

export const recoverSchema = z.object({ email, redirect_to: redirectTo });

export const changePasswordSchema = z.object({
  password: newPassword,
  /** Required unless the session comes from a password recovery link. */
  current_password: z.string().min(1).max(72).optional(),
});

// -----------------------------------------------------------------------------
// Routes
// -----------------------------------------------------------------------------

export async function signIn(input: z.infer<typeof signInSchema>): Promise<SessionJson> {
  const { data, error } = await supabaseAuth().auth.signInWithPassword(input);
  if (error) authError(error);
  return sessionJson(data.session!);
}

/**
 * Creates the account. With email confirmation on (the default), there is no
 * session until the user opens the link, and `session` is null.
 */
export async function signUp(
  input: z.infer<typeof signUpSchema>,
): Promise<{ session: SessionJson | null; confirmation_required: boolean }> {
  const { data, error } = await supabaseAuth().auth.signUp({
    email: input.email,
    password: input.password,
    options: {
      data: input.full_name ? { full_name: input.full_name } : undefined,
      emailRedirectTo: input.redirect_to,
    },
  });
  if (error) authError(error);
  return {
    session: data.session ? sessionJson(data.session) : null,
    confirmation_required: !data.session,
  };
}

/** New access token for a refresh token (each refresh token works once). */
export async function refresh(input: z.infer<typeof refreshSchema>): Promise<SessionJson> {
  const { data, error } = await supabaseAuth().auth.refreshSession({ refresh_token: input.refresh_token });
  if (error) authError(error);
  if (!data.session) throw new HttpError(401, 'Session expired', 'session_expired');
  return sessionJson(data.session);
}

/** Ends this session on the server: its refresh token stops working. */
export async function signOut(accessToken: string): Promise<{ signed_out: true }> {
  const { error } = await supabaseAdmin().auth.admin.signOut(accessToken, 'local');
  // An already expired or revoked session is signed out anyway.
  if (error && !(isAuthError(error) && (error.status === 401 || error.status === 403 || error.status === 404))) {
    authError(error);
  }
  return { signed_out: true };
}

/**
 * Emails a link to choose a new password. Always answers the same way, so it
 * doesn't reveal which emails have an account.
 */
export async function recover(input: z.infer<typeof recoverSchema>): Promise<{ sent: true }> {
  const { error } = await supabaseAuth().auth.resetPasswordForEmail(input.email, {
    redirectTo: input.redirect_to,
  });
  // Rate limits are worth telling the user; other errors are not.
  if (error && isAuthError(error) && error.status === 429) authError(error);
  if (error) console.error('Password recovery email failed', error);
  return { sent: true };
}

/** Checks the password without leaving a new session behind. */
export async function verifyPassword(user: AuthUser, password: string): Promise<void> {
  if (!user.email) throw badRequest('This account has no email');
  const { data, error } = await supabaseAuth().auth.signInWithPassword({ email: user.email, password });
  if (error || !data.session) {
    throw new HttpError(400, 'The current password is not correct', 'wrong_password');
  }
  await supabaseAdmin().auth.admin.signOut(data.session.access_token, 'local');
}

/** How a session was started, from the access token's `amr` claim. */
function signInMethods(accessToken: string): { method: string; timestamp: number }[] {
  try {
    const payload = JSON.parse(Buffer.from(accessToken.split('.')[1], 'base64url').toString());
    return Array.isArray(payload.amr) ? payload.amr : [];
  } catch {
    return [];
  }
}

/** A session opened with an email link (recovery, magic link) in the last hour. */
function isRecentEmailLinkSession(accessToken: string): boolean {
  const hourAgo = Date.now() / 1000 - 3600;
  return signInMethods(accessToken).some(
    (entry) => ['recovery', 'otp', 'magiclink'].includes(entry.method) && entry.timestamp > hourAgo,
  );
}

/**
 * Sets a new password. Needs the current one, except right after opening a
 * password recovery link (that's how a forgotten password is replaced).
 *
 * Supabase ends every session of the user when the password changes (other
 * devices are signed out, which is what you want after a change), including
 * this one, so a new session is returned for the app to carry on with.
 */
export async function changePassword(
  user: AuthUser,
  accessToken: string,
  input: z.infer<typeof changePasswordSchema>,
): Promise<SessionJson> {
  if (input.current_password) {
    await verifyPassword(user, input.current_password);
  } else if (!isRecentEmailLinkSession(accessToken)) {
    throw new HttpError(400, 'The current password is required', 'current_password_required');
  }
  const { error } = await supabaseAdmin().auth.admin.updateUserById(user.id, { password: input.password });
  if (error) authError(error);
  return signIn({ email: user.email!, password: input.password });
}
