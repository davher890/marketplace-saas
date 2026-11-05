import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/providers.dart';
import '../../models/cart.dart';
import '../../repositories/cart_repository.dart';
import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final cart = ref.watch(cartProvider);

    return ContentWidth(
      maxWidth: 900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Tu carrito'),
          if (user == null)
            Center(
              child: FilledButton(
                onPressed: () => context.go('/login?from=/cart'),
                child: const Text('Inicia sesión para ver tu carrito'),
              ),
            )
          else
            AsyncView(
              value: cart,
              onRetry: () => ref.invalidate(cartProvider),
              builder: (cart) => cart.isEmpty
                  ? Center(
                      child: Column(
                        children: [
                          const Text('Tu carrito está vacío.'),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () => context.go('/'),
                            child: const Text('Seguir comprando'),
                          ),
                        ],
                      ),
                    )
                  : _CartContent(cart: cart),
            ),
        ],
      ),
    );
  }
}

class _CartContent extends ConsumerWidget {
  const _CartContent({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shopSettingsProvider).value;
    final shipping = settings?.shippingFor(cart.subtotalCents) ?? 0;
    final threshold = settings?.freeShippingThresholdCents;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Column(
            children: [
              for (final item in cart.items) ...[
                _CartLine(item: item),
                if (item != cart.items.last) const Divider(height: 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _SummaryRow('Subtotal', formatCents(cart.subtotalCents)),
                _SummaryRow(
                  'Envío (estimado)',
                  shipping == 0 ? 'Gratis' : formatCents(shipping),
                ),
                if (threshold != null && cart.subtotalCents < threshold)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Te faltan ${formatCents(threshold - cart.subtotalCents)} para el envío gratis',
                      style: textTheme.bodySmall,
                    ),
                  ),
                const Divider(height: 24),
                _SummaryRow(
                  'Total',
                  formatCents(cart.subtotalCents + shipping),
                  bold: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.go('/checkout'),
                    child: const Text('Finalizar compra'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    final maxQuantity = item.variant.stock ?? 99;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (context.mounted) showMessage(context, describeError(error));
      }
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox.square(
              dimension: 72,
              child: ProductImageView(url: item.product.coverUrl),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.push('/product/${item.product.slug}'),
                  child: Text(
                    item.product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (item.product.hasOptions) Text(item.variant.label),
                if (item.customization.isNotEmpty)
                  Text('"${item.customization}"'),
                Text(formatCents(item.unitPriceCents)),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                run(() => notifier.updateQuantity(item.id, item.quantity - 1)),
            icon: const Icon(Icons.remove),
          ),
          Text('${item.quantity}'),
          IconButton(
            onPressed: item.quantity < maxQuantity
                ? () => run(
                    () => notifier.updateQuantity(item.id, item.quantity + 1),
                  )
                : null,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: () => run(() => notifier.remove(item.id)),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      fontSize: bold ? 18 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
