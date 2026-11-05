import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Global Supabase client. Overridable in tests.
final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Emits on every sign in / sign out / token refresh.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

/// Currently signed-in user, or `null`.
final currentUserProvider = Provider<User?>((ref) {
  // Re-evaluate whenever the auth state changes.
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});
