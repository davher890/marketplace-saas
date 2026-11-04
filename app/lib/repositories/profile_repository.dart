import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'api_client.dart';

/// The signed-in user's profile, as returned by `GET /api/me`.
class Profile {
  const Profile({
    required this.id,
    required this.isAdmin,
    this.email,
    this.fullName,
    this.phone,
  });

  final String id;
  final String? email;
  final String? fullName;
  final String? phone;
  final bool isAdmin;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    email: json['email'] as String?,
    fullName: json['full_name'] as String?,
    phone: json['phone'] as String?,
    isAdmin: json['is_admin'] as bool? ?? false,
  );
}

/// Loads (and on first sign in creates) the current user's profile.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final json = await ref.watch(apiClientProvider).get('/api/me');
  return Profile.fromJson(json as Map<String, dynamic>);
});

/// Whether the current user has the `admin` role.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  return profile?.isAdmin ?? false;
});
