/// A list the customer picks one value from (e.g. "Color del lazo": Rojo,
/// Azul). Unlike variants it has no price or stock of its own.
class ChoiceField {
  const ChoiceField({required this.label, required this.options});

  final String label;
  final List<String> options;

  factory ChoiceField.fromJson(Map<String, dynamic> json) => ChoiceField(
    label: json['label'] as String,
    options: (json['options'] as List? ?? []).cast<String>(),
  );

  Map<String, dynamic> toJson() => {'label': label, 'options': options};
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.slug,
    required this.basePriceCents,
    this.categoryId,
    this.categoryIds = const [],
    this.description,
    this.isCustomizable = false,
    this.customizationLabel,
    this.choiceFields = const [],
    this.isActive = true,
    this.isFeatured = false,
    this.variants = const [],
    this.images = const [],
  });

  final String id;

  /// Main category: the first of [categoryIds].
  final String? categoryId;

  /// Every category the product is listed in, main one first.
  final List<String> categoryIds;
  final String name;
  final String slug;
  final String? description;
  final int basePriceCents;
  final bool isCustomizable;
  final String? customizationLabel;

  /// Lists the customer picks one value from before adding to the cart.
  final List<ChoiceField> choiceFields;
  final bool isActive;
  final bool isFeatured;
  final List<ProductVariant> variants;
  final List<ProductImage> images;

  String? get coverUrl => images.isEmpty ? null : images.first.url;

  List<ProductVariant> get activeVariants =>
      variants.where((v) => v.isActive).toList();

  /// Lowest price across active variants, used for "from X €" labels.
  int get minPriceCents {
    final prices = activeVariants.map(priceOf);
    return prices.isEmpty
        ? basePriceCents
        : prices.reduce((a, b) => a < b ? a : b);
  }

  bool get hasPriceRange => activeVariants.map(priceOf).toSet().length > 1;

  int priceOf(ProductVariant variant) => variant.priceCents ?? basePriceCents;

  /// A product with a single "Default" variant has no options to choose.
  bool get hasOptions =>
      activeVariants.length > 1 ||
      activeVariants.any((v) => v.options.isNotEmpty);

  factory Product.fromJson(Map<String, dynamic> json) {
    final variants =
        (json['product_variants'] as List? ?? [])
            .map((e) => ProductVariant.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final images =
        (json['product_images'] as List? ?? [])
            .map((e) => ProductImage.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));

    return Product(
      id: json['id'] as String,
      categoryId: json['category_id'] as String?,
      // Older API responses only had the main category.
      categoryIds:
          (json['category_ids'] as List?)?.cast<String>() ??
          [if (json['category_id'] != null) json['category_id'] as String],
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      basePriceCents: json['base_price_cents'] as int,
      isCustomizable: json['is_customizable'] as bool? ?? false,
      customizationLabel: json['customization_label'] as String?,
      choiceFields: (json['choice_fields'] as List? ?? [])
          .map((e) => ChoiceField.fromJson(e as Map<String, dynamic>))
          .toList(),
      isActive: json['is_active'] as bool? ?? true,
      isFeatured: json['is_featured'] as bool? ?? false,
      variants: variants,
      images: images,
    );
  }

  /// Product fields for the admin API (variants are sent alongside).
  Map<String, dynamic> toJson() => {
    'category_id': categoryIds.firstOrNull ?? categoryId,
    'category_ids': categoryIds,
    'name': name,
    'slug': slug,
    'description': description,
    'base_price_cents': basePriceCents,
    'is_customizable': isCustomizable,
    'customization_label': customizationLabel,
    'choice_fields': [for (final field in choiceFields) field.toJson()],
    'is_active': isActive,
    'is_featured': isFeatured,
  };
}

class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.sku,
    this.options = const {},
    this.priceCents,
    this.stock,
    this.position = 0,
    this.isActive = true,
  });

  final String id;
  final String productId;
  final String? sku;
  final String name;

  /// Attribute combination, e.g. `{"Talla": "2 años"}`.
  final Map<String, String> options;

  /// Overrides the product's base price when set.
  final int? priceCents;

  /// `null` means made to order (stock is not tracked).
  final int? stock;
  final int position;
  final bool isActive;

  bool get tracksStock => stock != null;
  bool get isInStock => stock == null || stock! > 0;

  String get label => options.isEmpty ? name : options.values.join(' · ');

  factory ProductVariant.fromJson(Map<String, dynamic> json) => ProductVariant(
    id: json['id'] as String,
    productId: json['product_id'] as String,
    sku: json['sku'] as String?,
    name: json['name'] as String? ?? 'Default',
    options: (json['options'] as Map? ?? {}).map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    ),
    priceCents: json['price_cents'] as int?,
    stock: json['stock'] as int?,
    position: json['position'] as int? ?? 0,
    isActive: json['is_active'] as bool? ?? true,
  );
}

class ProductImage {
  const ProductImage({
    required this.id,
    required this.productId,
    required this.url,
    this.variantId,
    this.storagePath,
    this.altText,
    this.position = 0,
  });

  final String id;
  final String productId;
  final String? variantId;
  final String url;
  final String? storagePath;
  final String? altText;
  final int position;

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
    id: json['id'] as String,
    productId: json['product_id'] as String,
    variantId: json['variant_id'] as String?,
    url: json['url'] as String,
    storagePath: json['storage_path'] as String?,
    altText: json['alt_text'] as String?,
    position: json['position'] as int? ?? 0,
  );
}
