import 'dart:typed_data';

import '../models/buttons.dart';

const int kRemoteScreenWidth = 128;
const int kRemoteScreenHeight = 64;

enum RemoteTextKind { text, byte, number }

enum RemoteKeyboardFamily { stockText, momentumText, byte, number }

class KeyStep {
  const KeyStep(this.button, {this.long = false});

  final RemoteButton button;
  final bool long;
}

class KeyPlan {
  const KeyPlan(this.steps, this.next);

  final List<KeyStep> steps;
  final OnScreenKeyboard next;
}

class OnScreenKeyboard {
  const OnScreenKeyboard({
    required this.family,
    required this.row,
    required this.column,
    this.page = 0,
    this.uppercaseByDefault = false,
  });

  final RemoteKeyboardFamily family;
  final int row;
  final int column;
  final int page;
  final bool uppercaseByDefault;

  RemoteTextKind get kind => switch (family) {
    RemoteKeyboardFamily.stockText ||
    RemoteKeyboardFamily.momentumText => RemoteTextKind.text,
    RemoteKeyboardFamily.byte => RemoteTextKind.byte,
    RemoteKeyboardFamily.number => RemoteTextKind.number,
  };

  OnScreenKeyboard copyWith({
    int? row,
    int? column,
    int? page,
    bool? uppercaseByDefault,
  }) {
    return OnScreenKeyboard(
      family: family,
      row: row ?? this.row,
      column: column ?? this.column,
      page: page ?? this.page,
      uppercaseByDefault: uppercaseByDefault ?? this.uppercaseByDefault,
    );
  }
}

class _Cell {
  const _Cell(this.symbol, this.boxX, this.boxY, this.boxW, this.boxH);

  final String symbol;
  final int boxX;
  final int boxY;
  final int boxW;
  final int boxH;

  bool get isLetter =>
      symbol != '\r' && symbol != '\b' && symbol != '\t' && symbol != '-';
}

int _pixel(Uint8List pixels, int x, int y) {
  if (x < 0 || y < 0 || x >= kRemoteScreenWidth || y >= kRemoteScreenHeight) {
    return 0;
  }
  return pixels[y * kRemoteScreenWidth + x];
}

double _fill(Uint8List pixels, int x, int y, int w, int h) {
  var ink = 0;
  var count = 0;
  for (var yy = y; yy < y + h; yy++) {
    for (var xx = x; xx < x + w; xx++) {
      count++;
      ink += _pixel(pixels, xx, yy);
    }
  }
  if (count == 0) return 0;
  return ink / count;
}

_Cell _letter(String symbol, int keyX, int keyY, {required bool momentum}) {
  if (momentum) {
    return _Cell(symbol, 1 + keyX - 2, 29 + keyY - 9, 9, 11);
  }
  return _Cell(symbol, keyX, 29 + keyY - 8, 7, 10);
}

_Cell _icon(String symbol, int x, int y, int w, int h) {
  return _Cell(symbol, x, y, w, h);
}

List<List<_Cell>> _stockTextRows() {
  _Cell letter(String symbol, int keyX, int keyY) =>
      _letter(symbol, keyX, keyY, momentum: false);
  return [
    [
      letter('q', 1, 8),
      letter('w', 10, 8),
      letter('e', 19, 8),
      letter('r', 28, 8),
      letter('t', 37, 8),
      letter('y', 46, 8),
      letter('u', 55, 8),
      letter('i', 64, 8),
      letter('o', 73, 8),
      letter('p', 82, 8),
      letter('0', 91, 8),
      letter('1', 100, 8),
      letter('2', 110, 8),
      letter('3', 120, 8),
    ],
    [
      letter('a', 1, 20),
      letter('s', 10, 20),
      letter('d', 19, 20),
      letter('f', 28, 20),
      letter('g', 37, 20),
      letter('h', 46, 20),
      letter('j', 55, 20),
      letter('k', 64, 20),
      letter('l', 73, 20),
      _icon('\b', 83, 41, 16, 9),
      letter('4', 100, 20),
      letter('5', 110, 20),
      letter('6', 120, 20),
    ],
    [
      letter('z', 1, 32),
      letter('x', 10, 32),
      letter('c', 19, 32),
      letter('v', 28, 32),
      letter('b', 37, 32),
      letter('n', 46, 32),
      letter('m', 55, 32),
      letter('_', 64, 32),
      _icon('\r', 75, 52, 24, 11),
      letter('7', 100, 32),
      letter('8', 110, 32),
      letter('9', 120, 32),
    ],
  ];
}

List<List<_Cell>> _momentumAlphaRows() {
  _Cell letter(String symbol, int keyX, int keyY) =>
      _letter(symbol, keyX, keyY, momentum: true);
  return [
    [
      letter('q', 1, 8),
      letter('w', 10, 8),
      letter('e', 19, 8),
      letter('r', 28, 8),
      letter('t', 37, 8),
      letter('y', 46, 8),
      letter('u', 55, 8),
      letter('i', 64, 8),
      letter('o', 73, 8),
      letter('p', 82, 8),
      letter('0', 92, 8),
      letter('1', 102, 8),
      letter('2', 111, 8),
      letter('3', 120, 8),
    ],
    [
      letter('a', 1, 20),
      letter('s', 10, 20),
      letter('d', 19, 20),
      letter('f', 28, 20),
      letter('g', 37, 20),
      letter('h', 46, 20),
      letter('j', 55, 20),
      letter('k', 64, 20),
      letter('l', 73, 20),
      _icon('\b', 83, 40, 17, 11),
      letter('4', 102, 20),
      letter('5', 111, 20),
      letter('6', 120, 20),
    ],
    [
      _icon('\t', 1, 52, 10, 11),
      letter('z', 13, 32),
      letter('x', 21, 32),
      letter('c', 29, 32),
      letter('v', 37, 32),
      letter('b', 45, 32),
      letter('n', 53, 32),
      letter('m', 61, 32),
      letter('_', 69, 32),
      _icon('\r', 78, 52, 22, 11),
      letter('7', 102, 32),
      letter('8', 111, 32),
      letter('9', 120, 32),
    ],
  ];
}

List<List<_Cell>> _momentumSymbolRows() {
  _Cell letter(String symbol, int keyX, int keyY) =>
      _letter(symbol, keyX, keyY, momentum: true);
  return [
    [
      letter('!', 2, 8),
      letter('@', 12, 8),
      letter('#', 22, 8),
      letter('\$', 32, 8),
      letter('%', 42, 8),
      letter('^', 52, 8),
      letter('&', 62, 8),
      letter('(', 71, 8),
      letter(')', 81, 8),
      letter('0', 92, 8),
      letter('1', 102, 8),
      letter('2', 111, 8),
      letter('3', 120, 8),
    ],
    [
      letter('~', 2, 20),
      letter('+', 12, 20),
      letter('-', 22, 20),
      letter('=', 32, 20),
      letter('[', 42, 20),
      letter(']', 52, 20),
      letter('{', 62, 20),
      letter('}', 72, 20),
      _icon('\b', 83, 40, 17, 11),
      letter('4', 102, 20),
      letter('5', 111, 20),
      letter('6', 120, 20),
    ],
    [
      _icon('\t', 1, 52, 10, 11),
      letter('.', 15, 32),
      letter(',', 29, 32),
      letter(';', 41, 32),
      letter('`', 53, 32),
      letter("'", 65, 32),
      _icon('\r', 78, 52, 22, 11),
      letter('7', 102, 32),
      letter('8', 111, 32),
      letter('9', 120, 32),
    ],
  ];
}

_Cell _nibble(String symbol, int keyX, int keyY) {
  return _Cell(symbol, 7 + keyX - 3, 31 + keyY - 10, 11, 13);
}

List<List<_Cell>> _byteRows() {
  return [
    [
      _nibble('0', 0, 12),
      _nibble('1', 11, 12),
      _nibble('2', 22, 12),
      _nibble('3', 33, 12),
      _nibble('4', 44, 12),
      _nibble('5', 55, 12),
      _nibble('6', 66, 12),
      _nibble('7', 77, 12),
      _icon('\b', 110, 35, 16, 9),
    ],
    [
      _nibble('8', 0, 26),
      _nibble('9', 11, 26),
      _nibble('A', 22, 26),
      _nibble('B', 33, 26),
      _nibble('C', 44, 26),
      _nibble('D', 55, 26),
      _nibble('E', 66, 26),
      _nibble('F', 77, 26),
      _icon('\r', 102, 48, 24, 11),
    ],
  ];
}

List<List<_Cell>> _numberRows() {
  return [
    [
      _nibble('0', 0, 12),
      _nibble('1', 11, 12),
      _nibble('2', 22, 12),
      _nibble('3', 33, 12),
      _nibble('4', 44, 12),
      _icon('\b', 110, 35, 16, 9),
    ],
    [
      _nibble('5', 0, 26),
      _nibble('6', 11, 26),
      _nibble('7', 22, 26),
      _nibble('8', 33, 26),
      _nibble('9', 44, 26),
      _icon('-', 62, 48, 21, 11),
      _icon('\r', 102, 48, 24, 11),
    ],
  ];
}

class _Layout {
  const _Layout(this.family, this.pages);

  final RemoteKeyboardFamily family;
  final List<List<List<_Cell>>> pages;
}

class _Cursor {
  _Cursor(this.row, this.column, this.page);
  int row;
  int column;
  int page;

  _Cursor copy() => _Cursor(row, column, page);
}

List<List<_Cell>> _page(_Layout layout, int page) => layout.pages[page];

_Cell _cell(_Layout layout, _Cursor cursor) =>
    _page(layout, cursor.page)[cursor.row][cursor.column];

void _wrapHorizontal(_Layout layout, _Cursor cursor, int delta) {
  final row = _page(layout, cursor.page)[cursor.row];
  final next = cursor.column + delta;
  if (next < 0) {
    cursor.column = row.length - 1;
  } else if (next >= row.length) {
    cursor.column = 0;
  } else {
    cursor.column = next;
  }
}

void _moveStock(_Cursor cursor, RemoteButton button) {
  const sizes = [14, 13, 12];
  switch (button) {
    case RemoteButton.up:
      if (cursor.row > 0) {
        cursor.row--;
        if (cursor.column > sizes[cursor.row] - 6) cursor.column++;
      }
    case RemoteButton.down:
      if (cursor.row < 2) {
        cursor.row++;
        if (cursor.column > sizes[cursor.row] - 4) cursor.column--;
      }
    case RemoteButton.left:
      _wrapHorizontal(_stockLayout, cursor, -1);
    case RemoteButton.right:
      _wrapHorizontal(_stockLayout, cursor, 1);
    case RemoteButton.ok:
    case RemoteButton.back:
      break;
  }
}

void _moveMomentum(_Cursor cursor, RemoteButton button) {
  final sizes = cursor.page == 0 ? const [14, 13, 13] : const [14, 13, 10];
  switch (button) {
    case RemoteButton.up:
      if (cursor.row <= 0) return;
      cursor.row--;
      if (cursor.row == 0 && cursor.column > sizes[cursor.row] - 6) {
        cursor.column++;
      }
      if (cursor.row == 1 && cursor.page == 1) {
        if (cursor.column > 5) {
          cursor.column += 2;
        } else if (cursor.column > 1) {
          cursor.column++;
        }
      }
    case RemoteButton.down:
      if (cursor.row >= 2) return;
      cursor.row++;
      if (cursor.row == 1 && cursor.column > sizes[cursor.row] - 4) {
        cursor.column--;
      }
      if (cursor.row == 2 && cursor.page == 1) {
        if (cursor.column > 6) {
          cursor.column -= 2;
        } else if (cursor.column > 1) {
          cursor.column--;
        }
      }
    case RemoteButton.left:
      _wrapHorizontal(_momentumLayout, cursor, -1);
    case RemoteButton.right:
      _wrapHorizontal(_momentumLayout, cursor, 1);
    case RemoteButton.ok:
    case RemoteButton.back:
      break;
  }
}

void _moveGrid(_Layout layout, _Cursor cursor, RemoteButton button) {
  final rows = _page(layout, cursor.page);
  switch (button) {
    case RemoteButton.up:
      if (cursor.row > 0) {
        cursor.row--;
        final width = rows[cursor.row].length;
        if (cursor.column >= width) cursor.column = width - 1;
      }
    case RemoteButton.down:
      if (cursor.row < rows.length - 1) {
        final nextWidth = rows[cursor.row + 1].length;
        if (cursor.column >= rows[cursor.row].length - 1 &&
            cursor.column >= nextWidth) {
          cursor.column = nextWidth - 1;
        }
        cursor.row++;
        if (cursor.column >= rows[cursor.row].length) {
          cursor.column = rows[cursor.row].length - 1;
        }
      }
    case RemoteButton.left:
      _wrapHorizontal(layout, cursor, -1);
    case RemoteButton.right:
      _wrapHorizontal(layout, cursor, 1);
    case RemoteButton.ok:
    case RemoteButton.back:
      break;
  }
}

final _Layout _stockLayout = _Layout(RemoteKeyboardFamily.stockText, [
  _stockTextRows(),
]);

final _Layout _momentumLayout = _Layout(RemoteKeyboardFamily.momentumText, [
  _momentumAlphaRows(),
  _momentumSymbolRows(),
]);

final _Layout _byteLayout = _Layout(RemoteKeyboardFamily.byte, [_byteRows()]);

final _Layout _numberLayout = _Layout(RemoteKeyboardFamily.number, [
  _numberRows(),
]);

void _applyMove(_Layout layout, _Cursor cursor, RemoteButton button) {
  switch (layout.family) {
    case RemoteKeyboardFamily.stockText:
      _moveStock(cursor, button);
    case RemoteKeyboardFamily.momentumText:
      _moveMomentum(cursor, button);
    case RemoteKeyboardFamily.byte:
    case RemoteKeyboardFamily.number:
      _moveGrid(layout, cursor, button);
  }
}

final List<_Layout> _layouts = [
  _stockLayout,
  _momentumLayout,
  _byteLayout,
  _numberLayout,
];

class _Hit {
  _Hit(this.layout, this.page, this.row, this.column, this.fill, this.present);
  final _Layout layout;
  final int page;
  final int row;
  final int column;
  final double fill;
  final int present;
}

_Hit? _score(Uint8List pixels, _Layout layout) {
  var bestFill = 0.0;
  var bestPage = 0;
  var bestRow = 0;
  var bestColumn = 0;
  var present = 0;
  var sawSelection = false;
  for (var page = 0; page < layout.pages.length; page++) {
    final rows = layout.pages[page];
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        final cell = rows[row][column];
        final fill = _fill(pixels, cell.boxX, cell.boxY, cell.boxW, cell.boxH);
        final selected = cell.isLetter ? fill >= 0.75 : fill >= 0.55;
        if (selected && fill >= bestFill) {
          sawSelection = true;
          bestFill = fill;
          bestPage = page;
          bestRow = row;
          bestColumn = column;
        } else if (fill >= 0.04 && fill < 0.65) {
          present++;
        }
      }
    }
  }
  if (!sawSelection || present < 6) return null;
  return _Hit(layout, bestPage, bestRow, bestColumn, bestFill, present);
}

bool _byteOnlyInk(Uint8List pixels) {
  final rows = _byteRows();
  const spots = [(0, 5), (0, 6), (0, 7), (1, 6), (1, 7)];
  for (final (row, column) in spots) {
    final cell = rows[row][column];
    if (_fill(pixels, cell.boxX, cell.boxY, cell.boxW, cell.boxH) >= 0.04) {
      return true;
    }
  }
  return false;
}

bool _textFieldWantsUppercase(Uint8List pixels) {
  const x0 = 4;
  const y0 = 14;
  const w = 118;
  const h = 11;
  final ratio = _fill(pixels, x0, y0, w, h);
  final ink = (ratio * w * h).round();
  return ink < 20 || ratio > 0.4;
}

OnScreenKeyboard? detectOnScreenKeyboard(Uint8List pixels) {
  if (pixels.length < kRemoteScreenWidth * kRemoteScreenHeight) return null;
  _Hit? best;
  for (final layout in _layouts) {
    final hit = _score(pixels, layout);
    if (hit == null) continue;
    if (best == null ||
        hit.present > best.present ||
        (hit.present == best.present && hit.fill > best.fill)) {
      best = hit;
    }
  }
  if (best == null) return null;
  if (best.layout.family == RemoteKeyboardFamily.byte &&
      !_byteOnlyInk(pixels)) {
    final number = _score(pixels, _numberLayout);
    if (number != null) best = number;
  }
  final text =
      best.layout.family == RemoteKeyboardFamily.stockText ||
      best.layout.family == RemoteKeyboardFamily.momentumText;
  return OnScreenKeyboard(
    family: best.layout.family,
    row: best.row,
    column: best.column,
    page: best.page,
    uppercaseByDefault: text && _textFieldWantsUppercase(pixels),
  );
}

_Layout _layoutFor(RemoteKeyboardFamily family) {
  return _layouts.firstWhere((layout) => layout.family == family);
}

String _wantedSymbol(String character) {
  if (character == ' ') return '_';
  final lower = character.toLowerCase();
  if (lower != character && lower.codeUnitAt(0) >= 0x61) return lower;
  return character;
}

bool _needsLongOk(OnScreenKeyboard board, String character) {
  if (board.kind != RemoteTextKind.text) return false;
  final upper = character.toUpperCase();
  final isLetter = character.toLowerCase() != character || upper != character;
  if (character == ' ') return !board.uppercaseByDefault;
  if (!isLetter) return false;
  final wantUpper = character == upper;
  return wantUpper != board.uppercaseByDefault;
}

(int, int, int)? _findSymbol(
  _Layout layout,
  OnScreenKeyboard board,
  String symbol,
) {
  (int, int, int)? fallback;
  for (var page = 0; page < layout.pages.length; page++) {
    final rows = layout.pages[page];
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        if (rows[row][column].symbol != symbol) continue;
        if (page == board.page) return (page, row, column);
        fallback ??= (page, row, column);
      }
    }
  }
  return fallback;
}

List<KeyStep>? _pathTo(
  _Layout layout,
  OnScreenKeyboard board,
  int page,
  int row,
  int column,
) {
  final start = _Cursor(board.row, board.column, board.page);
  if (start.row == row && start.column == column && start.page == page) {
    return const [];
  }
  final seen = <String>{'${start.page}:${start.row}:${start.column}'};
  final queue = <(_Cursor, List<KeyStep>)>[(start, const [])];
  const arrows = [
    RemoteButton.up,
    RemoteButton.down,
    RemoteButton.left,
    RemoteButton.right,
  ];
  while (queue.isNotEmpty) {
    final (cursor, steps) = queue.removeAt(0);
    if (steps.length > 24) continue;
    for (final button in arrows) {
      final next = cursor.copy();
      _applyMove(layout, next, button);
      final key = '${next.page}:${next.row}:${next.column}';
      if (!seen.add(key)) continue;
      final path = [...steps, KeyStep(button)];
      if (next.row == row && next.column == column && next.page == page) {
        return path;
      }
      queue.add((next, path));
    }
    if (_cell(layout, cursor).symbol == '\t') {
      final next = cursor.copy()..page = cursor.page == 0 ? 1 : 0;
      final key = '${next.page}:${next.row}:${next.column}';
      if (seen.add(key)) {
        final path = [...steps, const KeyStep(RemoteButton.ok)];
        if (next.row == row && next.column == column && next.page == page) {
          return path;
        }
        queue.add((next, path));
      }
    }
  }
  return null;
}

KeyPlan? planOnScreenEdit(
  OnScreenKeyboard board, {
  String? character,
  bool backspace = false,
  bool submit = false,
}) {
  final layout = _layoutFor(board.family);
  if (backspace && board.kind == RemoteTextKind.text) {
    return KeyPlan(const [KeyStep(RemoteButton.back, long: true)], board);
  }
  final symbol = submit
      ? '\r'
      : backspace
      ? '\b'
      : character == null
      ? null
      : _wantedSymbol(character);
  if (symbol == null) return null;
  final target = _findSymbol(layout, board, symbol);
  if (target == null) return null;
  final (page, row, column) = target;
  final path = _pathTo(layout, board, page, row, column);
  if (path == null) return null;
  final long = character != null && _needsLongOk(board, character);
  final steps = [...path, KeyStep(RemoteButton.ok, long: long)];
  final next = board.copyWith(
    row: row,
    column: column,
    page: page,
    uppercaseByDefault: character == null ? null : false,
  );
  return KeyPlan(steps, next);
}
