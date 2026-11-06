import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/auth.dart';
import '../../core/theme.dart';
import '../../models/product.dart';
import '../../repositories/cart_repository.dart';
import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';

class ProductScreen extends ConsumerWidget {
  const ProductScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productBySlugProvider(slug));
    return ContentWidth(
      padding: const EdgeInsets.all(16),
      child: AsyncView(
        value: product,
        onRetry: () => ref.invalidate(productBySlugProvider(slug)),
        builder: (product) => product == null
            ? const Padding(
                padding: EdgeInsets.all(48),
                child: Center(
                  child: Text(
                    'Este producto no existe o ya no está disponible.',
                  ),
                ),
              )
            : _ProductDetail(product: product),
      ),
    );
  }
}

class _ProductDetail extends ConsumerStatefulWidget {
  const _ProductDetail({required this.product});

  final Product product;

  @override
  ConsumerState<_ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends ConsumerState<_ProductDetail> {
  ProductVariant? _variant;
  int _quantity = 1;
  int _imageIndex = 0;
  bool _adding = false;
  final _customization = TextEditingController();

  Product get product => widget.product;

  @override
  void initState() {
    super.initState();
    _variant =
        product.activeVariants.where((v) => v.isInStock).firstOrNull ??
        product.activeVariants.firstOrNull;
  }

  @override
  void dispose() {
    _customization.dispose();
    super.dispose();
  }

  int get _maxQuantity {
    final stock = _variant?.stock;
    return stock == null ? 99 : stock.clamp(0, 99);
  }

  Future<void> _addToCart() async {
    final variant = _variant;
    if (variant == null) return;

    if (ref.read(currentUserProvider) == null) {
      final from = GoRouterState.of(context).uri.toString();
      context.go('/login?from=${Uri.encodeComponent(from)}');
      return;
    }

    if (product.isCustomizable && _customization.text.trim().isEmpty) {
      showMessage(
        context,
        'Indica: ${product.customizationLabel ?? 'personalización'}',
      );
      return;
    }

    setState(() => _adding = true);
    try {
      await ref
          .read(cartProvider.notifier)
          .add(
            variant.id,
            quantity: _quantity,
            customization: _customization.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Añadido al carrito'),
          action: SnackBarAction(
            label: 'Ver carrito',
            textColor: AppColors.cream,
            onPressed: () => context.go('/cart'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 800;
    final gallery = _Gallery(
      images: product.images,
      index: _imageIndex,
      onSelect: (i) => setState(() => _imageIndex = i),
    );
    final info = _buildInfo(context);

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: gallery),
              const SizedBox(width: 32),
              Expanded(child: info),
            ],
          )
        : Column(children: [gallery, const SizedBox(height: 24), info]);
  }

  Widget _buildInfo(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final variant = _variant;
    final price = variant == null
        ? product.basePriceCents
        : product.priceOf(variant);
    final soldOut = variant == null || !variant.isInStock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.name, style: textTheme.displaySmall),
        const SizedBox(height: 8),
        Text(formatCents(price), style: textTheme.titleLarge),
        const SizedBox(height: 24),
        if (product.hasOptions) ...[
          Text('Opciones', style: textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in product.activeVariants)
                ChoiceChip(
                  label: Text(v.isInStock ? v.label : '${v.label} (agotado)'),
                  selected: v.id == variant?.id,
                  labelStyle: TextStyle(
                    color: v.id == variant?.id
                        ? AppColors.cream
                        : AppColors.ink,
                  ),
                  onSelected: (_) => setState(() {
                    _variant = v;
                    _quantity = 1;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        if (product.isCustomizable) ...[
          TextField(
            controller: _customization,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: product.customizationLabel ?? 'Personalización',
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            _QuantityStepper(
              value: _quantity,
              max: _maxQuantity,
              onChanged: (q) => setState(() => _quantity = q),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton.icon(
                onPressed: soldOut || _adding ? null : _addToCart,
                icon: _adding
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_shopping_cart),
                label: Text(soldOut ? 'Agotado' : 'Añadir al carrito'),
              ),
            ),
          ],
        ),
        if (variant?.tracksStock ?? false) ...[
          const SizedBox(height: 8),
          Text('Quedan ${variant!.stock} unidades', style: textTheme.bodySmall),
        ] else ...[
          const SizedBox(height: 8),
          Text('Hecho por encargo', style: textTheme.bodySmall),
        ],
        if (product.description != null) ...[
          const SizedBox(height: 24),
          Text(product.description!, style: textTheme.bodyLarge),
        ],
      ],
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.images,
    required this.index,
    required this.onSelect,
  });

  final List<ProductImage> images;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final current = images.isEmpty
        ? null
        : images[index.clamp(0, images.length - 1)].url;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 1,
            child: ProductImageView(url: current),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => onSelect(i),
                child: Container(
                  width: 72,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: i == index ? AppColors.forest : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ProductImageView(url: images[i].url),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
