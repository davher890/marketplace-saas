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
    final page = uncategorized.isEmpty
        ? child
        : Column(
            children: [
              _UncategorizedWarning(products: uncategorized),
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

/// "Hay 2 productos sin categoría…" with a button to see them.
class _UncategorizedWarning extends StatelessWidget {
  const _UncategorizedWarning({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final count = products.length;
    final names = products.take(3).map((p) => p.name).join(', ');
    final more = count > 3 ? ' y ${count - 3} más' : '';
    return Material(
      color: const Color(0xFFFFF3CD),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A6D00)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 1
                    ? 'Hay 1 producto sin categoría ($names): no aparece en '
                          'ningún menú de la tienda.'
                    : 'Hay $count productos sin categoría ($names$more): no '
                          'aparecen en ningún menú de la tienda.',
                style: const TextStyle(color: Color(0xFF5C4800)),
              ),
            ),
            TextButton(
              onPressed: () => context.go('/admin/products?sin_categoria=1'),
              child: const Text('Revisar'),
            ),
          ],
        ),
      ),
    );
  }
}
