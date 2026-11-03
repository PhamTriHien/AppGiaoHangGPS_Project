import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/presentation/widgets/motion_3d_effects.dart';

class _MountCounterProbe extends StatefulWidget {
  const _MountCounterProbe({
    required this.onInit,
    required this.child,
  });

  final VoidCallback onInit;
  final Widget child;

  @override
  State<_MountCounterProbe> createState() => _MountCounterProbeState();
}

class _MountCounterProbeState extends State<_MountCounterProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  testWidgets(
    'Motion3dInteractiveSurface applies Matrix4 perspective tilt, preserves child State, and settles',
    (tester) async {
      var tapCount = 0;
      var mountCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Motion3dInteractiveSurface(
                forceInTest: true,
                maxTilt: 0.10,
                pressScale: 0.94,
                child: _MountCounterProbe(
                  onInit: () => mountCount++,
                  child: Material(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      key: const ValueKey('target-surface'),
                      onTap: () => tapCount++,
                      child: const SizedBox(width: 220, height: 120),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final transformFinder = find.descendant(
        of: find.byType(Motion3dInteractiveSurface),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
      expect(tester.widget<Transform>(transformFinder).transform.isIdentity(), isTrue);
      expect(mountCount, 1);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final boxRect = tester.getRect(find.byKey(const ValueKey('target-surface')));
      await gesture.moveTo(boxRect.topRight - const Offset(12, -12));
      await tester.pump(const Duration(milliseconds: 80));

      final hoverTransform = tester.widget<Transform>(transformFinder);
      expect(hoverTransform.transform.entry(3, 2), closeTo(0.0016, 0.0001));
      expect(hoverTransform.transform.isIdentity(), isFalse);
      expect(mountCount, 1);

      await gesture.down(boxRect.center);
      await tester.pump(const Duration(milliseconds: 60));
      await gesture.up();
      await tester.pump();
      expect(tapCount, 1);
      expect(mountCount, 1);

      await gesture.moveTo(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(tester.widget<Transform>(transformFinder).transform.isIdentity(), isTrue);
      expect(mountCount, 1);
    },
  );

  testWidgets(
    'Motion3dSectionTransition animates 3D depth on key change without remounting child State',
    (tester) async {
      final tab = ValueNotifier<int>(0);
      addTearDown(tab.dispose);
      var mountCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: tab,
              builder: (context, active, _) => Motion3dSectionTransition(
                transitionKey: active,
                forceInTest: true,
                child: _MountCounterProbe(
                  onInit: () => mountCount++,
                  child: SizedBox(
                    width: 300,
                    height: 200,
                    child: Text('Tab $active'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final transformFinder = find.descendant(
        of: find.byType(Motion3dSectionTransition),
        matching: find.byType(Transform),
      );
      expect(find.text('Tab 0'), findsOneWidget);
      expect(tester.widget<Transform>(transformFinder).transform.isIdentity(), isTrue);
      expect(mountCount, 1);

      tab.value = 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('Tab 1'), findsOneWidget);
      expect(tester.widget<Transform>(transformFinder).transform.isIdentity(), isFalse);
      expect(mountCount, 1);

      await tester.pumpAndSettle();
      expect(tester.widget<Transform>(transformFinder).transform.isIdentity(), isTrue);
      expect(mountCount, 1);
    },
  );

  testWidgets(
    'Motion3dFloatingLayer animates continuous 3D levitation across frames and disposes cleanly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Motion3dFloatingLayer(
                forceInTest: true,
                floatAmplitude: 4.0,
                tiltAmplitude: 0.03,
                period: Duration(milliseconds: 1200),
                child: SizedBox(width: 80, height: 80),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      final transformFinder = find.descendant(
        of: find.byType(Motion3dFloatingLayer),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
      final firstMatrix = tester.widget<Transform>(transformFinder).transform.clone();

      await tester.pump(const Duration(milliseconds: 300));
      final secondMatrix = tester.widget<Transform>(transformFinder).transform;
      expect(secondMatrix, isNot(equals(firstMatrix)));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
