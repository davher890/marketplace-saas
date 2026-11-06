import 'dart:async';
import 'dart:convert';

import 'package:dona_galleta/core/providers.dart';
import 'package:dona_galleta/core/push_notifications.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/profile_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Signed-in user, switchable from the test.
class _User extends Notifier<User?> {
  @override
  User? build() => const User(
    id: 'u1',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-11-07T00:00:00Z',
  );

  void signOut() => state = null;
}

final _userProvider = NotifierProvider<_User, User?>(_User.new);

void main() {
  late _FakeMessaging messaging;
  late List<http.Request> requests;

  ProviderContainer start({
    bool isAdmin = true,
    bool enabled = true,
    bool permission = true,
  }) {
    messaging = _FakeMessaging()..permission = permission;
    requests = [];
    final api = ApiClient(
      SupabaseClient('http://localhost:54321', 'test-key'),
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{"registered":true}', 200);
      }),
    );
    final container = ProviderContainer(
      overrides: [
        pushEnabledProvider.overrideWithValue(enabled),
        pushMessagingProvider.overrideWithValue(messaging),
        apiClientProvider.overrideWithValue(api),
        currentUserProvider.overrideWith((ref) => ref.watch(_userProvider)),
        isAdminProvider.overrideWith((ref) async => isAdmin),
      ],
    );
    addTearDown(container.dispose);
    container.listen(adminPushProvider, (_, _) {});
    return container;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('an admin registers this device with the API', () async {
    start();
    await settle();
    await settle();
    expect(messaging.calls, ['permission', 'register', 'installationId']);
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/admin/devices');
    expect(jsonDecode(requests.single.body), {
      'fid': 'fid-1',
      'platform': 'android',
    });
  });

  test('a new FID from FCM is sent again', () async {
    start();
    await settle();
    messaging.registered.add('fid-2');
    await settle();
    expect(requests.map((r) => (jsonDecode(r.body) as Map)['fid']), [
      'fid-1',
      'fid-2',
    ]);
  });

  test('signing out unregisters the device', () async {
    final container = start();
    await settle();
    container.read(_userProvider.notifier).signOut();
    await settle();
    expect(messaging.calls.last, 'unregister');

    // No longer listening: later FIDs aren't sent for the old user.
    messaging.registered.add('fid-3');
    await settle();
    expect(requests, hasLength(1));
  });

  test('nothing is registered without permission', () async {
    start(permission: false);
    await settle();
    expect(messaging.calls, ['permission']);
    expect(requests, isEmpty);
  });

  test('customers are never registered', () async {
    start(isAdmin: false);
    await settle();
    expect(messaging.calls, isEmpty);
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
