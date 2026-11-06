import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/password_fields.dart';

/// "Mi perfil": personal details, password change, password recovery and
/// account deletion.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ContentWidth(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Mi perfil'),
          AsyncView(
            value: ref.watch(profileProvider),
            onRetry: () => ref.invalidate(profileProvider),
            builder: (profile) => profile == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Keyed by id so the form resets if the account changes.
                      _DetailsCard(key: ValueKey(profile.id), profile: profile),
                      const SizedBox(height: 24),
                      const _PasswordCard(),
                      const SizedBox(height: 24),
                      _RecoveryCard(email: profile.email),
                      const SizedBox(height: 24),
                      _DeleteAccountCard(isAdmin: profile.isAdmin),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends ConsumerStatefulWidget {
  const _DetailsCard({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<_DetailsCard> createState() => _DetailsCardState();
}

class _DetailsCardState extends ConsumerState<_DetailsCard> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _phone = TextEditingController(text: widget.profile.phone);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            fullName: _name.text.trim(),
            phone: _phone.text.trim(),
          );
      ref.invalidate(profileProvider);
      if (mounted) showMessage(context, 'Datos guardados.');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Datos personales',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              initialValue: widget.profile.email ?? '',
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Email',
                helperText: 'El email no se puede modificar.',
                suffixIcon: Icon(Icons.lock_outline, color: AppColors.forest),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              maxLength: 120,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Escribe tu nombre' : null,
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Teléfono',
                hintText: '+34 600 000 000',
              ),
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: validatePhone,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordCard extends ConsumerStatefulWidget {
  const _PasswordCard();

  @override
  ConsumerState<_PasswordCard> createState() => _PasswordCardState();
}

class _PasswordCardState extends ConsumerState<_PasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      _formKey.currentState!.reset();
      for (final c in [_current, _new, _confirm]) {
        c.clear();
      }
      if (mounted) showMessage(context, 'Contraseña cambiada.');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Cambiar contraseña',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _current,
                decoration: const InputDecoration(
                  labelText: 'Contraseña actual',
                ),
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Escribe tu contraseña actual'
                    : null,
              ),
              const SizedBox(height: 12),
              NewPasswordFields(
                password: _new,
                confirmation: _confirm,
                onSubmitted: _submit,
                differentFrom: _current,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: const Text('Cambiar contraseña'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryCard extends ConsumerStatefulWidget {
  const _RecoveryCard({required this.email});

  final String? email;

  @override
  ConsumerState<_RecoveryCard> createState() => _RecoveryCardState();
}

class _RecoveryCardState extends ConsumerState<_RecoveryCard> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .sendPasswordReset(widget.email!);
      if (mounted) {
        showMessage(
          context,
          'Te hemos enviado un email a ${widget.email} para elegir una nueva contraseña.',
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Recuperar contraseña',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿No recuerdas tu contraseña actual? Te enviaremos un enlace a '
            '${widget.email ?? 'tu email'} para elegir una nueva.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _sending || widget.email == null ? null : _send,
              child: const Text('Enviar enlace'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Google Play requires apps with sign up to let users delete their account.
class _DeleteAccountCard extends StatelessWidget {
  const _DeleteAccountCard({required this.isAdmin});

  final bool isAdmin;

  Future<void> _delete(BuildContext context) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (deleted == true && context.mounted) {
      showMessage(context, 'Tu cuenta se ha eliminado.');
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Section(
      title: 'Eliminar cuenta',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isAdmin
                ? 'Las cuentas de administrador no se pueden eliminar desde la '
                      'app. Primero hay que quitarle el rol de administrador.'
                : 'Se borrarán tu perfil, tu carrito y tus datos de acceso. '
                      'Los pedidos que hayas hecho se conservan, sin estar '
                      'ligados a ninguna cuenta, porque la tienda está obligada '
                      'a guardar sus ventas.',
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error),
              ),
              onPressed: isAdmin ? null : () => _delete(context),
              child: const Text('Eliminar mi cuenta'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for the password again and deletes the account. Pops `true` when done.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .deleteAccount(password: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('¿Eliminar tu cuenta?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Esta acción no se puede deshacer. Escribe tu contraseña para '
            'confirmarla.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            enabled: !_deleting,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              errorText: _error,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _password.text.isEmpty ? null : _delete(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: _deleting || _password.text.isEmpty ? null : _delete,
          child: const Text('Eliminar'),
        ),
      ],
    );
  }
}
