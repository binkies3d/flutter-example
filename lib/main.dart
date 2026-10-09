import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

import 'binkies_viewer.dart';

void main() {
  runApp(const ExampleApp());
}

/// The product variants the app offers. [productId] is the Binkies content id that is sent to
/// the viewer as the "product" setting, the rest is only used by the app's own UI.
enum ProductColor {
  cream('Cream', Color(0xFFF1E9D6), 'samsung-galaxy-z-flip8-cream'),
  mint('Mint', Color(0xFFBFE3D0), 'samsung-galaxy-z-flip8-mint'),

  // No 3D model exists for this content id, so the page answers with "hide"
  pink('Pink', Color(0xFFF4C6D2), 'samsung-galaxy-z-flip8-pink');

  const ProductColor(this.label, this.swatch, this.productId);

  final String label;
  final Color swatch;
  final String productId;
}

// Material 3 with the wallpaper colors (Android 12+), like the Kotlin example
const _fallbackSeedColor = Color(0xFF6650A4);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp(
        title: 'FlutterExample',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: lightDynamic ?? ColorScheme.fromSeed(seedColor: _fallbackSeedColor)),
        darkTheme: ThemeData(
          colorScheme: darkDynamic ?? ColorScheme.fromSeed(seedColor: _fallbackSeedColor, brightness: Brightness.dark),
        ),
        home: const ProductScreen(),
      ),
    );
  }
}

/// Example product page: the 3D viewer on top, the color selector below it.
/// Selecting a color only changes [BinkiesViewer]'s product, the WebView stays loaded.
class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  var _selected = ProductColor.cream;
  // null until the page sends its first "show" or "hide"
  bool? _visible;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stays collapsed until the page reports that the selected product has a 3D model
            BinkiesViewer(
              settings: BinkiesSettings(
                product: _selected.productId,
                // Optional, these are the defaults
                thumbnailsPlacement: ThumbnailsPlacement.bottom,
                thumbnailsSelectedColor: const Color(0xFF262626),
              ),
              visible: _visible == true,
              onVisibilityChange: (visible) => setState(() => _visible = visible),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Color: ${_selected.label}${_visible == false ? ' (no 3D)' : ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ColorSelector(selected: _selected, onSelect: (color) => setState(() => _selected = color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of round color swatches, the selected one gets a border.
class ColorSelector extends StatelessWidget {
  const ColorSelector({super.key, required this.selected, required this.onSelect});

  final ProductColor selected;
  final ValueChanged<ProductColor> onSelect;

  @override
  Widget build(BuildContext context) {
    final selectedBorder = Theme.of(context).colorScheme.onSurface;
    return Row(
      spacing: 16,
      children: [
        for (final color in ProductColor.values)
          GestureDetector(
            onTap: () => onSelect(color),
            child: Container(
              width: 44,
              height: 44,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(width: 2, color: color == selected ? selectedBorder : Colors.transparent),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.swatch),
              ),
            ),
          ),
      ],
    );
  }
}
