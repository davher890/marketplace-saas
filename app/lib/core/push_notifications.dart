import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/api_client.dart';
import '../repositories/order_repository.dart';
import '../repositories/profile_repository.dart';
import 'providers.dart';
import 'router.dart';

// Push notifications to admins about new orders (Android only).
//
// Firebase is configured by `android/app/google-services.json` (see README
// "Push notifications"). Without it, or on the web, [initPushNotifications]
// returns false and nothing below runs. The API sends the notifications
// (server/services/push.ts); the app only registers the device and opens the
// order when a notification is tapped.

/// Starts Firebase. Returns whether push notifications are available.
Future<bool> initPushNotifications() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    await Firebase.initializeApp();
    return true;
  } catch (error) {
    debugPrint('Push notifications disabled: $error');
    return false;
  }
}

/// Set in `main` from [initPushNotifications].
final pushEnabledProvider = Provider<bool>((ref) => false);

/// Shows snack bars from outside the widget tree (foreground notifications).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Where a notification should take the admin when tapped.
String? routeForMessage(Map<String, dynamic> data) {
  final orderId = data['order_id'];
  return data['type'] == 'new_order' && orderId is String && orderId.isNotEmpty
      ? '/admin/orders/$orderId'
      : null;
}

/// The parts of Firebase Messaging the app uses. Replaced in tests.
abstract class PushMessaging {
  /// Asks for the notification permission (Android 13+). Whether it's granted.
  Future<bool> requestPermission();

  /// Registers this install with FCM; the ID arrives through [onRegistered].
  Future<void> register();

  /// Firebase Installation IDs (FIDs) to send to the API: after [register]
  /// and whenever FCM assigns a new one.
  Stream<String> get onRegistered;

  /// Stops this install from receiving pushes.
  Future<void> unregister();

  /// Messages received while the app is in the foreground (not shown by Android).
  Stream<RemoteMessage> get onMessage;

  /// Notifications tapped while the app was in the background.
  Stream<RemoteMessage> get onMessageOpenedApp;

  /// The notification that launched the app, if any.
  Future<RemoteMessage?> getInitialMessage();
}

class FirebasePushMessaging implements PushMessaging {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<void> register() => _messaging.register();

  @override
  Stream<String> get onRegistered => _messaging.onRegistered;

  @override
  Future<void> unregister() => _messaging.unregister();

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();
}

final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => FirebasePushMessaging(),
);

/// Watched by the app root. While an admin is signed in, this device is
/// registered with the API; on sign out it's unregistered from FCM so the
/// next person using the phone doesn't get the shop's notifications.
final adminPushProvider = Provider<void>((ref) {
  if (!ref.watch(pushEnabledProvider)) return;
  final messaging = ref.watch(pushMessagingProvider);
  final api = ref.watch(apiClientProvider);
  final subscriptions = <StreamSubscription<Object?>>[];
  StreamSubscription<String>? registrations;
  ref.onDispose(() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    registrations?.cancel();
  });

  Future<void> saveDevice(String fid) async {
    try {
      await api.post('/api/admin/devices', {'fid': fid, 'platform': 'android'});
    } catch (error) {
      debugPrint('Could not register for push notifications: $error');
    }
  }

  ref.listen(isAdminProvider, (_, next) async {
    if (next.value != true || registrations != null) return;
    registrations = messaging.onRegistered.listen(saveDevice);
    try {
      if (!await messaging.requestPermission()) return;
      await messaging.register();
    } catch (error) {
      debugPrint('Push notifications unavailable: $error');
    }
  }, fireImmediately: true);

  ref.listen(currentUserProvider, (previous, next) {
    if (previous == null || next != null) return;
    registrations?.cancel();
    registrations = null;
    messaging.unregister().catchError(
      (Object error) => debugPrint('Could not unregister from FCM: $error'),
    );
  });

  void open(RemoteMessage? message) {
    final route = message == null ? null : routeForMessage(message.data);
    if (route != null) ref.read(routerProvider).go(route);
  }

  messaging.getInitialMessage().then(open, onError: (_) {});
  subscriptions
    ..add(messaging.onMessageOpenedApp.listen(open))
    ..add(
      messaging.onMessage.listen((message) {
        final route = routeForMessage(message.data);
        if (route == null) return;
        ref.invalidate(adminOrdersProvider);
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              [
                message.notification?.title,
                message.notification?.body,
              ].whereType<String>().join(': '),
            ),
            action: SnackBarAction(
              label: 'Ver',
              onPressed: () => ref.read(routerProvider).go(route),
            ),
          ),
        );
      }),
    );
});
