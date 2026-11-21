import 'package:dona_galleta/widgets/password_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the eye button shows and hides the password', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PasswordField(controller: controller, label: 'Contraseña'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'galleta123');

    bool obscured() =>
        tester.widget<TextField>(find.byType(TextField)).obscureText;

    expect(obscured(), isTrue);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(obscured(), isFalse);
    expect(find.text('galleta123'), findsOneWidget);

    await tester.tap(find.byTooltip('Ocultar contraseña'));
    await tester.pump();
    expect(obscured(), isTrue);
    // Showing it doesn't change what was typed.
    expect(controller.text, 'galleta123');
  });
}
