import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/file_saver.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/order_stats.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/common.dart';
import 'admin_orders_screen.dart';

/// Admin "Resumen": orders in progress by status, and figures for past orders
/// (per month, best sellers) over a chosen period.
class AdminSummaryScreen extends ConsumerStatefulWidget {
  const AdminSummaryScreen({super.key});

  @override
  ConsumerState<AdminSummaryScreen> createState() => _AdminSummaryScreenState();
}

class _AdminSummaryScreenState extends ConsumerState<AdminSummaryScreen> {
  SummaryPeriod _period = SummaryPeriod.month;

  /// Last figures received, shown (dimmed) while another period loads so the
  /// page doesn't jump.
  OrderStats? _last;

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(adminOrderStatsProvider(_period));
    if (summary.hasValue) _last = summary.value;
    final reloading = summary.isLoading && !summary.hasValue && _last != null;
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(adminOrderStatsProvider(_period).future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Resumen', style: textTheme.displaySmall),
          const SizedBox(height: 4),
          SizedBox(
            height: 4,
            child: reloading ? const LinearProgressIndicator() : null,
          ),
          const SizedBox(height: 8),
          AsyncView(
            value: reloading ? AsyncData(_last!) : summary,
            onRetry: () => ref.invalidate(adminOrderStatsProvider(_period)),
            builder: (summary) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Heading(
                  'Pedidos en curso',
                  action: TextButton(
                    onPressed: () => context.go(
                      AdminOrdersScreen.location(view: OrderView.open),
                    ),
                    child: const Text('Ver todos'),
                  ),
                ),
                _OpenOrders(summary),
                const SizedBox(height: 32),
                _Heading(
                  'Histórico',
                  action: TextButton(
                    onPressed: () => context.go(
                      AdminOrdersScreen.location(view: OrderView.closed),
                    ),
                    child: const Text('Ver pedidos históricos'),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final period in SummaryPeriod.values)
                      ChoiceChip(
                        label: Text(period.label),
                        selected: _period == period,
                        labelStyle: TextStyle(
                          color: _period == period
                              ? AppColors.cream
                              : AppColors.ink,
                        ),
                        onSelected: (_) => setState(() => _period = period),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (summary.orders == 0)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay pedidos en este periodo.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else ...[
                  _Totals(summary),
                  const SizedBox(height: 24),
                  Text('Por mes', style: textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _MonthsTable(summary.months),
                  if (summary.topProducts.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Más vendidos', style: textTheme.titleLarge),
                    const SizedBox(height: 8),
                    _TopProducts(summary.topProducts),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.action});

  final String text;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(text, style: Theme.of(context).textTheme.headlineSmall),
          action,
        ],
      ),
    );
  }
}

/// One card per status still in progress, plus the unpaid orders; each opens
/// the filtered list.
class _OpenOrders extends StatelessWidget {
  const _OpenOrders(this.stats);

  final OrderStats stats;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final status in OrderView.open.statuses)
        _CountCard(
          color: OrderStatusChip.colorOf(status),
          label: status.label,
          count: stats.byStatus[status]!,
          location: AdminOrdersScreen.location(status: status),
        ),
      _CountCard(
        color: PaymentChip.unpaidColor,
        label: 'Sin pagar',
        count: stats.unpaidOrders,
        note: formatCents(stats.unpaidCents),
        location: AdminOrdersScreen.location(view: OrderView.unpaid),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        // Four in a row on wide screens, two on phones.
        final perRow = constraints.maxWidth >= 640 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({
    required this.color,
    required this.label,
    required this.count,
    required this.location,
    this.note,
  });

  final Color color;
  final String label;
  final int count;
  final String location;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: () => context.go(location),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 6)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$count',
                    style: textTheme.headlineMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        note!,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.cocoa,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(label, style: textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Key figures for the period.
class _Totals extends StatelessWidget {
  const _Totals(this.summary);

  final OrderStats summary;

  @override
  Widget build(BuildContext context) {
    final figures = [
      (
        label: 'Facturado',
        value: formatCents(summary.revenueCents),
        note:
            '${summary.sold} ${summary.sold == 1 ? 'pedido pagado' : 'pedidos pagados'}',
      ),
      (
        label: 'Pedido medio',
        value: formatCents(summary.averageCents),
        note: 'de los pagados',
      ),
      (
        label: 'Pedidos',
        value: '${summary.orders}',
        note: 'Envío ${summary.shipping} · Recogida ${summary.pickup}',
      ),
      (
        label: 'Entregados',
        value: '${summary.delivered}',
        note: 'Cancelados ${summary.cancelled}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 640 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        final textTheme = Theme.of(context).textTheme;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final figure in figures)
              SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(figure.label, style: textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            figure.value,
                            style: textTheme.headlineSmall?.copyWith(
                              color: AppColors.chocolate,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          figure.note,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.cocoa,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Orders, cancellations and billing per month, each row with a button to
/// download that month's orders as a CSV file (opens in Excel).
class _MonthsTable extends ConsumerStatefulWidget {
  const _MonthsTable(this.months);

  final List<MonthSummary> months;

  @override
  ConsumerState<_MonthsTable> createState() => _MonthsTableState();
}

class _MonthsTableState extends ConsumerState<_MonthsTable> {
  /// Months being downloaded right now.
  final _downloading = <String>{};

  Future<void> _download(MonthSummary month) async {
    setState(() => _downloading.add(month.month));
    try {
      final bytes = await ref
          .read(orderRepositoryProvider)
          .exportMonth(month.month);
      await ref.read(fileSaverProvider)(
        bytes,
        'pedidos-${month.month}.csv',
        'text/csv',
      );
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _downloading.remove(month.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final header = textTheme.labelLarge?.copyWith(color: AppColors.cocoa);

    Widget cell(String text, {TextStyle? style, bool first = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        text,
        style: style,
        textAlign: first ? TextAlign.start : TextAlign.end,
      ),
    );

    return Card(
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(),
          2: FlexColumnWidth(1.2),
          3: FlexColumnWidth(1.6),
          4: FixedColumnWidth(48),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AppColors.cream),
            children: [
              cell('Mes', style: header, first: true),
              cell('Pedidos', style: header),
              cell('Cancel.', style: header),
              cell('Facturado', style: header),
              const SizedBox.shrink(),
            ],
          ),
          for (final month in widget.months)
            TableRow(
              children: [
                cell(month.label, first: true),
                cell('${month.orders}'),
                cell('${month.cancelled}'),
                cell(formatCents(month.revenueCents)),
                _downloading.contains(month.month)
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Descargar los pedidos de ${month.label}',
                        icon: const Icon(Icons.download_outlined),
                        onPressed: () => _download(month),
                      ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts(this.products);

  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (final (index, product) in products.indexed) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.sageLight,
                foregroundColor: AppColors.forest,
                child: Text('${index + 1}'),
              ),
              title: Text(product.name),
              subtitle: Text(
                '${product.quantity} ${product.quantity == 1 ? 'unidad' : 'unidades'}',
              ),
              trailing: Text(formatCents(product.revenueCents)),
            ),
          ],
        ],
      ),
    );
  }
}
