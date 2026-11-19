import '../core/money.dart';

class ShopSettings {
  const ShopSettings({
    required this.shippingFlatCents,
    this.shippingMadridCents,
    this.freeShippingThresholdCents,
    this.contactEmail,
    this.contactPhone,
  });

  /// Shipping outside Madrid (and to Madrid when there's no Madrid rate).
  final int shippingFlatCents;

  /// Shipping to Madrid postal codes (28xxx); `null` = [shippingFlatCents].
  final int? shippingMadridCents;

  /// `null` disables free shipping.
  final int? freeShippingThresholdCents;
  final String? contactEmail;
  final String? contactPhone;

  static const fallback = ShopSettings(shippingFlatCents: 0);

  /// Mirrors `shippingFor` in the API (the source of truth): free when picked
  /// up or above the threshold, otherwise the Madrid rate for 28xxx postal
  /// codes or the normal rate.
  int shippingFor(
    int subtotalCents, {
    bool pickup = false,
    String? postalCode,
  }) {
    if (pickup) return 0;
    final threshold = freeShippingThresholdCents;
    if (threshold != null && subtotalCents >= threshold) return 0;
    final madrid = shippingMadridCents;
    if (madrid != null && isMadridPostalCode(postalCode)) return madrid;
    return shippingFlatCents;
  }

  factory ShopSettings.fromJson(Map<String, dynamic> json) => ShopSettings(
    shippingFlatCents: json['shipping_flat_cents'] as int? ?? 0,
    shippingMadridCents: json['shipping_madrid_cents'] as int?,
    freeShippingThresholdCents: json['free_shipping_threshold_cents'] as int?,
    contactEmail: json['contact_email'] as String?,
    contactPhone: json['contact_phone'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'shipping_flat_cents': shippingFlatCents,
    'shipping_madrid_cents': shippingMadridCents,
    'free_shipping_threshold_cents': freeShippingThresholdCents,
    'contact_email': contactEmail,
    'contact_phone': contactPhone,
  };
}

/// Spanish postal code: five digits, the first two the province (01-52),
/// e.g. 28010. Mirrors `isSpanishPostalCode` in the API.
bool isSpanishPostalCode(String? postalCode) => RegExp(
  r'^(0[1-9]|[1-4]\d|5[0-2])\d{3}$',
).hasMatch((postalCode ?? '').replaceAll(' ', ''));

/// Postal codes of the Madrid province start with 28 (28001-28999).
bool isMadridPostalCode(String? postalCode) =>
    RegExp(r'^28\d{3}$').hasMatch((postalCode ?? '').replaceAll(' ', ''));

/// E.g. "Madrid 5,00 € · Resto de España 6,00 € · Recogida en tienda gratis".
String shippingRatesText(ShopSettings settings, {bool withPickup = true}) {
  final madrid = settings.shippingMadridCents;
  return [
    if (madrid != null) 'Madrid ${formatCents(madrid)}',
    '${madrid != null ? 'Resto de España' : 'Envío'} '
        '${formatCents(settings.shippingFlatCents)}',
    if (withPickup) 'Recogida en tienda gratis',
  ].join(' · ');
}
