import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth.dart';
import '../models/cart.dart';
import 'api_client.dart';

/// The cart is stored server-side (one per user), so it is shared between the
/// web and the Android app. Every call returns the updated cart.
class CartRepository {
  CartRepository(this._api);

  final ApiClient _api;

  Future<Cart> fetchCart() async => _parse(await _api.get('/api/cart'));

  Future<Cart> add(
    String variantId, {
    int quantity = 1,
    String customization = '',
  }) async => _parse(
    await _api.post('/api/cart/items', {
      'variant_id': variantId,
      'quantity': quantity,
      'customization': customization,
    }),
  );

  /// A quantity of 0 removes the line.
  Future<Cart> updateQuantity(String itemId, int quantity) async => _parse(
    await _api.patch('/api/cart/items/$itemId', {
      'quantity': quantity < 0 ? 0 : quantity,
    }),
  );

  Future<Cart> remove(String itemId) async =>
      _parse(await _api.delete('/api/cart/items/$itemId'));

  Cart _parse(dynamic json) => Cart.fromJson(json as Map<String, dynamic>);
}

final cartRepositoryProvider = Provider(
  (ref) => CartRepository(ref.watch(apiClientProvider)),
);

/// Current user's cart. Mutations go through the notifier so the UI refreshes.
class CartNotifier extends AsyncNotifier<Cart> {
  CartRepository get _repo => ref.read(cartRepositoryProvider);

  @override
  Future<Cart> build() async {
    // Reload when the user changes; signed-out users have an empty cart.
    if (ref.watch(currentUserProvider) == null) return Cart.empty;
    return _repo.fetchCart();
  }

  Future<void> add(
    String variantId, {
    int quantity = 1,
    String customization = '',
  }) async {
    state = AsyncData(
      await _repo.add(
        variantId,
        quantity: quantity,
        customization: customization,
      ),
    );
  }

  Future<void> updateQuantity(String itemId, int quantity) async {
    state = AsyncData(await _repo.updateQuantity(itemId, quantity));
  }

  Future<void> remove(String itemId) async {
    state = AsyncData(await _repo.remove(itemId));
  }
}

final cartProvider = AsyncNotifierProvider<CartNotifier, Cart>(
  CartNotifier.new,
);
