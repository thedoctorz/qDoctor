import 'dart:async';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doctormobile/pages/tools/remote/desktop/input/keyboard_board.dart';
import 'package:doctormobile/pages/tools/remote/desktop/input/phone_field.dart';
import 'package:doctormobile/pages/tools/remote/desktop/page.dart';
import 'package:doctormobile/pages/tools/remote/desktop/widgets/controls.dart';
import 'package:doctormobile/services/localization/gen/l10n_generated.dart';
import 'package:doctormobile/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeClient implements FlipperClient {
  final broadcast = StreamController<Main>.broadcast();
  final connection = StreamController<FlipperConnectionState>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<Main> get broadcastStream => broadcast.stream;

  @override
  Stream<Main> get notificationStream => broadcast.stream;

  @override
  Stream<FlipperConnectionState> get connectionStream => connection.stream;

  @override
  Future<List<Main>> callRpcFrames(
    Main request, {
    Duration timeout = const Duration(seconds: 8),
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    void Function(Main frame)? onFrame,
    void Function()? onSent,
    bool retainFrames = true,
    bool interleavable = false,
    bool pipelined = true,
  }) async {
    onSent?.call();
    return const <Main>[];
  }

  @override
  Future<void> sendRpc(
    Main message, {
    FlipperRequestPriority priority = FlipperRequestPriority.unattended,
    Duration sendTimeout = const Duration(seconds: 30),
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<int> _keyboardFrame() {
  final pixels = Uint8List(kRemoteScreenWidth * kRemoteScreenHeight);
  void paint(int x, int y, int w, int h) {
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        pixels[yy * kRemoteScreenWidth + xx] = 1;
      }
    }
  }

  final boxes = keyboardKeyBoxes(RemoteKeyboardFamily.stockText);
  for (var i = 0; i < boxes.length; i++) {
    final (x, y, w, h) = boxes[i];
    if (i == 0) {
      paint(x, y, w, h);
    } else {
      paint(x + 1, y + 1, w ~/ 2, (h * 2) ~/ 5);
    }
  }
  final packed = Uint8List(kRemoteScreenWidth * kRemoteScreenHeight ~/ 8);
  for (var y = 0; y < kRemoteScreenHeight; y++) {
    for (var x = 0; x < kRemoteScreenWidth; x++) {
      if (pixels[y * kRemoteScreenWidth + x] == 0) continue;
      packed[(y ~/ 8) * kRemoteScreenWidth + x] |= 1 << (y & 7);
    }
  }
  return packed;
}

Widget _wrap(Widget child) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: child,
);

void main() {
  late _FakeClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    client = _FakeClient();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(RemoteControlPage(client: client, mediaRemoteSupported: false)),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  Future<void> push(WidgetTester tester, Main message) async {
    client.broadcast.add(message);
    await tester.pump();
  }

  Future<void> lock(WidgetTester tester, bool locked) =>
      push(tester, Main(desktopStatus: Status(locked: locked)));

  Future<void> showKeyboard(WidgetTester tester) =>
      push(tester, Main(guiScreenFrame: ScreenFrame(data: _keyboardFrame())));

  Future<void> focus(WidgetTester tester, InputFocusKind kind) =>
      push(tester, Main(guiInputFocus: InputFocus(kind: kind)));

  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 2));

  bool fieldFocused(WidgetTester tester) {
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    return editable.focusNode.hasFocus;
  }

  testWidgets('a keyboard picture on a locked Flipper opens nothing', (
    tester,
  ) async {
    await open(tester);
    await lock(tester, true);
    await settle(tester);
    await showKeyboard(tester);
    await settle(tester);

    expect(find.byType(PhoneKeyboardField), findsNothing);
  });

  testWidgets('a keyboard picture right after opening waits for firmware', (
    tester,
  ) async {
    await open(tester);
    await lock(tester, false);
    await showKeyboard(tester);
    // Past the settle but inside the grace: firmware that reports focus has
    // not been heard from yet, so the picture is not acted on.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PhoneKeyboardField), findsNothing);

    await focus(tester, InputFocusKind.NONE);
    await settle(tester);
    expect(
      find.byType(PhoneKeyboardField),
      findsNothing,
      reason: 'the firmware said nothing is focused, and it is the authority',
    );
  });

  testWidgets(
    'a keyboard picture shows the field without raising the keyboard',
    (tester) async {
      await open(tester);
      await lock(tester, false);
      await settle(tester);
      await showKeyboard(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byType(PhoneKeyboardField),
        findsNothing,
        reason: 'one frame is not yet a text field',
      );

      await settle(tester);
      expect(find.byType(PhoneKeyboardField), findsOneWidget);
      expect(fieldFocused(tester), isFalse);
    },
  );

  testWidgets('firmware focus opens and closes the phone keyboard', (
    tester,
  ) async {
    await open(tester);
    await focus(tester, InputFocusKind.NONE);
    await settle(tester);
    expect(find.byType(PhoneKeyboardField), findsNothing);

    await focus(tester, InputFocusKind.TEXT);
    await tester.pump();
    await tester.pump();
    expect(find.byType(PhoneKeyboardField), findsOneWidget);
    expect(fieldFocused(tester), isTrue);

    await tester.tap(find.byIcon(Icons.keyboard_hide_outlined));
    await tester.pump();
    expect(fieldFocused(tester), isFalse);

    await focus(tester, InputFocusKind.NONE);
    expect(find.byType(PhoneKeyboardField), findsNothing);
  });

  testWidgets('typing with the system keyboard up leaves out the controls', (
    tester,
  ) async {
    await open(tester);
    await focus(tester, InputFocusKind.TEXT);
    await tester.pump();
    await tester.pump();
    expect(find.byType(RemoteControls), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(RemoteControls), findsNothing);
    expect(find.byType(PhoneKeyboardField), findsOneWidget);

    tester.view.resetViewInsets();
    await tester.pump();
    expect(find.byType(RemoteControls), findsOneWidget);
  });
}
