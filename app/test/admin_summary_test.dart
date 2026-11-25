import 'dart:convert';

import 'package:dona_galleta/core/file_saver.dart';
import 'package:dona_galleta/core/money.dart';
import 'package:dona_galleta/features/admin/admin_orders_screen.dart';
import 'package:dona_galleta/features/admin/admin_summary_screen.dart';
import 'package:dona_galleta/models/order.dart';
import 'package:dona_galleta/models/order_stats.dart';
import 'package:dona_galleta/repositories/api_client.dart';
import 'package:dona_galleta/repositories/order_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _statsJson({int orders = 3}) => {
  'period': 'month',
  'by_status': {
    'received': 2,
    'processing': 0,
    'shipped': 4,
    'delivered': 7,
    'cancelled': 1,
  },
  'unpaid': {'orders': 5, 'total_cents': 12345},
  'totals': {
    'orders': orders,
    'sold': 2,
    'delivered': 1,
    'cancelled': 1,
    'revenue_cents': 3250,
    'average_cents': 1625,
    'pickup': 1,
    'shipping': 1,
  },
  'months': [
    {
      'month': '2026-11',
      'orders': 3,
      'sold': 2,
      'cancelled': 1,
      'revenue_cents': 3250,
    },
  ],
  'top_products': [
    {'name': 'Galletas de mantequilla', 'quantity': 4, 'revenue_cents': 2000},
  ],
};

void main() {
  test('OrderStats reads the API response', () {
    final stats = OrderStats.fromJson(_statsJson());
    expect(stats.byStatus[OrderStatus.received], 2);
    expect(stats.unpaidOrders, 5);
    expect(stats.unpaidCents, 12345);
    expect(stats.byStatus[OrderStatus.shipped], 4);
    expect(stats.revenueCents, 3250);
    expect(stats.averageCents, 1625);
    expect(stats.months.single.label, 'Noviembre 2026');
    expect(stats.topProducts.single.quantity, 4);
  });

  test('admin order list URLs', () {
    expect(AdminOrdersScreen.location(), '/admin/orders');
    expect(
      AdminOrdersScreen.location(status: OrderStatus.processing),
      '/admin/orders?estado=processing',
    );
    expect(
      AdminOrdersScreen.location(view: OrderView.closed),
      '/admin/orders?vista=historicos',
    );
    // A finished status opens the "Históricos" view.
    expect(
      AdminOrdersScreen.location(status: OrderStatus.cancelled),
      '/admin/orders?vista=historicos&estado=cancelled',
    );
    expect(
      AdminOrdersScreen.location(
        view: OrderView.unpaid,
        status: OrderStatus.delivered,
      ),
      '/admin/orders?vista=sin-pagar&estado=delivered',
    );
    expect(OrderView.fromUrl('historicos'), OrderView.closed);
    expect(OrderView.fromUrl('sin-pagar'), OrderView.unpaid);
    expect(OrderView.fromUrl(null), OrderView.open);
  });

  group('Resumen page', () {
    late List<SummaryPeriod> requested;
    late List<Uri> exportRequests;
    late List<({String fileName, String text, String mimeType})> saved;
    late int exportStatus;

    Future<GoRouter> pump(WidgetTester tester, {double width = 1200}) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      requested = [];
      exportRequests = [];
      saved = [];
      final api = ApiClient(
        baseUrl: 'https://shop.test',
        httpClient: MockClient((request) async {
          exportRequests.add(request.url);
          return exportStatus == 200
              ? http.Response.bytes(
                  utf8.encode('\uFEFFPedido;Fecha\r\n1004;01/11/2026\r\n'),
                  200,
                  headers: {'content-type': 'text/csv; charset=utf-8'},
                )
              : http.Response(
                  '{"error": "Admin access required"}',
                  exportStatus,
                );
        }),
      );
      final router = GoRouter(
        initialLocation: '/admin/summary',
        routes: [
          GoRoute(
            path: '/admin/summary',
            builder: (_, _) => const Scaffold(body: AdminSummaryScreen()),
          ),
          GoRoute(
            path: '/admin/orders',
            builder: (_, state) =>
                Scaffold(body: Text('Lista ${state.uri.query}')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminOrderStatsProvider.overrideWith((ref, period) async {
              requested.add(period);
              return OrderStats.fromJson(
                period == SummaryPeriod.all
                    ? _statsJson(orders: 0)
                    : _statsJson(),
              );
            }),
            orderRepositoryProvider.overrideWithValue(OrderRepository(api)),
            fileSaverProvider.overrideWithValue((bytes, fileName, mime) async {
              saved.add((
                fileName: fileName,
                text: utf8.decode(bytes),
                mimeType: mime,
              ));
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('shows orders in progress and this month\'s figures', (
      tester,
    ) async {
      await pump(tester);
      expect(requested, [SummaryPeriod.month]);
      for (final status in OrderView.open.statuses) {
        expect(find.text(status.label), findsOneWidget);
      }
      // Finished statuses are not cards of their own.
      expect(find.text(OrderStatus.delivered.label), findsNothing);
      expect(find.text('Sin pagar'), findsOneWidget);
      expect(find.text(formatCents(12345)), findsOneWidget);
      expect(find.text(formatCents(3250)), findsNWidgets(2)); // total + month
      expect(find.text(formatCents(1625)), findsOneWidget);
      expect(find.text('Noviembre 2026'), findsOneWidget);
      expect(find.text('Galletas de mantequilla'), findsOneWidget);
      expect(find.text('Envío 1 · Recogida 1'), findsOneWidget);
      expect(find.text('Columnas del Excel'), findsOneWidget);
    });

    testWidgets('a status card opens the list filtered by it', (tester) async {
      await pump(tester);
      await tester.tap(find.text(OrderStatus.shipped.label));
      await tester.pumpAndSettle();
      expect(find.text('Lista estado=shipped'), findsOneWidget);
    });

    testWidgets('the unpaid card opens the unpaid orders', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Sin pagar'));
      await tester.pumpAndSettle();
      expect(find.text('Lista vista=sin-pagar'), findsOneWidget);
    });

    testWidgets('changing the period asks for its figures', (tester) async {
      await pump(tester);
      await tester.tap(find.text(SummaryPeriod.all.label));
      await tester.pumpAndSettle();
      expect(requested, [SummaryPeriod.month, SummaryPeriod.all]);
      expect(find.text('No hay pedidos en este periodo.'), findsOneWidget);
      // Orders in progress are still shown.
      expect(find.text(OrderStatus.received.label), findsOneWidget);
    });

    testWidgets('each month downloads its orders as CSV', (tester) async {
      exportStatus = 200;
      await pump(tester);
      await tester.tap(
        find.byTooltip('Descargar los pedidos de Noviembre 2026'),
      );
      await tester.pumpAndSettle();
      expect(exportRequests.single.path, '/api/admin/orders/export');
      expect(exportRequests.single.queryParameters, {'month': '2026-11'});
      expect(saved.single.fileName, 'pedidos-2026-11.csv');
      expect(saved.single.mimeType, 'text/csv');
      expect(saved.single.text, contains('1004;01/11/2026'));
    });

    testWidgets('a failed download says why', (tester) async {
      exportStatus = 403;
      await pump(tester);
      await tester.tap(
        find.byTooltip('Descargar los pedidos de Noviembre 2026'),
      );
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.text('Admin access required'), findsOneWidget);
      // The button is back, to try again.
      expect(
        find.byTooltip('Descargar los pedidos de Noviembre 2026'),
        findsOneWidget,
      );
    });

    testWidgets('fits a phone screen', (tester) async {
      await pump(tester, width: 360);
      expect(tester.takeException(), isNull);
      expect(find.text('Noviembre 2026'), findsOneWidget);
    });
  });

  testWidgets('order list switches between in progress and finished', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final filters = <({OrderView view, OrderStatus? status})>[];
    final router = GoRouter(
      initialLocation: '/admin/orders',
      routes: [
        GoRoute(
          path: '/admin/orders',
          builder: (_, state) => Scaffold(
            body: AdminOrdersScreen(
              view: OrderView.fromUrl(state.uri.queryParameters['vista']),
              status: OrderStatus.values
                  .asNameMap()[state.uri.queryParameters['estado']],
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminOrdersProvider.overrideWith((ref, filter) async {
            filters.add(filter);
            return <Order>[];
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(filters.last, (view: OrderView.open, status: null));
    expect(find.widgetWithText(ChoiceChip, 'Entregado'), findsNothing);

    await tester.tap(find.text('Históricos'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/admin/orders?vista=historicos');
    expect(filters.last, (view: OrderView.closed, status: null));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Entregado'));
    await tester.pumpAndSettle();
    expect(filters.last, (
      view: OrderView.closed,
      status: OrderStatus.delivered,
    ));
    expect(find.widgetWithText(ChoiceChip, 'Recibido'), findsNothing);

    // Unpaid orders keep the view when filtering by status.
    await tester.tap(find.text('Sin pagar'));
    await tester.pumpAndSettle();
    expect(filters.last, (view: OrderView.unpaid, status: null));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Entregado'));
    await tester.pumpAndSettle();
    expect(
      router.state.uri.toString(),
      '/admin/orders?vista=sin-pagar&estado=delivered',
    );
    expect(filters.last, (
      view: OrderView.unpaid,
      status: OrderStatus.delivered,
    ));
    expect(find.widgetWithText(ChoiceChip, 'Cancelado'), findsNothing);
  });
}
