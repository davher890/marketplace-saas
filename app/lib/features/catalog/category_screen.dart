import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/category.dart';
import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';
import 'product_card.dart';

class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({
    super.key,
    required this.slug,
    this.sort = ProductSort.standard,
  });

  final String slug;

  /// From the page address (`?orden=`), so it survives reloads and sharing.
  final ProductSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final category = categories.where((c) => c.slug == slug).firstOrNull;
    // On a main category or one of its sub-categories, the same row of
    // buttons: "Todo" for the main category, then each sub-category.
    final root = category == null || category.isRoot
        ? category
        : categories.where((c) => c.id == category.parentId).firstOrNull;
    final subcategories = root == null
        ? const <Category>[]
        : categories.where((c) => c.parentId == root.id && c.isActive).toList();
    final key = (slug: slug, sort: sort);
    final products = ref.watch(categoryProductsProvider(key));

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
          if (root != null && subcategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  CategoryTabButton(
                    label: 'Todo',
                    selected: category == root,
                    onPressed: () => context.go('/c/${root.slug}'),
                  ),
                  for (final sub in subcategories)
                    CategoryTabButton(
                      label: sub.name,
                      selected: sub.slug == slug,
                      onPressed: () => context.go('/c/${sub.slug}'),
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _SortMenu(
                sort: sort,
                onChanged: (value) => context.go(
                  value == ProductSort.standard
                      ? '/c/$slug'
                      : '/c/$slug?orden=${value.urlValue}',
                ),
              ),
            ),
          ),
          AsyncView(
            value: products,
            onRetry: () => ref.invalidate(categoryProductsProvider(key)),
            builder: (items) => ProductGrid(products: items),
          ),
        ],
      ),
    );
  }
}

/// "Ordenar por" selector above the product grid.
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onChanged});

  final ProductSort sort;
  final ValueChanged<ProductSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<ProductSort>(
      key: ValueKey(sort),
      initialSelection: sort,
      label: const Text('Ordenar por'),
      // Wide enough for the longest option ("Precio: de menor a mayor").
      width: 300,
      requestFocusOnTap: false,
      onSelected: (value) {
        if (value != null && value != sort) onChanged(value);
      },
      dropdownMenuEntries: [
        for (final option in ProductSort.values)
          DropdownMenuEntry(value: option, label: option.label),
      ],
    );
  }
}
