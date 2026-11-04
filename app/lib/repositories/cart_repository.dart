import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/providers.dart';
import '../models/cart.dart';

/// The cart lives in Supabase (`carts` / `cart_items`), so it is shared
/// between the web and the Android app for the same user.
class CartRepository {
  CartRepository(this._db);

  final SupabaseClient _db;

  Future<Cart> fetchCart() async {
    final user = _db.auth.currentUser;
    if (user == null) return Cart.empty;

    final cart = await _db
        .from('carts')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle();
    if (cart == null) return Cart.empty;

    final rows = await _db
        .from('cart_items')
        .select(CartItem.selectQuery)
        .eq('cart_id', cart['id'] as String)
        .order('created_at', ascending: true);
    return Cart(rows.map(CartItem.fromJson).toList());
  }

  Future<void> add(
    String variantId, {
    int quantity = 1,
    String customization = '',
  }) async {
    await _db.rpc(
      'add_to_cart',
      params: {
        'p_variant_id': variantId,
        'p_quantity': quantity,
        'p_customization': customization,
      },
    );
  }

  Future<void> updateQuantity(String itemId, int quantity) async {
    if (quantity <= 0) return remove(itemId);
    await _db
        .from('cart_items')
        .update({'quantity': quantity})
        .eq('id', itemId);
  }

  Future<void> remove(String itemId) async {
    await _db.from('cart_items').delete().eq('id', itemId);
  }
}

final cartRepositoryProvider = Provider(
  (ref) => CartRepository(ref.watch(supabaseProvider)),
);

/// Current user's cart. Mutations go through the notifier so the UI refreshes.
class CartNotifier extends AsyncNotifier<Cart> {
  CartRepository get _repo => ref.read(cartRepositoryProvider);

  @override
  Future<Cart> build() {
    ref.watch(currentUserProvider); // Reload when the user changes.
    return ref.read(cartRepositoryProvider).fetchCart();
  }

  Future<void> add(
    String variantId, {
    int quantity = 1,
    String customization = '',
  }) => _mutate(
    () =>
        _repo.add(variantId, quantity: quantity, customization: customization),
  );

  Future<void> updateQuantity(String itemId, int quantity) =>
      _mutate(() => _repo.updateQuantity(itemId, quantity));

  Future<void> remove(String itemId) => _mutate(() => _repo.remove(itemId));

  Future<void> reload() async {
    state = await AsyncValue.guard(_repo.fetchCart);
  }

  Future<void> _mutate(Future<void> Function() action) async {
    await action();
    await reload();
  }
}

final cartProvider = AsyncNotifierProvider<CartNotifier, Cart>(
  CartNotifier.new,
);
