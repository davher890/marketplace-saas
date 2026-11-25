import 'dart:convert';

import 'package:dona_galleta/features/admin/export_columns_dialog.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _available = [
  {'key': 'order_number', 'label': 'Pedido'},
  {'key': 'created_at', 'label': 'Fecha'},
  {'key': 'customer', 'label': 'Cliente'},
  {'key': 'items', 'label': 'Artículos'},
  {'key': 'total', 'label': 'Total (€)'},
];

void main() {
  late List<Object?> saved;

  Future<void> pump(WidgetTester tester, List<String> selected) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    saved = [];
    final api = ApiClient(
      baseUrl: 'https://shop.test',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/admin/orders/export-columns');
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          saved.add(body['columns']);
          return http.Response(
            jsonEncode({'available': _available, 'selected': body['columns']}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'available': _available, 'selected': selected}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderRepositoryProvider.overrideWithValue(OrderRepository(api)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showExportColumnsDialog(context),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  /// Labels in the order the dialog lists them.
  List<String> labels(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
      (tile.title! as Text).data!,
  ];

  bool checked(WidgetTester tester, String label) => tester
      .widget<Checkbox>(
        find.descendant(
          of: find.widgetWithText(ListTile, label),
          matching: find.byType(Checkbox),
        ),
      )
      .value!;

  testWidgets('chosen columns first, in their order, then the rest', (
    tester,
  ) async {
    await pump(tester, ['total', 'customer']);
    expect(labels(tester), [
      'Total (€)',
      'Cliente',
      'Pedido',
      'Fecha',
      'Artículos',
    ]);
    expect(checked(tester, 'Total (€)'), isTrue);
    expect(checked(tester, 'Pedido'), isFalse);
  });

  testWidgets('ticking a column adds it in its place; saved in order', (
    tester,
  ) async {
    await pump(tester, ['total', 'customer']);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Pedido'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Total (€)'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(saved, [
      ['customer', 'order_number'],
    ]);
    expect(find.text('Columnas guardadas'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('dragging a column changes the order', (tester) async {
    await pump(tester, ['order_number', 'created_at', 'customer']);
    final handle = find.descendant(
      of: find.widgetWithText(ListTile, 'Cliente'),
      matching: find.byIcon(Icons.drag_handle),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    final rowHeight = tester.getSize(find.byType(ListTile).first).height;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, -rowHeight * 0.25));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(labels(tester).take(3), ['Cliente', 'Pedido', 'Fecha']);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(saved, [
      ['customer', 'order_number', 'created_at'],
    ]);
  });

  testWidgets('at least one column; "Restablecer" brings back every column', (
    tester,
  ) async {
    await pump(tester, ['total']);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Total (€)'),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Elige al menos una columna'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.tap(find.text('Restablecer'));
    await tester.pumpAndSettle();
    expect(labels(tester), [
      'Pedido',
      'Fecha',
      'Cliente',
      'Artículos',
      'Total (€)',
    ]);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(saved, [
      ['order_number', 'created_at', 'customer', 'items', 'total'],
    ]);
  });
}
