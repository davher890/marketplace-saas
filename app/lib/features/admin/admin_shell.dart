import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Admin layout: navigation rail on wide screens, bottom bar on phones.
class AdminShell extends StatelessWidget {
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
    (path: '/admin/settings', icon: Icons.settings_outlined, label: 'Ajustes'),
  ];

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final selected = _destinations
        .indexWhere((d) => path.startsWith(d.path))
        .clamp(0, 2);
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
                Expanded(child: child),
              ],
            )
          : child,
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
