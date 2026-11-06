import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/auth.dart';
import '../../models/order.dart';
import '../../repositories/cart_repository.dart';
import '../../repositories/catalog_repository.dart';
import '../../repositories/order_repository.dart';
import '../../widgets/common.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: ref.read(currentUserProvider)?.fullName ?? '',
  );
  late final _email = TextEditingController(
    text: ref.read(currentUserProvider)?.email ?? '',
  );
  final _phone = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _postalCode = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();
  final _notes = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _phone,
      _line1,
      _line2,
      _postalCode,
      _city,
      _province,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Obligatorio' : null;

  String? _nullIfEmpty(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final order = await ref
          .read(orderRepositoryProvider)
          .checkout(
            CheckoutRequest(
              shippingName: _name.text.trim(),
              contactEmail: _nullIfEmpty(_email),
              shippingPhone: _nullIfEmpty(_phone),
              customerNotes: _nullIfEmpty(_notes),
              shippingAddress: ShippingAddress(
                line1: _line1.text.trim(),
                line2: _line2.text.trim(),
                postalCode: _postalCode.text.trim(),
                city: _city.text.trim(),
                province: _province.text.trim(),
              ),
            ),
          );
      ref.invalidate(cartProvider);
      ref.invalidate(myOrdersProvider);
      if (mounted) context.go('/orders/${order.id}?placed=1');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final settings = ref.watch(shopSettingsProvider).value;

    Widget field(
      TextEditingController c,
      String label, {
      bool required = false,
      TextInputType? keyboard,
      List<String>? autofill,
      int maxLines = 1,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: required ? '$label *' : label),
        validator: required ? _required : null,
        keyboardType: keyboard,
        autofillHints: autofill,
        maxLines: maxLines,
      ),
    );

    return ContentWidth(
      maxWidth: 700,
      child: AsyncView(
        value: cart,
        builder: (cart) {
          if (cart.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('Tu carrito está vacío.')),
            );
          }
          final shipping = settings?.shippingFor(cart.subtotalCents) ?? 0;

          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('Datos de envío'),
                  field(
                    _name,
                    'Nombre y apellidos',
                    required: true,
                    autofill: const [AutofillHints.name],
                  ),
                  field(
                    _email,
                    'Email',
                    required: true,
                    keyboard: TextInputType.emailAddress,
                    autofill: const [AutofillHints.email],
                  ),
                  field(
                    _phone,
                    'Teléfono',
                    keyboard: TextInputType.phone,
                    autofill: const [AutofillHints.telephoneNumber],
                  ),
                  field(
                    _line1,
                    'Dirección',
                    required: true,
                    autofill: const [AutofillHints.streetAddressLine1],
                  ),
                  field(
                    _line2,
                    'Piso, puerta... (opcional)',
                    autofill: const [AutofillHints.streetAddressLine2],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: field(
                          _postalCode,
                          'Código postal',
                          required: true,
                          keyboard: TextInputType.number,
                          autofill: const [AutofillHints.postalCode],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: field(
                          _city,
                          'Ciudad',
                          required: true,
                          autofill: const [AutofillHints.addressCity],
                        ),
                      ),
                    ],
                  ),
                  field(
                    _province,
                    'Provincia',
                    autofill: const [AutofillHints.addressState],
                  ),
                  field(_notes, 'Notas para Doña Galleta', maxLines: 3),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          for (final item in cart.items)
                            _Row(
                              '${item.quantity} × ${item.product.name}',
                              formatCents(item.lineTotalCents),
                            ),
                          const Divider(height: 24),
                          _Row('Subtotal', formatCents(cart.subtotalCents)),
                          _Row(
                            'Envío',
                            shipping == 0 ? 'Gratis' : formatCents(shipping),
                          ),
                          _Row(
                            'Total',
                            formatCents(cart.subtotalCents + shipping),
                            bold: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submitting ? null : _placeOrder,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Realizar pedido'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Te contactaremos para confirmar el pago y los detalles de la personalización.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
