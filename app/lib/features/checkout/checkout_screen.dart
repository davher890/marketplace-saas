import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/auth.dart';
import '../../models/cart.dart';
import '../../models/coupon.dart';
import '../../models/order.dart';
import '../../models/shop_settings.dart';
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
  final _couponCode = TextEditingController();
  DeliveryMethod _delivery = DeliveryMethod.shipping;
  bool _submitting = false;

  /// The discount code the customer applied (checked by the API).
  Coupon? _coupon;
  bool _applyingCoupon = false;
  String? _couponError;

  bool get _pickup => _delivery == DeliveryMethod.pickup;

  @override
  void initState() {
    super.initState();
    // Madrid postal codes have their own rate: refresh the summary.
    _postalCode.addListener(() => setState(() {}));
  }

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
      _couponCode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Obligatorio' : null;

  String? _nullIfEmpty(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  int _shippingFor(Cart cart, ShopSettings? settings) =>
      settings?.shippingFor(
        cart.subtotalCents,
        pickup: _pickup,
        postalCode: _postalCode.text,
      ) ??
      0;

  /// What the applied coupon takes off this cart (0 without one, or when it
  /// gives nothing, like free shipping on a pickup order).
  int _discountFor(Cart cart, int shipping) =>
      _coupon?.discountFor(cart.subtotalCents, shipping) ?? 0;

  Future<void> _applyCoupon() async {
    final code = _couponCode.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _applyingCoupon = true;
      _couponError = null;
    });
    try {
      final coupon = await ref.read(orderRepositoryProvider).applyCoupon(code);
      if (!mounted) return;
      setState(() {
        _coupon = coupon;
        _couponCode.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _couponError = describeError(error));
    } finally {
      if (mounted) setState(() => _applyingCoupon = false);
    }
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    final cart = ref.read(cartProvider).value;
    final discount = cart == null
        ? 0
        : _discountFor(
            cart,
            _shippingFor(cart, ref.read(shopSettingsProvider).value),
          );
    setState(() => _submitting = true);
    try {
      final order = await ref
          .read(orderRepositoryProvider)
          .checkout(
            CheckoutRequest(
              shippingName: _name.text.trim(),
              deliveryMethod: _delivery,
              contactEmail: _nullIfEmpty(_email),
              shippingPhone: _nullIfEmpty(_phone),
              customerNotes: _nullIfEmpty(_notes),
              // A coupon that gives nothing here isn't sent (the API would
              // refuse the order).
              couponCode: discount > 0 ? _coupon?.code : null,
              shippingAddress: _pickup
                  ? null
                  : ShippingAddress(
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
          final shipping = _shippingFor(cart, settings);
          final discount = _discountFor(cart, shipping);

          return Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle('Entrega'),
                  SegmentedButton<DeliveryMethod>(
                    segments: const [
                      ButtonSegment(
                        value: DeliveryMethod.shipping,
                        icon: Icon(Icons.local_shipping_outlined),
                        label: Text('Envío a domicilio'),
                      ),
                      ButtonSegment(
                        value: DeliveryMethod.pickup,
                        icon: Icon(Icons.storefront_outlined),
                        label: Text('Recogida en tienda'),
                      ),
                    ],
                    selected: {_delivery},
                    onSelectionChanged: (selection) =>
                        setState(() => _delivery = selection.single),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pickup
                        ? 'Sin gastos de envío. Te avisaremos cuando esté listo para recoger.'
                        : settings == null
                        ? ''
                        : shippingRatesText(settings, withPickup: false),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
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
                  if (!_pickup) ...[
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
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TextFormField(
                              controller: _postalCode,
                              decoration: const InputDecoration(
                                labelText: 'Código postal *',
                                hintText: '28010',
                              ),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Obligatorio'
                                  : isSpanishPostalCode(v)
                                  ? null
                                  : 'Código postal no válido',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              autofillHints: const [AutofillHints.postalCode],
                            ),
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
                  ],
                  field(_notes, 'Notas para Doña Galleta', maxLines: 3),
                  _CouponField(
                    controller: _couponCode,
                    coupon: _coupon,
                    applying: _applyingCoupon,
                    error: _couponError,
                    notApplicable: _coupon != null && discount == 0,
                    onApply: _applyCoupon,
                    onRemove: () => setState(() => _coupon = null),
                  ),
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
                            _pickup ? 'Recogida en tienda' : 'Envío',
                            shipping == 0 ? 'Gratis' : formatCents(shipping),
                          ),
                          if (discount > 0)
                            _Row(
                              'Descuento (${_coupon!.code})',
                              '-${formatCents(discount)}',
                            ),
                          _Row(
                            'Total',
                            formatCents(
                              cart.subtotalCents + shipping - discount,
                            ),
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

/// "Código de descuento" with an "Aplicar" button; once applied, the coupon
/// with a button to remove it.
class _CouponField extends StatelessWidget {
  const _CouponField({
    required this.controller,
    required this.coupon,
    required this.applying,
    required this.error,
    required this.notApplicable,
    required this.onApply,
    required this.onRemove,
  });

  final TextEditingController controller;
  final Coupon? coupon;
  final bool applying;
  final String? error;

  /// Applied, but it gives nothing on this order.
  final bool notApplicable;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final coupon = this.coupon;
    if (coupon != null) {
      final textTheme = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.local_offer_outlined),
            title: Text(
              'Cupón ${coupon.code} · ${coupon.valueLabel}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: notApplicable
                ? Text(
                    coupon.discountType == DiscountType.freeShipping
                        ? 'Es de envío gratis: no cambia nada en la recogida '
                              'en tienda.'
                        : 'No se aplica a este pedido.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : coupon.description.isEmpty
                ? null
                : Text(coupon.description),
            trailing: IconButton(
              tooltip: 'Quitar cupón',
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Código de descuento',
                errorText: error,
                errorMaxLines: 2,
              ),
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => onApply(),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: applying ? null : onApply,
              child: applying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aplicar'),
            ),
          ),
        ],
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
