import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../repositories/api_client.dart';

// Sign in, sign up and the session, all through the API (`/api/auth/*`): the
// app never talks to Supabase Auth itself. The session (access + refresh
// token) is kept in secure storage; the access token is renewed shortly
// before it expires, or after the API answers 401.

/// The signed-in user, as far as the session knows (the profile with phone
/// and role comes from `GET /api/me`).
@immutable
class AuthUser {
  const AuthUser({required this.id, this.email, this.fullName});

  final String id;
  final String? email;

  /// Name given at sign up.
  final String? fullName;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String?,
    fullName: json['full_name'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
  };

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.fullName == fullName;

  @override
  int get hashCode => Object.hash(id, email, fullName);
}

@immutable
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AuthUser user;

  /// Renewed a minute early so a request never leaves with a dying token.
  bool get expiresSoon =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  /// As returned by `/api/auth/login`, `/signup` and `/refresh`.
  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(
      (json['expires_at'] as num).toInt() * 1000,
    ),
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
    'user': user.toJson(),
  };
}

/// What an email link (confirm account, recover password) brought back.
///
/// Supabase sends the user to `redirect_to` with the result in the URL
/// fragment: `#access_token=...&refresh_token=...&expires_at=...&type=recovery`
/// or `#error=...&error_description=...`. Only the web app opens these links.
@immutable
class AuthLink {
  const AuthLink({this.type, this.session, this.error});

  /// `signup`, `recovery`, `magiclink`...
  final String? type;
  final AuthSession? session;

  /// Set when the link was invalid or had expired.
  final String? error;

  bool get isRecovery => type == 'recovery';

  /// Null when the URL isn't the result of an email link.
  static AuthLink? fromUrl(Uri url) {
    if (url.fragment.isEmpty) return null;
    final Map<String, String> params;
    try {
      params = Uri.splitQueryString(url.fragment);
    } catch (_) {
      return null;
    }
    if (params.containsKey('error') || params.containsKey('error_code')) {
      return AuthLink(
        type: params['type'],
        error: params['error_description'] ?? params['error'],
      );
    }
    final accessToken = params['access_token'];
    final refreshToken = params['refresh_token'];
    if (accessToken == null || refreshToken == null) return null;
    final claims = _jwtClaims(accessToken);
    final userId = claims?['sub'];
    if (userId is! String) return null;

    final metadata = claims!['user_metadata'];
    final fullName = metadata is Map ? metadata['full_name'] : null;
    final expiresAt =
        int.tryParse(params['expires_at'] ?? '') ??
        (claims['exp'] as num?)?.toInt() ??
        0;
    return AuthLink(
      type: params['type'],
      session: AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000),
        user: AuthUser(
          id: userId,
          email: claims['email'] as String?,
          fullName: fullName is String && fullName.isNotEmpty ? fullName : null,
        ),
      ),
    );
  }

  /// Reads (doesn't verify) a JWT's payload; the API verifies every token.
  static Map<String, dynamic>? _jwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

/// Where the session survives app restarts. Replaced in tests.
abstract class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession? session);
}

/// Android Keystore / encrypted storage on the web.
class SecureSessionStore implements SessionStore {
  static const _key = 'auth_session';
  final _storage = const FlutterSecureStorage();

  @override
  Future<AuthSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      // Unreadable (e.g. restored from a backup on another device): sign in again.
      debugPrint('Ignoring the stored session: $error');
      return null;
    }
  }

  @override
  Future<void> write(AuthSession? session) => session == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: jsonEncode(session.toJson()));
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

/// The session read on start-up (from storage or an email link); set in `main`.
final initialSessionProvider = Provider<AuthSession?>((ref) => null);

/// The email link the app was opened with, if any; set in `main`.
final authLinkProvider = Provider<AuthLink?>((ref) => null);

/// Calls that don't need a session (sign in, sign up, refresh...).
final authApiClientProvider = Provider((ref) => ApiClient());

/// The session, or null when signed out.
final authProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);

/// Currently signed-in user, or `null`. Doesn't change when only the tokens
/// are renewed, so what depends on the user isn't reloaded every hour.
final currentUserProvider = Provider<AuthUser?>(
  (ref) => ref.watch(authProvider.select((session) => session?.user)),
);

class AuthController extends Notifier<AuthSession?> implements TokenSource {
  Future<AuthSession?>? _refreshing;

  @override
  AuthSession? build() => ref.read(initialSessionProvider);

  ApiClient get _api => ref.read(authApiClientProvider);

  Future<void> _save(AuthSession? session) async {
    state = session;
    try {
      await ref.read(sessionStoreProvider).write(session);
    } catch (error) {
      // Still signed in (or out) for this run; just not remembered.
      debugPrint('Could not store the session: $error');
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final json = await _api.post('/api/auth/login', {
      'email': email,
      'password': password,
    });
    await _save(AuthSession.fromJson(json as Map<String, dynamic>));
  }

  /// Creates the account. Returns false when it has to be confirmed by email
  /// first (no session yet).
  Future<bool> signUp({
    required String email,
    required String password,
    String? fullName,
    String? redirectTo,
  }) async {
    final json =
        await _api.post('/api/auth/signup', {
              'email': email,
              'password': password,
              if (fullName != null && fullName.isNotEmpty)
                'full_name': fullName,
              'redirect_to': ?redirectTo,
            })
            as Map<String, dynamic>;
    final session = json['session'];
    if (session == null) return false;
    await _save(AuthSession.fromJson(session as Map<String, dynamic>));
    return true;
  }

  /// Emails a link to choose a new password.
  Future<void> recoverPassword(String email, {String? redirectTo}) => _api.post(
    '/api/auth/recover',
    {'email': email, 'redirect_to': ?redirectTo},
  );

  /// Starts using a session obtained elsewhere (an email link).
  Future<void> adopt(AuthSession session) => _save(session);

  /// Signs out here and ends the session on the server.
  Future<void> signOut() async {
    final session = state;
    await _save(null);
    if (session == null) return;
    try {
      // Sent with the old session's token, not the (now empty) current one.
      await _api.post('/api/auth/logout', null, session.accessToken);
    } catch (error) {
      // Signed out on this device anyway; the server session will expire.
      debugPrint('Could not end the session on the server: $error');
    }
  }

  /// Forgets the session without telling the server (e.g. the account was
  /// just deleted).
  Future<void> forget() => _save(null);

  @override
  Future<String?> accessToken() async {
    final session = state;
    if (session == null) return null;
    if (!session.expiresSoon) return session.accessToken;
    return (await _refresh())?.accessToken;
  }

  @override
  Future<String?> refreshedAccessToken() async =>
      (await _refresh())?.accessToken;

  /// One refresh at a time: refresh tokens can only be used once.
  Future<AuthSession?> _refresh() =>
      _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<AuthSession?> _doRefresh() async {
    final session = state;
    if (session == null) return null;
    try {
      final json = await _api.post('/api/auth/refresh', {
        'refresh_token': session.refreshToken,
      });
      final renewed = AuthSession.fromJson(json as Map<String, dynamic>);
      await _save(renewed);
      return renewed;
    } on ApiException catch (error) {
      // The server rejected the refresh token (revoked, expired, account
      // deleted): the session is over. Network or server errors keep it.
      final status = error.statusCode;
      if (status != null && status >= 400 && status < 500) await _save(null);
      return null;
    } catch (_) {
      return null;
    }
  }
}
