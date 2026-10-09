import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_example/main.dart';

void main() {
  testWidgets('ColorSelector reports the tapped color', (tester) async {
    ProductColor? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorSelector(selected: ProductColor.cream, onSelect: (color) => tapped = color),
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector).at(ProductColor.mint.index));
    expect(tapped, ProductColor.mint);
  });
}
