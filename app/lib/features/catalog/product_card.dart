import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../models/product.dart';
import '../../widgets/common.dart';

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final price = formatCents(product.minPriceCents);

    return Card(
      child: InkWell(
        onTap: () => context.push('/product/${product.slug}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ProductImageView(url: product.coverUrl),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.hasPriceRange ? 'Desde $price' : price,
                    style: textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Responsive grid of products (2 columns on phones, up to 4 on desktop).
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('Todavía no hay productos aquí.')),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 260).floor().clamp(2, 4);
        final cellWidth = (constraints.maxWidth - 16 * (columns - 1)) / columns;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            // Square image + room for a two-line name and the price.
            mainAxisExtent: cellWidth + 92,
          ),
          itemBuilder: (_, index) => ProductCard(product: products[index]),
        );
      },
    );
  }
}
