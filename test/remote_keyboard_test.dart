import 'dart:typed_data';

import 'package:doctormobile/pages/tools/remote/desktop/input/keyboard_board.dart';
import 'package:doctormobile/pages/tools/remote/desktop/models/buttons.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _blank() => Uint8List(kRemoteScreenWidth * kRemoteScreenHeight);

void _paint(Uint8List pixels, int x, int y, int w, int h) {
  for (var yy = y; yy < y + h; yy++) {
    for (var xx = x; xx < x + w; xx++) {
      pixels[yy * kRemoteScreenWidth + xx] = 1;
    }
  }
}

Uint8List _keyboard(
  RemoteKeyboardFamily family, {
  int selected = 0,
  Set<int> bare = const {},
}) {
  final pixels = _blank();
  final boxes = keyboardKeyBoxes(family);
  for (var i = 0; i < boxes.length; i++) {
    if (bare.contains(i)) continue;
    final (x, y, w, h) = boxes[i];
    if (i == selected) {
      _paint(pixels, x, y, w, h);
    } else {
      _paint(pixels, x + 1, y + 1, w ~/ 2, (h * 2) ~/ 5);
    }
  }
  return pixels;
}

void main() {
  test('a blank frame is not a keyboard', () {
    expect(detectOnScreenKeyboard(_blank()), isNull);
  });

  test('stock text keyboard reports the filled key', () {
    final board = detectOnScreenKeyboard(
      _keyboard(RemoteKeyboardFamily.stockText),
    );
    expect(board, isNotNull);
    expect(board!.family, RemoteKeyboardFamily.stockText);
    expect(board.row, 0);
    expect(board.column, 0);
    expect(board.uppercaseByDefault, isTrue);
  });

  test('the selected key is the one reported, not the first', () {
    final board = detectOnScreenKeyboard(
      _keyboard(RemoteKeyboardFamily.stockText, selected: 3),
    );
    expect(board, isNotNull);
    expect(board!.row, 0);
    expect(board.column, 3);
  });

  test('one solid box and a little ink is not a keyboard', () {
    final pixels = _blank();
    _paint(pixels, 1, 29, 7, 10);
    for (final (x, y) in const [
      (10, 29),
      (19, 29),
      (28, 29),
      (1, 41),
      (10, 41),
      (1, 53),
      (10, 53),
      (91, 29),
    ]) {
      _paint(pixels, x, y, 2, 2);
    }
    expect(detectOnScreenKeyboard(pixels), isNull);
  });

  test('a keyboard with two solid keys is not a keyboard', () {
    final pixels = _keyboard(RemoteKeyboardFamily.stockText);
    final (x, y, w, h) = keyboardKeyBoxes(RemoteKeyboardFamily.stockText)[5];
    _paint(pixels, x, y, w, h);
    expect(detectOnScreenKeyboard(pixels), isNull);
  });

  test('a large dark picture is not a keyboard', () {
    final pixels = _blank();
    _paint(pixels, 40, 20, 48, 30);
    for (var x = 0; x < kRemoteScreenWidth; x += 3) {
      _paint(pixels, x, 56, 1, 6);
    }
    expect(detectOnScreenKeyboard(pixels), isNull);
  });

  test('stock path from q to w is one step right', () {
    const board = OnScreenKeyboard(
      family: RemoteKeyboardFamily.stockText,
      row: 0,
      column: 0,
      uppercaseByDefault: true,
    );
    final plan = planOnScreenEdit(board, character: 'W');
    expect(plan, isNotNull);
    expect(plan!.steps.map((step) => (step.button, step.long)), [
      (RemoteButton.right, false),
      (RemoteButton.ok, false),
    ]);
    expect(plan.next.column, 1);
  });

  test('an empty stock field uses a long OK for a lowercase letter', () {
    const board = OnScreenKeyboard(
      family: RemoteKeyboardFamily.stockText,
      row: 0,
      column: 0,
      uppercaseByDefault: true,
    );
    final plan = planOnScreenEdit(board, character: 'q');
    expect(plan!.steps.single.long, isTrue);
  });

  test('text backspace is a long back', () {
    const board = OnScreenKeyboard(
      family: RemoteKeyboardFamily.stockText,
      row: 0,
      column: 0,
    );
    final plan = planOnScreenEdit(board, backspace: true);
    expect(plan!.steps.single.button, RemoteButton.back);
    expect(plan.steps.single.long, isTrue);
  });

  test('stock keyboard cannot type a symbol', () {
    const board = OnScreenKeyboard(
      family: RemoteKeyboardFamily.stockText,
      row: 0,
      column: 0,
    );
    expect(planOnScreenEdit(board, character: '!'), isNull);
  });

  test('momentum reaches a symbol by switching pages', () {
    const board = OnScreenKeyboard(
      family: RemoteKeyboardFamily.momentumText,
      row: 0,
      column: 0,
    );
    final plan = planOnScreenEdit(board, character: '!');
    expect(plan, isNotNull);
    expect(plan!.next.page, 1);
    expect(
      plan.steps.where((step) => step.button == RemoteButton.ok).length,
      greaterThan(1),
    );
  });

  test('number keys are not reported as hex', () {
    final board = detectOnScreenKeyboard(
      _keyboard(RemoteKeyboardFamily.number, bare: {11}),
    );
    expect(board, isNotNull);
    expect(board!.family, RemoteKeyboardFamily.number);
    expect(board.row, 0);
    expect(board.column, 0);
  });

  test('hex keyboard is reported as byte input', () {
    final board = detectOnScreenKeyboard(_keyboard(RemoteKeyboardFamily.byte));
    expect(board, isNotNull);
    expect(board!.family, RemoteKeyboardFamily.byte);
  });

  test('number backspace uses the on-screen key', () {
    const board = OnScreenKeyboard(
      family: RemoteKeyboardFamily.number,
      row: 0,
      column: 0,
    );
    final plan = planOnScreenEdit(board, backspace: true);
    expect(plan, isNotNull);
    expect(
      plan!.steps.any((step) => step.button == RemoteButton.back),
      isFalse,
    );
    expect(plan.steps.last.button, RemoteButton.ok);
    expect(plan.steps.last.long, isFalse);
  });
}
