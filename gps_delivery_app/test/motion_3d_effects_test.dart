import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_delivery_app/core/theme/admin_studio_theme.dart';
import 'package:gps_delivery_app/core/theme/app_theme.dart';
import 'package:gps_delivery_app/presentation/widgets/animated_3d_ui_icons.dart';
import 'package:gps_delivery_app/presentation/widgets/ghst_button_icon.dart';
import 'package:gps_delivery_app/presentation/widgets/motion_3d_effects.dart';
import 'package:gps_delivery_app/presentation/widgets/system_state_screens.dart';

class _MountAndBuildProbe extends StatefulWidget {
  const _MountAndBuildProbe({
    required this.onInit,
    required this.onBuild,
    required this.child,
  });

  final VoidCallback onInit;
  final VoidCallback onBuild;
  final Widget child;

  @override
  State<_MountAndBuildProbe> createState() => _MountAndBuildProbeState();
}

class _MountAndBuildProbeState extends State<_MountAndBuildProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return widget.child;
  }
}

void main() {
  testWidgets(
    'Motion3dInteractiveSurface uses spring physics, FilterQuality.medium when tilted, zero ClipRRect, and zero child rebuilds',
    (tester) async {
      var tapCount = 0;
      var mountCount = 0;
      var buildCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Motion3dInteractiveSurface(
                forceInTest: true,
                maxTilt: 0.05,
                pressScale: 0.96,
                child: _MountAndBuildProbe(
                  onInit: () => mountCount++,
                  onBuild: () => buildCount++,
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
      final clipRRectFinder = find.descendant(
        of: find.byType(Motion3dInteractiveSurface),
        matching: find.byType(ClipRRect),
      );
      expect(transformFinder, findsOneWidget);
      expect(clipRRectFinder, findsNothing);

      final restTransform = tester.widget<Transform>(transformFinder);
      expect(restTransform.transform.isIdentity(), isTrue);
      expect(restTransform.filterQuality, isNull);
      expect(mountCount, 1);
      expect(buildCount, 1);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final boxRect = tester.getRect(find.byKey(const ValueKey('target-surface')));
      await gesture.moveTo(boxRect.topRight - const Offset(12, -12));
      await tester.pump(const Duration(milliseconds: 64));

      final hoverTransform = tester.widget<Transform>(transformFinder);
      expect(hoverTransform.transform.entry(3, 2), closeTo(0.0009, 0.00005));
      expect(hoverTransform.transform.isIdentity(), isFalse);
      expect(hoverTransform.filterQuality, FilterQuality.medium);
      expect(mountCount, 1);
      expect(buildCount, 1);

      await gesture.down(boxRect.center);
      await tester.pump(const Duration(milliseconds: 48));
      await gesture.up();
      await tester.pump();
      expect(tapCount, 1);
      expect(mountCount, 1);
      expect(buildCount, 1);

      await gesture.moveTo(const Offset(2, 2));
      await tester.pumpAndSettle();
      final settledTransform = tester.widget<Transform>(transformFinder);
      expect(settledTransform.transform.isIdentity(), isTrue);
      expect(settledTransform.filterQuality, isNull);
      expect(mountCount, 1);
      expect(buildCount, 1);
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
                child: _MountAndBuildProbe(
                  onInit: () => mountCount++,
                  onBuild: () {},
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
      final activeTransform = tester.widget<Transform>(transformFinder);
      expect(activeTransform.transform.isIdentity(), isFalse);
      expect(activeTransform.filterQuality, FilterQuality.medium);
      expect(mountCount, 1);

      await tester.pumpAndSettle();
      final endTransform = tester.widget<Transform>(transformFinder);
      expect(endTransform.transform.isIdentity(), isTrue);
      expect(endTransform.filterQuality, isNull);
      expect(mountCount, 1);
    },
  );

  testWidgets(
    'Motion3dFloatingLayer animates continuous loop-seamless 3D levitation and disposes cleanly',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Motion3dFloatingLayer(
                forceInTest: true,
                floatAmplitude: 3.0,
                tiltAmplitude: 0.02,
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

  test(
    'PrecomputedRoute3d precomputes smooth filleted arc-length table with normalized tangents',
    () {
      final route = PrecomputedRoute3d.fromWaypoints(const [
        (-640, 260),
        (-430, 80),
        (360, -190),
        (640, 250),
      ]);
      expect(route.totalLength, greaterThan(1200.0));

      final mid = route.sample(0.5, trailWorldLength: 92.0, trailSteps: 8);
      final normSq = mid.tangentX * mid.tangentX + mid.tangentZ * mid.tangentZ;
      expect(normSq, closeTo(1.0, 1e-4));
      expect(mid.trailPoints.length, 9);
    },
  );

  testWidgets(
    'All 26 AI-generated Icon3dStyle assets exist (>100KB) and render in GhstAiIcon & Animated3dIconBadge without pumpAndSettle hang',
    (tester) async {
      expect(Icon3dStyle.values.length, 26);
      for (final style in Icon3dStyle.values) {
        final file = File(style.assetPath);
        expect(file.existsSync(), isTrue, reason: 'Missing ${style.assetPath}');
        expect(
          file.lengthSync(),
          greaterThan(100000),
          reason: 'Asset too small: ${style.assetPath}',
        );
      }
      for (final launcher in const [
        'web/favicon.png',
        'web/icons/Icon-192.png',
        'web/icons/Icon-512.png',
        'web/icons/Icon-maskable-192.png',
        'web/icons/Icon-maskable-512.png',
        'windows/runner/resources/app_icon.ico',
      ]) {
        final f = File(launcher);
        expect(f.existsSync(), isTrue, reason: 'Missing $launcher');
        expect(f.lengthSync(), greaterThan(4000));
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final style in Icon3dStyle.values) ...[
                    GhstAiIcon(
                      style: style,
                      size: 36,
                      selected: true,
                    ),
                    GhstAiIcon(
                      style: style,
                      size: 24,
                      circular: true,
                      dimmed: true,
                    ),
                    Animated3dIconBadge(
                      style: style,
                      size: 48,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GhstAiIcon), findsNWidgets(52));
      expect(find.byType(Animated3dIconBadge), findsNWidgets(26));
      expect(find.byType(Icon), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GhstAiIcon),
          matching: find.byType(RepaintBoundary),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(GhstAiIcon),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Animated3dIconBadge(
                style: Icon3dStyle.scooterExpress,
                size: 38,
                animateIdle: false,
                showRadarPulse: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final badgeTransforms = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(Animated3dIconBadge),
              matching: find.byType(Transform),
            ),
          )
          .toList();
      final mainTransform = badgeTransforms.last;
      expect(mainTransform.transform.isIdentity(), isTrue);
      expect(mainTransform.filterQuality, isNull);
    },
  );

  testWidgets(
    'GhstButtonIcon and ActionIconThemeData render 100% bespoke studio icons with zero stock Icon widgets',
    (tester) async {
      for (final theme in [
        AppTheme.lightTheme,
        AppTheme.darkTheme,
        AdminStudioTheme.themeData(),
        AdminStudioTheme.themeData(brightness: Brightness.dark),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                actions: const [
                  CloseButton(),
                  DrawerButton(),
                  EndDrawerButton(),
                ],
              ),
              body: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in GhstActionKind.values)
                        GhstButtonIcon.glyph(kind, size: 18),
                      const GhstButtonIcon(Icons.send_rounded, size: 18),
                      const GhstButtonIcon.ai(
                        Icon3dStyle.scooterExpress,
                        size: 22,
                      ),
                      GhstButtonIcon.forLabel('Tiếp tục với Google', size: 18),
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: const GhstButtonIcon(Icons.qr_code_2, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Icon), findsNothing);
        expect(
          find.descendant(
            of: find.byType(GhstButtonIcon),
            matching: find.byType(RepaintBoundary),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
