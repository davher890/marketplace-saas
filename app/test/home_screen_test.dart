import 'package:dona_galleta/features/catalog/home_screen.dart';
import 'package:dona_galleta/models/category.dart';
import 'package:dona_galleta/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, {required double width}) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryTreeProvider.overrideWith(
            (ref) async => const [
              CategoryNode(
                Category(id: 'c1', name: 'Navidad', slug: 'navidad'),
                [],
              ),
            ],
          ),
          featuredProductsProvider.overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: HomeScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('narrow screens get the category shortcuts', (tester) async {
    await pumpHome(tester, width: 400);
    expect(find.widgetWithText(ActionChip, 'Navidad'), findsOneWidget);
  });

  testWidgets('wide screens don\'t repeat the header menu', (tester) async {
    await pumpHome(tester, width: 1200);
    expect(find.widgetWithText(ActionChip, 'Navidad'), findsNothing);
  });
}
