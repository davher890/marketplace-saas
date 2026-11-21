import 'package:flutter/material.dart';

import '../repositories/profile_repository.dart';

/// Password field with an eye button to show or hide what is typed.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.validator,
    this.errorText,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final String? errorText;
  final bool autofocus;
  final bool enabled;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: !_visible,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onFieldSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
          icon: Icon(
            _visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}

/// "New password" + "repeat it" fields with their validation. Shared by the
/// profile and the password recovery screen.
class NewPasswordFields extends StatelessWidget {
  const NewPasswordFields({
    super.key,
    required this.password,
    required this.confirmation,
    required this.onSubmitted,
    this.differentFrom,
  });

  final TextEditingController password;
  final TextEditingController confirmation;
  final VoidCallback onSubmitted;

  /// When given, the new password must not be the same as this one.
  final TextEditingController? differentFrom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PasswordField(
          controller: password,
          label: 'Nueva contraseña',
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.next,
          validator: (v) {
            if (v == null || v.length < minPasswordLength) {
              return 'Mínimo $minPasswordLength caracteres';
            }
            if (differentFrom != null && v == differentFrom!.text) {
              return 'Debe ser distinta de la actual';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        PasswordField(
          controller: confirmation,
          label: 'Repite la nueva contraseña',
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => onSubmitted(),
          validator: (v) =>
              v != password.text ? 'Las contraseñas no coinciden' : null,
        ),
      ],
    );
  }
}
