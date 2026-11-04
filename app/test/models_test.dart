import 'package:dona_galleta/core/money.dart';
import 'package:dona_galleta/features/admin/product_form_screen.dart';
import 'package:dona_galleta/models/cart.dart';
import 'package:dona_galleta/models/product.dart';
import 'package:dona_galleta/models/shop_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_ES'));

  group('money', () {
    test('formats cents as euros', () {
      expect(formatCents(3000).replaceAll(' ', ' '), '30,00 €');
      expect(formatCents(1695).replaceAll(' ', ' '), '16,95 €');
    });

    test('parses comma and dot decimals', () {
      expect(parseCents('16,95'), 1695);
      expect(parseCents('16.95'), 1695);
      expect(parseCents(' 30 € '), 3000);
      expect(parseCents(''), isNull);
      expect(parseCents('-1'), isNull);
      expect(parseCents('abc'), isNull);
    });
  });

  group('Product', () {
    final product = Product.fromJson({
      'id': 'p1',
      'name': 'Conjunto',
      'slug': 'conjunto',
      'base_price_cents': 3000,
      'product_variants': [
        {
          'id': 'v2',
          'product_id': 'p1',
          'name': '4 años',
          'options': {'Talla': '4 años'},
          'price_cents': 3500,
          'stock': 0,
          'position': 2,
        },
        {
          'id': 'v1',
          'product_id': 'p1',
          'name': '2 años',
          'options': {'Talla': '2 años'},
          'stock': null,
          'position': 1,
        },
      ],
      'product_images': [],
    });

    test('sorts variants by position and resolves prices', () {
      expect(product.variants.map((v) => v.id), ['v1', 'v2']);
      expect(product.priceOf(product.variants.first), 3000);
      expect(product.priceOf(product.variants.last), 3500);
      expect(product.minPriceCents, 3000);
      expect(product.hasPriceRange, isTrue);
      expect(product.hasOptions, isTrue);
    });

    test('null stock means made to order', () {
      expect(product.variants.first.isInStock, isTrue);
      expect(product.variants.first.tracksStock, isFalse);
      expect(product.variants.last.isInStock, isFalse);
    });
  });

  test('cart totals', () {
    final item = CartItem.fromJson({
      'id': 'c1',
      'quantity': 3,
      'customization': '',
      'product_variants': {
        'id': 'v1',
        'product_id': 'p1',
        'name': 'Default',
        'options': {},
        'price_cents': null,
        'stock': 5,
        'products': {
          'id': 'p1',
          'name': 'Cojín',
          'slug': 'cojin',
          'base_price_cents': 1695,
          'product_images': [],
        },
      },
    });
    final cart = Cart([item]);
    expect(cart.itemCount, 3);
    expect(cart.subtotalCents, 5085);
  });

  test('shipping rule mirrors place_order', () {
    const settings = ShopSettings(
      shippingFlatCents: 495,
      freeShippingThresholdCents: 5000,
    );
    expect(settings.shippingFor(4999), 495);
    expect(settings.shippingFor(5000), 0);
    expect(const ShopSettings(shippingFlatCents: 495).shippingFor(100000), 495);
  });

  test('slugify', () {
    expect(slugify('Cojín Nube 30x50'), 'cojin-nube-30x50');
    expect(slugify('  ¡Año nuevo!  '), 'ano-nuevo');
  });
}
