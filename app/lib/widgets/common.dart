import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/order.dart';
import '../repositories/api_client.dart';

/// Renders loading / error / data states of an [AsyncValue] consistently.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.cocoa),
              const SizedBox(height: 12),
              Text(describeError(error), textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Spanish messages for the API's error codes (sign in, passwords...).
const _errorMessages = {
  'invalid_credentials': 'Email o contraseña incorrectos.',
  'email_not_confirmed':
      'Confirma tu email antes de entrar: revisa tu bandeja de entrada.',
  'user_already_exists': 'Ya hay una cuenta con ese email.',
  'email_exists': 'Ya hay una cuenta con ese email.',
  'email_address_invalid': 'Email no válido.',
  'weak_password': 'La contraseña es demasiado débil.',
  'same_password': 'La nueva contraseña tiene que ser distinta de la actual.',
  'wrong_password': 'La contraseña actual no es correcta.',
  'current_password_required': 'Escribe tu contraseña actual.',
  'over_request_rate_limit':
      'Demasiados intentos. Espera unos minutos y vuelve a probar.',
  'over_email_send_rate_limit':
      'Demasiados emails enviados. Espera unos minutos y vuelve a probar.',
  'signup_disabled': 'Ahora mismo no se pueden crear cuentas.',
  'session_expired': 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
  'session_not_found': 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
  'refresh_token_not_found': 'Tu sesión ha caducado. Vuelve a iniciar sesión.',
  'refresh_token_already_used':
      'Tu sesión ha caducado. Vuelve a iniciar sesión.',
};

/// Human readable message for API / network errors.
String describeError(Object error) {
  if (error is ApiException) return _errorMessages[error.code] ?? error.message;
  return error.toString();
}

/// Shows snack bars from outside the widget tree (notifications, email links).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Centers content and caps its width on large screens.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 1100,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 16),
          child: child,
        ),
      ),
    );
  }
}

/// Product image with a soft placeholder when missing or failing to load.
class ProductImageView extends StatelessWidget {
  const ProductImageView({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.sageLight,
      child: Center(
        child: Icon(Icons.image_outlined, size: 40, color: AppColors.forest),
      ),
    );
    if (url == null) return placeholder;
    return Image.network(
      url!,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const ColoredBox(color: AppColors.sageLight),
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  static Color colorOf(OrderStatus status) => switch (status) {
    OrderStatus.pending => const Color(0xFFE8C872),
    OrderStatus.paid => const Color(0xFF9CC5A1),
    OrderStatus.processing => const Color(0xFFA8C5DA),
    OrderStatus.shipped => const Color(0xFFB9A8DA),
    OrderStatus.delivered => AppColors.sage,
    OrderStatus.cancelled => const Color(0xFFDDB0B0),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorOf(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall,
      ),
    );
  }
}
