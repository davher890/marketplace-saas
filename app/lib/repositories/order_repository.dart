import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    'shippingName': shippingName,
    'shippingAddress': shippingAddress.toJson(),
    'shippingPhone': shippingPhone,
    'contactEmail': contactEmail,
    'customerNotes': customerNotes,
  };
}

class OrderRepository {
  OrderRepository(this._db, this._api);

  final SupabaseClient _db;
  final ApiClient _api;

  /// Places the order through the Vercel API, which runs `place_order` in
  /// Supabase (prices, stock and shipping are computed server-side).
  Future<Order> checkout(CheckoutRequest request) async {
    final json = await _api.post('/api/checkout', request.toJson());
    return Order.fromJson(json['order'] as Map<String, dynamic>);
  }

  /// Orders visible to the current user (all orders for admins, via RLS).
  Future<List<Order>> fetchOrders({OrderStatus? status, String? userId}) async {
    var query = _db.from('orders').select(Order.listSelectQuery);
    if (status != null) query = query.eq('status', status.name);
    if (userId != null) query = query.eq('user_id', userId);
    final rows = await query.order('created_at', ascending: false);
    return rows.map(Order.fromJson).toList();
  }

  Future<Order?> fetchOrder(String id) async {
    final row = await _db
        .from('orders')
        .select(Order.detailSelectQuery)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Order.fromJson(row);
  }

  Future<void> cancel(String orderId) async {
    await _db.rpc('cancel_order', params: {'p_order_id': orderId});
  }

  /// Admin only (enforced by RLS).
  Future<void> updateStatus(String orderId, OrderStatus status) async {
    // Cancelling goes through the SQL function so stock is restored.
    if (status == OrderStatus.cancelled) return cancel(orderId);
    await _db.from('orders').update({'status': status.name}).eq('id', orderId);
  }

  /// Admin only (enforced by RLS).
  Future<void> updateAdminNotes(String orderId, String notes) async {
    await _db.from('orders').update({'admin_notes': notes}).eq('id', orderId);
  }
}

final orderRepositoryProvider = Provider(
  (ref) => OrderRepository(
    ref.watch(supabaseProvider),
    ref.watch(apiClientProvider),
  ),
);

/// Current customer's own orders.
final myOrdersProvider = FutureProvider<List<Order>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(orderRepositoryProvider).fetchOrders(userId: user.id);
});

/// All orders for the admin panel, optionally filtered by status.
final adminOrdersProvider = FutureProvider.family<List<Order>, OrderStatus?>((
  ref,
  status,
) {
  return ref.watch(orderRepositoryProvider).fetchOrders(status: status);
});

final orderProvider = FutureProvider.family<Order?, String>((ref, id) {
  return ref.watch(orderRepositoryProvider).fetchOrder(id);
});
