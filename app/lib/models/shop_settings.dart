class ShopSettings {
  const ShopSettings({
    required this.shippingFlatCents,
    this.freeShippingThresholdCents,
    this.contactEmail,
    this.contactPhone,
  });

  final int shippingFlatCents;

  /// `null` disables free shipping.
  final int? freeShippingThresholdCents;
  final String? contactEmail;
  final String? contactPhone;

  static const fallback = ShopSettings(shippingFlatCents: 0);

  /// Mirrors the rule in the `place_order` SQL function (the source of truth).
  int shippingFor(int subtotalCents) {
    final threshold = freeShippingThresholdCents;
    if (threshold != null && subtotalCents >= threshold) return 0;
    return shippingFlatCents;
  }

  factory ShopSettings.fromJson(Map<String, dynamic> json) => ShopSettings(
    shippingFlatCents: json['shipping_flat_cents'] as int? ?? 0,
    freeShippingThresholdCents: json['free_shipping_threshold_cents'] as int?,
    contactEmail: json['contact_email'] as String?,
    contactPhone: json['contact_phone'] as String?,
  );

  Map<String, dynamic> toRow() => {
    'shipping_flat_cents': shippingFlatCents,
    'free_shipping_threshold_cents': freeShippingThresholdCents,
    'contact_email': contactEmail,
    'contact_phone': contactPhone,
  };
}
