import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/coupon.dart';
import '../../repositories/admin_repository.dart';
import '../../widgets/common.dart';

final _day = DateFormat('dd/MM/yyyy');

/// "Del 01/12/2026 al 31/12/2026".
String couponDates(Coupon coupon) =>
    'Del ${_day.format(coupon.startsOn!)} al ${_day.format(coupon.endsOn!)}';

/// Discount coupons: the ones that can be used today, then the rest
/// (scheduled, expired or switched off). Customers type the code at checkout.
class AdminCouponsScreen extends ConsumerWidget {
  const AdminCouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(adminCouponsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCouponDialog(context, ref),
        backgroundColor: AppColors.forest,
        foregroundColor: AppColors.cream,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo cupón'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminCouponsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text('Cupones', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 4),
            const Text(
              'Los clientes escriben el código al hacer el pedido. El '
              'descuento se aplica al precio final (productos y envío).',
            ),
            const SizedBox(height: 16),
            AsyncView(
              value: coupons,
              onRetry: () => ref.invalidate(adminCouponsProvider),
              builder: (all) {
                if (all.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Todavía no hay cupones.')),
                  );
                }
                final active = all
                    .where((c) => c.status == CouponStatus.active)
                    .toList();
                final inactive = all
                    .where((c) => c.status != CouponStatus.active)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionTitle('Activos (${active.length})'),
                    if (active.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Ningún cupón se puede usar hoy.'),
                      ),
                    for (final coupon in active) _CouponCard(coupon: coupon),
                    const SizedBox(height: 8),
                    SectionTitle('No activos (${inactive.length})'),
                    if (inactive.isEmpty)
                      const Text('Todos los cupones se pueden usar hoy.'),
                    for (final coupon in inactive) _CouponCard(coupon: coupon),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CouponCard extends ConsumerStatefulWidget {
  const _CouponCard({required this.coupon});

  final Coupon coupon;

  @override
  ConsumerState<_CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends ConsumerState<_CouponCard> {
  bool _saving = false;

  Future<void> _setActive(bool value) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .setCouponActive(widget.coupon.id!, value);
      ref.invalidate(adminCouponsProvider);
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coupon = widget.coupon;
    final textTheme = Theme.of(context).textTheme;
    final uses = switch (coupon.uses) {
      0 => 'Sin usar',
      1 => 'Usado en 1 pedido',
      final n => 'Usado en $n pedidos',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showCouponDialog(context, ref, coupon: coupon),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            coupon.code,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                          _Pill(coupon.valueLabel, color: AppColors.sage),
                          _Pill(
                            coupon.status.label,
                            color: _statusColor(coupon.status),
                          ),
                        ],
                      ),
                      if (coupon.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(coupon.description),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${couponDates(coupon)} · ${coupon.usage.label} · $uses',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: coupon.isActive ? 'Desactivar' : 'Activar',
                  child: Switch(
                    value: coupon.isActive,
                    onChanged: _saving ? null : _setActive,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColor(CouponStatus status) => switch (status) {
    CouponStatus.active => const Color(0xFFB7D7A8),
    CouponStatus.scheduled => const Color(0xFFA8C5DA),
    CouponStatus.expired => const Color(0xFFE0D6D2),
    CouponStatus.disabled => const Color(0xFFDDB0B0),
  };
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// Creates a coupon, or edits [coupon].
Future<void> showCouponDialog(
  BuildContext context,
  WidgetRef ref, {
  Coupon? coupon,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => CouponDialog(coupon: coupon),
  );
  if (saved == true) {
    ref.invalidate(adminCouponsProvider);
    if (context.mounted) {
      showMessage(
        context,
        coupon == null ? 'Cupón creado.' : 'Cupón guardado.',
      );
    }
  }
}

class CouponDialog extends ConsumerStatefulWidget {
  const CouponDialog({super.key, this.coupon});

  final Coupon? coupon;

  @override
  ConsumerState<CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends ConsumerState<CouponDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.coupon?.code);
  late final _description = TextEditingController(
    text: widget.coupon?.description,
  );
  late final _amount = TextEditingController(
    text: widget.coupon?.amountCents == null
        ? ''
        : centsToInput(widget.coupon!.amountCents!),
  );
  late final _percent = TextEditingController(
    text: widget.coupon?.percent?.toString() ?? '',
  );
  late DateTimeRange? _dates =
      widget.coupon?.startsOn == null || widget.coupon?.endsOn == null
      ? null
      : DateTimeRange(
          start: widget.coupon!.startsOn!,
          end: widget.coupon!.endsOn!,
        );
  late CouponUsage _usage = widget.coupon?.usage ?? CouponUsage.oncePerUser;
  late DiscountType _type = widget.coupon?.discountType ?? DiscountType.amount;
  late bool _isActive = widget.coupon?.isActive ?? true;
  bool _saving = false;
  bool _datesMissing = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _description.dispose();
    _amount.dispose();
    _percent.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(today.year + 5, 12, 31),
      initialDateRange: _dates,
      currentDate: today,
      helpText: 'Fechas de validez',
      saveText: 'Aceptar',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      fieldStartLabelText: 'Desde',
      fieldEndLabelText: 'Hasta',
      fieldStartHintText: 'dd/mm/aaaa',
      fieldEndHintText: 'dd/mm/aaaa',
      errorInvalidRangeText: 'Las fechas no son válidas',
    );
    if (picked != null) {
      setState(() {
        _dates = picked;
        _datesMissing = false;
      });
    }
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    setState(() => _datesMissing = _dates == null);
    if (!formOk || _dates == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveCoupon(
            Coupon(
              code: _code.text.trim().toUpperCase(),
              description: _description.text.trim(),
              startsOn: _dates!.start,
              endsOn: _dates!.end,
              usage: _usage,
              discountType: _type,
              amountCents: _type == DiscountType.amount
                  ? parseCents(_amount.text)
                  : null,
              percent: _type == DiscountType.percent
                  ? int.tryParse(_percent.text.trim())
                  : null,
              isActive: _isActive,
            ),
            couponId: widget.coupon?.id,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final errorColor = Theme.of(context).colorScheme.error;
    final used = (widget.coupon?.uses ?? 0) > 0;

    return AlertDialog(
      title: Text(widget.coupon == null ? 'Nuevo cupón' : 'Editar cupón'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _code,
                  autofocus: widget.coupon == null,
                  decoration: InputDecoration(
                    labelText: 'Código *',
                    hintText: 'NAVIDAD10',
                    helperText: used
                        ? 'Ya se ha usado: los pedidos guardan el código '
                              'con el que se hicieron.'
                        : 'Lo que escribe el cliente. Letras, números, - y _',
                    helperMaxLines: 2,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                    _UpperCase(),
                  ],
                  maxLength: 30,
                  validator: (v) => (v ?? '').trim().length < 3
                      ? 'Al menos 3 caracteres'
                      : null,
                ),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    helperText: 'Para ti y para el cliente al aplicarlo',
                  ),
                  maxLength: 300,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Text('Validez *', style: textTheme.labelLarge),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _pickDates,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    _dates == null
                        ? 'Elegir fechas'
                        : 'Del ${_day.format(_dates!.start)} '
                              'al ${_day.format(_dates!.end)}',
                  ),
                ),
                if (_datesMissing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Elige las fechas',
                      style: TextStyle(color: errorColor, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Restricción de uso', style: textTheme.labelLarge),
                const SizedBox(height: 4),
                SegmentedButton<CouponUsage>(
                  segments: [
                    for (final usage in CouponUsage.values)
                      ButtonSegment(value: usage, label: Text(usage.label)),
                  ],
                  selected: {_usage},
                  onSelectionChanged: (s) => setState(() => _usage = s.single),
                ),
                const SizedBox(height: 4),
                Text(
                  _usage == CouponUsage.oncePerUser
                      ? 'Cada cliente puede usarlo en un solo pedido.'
                      : 'Se puede usar en todos los pedidos, uno por pedido.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text('Descuento', style: textTheme.labelLarge),
                const SizedBox(height: 4),
                SegmentedButton<DiscountType>(
                  segments: [
                    for (final type in DiscountType.values)
                      ButtonSegment(value: type, label: Text(type.label)),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.single),
                ),
                const SizedBox(height: 12),
                if (_type == DiscountType.amount)
                  TextFormField(
                    key: const ValueKey('amount'),
                    controller: _amount,
                    decoration: const InputDecoration(
                      labelText: 'Euros de descuento *',
                      suffixText: '€',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) => (parseCents(v ?? '') ?? 0) <= 0
                        ? 'Importe no válido'
                        : null,
                  ),
                if (_type == DiscountType.percent)
                  TextFormField(
                    key: const ValueKey('percent'),
                    controller: _percent,
                    decoration: const InputDecoration(
                      labelText: 'Porcentaje de descuento *',
                      suffixText: '%',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final value = int.tryParse(v ?? '');
                      return value == null || value < 1 || value > 100
                          ? 'Entre 1 y 100'
                          : null;
                    },
                  ),
                if (_type == DiscountType.freeShipping)
                  Text(
                    'El envío sale gratis. No se aplica a los pedidos de '
                    'recogida en tienda, que ya no pagan envío.',
                    style: textTheme.bodySmall,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activado'),
                  subtitle: const Text(
                    'Desactívalo para que deje de funcionar sin borrarlo',
                  ),
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                ),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: errorColor)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Codes are stored in capitals: show them that way while typing.
class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}
