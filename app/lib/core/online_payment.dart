import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/catalog_repository.dart';
import '../repositories/order_repository.dart';
import '../repositories/profile_repository.dart';

/// Whether "Pagar ahora" (Stripe) is offered: to everyone once the shop
/// turns it on in Ajustes, and always to admins so they can try it. The API
/// checks the same.
final canPayOnlineProvider = FutureProvider<bool>((ref) async {
  final settings = await ref.watch(shopSettingsProvider.future);
  if (settings.onlinePaymentPublic) return true;
  return ref.watch(isAdminProvider.future);
});

/// Opens Stripe's payment page: in the same tab on the web (Stripe sends the
/// customer back to the order), in the browser on Android.
final paymentPageOpenerProvider = Provider<Future<void> Function(Uri)>(
  (ref) => (url) async {
    await launchUrl(
      url,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
  },
);

/// Creates the Stripe session for [orderId] and opens its page.
Future<void> payOnline(WidgetRef ref, String orderId) async {
  final url = await ref.read(orderRepositoryProvider).payOnline(orderId);
  await ref.read(paymentPageOpenerProvider)(url);
}
