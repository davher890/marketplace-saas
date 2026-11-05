import 'package:dona_galleta/features/profile/profile_screen.dart';
import 'package:dona_galleta/repositories/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the calls the screen makes instead of talking to the API / Auth.
class _FakeProfileRepository implements ProfileRepository {
  final calls = <String>[];

  @override
  Future<Profile> updateProfile({String? fullName, String? phone}) async {
    calls.add('update $fullName|$phone');
    return Profile(id: 'u1', isAdmin: false, fullName: fullName, phone: phone);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => calls.add('password $currentPassword>$newPassword');

  @override
  Future<void> sendPasswordReset(String email) async =>
      calls.add('reset $email');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeProfileRepository repository;

  Future<void> pumpProfile(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = _FakeProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            (ref) async => const Profile(
              id: 'u1',
              isAdmin: false,
              email: 'ana@example.com',
              fullName: 'Ana',
            ),
          ),
          profileRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ProfileScreen())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextField));

  testWidgets('email is shown but not editable', (tester) async {
    await pumpProfile(tester);
    final email = tester.widget<TextField>(field('Email'));
    expect(email.controller?.text ?? '', 'ana@example.com');
    expect(email.enabled, isFalse);
    expect(find.text('El email no se puede modificar.'), findsOneWidget);
  });

  testWidgets('saves name and phone, rejecting an invalid phone', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.enterText(field('Nombre'), '  Ana López ');
    await tester.enterText(field('Teléfono'), 'abc');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Teléfono no válido'), findsOneWidget);
    expect(repository.calls, isEmpty);

    await tester.enterText(field('Teléfono'), '+34 600 123 456');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['update Ana López|+34 600 123 456']);
  });

  testWidgets('password change needs matching new passwords', (tester) async {
    await pumpProfile(tester);
    await tester.enterText(field('Contraseña actual'), 'old-secret');
    await tester.enterText(field('Nueva contraseña'), 'new-secret');
    await tester.enterText(field('Repite la nueva contraseña'), 'other');
    await tester.tap(find.widgetWithText(FilledButton, 'Cambiar contraseña'));
    await tester.pumpAndSettle();
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(repository.calls, isEmpty);

    await tester.enterText(field('Repite la nueva contraseña'), 'new-secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Cambiar contraseña'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['password old-secret>new-secret']);
  });

  testWidgets('recovery sends the link to the account email', (tester) async {
    await pumpProfile(tester);
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(repository.calls, ['reset ana@example.com']);
  });

  test('validatePhone', () {
    expect(validatePhone(''), isNull);
    expect(validatePhone('+34 600 123 456'), isNull);
    expect(validatePhone('(91) 123-4567'), isNull);
    expect(validatePhone('abc'), isNotNull);
    expect(validatePhone('123'), isNotNull);
  });
}
