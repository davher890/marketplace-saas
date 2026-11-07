import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/analytics/cookie_consent.dart';
import '../../core/env.dart';
import '../../core/auth.dart';
import '../../repositories/profile_repository.dart';
import '../../core/theme.dart';
import '../../models/category.dart';
import '../../repositories/cart_repository.dart';
import '../../repositories/catalog_repository.dart';

/// Layout shared by every storefront page: header with the wordmark,
/// category menu, cart / account actions and the footer.
class StoreShell extends ConsumerWidget {
  const StoreShell({super.key, required this.child});

  final Widget child;

  static const _wideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final tree = ref.watch(categoryTreeProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: isWide ? 96 : 64,
        title: InkWell(
          onTap: () => context.go('/'),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Doña Galleta',
              style: AppTheme.wordmark(size: isWide ? 60 : 38),
            ),
          ),
        ),
        actions: const [_CartButton(), _AccountButton(), SizedBox(width: 8)],
        bottom: isWide && tree.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: _CategoryMenuBar(tree: tree),
              )
            : null,
      ),
      drawer: isWide ? null : _CategoryDrawer(tree: tree),
      // `child` is the nested Navigator of the ShellRoute: it must fill the
      // body. Each page scrolls on its own inside a [StorePage].
      body: child,
    );
  }
}

/// Scrollable page body with the footer, used by every storefront route.
class StorePage extends StatelessWidget {
  const StorePage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: child),
        // Keeps the footer at the bottom on short pages.
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Align(alignment: Alignment.bottomCenter, child: _Footer()),
        ),
      ],
    );
  }
}

class _CategoryMenuBar extends StatelessWidget {
  const _CategoryMenuBar({required this.tree});

  final List<CategoryNode> tree;

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;

    return Container(
      height: 60,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.forest, width: 0.5)),
      ),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              for (final node in tree)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _CategoryMenuButton(
                    node: node,
                    currentPath: currentPath,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab-like button that mimics the site's menu: white, rounded, dark green
/// when selected, with a dropdown for sub-categories.
class _CategoryMenuButton extends StatelessWidget {
  const _CategoryMenuButton({required this.node, required this.currentPath});

  final CategoryNode node;
  final String currentPath;

  bool get _isSelected =>
      currentPath == '/c/${node.category.slug}' ||
      node.children.any((c) => currentPath == '/c/${c.slug}');

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: _isSelected ? AppColors.forest : AppColors.surface,
      foregroundColor: _isSelected ? AppColors.cream : AppColors.ink,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      elevation: 1,
    );

    if (node.children.isEmpty) {
      return FilledButton(
        style: style,
        onPressed: () => context.go('/c/${node.category.slug}'),
        child: Text(node.category.name),
      );
    }

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: () => context.go('/c/${node.category.slug}'),
          child: Text('Todo ${node.category.name}'),
        ),
        for (final child in node.children)
          MenuItemButton(
            onPressed: () => context.go('/c/${child.slug}'),
            child: Text(child.name),
          ),
      ],
      builder: (context, controller, _) => FilledButton(
        style: style,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Text(node.category.name),
      ),
    );
  }
}

class _CategoryDrawer extends StatelessWidget {
  const _CategoryDrawer({required this.tree});

  final List<CategoryNode> tree;

  @override
  Widget build(BuildContext context) {
    void go(String path) {
      Navigator.of(context).pop();
      context.go(path);
    }

    return Drawer(
      backgroundColor: AppColors.sageLight,
      child: ListView(
        children: [
          DrawerHeader(
            child: Center(
              child: Text('Doña Galleta', style: AppTheme.wordmark(size: 44)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Inicio'),
            onTap: () => go('/'),
          ),
          for (final node in tree)
            node.children.isEmpty
                ? ListTile(
                    title: Text(node.category.name),
                    onTap: () => go('/c/${node.category.slug}'),
                  )
                : ExpansionTile(
                    title: Text(node.category.name),
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.only(left: 32),
                        title: Text('Todo ${node.category.name}'),
                        onTap: () => go('/c/${node.category.slug}'),
                      ),
                      for (final child in node.children)
                        ListTile(
                          contentPadding: const EdgeInsets.only(left: 32),
                          title: Text(child.name),
                          onTap: () => go('/c/${child.slug}'),
                        ),
                    ],
                  ),
        ],
      ),
    );
  }
}

class _CartButton extends ConsumerWidget {
  const _CartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartProvider).value?.itemCount ?? 0;
    return IconButton(
      tooltip: 'Carrito',
      onPressed: () => context.go('/cart'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: AppColors.mauve,
        child: const Icon(Icons.shopping_bag_outlined),
      ),
    );
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = ref.watch(isAdminProvider).value ?? false;

    if (user == null) {
      return IconButton(
        tooltip: 'Iniciar sesión',
        onPressed: () => context.go('/login'),
        icon: const Icon(Icons.account_circle_outlined),
      );
    }

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.person_outline),
          onPressed: () => context.go('/profile'),
          child: const Text('Mi perfil'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => context.go('/orders'),
          child: const Text('Mis pedidos'),
        ),
        if (isAdmin)
          MenuItemButton(
            leadingIcon: const Icon(Icons.dashboard_outlined),
            onPressed: () => context.go('/admin'),
            child: const Text('Administración'),
          ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => ref.read(authProvider.notifier).signOut(),
          child: const Text('Cerrar sesión'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: user.email ?? 'Cuenta',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.account_circle),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shopSettingsProvider).value;
    final heading = Theme.of(
      context,
    ).textTheme.headlineMedium?.copyWith(color: AppColors.cream);
    const body = TextStyle(color: AppColors.cream);

    final columns = [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hecho a mano', style: heading),
          const SizedBox(height: 8),
          const Text('Diseñado y hecho a mano en España.', style: body),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Contacto', style: heading),
          const SizedBox(height: 8),
          if (settings?.contactEmail != null)
            Text(settings!.contactEmail!, style: body),
          if (settings?.contactPhone != null)
            Text(settings!.contactPhone!, style: body),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Legal', style: heading),
          const SizedBox(height: 8),
          _FooterLink(
            'Política de privacidad',
            onTap: () => launchUrl(Env.sitePage('privacidad.html')),
          ),
          // Lets visitors change their analytics cookies choice at any time.
          if (ref.read(cookieConsentProvider.notifier).available) ...[
            const SizedBox(height: 4),
            _FooterLink(
              'Cookies',
              onTap: ref.read(cookieConsentProvider.notifier).reopen,
            ),
          ],
        ],
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 48),
      color: AppColors.cocoa,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Wrap(
            spacing: 64,
            runSpacing: 24,
            alignment: WrapAlignment.spaceBetween,
            children: columns,
          ),
        ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.cream,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.cream,
        ),
      ),
    );
  }
}
