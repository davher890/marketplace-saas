import 'product.dart';

/// A cart line with its variant and product nested, as returned by the API.
class CartItem {
  const CartItem({
    required this.id,
    required this.quantity,
    required this.customization,
    required this.variant,
    required this.product,
  });

  final String id;
  final int quantity;
  final String customization;
  final ProductVariant variant;
  final Product product;

  int get unitPriceCents => product.priceOf(variant);
  int get lineTotalCents => unitPriceCents * quantity;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final variantJson = Map<String, dynamic>.from(
      json['product_variants'] as Map,
    );
    final productJson = Map<String, dynamic>.from(
      variantJson.remove('products') as Map,
    );
    return CartItem(
      id: json['id'] as String,
      quantity: json['quantity'] as int,
      customization: json['customization'] as String? ?? '',
      variant: ProductVariant.fromJson(variantJson),
      product: Product.fromJson(productJson),
    );
  }
}

class Cart {
  const Cart(this.items);

  final List<CartItem> items;

  static const empty = Cart([]);

  /// Parses `GET /api/cart`. Totals are recomputed from the lines; shipping
  /// is estimated in the UI from the shop settings.
  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
    (json['items'] as List)
        .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
  int get subtotalCents =>
      items.fold(0, (sum, item) => sum + item.lineTotalCents);
}
