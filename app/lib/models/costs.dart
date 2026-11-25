import '../core/money.dart';

/// Size of the box a product is packed in; each size has its price in
/// Ajustes. One box per article of an order.
enum BoxSize {
  s('S'),
  m('M'),
  l('L');

  const BoxSize(this.apiName);

  final String apiName;

  static BoxSize? fromApi(String? name) =>
      values.where((size) => size.apiName == name).firstOrNull;
}

/// Price of each box size (Ajustes → Costes).
class CostSettings {
  const CostSettings({
    required this.boxSCents,
    required this.boxMCents,
    required this.boxLCents,
  });

  final int boxSCents;
  final int boxMCents;
  final int boxLCents;

  int priceOf(BoxSize size) => switch (size) {
    BoxSize.s => boxSCents,
    BoxSize.m => boxMCents,
    BoxSize.l => boxLCents,
  };

  factory CostSettings.fromJson(Map<String, dynamic> json) => CostSettings(
    boxSCents: json['box_s_cents'] as int,
    boxMCents: json['box_m_cents'] as int,
    boxLCents: json['box_l_cents'] as int,
  );

  Map<String, dynamic> toJson() => {
    'box_s_cents': boxSCents,
    'box_m_cents': boxMCents,
    'box_l_cents': boxLCents,
  };
}

/// Who the shop buys from, and what picking an order up from them costs.
class Supplier {
  const Supplier({
    required this.name,
    required this.transportCents,
    this.id,
    this.products = 0,
  });

  final String? id;
  final String name;
  final int transportCents;

  /// Products that have it as their supplier.
  final int products;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: json['id'] as String?,
    name: json['name'] as String,
    transportCents: json['transport_cents'] as int,
    products: json['products'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'transport_cents': transportCents,
  };
}

/// What one article of an order cost the shop.
class OrderItemCost {
  const OrderItemCost({
    required this.orderItemId,
    required this.quantity,
    required this.lineCostCents,
    this.unitCostCents,
    this.boxSize,
    this.boxCents = 0,
    this.supplierName,
    this.estimated = false,
  });

  final String orderItemId;
  final int quantity;

  /// `null`: the product has no cost.
  final int? unitCostCents;
  final BoxSize? boxSize;
  final int boxCents;
  final String? supplierName;

  /// Unit cost × quantity + the box.
  final int lineCostCents;

  /// Worked out with today's costs (the order is older than the costs).
  final bool estimated;

  /// "3 × 2,00 € + caja M 0,50 €"; "Sin coste" when the product has none.
  String get breakdown {
    final parts = [
      if (unitCostCents == null)
        'Sin coste'
      else
        '$quantity × ${formatCents(unitCostCents!)}',
      if (boxSize != null) 'caja ${boxSize!.apiName} ${formatCents(boxCents)}',
    ];
    return parts.join(' + ');
  }

  factory OrderItemCost.fromJson(Map<String, dynamic> json) => OrderItemCost(
    orderItemId: json['order_item_id'] as String,
    quantity: json['quantity'] as int,
    lineCostCents: json['line_cost_cents'] as int,
    unitCostCents: json['unit_cost_cents'] as int?,
    boxSize: BoxSize.fromApi(json['box_size'] as String?),
    boxCents: json['box_cents'] as int? ?? 0,
    supplierName: json['supplier_name'] as String?,
    estimated: json['estimated'] as bool? ?? false,
  );
}

/// What an order cost the shop: its articles and each supplier's transport
/// once (admin only).
class OrderCosts {
  const OrderCosts({
    required this.items,
    required this.suppliers,
    required this.itemsCostCents,
    required this.transportCents,
    required this.totalCostCents,
    this.missingCosts = false,
    this.estimated = false,
  });

  final List<OrderItemCost> items;
  final List<({String name, int transportCents})> suppliers;
  final int itemsCostCents;
  final int transportCents;
  final int totalCostCents;

  /// Some article has no cost, so the total falls short.
  final bool missingCosts;

  /// Some article was worked out with today's costs.
  final bool estimated;

  OrderItemCost? forItem(String orderItemId) =>
      items.where((item) => item.orderItemId == orderItemId).firstOrNull;

  factory OrderCosts.fromJson(Map<String, dynamic> json) => OrderCosts(
    items: [
      for (final item in json['items'] as List)
        OrderItemCost.fromJson(item as Map<String, dynamic>),
    ],
    suppliers: [
      for (final s in json['suppliers'] as List)
        (
          name: (s as Map<String, dynamic>)['name'] as String,
          transportCents: s['transport_cents'] as int,
        ),
    ],
    itemsCostCents: json['items_cost_cents'] as int,
    transportCents: json['transport_cents'] as int,
    totalCostCents: json['total_cost_cents'] as int,
    missingCosts: json['missing_costs'] as bool? ?? false,
    estimated: json['estimated'] as bool? ?? false,
  );
}
