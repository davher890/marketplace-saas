import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/costs.dart';
import '../../models/shop_settings.dart';
import '../../repositories/admin_repository.dart';
import '../../repositories/catalog_repository.dart';
import '../../widgets/common.dart';

class AdminSettingsScreen extends ConsumerWidget {
  const AdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(shopSettingsProvider),
      onRetry: () => ref.invalidate(shopSettingsProvider),
      builder: (settings) => _SettingsForm(settings: settings),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final ShopSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _shipping = TextEditingController(
    text: centsToInput(widget.settings.shippingFlatCents),
  );
  late final _madrid = TextEditingController(
    text: widget.settings.shippingMadridCents == null
        ? ''
        : centsToInput(widget.settings.shippingMadridCents!),
  );
  late final _threshold = TextEditingController(
    text: widget.settings.freeShippingThresholdCents == null
        ? ''
        : centsToInput(widget.settings.freeShippingThresholdCents!),
  );
  late final _email = TextEditingController(
    text: widget.settings.contactEmail ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.settings.contactPhone ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_shipping, _madrid, _threshold, _email, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveSettings(
            ShopSettings(
              shippingFlatCents: parseCents(_shipping.text)!,
              shippingMadridCents: parseCents(_madrid.text),
              freeShippingThresholdCents: parseCents(_threshold.text),
              contactEmail: _email.text.trim().isEmpty
                  ? null
                  : _email.text.trim(),
              contactPhone: _phone.text.trim().isEmpty
                  ? null
                  : _phone.text.trim(),
            ),
          );
      ref.invalidate(shopSettingsProvider);
      if (mounted) showMessage(context, 'Ajustes guardados');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Ajustes de la tienda',
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _shipping,
            decoration: const InputDecoration(
              labelText: 'Envío (€)',
              helperText: 'Resto de España',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) =>
                parseCents(v ?? '') == null ? 'Importe no válido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _madrid,
            decoration: const InputDecoration(
              labelText: 'Envío en Madrid (€)',
              helperText:
                  'Códigos postales que empiezan por 28. Vacío: el envío normal',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) =>
                (v ?? '').trim().isNotEmpty && parseCents(v!) == null
                ? 'Importe no válido'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _threshold,
            decoration: const InputDecoration(
              labelText: 'Envío gratis a partir de (€)',
              helperText: 'Déjalo vacío para no ofrecer envío gratis',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) =>
                (v ?? '').trim().isNotEmpty && parseCents(v!) == null
                ? 'Importe no válido'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email de contacto'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono de contacto',
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Guardar'),
            ),
          ),
          const SizedBox(height: 40),
          const _BoxPricesSection(),
          const SizedBox(height: 40),
          const _SuppliersSection(),
        ],
      ),
    );
  }
}

/// "Cajas": the price of each box size, part of each article's cost.
class _BoxPricesSection extends ConsumerWidget {
  const _BoxPricesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cajas', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text(
          'Precio de cada tamaño de caja. Cada artículo de un pedido suma '
          'una caja a su coste.',
          style: TextStyle(color: AppColors.cocoa),
        ),
        const SizedBox(height: 12),
        AsyncView(
          value: ref.watch(costSettingsProvider),
          onRetry: () => ref.invalidate(costSettingsProvider),
          builder: (settings) => _BoxPricesForm(settings: settings),
        ),
      ],
    );
  }
}

class _BoxPricesForm extends ConsumerStatefulWidget {
  const _BoxPricesForm({required this.settings});

  final CostSettings settings;

  @override
  ConsumerState<_BoxPricesForm> createState() => _BoxPricesFormState();
}

class _BoxPricesFormState extends ConsumerState<_BoxPricesForm> {
  final _formKey = GlobalKey<FormState>();
  late final _prices = {
    for (final size in BoxSize.values)
      size: TextEditingController(
        text: centsToInput(widget.settings.priceOf(size)),
      ),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveCostSettings(
            CostSettings(
              boxSCents: parseCents(_prices[BoxSize.s]!.text)!,
              boxMCents: parseCents(_prices[BoxSize.m]!.text)!,
              boxLCents: parseCents(_prices[BoxSize.l]!.text)!,
            ),
          );
      ref.invalidate(costSettingsProvider);
      if (mounted) showMessage(context, 'Precios de las cajas guardados');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, size) in BoxSize.values.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _prices[size],
                    decoration: InputDecoration(
                      labelText: 'Caja ${size.apiName} (€)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) =>
                        parseCents(v ?? '') == null ? 'No válido' : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Guardar precios'),
          ),
        ],
      ),
    );
  }
}

/// "Proveedores": who the shop buys from and what picking an order up from
/// them costs. Each product picks one in its form.
class _SuppliersSection extends ConsumerWidget {
  const _SuppliersSection();

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Supplier supplier,
  ) async {
    final products = supplier.products;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar ${supplier.name}?'),
        content: Text(
          [
            if (products > 0)
              products == 1
                  ? 'El producto que lo tiene se quedará sin proveedor.'
                  : 'Los $products productos que lo tienen se quedarán sin proveedor.',
            'Los pedidos ya hechos no cambian.',
          ].join(' '),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminRepositoryProvider).deleteSupplier(supplier.id!);
      ref.invalidate(suppliersProvider);
      if (context.mounted) showMessage(context, 'Proveedor eliminado');
    } catch (error) {
      if (context.mounted) showMessage(context, describeError(error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Proveedores',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            TextButton.icon(
              onPressed: () => showSupplierDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Añadir proveedor'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'El transporte es lo que cuesta recoger un pedido del proveedor. '
          'En cada pedido se cuenta una vez por proveedor.',
          style: TextStyle(color: AppColors.cocoa),
        ),
        const SizedBox(height: 12),
        AsyncView(
          value: ref.watch(suppliersProvider),
          onRetry: () => ref.invalidate(suppliersProvider),
          builder: (suppliers) => suppliers.isEmpty
              ? const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Aún no hay proveedores.'),
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final (i, supplier) in suppliers.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          title: Text(supplier.name),
                          subtitle: Text(
                            'Transporte ${formatCents(supplier.transportCents)}'
                            ' · ${supplier.products == 1 ? '1 producto' : '${supplier.products} productos'}',
                          ),
                          onTap: () =>
                              showSupplierDialog(context, supplier: supplier),
                          trailing: IconButton(
                            tooltip: 'Eliminar ${supplier.name}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(context, ref, supplier),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// Adds a supplier, or edits [supplier].
Future<void> showSupplierDialog(
  BuildContext context, {
  Supplier? supplier,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => SupplierDialog(supplier: supplier),
  );
  if (saved == true && context.mounted) {
    showMessage(
      context,
      supplier == null ? 'Proveedor añadido' : 'Proveedor guardado',
    );
  }
}

class SupplierDialog extends ConsumerStatefulWidget {
  const SupplierDialog({super.key, this.supplier});

  final Supplier? supplier;

  @override
  ConsumerState<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends ConsumerState<SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _transport = TextEditingController(
    text: widget.supplier == null
        ? ''
        : centsToInput(widget.supplier!.transportCents),
  );
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _transport.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveSupplier(
            Supplier(
              id: widget.supplier?.id,
              name: _name.text.trim(),
              transportCents: parseCents(_transport.text)!,
            ),
          );
      ref.invalidate(suppliersProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showMessage(context, describeError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor',
      ),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Escribe el nombre' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _transport,
                decoration: const InputDecoration(
                  labelText: 'Transporte (€) *',
                  helperText: 'Lo que cuesta recoger un pedido',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) =>
                    parseCents(v ?? '') == null ? 'Importe no válido' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
