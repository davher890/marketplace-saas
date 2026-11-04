import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';
import 'product_card.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final category = categories.where((c) => c.slug == slug).firstOrNull;
    final children = category == null
        ? const []
        : categories
              .where((c) => c.parentId == category.id && c.isActive)
              .toList();
    final products = ref.watch(categoryProductsProvider(slug));

    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(category?.name ?? ''),
          if (category?.description != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(category!.description!, textAlign: TextAlign.center),
            ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final child in children)
                    ActionChip(
                      label: Text(child.name),
                      onPressed: () => context.go('/c/${child.slug}'),
                    ),
                ],
              ),
            ),
          AsyncView(
            value: products,
            onRetry: () => ref.invalidate(categoryProductsProvider(slug)),
            builder: (items) => ProductGrid(products: items),
          ),
        ],
      ),
    );
  }
}
