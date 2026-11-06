import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
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

/// Phone numbers accepted by the API: digits, spaces, `+`, `-`, `(`, `)`,
/// with 6 to 15 digits.
String? validatePhone(String? value) {
  final phone = value?.trim() ?? '';
  if (phone.isEmpty) return null; // Optional.
  final digits = phone.replaceAll(RegExp(r'\D'), '').length;
  if (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(phone) ||
      digits < 6 ||
      digits > 15) {
    return 'Teléfono no válido';
  }
  return null;
}

/// Where links in Supabase Auth emails (sign-up confirmation, password
/// recovery) should land. On the web it's this same site, so local and
/// deployed builds each get their own links; elsewhere `null` lets Supabase
/// use its Site URL (the deployed web app). The URL must be listed in
/// Supabase → Authentication → URL Configuration → Redirect URLs.
String? authRedirectUrl([String path = '']) =>
    kIsWeb ? '${Uri.base.origin}$path' : null;

/// Minimum length enforced by Supabase Auth by default.
const minPasswordLength = 6;

/// Profile and password changes, all through the API.
/// The email is the account identity and can't be changed from the app.
class ProfileRepository {
  ProfileRepository(this._api, this._auth);

  final ApiClient _api;
  final AuthController _auth;

  Future<Profile> updateProfile({String? fullName, String? phone}) async {
    final json = await _api.patch('/api/me', {
      'full_name': fullName,
      'phone': phone,
    });
    return Profile.fromJson(json as Map<String, dynamic>);
  }

  /// The API checks the current password before setting the new one, so an
  /// unattended signed-in device can't be used to take over the account.
  /// Other devices are signed out; this one gets a new session.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _setPassword({
    'current_password': currentPassword,
    'password': newPassword,
  });

  /// Deletes the account (the API checks the password), then forgets the
  /// session on this device. Orders are kept by the shop.
  Future<void> deleteAccount({required String password}) async {
    await _api.delete('/api/me', {'password': password});
    // The user no longer exists on the server: only clear the local session.
    await _auth.forget();
  }

  /// Sets a new password right after opening a password recovery link (the
  /// API allows it without the current one only then).
  Future<void> setNewPassword(String newPassword) =>
      _setPassword({'password': newPassword});

  Future<void> _setPassword(Map<String, String> body) async {
    final json = await _api.put('/api/auth/password', body);
    await _auth.adopt(AuthSession.fromJson(json as Map<String, dynamic>));
  }

  /// Emails a link to choose a new password. On the web it opens
  /// `/reset-password` of this same site; elsewhere Supabase's Site URL.
  Future<void> sendPasswordReset(String email) => _auth.recoverPassword(
    email,
    redirectTo: authRedirectUrl('/reset-password'),
  );
}

final profileRepositoryProvider = Provider(
  (ref) => ProfileRepository(
    ref.watch(apiClientProvider),
    ref.read(authProvider.notifier),
  ),
);
