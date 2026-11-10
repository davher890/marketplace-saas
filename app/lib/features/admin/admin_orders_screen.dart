import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/order.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/common.dart';
import '../orders/order_widgets.dart';

class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen> {
  OrderStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(adminOrdersProvider(_filter));

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminOrdersProvider(_filter).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pedidos', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: _filter == null,
                labelStyle: TextStyle(
                  color: _filter == null ? AppColors.cream : AppColors.ink,
                ),
                onSelected: (_) => setState(() => _filter = null),
              ),
              for (final status in OrderStatus.values)
                ChoiceChip(
                  label: Text(status.label),
                  selected: _filter == status,
                  labelStyle: TextStyle(
                    color: _filter == status ? AppColors.cream : AppColors.ink,
                  ),
                  onSelected: (_) => setState(() => _filter = status),
                ),
            ],
          ),
          const SizedBox(height: 16),
          AsyncView(
            value: orders,
            onRetry: () => ref.invalidate(adminOrdersProvider(_filter)),
            builder: (orders) => orders.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No hay pedidos.')),
                  )
                : Column(
                    children: [
                      for (final order in orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OrderTile(
                            order: order,
                            showCustomer: true,
                            onTap: () =>
                                context.go('/admin/orders/${order.id}'),
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

class AdminOrderScreen extends ConsumerStatefulWidget {
  const AdminOrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<AdminOrderScreen> createState() => _AdminOrderScreenState();
}

class _AdminOrderScreenState extends ConsumerState<AdminOrderScreen> {
  final _notes = TextEditingController();
  bool _notesLoaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _refreshLists() {
    ref.invalidate(orderProvider(widget.orderId));
    ref.invalidate(adminOrdersProvider);
  }

  Future<void> _run(
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _saving = true);
    try {
      await action();
      _refreshLists();
      if (mounted) showMessage(context, successMessage);
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(Order order, OrderStatus status) async {
    if (status == order.status) return;
    if (status == OrderStatus.cancelled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('¿Cancelar el pedido #${order.orderNumber}?'),
          content: const Text('Se devolverá el stock de los productos.'),
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
    }
    await _run(
      () => ref.read(orderRepositoryProvider).updateStatus(order.id, status),
      'Estado actualizado: ${status.label}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = ref.watch(orderProvider(widget.orderId));

    return AsyncView(
      value: order,
      onRetry: () => ref.invalidate(orderProvider(widget.orderId)),
      builder: (order) {
        if (order == null) {
          return const Center(child: Text('Pedido no encontrado.'));
        }
        if (!_notesLoaded) {
          _notes.text = order.adminNotes ?? '';
          _notesLoaded = true;
        }
        final isCancelled = order.status == OrderStatus.cancelled;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.go('/admin/orders'),
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    'Pedido #${order.orderNumber}',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
                _CopyForSupplierButton(order: order),
                const SizedBox(width: 8),
                OrderStatusChip(order.status),
              ],
            ),
            Text(dateFormat.format(order.createdAt)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Cambiar estado',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final status in OrderStatus.values)
                          ChoiceChip(
                            label: Text(status.label),
                            selected: order.status == status,
                            labelStyle: TextStyle(
                              color: order.status == status
                                  ? AppColors.cream
                                  : AppColors.ink,
                            ),
                            // A cancelled order has had its stock restored; keep it final.
                            onSelected: _saving || isCancelled
                                ? null
                                : (_) => _changeStatus(order, status),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notas internas',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _run(
                                () => ref
                                    .read(orderRepositoryProvider)
                                    .updateAdminNotes(
                                      order.id,
                                      _notes.text.trim(),
                                    ),
                                'Notas guardadas',
                              ),
                        child: const Text('Guardar notas'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OrderSummary(order: order),
          ],
        );
      },
    );
  }
}

/// Copies the items to paste to the supplier ([Order.supplierText]). On
/// narrow screens only the icon is shown.
class _CopyForSupplierButton extends StatelessWidget {
  const _CopyForSupplierButton({required this.order});

  final Order order;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: order.supplierText));
    if (context.mounted) {
      showMessage(
        context,
        'Encargo copiado: pégalo en el mensaje al proveedor.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const label = 'Copiar encargo';
    if (MediaQuery.sizeOf(context).width < 600) {
      return IconButton(
        tooltip: label,
        onPressed: () => _copy(context),
        icon: const Icon(Icons.content_paste_go_outlined),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _copy(context),
      icon: const Icon(Icons.content_paste_go_outlined),
      label: const Text(label),
    );
  }
}
