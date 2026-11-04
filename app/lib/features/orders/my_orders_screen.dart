import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/order.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/common.dart';
import 'order_widgets.dart';

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);
    return ContentWidth(
      maxWidth: 800,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Mis pedidos'),
          AsyncView(
            value: orders,
            onRetry: () => ref.invalidate(myOrdersProvider),
            builder: (orders) => orders.isEmpty
                ? const Center(child: Text('Aún no has hecho ningún pedido.'))
                : Column(
                    children: [
                      for (final order in orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OrderTile(
                            order: order,
                            onTap: () => context.push('/orders/${order.id}'),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.justPlaced = false,
  });

  final String orderId;
  final bool justPlaced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));

    Future<void> cancel(Order order) async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('¿Cancelar el pedido #${order.orderNumber}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí, cancelar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref.read(orderRepositoryProvider).cancel(order.id);
        ref.invalidate(orderProvider(orderId));
        ref.invalidate(myOrdersProvider);
      } catch (error) {
        if (context.mounted) showMessage(context, describeError(error));
      }
    }

    return ContentWidth(
      maxWidth: 800,
      child: AsyncView(
        value: order,
        onRetry: () => ref.invalidate(orderProvider(orderId)),
        builder: (order) {
          if (order == null) {
            return const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('Pedido no encontrado.')),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle('Pedido #${order.orderNumber}'),
              if (justPlaced)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('¡Gracias por tu pedido!'),
                    subtitle: Text(
                      'Te escribiremos pronto para confirmar el pago y el envío.',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: OrderStatusChip(order.status),
              ),
              const SizedBox(height: 16),
              OrderSummary(order: order),
              if (order.status == OrderStatus.pending) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => cancel(order),
                  child: const Text('Cancelar pedido'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
