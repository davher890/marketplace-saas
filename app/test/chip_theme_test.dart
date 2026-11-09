import 'package:dona_galleta/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Color the chip's label is actually painted with.
  Color? labelColor(WidgetTester tester, String text) {
    final rich = tester.widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
    return rich.text.style?.color;
  }

  testWidgets('selected chips have light text on the dark background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Row(
            children: [
              FilterChip(
                label: const Text('Sin foto (2)'),
                selected: true,
                onSelected: (_) {},
              ),
              FilterChip(
                label: const Text('Sin categoría (0)'),
                selected: false,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(labelColor(tester, 'Sin foto (2)'), AppColors.cream);
    expect(labelColor(tester, 'Sin categoría (0)'), AppColors.ink);
  });
}
