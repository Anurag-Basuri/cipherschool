import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/presentation/widgets/product_card.dart';

void main() {
  testWidgets('QuantityStepper shows the quantity and reacts to taps',
      (tester) async {
    var increments = 0;
    var decrements = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: QuantityStepper(
            quantity: 3,
            canIncrement: true,
            onIncrement: () => increments++,
            onDecrement: () => decrements++,
          ),
        ),
      ),
    ));

    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.remove));
    expect(increments, 1);
    expect(decrements, 1);
  });
}
