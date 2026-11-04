import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
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
    for (final c in [_shipping, _threshold, _email, _phone]) {
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
            decoration: const InputDecoration(labelText: 'Coste de envío (€)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) =>
                parseCents(v ?? '') == null ? 'Importe no válido' : null,
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
        ],
      ),
    );
  }
}
