import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/online_payment.dart';
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

/// How the customer came back from Stripe's payment page (`?pago=`).
enum PaymentReturn {
  none,
  succeeded,
  cancelled;

  static PaymentReturn fromUrl(String? value) => switch (value) {
    'ok' => succeeded,
    'cancelado' => cancelled,
    _ => none,
  };
}

class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.justPlaced = false,
    this.paymentReturn = PaymentReturn.none,
  });

  final String orderId;
  final bool justPlaced;
  final PaymentReturn paymentReturn;

  /// After paying, Stripe's confirmation may take a few seconds to reach the
  /// API: reload the order this often until it shows as paid...
  static const pollInterval = Duration(seconds: 2);

  /// ...at most this many times.
  static const maxPolls = 15;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Timer? _poll;
  bool _paying = false;

  String get orderId => widget.orderId;

  @override
  void initState() {
    super.initState();
    if (widget.paymentReturn == PaymentReturn.succeeded) {
      _poll = Timer.periodic(OrderDetailScreen.pollInterval, (timer) {
        final paid = ref.read(orderProvider(orderId)).value?.isPaid ?? false;
        if (paid || timer.tick > OrderDetailScreen.maxPolls) {
          timer.cancel();
          if (paid) ref.invalidate(myOrdersProvider);
          return;
        }
        ref.invalidate(orderProvider(orderId));
      });
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _pay(Order order) async {
    setState(() => _paying = true);
    try {
      await payOnline(ref, order.id);
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _cancel(Order order) async {
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
      if (mounted) showMessage(context, describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(orderId));
    final canPayOnline = ref.watch(canPayOnlineProvider).value ?? false;

    return ContentWidth(
      maxWidth: 800,
      child: AsyncView(
        // Keep the page while it reloads to check the payment.
        value: order.hasValue ? AsyncData(order.value) : order,
        onRetry: () => ref.invalidate(orderProvider(orderId)),
        builder: (order) {
          if (order == null) {
            return const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('Pedido no encontrado.')),
            );
          }
          final payable =
              canPayOnline &&
              !order.isPaid &&
              order.status != OrderStatus.cancelled;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle('Pedido #${order.orderNumber}'),
              if (widget.paymentReturn == PaymentReturn.succeeded)
                Card(
                  child: ListTile(
                    leading: order.isPaid
                        ? const Icon(Icons.check_circle_outline)
                        : const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                    title: Text(
                      order.isPaid
                          ? '¡Pago recibido, gracias!'
                          : 'Estamos confirmando tu pago…',
                    ),
                    subtitle: Text(
                      order.isPaid
                          ? 'Te hemos enviado la confirmación por email.'
                          : 'Puede tardar unos segundos.',
                    ),
                  ),
                )
              else if (widget.paymentReturn == PaymentReturn.cancelled &&
                  !order.isPaid)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('No se ha completado el pago'),
                    subtitle: Text(
                      'Tu pedido está guardado. Puedes pagarlo cuando quieras.',
                    ),
                  ),
                )
              else if (widget.justPlaced)
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OrderStatusChip(order.status),
                  if (order.status != OrderStatus.cancelled)
                    PaymentChip(paid: order.isPaid),
                ],
              ),
              if (payable) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _paying ? null : () => _pay(order),
                  icon: const Icon(Icons.credit_card),
                  label: Text('Pagar ahora · ${formatCents(order.totalCents)}'),
                ),
              ],
              const SizedBox(height: 16),
              OrderSummary(order: order),
              if (order.canCustomerCancel) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => _cancel(order),
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
