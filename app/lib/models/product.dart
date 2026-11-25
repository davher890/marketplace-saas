import 'costs.dart';

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
    this.costCents,
    this.supplierId,
    this.boxSize,
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

  /// What it costs the shop (admin only; the store never gets it). A
  /// variant's own cost wins, like the price.
  final int? costCents;
  final String? supplierId;

  /// Box it's packed in: one per article of an order.
  final BoxSize? boxSize;

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
  bool get hasOptions => variantOptions(activeVariants).isNotEmpty;

  /// Active variant matching every value in [selected], if any.
  ProductVariant? variantFor(Map<String, String> selected) =>
      activeVariants.where((v) {
        final options = optionsOf(v, activeVariants);
        return selected.entries.every((e) => options[e.key] == e.value);
      }).firstOrNull;

  /// Active variant after the customer picks [value] for [option], keeping as
  /// many of the other [selected] values as possible.
  ProductVariant? pick(
    Map<String, String> selected,
    String option,
    String value,
  ) {
    final candidates = activeVariants
        .where((v) => optionsOf(v, activeVariants)[option] == value)
        .toList();
    int score(ProductVariant v) {
      final options = optionsOf(v, activeVariants);
      return selected.entries.where((e) => options[e.key] == e.value).length;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.firstOrNull;
  }

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
      costCents: json['cost_cents'] as int?,
      supplierId: json['supplier_id'] as String?,
      boxSize: BoxSize.fromApi(json['box_size'] as String?),
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
    'cost_cents': costCents,
    'supplier_id': supplierId,
    'box_size': boxSize?.apiName,
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
    this.costCents,
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

  /// Its own cost (admin only); `null` = the product's.
  final int? costCents;

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
    costCents: json['cost_cents'] as int?,
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

/// One option customers choose a value of, e.g. "Tamaño": 8 cm, 10 cm.
typedef VariantOption = ({String name, List<String> values});

/// Name used for products whose variants were saved without options.
const defaultOptionName = 'Opción';

/// Value used for a variant that lacks an option the others have.
const defaultOptionValue = 'Estándar';

/// Options of [variants] in order of appearance, e.g. Tamaño then Material.
///
/// Variants saved before options could be combined may lack them: a product
/// with several variants and no options gets one [defaultOptionName] option
/// with their names, and a variant missing an option takes its own name.
List<VariantOption> variantOptions(List<ProductVariant> variants) {
  final values = <String, List<String>>{};
  for (final variant in variants) {
    optionsOf(variant, variants).forEach((name, value) {
      final list = values.putIfAbsent(name, () => []);
      if (!list.contains(value)) list.add(value);
    });
  }
  return [for (final e in values.entries) (name: e.key, values: e.value)];
}

/// [variant]'s value for every option of [variants] (see [variantOptions]).
Map<String, String> optionsOf(
  ProductVariant variant,
  List<ProductVariant> variants,
) {
  final names = <String>{for (final v in variants) ...v.options.keys};
  if (names.isEmpty) {
    return variants.length > 1
        ? {defaultOptionName: _ownValue(variant)}
        : const {};
  }
  return {
    for (final name in names) name: variant.options[name] ?? _ownValue(variant),
  };
}

String _ownValue(ProductVariant variant) =>
    variant.name == 'Default' || variant.name.trim().isEmpty
    ? defaultOptionValue
    : variant.name;

/// Every combination of the options' values; the first option changes
/// slowest, e.g. 8 cm · Cristal, 8 cm · Madera, 10 cm · Cristal...
List<Map<String, String>> optionCombinations(List<VariantOption> options) {
  var combinations = [<String, String>{}];
  for (final option in options) {
    if (option.values.isEmpty) continue;
    combinations = [
      for (final combination in combinations)
        for (final value in option.values) {...combination, option.name: value},
    ];
  }
  return options.any((o) => o.values.isNotEmpty) ? combinations : [];
}

/// For each combination, the index in [rows] of the variant to keep for it,
/// or `null` for a new one. A row with exactly those values wins; otherwise
/// an unclaimed row that agrees on every option both have (e.g. an option was
/// just added or removed), preferring the one sharing most values.
List<int?> matchCombinations(
  List<Map<String, String>> combinations,
  List<Map<String, String>> rows,
) {
  bool same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  final claimed = <int>{};
  final result = List<int?>.filled(combinations.length, null);
  for (final (i, combination) in combinations.indexed) {
    for (final (j, row) in rows.indexed) {
      if (!claimed.contains(j) && same(combination, row)) {
        result[i] = j;
        claimed.add(j);
        break;
      }
    }
  }
  for (final (i, combination) in combinations.indexed) {
    if (result[i] != null) continue;
    int? best;
    var bestShared = -1;
    for (final (j, row) in rows.indexed) {
      if (claimed.contains(j)) continue;
      final shared = combination.keys.where(row.containsKey);
      if (shared.any((key) => row[key] != combination[key])) continue;
      if (shared.length > bestShared) {
        best = j;
        bestShared = shared.length;
      }
    }
    if (best != null) {
      result[i] = best;
      claimed.add(best);
    }
  }
  return result;
}
