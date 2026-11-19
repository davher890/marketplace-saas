import 'package:dona_galleta/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

ProductVariant _variant(
  String id,
  String name, [
  Map<String, String> options = const {},
  int? stock,
]) => ProductVariant(
  id: id,
  productId: 'p1',
  name: name,
  options: options,
  stock: stock,
);

/// Records holding lists don't compare by content, so compare plain lists.
List<List<Object>> _plain(List<VariantOption> options) => [
  for (final o in options) [o.name, o.values],
];

void main() {
  group('variantOptions', () {
    test('lists every option and its values in order of appearance', () {
      final variants = [
        _variant('a', '8 cm · Cristal', {
          'Tamaño': '8 cm',
          'Material': 'Cristal',
        }),
        _variant('b', '8 cm · Madera', {
          'Tamaño': '8 cm',
          'Material': 'Madera',
        }),
        _variant('c', '10 cm · Cristal', {
          'Tamaño': '10 cm',
          'Material': 'Cristal',
        }),
      ];
      expect(_plain(variantOptions(variants)), [
        [
          'Tamaño',
          ['8 cm', '10 cm'],
        ],
        [
          'Material',
          ['Cristal', 'Madera'],
        ],
      ]);
    });

    test('variants saved without options become one "Opción"', () {
      final variants = [_variant('a', '4'), _variant('b', '10')];
      expect(_plain(variantOptions(variants)), [
        [
          defaultOptionName,
          ['4', '10'],
        ],
      ]);
    });

    test('a variant missing an option takes its own name', () {
      final variants = [
        _variant('a', 'Default'),
        _variant('b', 'Añade termo', {'Color': 'Añade termo'}),
      ];
      expect(optionsOf(variants.first, variants), {
        'Color': defaultOptionValue,
      });
    });

    test('a single plain variant has no options', () {
      expect(variantOptions([_variant('a', 'Default')]), isEmpty);
    });
  });

  test('optionCombinations: first option changes slowest', () {
    expect(
      optionCombinations([
        (name: 'Tamaño', values: ['8 cm', '10 cm']),
        (name: 'Material', values: ['Cristal', 'Madera']),
        (name: 'Vacía', values: []),
      ]),
      [
        {'Tamaño': '8 cm', 'Material': 'Cristal'},
        {'Tamaño': '8 cm', 'Material': 'Madera'},
        {'Tamaño': '10 cm', 'Material': 'Cristal'},
        {'Tamaño': '10 cm', 'Material': 'Madera'},
      ],
    );
    expect(optionCombinations([]), isEmpty);
  });

  group('matchCombinations', () {
    test('keeps exact matches, wherever they are', () {
      expect(
        matchCombinations(
          [
            {'Tamaño': '8 cm'},
            {'Tamaño': '10 cm'},
          ],
          [
            {'Tamaño': '10 cm'},
            {'Tamaño': '8 cm'},
          ],
        ),
        [1, 0],
      );
    });

    test('a new option reuses each variant once, the rest are new', () {
      expect(
        matchCombinations(
          [
            {'Tamaño': '8 cm', 'Material': 'Cristal'},
            {'Tamaño': '8 cm', 'Material': 'Madera'},
            {'Tamaño': '10 cm', 'Material': 'Cristal'},
            {'Tamaño': '10 cm', 'Material': 'Madera'},
          ],
          [
            {'Tamaño': '8 cm'},
            {'Tamaño': '10 cm'},
          ],
        ),
        [0, null, 1, null],
      );
    });

    test('a removed value is not reused for another one', () {
      expect(
        matchCombinations(
          [
            {'Tamaño': '8 cm'},
          ],
          [
            {'Tamaño': '12 cm'},
          ],
        ),
        [null],
      );
    });
  });

  group('Product.pick', () {
    final product = Product(
      id: 'p1',
      name: 'Bola',
      slug: 'bola',
      basePriceCents: 800,
      variants: [
        _variant('a', '', {'Tamaño': '8 cm', 'Material': 'Cristal'}, 2),
        _variant('b', '', {'Tamaño': '8 cm', 'Material': 'Madera'}, 0),
        _variant('c', '', {'Tamaño': '10 cm', 'Material': 'Madera'}, 5),
      ],
    );

    test('keeps the other values when that combination exists', () {
      final picked = product.pick(
        {'Tamaño': '8 cm', 'Material': 'Cristal'},
        'Material',
        'Madera',
      );
      expect(picked?.id, 'b');
    });

    test('changes the other values when it has to', () {
      final picked = product.pick(
        {'Tamaño': '8 cm', 'Material': 'Cristal'},
        'Tamaño',
        '10 cm',
      );
      expect(picked?.id, 'c');
    });

    test('variantFor finds the exact combination', () {
      expect(
        product.variantFor({'Tamaño': '10 cm', 'Material': 'Madera'})?.id,
        'c',
      );
      expect(
        product.variantFor({'Tamaño': '10 cm', 'Material': 'Cristal'}),
        isNull,
      );
    });
  });
}
