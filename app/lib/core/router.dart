import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/admin_orders_screen.dart';
import '../features/admin/admin_products_screen.dart';
import '../features/admin/admin_settings_screen.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/product_form_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/catalog/category_screen.dart';
import '../features/catalog/home_screen.dart';
import '../features/catalog/product_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/orders/my_orders_screen.dart';
import '../features/shell/store_shell.dart';
import '../repositories/profile_repository.dart';
import 'providers.dart';

/// Re-runs router redirects whenever a stream emits (used for auth changes).
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final db = ref.watch(supabaseProvider);
  final refresh = _StreamListenable(db.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  const signedInOnly = ['/checkout', '/orders'];

  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) async {
      final path = state.uri.path;
      final signedIn = db.auth.currentUser != null;

      if (!signedIn &&
          (signedInOnly.any(path.startsWith) || path.startsWith('/admin'))) {
        return '/login?from=${Uri.encodeComponent(state.uri.toString())}';
      }
      if (path.startsWith('/admin')) {
        // RLS is the real guard; this only keeps customers out of the UI.
        final isAdmin = await ref.read(isAdminProvider.future);
        if (!isAdmin) return '/';
        if (path == '/admin') return '/admin/orders';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => StoreShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: '/c/:slug',
            builder: (_, state) =>
                CategoryScreen(slug: state.pathParameters['slug']!),
          ),
          GoRoute(
            path: '/product/:slug',
            builder: (_, state) =>
                ProductScreen(slug: state.pathParameters['slug']!),
          ),
          GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
          GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
          GoRoute(
            path: '/login',
            builder: (_, state) =>
                LoginScreen(redirectTo: state.uri.queryParameters['from']),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const MyOrdersScreen()),
          GoRoute(
            path: '/orders/:id',
            builder: (_, state) => OrderDetailScreen(
              orderId: state.pathParameters['id']!,
              justPlaced: state.uri.queryParameters['placed'] == '1',
            ),
          ),
        ],
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(path: '/admin', builder: (_, _) => const SizedBox.shrink()),
          GoRoute(
            path: '/admin/orders',
            builder: (_, _) => const AdminOrdersScreen(),
          ),
          GoRoute(
            path: '/admin/orders/:id',
            builder: (_, state) =>
                AdminOrderScreen(orderId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admin/products',
            builder: (_, _) => const AdminProductsScreen(),
          ),
          GoRoute(
            path: '/admin/products/new',
            builder: (_, _) => const ProductFormScreen(),
          ),
          GoRoute(
            path: '/admin/products/:id',
            builder: (_, state) =>
                ProductFormScreen(productId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/settings',
            builder: (_, _) => const AdminSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
