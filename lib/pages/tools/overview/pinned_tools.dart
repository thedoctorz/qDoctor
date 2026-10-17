import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinnedToolsStore extends ChangeNotifier {
  PinnedToolsStore._() {
    unawaited(_load());
  }

  static final PinnedToolsStore instance = PinnedToolsStore._();

  static const _pref = 'home_pinned_tools';

  List<String> _ids = const [];
  List<String> get ids => _ids;

  bool contains(String id) => _ids.contains(id);

  bool toggle(String id) {
    if (id.isEmpty) return false;
    final next = List<String>.of(_ids);
    final added = !next.remove(id);
    if (added) next.add(id);
    _ids = List.unmodifiable(next);
    notifyListeners();
    unawaited(_save());
    return added;
  }

  void remove(String id) {
    if (!_ids.contains(id)) return;
    _ids = List.unmodifiable(_ids.where((e) => e != id));
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _ids = List.unmodifiable(prefs.getStringList(_pref) ?? const <String>[]);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pref, _ids);
  }
}
