enum OrderStatus {
  pending('Pendiente de pago'),
  paid('Pagado'),
  processing('En preparación'),
  shipped('Enviado'),
  delivered('Entregado'),
  cancelled('Cancelado');

  const OrderStatus(this.label);

  /// Spanish label shown in the UI.
  final String label;

  static OrderStatus fromName(String name) => OrderStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => OrderStatus.pending,
  );
}

class ShippingAddress {
  const ShippingAddress({
    required this.line1,
    required this.city,
    required this.postalCode,
    this.line2 = '',
    this.province = '',
    this.country = 'ES',
  });

  final String line1;
  final String line2;
  final String city;
  final String postalCode;
  final String province;
  final String country;

  factory ShippingAddress.fromJson(Map<String, dynamic> json) =>
      ShippingAddress(
        line1: json['line1'] as String? ?? '',
        line2: json['line2'] as String? ?? '',
        city: json['city'] as String? ?? '',
        postalCode: json['postal_code'] as String? ?? '',
        province: json['province'] as String? ?? '',
        country: json['country'] as String? ?? 'ES',
      );

  Map<String, dynamic> toJson() => {
    'line1': line1,
    'line2': line2,
    'city': city,
    'postal_code': postalCode,
    'province': province,
    'country': country,
  };

  List<String> get lines => [
    line1,
    if (line2.isNotEmpty) line2,
    '$postalCode $city',
    if (province.isNotEmpty) province,
    country,
  ];
}

class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.subtotalCents,
    required this.shippingCents,
    required this.totalCents,
    required this.shippingName,
    required this.shippingAddress,
    required this.createdAt,
    this.userId,
    this.contactEmail,
    this.shippingPhone,
    this.customerNotes,
    this.adminNotes,
    this.items = const [],
    this.history = const [],
  });

  final String id;
  final int orderNumber;
  final String? userId;
  final OrderStatus status;
  final int subtotalCents;
  final int shippingCents;
  final int totalCents;
  final String? contactEmail;
  final String shippingName;
  final String? shippingPhone;
  final ShippingAddress shippingAddress;
  final String? customerNotes;
  final String? adminNotes;
  final DateTime createdAt;
  final List<OrderItem> items;
  final List<OrderStatusChange> history;

  static const listSelectQuery = '*, order_items(*)';
  static const detailSelectQuery = '*, order_items(*), order_status_history(*)';

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  factory Order.fromJson(Map<String, dynamic> json) => Order(
    id: json['id'] as String,
    orderNumber: json['order_number'] as int,
    userId: json['user_id'] as String?,
    status: OrderStatus.fromName(json['status'] as String),
    subtotalCents: json['subtotal_cents'] as int,
    shippingCents: json['shipping_cents'] as int,
    totalCents: json['total_cents'] as int,
    contactEmail: json['contact_email'] as String?,
    shippingName: json['shipping_name'] as String,
    shippingPhone: json['shipping_phone'] as String?,
    shippingAddress: ShippingAddress.fromJson(
      Map<String, dynamic>.from(json['shipping_address'] as Map? ?? {}),
    ),
    customerNotes: json['customer_notes'] as String?,
    adminNotes: json['admin_notes'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    items: (json['order_items'] as List? ?? [])
        .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    history:
        (json['order_status_history'] as List? ?? [])
            .map((e) => OrderStatusChange.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );
}

class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.variantName,
    required this.unitPriceCents,
    required this.quantity,
    required this.lineTotalCents,
    this.sku,
    this.customization = '',
  });

  final String id;
  final String productName;
  final String variantName;
  final String? sku;
  final int unitPriceCents;
  final int quantity;
  final int lineTotalCents;
  final String customization;

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    id: json['id'] as String,
    productName: json['product_name'] as String,
    variantName: json['variant_name'] as String,
    sku: json['sku'] as String?,
    unitPriceCents: json['unit_price_cents'] as int,
    quantity: json['quantity'] as int,
    lineTotalCents: json['line_total_cents'] as int,
    customization: json['customization'] as String? ?? '',
  );
}

class OrderStatusChange {
  const OrderStatusChange({
    required this.toStatus,
    required this.createdAt,
    this.fromStatus,
  });

  final OrderStatus? fromStatus;
  final OrderStatus toStatus;
  final DateTime createdAt;

  factory OrderStatusChange.fromJson(Map<String, dynamic> json) =>
      OrderStatusChange(
        fromStatus: json['from_status'] == null
            ? null
            : OrderStatus.fromName(json['from_status'] as String),
        toStatus: OrderStatus.fromName(json['to_status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
