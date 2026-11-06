import 'package:dona_galleta/features/admin/admin_categories_screen.dart';
import 'package:dona_galleta/models/category.dart';
import 'package:dona_galleta/repositories/admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _categories = [
  Category(id: 'j', name: 'Joyería', slug: 'joyeria'),
  Category(id: 'a', parentId: 'j', name: 'Anillos', slug: 'anillos'),
  Category(
    id: 'p',
    parentId: 'j',
    name: 'Pulseras',
    slug: 'pulseras',
    position: 1,
    productCount: 3,
    isActive: false,
  ),
  Category(id: 'c', name: 'Complementos', slug: 'complementos', position: 1),
];

void main() {
  testWidgets(
    'rows fit on a phone',
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.macOS,
    }),
    (tester) async {
      // Pixel-like phone with a slightly enlarged system font.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminCategoriesProvider.overrideWith((ref) async => _categories),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.15)),
              child: child!,
            ),
            home: const Scaffold(body: AdminCategoriesScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A RenderFlex overflow would be reported as an exception.
      expect(tester.takeException(), isNull);
      expect(find.text('Pulseras'), findsOneWidget);
      expect(find.text('3 productos · Oculta'), findsOneWidget);
      expect(find.byTooltip('Subir'), findsNWidgets(4));
    },
  );
}
