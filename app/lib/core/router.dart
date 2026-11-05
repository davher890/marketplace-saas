import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/admin/admin_categories_screen.dart';
import '../features/admin/admin_orders_screen.dart';
import '../features/admin/admin_products_screen.dart';
import '../features/admin/admin_settings_screen.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/product_form_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/catalog/category_screen.dart';
import '../features/catalog/home_screen.dart';
import '../features/catalog/product_screen.dart';
import '../features/checkout/checkout_screen.dart';
import '../features/orders/my_orders_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/store_shell.dart';
import '../repositories/profile_repository.dart';
import 'providers.dart';
import 'theme.dart';

/// Re-runs router redirects whenever a stream emits (used for auth changes).
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _subscription = stream.listen(
      (_) => notifyListeners(),
      // e.g. an expired recovery link: the screens show the signed-out state.
      onError: (Object _) => notifyListeners(),
    );
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

  const signedInOnly = ['/checkout', '/orders', '/profile'];

  final router = GoRouter(
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
        pageBuilder: (_, state, child) =>
            _fadePage(state, StoreShell(child: child)),
        routes: [
          _storeRoute('/', (_) => const HomeScreen()),
          _storeRoute(
            '/c/:slug',
            (state) => CategoryScreen(slug: state.pathParameters['slug']!),
          ),
          _storeRoute(
            '/product/:slug',
            (state) => ProductScreen(slug: state.pathParameters['slug']!),
          ),
          _storeRoute('/cart', (_) => const CartScreen()),
          _storeRoute('/checkout', (_) => const CheckoutScreen()),
          _storeRoute(
            '/login',
            (state) =>
                LoginScreen(redirectTo: state.uri.queryParameters['from']),
          ),
          _storeRoute('/reset-password', (_) => const ResetPasswordScreen()),
          _storeRoute('/profile', (_) => const ProfileScreen()),
          _storeRoute('/orders', (_) => const MyOrdersScreen()),
          _storeRoute(
            '/orders/:id',
            (state) => OrderDetailScreen(
              orderId: state.pathParameters['id']!,
              justPlaced: state.uri.queryParameters['placed'] == '1',
            ),
          ),
        ],
      ),
      ShellRoute(
        pageBuilder: (_, state, child) =>
            _fadePage(state, AdminShell(child: child)),
        routes: [
          _adminRoute('/admin', (_) => const SizedBox.shrink()),
          _adminRoute('/admin/orders', (_) => const AdminOrdersScreen()),
          _adminRoute(
            '/admin/orders/:id',
            (state) => AdminOrderScreen(orderId: state.pathParameters['id']!),
          ),
          _adminRoute('/admin/products', (_) => const AdminProductsScreen()),
          _adminRoute('/admin/products/new', (_) => const ProductFormScreen()),
          _adminRoute(
            '/admin/products/:id',
            (state) => ProductFormScreen(productId: state.pathParameters['id']),
          ),
          _adminRoute(
            '/admin/categories',
            (_) => const AdminCategoriesScreen(),
          ),
          _adminRoute('/admin/settings', (_) => const AdminSettingsScreen()),
        ],
      ),
    ],
  );

  // A password recovery link signs the user in with a `passwordRecovery`
  // event. Links redirected to `/reset-password` already land there; this
  // covers links that open another page (e.g. Supabase's Site URL).
  // `onAuthStateChange` replays past events, so the one emitted while
  // Supabase was initializing is not missed.
  final recovery = db.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      // The replayed event can arrive while the router is still being built.
      Future.microtask(() => router.go('/reset-password'));
    }
  }, onError: (Object _) {});
  ref.onDispose(() {
    recovery.cancel();
    router.dispose();
  });
  return router;
});

/// Short cross-fade between pages. The default transition on iOS / macOS
/// (which includes the web on a Mac) slides the new page in from the side,
/// which looks out of place in a web shop.
Page<void> _fadePage(GoRouterState state, Widget child, {Color? background}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    // Pages draw on the shell's background; make each one opaque so the
    // previous page doesn't show through while they fade.
    child: background == null
        ? child
        : ColoredBox(color: background, child: child),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

/// Storefront page: scrolls with the footer, inside [StoreShell].
GoRoute _storeRoute(String path, Widget Function(GoRouterState) build) =>
    GoRoute(
      path: path,
      pageBuilder: (_, state) => _fadePage(
        state,
        StorePage(child: build(state)),
        background: AppColors.sage,
      ),
    );

/// Admin page, inside [AdminShell].
GoRoute _adminRoute(String path, Widget Function(GoRouterState) build) =>
    GoRoute(
      path: path,
      pageBuilder: (_, state) =>
          _fadePage(state, build(state), background: AppColors.sageLight),
    );
