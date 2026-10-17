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

void _speck(Uint8List pixels, int x, int y) {
  _paint(pixels, x, y, 2, 2);
}

void main() {
  test('a blank frame is not a keyboard', () {
    expect(detectOnScreenKeyboard(_blank()), isNull);
  });

  test('stock text keyboard reports the filled key', () {
    final pixels = _blank();
    _paint(pixels, 1, 29, 7, 10);
    for (final origin in const [
      (10, 29),
      (19, 29),
      (28, 29),
      (1, 41),
      (10, 41),
      (1, 53),
      (10, 53),
      (91, 29),
    ]) {
      _speck(pixels, origin.$1, origin.$2);
    }

    final board = detectOnScreenKeyboard(pixels);
    expect(board, isNotNull);
    expect(board!.family, RemoteKeyboardFamily.stockText);
    expect(board.row, 0);
    expect(board.column, 0);
    expect(board.uppercaseByDefault, isTrue);
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
    final pixels = _blank();
    _paint(pixels, 4, 33, 11, 13);
    for (final origin in const [
      (15, 33),
      (26, 33),
      (37, 33),
      (48, 33),
      (4, 47),
      (15, 47),
      (26, 47),
    ]) {
      _paint(pixels, origin.$1, origin.$2, 4, 2);
    }

    final board = detectOnScreenKeyboard(pixels);
    expect(board, isNotNull);
    expect(board!.family, RemoteKeyboardFamily.number);
    expect(board.row, 0);
    expect(board.column, 0);
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
