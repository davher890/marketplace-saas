import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth.dart';
import '../../repositories/profile_repository.dart';
import '../../widgets/common.dart';

/// Email + password sign in / sign up, through the API.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.redirectTo});

  /// Where to go after a successful sign in.
  final String? redirectTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final auth = ref.read(authProvider.notifier);

    try {
      if (_isSignUp) {
        final signedIn = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          fullName: _name.text.trim(),
          // Without it the confirmation link goes to Supabase's Site URL.
          redirectTo: authRedirectUrl(),
        );
        if (!signedIn) {
          // Email confirmation is enabled in Supabase.
          if (mounted) {
            showMessage(context, 'Revisa tu email para confirmar la cuenta.');
          }
          return;
        }
      } else {
        await auth.signIn(email: _email.text.trim(), password: _password.text);
      }
      if (mounted) context.go(widget.redirectTo ?? '/');
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showMessage(context, 'Escribe tu email primero.');
      return;
    }
    try {
      await ref.read(profileRepositoryProvider).sendPasswordReset(email);
      if (mounted) {
        showMessage(
          context,
          'Te hemos enviado un email para cambiar la contraseña.',
        );
      }
    } catch (error) {
      if (mounted) showMessage(context, describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ContentWidth(
      maxWidth: 420,
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(_isSignUp ? 'Crear cuenta' : 'Iniciar sesión'),
              if (_isSignUp) ...[
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Email no válido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                obscureText: true,
                autofillHints: [
                  _isSignUp
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onFieldSubmitted: (_) => _submit(),
                validator: (v) =>
                    (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_isSignUp ? 'Crear cuenta' : 'Entrar'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp
                      ? '¿Ya tienes cuenta? Inicia sesión'
                      : '¿No tienes cuenta? Regístrate',
                ),
              ),
              if (!_isSignUp)
                TextButton(
                  onPressed: _resetPassword,
                  child: const Text('He olvidado mi contraseña'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
