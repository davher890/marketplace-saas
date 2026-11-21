import 'order.dart';

/// Period shown on the admin "Resumen" page.
enum SummaryPeriod {
  month('Este mes'),
  quarter('Últimos 3 meses'),
  year('Este año'),
  all('Todo');

  const SummaryPeriod(this.label);

  final String label;
}

/// Ways of listing orders in the admin panel: still being worked on,
/// finished, or not paid yet (whatever their status, except cancelled).
enum OrderView {
  open('En curso', 'en-curso', [
    OrderStatus.received,
    OrderStatus.processing,
    OrderStatus.shipped,
  ]),
  closed('Históricos', 'historicos', [
    OrderStatus.delivered,
    OrderStatus.cancelled,
  ]),
  unpaid('Sin pagar', 'sin-pagar', [
    OrderStatus.received,
    OrderStatus.processing,
    OrderStatus.shipped,
    OrderStatus.delivered,
  ], paid: false);

  const OrderView(this.label, this.urlValue, this.statuses, {this.paid});

  final String label;

  /// Value of the `vista` query parameter in the admin orders URL.
  final String urlValue;
  final List<OrderStatus> statuses;

  /// Only paid (`true`) or unpaid (`false`) orders; `null` for both.
  final bool? paid;

  static OrderView fromUrl(String? value) =>
      values.firstWhere((v) => v.urlValue == value, orElse: () => open);

  /// The in progress / finished view a status belongs to.
  static OrderView of(OrderStatus status) =>
      closed.statuses.contains(status) ? closed : open;
}

class MonthSummary {
  const MonthSummary({
    required this.month,
    required this.orders,
    required this.sold,
    required this.cancelled,
    required this.revenueCents,
  });

  factory MonthSummary.fromJson(Map<String, dynamic> json) => MonthSummary(
    month: json['month'] as String,
    orders: json['orders'] as int,
    sold: json['sold'] as int,
    cancelled: json['cancelled'] as int,
    revenueCents: json['revenue_cents'] as int,
  );

  /// "2026-11".
  final String month;
  final int orders;
  final int sold;
  final int cancelled;
  final int revenueCents;

  static const _monthNames = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  /// "Noviembre 2026".
  String get label {
    final [year, number] = month.split('-');
    final name = _monthNames[int.parse(number) - 1];
    return '${name[0].toUpperCase()}${name.substring(1)} $year';
  }
}

class TopProduct {
  const TopProduct({
    required this.name,
    required this.quantity,
    required this.revenueCents,
  });

  factory TopProduct.fromJson(Map<String, dynamic> json) => TopProduct(
    name: json['name'] as String,
    quantity: json['quantity'] as int,
    revenueCents: json['revenue_cents'] as int,
  );

  final String name;
  final int quantity;
  final int revenueCents;
}

/// Figures for the admin "Resumen" page, computed by the API.
class OrderStats {
  const OrderStats({
    required this.byStatus,
    required this.unpaidOrders,
    required this.unpaidCents,
    required this.orders,
    required this.sold,
    required this.delivered,
    required this.cancelled,
    required this.revenueCents,
    required this.averageCents,
    required this.pickup,
    required this.shipping,
    required this.months,
    required this.topProducts,
  });

  factory OrderStats.fromJson(Map<String, dynamic> json) {
    final byStatus = json['by_status'] as Map<String, dynamic>;
    final totals = json['totals'] as Map<String, dynamic>;
    final unpaid = json['unpaid'] as Map<String, dynamic>? ?? const {};
    return OrderStats(
      byStatus: {
        for (final status in OrderStatus.values)
          status: (byStatus[status.name] as int?) ?? 0,
      },
      unpaidOrders: unpaid['orders'] as int? ?? 0,
      unpaidCents: unpaid['total_cents'] as int? ?? 0,
      orders: totals['orders'] as int,
      sold: totals['sold'] as int,
      delivered: totals['delivered'] as int,
      cancelled: totals['cancelled'] as int,
      revenueCents: totals['revenue_cents'] as int,
      averageCents: totals['average_cents'] as int,
      pickup: totals['pickup'] as int,
      shipping: totals['shipping'] as int,
      months: [
        for (final month in json['months'] as List)
          MonthSummary.fromJson(month as Map<String, dynamic>),
      ],
      topProducts: [
        for (final product in json['top_products'] as List)
          TopProduct.fromJson(product as Map<String, dynamic>),
      ],
    );
  }

  /// Current number of orders in each status, whatever the period.
  final Map<OrderStatus, int> byStatus;

  /// Orders not cancelled and not paid yet, and what they add up to,
  /// whatever the period.
  final int unpaidOrders;
  final int unpaidCents;

  // The rest is about orders placed in the chosen period.
  final int orders;

  /// Marked paid and not cancelled: the ones counted in [revenueCents].
  final int sold;
  final int delivered;
  final int cancelled;
  final int revenueCents;
  final int averageCents;
  final int pickup;
  final int shipping;

  /// Newest first.
  final List<MonthSummary> months;
  final List<TopProduct> topProducts;
}
