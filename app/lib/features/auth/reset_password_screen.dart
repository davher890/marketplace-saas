import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../repositories/profile_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/password_fields.dart';

/// Opened from the password recovery email. Supabase signs the user in with
/// the link (before the app starts, see `Supabase.initialize`), so here they
/// only choose the new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).setNewPassword(_password.text);
      if (!mounted) return;
      showMessage(context, 'Contraseña cambiada.');
      context.go('/profile');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return ContentWidth(
      maxWidth: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('Nueva contraseña'),
          if (user == null) ...[
            const Text(
              'El enlace no es válido o ha caducado. Pide uno nuevo desde '
              '"He olvidado mi contraseña" y ábrelo en este mismo navegador.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('Ir a iniciar sesión'),
            ),
          ] else
            Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (user.email != null) ...[
                      Text(
                        'Cuenta: ${user.email}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                    NewPasswordFields(
                      password: _password,
                      confirmation: _confirm,
                      onSubmitted: _submit,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: const Text('Guardar contraseña'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
