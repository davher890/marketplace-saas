import 'dart:convert';

import 'package:dona_galleta/core/auth.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/widgets/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryStore implements SessionStore {
  AuthSession? saved;

  @override
  Future<AuthSession?> read() async => saved;

  @override
  Future<void> write(AuthSession? session) async => saved = session;
}

/// An unsigned JWT with these claims (the app only reads them).
String _jwt(Map<String, dynamic> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.signature';
}

Map<String, dynamic> _sessionJson(String access, {int inSeconds = 3600}) => {
  'access_token': access,
  'refresh_token': 'refresh-$access',
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + inSeconds,
  'user': {'id': 'u1', 'email': 'ana@example.com', 'full_name': 'Ana'},
};

void main() {
  late _MemoryStore store;
  late List<http.Request> requests;
  late ProviderContainer container;

  /// [respond] answers every request the app makes to the API.
  void start(
    http.Response Function(http.Request request) respond, {
    AuthSession? session,
  }) {
    store = _MemoryStore()..saved = session;
    requests = [];
    final client = MockClient((request) async {
      requests.add(request);
      return respond(request);
    });
    container = ProviderContainer(
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        initialSessionProvider.overrideWithValue(session),
        authApiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'https://shop.test', httpClient: client),
        ),
        apiClientProvider.overrideWith(
          (ref) => ApiClient(
            tokens: ref.read(authProvider.notifier),
            baseUrl: 'https://shop.test',
            httpClient: client,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  AuthController auth() => container.read(authProvider.notifier);
  ApiClient api() => container.read(apiClientProvider);
  List<String> paths() => requests.map((r) => r.url.path).toList();

  group('sign in and out', () {
    test('signing in stores the session and sets the user', () async {
      start((_) => json(_sessionJson('a1')));
      await auth().signIn(email: 'ana@example.com', password: 'secret');

      expect(jsonDecode(requests.single.body), {
        'email': 'ana@example.com',
        'password': 'secret',
      });
      expect(container.read(currentUserProvider)?.fullName, 'Ana');
      expect(store.saved?.accessToken, 'a1');
    });

    test('wrong credentials come back as a Spanish message', () async {
      start(
        (_) => json({
          'error': 'Invalid login credentials',
          'code': 'invalid_credentials',
        }, 400),
      );
      final error = await auth()
          .signIn(email: 'ana@example.com', password: 'bad')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(describeError(error!), 'Email o contraseña incorrectos.');
      expect(container.read(currentUserProvider), isNull);
    });

    test('sign up that needs email confirmation leaves no session', () async {
      start((_) => json({'session': null, 'confirmation_required': true}, 201));
      final signedIn = await auth().signUp(
        email: 'ana@example.com',
        password: 'secret1',
        fullName: 'Ana',
        redirectTo: 'https://shop.test',
      );
      expect(signedIn, isFalse);
      expect(jsonDecode(requests.single.body), {
        'email': 'ana@example.com',
        'password': 'secret1',
        'full_name': 'Ana',
        'redirect_to': 'https://shop.test',
      });
      expect(container.read(authProvider), isNull);
    });

    test('signing out forgets the session and ends it on the server', () async {
      start(
        (_) => json({'signed_out': true}),
        session: AuthSession.fromJson(_sessionJson('a1')),
      );
      await auth().signOut();

      expect(container.read(authProvider), isNull);
      expect(store.saved, isNull);
      expect(paths(), ['/api/auth/logout']);
      expect(requests.single.headers['Authorization'], 'Bearer a1');
    });
  });

  group('access token', () {
    test('is sent with API requests', () async {
      start(
        (_) => json({'id': 'u1'}),
        session: AuthSession.fromJson(_sessionJson('a1')),
      );
      await api().get('/api/me');
      expect(requests.single.headers['Authorization'], 'Bearer a1');
    });

    test(
      'is renewed first when about to expire, once for parallel requests',
      () async {
        start(
          (request) => request.url.path == '/api/auth/refresh'
              ? json(_sessionJson('a2'))
              : json({}),
          session: AuthSession.fromJson(_sessionJson('a1', inSeconds: 30)),
        );
        await Future.wait([api().get('/api/me'), api().get('/api/cart')]);

        expect(paths().where((p) => p == '/api/auth/refresh'), hasLength(1));
        expect(jsonDecode(requests.first.body), {
          'refresh_token': 'refresh-a1',
        });
        for (final request in requests.skip(1)) {
          expect(request.headers['Authorization'], 'Bearer a2');
        }
        expect(store.saved?.accessToken, 'a2');
      },
    );

    test('a 401 renews the session and retries the request', () async {
      start((request) {
        if (request.url.path == '/api/auth/refresh') {
          return json(_sessionJson('a2'));
        }
        return request.headers['Authorization'] == 'Bearer a2'
            ? json({'ok': true})
            : json({'error': 'Invalid or expired session'}, 401);
      }, session: AuthSession.fromJson(_sessionJson('a1')));

      expect(await api().get('/api/me'), {'ok': true});
      expect(paths(), ['/api/me', '/api/auth/refresh', '/api/me']);
    });

    test('a rejected refresh token signs the user out', () async {
      start((request) {
        if (request.url.path == '/api/auth/refresh') {
          return json({
            'error': 'Invalid Refresh Token',
            'code': 'refresh_token_not_found',
          }, 400);
        }
        return json({'error': 'Invalid or expired session'}, 401);
      }, session: AuthSession.fromJson(_sessionJson('a1')));

      await expectLater(api().get('/api/me'), throwsA(isA<ApiException>()));
      expect(container.read(authProvider), isNull);
      expect(store.saved, isNull);
    });

    test('a network error while renewing keeps the session', () async {
      start((request) {
        if (request.url.path == '/api/auth/refresh') {
          throw http.ClientException('offline');
        }
        return json({'error': 'Invalid or expired session'}, 401);
      }, session: AuthSession.fromJson(_sessionJson('a1')));

      await expectLater(api().get('/api/me'), throwsA(isA<ApiException>()));
      expect(container.read(authProvider)?.accessToken, 'a1');
    });
  });

  group('AuthLink (email links)', () {
    final token = _jwt({
      'sub': 'u1',
      'email': 'ana@example.com',
      'exp': 2000000000,
      'user_metadata': {'full_name': 'Ana'},
    });

    test('reads the session a recovery link brings', () {
      final link = AuthLink.fromUrl(
        Uri.parse(
          'https://shop.test/reset-password#access_token=$token'
          '&expires_at=1900000000&refresh_token=r1&token_type=bearer'
          '&type=recovery',
        ),
      )!;
      expect(link.isRecovery, isTrue);
      expect(link.session!.refreshToken, 'r1');
      expect(
        link.session!.user,
        const AuthUser(id: 'u1', email: 'ana@example.com', fullName: 'Ana'),
      );
      expect(link.session!.expiresAt.millisecondsSinceEpoch, 1900000000000);
    });

    test('an expired link reports the error and no session', () {
      final link = AuthLink.fromUrl(
        Uri.parse(
          'https://shop.test/#error=access_denied&error_code=otp_expired'
          '&error_description=Email+link+is+invalid+or+has+expired',
        ),
      )!;
      expect(link.session, isNull);
      expect(link.error, 'Email link is invalid or has expired');
    });

    test('ignores URLs that are not email links', () {
      expect(AuthLink.fromUrl(Uri.parse('https://shop.test/c/bebes')), isNull);
      expect(AuthLink.fromUrl(Uri.parse('https://shop.test/#top')), isNull);
      expect(
        AuthLink.fromUrl(
          Uri.parse('https://shop.test/#access_token=bad&refresh_token=r'),
        ),
        isNull,
      );
    });
  });
}
