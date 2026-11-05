import 'package:flutter/material.dart';

import '../repositories/profile_repository.dart';

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
        TextFormField(
          controller: password,
          decoration: const InputDecoration(labelText: 'Nueva contraseña'),
          obscureText: true,
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
        TextFormField(
          controller: confirmation,
          decoration: const InputDecoration(
            labelText: 'Repite la nueva contraseña',
          ),
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          onFieldSubmitted: (_) => onSubmitted(),
          validator: (v) =>
              v != password.text ? 'Las contraseñas no coinciden' : null,
        ),
      ],
    );
  }
}
