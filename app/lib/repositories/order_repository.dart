import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../models/order.dart';
import 'api_client.dart';

class CheckoutRequest {
  const CheckoutRequest({
    required this.shippingName,
    required this.shippingAddress,
    this.shippingPhone,
    this.contactEmail,
    this.customerNotes,
  });

  final String shippingName;
  final ShippingAddress shippingAddress;
  final String? shippingPhone;
  final String? contactEmail;
  final String? customerNotes;

  Map<String, dynamic> toJson() => {
    'shipping_name': shippingName,
    'shipping_address': shippingAddress.toJson(),
    'shipping_phone': shippingPhone,
    'contact_email': contactEmail,
    'customer_notes': customerNotes,
  };
}

/// Orders are read and changed only through the API.
class OrderRepository {
  OrderRepository(this._api);

  final ApiClient _api;

  /// Prices, stock and shipping are computed by the API, never by the app.
  Future<Order> checkout(CheckoutRequest request) async {
    final json = await _api.post('/api/checkout', request.toJson());
    return Order.fromJson((json as Map<String, dynamic>)['order']);
  }

  /// The current customer's own orders.
  Future<List<Order>> fetchMyOrders() async =>
      parseList(await _api.get('/api/orders'), Order.fromJson);

  /// Every order (admin only), optionally filtered by status.
  Future<List<Order>> fetchAllOrders({OrderStatus? status}) async => parseList(
    await _api.get(
      '/api/admin/orders',
      query: status == null ? null : {'status': status.name},
    ),
    Order.fromJson,
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

  /// Admin only. Cancelling also restores stock.
  Future<Order> updateStatus(String orderId, OrderStatus status) async =>
      Order.fromJson(
        await _api.patch('/api/admin/orders/$orderId', {'status': status.name}),
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

/// All orders for the admin panel, optionally filtered by status.
final adminOrdersProvider = FutureProvider.family<List<Order>, OrderStatus?>((
  ref,
  status,
) {
  return ref.watch(orderRepositoryProvider).fetchAllOrders(status: status);
});

final orderProvider = FutureProvider.family<Order?, String>((ref, id) {
  return ref.watch(orderRepositoryProvider).fetchOrder(id);
});
