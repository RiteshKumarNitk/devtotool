import 'package:debug_browser/features/browser/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(String id, int dir) => MaterialApp(
      home: SizedBox(
        width: 400,
        height: 600,
        child: TabTransition(tabId: id, direction: dir, child: Text('page $id')),
      ),
    );

Offset slideOf(WidgetTester t, String text) {
  final slide = t.widget<SlideTransition>(find.ancestor(of: find.text(text), matching: find.byType(SlideTransition)).first);
  return slide.position.value;
}

void main() {
  testWidgets('next tab slides in from the right, old one leaves left', (t) async {
    await t.pumpWidget(host('a', 1));
    await t.pumpWidget(host('b', 1));
    await t.pump(const Duration(milliseconds: 60));
    expect(find.text('page a'), findsOneWidget, reason: 'both visible mid-transition');
    expect(slideOf(t, 'page b').dx, greaterThan(0));
    expect(slideOf(t, 'page a').dx, lessThan(0));
    await t.pumpAndSettle();
    expect(find.text('page a'), findsNothing);
    expect(slideOf(t, 'page b'), Offset.zero);
  });

  testWidgets('previous tab slides in from the left', (t) async {
    await t.pumpWidget(host('a', -1));
    await t.pumpWidget(host('b', -1));
    await t.pump(const Duration(milliseconds: 60));
    expect(slideOf(t, 'page b').dx, lessThan(0));
    expect(slideOf(t, 'page a').dx, greaterThan(0));
  });

  testWidgets('jumping between tabs fades (no slide)', (t) async {
    await t.pumpWidget(host('a', 0));
    await t.pumpWidget(host('b', 0));
    await t.pump(const Duration(milliseconds: 60));
    expect(find.descendant(of: find.byType(TabTransition), matching: find.byType(SlideTransition)), findsNothing);
    expect(find.ancestor(of: find.text('page b'), matching: find.byType(FadeTransition)), findsWidgets);
  });

  testWidgets('same tab rebuilding does not animate', (t) async {
    await t.pumpWidget(host('a', 1));
    await t.pumpWidget(host('a', 1));
    await t.pump(const Duration(milliseconds: 60));
    expect(find.text('page a'), findsOneWidget);
  });
}
