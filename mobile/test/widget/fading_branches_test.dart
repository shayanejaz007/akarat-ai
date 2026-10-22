import 'package:akarat/app/router/scaffold_with_nav.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A tab with its own state: a counter that only taps change.
class _Counter extends StatefulWidget {
  const _Counter(this.name);
  final String name;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: Center(
      child: TextButton(onPressed: () => setState(() => taps++), child: Text('${widget.name} $taps')),
    ),
  );
}

Widget _tabs(int index) => MaterialApp(
  home: FadingBranches(index: index, children: const [_Counter('A'), _Counter('B'), _Counter('C')]),
);

void main() {
  testWidgets('switching tabs keeps every tab as it was, and the chosen one takes the taps', (tester) async {
    await tester.pumpWidget(_tabs(0));
    await tester.tap(find.text('A 0'));
    await tester.pump();
    expect(find.text('A 1'), findsOneWidget);

    // To C, past B, and back: the order of the layers changes each time.
    await tester.pumpWidget(_tabs(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('C 0'));
    await tester.pump();
    await tester.pumpWidget(_tabs(1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_tabs(0));
    await tester.pumpAndSettle();

    expect(find.text('A 1'), findsOneWidget, reason: "A's state survived");
    await tester.pumpWidget(_tabs(2));
    await tester.pumpAndSettle();
    expect(find.text('C 1'), findsOneWidget, reason: "C's state survived");
    await tester.tap(find.text('C 1'));
    await tester.pump();
    expect(find.text('C 2'), findsOneWidget, reason: 'the chosen tab is on top and takes taps');
  });

  testWidgets('mid-switch, the incoming tab fades in over the outgoing one', (tester) async {
    await tester.pumpWidget(_tabs(0));
    await tester.pumpWidget(_tabs(1));
    await tester.pump(const Duration(milliseconds: 60));
    final fades = tester.widgetList<FadeTransition>(find.byType(FadeTransition)).toList();
    // The last layer painted is the incoming tab, part-way through its fade.
    expect(fades.last.opacity.value, inExclusiveRange(0.0, 1.0));
    expect(find.text('A 0'), findsOneWidget, reason: 'the outgoing tab is still there underneath');
    await tester.pumpAndSettle();
    expect(find.text('A 0'), findsNothing, reason: 'and steps away once the fade ends');
  });
}
