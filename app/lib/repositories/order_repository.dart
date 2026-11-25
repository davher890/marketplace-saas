import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
import '../models/costs.dart';
import '../models/coupon.dart';
import '../models/export_columns.dart';
import '../models/order.dart';
import '../models/order_stats.dart';
import 'api_client.dart';

class CheckoutRequest {
  const CheckoutRequest({
    required this.shippingName,
    this.deliveryMethod = DeliveryMethod.shipping,
    this.shippingAddress,
    this.shippingPhone,
    this.contactEmail,
    this.customerNotes,
    this.couponCode,
  });

  final String shippingName;
  final DeliveryMethod deliveryMethod;

  /// Required to ship; `null` when picked up.
  final ShippingAddress? shippingAddress;
  final String? shippingPhone;
  final String? contactEmail;
  final String? customerNotes;

  /// Discount code; the API checks it again and works out the discount.
  final String? couponCode;

  Map<String, dynamic> toJson() => {
    'delivery_method': deliveryMethod.name,
    'shipping_name': shippingName,
    if (deliveryMethod == DeliveryMethod.shipping)
      'shipping_address': shippingAddress?.toJson(),
    'shipping_phone': shippingPhone,
    'contact_email': contactEmail,
    'customer_notes': customerNotes,
    if (couponCode != null) 'coupon_code': couponCode,
  };
}

/// Orders are read and changed only through the API.
class OrderRepository {
  OrderRepository(this._api);

  final ApiClient _api;

  /// Prices and shipping are computed by the API, never by the app.
  Future<Order> checkout(CheckoutRequest request) async {
    final json = await _api.post('/api/checkout', request.toJson());
    return Order.fromJson((json as Map<String, dynamic>)['order']);
  }

  /// Checks a discount code for the current customer. Throws an
  /// [ApiException] whose code says why it can't be used (`coupon_expired`...).
  Future<Coupon> applyCoupon(String code) async => Coupon.fromJson(
    await _api.post('/api/checkout/coupon', {'code': code})
        as Map<String, dynamic>,
  );

  /// The current customer's own orders.
  Future<List<Order>> fetchMyOrders() async =>
      parseList(await _api.get('/api/orders'), Order.fromJson);

  /// Every order (admin only), optionally only those in [statuses] and
  /// paid or not ([paid]).
  Future<List<Order>> fetchAllOrders({
    List<OrderStatus>? statuses,
    bool? paid,
  }) async {
    final query = {
      if (statuses != null && statuses.isNotEmpty)
        'status': statuses.map((s) => s.name).join(','),
      if (paid != null) 'paid': '$paid',
    };
    return parseList(
      await _api.get('/api/admin/orders', query: query.isEmpty ? null : query),
      Order.fromJson,
    );
  }

  /// The orders placed in [month] ("2026-11") as a CSV file (admin only).
  Future<Uint8List> exportMonth(String month) =>
      _api.getBytes('/api/admin/orders/export', query: {'month': month});

  /// Which columns the monthly file has, and in what order (admin only).
  Future<ExportColumns> fetchExportColumns() async => ExportColumns.fromJson(
    await _api.get('/api/admin/orders/export-columns'),
  );

  /// Saves the columns of the monthly file, in order (admin only).
  Future<ExportColumns> saveExportColumns(List<String> columns) async =>
      ExportColumns.fromJson(
        await _api.put('/api/admin/orders/export-columns', {
          'columns': columns,
        }),
      );

  /// What the order cost the shop (admin only).
  Future<OrderCosts> fetchOrderCosts(String orderId) async =>
      OrderCosts.fromJson(await _api.get('/api/admin/orders/$orderId/costs'));

  /// Counts and sales for the admin "Resumen" page.
  Future<OrderStats> fetchStats(SummaryPeriod period) async =>
      OrderStats.fromJson(
        await _api.get(
          '/api/admin/orders/summary',
          query: {'period': period.name},
        ),
      );

  /// Customers get their own orders; admins any order.
  Future<Order?> fetchOrder(String id) async {
    try {
      return Order.fromJson(await _api.get('/api/orders/$id'));
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Order> cancel(String orderId) async =>
      Order.fromJson(await _api.post('/api/orders/$orderId/cancel'));

  /// Admin only.
  Future<Order> updateStatus(String orderId, OrderStatus status) async =>
      Order.fromJson(
        await _api.patch('/api/admin/orders/$orderId', {'status': status.name}),
      );

  /// Admin only. Marking it paid emails the customer.
  Future<Order> updatePaid(String orderId, bool paid) async => Order.fromJson(
    await _api.patch('/api/admin/orders/$orderId', {'paid': paid}),
  );

  /// Admin only.
  Future<Order> updateAdminNotes(String orderId, String notes) async =>
      Order.fromJson(
        await _api.patch('/api/admin/orders/$orderId', {'admin_notes': notes}),
      );
}

final orderRepositoryProvider = Provider(
  (ref) => OrderRepository(ref.watch(apiClientProvider)),
);

/// Current customer's own orders.
final myOrdersProvider = FutureProvider<List<Order>>((ref) {
  if (ref.watch(currentUserProvider) == null) return [];
  return ref.watch(orderRepositoryProvider).fetchMyOrders();
});

/// Orders for the admin panel: those in [view], or only one [status] of it.
final adminOrdersProvider =
    FutureProvider.family<List<Order>, ({OrderView view, OrderStatus? status})>(
      (ref, filter) {
        return ref
            .watch(orderRepositoryProvider)
            .fetchAllOrders(
              statuses: filter.status == null
                  ? filter.view.statuses
                  : [filter.status!],
              paid: filter.view.paid,
            );
      },
    );

/// Figures for the admin "Resumen" page.
final adminOrderStatsProvider =
    FutureProvider.family<OrderStats, SummaryPeriod>((ref, period) {
      return ref.watch(orderRepositoryProvider).fetchStats(period);
    });

/// What an order cost the shop (admin order page).
final adminOrderCostsProvider = FutureProvider.family<OrderCosts, String>((
  ref,
  orderId,
) {
  return ref.watch(orderRepositoryProvider).fetchOrderCosts(orderId);
});

final orderProvider = FutureProvider.family<Order?, String>((ref, id) {
  return ref.watch(orderRepositoryProvider).fetchOrder(id);
});
