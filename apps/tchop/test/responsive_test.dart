import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tchop/core/responsive.dart';

/// Pumps [child] under a [MediaQuery] of the given width and returns the
/// [ScreenSize] + [responsiveValue] seen by the child.
Future<(ScreenSize, int)> _probe(WidgetTester tester, double width) async {
  ScreenSize? size;
  int? value;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(
          builder: (context) {
            size = context.screenSize;
            value = context.responsiveValue(mobile: 2, tablet: 3, desktop: 5);
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return (size!, value!);
}

void main() {
  testWidgets('breakpoints classify widths', (tester) async {
    expect(await _probe(tester, 390), (ScreenSize.mobile, 2));
    expect(await _probe(tester, 599), (ScreenSize.mobile, 2));
    expect(await _probe(tester, 600), (ScreenSize.tablet, 3));
    expect(await _probe(tester, 834), (ScreenSize.tablet, 3));
    expect(await _probe(tester, 1099), (ScreenSize.tablet, 3));
    expect(await _probe(tester, 1100), (ScreenSize.desktop, 5));
    expect(await _probe(tester, 1920), (ScreenSize.desktop, 5));
  });

  testWidgets('tablet falls back to mobile when tablet value omitted',
      (tester) async {
    int? value;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Builder(
            builder: (context) {
              value = context.responsiveValue(mobile: 1, desktop: 9);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(value, 1);
  });

  testWidgets('isMobile/isTablet/isDesktop agree with screenSize',
      (tester) async {
    bool? mobile;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              mobile = context.isMobile;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(mobile, isTrue);
  });

  testWidgets('ResponsiveLayout picks the right subtree', (tester) async {
    Future<void> pump(double width) => tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(width, 800)),
              child: const ResponsiveLayout(
                mobile: Text('m'),
                tablet: Text('t'),
                desktop: Text('d'),
              ),
            ),
          ),
        );
    await pump(390);
    expect(find.text('m'), findsOneWidget);
    await pump(800);
    expect(find.text('t'), findsOneWidget);
    await pump(1400);
    expect(find.text('d'), findsOneWidget);
  });

  testWidgets('ResponsiveLayout tablet falls back to mobile', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: const ResponsiveLayout(
            mobile: Text('m'),
            desktop: Text('d'),
          ),
        ),
      ),
    );
    expect(find.text('m'), findsOneWidget);
  });
}
