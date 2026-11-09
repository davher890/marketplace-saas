import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/product.dart';
import '../../repositories/admin_repository.dart';

/// Admin layout: navigation rail on wide screens, bottom bar on phones, and
/// a warning on top while some product has no category.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  static const _destinations = [
    (
      path: '/admin/orders',
      icon: Icons.receipt_long_outlined,
      label: 'Pedidos',
    ),
    (
      path: '/admin/products',
      icon: Icons.inventory_2_outlined,
      label: 'Productos',
    ),
    (
      path: '/admin/categories',
      icon: Icons.category_outlined,
      label: 'Categorías',
    ),
    (path: '/admin/settings', icon: Icons.settings_outlined, label: 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uncategorized =
        ref.watch(uncategorizedProductsProvider).value ?? const <Product>[];
    final withoutPhoto =
        ref.watch(productsWithoutPhotoProvider).value ?? const <Product>[];
    final warnings = [
      if (uncategorized.isNotEmpty)
        _ProductsWarning(
          products: uncategorized,
          missing: 'sin categoría',
          consequence:
              'no aparece en la tienda (ni en los menús ni en el '
              'buscador)',
          consequencePlural:
              'no aparecen en la tienda (ni en los menús ni en '
              'el buscador)',
          reviewPath: '/admin/products?sin_categoria=1',
        ),
      if (withoutPhoto.isNotEmpty)
        _ProductsWarning(
          products: withoutPhoto,
          missing: 'sin foto',
          consequence: 'se ve en la tienda sin imagen',
          consequencePlural: 'se ven en la tienda sin imagen',
          reviewPath: '/admin/products?sin_foto=1',
        ),
    ];
    final page = warnings.isEmpty
        ? child
        : Column(
            children: [
              ...warnings,
              Expanded(child: child),
            ],
          );
    final path = GoRouterState.of(context).uri.path;
    final selected = _destinations
        .indexWhere((d) => path.startsWith(d.path))
        .clamp(0, _destinations.length - 1);
    final isWide = MediaQuery.sizeOf(context).width >= 800;

    void onSelect(int index) => context.go(_destinations[index].path);

    return Scaffold(
      backgroundColor: AppColors.sageLight,
      appBar: AppBar(
        backgroundColor: AppColors.forest,
        foregroundColor: AppColors.cream,
        title: Text(
          'Doña Galleta · Admin',
          style: AppTheme.wordmark(size: 32, color: AppColors.cream),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/'),
            style: TextButton.styleFrom(foregroundColor: AppColors.cream),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Ver tienda'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isWide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                Expanded(child: page),
              ],
            )
          : page,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: onSelect,
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(icon: Icon(d.icon), label: d.label),
              ],
            ),
    );
  }
}

/// "Hay 2 productos sin foto (…): se ven en la tienda sin imagen", with a
/// button to see them in the product list.
class _ProductsWarning extends StatelessWidget {
  const _ProductsWarning({
    required this.products,
    required this.missing,
    required this.consequence,
    required this.consequencePlural,
    required this.reviewPath,
  });

  final List<Product> products;

  /// What the products lack, e.g. "sin foto".
  final String missing;
  final String consequence;
  final String consequencePlural;
  final String reviewPath;

  @override
  Widget build(BuildContext context) {
    final count = products.length;
    final names = products.take(3).map((p) => p.name).join(', ');
    final more = count > 3 ? ' y ${count - 3} más' : '';
    return Material(
      color: const Color(0xFFFFF3CD),
      shape: const Border(bottom: BorderSide(color: Color(0xFFF0DFA0))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A6D00)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 1
                    ? 'Hay 1 producto $missing ($names): $consequence.'
                    : 'Hay $count productos $missing ($names$more): '
                          '$consequencePlural.',
                style: const TextStyle(color: Color(0xFF5C4800)),
              ),
            ),
            TextButton(
              onPressed: () => context.go(reviewPath),
              child: const Text('Revisar'),
            ),
          ],
        ),
      ),
    );
  }
}
