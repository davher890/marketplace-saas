import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';
import 'product_card.dart';

/// Product search by name (`/buscar?q=...`). The text lives in the URL, so a
/// search can be reloaded, shared and reached with the back button.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.query});

  final String query;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _text = TextEditingController(text: widget.query);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  /// Updates the URL a moment after the user stops typing.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  void _search(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query == widget.query) return;
    context.go(
      query.isEmpty
          ? '/buscar'
          : '/buscar?q=${Uri.encodeQueryComponent(query)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query.trim();
    return ContentWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Buscar'),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: TextField(
                controller: _text,
                autofocus: query.isEmpty,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Busca por nombre: bola, taza, chupetero...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _text.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _text.clear();
                            _search('');
                          },
                        ),
                ),
                onChanged: (value) {
                  setState(() {}); // Shows / hides the clear button.
                  _onChanged(value);
                },
                onSubmitted: _search,
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (query.length < 2)
            const Text(
              'Escribe al menos dos letras.',
              textAlign: TextAlign.center,
            )
          else
            AsyncView(
              value: ref.watch(searchProductsProvider(query)),
              onRetry: () => ref.invalidate(searchProductsProvider(query)),
              builder: (products) => products.isEmpty
                  ? Text(
                      'No hay productos que coincidan con "$query".',
                      textAlign: TextAlign.center,
                    )
                  : ProductGrid(products: products),
            ),
        ],
      ),
    );
  }
}
