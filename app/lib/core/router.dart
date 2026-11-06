import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import 'auth.dart';
import 'theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-runs the redirects when the user signs in or out.
  final refresh = ValueNotifier(0);
  ref.listen(currentUserProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  const signedInOnly = ['/checkout', '/orders', '/profile'];

  final router = GoRouter(
    refreshListenable: refresh,
    // A password recovery link sent from the Android app lands on the web
    // app's home page (Supabase's Site URL): go straight to the form.
    initialLocation: ref.read(authLinkProvider)?.isRecovery == true
        ? '/reset-password'
        : '/',
    redirect: (context, state) async {
      final path = state.uri.path;
      final signedIn = ref.read(currentUserProvider) != null;

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

  ref.onDispose(router.dispose);
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
