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

/// Whether the current user has the `admin` role in `public.profiles`.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final row = await ref
      .watch(supabaseProvider)
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();
  return row?['role'] == 'admin';
});
