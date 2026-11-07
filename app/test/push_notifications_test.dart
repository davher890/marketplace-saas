import 'dart:async';
import 'dart:convert';

import 'package:dona_galleta/core/auth.dart';
import 'package:dona_galleta/core/push_notifications.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records what the app asks Firebase Messaging to do.
class _FakeMessaging implements PushMessaging {
  final calls = <String>[];
  final registered = StreamController<String>.broadcast();
  bool permission = true;

  @override
  Future<bool> requestPermission() async {
    calls.add('permission');
    return permission;
  }

  /// FCM registers at app start, so register() emits nothing: the current
  /// FID is only available from installationId().
  @override
  Future<void> register() async => calls.add('register');

  @override
  Future<String> installationId() async {
    calls.add('installationId');
    return 'fid-1';
  }

  @override
  Stream<String> get onRegistered => registered.stream;

  @override
  Future<void> unregister() async => calls.add('unregister');

  @override
  Stream<RemoteMessage> get onMessage => const Stream.empty();

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => const Stream.empty();

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
}

/// Who is signed in, switchable from the test.
class _User extends Notifier<AuthUser?> {
  _User(this.initial);

  final AuthUser? initial;

  @override
  AuthUser? build() => initial;

  void signIn(String id) => state = AuthUser(id: id);
  void signOut() => state = null;
}

/// Gives the API client the signed-in user's token, like AuthController.
class _Tokens implements TokenSource {
  _Tokens(this.read);

  final AuthUser? Function() read;

  @override
  Future<String?> accessToken() async {
    final user = read();
    return user == null ? null : 'token-${user.id}';
  }

  @override
  Future<String?> refreshedAccessToken() => accessToken();
}

void main() {
  late _FakeMessaging messaging;
  late List<http.Request> requests;
  late NotifierProvider<_User, AuthUser?> userProvider;

  ProviderContainer start({
    AuthUser? signedIn,
    bool enabled = true,
    bool permission = true,
  }) {
    messaging = _FakeMessaging()..permission = permission;
    requests = [];
    userProvider = NotifierProvider<_User, AuthUser?>(() => _User(signedIn));
    late ProviderContainer container;
    final api = ApiClient(
      tokens: _Tokens(() => container.read(userProvider)),
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{"registered":true}', 200);
      }),
    );
    container = ProviderContainer(
      overrides: [
        pushEnabledProvider.overrideWithValue(enabled),
        pushMessagingProvider.overrideWithValue(messaging),
        apiClientProvider.overrideWithValue(api),
        currentUserProvider.overrideWith((ref) => ref.watch(userProvider)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(pushRegistrationProvider, (_, _) {});
    return container;
  }

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// "fid → token" for each registration sent to the API.
  List<String> registrations() => [
    for (final r in requests)
      '${(jsonDecode(r.body) as Map)['fid']} → '
          '${r.headers['Authorization'] ?? 'nobody'}',
  ];

  test('everyone is asked on open, and the device registered', () async {
    start();
    await settle();
    expect(messaging.calls, ['permission', 'register', 'installationId']);
    expect(requests.single.url.path, '/api/devices');
    expect(jsonDecode(requests.single.body), {
      'fid': 'fid-1',
      'platform': 'android',
    });
    expect(registrations(), ['fid-1 → nobody']);
  });

  test('a signed-in user\'s device is linked to them', () async {
    start(signedIn: const AuthUser(id: 'u1'));
    await settle();
    expect(registrations(), ['fid-1 → Bearer token-u1']);
  });

  test('signing in and out relinks the device', () async {
    final container = start();
    await settle();
    container.read(userProvider.notifier).signIn('u1');
    await settle();
    container.read(userProvider.notifier).signOut();
    await settle();
    expect(registrations(), [
      'fid-1 → nobody',
      'fid-1 → Bearer token-u1',
      'fid-1 → nobody',
    ]);
    // The device keeps its registration (shop news); it's just nobody's now.
    expect(messaging.calls, isNot(contains('unregister')));
  });

  test('a new FID from FCM is sent again', () async {
    start();
    await settle();
    messaging.registered.add('fid-2');
    await settle();
    expect(registrations(), ['fid-1 → nobody', 'fid-2 → nobody']);
  });

  test('nothing is registered without permission', () async {
    start(permission: false);
    await settle();
    expect(messaging.calls, ['permission']);
    expect(requests, isEmpty);
  });

  test('does nothing when Firebase is not configured', () async {
    start(enabled: false);
    await settle();
    expect(messaging.calls, isEmpty);
  });

  test('routeForMessage opens the new order', () {
    expect(
      routeForMessage({'type': 'new_order', 'order_id': 'o1'}),
      '/admin/orders/o1',
    );
    expect(routeForMessage({'type': 'other', 'order_id': 'o1'}), isNull);
    expect(routeForMessage({'type': 'new_order'}), isNull);
  });
}
