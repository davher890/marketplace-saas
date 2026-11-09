import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';
import '../shell/store_shell.dart';
import 'product_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredProductsProvider);
    final tree = ref.watch(categoryTreeProvider);
    final textTheme = Theme.of(context).textTheme;

    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          Text(
            'Regalos hechos a mano, con mucho cariño',
            textAlign: TextAlign.center,
            style: textTheme.displayMedium,
          ),
          const SizedBox(height: 24),
          // Quick links to the categories, only on narrow screens: wider
          // ones already show them in the header menu.
          if (!StoreShell.isWide(context))
            tree.when(
              data: (nodes) => Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final node in nodes)
                    ActionChip(
                      label: Text(node.category.name),
                      onPressed: () => context.go('/c/${node.category.slug}'),
                    ),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          const SectionTitle('Destacados'),
          AsyncView(
            value: featured,
            onRetry: () => ref.invalidate(featuredProductsProvider),
            builder: (products) => ProductGrid(products: products),
          ),
        ],
      ),
    );
  }
}
