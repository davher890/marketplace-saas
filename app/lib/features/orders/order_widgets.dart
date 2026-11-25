import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/costs.dart';
import '../../models/order.dart';
import '../../widgets/common.dart';

final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

/// One row in an order list (customer and admin).
class OrderTile extends StatelessWidget {
  const OrderTile({
    super.key,
    required this.order,
    required this.onTap,
    this.showCustomer = false,
  });

  final Order order;
  final VoidCallback onTap;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      dateFormat.format(order.createdAt),
      '${order.itemCount} artículo${order.itemCount == 1 ? '' : 's'}',
      if (showCustomer) order.shippingName,
    ].join(' · ');

    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(
          'Pedido #${order.orderNumber}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            // Cancelled orders don't need paying.
            if (order.status != OrderStatus.cancelled) ...[
              const SizedBox(height: 6),
              PaymentChip(paid: order.isPaid),
            ],
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatCents(order.totalCents),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            OrderStatusChip(order.status),
          ],
        ),
      ),
    );
  }
}

/// Lines, totals, shipping data and status timeline of an order. With
/// [costs] (admin only) each article shows its cost, and the total cost
/// goes under the total.
class OrderSummary extends StatelessWidget {
  const OrderSummary({super.key, required this.order, this.costs});

  final Order order;
  final OrderCosts? costs;

  /// "Coste total" and what it's made of: articles with their boxes, and
  /// each supplier's transport once.
  List<Widget> _costLines(BuildContext context, OrderCosts costs) {
    final small = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: AppColors.cocoa);
    Widget line(String label, String value, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
    return [
      const SizedBox(height: 8),
      line(
        'Coste total',
        formatCents(costs.totalCostCents),
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.cocoa,
        ),
      ),
      line(
        'Artículos y cajas',
        formatCents(costs.itemsCostCents),
        style: small,
      ),
      for (final supplier in costs.suppliers)
        line(
          'Transporte (${supplier.name})',
          formatCents(supplier.transportCents),
          style: small,
        ),
      if (costs.missingCosts)
        Text(
          'Algún artículo no tiene coste: el coste total se queda corto.',
          style: small,
        ),
      if (costs.estimated)
        Text(
          'Pedido anterior a los costes: calculado con los costes actuales.',
          style: small,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget row(String label, String value, {bool bold = false}) {
      final style = TextStyle(
        fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(value, style: style),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Artículos', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final item in order.items) ...[
                  row(
                    '${item.quantity} × ${item.productName}',
                    formatCents(item.lineTotalCents),
                  ),
                  if (item.variantName != 'Default')
                    Text(item.variantName, style: textTheme.bodySmall),
                  if (item.customization.isNotEmpty)
                    Text(
                      'Personalización: "${item.customization}"',
                      style: textTheme.bodySmall,
                    ),
                  if (item.sku != null)
                    Text('SKU ${item.sku}', style: textTheme.bodySmall),
                  if (costs?.forItem(item.id) case final cost?)
                    Text(
                      'Coste: ${formatCents(cost.lineCostCents)}'
                      ' (${cost.breakdown})',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.cocoa,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
                const Divider(height: 24),
                row('Subtotal', formatCents(order.subtotalCents)),
                row(
                  order.isPickup ? 'Recogida en tienda' : 'Envío',
                  order.shippingCents == 0
                      ? 'Gratis'
                      : formatCents(order.shippingCents),
                ),
                if (order.discountCents > 0)
                  row(
                    order.couponCode == null
                        ? 'Descuento'
                        : 'Descuento (${order.couponCode})',
                    '-${formatCents(order.discountCents)}',
                  ),
                row('Total', formatCents(order.totalCents), bold: true),
                if (costs case final costs?) ..._costLines(context, costs),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.isPickup ? 'Recogida en tienda' : 'Envío',
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  order.shippingName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (!order.isPickup)
                  for (final line in order.shippingAddress.lines) Text(line),
                if (order.shippingPhone != null)
                  Text('Tel. ${order.shippingPhone}'),
                if (order.contactEmail != null) Text(order.contactEmail!),
                if (order.customerNotes != null) ...[
                  const SizedBox(height: 8),
                  Text('Notas: ${order.customerNotes}'),
                ],
              ],
            ),
          ),
        ),
        if (order.history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Historial', style: textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final change in order.history)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          OrderStatusChip(change.toStatus),
                          const SizedBox(width: 12),
                          Text(dateFormat.format(change.createdAt)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
