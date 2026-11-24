import '../core/money.dart';

/// How many times a coupon can be used.
enum CouponUsage {
  oncePerUser('once_per_user', 'Una vez por usuario'),
  oncePerOrder('once_per_order', 'Una vez por compra');

  const CouponUsage(this.apiName, this.label);

  final String apiName;
  final String label;

  static CouponUsage fromApi(String? name) =>
      values.firstWhere((u) => u.apiName == name, orElse: () => oncePerOrder);
}

/// What the coupon takes off the order.
enum DiscountType {
  amount('amount', 'Importe (€)'),
  percent('percent', 'Porcentaje (%)'),
  freeShipping('free_shipping', 'Envío gratis');

  const DiscountType(this.apiName, this.label);

  final String apiName;
  final String label;

  static DiscountType fromApi(String? name) =>
      values.firstWhere((t) => t.apiName == name, orElse: () => amount);
}

/// Whether a coupon can be used today (worked out by the API).
enum CouponStatus {
  active('Activo'),
  scheduled('Programado'),
  expired('Caducado'),
  disabled('Desactivado');

  const CouponStatus(this.label);

  final String label;

  static CouponStatus fromApi(String? name) =>
      values.asNameMap()[name] ?? disabled;
}

/// A discount coupon. The admin list fills every field; the one the checkout
/// gets after applying a code only has the code, description and discount.
class Coupon {
  const Coupon({
    required this.code,
    required this.discountType,
    this.id,
    this.description = '',
    this.startsOn,
    this.endsOn,
    this.usage = CouponUsage.oncePerOrder,
    this.amountCents,
    this.percent,
    this.isActive = true,
    this.status = CouponStatus.active,
    this.uses = 0,
  });

  final String? id;
  final String code;
  final String description;

  /// First and last day it can be used (both included), Spain's calendar.
  final DateTime? startsOn;
  final DateTime? endsOn;
  final CouponUsage usage;
  final DiscountType discountType;
  final int? amountCents;
  final int? percent;
  final bool isActive;
  final CouponStatus status;

  /// Orders (not cancelled) that used it.
  final int uses;

  /// "5,00 €", "10 %" or "Envío gratis".
  String get valueLabel => switch (discountType) {
    DiscountType.amount => '-${formatCents(amountCents ?? 0)}',
    DiscountType.percent => '-${percent ?? 0} %',
    DiscountType.freeShipping => 'Envío gratis',
  };

  /// What it takes off an order of [subtotalCents] products and
  /// [shippingCents]: the same rule the API applies when the order is placed
  /// (off the final price, never below 0).
  int discountFor(int subtotalCents, int shippingCents) {
    final total = subtotalCents + shippingCents;
    final discount = switch (discountType) {
      DiscountType.amount => amountCents ?? 0,
      DiscountType.percent => (total * (percent ?? 0) / 100).round(),
      DiscountType.freeShipping => shippingCents,
    };
    return discount.clamp(0, total);
  }

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
    id: json['id'] as String?,
    code: json['code'] as String,
    description: json['description'] as String? ?? '',
    startsOn: _date(json['starts_on']),
    endsOn: _date(json['ends_on']),
    usage: CouponUsage.fromApi(json['usage'] as String?),
    discountType: DiscountType.fromApi(json['discount_type'] as String?),
    amountCents: json['amount_cents'] as int?,
    percent: json['percent'] as int?,
    isActive: json['is_active'] as bool? ?? true,
    status: CouponStatus.fromApi(json['status'] as String?),
    uses: json['uses'] as int? ?? 0,
  );

  /// Body for creating or updating it in the admin API.
  Map<String, dynamic> toJson() => {
    'code': code,
    'description': description,
    'starts_on': apiDate(startsOn!),
    'ends_on': apiDate(endsOn!),
    'usage': usage.apiName,
    'discount_type': discountType.apiName,
    'amount_cents': discountType == DiscountType.amount ? amountCents : null,
    'percent': discountType == DiscountType.percent ? percent : null,
    'is_active': isActive,
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

/// "2026-11-24", the API's date format.
String apiDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
