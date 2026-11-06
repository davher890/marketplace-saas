import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../repositories/admin_repository.dart';
import '../../widgets/common.dart';

class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  ConsumerState<AdminProductsScreen> createState() =>
      _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(adminProductsProvider);
    final categories = ref.watch(adminCategoriesProvider).value ?? const [];
    String categoryNames(List<String> ids) {
      final names = [
        for (final id in ids)
          ?categories.where((c) => c.id == id).firstOrNull?.name,
      ];
      return names.isEmpty ? 'Sin categoría' : names.join(', ');
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/admin/products/new'),
        backgroundColor: AppColors.forest,
        foregroundColor: AppColors.cream,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminProductsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text('Productos', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por nombre',
              ),
              onChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 16),
            AsyncView(
              value: products,
              onRetry: () => ref.invalidate(adminProductsProvider),
              builder: (products) {
                final filtered = products
                    .where(
                      (p) =>
                          _search.isEmpty ||
                          p.name.toLowerCase().contains(_search),
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No hay productos.')),
                  );
                }
                return Column(
                  children: [
                    for (final product in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ProductRow(
                          product: product,
                          categoryName: categoryNames(product.categoryIds),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductRow extends ConsumerWidget {
  const _ProductRow({required this.product, required this.categoryName});

  final Product product;
  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackedStock = product.variants
        .where((v) => v.tracksStock)
        .fold<int>(0, (sum, v) => sum + v.stock!);
    final tracksStock = product.variants.any((v) => v.tracksStock);
    final stockLabel = tracksStock ? 'Stock: $trackedStock' : 'Por encargo';

    return Card(
      child: ListTile(
        onTap: () => context.go('/admin/products/${product.id}'),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox.square(
            dimension: 48,
            child: ProductImageView(url: product.coverUrl),
          ),
        ),
        title: Text(product.name),
        subtitle: Text(
          '$categoryName · ${formatCents(product.minPriceCents)} · '
          '${product.variants.length} variante${product.variants.length == 1 ? '' : 's'} · $stockLabel',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (product.isFeatured)
              const Icon(Icons.star, color: AppColors.mauve),
            Switch(
              value: product.isActive,
              onChanged: (value) async {
                try {
                  await ref
                      .read(adminRepositoryProvider)
                      .setProductActive(product.id, value);
                  ref.invalidate(adminProductsProvider);
                } catch (error) {
                  if (context.mounted) {
                    showMessage(context, describeError(error));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
